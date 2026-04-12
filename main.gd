# main.gd — 启动场景主脚本
# 职责: 设置透明窗口、创建屏幕边界墙、实例化宠物、管理鼠标穿透区域
extends Node2D

# ── 窗口交互模式 ──
enum WindowMode { FREE, CONFINED, REPELLED }

var pet_scene := preload("res://entities/pet/pet.tscn")
var pet_instance: RigidBody2D
var screen_rect: Rect2i
var boundary_size: Vector2  # 实际使用的边界尺寸 (视口坐标系)
var is_dragging := false
var is_menu_open := false

# -- 双端架构 C# 桥接池 --
var win_manager: Node
var ghost_walls: Array[StaticBody2D] = []

# ── 窗口交互模式状态 ──
var window_mode: int = WindowMode.FREE
var confined_window_rect: Rect2 = Rect2()  # 封闭模式的合并后封闭区域 (本地坐标系)
var confined_anchor_rect: Rect2 = Rect2()  # 封闭模式的原始目标窗口 (用于跨帧匹配)
var confined_wall: StaticBody2D = null  # 封闭模式专用四面墙
var void_fillers: Array[StaticBody2D] = []  # 封闭模式虚空填充墙池

func _ready() -> void:
	# ── 性能调频 ──
	Engine.max_fps = 120
	Engine.physics_ticks_per_second = 120
	
	# ── C# 底层桥接 (先加载，用于提权) ──
	if ResourceLoader.exists("res://interop/WindowsManager.cs"):
		win_manager = load("res://interop/WindowsManager.cs").new()
		add_child(win_manager)
		if win_manager.has_method("BoostProcessPriority"):
			win_manager.call("BoostProcessPriority")
	
	# 双保险：设置窗口前先隐藏，防止任务栏闪烁
	get_window().visible = false
	
	_setup_window()
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 窗口完全就绪后推 ToolWindow 标记，再恢复可见
	if win_manager and win_manager.has_method("HideFromTaskbar"):
		win_manager.call("HideFromTaskbar")
	get_window().visible = true
	
	_create_boundaries()
	_spawn_pet()
	
	# 启动幽灵墙同步雷达
	if win_manager:
		var sync_timer = Timer.new()
		sync_timer.wait_time = 0.1
		sync_timer.autostart = true
		sync_timer.timeout.connect(_sync_ghost_walls)
		add_child(sync_timer)
		print("[DesktopPet] 幽灵侦测雷达已启动")
	
	EventBus.drag_started.connect(_on_drag_started)
	EventBus.drag_ended.connect(_on_drag_ended)
	EventBus.context_menu_toggled.connect(_on_context_menu_toggled)
	EventBus.window_mode_changed.connect(_on_window_mode_changed)
	
	# 从持久化恢复窗口交互模式
	window_mode = SettingsManager.get_int("window_mode", WindowMode.FREE)
	
	# 挂载提醒系统
	_setup_reminder_system()
	
	_setup_system_tray()

func _setup_system_tray() -> void:
	# Godot 4 高级特性兼容检测：如果带有内置系统托盘功能则启用
	if ClassDB.class_exists("StatusIndicator"):
		var tray = ClassDB.instantiate("StatusIndicator")
		
		# 利用运行时生成一个神级单眼光晕图标，防止因为没有放图标文件导致隐形！
		if ResourceLoader.exists("res://icon.png"):
			tray.icon = load("res://icon.png")
		elif ResourceLoader.exists("res://icon.svg"):
			tray.icon = load("res://icon.svg")
		else:
			var grad = Gradient.new()
			grad.colors = PackedColorArray([Color("00ffff"), Color("001133"), Color.TRANSPARENT])
			grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			var tex = GradientTexture2D.new()
			tex.gradient = grad
			tex.width = 64
			tex.height = 64
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.5)
			tex.fill_to = Vector2(0.5, 0.0)
			tray.icon = tex
			
		tray.tooltip = "高能机械桌面单眼"
		
		# 挂载专属托盘温馨右键菜单
		var tray_menu = PopupMenu.new()
		tray_menu.add_item("抚摸并让它睡觉 (休眠退出)", 1)
		tray_menu.id_pressed.connect(func(id: int):
			if id == 1:
				get_tree().quit()
		)
		add_child(tray_menu)
		
		# 必须先将 tray 加入场景树，再设置 menu 路径 (否则 get_path 会因为不在树中报错)
		add_child(tray)
		tray.menu = tray_menu.get_path()
		print("[DesktopPet] 系统托盘托管成功启动！")

# ── 窗口设置 ──

func _setup_window() -> void:
	screen_rect = DisplayServer.screen_get_usable_rect()
	
	var window := get_window()
	window.position = Vector2i(screen_rect.position)
	window.size = Vector2i(screen_rect.size)
	window.transparent = true
	window.borderless = true
	window.always_on_top = true
	window.gui_embed_subwindows = false
	
	get_viewport().transparent_bg = true
	
	print("[DesktopPet] 屏幕可用区域: ", screen_rect)
	print("[DesktopPet] 窗口大小: ", window.size)

# ── 屏幕边界 ──

func _create_boundaries() -> void:
	# 关键修复: 使用视口的实际尺寸，而不是屏幕尺寸
	# 这样即使 Windows 有 125%/150% 缩放也不会坐标错位
	var vp_size := get_viewport_rect().size
	boundary_size = vp_size
	
	var w := vp_size.x
	var h := vp_size.y
	var thickness := 400.0
	
	print("[DesktopPet] 视口尺寸: ", vp_size, " (以此创建边界)")
	
	# 地面 — 表面在 y = h (视口底部)
	_add_wall(
		Vector2(w / 2.0, h + thickness / 2.0),
		Vector2(w * 2, thickness)
	)
	# 天花板 — 表面在 y = 0
	_add_wall(
		Vector2(w / 2.0, -thickness / 2.0),
		Vector2(w * 2, thickness)
	)
	# 左墙 — 表面在 x = 0
	_add_wall(
		Vector2(-thickness / 2.0, h / 2.0),
		Vector2(thickness, h * 2)
	)
	# 右墙 — 表面在 x = w (视口右侧)
	_add_wall(
		Vector2(w + thickness / 2.0, h / 2.0),
		Vector2(thickness, h * 2)
	)
	
	print("[DesktopPet] 边界墙已创建 — 地面y=", h, " 右墙x=", w)

func _add_wall(pos: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = pos
	
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.3
	wall.physics_material_override = mat
	
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	
	wall.add_child(collision)
	add_child(wall)

# ── 幽灵系统架构 (Win32 API Mapper) ──

# 每条踏板最多拆分为 3 个物理分段 (应对多窗口交叠场景)
const MAX_PLATFORM_SEGMENTS := 3
# 宽度不足此像素的碎片分段直接丢弃 (宠物站不稳)
const MIN_SEGMENT_WIDTH := 30.0
# 四面墙模式下每个窗口需要的碰撞子节点数:
# 顶部 3 分段 + 底部 3 分段 + 左墙 1 + 右墙 1 = 8
const CHILDREN_PER_WALL := MAX_PLATFORM_SEGMENTS * 2 + 2

func _sync_ghost_walls() -> void:
	if not is_instance_valid(win_manager): return
	
	# 从 C# 层获取 Z-Order 从高→低排列的桌面窗口矩形
	var rects: Array = win_manager.call("GetVisibleWindowRects")
	var count = rects.size()
	
	# 动态伸缩对象池
	while ghost_walls.size() < count:
		var wall = StaticBody2D.new()
		for k in range(CHILDREN_PER_WALL):
			var col = CollisionShape2D.new()
			col.shape = RectangleShape2D.new()
			col.disabled = true
			wall.add_child(col)
		var mat = PhysicsMaterial.new()
		mat.bounce = 0.2
		mat.friction = 0.8
		wall.physics_material_override = mat
		add_child(wall)
		ghost_walls.append(wall)
		
	while ghost_walls.size() > count:
		var wall = ghost_walls.pop_back()
		wall.queue_free()
	
	# rect 转本地坐标缓存
	var local_rects: Array[Rect2] = []
	for i in range(count):
		var desk_rect = rects[i] as Rect2i
		var lx = float(desk_rect.position.x - screen_rect.position.x)
		var ly = float(desk_rect.position.y - screen_rect.position.y)
		local_rects.append(Rect2(lx, ly, float(desk_rect.size.x), float(desk_rect.size.y)))
	
	# 根据当前模式分派处理
	match window_mode:
		WindowMode.FREE:
			_apply_free_mode(local_rects, count)
			_hide_confined_wall()
			_clear_void_fillers()
		WindowMode.CONFINED:
			_apply_confined_mode(local_rects, count)
		WindowMode.REPELLED:
			_apply_repelled_mode(local_rects, count)
			_hide_confined_wall()
			_clear_void_fillers()

## ── FREE 模式: 只生成顶/底单向踏板 (原有逻辑) ──

func _apply_free_mode(local_rects: Array[Rect2], count: int) -> void:
	var floor_thickness = 10.0
	for i in range(count):
		var lr = local_rects[i]
		var wall = ghost_walls[i]
		
		# 确保子节点数量正确
		_ensure_children(wall)
		
		wall.position = lr.position + lr.size / 2.0
		
		# 分段裁剪算法
		var win_left = lr.position.x
		var win_right = lr.position.x + lr.size.x
		var top_y = lr.position.y
		var bottom_y = lr.position.y + lr.size.y
		
		var top_segs = _compute_exposed_segments(win_left, win_right, top_y, local_rects, i)
		var bottom_segs = _compute_exposed_segments(win_left, win_right, bottom_y, local_rects, i)
		
		var wall_cx = lr.position.x + lr.size.x / 2.0
		var top_rel_y = -lr.size.y / 2.0 + floor_thickness / 2.0
		var bot_rel_y = lr.size.y / 2.0 - floor_thickness / 2.0
		_apply_platform_segments(wall, 0, top_segs, wall_cx, top_rel_y, floor_thickness, true)
		_apply_platform_segments(wall, MAX_PLATFORM_SEGMENTS, bottom_segs, wall_cx, bot_rel_y, floor_thickness, true)
		
		# 禁用左右侧墙
		_disable_side_walls(wall)

## ── REPELLED 模式: 顶部保留踏板 + 左右底部实体墙阻止进入 ──

func _apply_repelled_mode(local_rects: Array[Rect2], count: int) -> void:
	var floor_thickness = 10.0
	for i in range(count):
		var lr = local_rects[i]
		var wall = ghost_walls[i]
		
		_ensure_children(wall)
		wall.position = lr.position + lr.size / 2.0
		
		# 最大化窗口: 禁用所有碰撞体 (避免全屏墙封锁宠物)
		if _is_maximized_window(lr):
			for k in range(wall.get_child_count()):
				(wall.get_child(k) as CollisionShape2D).disabled = true
			continue
		
		var win_left = lr.position.x
		var win_right = lr.position.x + lr.size.x
		var top_y = lr.position.y
		var bottom_y = lr.position.y + lr.size.y
		
		# 顶部保留单向踏板 (可以站在上面，从内部可以跳出)
		var top_segs = _compute_exposed_segments(win_left, win_right, top_y, local_rects, i)
		var wall_cx = lr.position.x + lr.size.x / 2.0
		var top_rel_y = -lr.size.y / 2.0 + floor_thickness / 2.0
		_apply_platform_segments(wall, 0, top_segs, wall_cx, top_rel_y, floor_thickness, true)
		
		# 底部单向墙 (rotation=π, 法线朝下: 外面进不来，里面可以掉出)
		var bottom_segs = _compute_exposed_segments(win_left, win_right, bottom_y, local_rects, i)
		var bot_rel_y = lr.size.y / 2.0 - floor_thickness / 2.0
		_apply_platform_segments(wall, MAX_PLATFORM_SEGMENTS, bottom_segs, wall_cx, bot_rel_y, floor_thickness, true, PI)
		
		# 左右单向墙 (法线朝外: 外面进不来，里面可以走出)
		_enable_one_way_side_walls(wall, lr)

## ── CONFINED 模式: 合并外墙 + 重叠区自由通行 + 虚空填充 ──

func _apply_confined_mode(local_rects: Array[Rect2], count: int) -> void:
	if not is_instance_valid(pet_instance):
		_apply_free_mode(local_rects, count)
		_hide_confined_wall()
		_clear_void_fillers()
		return
	
	var pet_pos = pet_instance.global_position
	
	# ── Step 1: 找到目标窗口 ──
	var target_idx: int = -1
	var target_rect = Rect2()
	
	if confined_anchor_rect.size != Vector2.ZERO:
		for i in range(count):
			var lr = local_rects[i]
			if lr.position.distance_to(confined_anchor_rect.position) < 30.0 and \
			   lr.size.distance_to(confined_anchor_rect.size) < 30.0:
				target_rect = lr
				target_idx = i
				break
	
	if target_idx == -1:
		for i in range(count):
			if local_rects[i].has_point(pet_pos):
				target_rect = local_rects[i]
				target_idx = i
				break
	
	if target_idx == -1:
		confined_window_rect = Rect2()
		confined_anchor_rect = Rect2()
		_hide_confined_wall()
		_clear_void_fillers()
		if is_instance_valid(pet_instance):
			pet_instance.confined_rect = Rect2()
		_apply_free_mode(local_rects, count)
		return
	
	# ── Step 2: 合并所有重叠窗口 (跳过最大化窗口) ──
	var merged_rect = target_rect
	var overlapping: Array[int] = [target_idx]
	var overlap_rects: Array[Rect2] = [target_rect]
	
	var changed = true
	while changed:
		changed = false
		for i in range(count):
			if overlapping.has(i):
				continue
			# 跳过最大化窗口: 它们覆盖整个屏幕，会导致所有窗口被合并
			if _is_maximized_window(local_rects[i]):
				continue
			if merged_rect.intersects(local_rects[i]):
				merged_rect = merged_rect.merge(local_rects[i])
				overlapping.append(i)
				overlap_rects.append(local_rects[i])
				changed = true
	
	# ── Step 3: 合并外墙 + 虚空填充 ──
	confined_anchor_rect = target_rect
	confined_window_rect = merged_rect
	_show_confined_wall(merged_rect)
	_fill_void_areas(overlap_rects, merged_rect)
	
	if is_instance_valid(pet_instance):
		pet_instance.confined_rect = merged_rect
	
	# ── Step 4: 生成幽灵墙 ──
	var floor_thickness = 10.0
	for i in range(count):
		var lr = local_rects[i]
		var wall = ghost_walls[i]
		_ensure_children(wall)
		wall.position = lr.position + lr.size / 2.0
		
		# 重叠组内的窗口: 禁用所有碰撞体 (封闭墙+虚空填充已处理)
		# 最大化窗口与封闭区域交叩时: 也禁用 (避免内部干扰)
		if overlapping.has(i) or _is_maximized_window(lr) or merged_rect.intersects(lr):
			for k in range(wall.get_child_count()):
				(wall.get_child(k) as CollisionShape2D).disabled = true
			continue
		
		# 不重叠的窗口: 正常 FREE 模式踏板
		var win_left = lr.position.x
		var win_right = lr.position.x + lr.size.x
		var top_y = lr.position.y
		var bottom_y = lr.position.y + lr.size.y
		
		var top_segs = _compute_exposed_segments(win_left, win_right, top_y, local_rects, i)
		var bottom_segs = _compute_exposed_segments(win_left, win_right, bottom_y, local_rects, i)
		
		var wall_cx = lr.position.x + lr.size.x / 2.0
		var top_rel_y = -lr.size.y / 2.0 + floor_thickness / 2.0
		var bot_rel_y = lr.size.y / 2.0 - floor_thickness / 2.0
		_apply_platform_segments(wall, 0, top_segs, wall_cx, top_rel_y, floor_thickness, true)
		_apply_platform_segments(wall, MAX_PLATFORM_SEGMENTS, bottom_segs, wall_cx, bot_rel_y, floor_thickness, true)
		
		_disable_side_walls(wall)

## 创建/更新封闭模式的四面实体墙
func _show_confined_wall(rect: Rect2) -> void:
	if not is_instance_valid(confined_wall):
		confined_wall = StaticBody2D.new()
		var mat = PhysicsMaterial.new()
		mat.bounce = 0.3
		mat.friction = 0.8
		confined_wall.physics_material_override = mat
		# 四面墙各一个碰撞体: 上/下/左/右
		for k in range(4):
			var col = CollisionShape2D.new()
			col.shape = RectangleShape2D.new()
			confined_wall.add_child(col)
		add_child(confined_wall)
	
	confined_wall.position = rect.position + rect.size / 2.0
	
	var w = rect.size.x
	var h = rect.size.y
	var thickness = 10.0
	
	# 上墙
	var col_top = confined_wall.get_child(0) as CollisionShape2D
	col_top.position = Vector2(0, -h / 2.0 + thickness / 2.0)
	(col_top.shape as RectangleShape2D).size = Vector2(w + thickness * 2, thickness)
	col_top.disabled = false
	
	# 下墙
	var col_bot = confined_wall.get_child(1) as CollisionShape2D
	col_bot.position = Vector2(0, h / 2.0 - thickness / 2.0)
	(col_bot.shape as RectangleShape2D).size = Vector2(w + thickness * 2, thickness)
	col_bot.disabled = false
	
	# 左墙
	var col_left = confined_wall.get_child(2) as CollisionShape2D
	col_left.position = Vector2(-w / 2.0 + thickness / 2.0, 0)
	(col_left.shape as RectangleShape2D).size = Vector2(thickness, h)
	col_left.disabled = false
	
	# 右墙
	var col_right = confined_wall.get_child(3) as CollisionShape2D
	col_right.position = Vector2(w / 2.0 - thickness / 2.0, 0)
	(col_right.shape as RectangleShape2D).size = Vector2(thickness, h)
	col_right.disabled = false

func _hide_confined_wall() -> void:
	if is_instance_valid(confined_wall):
		for k in range(confined_wall.get_child_count()):
			(confined_wall.get_child(k) as CollisionShape2D).disabled = true

## ── 虚空填充系统 (Sweep-Line 算法) ──

## 计算合并 bounding box 内未被任何窗口覆盖的虚空区域，生成物理屏障
func _fill_void_areas(overlap_rects: Array[Rect2], merged: Rect2) -> void:
	# 收集所有窗口的 X 边界坐标
	var x_coords: Array[float] = [merged.position.x, merged.end.x]
	for r in overlap_rects:
		x_coords.append(r.position.x)
		x_coords.append(r.end.x)
	x_coords.sort()
	
	# 去重 (容差 2px)
	var unique_x: Array[float] = []
	for x in x_coords:
		if unique_x.is_empty() or abs(x - unique_x.back()) > 2.0:
			unique_x.append(x)
	
	# 对每个 X 切片，找出未被窗口覆盖的 Y 区间 = 虚空
	var void_rects: Array[Rect2] = []
	for j in range(unique_x.size() - 1):
		var x_left = unique_x[j]
		var x_right = unique_x[j + 1]
		if x_right - x_left < 5.0:
			continue
		var x_mid = (x_left + x_right) / 2.0
		
		# 找出在这个 X 位置被窗口覆盖的 Y 范围
		var covered: Array = []
		for r in overlap_rects:
			if r.position.x <= x_mid and r.end.x >= x_mid:
				covered.append([r.position.y, r.end.y])
		
		# 合并覆盖区间
		covered.sort()
		var merged_y = _merge_y_ranges(covered)
		
		# bounding box 的 Y 范围中未被覆盖的部分 = 虚空
		var prev_y = merged.position.y
		for c in merged_y:
			if c[0] > prev_y + 5.0:
				void_rects.append(Rect2(x_left, prev_y, x_right - x_left, c[0] - prev_y))
			prev_y = maxf(prev_y, c[1])
		if merged.end.y > prev_y + 5.0:
			void_rects.append(Rect2(x_left, prev_y, x_right - x_left, merged.end.y - prev_y))
	
	# 同步虚空填充墙池
	_sync_void_fillers(void_rects)

## 合并重叠的 Y 区间
func _merge_y_ranges(ranges: Array) -> Array:
	if ranges.is_empty():
		return []
	var result: Array = [ranges[0].duplicate()]
	for i in range(1, ranges.size()):
		var prev = result.back()
		if ranges[i][0] <= prev[1]:
			result[result.size() - 1] = [prev[0], maxf(prev[1], ranges[i][1])]
		else:
			result.append(ranges[i].duplicate())
	return result

## 同步虚空填充墙对象池
func _sync_void_fillers(void_rects: Array[Rect2]) -> void:
	var need = void_rects.size()
	
	# 扩展池
	while void_fillers.size() < need:
		var wall = StaticBody2D.new()
		var col = CollisionShape2D.new()
		col.shape = RectangleShape2D.new()
		wall.add_child(col)
		var mat = PhysicsMaterial.new()
		mat.bounce = 0.3
		mat.friction = 0.8
		wall.physics_material_override = mat
		add_child(wall)
		void_fillers.append(wall)
	
	# 更新或禁用
	for i in range(void_fillers.size()):
		var wall = void_fillers[i]
		var col = wall.get_child(0) as CollisionShape2D
		if i < need:
			var vr = void_rects[i]
			wall.position = vr.position + vr.size / 2.0
			(col.shape as RectangleShape2D).size = vr.size
			col.disabled = false
		else:
			col.disabled = true

## 清除所有虚空填充墙
func _clear_void_fillers() -> void:
	for wall in void_fillers:
		(wall.get_child(0) as CollisionShape2D).disabled = true

## 检测窗口是否为最大化 (覆盖 ≥90% 屏幕宽度和高度)
func _is_maximized_window(lr: Rect2) -> bool:
	return lr.size.x >= boundary_size.x * 0.9 and lr.size.y >= boundary_size.y * 0.85

## ── 幽灵墙辅助函数 ──

## 确保对象池中的墙有足够的碰撞子节点
func _ensure_children(wall: StaticBody2D) -> void:
	while wall.get_child_count() < CHILDREN_PER_WALL:
		var col = CollisionShape2D.new()
		col.shape = RectangleShape2D.new()
		col.disabled = true
		wall.add_child(col)

## 启用左右实体侧墙 (双面，用于 REPELLED-封闭式拒绝)
func _enable_side_walls(wall: StaticBody2D, lr: Rect2) -> void:
	var side_idx_left = MAX_PLATFORM_SEGMENTS * 2
	var side_idx_right = MAX_PLATFORM_SEGMENTS * 2 + 1
	var wall_thickness = 10.0
	
	# 左侧墙
	var col_l = wall.get_child(side_idx_left) as CollisionShape2D
	col_l.position = Vector2(-lr.size.x / 2.0 + wall_thickness / 2.0, 0)
	(col_l.shape as RectangleShape2D).size = Vector2(wall_thickness, lr.size.y)
	col_l.rotation = 0.0
	col_l.one_way_collision = false
	col_l.disabled = false
	
	# 右侧墙
	var col_r = wall.get_child(side_idx_right) as CollisionShape2D
	col_r.position = Vector2(lr.size.x / 2.0 - wall_thickness / 2.0, 0)
	(col_r.shape as RectangleShape2D).size = Vector2(wall_thickness, lr.size.y)
	col_r.rotation = 0.0
	col_r.one_way_collision = false
	col_r.disabled = false

## 启用左右单向侧墙 (外面进不来，里面可以出去，用于 REPELLED 模式)
func _enable_one_way_side_walls(wall: StaticBody2D, lr: Rect2) -> void:
	var side_idx_left = MAX_PLATFORM_SEGMENTS * 2
	var side_idx_right = MAX_PLATFORM_SEGMENTS * 2 + 1
	var wall_thickness = 10.0
	
	# 左侧墙: rotation=-π/2 → 法线朝左 → 外面进不来，里面可以左出
	var col_l = wall.get_child(side_idx_left) as CollisionShape2D
	col_l.position = Vector2(-lr.size.x / 2.0 + wall_thickness / 2.0, 0)
	# 旋转后宽高互换: 原(thickness, height) → 设置为(height, thickness)
	(col_l.shape as RectangleShape2D).size = Vector2(lr.size.y, wall_thickness)
	col_l.rotation = -PI / 2.0
	col_l.one_way_collision = true
	col_l.disabled = false
	
	# 右侧墙: rotation=π/2 → 法线朝右 → 外面进不来，里面可以右出
	var col_r = wall.get_child(side_idx_right) as CollisionShape2D
	col_r.position = Vector2(lr.size.x / 2.0 - wall_thickness / 2.0, 0)
	(col_r.shape as RectangleShape2D).size = Vector2(lr.size.y, wall_thickness)
	col_r.rotation = PI / 2.0
	col_r.one_way_collision = true
	col_r.disabled = false

## 禁用左右侧墙 (重置旋转状态)
func _disable_side_walls(wall: StaticBody2D) -> void:
	var side_idx_left = MAX_PLATFORM_SEGMENTS * 2
	var side_idx_right = MAX_PLATFORM_SEGMENTS * 2 + 1
	if wall.get_child_count() > side_idx_right:
		var col_l = wall.get_child(side_idx_left) as CollisionShape2D
		col_l.disabled = true
		col_l.rotation = 0.0
		var col_r = wall.get_child(side_idx_right) as CollisionShape2D
		col_r.disabled = true
		col_r.rotation = 0.0

## 计算踏板在 Z-Order 遮挡裁剪后剩余的可见水平分段
func _compute_exposed_segments(full_left: float, full_right: float, platform_y: float, all_rects: Array[Rect2], idx: int) -> Array:
	var segs: Array = [[full_left, full_right]]
	for j in range(idx):
		var hr = all_rects[j]
		# 高层窗口的上下边界必须真正"跨越"踏板 Y 坐标才构成遮挡
		if hr.position.y < platform_y - 5.0 and hr.position.y + hr.size.y > platform_y + 5.0:
			segs = _subtract_range(segs, hr.position.x, hr.position.x + hr.size.x)
	# 过滤掉宽度不足以让宠物站立的碎片
	var result: Array = []
	for s in segs:
		if s[1] - s[0] >= MIN_SEGMENT_WIDTH:
			result.append(s)
	return result.slice(0, MAX_PLATFORM_SEGMENTS)

## 从一组水平区间中扣除 [cut_l, cut_r] 范围
func _subtract_range(segs: Array, cut_l: float, cut_r: float) -> Array:
	var out: Array = []
	for s in segs:
		if cut_r <= s[0] or cut_l >= s[1]:
			out.append(s)  # 无交集，保留
		else:
			if s[0] < cut_l:
				out.append([s[0], cut_l])  # 左侧残余
			if s[1] > cut_r:
				out.append([cut_r, s[1]])  # 右侧残余
	return out

## 将可见分段映射到碰撞体子节点，未使用的分段自动禁用
func _apply_platform_segments(wall: StaticBody2D, child_offset: int, segs: Array, wall_cx: float, rel_y: float, thickness: float, one_way: bool, seg_rotation: float = 0.0) -> void:
	for k in range(MAX_PLATFORM_SEGMENTS):
		var col = wall.get_child(child_offset + k) as CollisionShape2D
		if k < segs.size():
			var seg = segs[k]
			var seg_cx = (seg[0] + seg[1]) / 2.0
			col.position = Vector2(seg_cx - wall_cx, rel_y)
			(col.shape as RectangleShape2D).size = Vector2(seg[1] - seg[0], thickness)
			col.one_way_collision = one_way
			col.rotation = seg_rotation
			col.disabled = false
		else:
			col.disabled = true
			col.rotation = 0.0

## ── 窗口模式切换回调 ──

func _on_window_mode_changed(mode: int) -> void:
	var old_mode = window_mode
	window_mode = mode
	SettingsManager.set_int("window_mode", mode)
	
	# 同步模式给宠物
	if is_instance_valid(pet_instance):
		pet_instance.window_mode = mode
	
	# 切换到封闭模式时，立即检测目标窗口
	if mode == WindowMode.CONFINED:
		confined_window_rect = Rect2()  # 重置，让下次同步重新检测
		confined_anchor_rect = Rect2()
	
	# 切换离开封闭模式时，释放封闭墙
	if old_mode == WindowMode.CONFINED:
		confined_window_rect = Rect2()
		confined_anchor_rect = Rect2()
		_hide_confined_wall()
		if is_instance_valid(pet_instance):
			pet_instance.confined_rect = Rect2()
	
	print("[DesktopPet] 窗口交互模式切换: ", ["自由漫游", "窗口封闭", "窗口排斥"][mode])


# ── 宠物实例化 ──

func _spawn_pet() -> void:
	pet_instance = pet_scene.instantiate()
	pet_instance.screen_rect = screen_rect
	pet_instance.boundary_size = boundary_size
	pet_instance.window_mode = window_mode
	# 从视口上方 1/3 处中央掉落
	pet_instance.position = Vector2(
		boundary_size.x / 2.0,
		boundary_size.y / 3.0
	)
	add_child(pet_instance)
	
	print("[DesktopPet] 宠物生成于: ", pet_instance.position)

# ── 提醒系统 ──

func _setup_reminder_system() -> void:
	# 提醒管理面板 (CanvasLayer，自带 UI)
	var panel_script = load("res://ui/reminder_panel.gd")
	if panel_script:
		var panel_node = CanvasLayer.new()
		panel_node.set_script(panel_script)
		add_child(panel_node)
	
	# 气泡通知 (CanvasLayer，跟随宠物头顶)
	var bubble_script = load("res://ui/reminder_bubble.gd")
	if bubble_script:
		var bubble_node = CanvasLayer.new()
		bubble_node.set_script(bubble_script)
		add_child(bubble_node)
		if pet_instance and bubble_node.has_method("link_pet"):
			bubble_node.link_pet(pet_instance)

# ── 鼠标穿透管理 ──

var last_passthrough_rect: Rect2i
var _passthrough_timer: float = 0.0
# 穿透区域刷新限流：DWM 重组合是头号性能杀手;
# 渲染跑 120fps，穿透检测只需 ~60hz 即可（延迟 ≤16ms 人眼不可感知）
const PASSTHROUGH_INTERVAL := 0.016

func _process(delta: float) -> void:
	if is_dragging or is_menu_open:
		return
	_passthrough_timer += delta
	if _passthrough_timer >= PASSTHROUGH_INTERVAL:
		_passthrough_timer = 0.0
		_update_passthrough_box()

func _update_passthrough_state() -> void:
	if is_dragging or is_menu_open:
		var full := PackedVector2Array([
			Vector2.ZERO,
			Vector2(boundary_size.x, 0),
			Vector2(boundary_size.x, boundary_size.y),
			Vector2(0, boundary_size.y),
		])
		DisplayServer.window_set_mouse_passthrough(full)
	else:
		last_passthrough_rect = Rect2i()
		_update_passthrough_box()

func _update_passthrough_box() -> void:
	if not is_instance_valid(pet_instance):
		return
	
	var exact_rect: Rect2
	if pet_instance.has_method("get_render_rect"):
		exact_rect = pet_instance.get_render_rect()
	else:
		var pos := pet_instance.global_position
		exact_rect = Rect2(pos - Vector2(50, 50), Vector2(100, 100))
	
	# 这里是终极秘诀：把浮点级的渲染框，对齐到底层 8 像素的栅格中
	# 这样一来，只有当特效或实体的包围盒真正跨越了 8 像素边界时，才会惊动 Windows 系统
	# 既完美消除了拖影的渲染裁剪，又 100% 杜绝了 DWM 底层每秒 60 次的无意义刷新卡顿！
	var snapped_x = int(exact_rect.position.x / 8.0) * 8
	var snapped_y = int(exact_rect.position.y / 8.0) * 8
	var snapped_w = int(exact_rect.size.x / 8.0) * 8 + 16
	var snapped_h = int(exact_rect.size.y / 8.0) * 8 + 16
	var current_rect_i = Rect2i(snapped_x, snapped_y, snapped_w, snapped_h)
	
	if current_rect_i == last_passthrough_rect:
		return
		
	last_passthrough_rect = current_rect_i
	
	var polygon := PackedVector2Array([
		current_rect_i.position,
		Vector2(current_rect_i.end.x, current_rect_i.position.y),
		current_rect_i.end,
		Vector2(current_rect_i.position.x, current_rect_i.end.y),
	])
	
	DisplayServer.window_set_mouse_passthrough(polygon)

func _on_drag_started() -> void:
	is_dragging = true
	_update_passthrough_state()

func _on_drag_ended() -> void:
	is_dragging = false
	_update_passthrough_state()

func _on_context_menu_toggled(is_open: bool) -> void:
	is_menu_open = is_open
	_update_passthrough_state()

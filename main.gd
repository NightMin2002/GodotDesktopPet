# main.gd — 启动场景主脚本
# 职责: 设置透明窗口、创建屏幕边界墙、实例化宠物、管理鼠标穿透区域
extends Node2D

# ── 窗口交互模式 ──
enum WindowMode { FREE, CONFINED, REPELLED }

var pet_scene := preload("res://entities/pet/pet.tscn")
var clone_scene := preload("res://entities/pet/clone_pet.tscn")
var pet_instance: RigidBody2D  # 原体引用 (快捷访问)
var pet_instances: Array[RigidBody2D] = []  # 所有宠物 (原体 + 克隆体)
var screen_rect: Rect2i
var boundary_size: Vector2  # 实际使用的边界尺寸 (视口坐标系)
var is_dragging := false
var is_menu_open := false

# ── 克隆系统 ──
const MAX_CLONES: int = 5
# 5 种预设色调偏移 (HSV hue 0~1)：紫、青、琥珀、翠绿、玫瑰
var CLONE_HUE_SHIFTS: Array[float] = [0.75, 0.45, 0.12, 0.35, 0.85]

# -- 双端架构 C# 桥接池 --
var win_manager: Node
var ghost_walls: Array[StaticBody2D] = []

# ── 窗口交互模式状态 ──
var window_mode: int = WindowMode.FREE

# ── 行为指令状态 ──
var behavior_mode: int = 0  # 0=FREE, 1=QUIET


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
	
	# 等待 5 帧让窗口内部 (GPU Context + DWM Surface) 完全就绪
	for i in range(5):
		await get_tree().process_frame
	
	# 先恢复可见，再推 ToolWindow 标记
	# 必须 Show → Hide → 修改样式 → Show，否则 Shell 不会正确刷新
	get_window().visible = true
	await get_tree().process_frame
	if win_manager and win_manager.has_method("HideFromTaskbar"):
		win_manager.call("HideFromTaskbar")
	
	_create_boundaries()
	_spawn_pet()
	
	# 从持久化恢复克隆体
	var saved_clones = SettingsManager.get_int("clone_count", 0)
	for i in range(mini(saved_clones, MAX_CLONES)):
		_clone_pet(null, false)  # 静默恢复，不冒泡
	
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
	EventBus.behavior_mode_changed.connect(_on_behavior_mode_changed)
	EventBus.clone_pet.connect(_on_clone_pet_requested)
	EventBus.dismiss_clones.connect(_on_dismiss_clones_requested)
	
	# 从持久化恢复窗口交互模式
	window_mode = SettingsManager.get_int("window_mode", WindowMode.FREE)
	
	# 从持久化恢复行为指令
	behavior_mode = SettingsManager.get_int("behavior_mode", 0)
	if behavior_mode == 1:
		EventBus.behavior_mode_changed.emit(1)
	

	# 启动任务栏样式守护 Timer (每5秒自检，防止引擎焦点变化时重置样式)
	if win_manager and win_manager.has_method("EnsureHiddenFromTaskbar"):
		var taskbar_timer = Timer.new()
		taskbar_timer.wait_time = 5.0
		taskbar_timer.autostart = true
		taskbar_timer.timeout.connect(_guard_taskbar_style)
		add_child(taskbar_timer)
	
	# 挂载提醒系统
	_setup_reminder_system()
	_setup_pet_chatter()
	
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
			# 利用运行时生成一个神级单眼图标：采用多段超短偏移实现硬边缘，完美复刻蓝白机械单眼！
			# 为适应托盘极小尺寸，中心光核修改为纯白色以凸显发光感
			var grad = Gradient.new()
			grad.colors = PackedColorArray([
				Color.WHITE,                  # 白亮核心，带来高能亮斑
				Color.WHITE,                  
				Color(0.20, 0.60, 1.00, 1.0), # 冰蓝色渐变发光内环
				Color(0.10, 0.30, 0.85, 1.0), # 湛蓝过渡层
				Color(0.05, 0.15, 0.45, 1.0), # 深蓝色外壳垫底
				Color(0.05, 0.15, 0.45, 1.0), 
				Color.WHITE,                  # 最亮眼的纯白防护边框
				Color.WHITE,                  
				Color(0.02, 0.08, 0.25, 1.0), # 极其深沉的外围轮廓
				Color(0.02, 0.08, 0.25, 1.0), 
				Color.TRANSPARENT             # 外部切圆透明
			])
			grad.offsets = PackedFloat32Array([
				0.0, 0.22,    # 白核区
				0.24, 0.50,   # 亮蓝发光区
				0.52, 0.70,   # 深蓝基地区
				0.72, 0.82,   # 白边界
				0.84, 0.96,   # 极暗外壳边界
				0.98          # 透明过渡抗锯齿
			])
			var tex = GradientTexture2D.new()
			tex.gradient = grad
			tex.width = 64
			tex.height = 64
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.5)
			tex.fill_to = Vector2(0.5, 0.0)
			tray.icon = tex
			
		tray.tooltip = "桌面宠物"
		
		# 挂载专属托盘温馨右键菜单
		var tray_menu = PopupMenu.new()
		tray_menu.add_item("💤 让宠物休息 (告别退出)", 1)
		tray_menu.add_separator()
		tray_menu.add_item("⚡ 强制退出", 2)
		tray_menu.id_pressed.connect(func(id: int):
			if id == 1:
				quit_with_farewell()
			elif id == 2:
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
		WindowMode.CONFINED:
			_apply_confined_mode(local_rects, count)
		WindowMode.REPELLED:
			_apply_repelled_mode(local_rects, count)

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

## ── REPELLED 模式: 复用多边形合并，法线朝内阻止进入 ──
## 重叠窗口先合并为连通外轮廓，避免内部小窗口产生虚假排斥墙

func _apply_repelled_mode(local_rects: Array[Rect2], count: int) -> void:
	# rotation_offset=0: 不加 PI，法线指向窗内 → 拦截向内移动 (排斥)
	_apply_polygon_wall_mode(local_rects, count, 0.0)

func _apply_confined_mode(local_rects: Array[Rect2], count: int) -> void:
	# rotation_offset=PI: 加 PI 反转法线指向窗外 → 拦截向外移动 (封闭)
	_apply_polygon_wall_mode(local_rects, count, PI)

## ── 通用多边形合并建墙 (CONFINED / REPELLED 共用) ──
## rotation_offset=PI → 封闭模式 (拦截外出)；rotation_offset=0 → 排斥模式 (拦截进入)

func _apply_polygon_wall_mode(local_rects: Array[Rect2], count: int, rotation_offset: float) -> void:
	# 收集所有非最大化窗口作为离散多边形
	var polys: Array[PackedVector2Array] = []
	for i in range(count):
		if _is_maximized_window(local_rects[i]):
			continue
		var r = local_rects[i]
		polys.append(PackedVector2Array([
			r.position,
			Vector2(r.end.x, r.position.y),
			r.end,
			Vector2(r.position.x, r.end.y)
		]))
		
	# ── 多边形合并 (Clipper) ──
	# 计算所有窗口连通块的确切外轮廓（包括内部孔洞）
	var merged_polys: Array[PackedVector2Array] = polys.duplicate()
	var merged_happened = true
	while merged_happened and merged_polys.size() > 1:
		merged_happened = false
		var next_polys: Array[PackedVector2Array] = []
		while merged_polys.size() > 0:
			var p1 = merged_polys.pop_back()
			var found_merge = false
			for i in range(merged_polys.size()):
				# 如果两个多边形有重叠交集
				if not Geometry2D.intersect_polygons(p1, merged_polys[i]).is_empty():
					var res = Geometry2D.merge_polygons(p1, merged_polys[i])
					merged_polys.remove_at(i)
					merged_polys.append_array(res)
					found_merge = true
					merged_happened = true
					break
			if not found_merge:
				next_polys.append(p1)
		merged_polys = next_polys
		
	# ── 建墙 ──
	var wall_idx = 0
	for poly in merged_polys:
		if wall_idx >= ghost_walls.size(): break
		var wall = ghost_walls[wall_idx]
		wall.position = Vector2.ZERO # 顶点已经是全局坐标
		var child_idx = 0
		var n = poly.size()
		
		# 沿着每条边建立精确尺寸的单向空气墙
		for i in range(n):
			var a = poly[i]
			var b = poly[(i + 1) % n]
			var length = a.distance_to(b)
			if length < 5.0: continue
			
			# 动态扩容子节点
			while child_idx >= wall.get_child_count():
				var c = CollisionShape2D.new()
				c.shape = RectangleShape2D.new()
				c.disabled = true
				wall.add_child(c)
				
			var col = wall.get_child(child_idx) as CollisionShape2D
			col.position = (a + b) / 2.0
			var rect_shape = col.shape as RectangleShape2D
			if rect_shape == null:
				rect_shape = RectangleShape2D.new()
				col.shape = rect_shape
				
			# 延伸 10 像素以覆盖角落缝隙
			rect_shape.size = Vector2(length + 10.0, 10.0)
			# Godot 单向碰撞原理：拦截向着 Local +Y 方向的移动，允许向着 Local -Y 的移动。
			# 外轮廓顺时针，(b-a).angle() 的 Local +Y 指向窗内。
			# rotation_offset=0   → 不反转，拦截向内移动 → 排斥模式 (REPELLED)
			# rotation_offset=PI  → 反转法线指向窗外，拦截向外移动 → 封闭模式 (CONFINED)
			col.rotation = (b - a).angle() + rotation_offset
			col.one_way_collision = true
			col.disabled = false
			child_idx += 1
			
		# 禁用此 wall 中未使用到的多余碰撞体积
		for i in range(child_idx, wall.get_child_count()):
			(wall.get_child(i) as CollisionShape2D).disabled = true
			
		wall_idx += 1

	# 未被用到的备用窗口对象池，直接禁用封存
	for i in range(wall_idx, ghost_walls.size()):
		var w = ghost_walls[i]
		for k in range(w.get_child_count()):
			(w.get_child(k) as CollisionShape2D).disabled = true

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
	window_mode = mode
	SettingsManager.set_int("window_mode", mode)
	
	# 同步模式给所有宠物
	for p in pet_instances:
		if is_instance_valid(p):
			p.window_mode = mode
	
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
	pet_instances.append(pet_instance)
	
	print("[DesktopPet] 宠物生成于: ", pet_instance.position)

# ── 克隆系统 ──

func _on_clone_pet_requested(_source: Node2D) -> void:
	_clone_pet(_source, true)

func _clone_pet(source: Node2D, with_bubble: bool) -> void:
	var clone_count = pet_instances.size() - 1  # 不含原体
	if clone_count >= MAX_CLONES:
		if with_bubble:
			EventBus.show_reminder_bubble.emit("分身已达上限 (" + str(MAX_CLONES) + "/" + str(MAX_CLONES) + ")！")
		return
	
	var clone = clone_scene.instantiate()
	clone.screen_rect = screen_rect
	clone.boundary_size = boundary_size
	clone.window_mode = window_mode
	clone.clone_hue_shift = CLONE_HUE_SHIFTS[clone_count % CLONE_HUE_SHIFTS.size()]
	
	# 在原体/源头附近上方生成，错开一点水平位置
	var spawn_x: float
	if is_instance_valid(source):
		spawn_x = source.global_position.x + randf_range(-80, 80)
	else:
		spawn_x = randf_range(boundary_size.x * 0.2, boundary_size.x * 0.8)
	spawn_x = clampf(spawn_x, 60.0, boundary_size.x - 60.0)
	clone.position = Vector2(spawn_x, boundary_size.y * 0.1)
	
	# 同步行为指令
	clone.behavior_mode = behavior_mode
	
	add_child(clone)
	pet_instances.append(clone)
	
	# 持久化保存
	SettingsManager.set_int("clone_count", pet_instances.size() - 1)
	
	if with_bubble:
		var greetings = ["分身术！召唤成功✨", "又多了一个伙伴！🎉", "一起热闹热闹～🌟", "家族壮大啦！⚡", "我给你叫了个帮手！🫡"]
		EventBus.show_reminder_bubble.emit(greetings[clone_count % greetings.size()])
	
	print("[DesktopPet] 克隆体 #", clone_count + 1, " 已生成 (hue_shift=", clone.clone_hue_shift, ")")
	reorganize_quiet_queue()

func _on_dismiss_clones_requested() -> void:
	var clones_to_remove: Array[RigidBody2D] = []
	for p in pet_instances:
		if p.is_clone:
			clones_to_remove.append(p)
	
	if clones_to_remove.is_empty():
		EventBus.show_reminder_bubble.emit("没有分身可以遣散哦~")
		return
	
	for clone in clones_to_remove:
		pet_instances.erase(clone)
		# 淡出消失动画 + 禁用碰撞 (防止隐形实体阻挡其他宠物)
		clone.freeze = true
		clone.collision_layer = 0
		clone.collision_mask = 0
		var tw = create_tween().set_parallel(true)
		tw.tween_property(clone, "modulate:a", 0.0, 0.5)
		tw.tween_property(clone, "scale", Vector2(0.1, 0.1), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		var c = clone  # 闭包捕获
		tw.finished.connect(func(): c.queue_free())
	
	SettingsManager.set_int("clone_count", 0)
	EventBus.show_reminder_bubble.emit("分身们，辛苦了！下次再见~ 👋")
	reorganize_quiet_queue()

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

# ── 宠物碎碎念 ──

func _setup_pet_chatter() -> void:
	var chatter_script = load("res://ui/pet_chatter.gd")
	if chatter_script:
		var chatter_node = Node.new()
		chatter_node.set_script(chatter_script)
		add_child(chatter_node)
		if pet_instance and chatter_node.has_method("link_pet"):
			chatter_node.link_pet(pet_instance)
		print("[DesktopPet] 宠物碎碎念系统已启动 (30分钟间隔)")

# ── 鼠标穿透管理 (WM_NCHITTEST 命中测试方案) ──

var _passthrough_timer: float = 0.0
var _last_circles: PackedFloat32Array = PackedFloat32Array()
var _last_rects: PackedFloat32Array = PackedFloat32Array()
# 穿透检测限流：命中测试不修改窗口形状，开销极低
# 但数据传递与变化检测仍需限流，~60hz 足够
const PASSTHROUGH_INTERVAL := 0.016

func _process(delta: float) -> void:
	if is_dragging or is_menu_open:
		return
	_passthrough_timer += delta
	if _passthrough_timer >= PASSTHROUGH_INTERVAL:
		_passthrough_timer = 0.0
		_update_hit_regions()

func _update_passthrough_state() -> void:
	if is_dragging or is_menu_open:
		# 拖拽/菜单打开时: 全窗口可交互
		if win_manager and win_manager.has_method("SetFullWindowHit"):
			win_manager.call("SetFullWindowHit", true)
		else:
			# 回退到 Godot API
			var full := PackedVector2Array([
				Vector2.ZERO,
				Vector2(boundary_size.x, 0),
				Vector2(boundary_size.x, boundary_size.y),
				Vector2(0, boundary_size.y),
			])
			DisplayServer.window_set_mouse_passthrough(full)
	else:
		if win_manager and win_manager.has_method("SetFullWindowHit"):
			win_manager.call("SetFullWindowHit", false)
		_last_circles = PackedFloat32Array()
		_last_rects = PackedFloat32Array()
		_update_hit_regions()

## 收集所有宠物/UI 元素的命中区域，传递给 C# 层
func _update_hit_regions() -> void:
	# 圆形区域: [cx, cy, radius, ...] — 宠物本体 (精确椭圆命中)
	var circles := PackedFloat32Array()
	# 矩形区域: [x, y, w, h, ...] — UI/特效包围盒
	var rects := PackedFloat32Array()
	
	for p in pet_instances:
		if not is_instance_valid(p):
			continue
		
		# ── 宠物本体: 精确圆形命中 ──
		var pet_pos := p.global_position
		var pet_r: float = p.PET_RADIUS + 15.0  # 半径 + 容差匹配 is_mouse_on_pet
		circles.append(_q(pet_pos.x))
		circles.append(_q(pet_pos.y))
		circles.append(_q(pet_r))
		
		# ── 拖影尾巴: 单个 AABB 矩形包围盒 (视觉特效无需精确命中) ──
		if p.trail_enabled and p.trail_history.size() > 0:
			var min_x := pet_pos.x
			var min_y := pet_pos.y
			var max_x := pet_pos.x
			var max_y := pet_pos.y
			for trail_pos in p.trail_history:
				min_x = minf(min_x, trail_pos.x - p.PET_RADIUS)
				min_y = minf(min_y, trail_pos.y - p.PET_RADIUS)
				max_x = maxf(max_x, trail_pos.x + p.PET_RADIUS)
				max_y = maxf(max_y, trail_pos.y + p.PET_RADIUS)
			rects.append(_q(min_x - 5))
			rects.append(_q(min_y - 5))
			rects.append(_q(max_x - min_x + 10))
			rects.append(_q(max_y - min_y + 10))
		
		# ── 冲击波: 单个 AABB 矩形包围盒 ──
		for shock in p.shockwaves:
			if shock["alpha"] > 0.1:
				var s_pos = pet_pos + shock["local_pos"]
				var sr: float = shock["radius"] + 10.0
				rects.append(_q(s_pos.x - sr))
				rects.append(_q(s_pos.y - sr))
				rects.append(_q(sr * 2.0))
				rects.append(_q(sr * 2.0))
		
		# ── 全息时钟 HUD: 矩形 ──
		if p.hud_clock_enabled and is_instance_valid(p.hud_clock_label) and p.hud_clock_label.visible:
			var clock_pos = p.hud_clock_label.global_position
			var clock_size = p.hud_clock_label.get_minimum_size()
			rects.append(_q(clock_pos.x - 5))
			rects.append(_q(clock_pos.y - 5))
			rects.append(_q(clock_size.x + 10))
			rects.append(_q(clock_size.y + 10))
		
		# ── 全局气泡覆盖层: 矩形 ──
		if p.overlay_rect.size != Vector2.ZERO:
			var ov = p.overlay_rect
			rects.append(_q(ov.position.x))
			rects.append(_q(ov.position.y))
			rects.append(_q(ov.size.x))
			rects.append(_q(ov.size.y))
		
		# ── 本地定向气泡堆栈: 每个气泡独立矩形 ──
		if p.has_method("get_local_bubble_rects"):
			for br in p.get_local_bubble_rects():
				rects.append(_q(br.position.x))
				rects.append(_q(br.position.y))
				rects.append(_q(br.size.x))
				rects.append(_q(br.size.y))
	
	# 变化检测: 栅格量化后只有显著变化才跨语言传递
	if circles == _last_circles and rects == _last_rects:
		return
	_last_circles = circles
	_last_rects = rects
	
	# 优先使用 C# 层混合形状区域 (椭圆+矩形)
	if win_manager and win_manager.has_method("UpdateHitRegions"):
		win_manager.call("UpdateHitRegions", circles, rects)
	else:
		# 回退: Godot API (单多边形 AABB)
		if circles.size() >= 3:
			var min_x := circles[0] - circles[2]
			var min_y := circles[1] - circles[2]
			var max_x := circles[0] + circles[2]
			var max_y := circles[1] + circles[2]
			for i in range(0, circles.size(), 3):
				min_x = minf(min_x, circles[i] - circles[i+2])
				min_y = minf(min_y, circles[i+1] - circles[i+2])
				max_x = maxf(max_x, circles[i] + circles[i+2])
				max_y = maxf(max_y, circles[i+1] + circles[i+2])
			for i in range(0, rects.size(), 4):
				min_x = minf(min_x, rects[i])
				min_y = minf(min_y, rects[i+1])
				max_x = maxf(max_x, rects[i] + rects[i+2])
				max_y = maxf(max_y, rects[i+1] + rects[i+3])
			DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
				Vector2(min_x, min_y),
				Vector2(max_x, min_y),
				Vector2(max_x, max_y),
				Vector2(min_x, max_y),
			]))

## 4px 栅格量化: 减少亚像素抖动导致的无意义 SetWindowRgn 刷新
func _q(v: float) -> float:
	return float(int(v / 4.0) * 4)

func _on_drag_started() -> void:
	is_dragging = true
	_update_passthrough_state()

func _on_drag_ended() -> void:
	is_dragging = false
	_update_passthrough_state()

func _on_context_menu_toggled(is_open: bool) -> void:
	is_menu_open = is_open
	_update_passthrough_state()

# ── 行为指令 ──

func _on_behavior_mode_changed(mode: int) -> void:
	behavior_mode = mode
	SettingsManager.set_int("behavior_mode", mode)
	# 手动切安静待命时，分配并移动到最近的屏幕边缘队列
	if mode == 1:
		reorganize_quiet_queue()

## 动态重新评估所有克隆体在屏幕上的水平位置，并重新分配车位。
## 防止出现“插队”带来的互相推搡死锁，或“首位被移走”后排不自动向前补位的问题。
func reorganize_quiet_queue() -> void:
	if behavior_mode != 1: return
	
	var left_q: Array[RigidBody2D] = []
	var right_q: Array[RigidBody2D] = []
	
	for p in pet_instances:
		if is_instance_valid(p):
			if p.global_position.x < boundary_size.x / 2.0:
				left_q.append(p)
			else:
				right_q.append(p)
				
	# 从外向内排序，离边缘越近排车位越靠前
	left_q.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	right_q.sort_custom(func(a, b): return a.global_position.x > b.global_position.x)
	
	var spacing := 65.0
	_apply_queue_targets(left_q, 40.0, spacing, 1.0)
	_apply_queue_targets(right_q, boundary_size.x - 40.0, spacing, -1.0)

func _apply_queue_targets(q: Array[RigidBody2D], base_x: float, spacing: float, dir: float) -> void:
	for i in range(q.size()):
		var p = q[i]
		var old_tgt = p.get_meta("retreat_target_x", -9999.0)
		var new_tgt = base_x + i * spacing * dir
		p.set_meta("retreat_target_x", new_tgt)
		
		# 如果目标车位发生了显著挪动，且宠物正在发呆，叫醒它滚向新目标
		if absf(old_tgt - new_tgt) > 5.0 and p.current_state_name == "idle":
			# 确保不是原地微调
			if absf(p.global_position.x - new_tgt) > 20.0:
				p.transition_to("retreat")

## 任务栏样式守护: 如果引擎意外重置了 WS_EX_TOOLWINDOW，重新推入
func _guard_taskbar_style() -> void:
	if win_manager and win_manager.has_method("EnsureHiddenFromTaskbar"):
		var fixed: bool = win_manager.call("EnsureHiddenFromTaskbar")
		if fixed:
			print("[DesktopPet] 任务栏样式守护：已自动修复 ToolWindow 标记")



# ── 告别退出 ──

var _is_quitting := false  # 防止重复触发告别流程

## 播放告别动画后退出: 宠物说一句告别的话 → 等待落地 → 滚向屏幕边缘外 → 渐隐消失 → 退出程序
func quit_with_farewell() -> void:
	if _is_quitting:
		return
	_is_quitting = true
	
	# 🛡️ 立即禁用所有宠物的输入处理，防止退出动画期间误触
	for p in pet_instances:
		if is_instance_valid(p):
			p.set_process_unhandled_input(false)
	
	var farewell_lines := [
		"主人再见！我去休息啦~ 🌙",
		"拜拜~ 下次见面要摸摸我哦！",
		"困了困了... 晚安主人 😴",
		"好的！我先去充个电~ ⚡",
		"下次再来陪你玩！再见~ 👋",
	]
	var line = farewell_lines[randi() % farewell_lines.size()]
	EventBus.force_show_bubble.emit(line)
	
	# 统一设置为安静模式
	for p in pet_instances:
		if is_instance_valid(p):
			p.behavior_mode = 1
	
	# 先让克隆体快速缩放淡出 + 禁用碰撞 (防止隐形实体阻挡原体退场)
	for p in pet_instances:
		if is_instance_valid(p) and p.is_clone:
			p.freeze = true
			p.collision_layer = 0
			p.collision_mask = 0
			var ctw = create_tween().set_parallel(true)
			ctw.tween_property(p, "modulate:a", 0.0, 0.4)
			ctw.tween_property(p, "scale", Vector2(0.1, 0.1), 0.4)
			var cp = p
			ctw.finished.connect(func(): cp.queue_free())
	
	if pet_instance:
		# 如果宠物在空中/正在下落，先等待落地 (最多 6 秒防止卡死)
		if not pet_instance.is_settled() or pet_instance.current_state_name in ["fall", "jump", "drag"]:
			if pet_instance.current_state_name == "drag":
				pet_instance.transition_to("fall")
			var wait_time := 0.0
			while wait_time < 6.0:
				await get_tree().create_timer(0.2).timeout
				wait_time += 0.2
				if pet_instance.is_settled() and pet_instance.current_state_name not in ["fall", "jump", "drag"]:
					break
		
		# 等气泡展示 2 秒 (给用户阅读告别语的缓冲)
		await get_tree().create_timer(2.0).timeout
		
		# 冻结物理, tween 全权控制退场
		pet_instance.freeze = true
		
		# 计算退场路径: 当前位置 → 滑出屏幕外
		var slide_dir = -1.0 if pet_instance.global_position.x < boundary_size.x / 2.0 else 1.0
		var dist_to_edge = pet_instance.global_position.x if slide_dir < 0 else boundary_size.x - pet_instance.global_position.x
		var total_dist = dist_to_edge + 150.0
		var exit_pos = pet_instance.global_position + Vector2(slide_dir * total_dist, 0)
		var roll_angle = pet_instance.rotation + slide_dir * total_dist / 30.0
		var slide_time = clampf(total_dist / 400.0, 0.8, 2.0)
		
		var tween = create_tween().set_parallel(true)
		tween.tween_property(pet_instance, "global_position", exit_pos, slide_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(pet_instance, "rotation", roll_angle, slide_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(pet_instance, "modulate:a", 0.0, slide_time)
		pet_instance.overlay_rect = Rect2()
		# 气泡同步淡出
		for child in get_children():
			if child.has_method("is_busy"):
				for sub in child.get_children():
					if sub is PanelContainer and sub.visible:
						tween.tween_property(sub, "modulate:a", 0.0, slide_time * 0.7)
		tween.chain().tween_callback(func(): get_tree().quit())
		return
	
	# 无宠物实例时直接退出
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

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
var _quiet_by_fullscreen: bool = false  # 是否由全屏自动触发的安静模式
var _was_fullscreen: bool = false  # 已确认的全屏状态
var _fs_confirm_count: int = 0  # 全屏连续检测计数 (进入防抖)
var _fs_exit_count: int = 0  # 非全屏连续检测计数 (退出防抖)
const FS_ENTER_THRESHOLD := 3  # 进入全屏需连续 3 次检测 (1.5s×3=4.5s 确认，避免截图误触发)
const FS_EXIT_THRESHOLD := 2   # 退出全屏需连续 2 次检测 (3s 确认)
var _fs_exit_cooldown: float = 0.0  # 退出冷却计时器 (防止频繁进出)
const FS_EXIT_COOLDOWN_DURATION := 30.0  # 退出全屏后 30 秒内不再重新进入
var _fs_last_bubble_time: float = 0.0  # 上次全屏气泡时间
const FS_BUBBLE_MIN_INTERVAL := 60.0  # 全屏气泡最小间隔 60 秒

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
	EventBus.fullscreen_locked_changed.connect(_on_fullscreen_locked_changed)
	EventBus.clone_pet.connect(_on_clone_pet_requested)
	EventBus.dismiss_clones.connect(_on_dismiss_clones_requested)
	
	# 从持久化恢复窗口交互模式
	window_mode = SettingsManager.get_int("window_mode", WindowMode.FREE)
	
	# 从持久化恢复行为指令
	behavior_mode = SettingsManager.get_int("behavior_mode", 0)
	if behavior_mode == 1:
		EventBus.behavior_mode_changed.emit(1)
	
	# 启动全屏检测雷达 (1.5s 一次，进入防抖 3 次 = 4.5s 确认)
	if win_manager and win_manager.has_method("IsUserInFullscreen"):
		var fs_timer = Timer.new()
		fs_timer.wait_time = 1.5
		fs_timer.autostart = true
		fs_timer.timeout.connect(_check_fullscreen)
		add_child(fs_timer)
		print("[DesktopPet] 全屏检测雷达已启动 (1.5s 间隔, 进入防抖 3 次)")
	
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

## ── CONFINED 模式: 重叠窗口合并为一个封闭区域 ──
## 核心: 先将重叠窗口分组，每组合并成一个 AABB，在 AABB 外边界建墙

func _apply_confined_mode(local_rects: Array[Rect2], count: int) -> void:
	# ── Step 1: 构建重叠分组 (Union-Find) ──
	var parent: Array[int] = []
	for idx in range(count):
		parent.append(idx)
	
	# 合并所有相交的非最大化窗口
	for a in range(count):
		if _is_maximized_window(local_rects[a]):
			continue
		for b in range(a + 1, count):
			if _is_maximized_window(local_rects[b]):
				continue
			if local_rects[a].intersects(local_rects[b]):
				# Union
				var ra = a
				while parent[ra] != ra: ra = parent[ra]
				var rb = b
				while parent[rb] != rb: rb = parent[rb]
				parent[rb] = ra
	
	# 收集每个组的成员 + 合并 AABB
	var groups: Dictionary = {}  # root_idx → { "members": [int], "aabb": Rect2 }
	for idx in range(count):
		if _is_maximized_window(local_rects[idx]):
			continue
		var root = idx
		while parent[root] != root: root = parent[root]
		if not groups.has(root):
			groups[root] = { "members": [], "aabb": local_rects[idx] }
		groups[root]["members"].append(idx)
		groups[root]["aabb"] = (groups[root]["aabb"] as Rect2).merge(local_rects[idx])
	
	# 标记哪些窗口已被分组处理
	var handled: Array[bool] = []
	for idx in range(count):
		handled.append(false)
	
	# ── Step 2: 每个组 → 用第一个成员的 ghost_wall 建外围墙 ──
	var floor_thickness = 10.0
	var wall_thickness = 10.0
	for root in groups:
		var grp = groups[root]
		var members: Array = grp["members"]
		var aabb: Rect2 = grp["aabb"]
		
		# 第一个成员承载组的外围碰撞体
		var primary_idx: int = members[0]
		var primary_wall: StaticBody2D = ghost_walls[primary_idx]
		_ensure_children(primary_wall)
		primary_wall.position = aabb.position + aabb.size / 2.0
		handled[primary_idx] = true
		
		var w = aabb.size.x
		var h = aabb.size.y
		
		# 顶部: 单向天花板 (rotation=PI → 从上方可落入，从内部无法跳出)
		var col_top = primary_wall.get_child(0) as CollisionShape2D
		col_top.position = Vector2(0, -h / 2.0 + floor_thickness / 2.0)
		(col_top.shape as RectangleShape2D).size = Vector2(w + wall_thickness * 2, floor_thickness)
		col_top.rotation = PI
		col_top.one_way_collision = true
		col_top.disabled = false
		# 禁用其余顶部分段
		for k in range(1, MAX_PLATFORM_SEGMENTS):
			(primary_wall.get_child(k) as CollisionShape2D).disabled = true
		
		# 底部: 标准单向踏板 (可以站在上面)
		var col_bot = primary_wall.get_child(MAX_PLATFORM_SEGMENTS) as CollisionShape2D
		col_bot.position = Vector2(0, h / 2.0 - floor_thickness / 2.0)
		(col_bot.shape as RectangleShape2D).size = Vector2(w + wall_thickness * 2, floor_thickness)
		col_bot.rotation = 0.0
		col_bot.one_way_collision = true
		col_bot.disabled = false
		# 禁用其余底部分段
		for k in range(1, MAX_PLATFORM_SEGMENTS):
			(primary_wall.get_child(MAX_PLATFORM_SEGMENTS + k) as CollisionShape2D).disabled = true
		
		# 左墙: 实体墙
		var si_l = MAX_PLATFORM_SEGMENTS * 2
		var col_l = primary_wall.get_child(si_l) as CollisionShape2D
		col_l.position = Vector2(-w / 2.0 + wall_thickness / 2.0, 0)
		(col_l.shape as RectangleShape2D).size = Vector2(wall_thickness, h)
		col_l.rotation = 0.0
		col_l.one_way_collision = false
		col_l.disabled = false
		
		# 右墙: 实体墙
		var si_r = MAX_PLATFORM_SEGMENTS * 2 + 1
		var col_r = primary_wall.get_child(si_r) as CollisionShape2D
		col_r.position = Vector2(w / 2.0 - wall_thickness / 2.0, 0)
		(col_r.shape as RectangleShape2D).size = Vector2(wall_thickness, h)
		col_r.rotation = 0.0
		col_r.one_way_collision = false
		col_r.disabled = false
		
		# ── Step 2b: 虚空填充 (AABB 内未被窗口覆盖的区域) ──
		# 收集组内所有窗口的矩形
		var grp_rects: Array[Rect2] = []
		for m_idx in members:
			grp_rects.append(local_rects[m_idx])
		var void_rects: Array[Rect2] = _compute_void_rects(grp_rects, aabb)
		
		# 用组内其他 ghost_wall 的碰撞体来填充虚空
		var filler_slot := 0  # 当前使用的填充碰撞体计数
		for m in range(1, members.size()):
			var filler_idx = members[m]
			var fw = ghost_walls[filler_idx]
			_ensure_children(fw)
			handled[filler_idx] = true
			
			# 将作为容器的父节点重置到世界原点，使得子节点局部坐标等于全局坐标
			fw.position = Vector2.ZERO
			
			# 充分利用每个备用的 ghost_wall 中的所有碰撞子节点 (CHILDREN_PER_WALL 个)
			for k in range(fw.get_child_count()):
				var col = fw.get_child(k) as CollisionShape2D
				if filler_slot < void_rects.size():
					var vr = void_rects[filler_slot]
					col.position = vr.position + vr.size / 2.0
					(col.shape as RectangleShape2D).size = vr.size
					col.rotation = 0.0
					col.one_way_collision = false
					col.disabled = false
					filler_slot += 1
				else:
					col.disabled = true
		
		# 如果虚空矩形数量超过可用填充插槽，后续的虚空无法填充 (可接受)
		# 如果还有未使用的组内成员，全部禁用
		for m in range(1, members.size()):
			var filler_idx = members[m]
			if not handled[filler_idx]:
				var fw = ghost_walls[filler_idx]
				_ensure_children(fw)
				for k in range(fw.get_child_count()):
					(fw.get_child(k) as CollisionShape2D).disabled = true
				handled[filler_idx] = true
	
	# ── Step 3: 未被分组处理的窗口 (最大化窗口等) → 禁用所有碰撞体 ──
	for idx in range(count):
		if handled[idx]:
			continue
		var w2 = ghost_walls[idx]
		_ensure_children(w2)
		w2.position = local_rects[idx].position + local_rects[idx].size / 2.0
		for k in range(w2.get_child_count()):
			(w2.get_child(k) as CollisionShape2D).disabled = true

## 计算 AABB 内未被任何窗口覆盖的虚空矩形 (X-sweep 算法)
func _compute_void_rects(rects: Array[Rect2], aabb: Rect2) -> Array[Rect2]:
	# 收集所有 X 边界
	var x_edges: Array[float] = [aabb.position.x, aabb.end.x]
	for r in rects:
		x_edges.append(r.position.x)
		x_edges.append(r.end.x)
	x_edges.sort()
	# 去重 (容差 2px)
	var xs: Array[float] = []
	for x in x_edges:
		if xs.is_empty() or abs(x - xs.back()) > 2.0:
			xs.append(x)
	
	var voids: Array[Rect2] = []
	for j in range(xs.size() - 1):
		var x_left = xs[j]
		var x_right = xs[j + 1]
		if x_right - x_left < 5.0:
			continue
		var x_mid = (x_left + x_right) / 2.0
		
		# 找出在这个 X 位置被窗口覆盖的 Y 范围
		var covered: Array = []
		for r in rects:
			if r.position.x <= x_mid and r.end.x >= x_mid:
				covered.append([r.position.y, r.end.y])
		covered.sort()
		
		# 合并 Y 覆盖区间
		var merged: Array = []
		for c in covered:
			if merged.is_empty() or c[0] > merged.back()[1]:
				merged.append([c[0], c[1]])
			else:
				merged[merged.size() - 1] = [merged.back()[0], maxf(merged.back()[1], c[1])]
		
		# AABB Y 范围中未被覆盖的部分 = 虚空
		var prev_y = aabb.position.y
		for c in merged:
			if c[0] > prev_y + 5.0:
				voids.append(Rect2(x_left, prev_y, x_right - x_left, c[0] - prev_y))
			prev_y = maxf(prev_y, c[1])
		if aabb.end.y > prev_y + 5.0:
			voids.append(Rect2(x_left, prev_y, x_right - x_left, aabb.end.y - prev_y))
	
	return voids

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

# ── 鼠标穿透管理 ──

var _last_region_key: String = ""
var _passthrough_timer: float = 0.0
# 穿透区域刷新限流：DWM 重组合是头号性能杀手;
# 渲染跑 120fps，穿透检测只需 ~60hz 即可（延迟 ≤16ms 人眼不可感知）
const PASSTHROUGH_INTERVAL := 0.016

func _process(delta: float) -> void:
	# 全屏锁定时不刷新穿透 (保持全窗口穿透)
	if is_instance_valid(pet_instance) and pet_instance.fullscreen_locked:
		return
	if is_dragging or is_menu_open:
		return
	_passthrough_timer += delta
	if _passthrough_timer >= PASSTHROUGH_INTERVAL:
		_passthrough_timer = 0.0
		_update_passthrough_box()

func _update_passthrough_state() -> void:
	if is_dragging or is_menu_open:
		# 拖拽/菜单打开时: 清除区域限制，整个窗口可见可交互
		if win_manager and win_manager.has_method("ClearWindowRegion"):
			win_manager.call("ClearWindowRegion")
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
		_last_region_key = ""
		_update_passthrough_box()

func _update_passthrough_box() -> void:
	# 为每个宠物实例生成独立的栅格对齐矩形
	var rects: Array[Rect2i] = []
	for p in pet_instances:
		if not is_instance_valid(p):
			continue
		var r: Rect2
		if p.has_method("get_render_rect"):
			r = p.get_render_rect()
		else:
			var pos := p.global_position
			r = Rect2(pos - Vector2(50, 50), Vector2(100, 100))
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		# 8 像素栅格对齐 (减少刷新频率)
		var sx := int(r.position.x / 8.0) * 8
		var sy := int(r.position.y / 8.0) * 8
		var sw := int(r.size.x / 8.0) * 8 + 16
		var sh := int(r.size.y / 8.0) * 8 + 16
		rects.append(Rect2i(sx, sy, sw, sh))
	
	if rects.is_empty():
		return
	
	# 变化检测 (避免无意义的 DWM 重组合)
	var key := ""
	for rect in rects:
		key += str(rect) + ";"
	if key == _last_region_key:
		return
	_last_region_key = key
	
	# 优先使用 C# 层 CombineRgn 实现真正的多矩形独立区域
	if win_manager and win_manager.has_method("SetWindowRegion"):
		var typed_rects := Rect2iArrayToGodotArray(rects)
		win_manager.call("SetWindowRegion", typed_rects)
	else:
		# 回退: 合并为单个 AABB (间隙会被阻挡，但至少可用)
		var merged := rects[0]
		for i in range(1, rects.size()):
			merged = merged.merge(rects[i])
		var polygon := PackedVector2Array([
			Vector2(merged.position),
			Vector2(merged.end.x, merged.position.y),
			Vector2(merged.end),
			Vector2(merged.position.x, merged.end.y),
		])
		DisplayServer.window_set_mouse_passthrough(polygon)

## 将 GDScript Array[Rect2i] 转换为 C# 可接收的 Godot.Collections.Array<Rect2I>
func Rect2iArrayToGodotArray(rects: Array[Rect2i]) -> Array:
	var arr: Array[Rect2i] = []
	arr.assign(rects)
	return arr

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
	# 手动切安静待命时，所有宠物也自动走向最近的屏幕边缘
	if mode == 1:
		for p in pet_instances:
			if is_instance_valid(p):
				p.transition_to("retreat")

## 任务栏样式守护: 如果引擎意外重置了 WS_EX_TOOLWINDOW，重新推入
func _guard_taskbar_style() -> void:
	if win_manager and win_manager.has_method("EnsureHiddenFromTaskbar"):
		var fixed: bool = win_manager.call("EnsureHiddenFromTaskbar")
		if fixed:
			print("[DesktopPet] 任务栏样式守护：已自动修复 ToolWindow 标记")

func _on_fullscreen_locked_changed(locked: bool) -> void:
	if locked:
		# 整个窗口鼠标穿透 (宠物仍然可见，但所有点击穿透到下层 app)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
		print("[DesktopPet] 全屏锁定：鼠标穿透已启用")
	else:
		# 关闭窗口级穿透，恢复正常的区域穿透模式
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false)
		_update_passthrough_state()
		print("[DesktopPet] 全屏解锁：鼠标交互已恢复")

# ── 全屏自动检测 ──

func _check_fullscreen() -> void:
	if not win_manager:
		return
	# 拖拽中跳过检测 (拖动宠物会让宠物窗口抢前台，等松手后再检测)
	if is_dragging:
		return
	
	# 冷却期递减
	if _fs_exit_cooldown > 0.0:
		_fs_exit_cooldown -= 1.5  # 每次检测减去 timer 间隔
	
	var is_fs: bool = win_manager.call("IsUserInFullscreen")
	
	# 进入计数
	if is_fs:
		_fs_confirm_count += 1
		_fs_exit_count = 0  # 重置退出计数
	else:
		_fs_exit_count += 1
		_fs_confirm_count = 0  # 重置进入计数
	
	# 进入全屏：需连续 N 次确认 + 冷却期已过
	if _fs_confirm_count >= FS_ENTER_THRESHOLD and not _was_fullscreen:
		# 冷却期内忽略 (防止频繁进出全屏反复触发)
		if _fs_exit_cooldown > 0.0:
			_fs_confirm_count = 0
			return
		print("[DesktopPet] 全屏已确认 (连续 ", _fs_confirm_count, " 次)")
		_was_fullscreen = true
		_on_fullscreen_entered()
	# 退出全屏：需连续 N 次确认
	elif _fs_exit_count >= FS_EXIT_THRESHOLD and _was_fullscreen:
		print("[DesktopPet] 全屏退出已确认")
		_was_fullscreen = false
		_on_fullscreen_exited()

func _on_fullscreen_entered() -> void:
	# 同步全屏标记到所有 pet
	for p in pet_instances:
		if is_instance_valid(p):
			p.quiet_by_fullscreen = true
	
	var now = Time.get_ticks_msec() / 1000.0
	if behavior_mode == 0:
		if now - _fs_last_bubble_time >= FS_BUBBLE_MIN_INTERVAL:
			EventBus.show_reminder_bubble.emit("主人要专注了吗？我去角落待着~")
			_fs_last_bubble_time = now
		behavior_mode = 1
		EventBus.behavior_mode_changed.emit(1)
	
	# 所有宠物走边缘
	for p in pet_instances:
		if is_instance_valid(p):
			p.transition_to("retreat")
	
	_quiet_by_fullscreen = true

func _on_fullscreen_exited() -> void:
	if not _quiet_by_fullscreen:
		return
	_quiet_by_fullscreen = false
	_fs_exit_cooldown = FS_EXIT_COOLDOWN_DURATION
	# 同步全屏标记到所有 pet + 解锁鼠标交互
	for p in pet_instances:
		if is_instance_valid(p):
			p.quiet_by_fullscreen = false
			p.fullscreen_locked = false
	EventBus.fullscreen_locked_changed.emit(false)
	var now = Time.get_ticks_msec() / 1000.0
	if now - _fs_last_bubble_time >= FS_BUBBLE_MIN_INTERVAL:
		EventBus.show_reminder_bubble.emit("主人忙完了？😊")
		_fs_last_bubble_time = now
	behavior_mode = 0
	EventBus.behavior_mode_changed.emit(0)
	for p in pet_instances:
		if is_instance_valid(p):
			p.transition_to("idle")

# ── 告别退出 ──

var _is_quitting := false  # 防止重复触发告别流程

## 播放告别动画后退出: 宠物说一句告别的话 → 等待落地 → 滚向屏幕边缘外 → 渐隐消失 → 退出程序
func quit_with_farewell() -> void:
	if _is_quitting:
		return
	_is_quitting = true
	
	var farewell_lines := [
		"主人再见！我去休息啦~ 🌙",
		"拜拜~ 下次见面要摸摸我哦！",
		"困了困了... 晚安主人 😴",
		"好的！我先去充个电~ ⚡",
		"下次再来陪你玩！再见~ 👋",
	]
	var line = farewell_lines[randi() % farewell_lines.size()]
	EventBus.show_reminder_bubble.emit(line)
	
	# 解除所有宠物的锁定状态
	for p in pet_instances:
		if is_instance_valid(p):
			p.fullscreen_locked = false
			p.quiet_by_fullscreen = false
			p.behavior_mode = 1
	EventBus.fullscreen_locked_changed.emit(false)
	
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

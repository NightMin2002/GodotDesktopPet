# main.gd — 启动场景主脚本
# 职责: 设置透明窗口、创建屏幕边界墙、实例化宠物、管理鼠标穿透区域
extends Node2D

var pet_scene := preload("res://entities/pet/pet.tscn")
var pet_instance: RigidBody2D
var screen_rect: Rect2i
var boundary_size: Vector2  # 实际使用的边界尺寸 (视口坐标系)
var is_dragging := false
var is_menu_open := false

# -- 双端架构 C# 桥接池 --
var win_manager: Node
var ghost_walls: Array[StaticBody2D] = []

func _ready() -> void:
	# ── 性能调频 ──
	Engine.max_fps = 120
	Engine.physics_ticks_per_second = 120
	
	_setup_window()
	# 等几帧，确保窗口和视口尺寸完全同步
	await get_tree().process_frame
	await get_tree().process_frame
	_create_boundaries()
	_spawn_pet()
	
	# 装载 C# 外挂底层
	if ResourceLoader.exists("res://interop/WindowsManager.cs"):
		win_manager = load("res://interop/WindowsManager.cs").new()
		add_child(win_manager)
		
		# 通知操作系统把这个程序从底部任务栏抹掉
		if win_manager.has_method("HideFromTaskbar"):
			win_manager.call("HideFromTaskbar")
			print("[DesktopPet] 已切入暗影模式：任务栏图标已擦除")
		
		# 提升进程优先级，对抗游戏等高占用程序的 CPU/GPU 资源抢夺
		if win_manager.has_method("BoostProcessPriority"):
			win_manager.call("BoostProcessPriority")
			print("[DesktopPet] 进程优先级已提升至 Above Normal")
		
		# 开启神级同步雷达 (每 0.1s 侦测一次全体桌面窗口变化)
		var sync_timer = Timer.new()
		sync_timer.wait_time = 0.1
		sync_timer.autostart = true
		sync_timer.timeout.connect(_sync_ghost_walls)
		add_child(sync_timer)
		print("[DesktopPet] C# Interop 幽灵侦测雷达已启动！")
	
	EventBus.drag_started.connect(_on_drag_started)
	EventBus.drag_ended.connect(_on_drag_ended)
	EventBus.context_menu_toggled.connect(_on_context_menu_toggled)
	
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

func _sync_ghost_walls() -> void:
	if not is_instance_valid(win_manager): return
	
	# 从 C# 层获取 Z-Order 从高→低排列的桌面窗口矩形
	var rects: Array = win_manager.call("GetVisibleWindowRects")
	var count = rects.size()
	
	# 动态伸缩对象池 — 每面墙 = 3 个顶部分段 + 3 个底部分段 = 6 个碰撞器
	var children_per_wall = MAX_PLATFORM_SEGMENTS * 2
	while ghost_walls.size() < count:
		var wall = StaticBody2D.new()
		for k in range(children_per_wall):
			var col = CollisionShape2D.new()
			col.shape = RectangleShape2D.new()
			col.one_way_collision = true
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
		
	# 实体化映射墙面
	var floor_thickness = 10.0
	for i in range(count):
		var lr = local_rects[i]
		var wall = ghost_walls[i]
		
		# 兼容旧池对象热重载：确保子节点数量正确
		while wall.get_child_count() < children_per_wall:
			var col = CollisionShape2D.new()
			col.shape = RectangleShape2D.new()
			col.one_way_collision = true
			col.disabled = true
			wall.add_child(col)
		
		wall.position = lr.position + lr.size / 2.0
		
		# ─── 分段裁剪算法 ───
		# 从完整踏板宽度出发，逐一扣除被 Z-Order 更高窗口覆盖的水平区间
		# 剩余的暴露区间各自成为独立碰撞体
		var win_left = lr.position.x
		var win_right = lr.position.x + lr.size.x
		var top_y = lr.position.y
		var bottom_y = lr.position.y + lr.size.y
		
		var top_segs = _compute_exposed_segments(win_left, win_right, top_y, local_rects, i)
		var bottom_segs = _compute_exposed_segments(win_left, win_right, bottom_y, local_rects, i)
		
		# 映射分段到碰撞子节点
		var wall_cx = lr.position.x + lr.size.x / 2.0
		var top_rel_y = -lr.size.y / 2.0 + floor_thickness / 2.0
		var bot_rel_y = lr.size.y / 2.0 - floor_thickness / 2.0
		_apply_platform_segments(wall, 0, top_segs, wall_cx, top_rel_y, floor_thickness)
		_apply_platform_segments(wall, MAX_PLATFORM_SEGMENTS, bottom_segs, wall_cx, bot_rel_y, floor_thickness)

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
func _apply_platform_segments(wall: StaticBody2D, child_offset: int, segs: Array, wall_cx: float, rel_y: float, thickness: float) -> void:
	for k in range(MAX_PLATFORM_SEGMENTS):
		var col = wall.get_child(child_offset + k) as CollisionShape2D
		if k < segs.size():
			var seg = segs[k]
			var seg_cx = (seg[0] + seg[1]) / 2.0
			col.position = Vector2(seg_cx - wall_cx, rel_y)
			(col.shape as RectangleShape2D).size = Vector2(seg[1] - seg[0], thickness)
			col.disabled = false
		else:
			col.disabled = true


# ── 宠物实例化 ──

func _spawn_pet() -> void:
	pet_instance = pet_scene.instantiate()
	pet_instance.screen_rect = screen_rect
	pet_instance.boundary_size = boundary_size
	# 从视口上方 1/3 处中央掉落
	pet_instance.position = Vector2(
		boundary_size.x / 2.0,
		boundary_size.y / 3.0
	)
	add_child(pet_instance)
	
	print("[DesktopPet] 宠物生成于: ", pet_instance.position)

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

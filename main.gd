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
		
		# [新增指令]：通知操作系统把这个程序从底部任务栏抹掉
		if win_manager.has_method("HideFromTaskbar"):
			win_manager.call("HideFromTaskbar")
			print("[DesktopPet] 已切入暗影模式：任务栏图标已擦除")
		
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
		
		# 在 Godot 4.3+ 中，menu 属性通常要求提供 NodePath 或者是直接引用（视具体小版本定义）
		tray.menu = tray_menu.get_path()
		add_child(tray)
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

func _sync_ghost_walls() -> void:
	if not is_instance_valid(win_manager): return
	
	# 从 C# DLL 中直接抽出操作系统内存级的桌面窗口边界数据
	var rects: Array = win_manager.call("GetVisibleWindowRects")
	var count = rects.size()
	
	# 动态伸缩对象池，防止高频 new/free 造成性能崩塌
	while ghost_walls.size() < count:
		var wall = StaticBody2D.new()
		
		# 顶部标题栏踏板
		var col_top = CollisionShape2D.new()
		col_top.shape = RectangleShape2D.new()
		col_top.one_way_collision = true
		wall.add_child(col_top)
		
		# 底部边缘踏板
		var col_bottom = CollisionShape2D.new()
		col_bottom.shape = RectangleShape2D.new()
		col_bottom.one_way_collision = true
		wall.add_child(col_bottom)
		
		var mat = PhysicsMaterial.new()
		mat.bounce = 0.2
		mat.friction = 0.8
		wall.physics_material_override = mat
		
		add_child(wall)
		ghost_walls.append(wall)
		
	while ghost_walls.size() > count:
		var wall = ghost_walls.pop_back()
		wall.queue_free()
		
	# 实体化映射墙面
	for i in range(count):
		var desk_rect = rects[i] as Rect2i
		# 从操作系统全局桌面坐标，映射回游戏引擎相对自身主屏幕的坐标矩阵
		var local_pos = Vector2(desk_rect.position.x - screen_rect.position.x, desk_rect.position.y - screen_rect.position.y)
		var local_size = Vector2(desk_rect.size.x, desk_rect.size.y)
		
		var wall = ghost_walls[i]
		wall.position = local_pos + local_size / 2.0
		var floor_thickness = 10.0
		
		# 更新顶部标题栏位置（相对于墙体中心上移）
		var shape_top = wall.get_child(0) as CollisionShape2D
		shape_top.position = Vector2(0, -local_size.y / 2.0 + floor_thickness / 2.0)
		(shape_top.shape as RectangleShape2D).size = Vector2(local_size.x, floor_thickness)
		
		# 更新底部边缘位置（相对于墙体中心下移）
		var shape_bottom = wall.get_child(1) as CollisionShape2D
		shape_bottom.position = Vector2(0, local_size.y / 2.0 - floor_thickness / 2.0)
		(shape_bottom.shape as RectangleShape2D).size = Vector2(local_size.x, floor_thickness)

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

func _process(_delta: float) -> void:
	if is_dragging or is_menu_open:
		return
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

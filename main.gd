# main.gd — 启动场景主脚本
# 职责: 设置透明窗口、创建屏幕边界墙、实例化宠物、管理鼠标穿透区域
extends Node2D

var pet_scene := preload("res://entities/pet/pet.tscn")
var pet_instance: RigidBody2D
var screen_rect: Rect2i
var boundary_size: Vector2  # 实际使用的边界尺寸 (视口坐标系)
var is_dragging := false
var is_menu_open := false

func _ready() -> void:
	_setup_window()
	# 等几帧，确保窗口和视口尺寸完全同步
	await get_tree().process_frame
	await get_tree().process_frame
	_create_boundaries()
	_spawn_pet()
	
	EventBus.drag_started.connect(_on_drag_started)
	EventBus.drag_ended.connect(_on_drag_ended)
	EventBus.context_menu_toggled.connect(_on_context_menu_toggled)

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
		_update_passthrough_box()

func _update_passthrough_box() -> void:
	if not is_instance_valid(pet_instance):
		return
	
	var pos := pet_instance.global_position
	var padding := 50.0
	
	var polygon := PackedVector2Array([
		Vector2(pos.x - padding, pos.y - padding),
		Vector2(pos.x + padding, pos.y - padding),
		Vector2(pos.x + padding, pos.y + padding),
		Vector2(pos.x - padding, pos.y + padding),
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

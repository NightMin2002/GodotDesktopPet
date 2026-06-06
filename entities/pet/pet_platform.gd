# pet_platform.gd — 共享悬浮踏板管理器 (RefCounted)
# 从 PetGaming 和 PetHoloScreen 提取的公共踏板逻辑
# 职责: 踏板创建/移除/升降驱动 + 宠物锁定/解锁
class_name PetPlatform extends RefCounted

var _platform: StaticBody2D = null
var _lift_phase: int = 0      # 0=空闲, 1=上升中, 2=已到位
var _lift_target_y: float = 0.0
var _using_existing_support: bool = false

## 踏板是否活跃 (已创建且在升降或已到位)
var is_active: bool:
	get: return _lift_phase > 0 or _using_existing_support

## 是否已升到位
var is_lifted: bool:
	get: return _lift_phase == 2 or _using_existing_support

# ── 公开接口 ──

## 锁定宠物: 取消空间跳跃 + 高阻尼 + 切 idle + 生成踏板
func lock_pet(pet: RigidBody2D) -> void:
	if pet.free_roam_sys.active:
		pet.free_roam_sys.finish()
	var use_existing_support = pet.free_roam_sys.settled and is_instance_valid(pet.free_roam_sys._settled_plat)
	pet.physics.apply("platform_lock")
	pet.linear_velocity = Vector2.ZERO
	pet.angular_velocity = 0.0
	if pet.current_state_name != "idle":
		pet.transition_to("idle")
	if use_existing_support:
		_using_existing_support = true
		_platform = null
		_lift_phase = 0
		pet.gravity_scale = 0.0
		return
	spawn(pet)

## 解锁宠物: 移除踏板 + 恢复重力 (不含状态切换, 调用方自行处理)
func unlock_pet(pet: RigidBody2D) -> void:
	remove(pet)

## 生成踏板 (宠物脚下, 缓缓升起)
func spawn(pet: RigidBody2D) -> void:
	var parent = pet.get_parent()
	if not parent:
		return
	_using_existing_support = false
	var plat_y = pet.global_position.y + pet.PET_RADIUS * pet.gravity_sign
	var body = StaticBody2D.new()
	body.position = Vector2(pet.global_position.x, plat_y)
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(pet.PET_RADIUS * 2.0, 8.0)
	col.shape = shape
	col.one_way_collision = true
	if pet.anti_gravity:
		col.rotation = PI
	body.add_child(col)
	var visual = FreeRoamSystem.PlatformVisual.new()
	visual.platform_width = pet.PET_RADIUS * 2.0
	visual.platform_color = pet.palette.shift_color(Color(0.2, 0.6, 1.0, 0.6))
	visual.quiet = true
	body.add_child(visual)
	parent.add_child(body)
	body.modulate.a = 0.0
	var tween = body.create_tween()
	tween.tween_property(body, "modulate:a", 1.0, 0.3)
	_platform = body
	_lift_target_y = plat_y - 15.0 * pet.gravity_sign
	_lift_phase = 1
	pet.gravity_scale = 0.0

## 移除踏板 (禁用碰撞 + 淡出 + 恢复重力)
func remove(pet: RigidBody2D) -> void:
	_lift_phase = 0
	_using_existing_support = false
	pet.gravity_scale = pet.gravity_sign
	if is_instance_valid(_platform):
		for child in _platform.get_children():
			if child is CollisionShape2D:
				child.disabled = true
		var plat = _platform
		_platform = null
		var tween = plat.create_tween()
		tween.tween_property(plat, "modulate:a", 0.0, 0.3)
		tween.finished.connect(func():
			if is_instance_valid(plat):
				plat.queue_free()
		)

## 每帧更新: 驱动升降 + 位置锁定
func update(pet: RigidBody2D, delta: float) -> void:
	if _using_existing_support:
		pet.linear_velocity = Vector2.ZERO
		pet.angular_velocity = 0.0
		return
	if _lift_phase == 1 and is_instance_valid(_platform):
		var lift_speed = 80.0
		_platform.position.y -= lift_speed * delta * pet.gravity_sign
		pet.global_position.y = _platform.position.y - (pet.PET_RADIUS + 5.0) * pet.gravity_sign
		var dist = (_platform.position.y - _lift_target_y) * pet.gravity_sign
		if dist <= 0.0:
			_platform.position.y = _lift_target_y
			pet.global_position.y = _lift_target_y - (pet.PET_RADIUS + 5.0) * pet.gravity_sign
			_lift_phase = 2
	elif _lift_phase == 2 and is_instance_valid(_platform):
		pet.linear_velocity = Vector2.ZERO
		pet.global_position.y = _platform.position.y - (pet.PET_RADIUS + 5.0) * pet.gravity_sign

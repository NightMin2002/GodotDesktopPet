# idle.gd — 待机状态
# 宠物立在原地，随机时间后转入 Walk 或 Jump
# 如果附近有漫步中的同伴滚来，跳起让路 (跳绳效果)
class_name StateIdle
extends PetState

var idle_timer: float = 0.0
var idle_duration: float = 0.0
var _dodge_cooldown: float = 0.0  # 让路跳跃冷却

func enter() -> void:
	idle_duration = randf_range(1.0, 4.0)
	idle_timer = 0.0
	_dodge_cooldown = 0.0
	if pet:
		pet.linear_damp = 0.8
		pet.angular_damp = 1.0
		if pet.behavior_mode == 1:
			pet.linear_damp = 5.0
			pet.angular_damp = 8.0

func exit() -> void:
	if pet:
		pet.linear_damp = 0.5

func process(delta: float) -> void:
	idle_timer += delta
	
	# ── 安静模式位置锁定：持续微校正物理漂移 ──
	if pet.behavior_mode == 1 and pet.has_meta("retreat_target_x"):
		var target_x: float = pet.get_meta("retreat_target_x")
		var drift := pet.global_position.x - target_x
		if absf(drift) > 2.0:
			# 轻柔吸附回槽位 (速率8让对齐干脆又不失柔滑，约0.3秒归位)
			pet.global_position.x = lerpf(pet.global_position.x, target_x, 8.0 * delta)
			pet.linear_velocity.x *= 0.8  # 同步衰减水平速度
	
	if idle_timer >= idle_duration:
		if pet.behavior_mode == 1:
			if not _is_at_slot():
				pet.transition_to("retreat")
				return
			idle_timer = 0.0
			idle_duration = randf_range(1.0, 3.0)
			return
		# 正在注视同伴时不跳动，安静地看着
		if pet.eye_behavior._look_at_pet != null:
			idle_timer = 0.0
			idle_duration = randf_range(1.5, 3.0)
			return
		# 随机多巴胺路由选择 (85% 小蹦跳, 15% 大跳)
		if randf() > 0.15:
			pet.transition_to("walk")
		else:
			pet.transition_to("jump")

func physics_process(delta: float) -> void:
	if not pet: return
	
	# 检查是否还在空中
	if not pet.is_settled():
		pet.transition_to("fall")
		return
	
	# ── 跳绳让路：近距离检测到漫步中的同伴 → 跳起让路 ──
	if pet.behavior_mode == 0:
		_dodge_cooldown -= delta
		if _dodge_cooldown <= 0.0:
			var stroller = _find_approaching_stroller()
			if stroller != null:
				pet.apply_central_impulse(Vector2(0, -350.0))
				pet.apply_torque_impulse(randf_range(-800.0, 800.0))
				_dodge_cooldown = 0.5

## 检测是否有漫步中的宠物正在靠近 (120px 范围)
func _find_approaching_stroller() -> RigidBody2D:
	var parent = pet.get_parent()
	if not parent: return null
	
	for child in parent.get_children():
		if child == pet or not (child is RigidBody2D): continue
		if not is_instance_valid(child): continue
		if not ("is_strolling" in child): continue
		if not child.is_strolling: continue
		
		var dist = absf(child.global_position.x - pet.global_position.x)
		if dist > 140.0: continue
		
		# 确认对方正朝自己滚来
		var vx = child.linear_velocity.x
		var dx = pet.global_position.x - child.global_position.x
		if (vx > 10.0 and dx > 0.0) or (vx < -10.0 and dx < 0.0):
			return child
	return null

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				pet.transition_to("drag")

## 精确判定是否已停靠在分配的队列槽位上 (替代旧的模糊边缘检测)
func _is_at_slot() -> bool:
	if not pet: return false
	if pet.has_meta("retreat_target_x"):
		var target_x: float = pet.get_meta("retreat_target_x")
		return absf(pet.global_position.x - target_x) < 25.0
	# 没有分配过槽位时回退到边缘检测
	var x = pet.global_position.x
	var w = pet.boundary_size.x
	return x < 100.0 or x > w - 100.0

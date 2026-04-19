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
			pet.linear_damp = 3.0
			pet.angular_damp = 5.0

func exit() -> void:
	if pet:
		pet.linear_damp = 0.5

func process(delta: float) -> void:
	idle_timer += delta
	if idle_timer >= idle_duration:
		if pet.behavior_mode == 1:
			if not _is_near_edge():
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
				pet.apply_central_impulse(Vector2(0, -450.0))
				pet.apply_torque_impulse(randf_range(-2000.0, 2000.0))
				_dodge_cooldown = 0.5

## 检测是否有漫步中的宠物正在靠近 (150px 范围)
func _find_approaching_stroller() -> RigidBody2D:
	var parent = pet.get_parent()
	if not parent: return null
	
	for child in parent.get_children():
		if child == pet or not (child is RigidBody2D): continue
		if not is_instance_valid(child): continue
		# 安全检查：确认是宠物节点 (有 is_strolling 属性)
		if not ("is_strolling" in child): continue
		if not child.is_strolling: continue
		
		var dist = absf(child.global_position.x - pet.global_position.x)
		if dist > 150.0: continue
		
		# 确认对方正朝自己滚来
		var vx = child.linear_velocity.x
		var dx = pet.global_position.x - child.global_position.x  # 正=对方在左侧
		if (vx > 10.0 and dx > 0.0) or (vx < -10.0 and dx < 0.0):
			return child
	return null

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				pet.transition_to("drag")

func _is_near_edge() -> bool:
	if not pet: return false
	var x = pet.global_position.x
	var w = pet.boundary_size.x
	return x < 100.0 or x > w - 100.0

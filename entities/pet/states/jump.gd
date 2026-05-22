# jump.gd — 大跳状态
# 宠物获得较大的向上冲量，在空中划出弧线后落地
class_name StateJump
extends PetState

func enter() -> void:
	if pet:
		pet.physics.apply("jump")
		
		# 大跳：确定方向
		var hop_dir = [-1.0, 1.0].pick_random()
		
		# 边缘检测
		var x = pet.global_position.x
		var w = pet.boundary_size.x
		if x < 100.0:
			hop_dir = 1.0
		elif x > w - 100.0:
			hop_dir = -1.0
		
		# 先看方向再跳 (缓冲到期后自动调用 _execute_jump)
		pet.movement.start(Vector2(hop_dir, 0), _execute_jump.bind(hop_dir))

func exit() -> void:
	if pet:
		pet.movement.finish()

## 缓冲到期后执行大跳冲量 (由 PetMovement 回调)
func _execute_jump(hop_dir: float) -> void:
	var burst_dir = Vector2(hop_dir * randf_range(0.6, 1.4), -randf_range(2.0, 3.0) * pet.gravity_sign).normalized()
	var force = randf_range(900.0, 1500.0)
	pet.apply_central_impulse(burst_dir * force)
	# 适度旋转 (空中翻滚的视觉效果)
	pet.apply_torque_impulse(hop_dir * randf_range(8000.0, 18000.0))

func process(_delta: float) -> void:
	pass

func physics_process(_delta: float) -> void:
	if not pet:
		return
	# 缓冲期 + 未起跳: 不检测落地
	if pet.movement.in_look_ahead: return
	
	# 落地稳定后回到 Idle
	if pet.is_settled():
		pet.transition_to("idle")

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 半空中也可以把它拽住！
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				pet.transition_to("drag")

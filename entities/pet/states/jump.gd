# jump.gd — 高能弹跳状态
# 球体获得强大的向上冲量和旋转扭矩，在屏幕内弹跳碰撞直到动能耗尽
class_name StateJump
extends PetState

func enter() -> void:
	if pet:
		# 降低阻尼，让它在空中能保持动能疯狂弹跳
		pet.linear_damp = 0.5
		
		# 朝上并且附带左/右的一个随机角度开火
		var burst_dir = Vector2(randf_range(-1.2, 1.2), -randf_range(1.5, 3.0)).normalized()
		var force = randf_range(800.0, 1600.0)  # 物理冲量，直接转化为瞬间速度
		pet.apply_central_impulse(burst_dir * force)
		
		# 极度疯狂的自旋扭矩冲量
		var spin = randf_range(-100000.0, 100000.0)
		pet.apply_torque_impulse(spin)

func exit() -> void:
	pass

func process(_delta: float) -> void:
	pass

func physics_process(_delta: float) -> void:
	if not pet:
		return
		
	# 只要跳跃/撞击结束后速度低于阈值一定时间，就会判定为落实地并重归闲置
	if pet.is_settled():
		pet.transition_to("idle")

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 半空中也可以把它拽住！
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				pet.transition_to("drag")

# walk.gd — 小蹦跳状态 (Hop)
# 宠物通过小幅度蹦跳向一个方向移动，落地后回到 Idle
class_name StateWalk
extends PetState

func enter() -> void:
	if pet:
		pet.linear_damp = 0.3   # 低阻尼，空中保持惯性
		pet.angular_damp = 0.5  # 适度角阻尼，落地后自然停转
		
		# 小蹦跳：温柔的向上冲量 + 随机水平方向
		var hop_dir = [-1.0, 1.0].pick_random()
		
		# 边缘检测：如果靠近边缘就往回跳
		var x = pet.global_position.x
		var w = pet.boundary_size.x
		if x < 100.0:
			hop_dir = 1.0
		elif x > w - 100.0:
			hop_dir = -1.0
		
		var hop_height = randf_range(180.0, 350.0)
		var hop_horizontal = randf_range(80.0, 220.0) * hop_dir
		pet.apply_central_impulse(Vector2(hop_horizontal, -hop_height))
		
		# 轻微自然旋转 (不是驱动力，只是蹦跳时的自然翻滚)
		pet.apply_torque_impulse(hop_dir * randf_range(2000.0, 6000.0))

func exit() -> void:
	pass

func process(_delta: float) -> void:
	pass

func physics_process(_delta: float) -> void:
	if not pet:
		return
	
	# 落地稳定后回到 Idle
	if pet.is_settled():
		pet.transition_to("idle")

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				pet.transition_to("drag")

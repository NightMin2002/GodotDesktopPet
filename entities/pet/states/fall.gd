# fall.gd — 自由落体状态
# 宠物被释放后在重力作用下掉落，落地稳定后回到 Idle
class_name StateFall
extends PetState

var settle_timer: float = 0.0
const SETTLE_THRESHOLD := 15.0   # 速度低于此值视为"落稳"
const SETTLE_TIME := 0.3         # 需持续稳定这么久才算真正落地

func enter() -> void:
	settle_timer = 0.0
	if pet:
		pet.linear_damp = 0.5
		pet.gravity_scale = pet.gravity_sign  # 尊重反重力模式

func exit() -> void:
	pass

func process(delta: float) -> void:
	if not pet:
		return
	
	# 检查是否已稳定
	if pet.linear_velocity.length() < SETTLE_THRESHOLD:
		settle_timer += delta
		if settle_timer >= SETTLE_TIME:
			if pet.behavior_mode == 1:
				# 落地停稳后，获取真实的地表 X 坐标并触发全局分身排队计算
				var main_node = pet.get_tree().root.get_node_or_null("Main")
				if main_node and main_node.has_method("reorganize_quiet_queue"):
					main_node.reorganize_quiet_queue()
				
				# 手动安静待命：也走回边缘
				if pet._was_dragged_in_quiet:
					pet._was_dragged_in_quiet = false
					pet.show_local_bubble("我要回去待命啦...")
				pet.transition_to("retreat")
			else:
				pet._was_dragged_in_quiet = false
				pet.transition_to("idle")
	else:
		settle_timer = 0.0

func physics_process(_delta: float) -> void:
	pass

func input(event: InputEvent) -> void:
	# 即使在下落过程中也能被抓住
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				pet.transition_to("drag")

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
		pet.gravity_scale = 1.0

func exit() -> void:
	pass

func process(delta: float) -> void:
	if not pet:
		return
	
	# 检查是否已稳定
	if pet.linear_velocity.length() < SETTLE_THRESHOLD:
		settle_timer += delta
		if settle_timer >= SETTLE_TIME:
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
				pet.transition_to("drag")

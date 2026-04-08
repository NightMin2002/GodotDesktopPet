# idle.gd — 待机状态
# 宠物立在原地，微微呼吸晃动，随机时间后转入 Walk
class_name StateIdle
extends PetState

var idle_timer: float = 0.0
var idle_duration: float = 0.0

func enter() -> void:
	# 闲置时间大幅压缩，彻底表现出“不停歇”的多动机制
	idle_duration = randf_range(0.3, 1.5)
	idle_timer = 0.0
	# 减缓速度
	if pet:
		pet.linear_damp = 1.0
		pet.angular_damp = 1.5

func exit() -> void:
	if pet:
		pet.linear_damp = 0.5

func process(delta: float) -> void:
	idle_timer += delta
	if idle_timer >= idle_duration:
		# 随机多巴胺路由选择
		if randf() > 0.35:
			pet.transition_to("walk")
		else:
			pet.transition_to("jump")

func physics_process(_delta: float) -> void:
	# 检查是否还在空中（被弹飞等情况）
	if pet and not pet.is_settled():
		pet.transition_to("fall")

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.transition_to("drag")

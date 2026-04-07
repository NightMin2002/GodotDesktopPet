# idle.gd — 待机状态
# 宠物立在原地，微微呼吸晃动，随机时间后转入 Walk
class_name StateIdle
extends PetState

var idle_timer: float = 0.0
var idle_duration: float = 0.0

# 呼吸动画
var breath_time: float = 0.0

func enter() -> void:
	idle_duration = randf_range(2.0, 5.0)
	idle_timer = 0.0
	breath_time = 0.0
	# 减速停下
	if pet:
		pet.linear_damp = 3.0

func exit() -> void:
	if pet:
		pet.linear_damp = 0.5

func process(delta: float) -> void:
	breath_time += delta
	# 呼吸缩放效果由 pet_visuals 处理
	
	idle_timer += delta
	if idle_timer >= idle_duration:
		# 只在落地时才会走动
		if pet.is_settled():
			pet.transition_to("walk")

func physics_process(_delta: float) -> void:
	# 检查是否还在空中（被弹飞等情况）
	if pet and not pet.is_settled():
		pet.transition_to("fall")

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.transition_to("drag")

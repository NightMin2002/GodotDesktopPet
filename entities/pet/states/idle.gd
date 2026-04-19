# idle.gd — 待机状态
# 宠物立在原地，微微呼吸晃动，随机时间后转入 Walk
class_name StateIdle
extends PetState

var idle_timer: float = 0.0
var idle_duration: float = 0.0

func enter() -> void:
	# 闲置时间大幅压缩，彻底表现出"不停歇"的多动机制
	idle_duration = randf_range(0.3, 1.5)
	idle_timer = 0.0
	# 减缓速度
	if pet:
		pet.linear_damp = 1.0
		pet.angular_damp = 1.5
		# 安静模式：提高阻尼让宠物真正安静下来
		if pet.behavior_mode == 1:
			pet.linear_damp = 3.0
			pet.angular_damp = 5.0

func exit() -> void:
	if pet:
		pet.linear_damp = 0.5

func process(delta: float) -> void:
	idle_timer += delta
	if idle_timer >= idle_duration:
		# 安静待命模式
		if pet.behavior_mode == 1:
			# 还没到边缘 → 重新触发撤退 (解决中途被阻拦后不再继续的问题)
			if not _is_near_edge():
				pet.transition_to("retreat")
				return
			# 已到位 → 续空转，不自主行动
			idle_timer = 0.0
			idle_duration = randf_range(1.0, 3.0)
			return
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
				pet.get_viewport().set_input_as_handled()
				pet.transition_to("drag")

## 检测宠物是否已到达屏幕边缘附近
func _is_near_edge() -> bool:
	if not pet:
		return false
	var x = pet.global_position.x
	var w = pet.boundary_size.x
	return x < 100.0 or x > w - 100.0

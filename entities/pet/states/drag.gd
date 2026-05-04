# drag.gd — 拖拽状态
# 使用弹簧力公式模拟宠物跟随鼠标的"皮筋"效果
# F = k * displacement - c * velocity
class_name StateDrag
extends PetState

const SPRING_STIFFNESS := 80.0   # 弹簧刚度 (越大跟随越紧)
const SPRING_DAMPING := 6.0      # 阻尼系数 (越大振荡越少)
const DRAG_GRAVITY_SCALE := 0.1  # 拖拽时降低重力

var original_gravity_scale: float = 1.0
var _drag_time: float = 0.0
var _init_mouse_pos: Vector2
var _init_pet_pos: Vector2  # 拖拽起始时宠物位置 (用于判定是否真的被拖走)

func enter() -> void:
	if pet:
		original_gravity_scale = pet.gravity_scale
		pet.gravity_scale = DRAG_GRAVITY_SCALE
		pet.linear_damp = 0.5
		_drag_time = 0.0
		_init_mouse_pos = pet.get_global_mouse_position()
		_init_pet_pos = pet.global_position
		# 中断正在进行的攀升/下降 (拖拽打断自由移动)
		if pet._roam_active:
			pet._roam_finish()
		EventBus.drag_started.emit()

func process(delta: float) -> void:
	_drag_time += delta

func exit() -> void:
	if pet:
		pet.gravity_scale = original_gravity_scale
		# 安静模式下：只有宠物真正被拖离原位时才记录 (poke 原地点击不触发吐槽)
		if pet.is_quiet_behavior():
			var moved = pet.global_position.distance_to(_init_pet_pos)
			if moved > 30.0:
				pet._was_dragged_in_quiet = true
		EventBus.drag_ended.emit()

func physics_process(_delta: float) -> void:
	if not pet:
		return
	
	var mouse_pos = pet.get_global_mouse_position()
	var displacement = mouse_pos - pet.global_position
	
	# 弹簧力: F = k * x - c * v
	var spring_force = displacement * SPRING_STIFFNESS
	var damping_force = -pet.linear_velocity * SPRING_DAMPING
	
	pet.apply_central_force(spring_force + damping_force)

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# 松开鼠标前判断是否是“戳一戳（Poke）”
			var dist = pet.get_global_mouse_position().distance_to(_init_mouse_pos)
			if _drag_time <= 0.25 and dist < 12.0:
				_handle_poke()
			# 松开鼠标 → 释放宠物，进入自由落体
			pet.transition_to("fall")

func _handle_poke() -> void:
	pet.handle_poke()

# drag.gd — 拖拽状态
# 使用弹簧力公式模拟宠物跟随鼠标的"皮筋"效果
# F = k * displacement - c * velocity
class_name StateDrag
extends PetState

const SPRING_STIFFNESS := 80.0   # 弹簧刚度 (越大跟随越紧)
const SPRING_DAMPING := 6.0      # 阻尼系数 (越大振荡越少)
const DRAG_GRAVITY_SCALE := 0.1  # 拖拽时降低重力

var original_gravity_scale: float = 1.0

func enter() -> void:
	if pet:
		original_gravity_scale = pet.gravity_scale
		pet.gravity_scale = DRAG_GRAVITY_SCALE
		pet.linear_damp = 0.5
		EventBus.drag_started.emit()

func exit() -> void:
	if pet:
		pet.gravity_scale = original_gravity_scale
		EventBus.drag_ended.emit()

func physics_process(_delta: float) -> void:
	if not pet:
		return
	
	var mouse_pos = pet.get_global_mouse_position()
	
	# 封闭模式下，限制弹簧目标点不超出封闭区域
	if pet.window_mode == 1 and pet.confined_rect.size != Vector2.ZERO:  # CONFINED
		var r = pet.confined_rect
		var margin = pet.PET_RADIUS + 5.0  # 留出球体半径的余量
		mouse_pos.x = clampf(mouse_pos.x, r.position.x + margin, r.end.x - margin)
		mouse_pos.y = clampf(mouse_pos.y, r.position.y + margin, r.end.y - margin)
	
	var displacement = mouse_pos - pet.global_position
	
	# 弹簧力: F = k * x - c * v
	var spring_force = displacement * SPRING_STIFFNESS
	var damping_force = -pet.linear_velocity * SPRING_DAMPING
	
	pet.apply_central_force(spring_force + damping_force)

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# 松开鼠标 → 释放宠物，进入自由落体
			pet.transition_to("fall")

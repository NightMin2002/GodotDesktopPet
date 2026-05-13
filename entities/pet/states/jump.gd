# jump.gd — 大跳状态
# 宠物获得较大的向上冲量，在空中划出弧线后落地
class_name StateJump
extends PetState

# ── 先看方向再行动 ──
var _look_delay: float = 0.0
var _hop_dir: float = 0.0
var _launched: bool = false
const LOOK_AHEAD_TIME := 0.3

func enter() -> void:
	if pet:
		pet.linear_damp = 0.2   # 空中低阻尼，保持抛物线惯性
		pet.angular_damp = 0.8  # 适度角阻尼，旋转自然衰减
		
		# 大跳：确定方向，先看再跳
		_hop_dir = [-1.0, 1.0].pick_random()
		
		# 边缘检测
		var x = pet.global_position.x
		var w = pet.boundary_size.x
		if x < 100.0:
			_hop_dir = 1.0
		elif x > w - 100.0:
			_hop_dir = -1.0
		
		# 先看向跳跃方向
		pet.eye_behavior.forced_look_dir = Vector2(_hop_dir, 0)
		_look_delay = LOOK_AHEAD_TIME
		_launched = false

func exit() -> void:
	# forced_look_dir 不在此处清零，交由 idle.enter() 的延迟机制自然过渡
	pass

func process(delta: float) -> void:
	if _look_delay > 0.0:
		_look_delay -= delta
		if _look_delay <= 0.0:
			_execute_jump()
		return

## 缓冲结束后执行大跳冲量
func _execute_jump() -> void:
	_launched = true
	var burst_dir = Vector2(_hop_dir * randf_range(0.6, 1.4), -randf_range(2.0, 3.0) * pet.gravity_sign).normalized()
	var force = randf_range(900.0, 1500.0)
	pet.apply_central_impulse(burst_dir * force)
	# 适度旋转 (空中翻滚的视觉效果)
	pet.apply_torque_impulse(_hop_dir * randf_range(8000.0, 18000.0))

func physics_process(_delta: float) -> void:
	if not pet:
		return
	# 缓冲期 + 未起跳: 不检测落地
	if not _launched: return
	
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

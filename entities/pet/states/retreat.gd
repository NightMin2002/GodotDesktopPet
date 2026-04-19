# retreat.gd — 撤退状态 (走向屏幕边缘)
# 触发安静待命时，宠物自动滚向最近的屏幕边缘，到达后切 Idle
class_name StateRetreat
extends PetState

var target_x: float = 0.0       # 目标 X 坐标 (屏幕边缘)
var direction: float = 0.0      # -1.0 左, 1.0 右
var retreat_force: float = 350.0
const ARRIVE_THRESHOLD := 20.0  # 到达边缘的判定距离 (缩紧以确保排队精准停靠)
const SLOWDOWN_DIST := 200.0    # 开始减速的距离
var _stuck_time: float = 0.0    # 防撞墙卡死计时器
var _last_stuck_x: float = 0.0  # 防撞墙位移参考点

func enter() -> void:
	if not pet:
		return
	# 计算或者读取分配好的目标 X
	var screen_width = pet.boundary_size.x
	if pet.has_meta("retreat_target_x"):
		target_x = pet.get_meta("retreat_target_x")
	else:
		var pet_x = pet.global_position.x
		if pet_x < screen_width / 2.0:
			target_x = 40.0        # 左边缘留出一个身位
		else:
			target_x = screen_width - 40.0
			
	if pet.global_position.x < target_x:
		direction = 1.0
	else:
		direction = -1.0
	_stuck_time = 0.0
	_last_stuck_x = pet.global_position.x
	# 行走时保持较高的线性阻尼，让位移主要来自扭矩+摩擦力转化
	pet.linear_damp = 1.5
	pet.angular_damp = 0.2  # 必须重置，否则从安静 idle(5.0) 转来时扭矩无效

func exit() -> void:
	if pet:
		pet.linear_damp = 0.5

func process(delta: float) -> void:
	if not pet:
		return
	# 到达目标位置 → 刹车 + 锁定 + 切换到 Idle
	var dist = absf(pet.global_position.x - target_x)
	var is_arrived = dist < ARRIVE_THRESHOLD
	
	# 如果身处 CONFINED 内部等情况被墙强行挡住
	if not is_arrived and pet.is_settled():
		_stuck_time += delta
		if _stuck_time > 0.5:
			# 每 0.5 秒检查一次绝对位移
			# 只要 0.5 秒内由于物理墙面摩擦导致位移小于 5 像素，就判定为彻底卡死
			var moved_dist = absf(pet.global_position.x - _last_stuck_x)
			if moved_dist < 5.0:
				is_arrived = true
			else:
				# 仍在有效位移中，重置参考点和计时器
				_last_stuck_x = pet.global_position.x
				_stuck_time = 0.0
	else:
		_stuck_time = 0.0
		_last_stuck_x = pet.global_position.x
		
	if is_arrived:
		# 主动刹车，防止撞墙反弹
		pet.linear_velocity = Vector2(0, pet.linear_velocity.y)
		pet.angular_velocity = 0.0
		pet.linear_damp = 3.0
		pet.transition_to("idle")

func physics_process(_delta: float) -> void:
	if not pet:
		return
	# 短暂腾空时不转 fall，继续施力 (避免 retreat→fall→retreat 死循环)
	# 只有真正的高空坠落才转 fall
	if not pet.is_settled() and pet.linear_velocity.y < -200:
		pet.transition_to("fall")
		return
	# 接近目标时减速，防止冲过头被弹飞
	var dist = absf(pet.global_position.x - target_x)
	var force_scale = clampf(dist / SLOWDOWN_DIST, 0.15, 1.0)
	# ── 真正的滚动物理 (与 walk 保持一致) ──
	pet.apply_torque(direction * 80000.0 * force_scale)
	pet.apply_central_force(Vector2(direction * retreat_force * 0.1 * force_scale, 0))

func input(event: InputEvent) -> void:
	# 撤退中也可以被拖拽 (松手后会通过 fall→retreat 自动回归队列)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				pet.transition_to("drag")


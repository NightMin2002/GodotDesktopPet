# retreat.gd — 撤退状态 (走向屏幕边缘)
# 触发安静待命时，宠物自动滚向最近的屏幕边缘，到达后切 Idle
class_name StateRetreat
extends PetState

var target_x: float = 0.0       # 目标 X 坐标 (屏幕边缘)
var direction: float = 0.0      # -1.0 左, 1.0 右
var retreat_force: float = 350.0
const ARRIVE_THRESHOLD := 12.0  # 到达边缘的判定距离 (精准停靠)
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
			target_x = 35.0        # 左边缘: 与队列基准对齐 (半径+留白)
		else:
			target_x = screen_width - 35.0
			
	if pet.global_position.x < target_x:
		direction = 1.0
	else:
		direction = -1.0
	_stuck_time = 0.0
	_last_stuck_x = pet.global_position.x
	pet.physics.apply("retreat")
	# 深夜休眠中被拖走: 临时解锁旋转才能正常滚动归位
	# (到达 idle 后 idle_behaviors.update() 会重新触发 hibernate 并锁定)
	# lock_rotation 已由 transition_to 统一重置 + profile 显式声明 false
	# 先看向撤退方向 (实际滚动等缓冲结束后开始)
	pet.movement.start(Vector2(direction, 0))

func exit() -> void:
	if pet:
		pet.physics.apply("idle_exit")
		pet.movement.finish()
		# 深夜模式归位完成: 恢复高阻尼，等 hibernate 重新锁定旋转
		if pet.nighttime_mode:
			pet.physics.apply("retreat_night_exit")

func process(delta: float) -> void:
	if not pet:
		return
	# 缓冲期: movement 控制器管理计时
	if pet.movement.in_look_ahead:
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
		# 主动刹车，最后几像素的精确对齐交给 idle 的 lerp 微校正柔滑完成
		pet.linear_velocity = Vector2(0, pet.linear_velocity.y)
		pet.angular_velocity = 0.0
		pet.physics.apply("retreat_arrive")
		pet.transition_to("idle")

func physics_process(_delta: float) -> void:
	if not pet:
		return
	if pet.movement.in_look_ahead: return
	# 短暂腾空时不转 fall，继续施力 (避免 retreat→fall→retreat 死循环)
	# 反重力时“坠落”方向反转: gravity_sign=1 时 vy<-200 (向上飞), gravity_sign=-1 时 vy>200 (向下掉)
	if not pet.is_settled() and pet.linear_velocity.y * pet.gravity_sign < -200:
		pet.transition_to("fall")
		return
	# 接近目标时减速，防止冲过头被弹飞
	var dist = absf(pet.global_position.x - target_x)
	var force_scale = clampf(dist / SLOWDOWN_DIST, 0.15, 1.0)
	# ── 真正的滚动物理 (与 walk 保持一致，乘 gravity_sign 适配反重力) ──
	pet.apply_torque(direction * 80000.0 * force_scale * pet.gravity_sign)
	pet.apply_central_force(Vector2(direction * retreat_force * 0.1 * force_scale, 0))

func input(event: InputEvent) -> void:
	# 撤退中也可以被拖拽 (松手后会通过 fall→retreat 自动回归队列)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				pet.transition_to("drag")


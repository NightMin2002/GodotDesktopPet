# retreat.gd — 撤退状态 (走向屏幕边缘)
# 触发安静待命时，宠物自动滚向最近的屏幕边缘，到达后切 Idle
class_name StateRetreat
extends PetState

var target_x: float = 0.0       # 目标 X 坐标 (屏幕边缘)
var direction: float = 0.0      # -1.0 左, 1.0 右
var retreat_force: float = 350.0
const ARRIVE_THRESHOLD := 80.0  # 到达边缘的判定距离 (宽松些，避免撞墙)
const SLOWDOWN_DIST := 200.0    # 开始减速的距离

func enter() -> void:
	if not pet:
		return
	# 计算最近的边缘
	var screen_width = pet.boundary_size.x
	var pet_x = pet.global_position.x
	if pet_x < screen_width / 2.0:
		target_x = 40.0        # 左边缘留出一个身位
		direction = -1.0
	else:
		target_x = screen_width - 40.0
		direction = 1.0
	# 行走时保持较高的线性阻尼，让位移主要来自扭矩+摩擦力转化
	pet.linear_damp = 1.5
	pet.angular_damp = 0.2  # 必须重置，否则从安静 idle(5.0) 转来时扭矩无效

func exit() -> void:
	if pet:
		pet.linear_damp = 0.5

func process(_delta: float) -> void:
	if not pet:
		return
	# 到达目标位置 → 刹车 + 锁定 + 切换到 Idle
	if absf(pet.global_position.x - target_x) < ARRIVE_THRESHOLD:
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

func input(_event: InputEvent) -> void:
	# 撤退中不响应任何鼠标交互
	pass

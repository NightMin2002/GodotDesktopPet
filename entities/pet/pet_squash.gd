# pet_squash.gd — 弹性形变系统 (Squash & Stretch)
# RefCounted，落地/撞墙弹性效果，碰撞体不变
# 核心: 弹簧阻尼器模型，由 RigidBody2D 碰撞信号驱动
# 冲量公式: v₀ = target_deform × √stiffness (物理学正确的速度-形变关系)
# 3 种风格:
#   0 = 轻弹 (Soft): 微妙的压扁回弹，快速恢复
#   1 = 果冻 (Jelly): 较大压扁幅度，慢速晃动恢复
#   2 = 弹力球 (Bouncy): 夸张压扁，强力弹簧回弹
class_name PetSquash
extends RefCounted

var pet: RigidBody2D
var enabled: bool = false
var style: int = 0  # 0=轻弹, 1=果冻, 2=弹力球

var _impact_deform: float = 0.0
var _impact_velocity: float = 0.0
var _impact_dir: Vector2 = Vector2.DOWN
var _cooldown: float = 0.0
var _last_impact: float = 0.0

const STYLES := [
	{"stiffness": 280.0, "damping": 13.0, "max_deform": 0.22, "vel_stretch": 0.08},
	{"stiffness": 140.0, "damping": 5.5, "max_deform": 0.28, "vel_stretch": 0.15},
	{"stiffness": 350.0, "damping": 9.0, "max_deform": 0.35, "vel_stretch": 0.20},
]

func apply_impact(pre_velocity: Vector2, pre_speed: float) -> void:
	if not enabled or pre_speed < 80.0:
		return
	
	var params = STYLES[style]
	# 增强碰撞强度的感知极限
	var impact = clampf(pre_speed / 800.0, 0.2, 1.2)
	# 压缩方向为碰撞抵达方向
	var inc_dir = pre_velocity.normalized()
	if inc_dir == Vector2.ZERO:
		inc_dir = Vector2.DOWN
	
	# 同向弱撞击过滤
	if _cooldown > 0.0 and inc_dir.dot(_impact_dir) > 0.6 and impact < _last_impact * 0.7:
		return
		
	_cooldown = 0.15
	_last_impact = impact
	
	# 方向剧变时，消除旧的形变积累
	if inc_dir.dot(_impact_dir) < 0.3:
		_impact_deform *= 0.3
		_impact_velocity *= 0.3
		
	_impact_dir = inc_dir
	var target = impact * params.max_deform
	
	# 初速度累加：让其在碰撞轴向强力回缩
	_impact_velocity -= target * sqrt(params.stiffness)

func update(delta: float) -> bool:
	if not pet: return false
	
	if not enabled:
		if absf(_impact_deform) > 0.001 or absf(_impact_velocity) > 0.001:
			_impact_deform = lerpf(_impact_deform, 0.0, delta * 10.0)
			_impact_velocity *= 0.9
			return true
		_impact_deform = 0.0
		_impact_velocity = 0.0
		return false
	
	var params = STYLES[style]
	if _cooldown > 0.0: _cooldown -= delta
	
	var spring_force = -params.stiffness * _impact_deform
	var damping_force = -params.damping * _impact_velocity
	
	_impact_velocity += (spring_force + damping_force) * delta
	_impact_deform += _impact_velocity * delta
	# 防止形变得过于夸张
	_impact_deform = clampf(_impact_deform, -0.45, 0.45)
	
	if absf(_impact_deform) < 0.002 and absf(_impact_velocity) < 0.1:
		_impact_deform = 0.0
		_impact_velocity = 0.0
		
	var speed = pet.linear_velocity.length()
	if speed > 60.0:
		return true
		
	return absf(_impact_deform) > 0.0

## 获取组合后的变形矩阵（世界坐标系方向）
func get_deformation_matrix() -> Transform2D:
	if not enabled:
		return Transform2D.IDENTITY
		
	var xform = Transform2D.IDENTITY
	var params = STYLES[style]
	var speed = pet.linear_velocity.length()
	
	# 1. 速度拉伸 (Velocity Stretch) - 基于当前全局速度
	if speed > 60.0:
		var vel_dir = pet.linear_velocity.normalized()
		var stretch = clampf((speed - 60.0) / 1200.0, 0.0, params.vel_stretch)
		var sq_v = 1.0 + stretch
		var sq_t = 1.0 / sq_v
		
		var angle = vel_dir.angle()
		var r_mat = Transform2D(angle, Vector2.ZERO)
		var r_inv = Transform2D(-angle, Vector2.ZERO)
		var s_mat = Transform2D.IDENTITY.scaled(Vector2(sq_v, sq_t))
		# R * S * R_inv: 转换到速度矢量正交系 -> 进行拉伸 -> 转回世界系
		var vel_xform = r_mat * s_mat * r_inv
		
		xform = xform * vel_xform
		
	# 2. 撞击挤压 (Impact Squash) - 基于撞击轴向的弹簧震荡
	if absf(_impact_deform) > 0.001:
		# _deform < 0 为挤压压缩
		var sq_i = 1.0 + _impact_deform
		sq_i = clampf(sq_i, 0.5, 1.5)
		var sq_t = 1.0 / sq_i
		
		var angle = _impact_dir.angle()
		var r_mat = Transform2D(angle, Vector2.ZERO)
		var r_inv = Transform2D(-angle, Vector2.ZERO)
		var s_mat = Transform2D.IDENTITY.scaled(Vector2(sq_i, sq_t))
		# 同理，使得形变严格沿着碰撞方向压扁，然后垂向切线伸展
		var impact_xform = r_mat * s_mat * r_inv
		
		xform = xform * impact_xform
		
	return xform

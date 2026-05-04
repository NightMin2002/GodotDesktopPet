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

# ── 配置 ──
var enabled: bool = false
var style: int = 0  # 0=轻弹, 1=果冻, 2=弹力球

# ── 弹簧状态 ──
var _deform: float = 0.0      # 形变量 (负=压扁, 正=拉伸)
var _velocity: float = 0.0    # 形变速度
var _squash_axis: int = 1     # 压扁方向: 0=水平(撞墙), 1=垂直(落地)
var _cooldown: float = 0.0    # 同轴碰撞冷却 (秒), 防止弹地连续重置
var _last_impact: float = 0.0 # 上次碰撞的强度

# ── 风格参数 ──
# stiffness: 弹簧刚度 (越大恢复越快)
# damping: 阻尼系数 (越大振荡越少)
# max_deform: 最大冲击时的目标压扁量 (0.18 = 18%压扁)
const STYLES := [
	# 轻弹: 快恢复 + 适度阻尼 → 自然柔弹，2-3次振荡
	{"stiffness": 280.0, "damping": 13.0, "max_deform": 0.18},
	# 果冻: 慢恢复 + 低阻尼 → QQ弹弹，4+次振荡
	{"stiffness": 140.0, "damping": 5.5, "max_deform": 0.20},
	# 弹力球: 快恢复 + 中阻尼 → 弹性十足
	{"stiffness": 350.0, "damping": 9.0, "max_deform": 0.25},
]

## 碰撞事件驱动: 由 pet.gd 的 _on_body_entered 调用
## pre_velocity: 碰撞前一帧的速度向量 (方向判断依据)
## pre_speed: 碰撞前一帧的速度大小 (冲击强度依据)
func apply_impact(pre_velocity: Vector2, pre_speed: float) -> void:
	if not enabled or pre_speed < 80.0:
		return
	
	var params = STYLES[style]
	var impact = clampf(pre_speed / 800.0, 0.15, 1.0)
	
	# 碰撞方向判断: 用碰撞前速度分量比例
	var vx = absf(pre_velocity.x)
	var vy = absf(pre_velocity.y)
	var total = vx + vy + 0.01
	var h_ratio = vx / total
	var new_axis = 0 if h_ratio > 0.6 else 1
	
	# 冷却保护: 仅拦截同一轴上的弱碰撞 (防止弹地连续重置)
	# 不同轴碰撞永远放行 (撞墙→落地应自然切换到地面形变)
	if _cooldown > 0.0 and new_axis == _squash_axis and impact < _last_impact * 0.7:
		return
	_cooldown = 0.15
	_last_impact = impact
	
	_switch_axis(new_axis)
	
	# 目标压扁量
	var target = impact * params.max_deform
	# 物理学正确的初速度: v₀ = target × ω (ω = √k 是弹簧自然频率)
	_velocity -= target * sqrt(params.stiffness)

## 每帧更新，返回 true 表示有视觉变化需要重绘
func update(delta: float) -> bool:
	if not pet:
		return false
	
	if not enabled:
		if absf(_deform) > 0.001 or absf(_velocity) > 0.001:
			_deform = lerpf(_deform, 0.0, delta * 10.0)
			_velocity *= 0.9
			return true
		_deform = 0.0
		_velocity = 0.0
		return false
	
	# ── 弹簧阻尼器积分 ──
	var params = STYLES[style]
	
	# 冷却计时器递减
	if _cooldown > 0.0:
		_cooldown -= delta
	
	var spring_force = -params.stiffness * _deform
	var damping_force = -params.damping * _velocity
	var acceleration = spring_force + damping_force
	
	_velocity += acceleration * delta
	_deform += _velocity * delta
	
	# 安全钳制
	_deform = clampf(_deform, -0.30, 0.30)
	
	# 静止判定
	if absf(_deform) < 0.002 and absf(_velocity) < 0.1:
		_deform = 0.0
		_velocity = 0.0
		return false
	
	return true

## 切换压扁轴方向，衰减旧轴残余振荡
func _switch_axis(new_axis: int) -> void:
	if new_axis != _squash_axis:
		_deform *= 0.3
		_velocity *= 0.3
		_squash_axis = new_axis

## 获取当前形变缩放 (供 _draw 使用)
func get_scale() -> Vector2:
	var squash_val = 1.0 + _deform
	squash_val = clampf(squash_val, 0.70, 1.35)
	var stretch_val = 1.0 / squash_val
	
	if _squash_axis == 1:
		return Vector2(stretch_val, squash_val)
	else:
		return Vector2(squash_val, stretch_val)

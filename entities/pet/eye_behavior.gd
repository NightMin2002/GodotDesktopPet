# eye_behavior.gd — 瞳孔行为控制器
# 管理：鼠标追踪 → 闲置好奇游走 过渡 + 机械虹膜眨眼
# 所有方向计算在世界坐标系中进行，不受刚体旋转影响
class_name EyeBehavior
extends RefCounted

var pet: RigidBody2D

# ── 追踪开关 (右键菜单控制) ──
var tracking_enabled := true

# ── 鼠标闲置检测 ──
var _last_mouse_pos := Vector2.ZERO
var _mouse_idle_time := 0.0
const MOUSE_IDLE_THRESHOLD := 2.5  # 鼠标静止超过此秒数 → 进入好奇游走

# ── 游走目标 (世界坐标系方向偏移) ──
var _wander_target := Vector2.ZERO
var _wander_timer := 0.0
var _pupil_pos := Vector2.ZERO  # 当前瞳孔偏移 (世界坐标系，相对于宠物中心)

# ── 机械虹膜眨眼 ──
var _blink_timer := 3.0        # 到下一次眨眼的等待时间
var _is_blinking := false
var _blink_progress := 0.0     # 0 → 1 完成一次闭合-张开循环
const BLINK_SPEED := 10.0      # 越大眨得越快 (≈0.1s 一次完整眨眼)

func update(delta: float) -> void:
	if not is_instance_valid(pet):
		return
	_update_idle_detection(delta)
	_update_pupil(delta)
	_update_blink(delta)

## 获取当前瞳孔相对于眼球中心的偏移量 (世界坐标系，可直接用于反旋转绘制)
func get_pupil_offset() -> Vector2:
	return _pupil_pos

## 获取当前虹膜闭合程度 (0.0 = 完全睁开, 1.0 = 闭合峰值)
func get_blink_amount() -> float:
	if not _is_blinking:
		return 0.0
	# sin 曲线让闭合/张开运动自然柔和
	return sin(_blink_progress * PI)

## 眼球始终活跃（游走 + 眨眼永远在运行）
func is_animating() -> bool:
	return true

# ── 内部逻辑 ──

func _update_idle_detection(delta: float) -> void:
	var current_mouse = pet.get_global_mouse_position()
	if current_mouse.distance_to(_last_mouse_pos) > 3.0:
		_mouse_idle_time = 0.0
		_last_mouse_pos = current_mouse
	else:
		_mouse_idle_time += delta

func _update_pupil(delta: float) -> void:
	var max_offset = pet.PET_RADIUS * 0.2
	var target: Vector2
	var lerp_speed: float
	
	# 追踪关闭 或 鼠标闲置 → 好奇游走模式
	if not tracking_enabled or _mouse_idle_time > MOUSE_IDLE_THRESHOLD:
		_wander_timer -= delta
		if _wander_timer <= 0:
			# 70% 概率看向某个方向，30% 概率回到中心 (模拟自然的注意力回收)
			if randf() > 0.3:
				var angle = randf() * TAU
				var dist = randf_range(0.2, 0.8)
				_wander_target = Vector2(cos(angle), sin(angle)) * max_offset * dist
			else:
				_wander_target = Vector2.ZERO  # 视线回到中心
			_wander_timer = randf_range(2.0, 5.0)  # 更长的停留时间，更从容
		target = _wander_target
		lerp_speed = 1.5  # 慢悠悠地转动，更自然
	else:
		# 鼠标活跃且追踪开启 → 世界空间追踪方向
		var to_mouse = (pet.get_global_mouse_position() - pet.global_position).normalized()
		target = to_mouse * max_offset
		lerp_speed = 12.0
	
	_pupil_pos = _pupil_pos.lerp(target, delta * lerp_speed)

func _update_blink(delta: float) -> void:
	if _is_blinking:
		_blink_progress += delta * BLINK_SPEED
		if _blink_progress >= 1.0:
			_is_blinking = false
			_blink_progress = 0.0
			# 小概率连眨两次 (真实眼睛的行为)
			if randf() < 0.2:
				_blink_timer = 0.15
			else:
				_blink_timer = randf_range(2.5, 7.0)
	else:
		_blink_timer -= delta
		if _blink_timer <= 0:
			_is_blinking = true
			_blink_progress = 0.0

# eye_behavior.gd — 瞳孔行为控制器
# 管理：鼠标追踪 → 注视同伴 → 好奇游走 + 机械虹膜眨眼
# 所有方向计算在世界坐标系中进行，不受刚体旋转影响
class_name EyeBehavior
extends RefCounted

var pet: RigidBody2D

# ── 追踪开关 (右键菜单控制) ──
var tracking_enabled := true

# ── 鼠标闲置检测 ──
var _last_mouse_pos := Vector2.ZERO
var _mouse_idle_time := 0.0
const MOUSE_IDLE_THRESHOLD := 2.5  # 鼠标静止超过此秒数 → 进入游走/社交模式

# ── 游走/社交目标 (世界坐标系方向偏移) ──
var _wander_target := Vector2.ZERO
var _wander_timer := 0.0
var _pupil_pos := Vector2.ZERO  # 当前瞳孔偏移 (世界坐标系)
var _prev_pupil_pos := Vector2.ZERO  # 上帧瞳孔位置 (按需重绘检测用)
var _look_at_pet: RigidBody2D = null  # 当前注视的同伴 (动态追踪)
var _glance_mouse: bool = false       # 好奇观察指针中 (偶尔盯一眷)

# ── 强制注视方向 (由状态机设定，非零时覆盖一切) ──
var forced_look_dir := Vector2.ZERO

# ── 机械虹膜眨眼 ──
var _blink_timer := 3.0
var _is_blinking := false
var _was_blinking := false  # 上帧是否在眨眼 (保证眨眼结束后多重绘一帧)
var _blink_progress := 0.0
const BLINK_SPEED := 10.0

# ── 低功耗休眠 (持续半闭眼) ──
var drowsy_amount := 0.0       # 外部控制: 0.0=正常, ~0.6=半闭
var _drowsy_target := 0.0      # 目标值 (lerp 过渡)

# ── 休眠视觉参数 (不同风格共用) ──
var hibernate_dim := 0.0         # 亮度衰减: 0.0=正常, 1.0=全暗
var _hibernate_dim_target := 0.0
var hibernate_iris_shrink := 0.0 # 光圈收缩: 0.0=正常, 1.0=缩到最小
var _hibernate_iris_shrink_target := 0.0



func update(delta: float) -> void:
	if not is_instance_valid(pet):
		return
	_prev_pupil_pos = _pupil_pos
	_was_blinking = _is_blinking  # 捕获眨眼状态 (blink更新前)
	_update_idle_detection(delta)
	_update_pupil(delta)
	_update_blink(delta)

## 获取当前瞳孔偏移 (世界坐标系，可直接用于反旋转绘制)
func get_pupil_offset() -> Vector2:
	return _pupil_pos

## 获取眨眼闭合程度 (仅眨眼，不含休眠)
func get_blink_amount() -> float:
	if not _is_blinking:
		return 0.0
	return sin(_blink_progress * PI)

## 获取休眠挡板闭合程度 (0.0=全开, ~0.6=半闭)
func get_drowsy_amount() -> float:
	return drowsy_amount

## 只在眸球实际变化时才需要重绘
func is_animating() -> bool:
	if _is_blinking or _was_blinking:
		return true
	if absf(drowsy_amount - _drowsy_target) > 0.01:
		return true
	if absf(hibernate_dim - _hibernate_dim_target) > 0.01:
		return true
	if absf(hibernate_iris_shrink - _hibernate_iris_shrink_target) > 0.01:
		return true
	if drowsy_amount > 0.01 or hibernate_dim > 0.01 or hibernate_iris_shrink > 0.01:
		return true
	return _pupil_pos.distance_to(_prev_pupil_pos) > 0.05

# ── 内部逻辑 ──

func _update_idle_detection(delta: float) -> void:
	var current_mouse = pet.get_global_mouse_position()
	if current_mouse.distance_to(_last_mouse_pos) > 3.0:
		_mouse_idle_time = 0.0
		_last_mouse_pos = current_mouse
	else:
		_mouse_idle_time += delta

func _update_pupil(delta: float) -> void:
	# 休眠态平滑过渡
	drowsy_amount = lerpf(drowsy_amount, _drowsy_target, delta * 3.0)
	hibernate_dim = lerpf(hibernate_dim, _hibernate_dim_target, delta * 3.0)
	hibernate_iris_shrink = lerpf(hibernate_iris_shrink, _hibernate_iris_shrink_target, delta * 3.0)


	var max_offset = pet.PET_RADIUS * 0.12
	

	var target: Vector2
	var lerp_speed: float
	
	# 最高优先级：状态机强制注视方向 (移动中看前方)
	if forced_look_dir != Vector2.ZERO:
		target = forced_look_dir.normalized() * max_offset
		lerp_speed = 18.0
	# 追踪关闭 或 鼠标闲置 → 游走/社交/好奇观察模式
	elif not tracking_enabled or _mouse_idle_time > MOUSE_IDLE_THRESHOLD:
		_wander_timer -= delta
		if _wander_timer <= 0:
			_look_at_pet = null
			_glance_mouse = false
			
			# ── 有同伴在看我？35% 概率回看 ──
			var gazer = _find_pet_looking_at_me()
			if gazer != null and randf() < 0.35:
				_look_at_pet = gazer
				_wander_timer = randf_range(2.0, 3.5)
			else:
				var other = _find_nearest_pet()
				if other != null and randf() < 0.10:
					# 10% 概率主动瞄一眼同伴
					_look_at_pet = other
					_wander_timer = randf_range(1.5, 3.0)
				elif _mouse_idle_time < MOUSE_IDLE_THRESHOLD and randf() < 0.15:
					# 15% 概率好奇盯一眼指针 (仅当鼠标活跃时)
					_glance_mouse = true
					_wander_timer = randf_range(2.0, 4.0)
				elif randf() > 0.3:
					# 随机方向好奇张望
					var angle = randf() * TAU
					var dist = randf_range(0.2, 0.8)
					_wander_target = Vector2(cos(angle), sin(angle)) * max_offset * dist
					_wander_timer = randf_range(2.0, 5.0)
				else:
					# 视线回到中心
					_wander_target = Vector2.ZERO
					_wander_timer = randf_range(2.0, 5.0)
		
		# 好奇观察指针: 动态跟踪鼠标位置 (缓慢跟随，像是不经意的观察)
		if _glance_mouse:
			var to_mouse = (pet.get_global_mouse_position() - pet.global_position).normalized()
			target = to_mouse * max_offset
			lerp_speed = 4.0
		# 注视同伴：动态追踪对方位置 (每帧更新方向)
		elif is_instance_valid(_look_at_pet):
			var to_other = (_look_at_pet.global_position - pet.global_position).normalized()
			target = to_other * max_offset
			lerp_speed = 2.0
		else:
			target = _wander_target
			lerp_speed = 1.5
	else:
		# 鼠标活跃且追踪开启 → 世界空间追踪
		_look_at_pet = null
		var to_mouse = (pet.get_global_mouse_position() - pet.global_position).normalized()
		target = to_mouse * max_offset
		lerp_speed = 12.0
	
	_pupil_pos = _pupil_pos.lerp(target, delta * lerp_speed)

## 查找是否有同伴正在注视自己 → 用于触发互相对视
func _find_pet_looking_at_me() -> RigidBody2D:
	if not is_instance_valid(pet): return null
	var parent = pet.get_parent()
	if not parent: return null
	
	for child in parent.get_children():
		if child is RigidBody2D and child != pet and is_instance_valid(child):
			if not child.has_method("is_mouse_on_pet"): continue
			# 检查对方的 eye_behavior 是否正在看我
			if "eye_behavior" in child and child.eye_behavior._look_at_pet == pet:
				return child
	return null

## 查找最近的、视线无遮挡的同伴宠物
## 遮挡判定：如果两只宠物连线上有第三只宠物 (距连线 < 40px)，视为遮挡
func _find_nearest_pet() -> RigidBody2D:
	if not is_instance_valid(pet): return null
	var parent = pet.get_parent()
	if not parent: return null
	
	# 先收集所有有效宠物及距离
	var pets: Array[RigidBody2D] = []
	for child in parent.get_children():
		if child is RigidBody2D and child != pet and is_instance_valid(child):
			if child.has_method("is_mouse_on_pet"):
				pets.append(child)
	
	if pets.is_empty(): return null
	
	# 按距离排序，优先考虑最近的
	var my_pos = pet.global_position
	pets.sort_custom(func(a, b): return my_pos.distance_to(a.global_position) < my_pos.distance_to(b.global_position))
	
	for candidate in pets:
		var d = my_pos.distance_to(candidate.global_position)
		if d > 600.0: break  # 超出最大注视距离
		
		# 检查连线上是否有其他宠物遮挡 (电灯泡检测)
		var blocked = false
		for other in pets:
			if other == candidate: continue
			var other_d = my_pos.distance_to(other.global_position)
			if other_d >= d: continue  # 不在中间的不算遮挡
			# 计算 other 到连线段的距离
			var line_dist = _point_to_segment_dist(other.global_position, my_pos, candidate.global_position)
			if line_dist < 40.0:
				blocked = true
				break
		
		if not blocked:
			return candidate
	
	return null

## 点到线段的最短距离
func _point_to_segment_dist(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var ab = seg_b - seg_a
	var ap = point - seg_a
	var t = clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
	var closest = seg_a + ab * t
	return point.distance_to(closest)

func _update_blink(delta: float) -> void:
	# 休眠态抑制正常眨眼 (已经半闭了，不需要再眨)
	if _drowsy_target > 0.3:
		_is_blinking = false
		_blink_progress = 0.0
		return

	if _is_blinking:
		_blink_progress += delta * BLINK_SPEED
		if _blink_progress >= 1.0:
			_is_blinking = false
			_blink_progress = 0.0
			if randf() < 0.2:
				_blink_timer = 0.15
			else:
				_blink_timer = randf_range(2.5, 7.0)
	else:
		_blink_timer -= delta
		if _blink_timer <= 0:
			_is_blinking = true
			_blink_progress = 0.0

# ── 外部接口: 休眠/扫描/检索控制 ──

## 进入休眠态 (虹膜缓慢收缩到指定程度)
func start_drowsy(amount := 0.6) -> void:
	_drowsy_target = amount

## 退出休眠态 (虹膜缓慢恢复)
func stop_drowsy() -> void:
	_drowsy_target = 0.0

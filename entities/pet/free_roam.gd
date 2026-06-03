## 空间跳跃系统 (FreeRoamSystem)
## 从 pet.gd 拆分。管理踏板跳跃、横移、电梯下降、破碎效果等全部自由移动逻辑。
## 模式: 跳→踏板接住→随心决策(继续跳/横移/跳下/电梯)→循环
class_name FreeRoamSystem
extends RefCounted

var pet: RigidBody2D  # 宠物引用

# ── 状态变量 ──
var platforms: Array[Node] = []       # 当前活跃的踏板
var active: bool = false              # 是否正在攀升/下降
var phase: int = 0                    # 0=空闲, 1=上升等顶点, 2=等落稳, 3=电梯下降中, 4=横移中
var _was_rising: bool = false         # 是否曾上升 (检测顶点用)
var _airtime: float = 0.0            # 空中/phase计时
var descending: bool = false          # 是否在下降阶段
var _elevator: StaticBody2D = null    # 电梯踏板引用
var _current_plat: StaticBody2D = null  # 当前站立的踏板引用
var _elevator_vanish_dist: float = 10.0  # 电梯消失距地面距离 (px)
var _walk_min_x: float = 0.0             # 横移踏板左边界
var _walk_max_x: float = 0.0             # 横移踏板右边界
var _last_pet_x: float = 0.0             # 上帧宠物X (屏幕穿越检测)
var no_descend: bool = false              # 遍伴触发: 禁止电梯/跳下, 只保留继续跳/横移/驻留

# ── 驻留状态 ──
var settled: bool = false                # 是否驻留在空中踏板上
var _settled_plat: StaticBody2D = null   # 驻留踏板 (独立于 platforms[] 管理)

const PLATFORM_WIDTH := 40.0             # 踏板基础宽度 (宠物是老手，不需要很宽)
const PLATFORM_MARGIN := 20.0            # 踏板边缘余量 (宠物位置外延)

# ── 公共接口 ──

## 屏幕缩放因子 (基准 1080p，4K 约 2.0)
func screen_scale() -> float:
	return pet.boundary_size.y / 1080.0

## 启动自由漫游
func start(p_no_descend: bool = false) -> void:
	no_descend = p_no_descend
	if settled:
		# 从驻留位置启动: 跳过首跳，直接进入决策
		active = true
		settled = false
		_current_plat = _settled_plat
		_settled_plat = null
		platforms.append(_current_plat)
		phase = 0
		descending = false
		_elevator = null
		# 恢复踏板透明度 + 确保碰撞启用 (拖拽可能留下 disabled)
		if is_instance_valid(_current_plat):
			var tw = _current_plat.create_tween()
			tw.tween_property(_current_plat, "modulate:a", 1.0, 0.2)
			for child in _current_plat.get_children():
				if child is CollisionShape2D and not child.has_meta("_roam_wall"):
					child.disabled = false
		_decide_next()
		return
	
	active = true
	phase = 0
	descending = false
	_elevator = null
	
	# 锁定到 idle 状态
	if pet.current_state != pet.states.get("idle"):
		pet.transition_to("idle")
	
	# 第一跳
	do_jump()

## 统一清理 (拖拽中断/正常结束)
func finish() -> void:
	_remove_side_walls()
	_clear_platforms()
	clear_settled()  # 同时清理驻留状态
	active = false
	phase = 0
	descending = false
	pet.gravity_scale = pet.gravity_sign
	no_descend = false
	_elevator = null
	_current_plat = null
	pet.physics_material_override.friction = 0.6
	pet.movement.finish()  # 重置 movement 状态 (防止卡在 HOLD/看向下方)
	# 重置 idle 计时器 (roam 期间 idle_timer 持续累加，不重置会导致
	# finish() 后第一帧 idle 立刻满足转换条件，walk 抢走瞳孔方向)
	if pet.current_state and pet.current_state is StateIdle:
		pet.current_state.idle_timer = 0.0
		pet.current_state.idle_duration = randf_range(0.8, 1.5)

## 每帧更新 (由 pet._process 调用)
func update(delta: float) -> void:
	if settled:
		_update_settled(delta)
		return
	if not active or phase == 0:
		return
	
	if phase == 1:
		# ── 上升中，检测抛物线顶点 ──
		_airtime += delta
		var vy = pet.linear_velocity.y * pet.gravity_sign
		if vy < -30.0:
			_was_rising = true
		if _was_rising and vy > -20.0 and _airtime > 0.15:
			var platform_y = pet.global_position.y + (pet.PET_RADIUS + 5.0) * pet.gravity_sign
			_current_plat = _spawn_platform(Vector2(pet.global_position.x, platform_y))
			# 初始化物理边界对齐踏板的初始宽度，防止首帧边界突变
			_walk_min_x = pet.global_position.x - PLATFORM_WIDTH / 2.0
			_walk_max_x = pet.global_position.x + PLATFORM_WIDTH / 2.0
			_last_pet_x = pet.global_position.x
			# 不人为制动，让宠物保持惯性自然落地
			pet.physics.apply("roam_land")
			# 临时降低摩擦力，让宠物在踏板上自然滑行
			pet.physics_material_override.friction = 0.05
			phase = 2
	
	elif phase == 2:
		# ── 踏板已生成，跟踪宠物滑行 + 等落稳 ──
		# 屏幕穿越检测: 宠物坐标突变时在新位置重建踏板
		if pet.screen_wrap and _detect_wrap():
			_respawn_platform_at_pet()
		_last_pet_x = pet.global_position.x
		if is_instance_valid(_current_plat):
			# 踏板单向追踪: 只覆盖原点到宠物位置 + 两端小余量
			var plat_x = _current_plat.position.x
			var pet_x = pet.global_position.x
			var margin = PLATFORM_MARGIN
			var left_edge = minf(plat_x, pet_x) - margin
			var right_edge = maxf(plat_x, pet_x) + margin
			var new_width = right_edge - left_edge
			var local_center = (left_edge + right_edge) / 2.0 - plat_x
			for child in _current_plat.get_children():
				if child is CollisionShape2D and not child.has_meta("_roam_wall"):
					var shape = child.shape as RectangleShape2D
					if shape:
						shape.size.x = new_width
					child.position.x = local_center
				elif child is PlatformVisual:
					child.platform_width = new_width
					child.position.x = local_center
		if pet.is_settled():
			pet.physics_material_override.friction = 0.6  # 恢复摩擦力
			_full_stop()
			phase = 0
			_decide_next()
	
	elif phase == 3:
		# ── 电梯下降中 ──
		if not is_instance_valid(_elevator):
			finish()
			return
		var elevator_speed = 100.0 * screen_scale()
		_elevator.position.y += elevator_speed * delta * pet.gravity_sign
		var target_y = _elevator.position.y - (pet.PET_RADIUS + 5.0) * pet.gravity_sign
		pet.global_position.y = target_y
		pet.linear_velocity.y = 0
		var drift = pet.global_position.x - _elevator.position.x
		if absf(drift) > 3.0:
			pet.global_position.x = lerpf(pet.global_position.x, _elevator.position.x, 6.0 * delta)
		pet.linear_velocity.x *= 0.8
		pet.angular_velocity *= 0.85
		var ground_y = pet.boundary_size.y if not pet.anti_gravity else 0.0
		var dist = absf(_elevator.position.y - ground_y)
		# 贴近地面时消失 (随机 10~50px × 屏幕缩放)
		if dist < _elevator_vanish_dist:
			pet.physics.apply("roam_elevator_end")
			phase = 0
			var elevator = _elevator
			_elevator = null
			platforms.erase(elevator)
			var tween = elevator.create_tween()
			tween.tween_property(elevator, "modulate:a", 0.0, 0.5)
			tween.finished.connect(func():
				if is_instance_valid(elevator):
					elevator.queue_free()
			)
			finish()
	
	elif phase == 4:
		# ── 横移中：踏板本体不动，碰撞体+视觉单向延伸 ──
		_airtime += delta
		# 屏幕穿越检测: 宠物坐标突变时在新位置重建踏板
		if pet.screen_wrap and _detect_wrap():
			_respawn_platform_at_pet()
		_last_pet_x = pet.global_position.x
		if is_instance_valid(_current_plat):
			var pet_x = pet.global_position.x
			var margin = PLATFORM_MARGIN
			
			var safe_min = pet_x - margin
			var safe_max = pet_x + margin
			
			# 1. 瞬间延展确保物理安全（向哪走，哪边立刻变长接住）
			_walk_min_x = minf(_walk_min_x, safe_min)
			_walk_max_x = maxf(_walk_max_x, safe_max)
			
			# 2. 延缓平滑收缩（随着宠物滑行，后方踏板跟随着消融收紧并激发噼啪火花）
			_walk_min_x = lerpf(_walk_min_x, safe_min, 1.25 * delta)
			_walk_max_x = lerpf(_walk_max_x, safe_max, 1.25 * delta)
			
			var plat_x = _current_plat.position.x
			var new_width = _walk_max_x - _walk_min_x
			var local_offset_x = (_walk_min_x + _walk_max_x) / 2.0 - plat_x
			for child in _current_plat.get_children():
				if child is CollisionShape2D and not child.has_meta("_roam_wall"):
					var shape = child.shape as RectangleShape2D
					if shape:
						shape.size.x = new_width
					child.position.x = local_offset_x
				elif child is PlatformVisual:
					child.platform_width = new_width
					child.position.x = local_offset_x
		# 至少等 0.8 秒再检测落稳
		if _airtime > 0.8 and pet.is_settled():
			pet.physics_material_override.friction = 0.6  # 恢复正常物理摩擦力
			_full_stop()
			phase = 0
			_decide_next()

# ── 跳跃 ──

func do_jump() -> void:
	_remove_side_walls()
	_was_rising = false
	_airtime = 0.0
	
	var ss = screen_scale()
	var hop_dir: float
	if no_descend:
		# 遇伴触发: 垂直起跳 (跳过同伴, 不像逃跑)
		hop_dir = 0.0
	else:
		hop_dir = [-1.0, 1.0].pick_random()
		var edge_pad = pet.boundary_size.x * 0.08
		var x = pet.global_position.x
		if x < edge_pad: hop_dir = 1.0
		elif x > pet.boundary_size.x - edge_pad: hop_dir = -1.0
	
	# 先看方向，缓冲到期后再起跳
	var look_dir = Vector2(hop_dir if hop_dir != 0.0 else 1.0, -pet.gravity_sign)
	pet.movement.start(look_dir, func():
		if not active:
			return
		phase = 1
		# 跳跃力度 (650~800)
		var vy = randf_range(650.0, 800.0) * ss * -pet.gravity_sign
		var vx = hop_dir * randf_range(60.0, 150.0) * ss
		pet.physics.apply("roam_jump")
		pet.apply_central_impulse(Vector2(vx, vy))
		pet.apply_torque_impulse(hop_dir * randf_range(2000.0, 5000.0) * ss)
	)

# ── 决策 ──

## 落稳后的决策: 继续跳 / 横移 / 驻留 / 跳下 / 电梯
func _decide_next() -> void:
	pet.movement.finish()  # 落稳后进入 HOLD → 自然过渡
	var pause = randf_range(0.6, 1.5)
	await pet.get_tree().create_timer(pause).timeout
	if not active:
		return
	
	var roll = randf()
	var _no_descend_this_time = no_descend
	no_descend = false  # 只限第一次决策, 后续恢复正常
	if _no_descend_this_time:
		# 遍伴触发模式: 只保留继续跳/横移/驻留 (40%/30%/30%)
		if roll < 0.40:
			do_jump()
		elif roll < 0.70:
			_walk_sideways()
		else:
			_settle_on_platform()
	else:
		# 正常模式: 全部行为可用
		if roll < 0.30:
			do_jump()
		elif roll < 0.50:
			_walk_sideways()
		elif roll < 0.70:
			_settle_on_platform()
		elif roll < 0.85:
			_jump_down()
		else:
			_begin_descent()

# ── 驻留 ──

## 驻留在当前踏板上: 结束 active 序列，踏板保留，宠物恢复自由行动
func _settle_on_platform() -> void:
	if not is_instance_valid(_current_plat):
		# 没有可驻留的踏板，降级为跳下
		_jump_down()
		return
	
	# 将踏板从自动管理列表移出，转为独立引用
	settled = true
	_settled_plat = _current_plat
	platforms.erase(_current_plat)
	_current_plat = null
	
	# 直接读取踏板当前的世界空间边界 (避免 margin 换算导致宽度突变)
	var plat_x = _settled_plat.position.x
	for child in _settled_plat.get_children():
		if child is CollisionShape2D and not child.has_meta("_roam_wall"):
			var shape = child.shape as RectangleShape2D
			if shape:
				var half_w = shape.size.x / 2.0
				var center = plat_x + child.position.x
				_walk_min_x = center - half_w
				_walk_max_x = center + half_w
			break
	
	# 结束 active 但不清理踏板
	active = false
	phase = 0
	descending = false
	pet.physics_material_override.friction = 0.6
	_elevator = null
	
	# 清理其他残留踏板
	_clear_platforms()
	
	# 重置 idle，让宠物恢复正常行为
	pet.movement.finish()
	if pet.current_state and pet.current_state is StateIdle:
		pet.current_state.idle_timer = 0.0
		pet.current_state.idle_duration = randf_range(0.8, 1.5)
	
	# 驻留踏板淡化，减少桌面视觉遮挡
	if is_instance_valid(_settled_plat):
		var tw = _settled_plat.create_tween()
		tw.tween_property(_settled_plat, "modulate:a", 0.1, 0.5)

## 驻留状态每帧更新: 踏板横向跟随 + 拖穿破碎检测
func _update_settled(delta: float) -> void:
	if not is_instance_valid(_settled_plat):
		clear_settled()
		return
	
	var is_dragging = pet.current_state_name == "drag"
	
	# ── 拖穿检测: 非拖拽时宠物中心低于踏板 → 破碎 ──
	if not is_dragging:
		var plat_y = _settled_plat.position.y
		var pet_y = pet.global_position.y
		var dist_below = (pet_y - plat_y) * pet.gravity_sign
		if dist_below > pet.PET_RADIUS * 2.0:
			_shatter_settled()
			return
	
	# ── 踏板横向跟随 (安全延展 + 软阻尼平滑收缩) ──
	var pet_x = pet.global_position.x
	var margin = PLATFORM_MARGIN
	
	var safe_min = pet_x - margin
	var safe_max = pet_x + margin
	
	# 1. 瞬间延展确保物理安全（向哪走，哪边立刻变长）
	_walk_min_x = minf(_walk_min_x, safe_min)
	_walk_max_x = maxf(_walk_max_x, safe_max)
	
	# 2. 延缓平滑收缩（离开的一侧，其尾部会以平缓的阻尼慢慢缩回至安全宽度）
	_walk_min_x = lerpf(_walk_min_x, safe_min, 1.25 * delta)
	_walk_max_x = lerpf(_walk_max_x, safe_max, 1.25 * delta)
	
	var plat_x = _settled_plat.position.x
	var new_width = _walk_max_x - _walk_min_x
	var local_offset_x = (_walk_min_x + _walk_max_x) / 2.0 - plat_x
	for child in _settled_plat.get_children():
		if child is CollisionShape2D and not child.has_meta("_roam_wall"):
			child.disabled = is_dragging
			var shape = child.shape as RectangleShape2D
			if shape:
				shape.size.x = new_width
			child.position.x = local_offset_x
		elif child is PlatformVisual:
			child.platform_width = new_width
			child.position.x = local_offset_x

## 拖穿踏板: 破碎效果 + 清理驻留状态
func _shatter_settled() -> void:
	if is_instance_valid(_settled_plat):
		_shatter_platform(_settled_plat)
		_settled_plat = null
	settled = false

## 静默清理驻留状态 (无破碎效果，用于 finish 等场景)
func clear_settled() -> void:
	if is_instance_valid(_settled_plat):
		var plat = _settled_plat
		_settled_plat = null
		var tween = plat.create_tween()
		tween.tween_property(plat, "modulate:a", 0.0, 0.3)
		tween.finished.connect(func():
			if is_instance_valid(plat):
				plat.queue_free()
		)
	settled = false

# ── 横向滚动 ──

## 空气墙防掉落 + 踏板跟随
func _walk_sideways() -> void:
	var ss = screen_scale()
	var hop_dir = [-1.0, 1.0].pick_random()
	var edge_pad = pet.boundary_size.x * 0.08
	var x = pet.global_position.x
	if x < edge_pad: hop_dir = 1.0
	elif x > pet.boundary_size.x - edge_pad: hop_dir = -1.0
	
	# 精确读取当前踏板在起跑瞬间的实际世界空间边界，实现无缝衔接，彻底消除宽幅突变与首帧火花闪烁
	if is_instance_valid(_current_plat):
		var plat_x = _current_plat.position.x
		for child in _current_plat.get_children():
			if child is CollisionShape2D and not child.has_meta("_roam_wall"):
				var shape = child.shape as RectangleShape2D
				if shape:
					var half_w = shape.size.x / 2.0
					var center = plat_x + child.position.x
					_walk_min_x = center - half_w
					_walk_max_x = center + half_w
				break
	else:
		# 兜底：若踏板不存在，以宠物为中心建立匹配初始宽度的边界
		var pet_x = pet.global_position.x
		_walk_min_x = pet_x - PLATFORM_WIDTH / 2.0
		_walk_max_x = pet_x + PLATFORM_WIDTH / 2.0
	
	# 先看方向，缓冲到期后再滚动
	pet.movement.start(Vector2(hop_dir, 0), func():
		if not active:
			return
		phase = 4
		_airtime = 0.0
		_last_pet_x = pet.global_position.x
		pet.physics.apply("roam_walk")
		
		# 采用自然贴地滚动的水平冲量（去除向上腾空，使其完全贴着踏板顺滑滚动）
		var vx = hop_dir * randf_range(140.0, 200.0) * ss
		pet.apply_central_impulse(Vector2(vx, 0.0))
		
		# 施加适度的前扑滚动旋转，防止转成虚影
		pet.apply_torque_impulse(hop_dir * randf_range(800.0, 1500.0) * ss)
		
		# 临时降低摩擦力，使宠物能在踏板上顺滑地惯性滑行一段距离，而不是踩刹车般强阻尼
		pet.physics_material_override.friction = 0.1
	)

# ── 跳下 (踏板破碎) ──

## 看向跳跃方向→蓄力→起跳→踏板因冲击破碎
func _jump_down() -> void:
	var ss = screen_scale()
	var hop_dir = [-1.0, 1.0].pick_random()
	var edge_pad = pet.boundary_size.x * 0.08
	var x = pet.global_position.x
	if x < edge_pad: hop_dir = 1.0
	elif x > pet.boundary_size.x - edge_pad: hop_dir = -1.0
	
	# 先看方向蓄力，缓冲到期后起跳
	_full_stop()
	pet.movement.start(Vector2(hop_dir, pet.gravity_sign), func():
		if not active:
			return
		# 移除空气墙
		_remove_side_walls()
		# 起跳! (强力横向 + 微小上弹)
		pet.physics.apply("roam_jump_down")
		pet.apply_central_impulse(Vector2(hop_dir * randf_range(200.0, 350.0) * ss, randf_range(50.0, 120.0) * -pet.gravity_sign * ss))
		pet.apply_torque_impulse(hop_dir * randf_range(3000.0, 7000.0) * ss)
		# 踏板因起跳冲击力破碎
		if is_instance_valid(_current_plat):
			_shatter_platform(_current_plat)
			platforms.erase(_current_plat)
			_current_plat = null
		_clear_platforms()
		finish()
	)

# ── 电梯式下降 ──

func _begin_descent() -> void:
	_remove_side_walls()
	_clear_platforms()
	
	var ground_y = pet.boundary_size.y if not pet.anti_gravity else 0.0
	var dist_to_ground = absf(pet.global_position.y - ground_y)
	
	if dist_to_ground < pet.boundary_size.y * 0.08:
		finish()
		return
	
	descending = true
	
	# 先看向下方，缓冲到期后生成电梯开始下降
	_full_stop()
	pet.movement.start(Vector2(0, pet.gravity_sign), func():
		if not active:
			return
		pet.gravity_scale = 0.0
		var platform_y = pet.global_position.y + (pet.PET_RADIUS + 5.0) * pet.gravity_sign
		var elevator = _spawn_platform(Vector2(pet.global_position.x, platform_y), true)
		_elevator = elevator
		_elevator_vanish_dist = randf_range(10.0, 50.0) * screen_scale()
		phase = 3
	)

# ── 物理辅助 ──

## 检测屏幕穿越: 单帧水平位移超过 40% 屏幕宽度 = 穿越发生
func _detect_wrap() -> bool:
	return absf(pet.global_position.x - _last_pet_x) > pet.boundary_size.x * 0.4

## 穿越后在宠物新位置重建踏板 (旧踏板保留原状自然淡出)
func _respawn_platform_at_pet() -> void:
	var platform_y: float
	if is_instance_valid(_current_plat):
		platform_y = _current_plat.position.y
	else:
		platform_y = pet.global_position.y + (pet.PET_RADIUS + 5.0) * pet.gravity_sign
	_current_plat = _spawn_platform(Vector2(pet.global_position.x, platform_y))
	_walk_min_x = pet.global_position.x
	_walk_max_x = pet.global_position.x

func _full_stop() -> void:
	pet.linear_velocity.x = 0
	pet.angular_velocity = 0
	pet.physics.apply("roam_full_stop")

# ── 空气墙管理 ──

func _add_side_walls() -> void:
	if not is_instance_valid(_current_plat): return
	_remove_side_walls()
	for side in [-1.0, 1.0]:
		var col = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(4.0, pet.PET_RADIUS * 4.0)
		col.shape = shape
		col.position = Vector2(side * PLATFORM_WIDTH / 2.0, -pet.PET_RADIUS * 2.0 * pet.gravity_sign)
		col.one_way_collision = false
		col.set_meta("_roam_wall", true)
		_current_plat.add_child(col)

func _remove_side_walls() -> void:
	if not is_instance_valid(_current_plat): return
	var to_remove: Array[CollisionShape2D] = []
	for child in _current_plat.get_children():
		if child is CollisionShape2D and child.has_meta("_roam_wall"):
			child.disabled = true
			to_remove.append(child)
	for c in to_remove:
		c.queue_free()

# ── 踏板管理 ──

func _clear_platforms() -> void:
	for body in platforms:
		if is_instance_valid(body):
			var tween = body.create_tween()
			tween.tween_property(body, "modulate:a", 0.0, 0.3)
			tween.finished.connect(func():
				if is_instance_valid(body):
					body.queue_free()
			)
	platforms.clear()

func _spawn_platform(pos: Vector2, is_elevator: bool = false) -> StaticBody2D:
	var parent = pet.get_parent()
	if not parent:
		return null
	
	var platform_thickness := 8.0
	
	var body = StaticBody2D.new()
	body.position = pos
	
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(PLATFORM_WIDTH, platform_thickness)
	col.shape = shape
	col.one_way_collision = true
	if pet.anti_gravity:
		col.rotation = PI
	body.add_child(col)
	
	var visual = PlatformVisual.new()
	visual.pet = pet
	visual.platform_width = PLATFORM_WIDTH
	visual.platform_color = pet.palette.shift_color(Color(0.2, 0.6, 1.0, 0.6))
	body.add_child(visual)
	
	parent.add_child(body)
	platforms.append(body)
	
	body.modulate.a = 0.0
	var tween = body.create_tween()
	tween.tween_property(body, "modulate:a", 1.0, 0.15)
	
	if not is_elevator:
		_schedule_removal(body, 3.5)
	
	return body

func _schedule_removal(body: Node, delay: float) -> void:
	await pet.get_tree().create_timer(delay).timeout
	if not is_instance_valid(body): return
	# 保护正在使用的踏板和驻留踏板
	if (active and is_instance_valid(_current_plat) and _current_plat == body) or \
	   (settled and is_instance_valid(_settled_plat) and _settled_plat == body):
		_schedule_removal(body, 2.0)
		return
	var tween = body.create_tween()
	tween.tween_property(body, "modulate:a", 0.0, 0.8)
	tween.finished.connect(func():
		if is_instance_valid(body):
			platforms.erase(body)
			body.queue_free()
		)

# ── 踏板破碎效果 ──

func _shatter_platform(plat: StaticBody2D) -> void:
	# 碎片从宠物起跳位置飞散 (X=宠物当前位置, Y=踏板高度)
	var pos = Vector2(pet.global_position.x, plat.position.y)
	var parent_node = plat.get_parent()
	
	for child in plat.get_children():
		if child is CollisionShape2D:
			child.disabled = true
	
	plat.modulate = Color(1.5, 1.5, 2.0, 1.0)
	var main_tw = plat.create_tween()
	main_tw.tween_property(plat, "modulate:a", 0.0, 0.2)
	main_tw.finished.connect(func():
		if is_instance_valid(plat): plat.queue_free()
	)
	
	if not parent_node: return
	var g_dir = pet.gravity_sign
	var frag_color = pet.palette.shift_color(Color(0.25, 0.55, 1.0, 0.75))
	for i in range(6):
		var frag = Polygon2D.new()
		var fw = randf_range(8.0, 16.0)
		var fh = randf_range(2.0, 4.0)
		frag.polygon = PackedVector2Array([
			Vector2(-fw/2, -fh/2), Vector2(fw/2, -fh/2),
			Vector2(fw/2, fh/2), Vector2(-fw/2, fh/2)
		])
		frag.color = frag_color
		frag.position = pos + Vector2(randf_range(-35, 35), randf_range(-3, 3))
		frag.rotation = randf_range(-0.3, 0.3)
		frag.z_index = -1
		parent_node.add_child(frag)
		
		var end_pos = frag.position + Vector2(randf_range(-150, 150), randf_range(60, 180) * g_dir)
		var tw = frag.create_tween()
		tw.tween_property(frag, "position", end_pos, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(frag, "rotation", frag.rotation + randf_range(-4.0, 4.0), 0.5)
		tw.parallel().tween_property(frag, "modulate:a", 0.0, 0.4).set_delay(0.1)
		tw.finished.connect(frag.queue_free)

# ── 踏板视觉渲染 (多风格) ──

class PlatformVisual extends Node2D:
	var platform_width: float = 120.0
	var platform_color: Color = Color(0.2, 0.6, 1.0, 0.6)
	var quiet: bool = false  # 静默模式: 强制极简 + 无粒子 (终端/游戏态用)
	var pet: RigidBody2D = null
	
	var _time: float = 0.0
	var _expand: float = 0.0
	var _last_left: float = INF
	var _last_right: float = INF
	var _particles: Array = []
	
	# 风格: -1=随机, 0=能量束, 1=脉冲链, 2=极简
	static var style: int = 0
	var _active_style: int = 0  # 实际渲染风格 (随机时每个平台的具体值)
	
	func _process(delta: float) -> void:
		if _time == 0.0:
			_active_style = 2 if quiet else (randi_range(0, 2) if style < 0 else style)
		_time += delta
		_expand = minf(_expand + delta / 0.3, 1.0)
		
		# ── 边缘收缩粒子发射监控 ──
		# 判定必须使用父空间坐标（即加上 position.x），只有这样才能在平移和对称展开中精确反映世界坐标系下的单侧缩小。
		var curr_left = position.x - platform_width / 2.0
		var curr_right = position.x + platform_width / 2.0
		
		# 宽度完全展开后，且不是第一帧才检测收缩，避免入场展开时误触发
		if _expand >= 1.0 and _last_left != INF and _last_right != INF:
			# 检测左边缘向右收缩（curr_left 在增大，即往右缩）
			if curr_left > _last_left + 0.1:
				var num_sparks = clampi(int((curr_left - _last_left) / 1.0), 1, 5)
				for i in num_sparks:
					# 粒子发射点必须置于自绘局部空间中的左边界：-platform_width / 2.0
					_spawn_spark(Vector2(-platform_width / 2.0, randf_range(-2.0, 2.0)), -1.0)
			
			# 检测右边缘向左收缩（curr_right 在减小，即往左缩）
			if curr_right < _last_right - 0.1:
				var num_sparks = clampi(int((_last_right - curr_right) / 1.0), 1, 5)
				for i in num_sparks:
					# 粒子发射点必须置于自绘局部空间中的右边界：platform_width / 2.0
					_spawn_spark(Vector2(platform_width / 2.0, randf_range(-2.0, 2.0)), 1.0)
		
		_last_left = curr_left
		_last_right = curr_right
		
		# ── 更新收缩电火花粒子 ──
		var active_particles = []
		var g_sign = pet.gravity_sign if is_instance_valid(pet) else 1.0
		for p in _particles:
			p.life -= delta
			if p.life > 0.0:
				p.pos += p.vel * delta
				p.vel.y += 350.0 * delta * g_sign # 模拟重力/反重力抛落
				p.vel.x *= 0.92                   # 阻尼减速
				active_particles.append(p)
		_particles = active_particles
		
		queue_redraw()
	
	func _spawn_spark(spawn_pos: Vector2, side_dir: float) -> void:
		if quiet: return
		# 特效开关判断：若用户在设置中关闭了踏板收缩火花特效，直接返回
		if not SettingsManager.get_bool("roam_spark", true):
			return
		var p = {}
		p.pos = spawn_pos
		var g_dir = pet.gravity_sign if is_instance_valid(pet) else 1.0
		# 朝收缩相反的方向微弹（side_dir == -1 向左弹，1 向右弹）
		p.vel = Vector2(
			side_dir * randf_range(80.0, 180.0),
			randf_range(-120.0, 10.0) * g_dir
		)
		p.color = platform_color
		# 40% 概率产生高亮超频亮白色/浅蓝色，更有噼啪火光质感
		if randf() > 0.6:
			p.color = Color(1.5, 1.2, 2.0, 1.0)
		else:
			p.color = Color(platform_color.r * 1.5, platform_color.g * 1.5, platform_color.b * 1.5, 1.0)
		p.max_life = randf_range(0.25, 0.45)
		p.life = p.max_life
		p.size = randf_range(1.5, 3.0)
		_particles.append(p)
	
	func _draw() -> void:
		var hw = platform_width / 2.0 * _ease_out(_expand)
		if hw < 1.0:
			return
		
		var pulse = 0.85 + sin(_time * TAU / 2.5) * 0.15
		var c = Color(
			platform_color.r,
			platform_color.g,
			platform_color.b,
			platform_color.a * pulse
		)
		
		match _active_style:
			0: _draw_energy(hw, c)
			1: _draw_pulse_chain(hw, c)
			2: _draw_minimal(hw, c)
			_: _draw_energy(hw, c)
		
		# ── 绘制边缘收缩的噼啪火光粒子 ──
		for p in _particles:
			var alpha = p.life / p.max_life
			var p_color = Color(p.color.r, p.color.g, p.color.b, p.color.a * alpha)
			# 沿粒子运动方向微微拉伸的火花线段，表现出喷射与拉断电火花感
			var length_vec = p.vel * 0.04 * alpha
			draw_line(p.pos, p.pos - length_vec, p_color, p.size, true)
		
	
	# ── 风格 0: 能量束 ──
	func _draw_energy(hw: float, c: Color) -> void:
		# 发光层
		draw_line(Vector2(-hw, 0), Vector2(hw, 0), Color(c.r, c.g, c.b, c.a * 0.15), 12.0, true)
		draw_line(Vector2(-hw, 0), Vector2(hw, 0), Color(c.r, c.g, c.b, c.a * 0.3), 6.0, true)
		draw_line(Vector2(-hw, 0), Vector2(hw, 0), c, 2.0, true)
		# 自适应刻度线
		var tick_gap = 20.0
		var tick_count = clampi(int(hw * 2.0 / tick_gap) - 1, 2, 20)
		var tick_c = Color(c.r, c.g, c.b, c.a * 0.5)
		for i in range(tick_count):
			var t = float(i + 1) / float(tick_count + 1)
			var tx = lerpf(-hw, hw, t)
			draw_line(Vector2(tx, -3.0), Vector2(tx, 3.0), tick_c, 1.0, true)
		# 两端光点
		var dot_c = Color(c.r, c.g, c.b, c.a * 0.9)
		draw_circle(Vector2(-hw, 0), 3.5, dot_c, true, -1.0, true)
		draw_circle(Vector2(hw, 0), 3.5, dot_c, true, -1.0, true)
		var halo_c = Color(c.r, c.g, c.b, c.a * 0.25)
		draw_circle(Vector2(-hw, 0), 6.0, halo_c, true, -1.0, true)
		draw_circle(Vector2(hw, 0), 6.0, halo_c, true, -1.0, true)
		# 汇聚粒子
		if _expand > 0.8:
			_draw_converge_particles(hw, c, 4)
	
	# ── 风格 1: 脉冲链 ──
	func _draw_pulse_chain(hw: float, c: Color) -> void:
		# 底层暗线
		draw_line(Vector2(-hw, 0), Vector2(hw, 0), Color(c.r, c.g, c.b, c.a * 0.15), 4.0, true)
		# 分段依次亮起
		var seg_w = 18.0
		var gap = 3.0
		var total = seg_w + gap
		var seg_count = int(hw * 2.0 / total) + 1
		var wave_speed = 2.0
		for i in range(seg_count):
			var sx = -hw + float(i) * total
			if sx > hw: break
			var ex = minf(sx + seg_w, hw)
			# 每段的亮度波浪: 从左到右依次点亮
			var phase_offset = float(i) * 0.3
			var brightness = 0.3 + 0.7 * maxf(0, sin(_time * wave_speed - phase_offset))
			var seg_c = Color(c.r, c.g, c.b, c.a * brightness)
			draw_line(Vector2(sx, 0), Vector2(ex, 0), seg_c, 3.0, true)
			# 高亮段加发光
			if brightness > 0.7:
				var glow_a = (brightness - 0.7) / 0.3 * c.a * 0.3
				draw_line(Vector2(sx, 0), Vector2(ex, 0), Color(c.r, c.g, c.b, glow_a), 8.0, true)
		# 两端小点
		var dot_c = Color(c.r, c.g, c.b, c.a * 0.9)
		draw_circle(Vector2(-hw, 0), 2.5, dot_c, true, -1.0, true)
		draw_circle(Vector2(hw, 0), 2.5, dot_c, true, -1.0, true)
		if _expand > 0.8:
			_draw_converge_particles(hw, c, 3)
	
	# ── 风格 2: 极简 ──
	func _draw_minimal(hw: float, c: Color) -> void:
		draw_line(Vector2(-hw, 0), Vector2(hw, 0), Color(c.r, c.g, c.b, c.a * 0.1), 8.0, true)
		draw_line(Vector2(-hw, 0), Vector2(hw, 0), Color(c.r, c.g, c.b, c.a * 0.6), 1.5, true)
		var dot_c = Color(c.r, c.g, c.b, c.a * 0.8)
		draw_circle(Vector2(-hw, 0), 2.0, dot_c, true, -1.0, true)
		draw_circle(Vector2(hw, 0), 2.0, dot_c, true, -1.0, true)
	
	# ── 汇聚粒子 (两端→中心) ──
	func _draw_converge_particles(hw: float, c: Color, count: int) -> void:
		var pc = Color(minf(c.r + 0.2, 1.0), minf(c.g + 0.2, 1.0), 1.0)
		for i in range(count):
			var off = float(i) / float(count)
			# 左侧粒子 → 中心
			var lt = fmod(_time * 0.7 + off, 1.0)
			var lx = lerpf(-hw * 0.95, 0, lt)
			var la = sin(lt * PI) * c.a * 0.8
			draw_circle(Vector2(lx, 0), 1.8, Color(pc.r, pc.g, pc.b, la), true, -1.0, true)
			# 右侧粒子 → 中心
			var rt = fmod(_time * 0.7 + off + 0.15, 1.0)
			var rx = lerpf(hw * 0.95, 0, rt)
			var ra = sin(rt * PI) * c.a * 0.8
			draw_circle(Vector2(rx, 0), 1.8, Color(pc.r, pc.g, pc.b, ra), true, -1.0, true)
	
	func _ease_out(t: float) -> float:
		return 1.0 - (1.0 - t) * (1.0 - t)

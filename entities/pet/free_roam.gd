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

const PLATFORM_WIDTH := 65.0             # 踏板基础宽度 (宠物是老手，不需要很宽)

# ── 公共接口 ──

## 屏幕缩放因子 (基准 1080p，4K 约 2.0)
func screen_scale() -> float:
	return pet.boundary_size.y / 1080.0

## 启动自由漫游
func start() -> void:
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
	active = false
	phase = 0
	descending = false
	pet.gravity_scale = pet.gravity_sign
	_elevator = null
	_current_plat = null
	pet.physics_material_override.friction = 0.6  # 确保摩擦力恢复
	# 重置 idle 计时器 (roam 期间 idle_timer 持续累加，不重置会导致
	# finish() 后第一帧 idle 立刻满足转换条件，walk 抢走瞳孔方向)
	if pet.current_state and pet.current_state is StateIdle:
		pet.current_state.idle_timer = 0.0
		pet.current_state.idle_duration = randf_range(0.8, 1.5)

## 每帧更新 (由 pet._process 调用)
func update(delta: float) -> void:
	if not active or phase == 0:
		return
	
	if phase == 1:
		# ── 上升中，检测抛物线顶点 ──
		_airtime += delta
		var vy = pet.linear_velocity.y * pet.gravity_sign
		if vy < -30.0:
			_was_rising = true
		if _was_rising and vy > -20.0 and _airtime > 0.15:
			var platform_y = pet.global_position.y + pet.PET_RADIUS * pet.gravity_sign
			_current_plat = _spawn_platform(Vector2(pet.global_position.x, platform_y))
			_walk_min_x = pet.global_position.x
			_walk_max_x = pet.global_position.x
			_last_pet_x = pet.global_position.x
			# 不人为制动，让宠物保持惯性自然落地
			pet.linear_damp = 0.8
			pet.angular_damp = 1.5
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
			# 踏板本体不动，碰撞体局部偏移追踪宠物
			var plat_x = _current_plat.position.x
			var pet_x = pet.global_position.x
			var offset = pet_x - plat_x
			# 宽度 = 偏移量的两倍 + 基础宽度
			var new_width = absf(offset) * 2.0 + PLATFORM_WIDTH
			for child in _current_plat.get_children():
				if child is CollisionShape2D and not child.has_meta("_roam_wall"):
					var shape = child.shape as RectangleShape2D
					if shape:
						shape.size.x = new_width
					child.position.x = offset
				elif child is PlatformVisual:
					child.platform_width = new_width
					child.position.x = offset
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
		var target_y = _elevator.position.y - pet.PET_RADIUS * pet.gravity_sign
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
			pet.linear_damp = 0.5
			pet.angular_damp = 0.8
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
			var plat_x = _current_plat.position.x
			# 动态更新边界 (只增不缩)
			_walk_min_x = minf(_walk_min_x, pet_x)
			_walk_max_x = maxf(_walk_max_x, pet_x)
			# 两侧各预留 PLATFORM_WIDTH 余量
			var left_edge = _walk_min_x - PLATFORM_WIDTH
			var right_edge = _walk_max_x + PLATFORM_WIDTH
			var new_width = right_edge - left_edge
			var local_offset_x = (left_edge + right_edge) / 2.0 - plat_x
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
			_full_stop()
			phase = 0
			_decide_next()

# ── 跳跃 ──

func do_jump() -> void:
	_remove_side_walls()
	phase = 1
	_was_rising = false
	_airtime = 0.0
	
	var ss = screen_scale()
	var hop_dir = [-1.0, 1.0].pick_random()
	var edge_pad = pet.boundary_size.x * 0.08
	var x = pet.global_position.x
	if x < edge_pad: hop_dir = 1.0
	elif x > pet.boundary_size.x - edge_pad: hop_dir = -1.0
	
	# 跳跃力度 (650~800)
	var vy = randf_range(650.0, 800.0) * ss * -pet.gravity_sign
	var vx = hop_dir * randf_range(60.0, 150.0) * ss
	
	pet.linear_damp = 0.2
	pet.angular_damp = 0.6
	pet.apply_central_impulse(Vector2(vx, vy))
	pet.apply_torque_impulse(hop_dir * randf_range(2000.0, 5000.0) * ss)
	
	pet.eye_behavior.forced_look_dir = Vector2(hop_dir, -pet.gravity_sign).normalized()

# ── 决策 ──

## 落稳后的决策: 继续跳 / 横移 / 跳下 / 电梯
func _decide_next() -> void:
	pet.eye_behavior.forced_look_dir = Vector2.ZERO  # 落稳后恢复自然追踪
	var pause = randf_range(0.6, 1.5)
	await pet.get_tree().create_timer(pause).timeout
	if not active:
		return
	
	var roll = randf()
	if roll < 0.40:
		do_jump()
	elif roll < 0.65:
		_walk_sideways()
	elif roll < 0.90:
		_jump_down()
	else:
		_begin_descent()

# ── 横向滚动 ──

## 空气墙防掉落 + 踏板跟随
func _walk_sideways() -> void:
	var ss = screen_scale()
	var hop_dir = [-1.0, 1.0].pick_random()
	var edge_pad = pet.boundary_size.x * 0.08
	var x = pet.global_position.x
	if x < edge_pad: hop_dir = 1.0
	elif x > pet.boundary_size.x - edge_pad: hop_dir = -1.0
	
	# 连续横移时不重置边界，踏板继续延伸
	var pet_x = pet.global_position.x
	_walk_min_x = minf(_walk_min_x, pet_x)
	_walk_max_x = maxf(_walk_max_x, pet_x)
	
	phase = 4
	_airtime = 0.0
	_last_pet_x = pet.global_position.x
	pet.linear_damp = 0.1
	pet.angular_damp = 0.3
	# 直接设定水平速度，确保宠物真正滚动位移
	pet.linear_velocity = Vector2(hop_dir * randf_range(150.0, 300.0) * ss, pet.linear_velocity.y)
	pet.apply_torque_impulse(hop_dir * randf_range(3000.0, 6000.0) * ss)
	pet.eye_behavior.forced_look_dir = Vector2(hop_dir, 0).normalized()

# ── 跳下 (踏板破碎) ──

## 看向跳跃方向→蓄力→起跳→踏板因冲击破碎
func _jump_down() -> void:
	var ss = screen_scale()
	var hop_dir = [-1.0, 1.0].pick_random()
	var edge_pad = pet.boundary_size.x * 0.08
	var x = pet.global_position.x
	if x < edge_pad: hop_dir = 1.0
	elif x > pet.boundary_size.x - edge_pad: hop_dir = -1.0
	
	# 蓄力: 瞳孔看向跳跃方向
	_full_stop()
	pet.eye_behavior.forced_look_dir = Vector2(hop_dir, 0).normalized()
	await pet.get_tree().create_timer(0.3).timeout
	if not active:
		return
	
	# 移除空气墙
	_remove_side_walls()
	
	# 起跳! (强力横向 + 微小上弹)
	pet.linear_damp = 0.2
	pet.angular_damp = 0.4
	pet.apply_central_impulse(Vector2(hop_dir * randf_range(200.0, 350.0) * ss, randf_range(50.0, 120.0) * -pet.gravity_sign * ss))
	pet.apply_torque_impulse(hop_dir * randf_range(3000.0, 7000.0) * ss)
	pet.eye_behavior.forced_look_dir = Vector2(hop_dir, pet.gravity_sign).normalized()
	
	# 踏板因起跳冲击力破碎
	if is_instance_valid(_current_plat):
		_shatter_platform(_current_plat)
		platforms.erase(_current_plat)
		_current_plat = null
	_clear_platforms()
	
	finish()

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
	
	await pet.get_tree().create_timer(0.6).timeout
	if not active:
		return
	
	_full_stop()
	pet.gravity_scale = 0.0
	
	var platform_y = pet.global_position.y + pet.PET_RADIUS * pet.gravity_sign
	var elevator = _spawn_platform(Vector2(pet.global_position.x, platform_y), true)
	_elevator = elevator
	_elevator_vanish_dist = randf_range(10.0, 50.0) * screen_scale()  # 随机 + 屏幕自适应
	
	pet.eye_behavior.forced_look_dir = Vector2(0, pet.gravity_sign)
	
	phase = 3

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
		platform_y = pet.global_position.y + pet.PET_RADIUS * pet.gravity_sign
	_current_plat = _spawn_platform(Vector2(pet.global_position.x, platform_y))
	_walk_min_x = pet.global_position.x
	_walk_max_x = pet.global_position.x

func _full_stop() -> void:
	pet.linear_velocity.x = 0
	pet.angular_velocity = 0
	pet.linear_damp = 5.0
	pet.angular_damp = 8.0

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
	if active and is_instance_valid(_current_plat) and _current_plat == body:
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
	var _time: float = 0.0
	var _expand: float = 0.0
	var _land_flash: float = 0.0
	var _landed: bool = false
	
	# 风格: -1=随机, 0=能量束, 1=脉冲链, 2=极简
	static var style: int = 0
	var _active_style: int = 0  # 实际渲染风格 (随机时每个平台的具体值)
	
	func _process(delta: float) -> void:
		if _time == 0.0:
			_active_style = randi_range(0, 2) if style < 0 else style
		_time += delta
		_expand = minf(_expand + delta / 0.3, 1.0)
		if _land_flash > 0.0:
			_land_flash = maxf(_land_flash - delta * 3.0, 0.0)
		if not _landed and _time > 0.35:
			_landed = true
			_land_flash = 1.0
		queue_redraw()
	
	func _draw() -> void:
		var hw = platform_width / 2.0 * _ease_out(_expand)
		if hw < 1.0:
			return
		
		var pulse = 0.85 + sin(_time * TAU / 2.5) * 0.15
		var flash = _land_flash * 0.4
		var c = Color(
			minf(platform_color.r + flash, 1.0),
			minf(platform_color.g + flash, 1.0),
			minf(platform_color.b + flash * 0.5, 1.0),
			platform_color.a * pulse
		)
		
		match _active_style:
			0: _draw_energy(hw, c)
			1: _draw_pulse_chain(hw, c)
			2: _draw_minimal(hw, c)
			_: _draw_energy(hw, c)
		
		# 着陆闪光环 (所有风格通用)
		if _land_flash > 0.01:
			var ring_r = hw * (1.0 + (1.0 - _land_flash) * 0.3)
			var ring_c = Color(c.r, c.g, c.b, _land_flash * 0.5)
			draw_arc(Vector2.ZERO, ring_r, 0, TAU, 24, ring_c, 1.5, true)
	
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

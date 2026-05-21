# pet_effects.gd — 宠物视觉特效管理器
# 管理: 冲击波、全息拖影、静电弧、虹彩渐变时间
# 从 pet.gd 拆分，负责特效数据的生命周期和渲染委托
class_name PetEffects
extends RefCounted

var pet: RigidBody2D  # 宿主宠物引用
const _PetColorPalette = preload("res://entities/pet/pet_color_palette.gd")

# ── 拖影系统 ──
var trail_history: Array[Vector2] = []
var max_trail_length: int = 15
var trail_style: int = 1

# ── 冲击波系统 ──
var shockwaves: Array[Dictionary] = []
var shockwave_enabled: bool = true

# ── 虹彩渐变时间 ──
var hue_time: float = 0.0

# ── 特效颜色模式 ──
# 0 = 虹彩 (彩虹循环, 默认)
# 1 = 跟随体色 (纯色, 使用宠物色调)
var effect_color_mode: int = 0

# ── 静电弧 ──
const ARC_RANGE := 150.0    # 触发距离
const ARC_SEGMENTS := 10    # 锯齿线段数
var arc_enabled: bool = true
var arc_nearby: bool = false # 是否有近距离宠物 (用于按需重绘)
var _arc_jitters: Dictionary = {}  # pet_index -> PackedFloat32Array (归一化噪声 -1~1)
var _arc_regen: float = 0.0        # 噪声重生计时器
var _arc_flash: float = 0.0        # 闪烁强度

# ── 数据更新 (由 pet._process 调用) ──

## 更新特效数据，返回是否有视觉变化 (用于按需重绘)
func update(delta: float) -> bool:
	var has_visual_change := false
	
	# 收集或消散残影以形成拖尾特效
	if trail_style > 0 and pet.linear_velocity.length() > 20.0:
		trail_history.push_front(pet.global_position)
		if trail_history.size() > max_trail_length:
			trail_history.pop_back()
		has_visual_change = true
	else:
		if trail_history.size() > 0:
			trail_history.pop_back()
			has_visual_change = true
	
	hue_time += delta * 0.3
	
	# 计算冲击波爆炸圈扩散和消散
	var active_shocks: Array[Dictionary] = []
	for shock in shockwaves:
		shock["radius"] += 350.0 * delta
		shock["alpha"] -= 1.6 * delta
		if shock.has("thickness"):
			shock["thickness"] = maxf(0.5, shock["thickness"] - 12.0 * delta)
		if shock["alpha"] > 0:
			active_shocks.append(shock)
	if shockwaves.size() > 0:
		has_visual_change = true
	shockwaves = active_shocks
	
	# 检测近距离宠物 (静电弧)
	var was_nearby = arc_nearby
	arc_nearby = false
	if arc_enabled and not pet.freeze:
		var main_node = pet.get_tree().root.get_node_or_null("Main")
		if main_node and "pet_instances" in main_node:
			for other in main_node.pet_instances:
				if other == pet or not is_instance_valid(other):
					continue
				# 跳过正在退场的宠物 (freeze=true 表示退场动画中)
				if other.freeze:
					continue
				if _arc_distance(other.global_position) < ARC_RANGE:
					arc_nearby = true
					break
	if arc_nearby or was_nearby:
		has_visual_change = true
	
	# 弧线路径重生计时器 + 闪烁衰减
	_arc_regen -= delta
	if _arc_flash > 0:
		_arc_flash = maxf(_arc_flash - delta * 6.0, 0.0)
	if not arc_nearby:
		_arc_jitters.clear()
	
	return has_visual_change

# ── 触发器 ──

func trigger_shockwave() -> void:
	# 双层高能震荡波，瞬间爆发
	shockwaves.append({"local_pos": Vector2.ZERO, "radius": pet.PET_RADIUS, "alpha": 1.0, "thickness": 6.0})
	shockwaves.append({"local_pos": Vector2.ZERO, "radius": pet.PET_RADIUS * 0.4, "alpha": 0.8, "thickness": 2.5})

func get_shockwave_count() -> int:
	return shockwaves.size()

# ── 渲染 (由 pet._draw 调用，使用宠物的 CanvasItem draw 方法) ──

func render(canvas: CanvasItem) -> void:
	_render_shockwaves(canvas)
	_render_trail(canvas)

func _render_shockwaves(canvas: CanvasItem) -> void:
	for shock in shockwaves:
		var effect_color: Color
		if effect_color_mode == 1:
			# 跟随体色: 纯色冒击波
			effect_color = Color.from_hsv(pet.palette.effective_hue(), 0.7, 1.0, shock["alpha"])
		else:
			# 虹彩: 彩虹循环
			effect_color = Color.from_hsv(fmod(hue_time + pet.palette.effective_hue() - _PetColorPalette.DEFAULT_HUE, 1.0), 0.6, 1.0, shock["alpha"])
		
		# 核心扩散光晕
		var glow_color = effect_color
		glow_color.a *= 0.15
		var thickness = shock.get("thickness", 4.0)
		canvas.draw_circle(shock["local_pos"], maxf(0.1, shock["radius"] - thickness), glow_color)
		
		# 致密外环
		canvas.draw_arc(shock["local_pos"], shock["radius"], 0, TAU, 32, effect_color, thickness, true)

func _render_trail(canvas: CanvasItem) -> void:
	if trail_style == 0:
		return
	match trail_style:
		1: _render_default_trail(canvas)

func _render_default_trail(canvas: CanvasItem) -> void:
	var trail_size = trail_history.size()
	if trail_size < 2:
		return
	
	var pet_hue = pet.palette.effective_hue()
	var points = PackedVector2Array()
	var colors = PackedColorArray()
	for i in range(trail_size):
		var local_pos = canvas.to_local(trail_history[i])
		points.append(local_pos)
		var ratio = 1.0 - float(i) / trail_size
		
		var trail_color: Color
		if effect_color_mode == 1:
			# 跟随体色: 尾端轻微偏移产生渐变感
			trail_color = Color.from_hsv(fmod(pet_hue + ratio * 0.08, 1.0), 0.7, 1.0, ratio * 0.7)
		else:
			# 虹彩: 五光十色的神圣尾迹
			trail_color = Color.from_hsv(fmod(hue_time + pet_hue - _PetColorPalette.DEFAULT_HUE + ratio * 0.3, 1.0), 0.65, 1.0, ratio * 0.7)
		colors.append(trail_color)
		
		if i % 3 == 0 and i > 0:
			var fade_radius = pet.PET_RADIUS * ratio * 0.85
			var core_color = trail_color
			core_color.a = ratio * 0.15
			canvas.draw_circle(local_pos, fade_radius, core_color)
		
	# 最后用高聚焦光束线描绘骨干
	canvas.draw_polyline_colors(points, colors, pet.PET_RADIUS * 0.5, true)

# ── 静电弧 (近距离宠物间的放电弧) ──
# 架构: 只缓存归一化噪声值 (-1~1)，每帧从实时位置重建路径
# 注意: _draw() 中调用前已设置 draw_set_transform(V2.ZERO, -rotation, V2.ONE)
# 因此绘图坐标系 = 以宠物中心为原点的世界对齐空间

func render_arcs(canvas: CanvasItem) -> void:
	if not arc_nearby:
		return
	var main_node = pet.get_tree().root.get_node_or_null("Main")
	if not main_node or not "pet_instances" in main_node:
		return
	var pets: Array = main_node.pet_instances
	var my_idx = pets.find(pet)
	if my_idx < 0:
		return
	
	# 噪声重生: 每 0.07 秒刷新锯齿形状
	var need_regen = _arc_regen <= 0
	if need_regen:
		_arc_regen = 0.07
		# 8% 概率闪烁突变
		if randf() < 0.08:
			_arc_flash = 1.0
	
	var my_hue = pet.palette.effective_hue()
	for i in range(my_idx + 1, pets.size()):
		var other = pets[i]
		if not is_instance_valid(other) or not other.palette:
			continue
		# 跳过正在退场的宠物
		if other.freeze:
			_arc_jitters.erase(i)
			continue
		var dist = _arc_distance(other.global_position)
		if dist >= ARC_RANGE:
			_arc_jitters.erase(i)
			continue
		# 世界对齐空间: 取最短路径的偏移 (屏幕穿越时可能跨边界)
		var other_offset = _arc_offset(other.global_position)
		var intensity = 1.0 - (dist / ARC_RANGE)
		var other_hue = other.palette.effective_hue()
		
		# 缓存或重生噪声
		if need_regen or not _arc_jitters.has(i):
			_arc_jitters[i] = _gen_arc_jitters()
		
		# 每帧从实时位置 + 缓存噪声重建路径
		var path = _build_arc_path(Vector2.ZERO, other_offset, _arc_jitters[i], intensity)
		_draw_lightning(path, canvas, intensity, my_hue, other_hue)

## 生成归一化锯齿噪声 (只是 -1~1 随机值，与位置无关)
func _gen_arc_jitters() -> PackedFloat32Array:
	var jitters = PackedFloat32Array()
	jitters.append(0.0)  # 起点: 无偏移，锚定宠物中心
	for i in range(1, ARC_SEGMENTS):
		jitters.append(randf_range(-1.0, 1.0))
	jitters.append(0.0)  # 终点: 无偏移，锚定对方中心
	return jitters

## 从实时端点 + 缓存噪声构建路径 (每帧调用)
func _build_arc_path(from: Vector2, to: Vector2, jitters: PackedFloat32Array, intensity: float) -> PackedVector2Array:
	var dir = to - from
	var perp = Vector2(-dir.y, dir.x).normalized()
	var jitter_scale = 14.0 * intensity
	var points = PackedVector2Array()
	var n = jitters.size()
	for i in range(n):
		var t = float(i) / float(n - 1)
		var base = from.lerp(to, t)
		points.append(base + perp * jitters[i] * jitter_scale)
	return points

func _draw_lightning(points: PackedVector2Array, canvas: CanvasItem, intensity: float, hue_a: float, hue_b: float) -> void:
	if points.size() < 2:
		return
	
	var alpha = intensity * 0.85 + _arc_flash * 0.15
	
	# 第1层: 双色渐变辉光 (宠物A色→宠物B色)
	var glow_colors = PackedColorArray()
	for i in range(points.size()):
		var t = float(i) / (points.size() - 1)
		var h = lerpf(hue_a, hue_b, t)
		# 处理色环跨越 (0→1边界)
		if absf(hue_a - hue_b) > 0.5:
			var a = hue_a if hue_a > hue_b else hue_a + 1.0
			var b = hue_b if hue_b > hue_a else hue_b + 1.0
			h = fmod(lerpf(a, b, t), 1.0)
		glow_colors.append(Color.from_hsv(h, 0.75, 1.0, alpha * 0.55))
	canvas.draw_polyline_colors(points, glow_colors, 7.0 * intensity + 5.0, true)
	
	# 第2层: 白色闪电内核
	var core = Color(0.9, 0.95, 1.0, alpha)
	canvas.draw_polyline(points, core, 2.5 * intensity + 1.5, true)
	
	# 两端电弧集结点的高光
	canvas.draw_circle(points[0], 3.0, Color(1.0, 1.0, 1.0, alpha * 0.8))
	canvas.draw_circle(points[-1], 3.0, Color(1.0, 1.0, 1.0, alpha * 0.8))

# ── 屏幕穿越辅助 (取直接距离和环绕距离中的最短) ──

func _arc_distance(other_pos: Vector2) -> float:
	var dist = pet.global_position.distance_to(other_pos)
	if not pet.screen_wrap:
		return dist
	var w = pet.boundary_size.x
	var shifted = other_pos
	shifted.x += w
	dist = min(dist, pet.global_position.distance_to(shifted))
	shifted.x -= w * 2
	dist = min(dist, pet.global_position.distance_to(shifted))
	return dist

func _arc_offset(other_pos: Vector2) -> Vector2:
	var offset = other_pos - pet.global_position
	if pet.screen_wrap:
		var w = pet.boundary_size.x
		if offset.x > w / 2.0:
			offset.x -= w
		elif offset.x < -w / 2.0:
			offset.x += w
	return offset

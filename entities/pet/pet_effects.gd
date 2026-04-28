# pet_effects.gd — 宠物视觉特效管理器
# 管理: 冲击波、全息拖影、能量共鸣弧、虹彩渐变时间
# 从 pet.gd 拆分，负责特效数据的生命周期和渲染委托
class_name PetEffects
extends RefCounted

var pet: RigidBody2D  # 宿主宠物引用
const _PetColorPalette = preload("res://entities/pet/pet_color_palette.gd")

# ── 拖影系统 ──
var trail_history: Array[Vector2] = []
var max_trail_length: int = 15
var trail_enabled: bool = true

# ── 冲击波系统 ──
var shockwaves: Array[Dictionary] = []
var shockwave_enabled: bool = true

# ── 虹彩渐变时间 ──
var hue_time: float = 0.0

# ── 特效颜色模式 ──
# 0 = 虹彩 (彩虹循环, 默认)
# 1 = 跟随体色 (纯色, 使用宠物色调)
var effect_color_mode: int = 0

# ── 能量共鸣弧 ──
const ARC_RANGE := 150.0    # 触发距离
var arc_enabled: bool = true
var arc_nearby: bool = false # 是否有近距离宠物 (用于按需重绘)

# ── 数据更新 (由 pet._process 调用) ──

## 更新特效数据，返回是否有视觉变化 (用于按需重绘)
func update(delta: float) -> bool:
	var has_visual_change := false
	
	# 收集或消散残影以形成拖尾特效
	if trail_enabled and pet.linear_velocity.length() > 20.0:
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
		shock["radius"] += 400.0 * delta
		shock["alpha"] -= 1.8 * delta
		if shock["alpha"] > 0:
			active_shocks.append(shock)
	if shockwaves.size() > 0:
		has_visual_change = true
	shockwaves = active_shocks
	
	# 检测近距离宠物 (能量共鸣弧)
	var was_nearby = arc_nearby
	arc_nearby = false
	if arc_enabled:
		var main_node = pet.get_tree().root.get_node_or_null("Main")
		if main_node and "pet_instances" in main_node:
			for other in main_node.pet_instances:
				if other == pet or not is_instance_valid(other):
					continue
				if pet.global_position.distance_to(other.global_position) < ARC_RANGE:
					arc_nearby = true
					break
	if arc_nearby or was_nearby:
		has_visual_change = true
	
	return has_visual_change

# ── 触发器 ──

func trigger_shockwave() -> void:
	# 双层高能震荡波，瞬间爆发
	shockwaves.append({"local_pos": Vector2.ZERO, "radius": pet.PET_RADIUS, "alpha": 1.0})
	shockwaves.append({"local_pos": Vector2.ZERO, "radius": pet.PET_RADIUS * 0.4, "alpha": 0.5})

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
		canvas.draw_arc(shock["local_pos"], shock["radius"], 0, TAU, 32, effect_color, 4.0, true)

func _render_trail(canvas: CanvasItem) -> void:
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
		
		var fade_radius = pet.PET_RADIUS * ratio * 0.85
		var core_color = trail_color
		core_color.a = ratio * 0.15
		canvas.draw_circle(local_pos, fade_radius, core_color)
		
	# 最后用高聚焦光束线描绘骨干
	canvas.draw_polyline_colors(points, colors, pet.PET_RADIUS * 0.5, true)

# ── 能量共鸣弧 (近距离宠物间的静电放电弧) ──

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
	# 只由 index 较小的宠物绘制，避免重复
	var my_hue = pet.palette.effective_hue()
	for i in range(my_idx + 1, pets.size()):
		var other = pets[i]
		if not is_instance_valid(other) or not other.palette:
			continue
		var dist = pet.global_position.distance_to(other.global_position)
		if dist >= ARC_RANGE:
			continue
		var other_local = canvas.to_local(other.global_position)
		var intensity = 1.0 - (dist / ARC_RANGE)
		var other_hue = other.palette.effective_hue()
		_draw_lightning(canvas, Vector2.ZERO, other_local, intensity, my_hue, other_hue)

func _draw_lightning(canvas: CanvasItem, from: Vector2, to: Vector2, intensity: float, hue_a: float, hue_b: float) -> void:
	var seg_count := 10
	var dir = to - from
	var perp = Vector2(-dir.y, dir.x).normalized()
	var jitter_strength = 14.0 * intensity
	
	# 生成锯齿状闪电路径
	var points = PackedVector2Array()
	points.append(from)
	for i in range(1, seg_count):
		var t = float(i) / seg_count
		var base = from.lerp(to, t)
		var jitter = perp * randf_range(-jitter_strength, jitter_strength)
		points.append(base + jitter)
	points.append(to)
	
	# 随机放电闪烁 (8% 概率突然变亮)
	var alpha = intensity * 0.85
	if randf() < 0.08:
		alpha = minf(alpha + 0.2, 1.0)
	
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
	
	# 第2层: 白色闪电内核 (真实闪电色)
	var core = Color(0.9, 0.95, 1.0, alpha)
	canvas.draw_polyline(points, core, 2.5 * intensity + 1.5, true)

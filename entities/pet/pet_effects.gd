# pet_effects.gd — 宠物视觉特效管理器
# 管理: 冲击波、全息拖影、虹彩渐变时间
# 从 pet.gd 拆分，负责特效数据的生命周期和渲染委托
# 未来新增特效 (粒子爆炸、残像闪烁等) 在此扩展
class_name PetEffects
extends RefCounted

var pet: RigidBody2D  # 宿主宠物引用

# ── 拖影系统 ──
var trail_history: Array[Vector2] = []
var max_trail_length: int = 15
var trail_enabled: bool = true

# ── 冲击波系统 ──
var shockwaves: Array[Dictionary] = []
var shockwave_enabled: bool = true

# ── 虹彩渐变时间 ──
var hue_time: float = 0.0

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
		var effect_color = Color.from_hsv(fmod(hue_time + pet.clone_hue_shift, 1.0), 0.6, 1.0, shock["alpha"])
		# 高科技空心雷达弧辐射
		canvas.draw_arc(shock["local_pos"], shock["radius"], 0, TAU, 32, effect_color, 4.0, true)

func _render_trail(canvas: CanvasItem) -> void:
	var trail_size = trail_history.size()
	if trail_size < 2:
		return
	
	var points = PackedVector2Array()
	var colors = PackedColorArray()
	for i in range(trail_size):
		var local_pos = canvas.to_local(trail_history[i])
		points.append(local_pos)
		var ratio = 1.0 - float(i) / trail_size
		
		# HSL 颜色空间：hue随时间加随粒子尾巴顺延发生偏转，产生五光十色的神圣尾迹！
		var trail_color = Color.from_hsv(fmod(hue_time + pet.clone_hue_shift + ratio * 0.3, 1.0), 0.65, 1.0, ratio * 0.7)
		colors.append(trail_color)
		
		var fade_radius = pet.PET_RADIUS * ratio * 0.85
		var core_color = trail_color
		core_color.a = ratio * 0.15
		canvas.draw_circle(local_pos, fade_radius, core_color)
		
	# 最后用高聚焦光束线描绘骨干
	canvas.draw_polyline_colors(points, colors, pet.PET_RADIUS * 0.5, true)

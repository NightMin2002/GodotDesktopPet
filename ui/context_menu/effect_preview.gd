# effect_preview.gd — 特效预览子系统 (RefCounted)
# 负责: 特效开关项的 hover 动画预览面板 (撞击冲击波 / 粒子尾流 / 静电弧)
# 从 context_menu.gd 拆分，遵循 RefCounted 子系统模式
extends RefCounted

var _menu  # context_menu 引用

# ── 预览条目注册表 ──
# key = setting_id, value = { panel, ctrl, btn }
var _entries: Dictionary = {}

func _init(menu_ref) -> void:
	_menu = menu_ref

# ═══════════════════════════════════════════
# 公共接口
# ═══════════════════════════════════════════

## 构建全部预览 (在 L3 特效面板创建完毕后调用)
func build() -> void:
	_register("shockwave", ShockwavePreview.new(), "高速撞击时爆发冲击波", Vector2(140, 100))
	_register("trail_fx",  TrailPreview.new(),     "运动轨迹的发光尾迹", Vector2(160, 80))
	_register("arc_fx",    ArcPreview.new(),       "宠物间的能量弧线",   Vector2(160, 80))

## 每帧定位跟踪 (由 context_menu._process 调用)
func update_positions() -> void:
	for entry in _entries.values():
		var panel = entry.panel as PanelContainer
		if is_instance_valid(panel) and panel.visible:
			_position_panel(panel, entry.btn)

# ═══════════════════════════════════════════
# 内部: 注册 + 面板生命周期
# ═══════════════════════════════════════════

func _register(setting_id: String, ctrl: Control, desc_text: String, ctrl_size: Vector2) -> void:
	var btn = _menu._submenu.l3_items.get(setting_id) as Button
	if not btn:
		return
	var panel = _make_panel(ctrl, desc_text, ctrl_size)
	var entry = { "panel": panel, "ctrl": ctrl, "btn": btn }
	_entries[setting_id] = entry
	# hover 信号绑定
	btn.mouse_entered.connect(func(): _show(entry))
	btn.mouse_exited.connect(func(): _hide(entry))

## 创建预览面板容器 (深色圆角卡片 + 动画区域 + 描述文字)
func _make_panel(ctrl: Control, desc_text: String, ctrl_size: Vector2) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.1, 0.95)
	style.border_color = Color.from_hsv(EventBus.ui_hue, 0.7, 1.0, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	ctrl.custom_minimum_size = ctrl_size
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(ctrl)
	var desc = Label.new()
	desc.text = desc_text
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.45, 0.6, 0.8, 0.7))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc)
	_menu.add_child(panel)
	return panel

## 弹簧动画显示
func _show(entry: Dictionary) -> void:
	var panel = entry.panel as PanelContainer
	var ctrl = entry.ctrl as Control
	ctrl.set_process(true)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.7, 0.7)
	panel.show()
	await _menu.get_tree().process_frame
	_position_panel(panel, entry.btn)
	var tween = _menu.create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 缩放淡出隐藏
func _hide(entry: Dictionary) -> void:
	var ctrl = entry.ctrl as Control
	var panel = entry.panel as PanelContainer
	ctrl.set_process(false)
	var tween = _menu.create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.1)
	tween.tween_property(panel, "scale", Vector2(0.7, 0.7), 0.1)
	tween.finished.connect(func(): panel.hide())

## 方向感知定位 (紧随 L3 特效面板外侧)
func _position_panel(panel: PanelContainer, btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var effects_panel = _menu._submenu.l3_panels.get("effects")
	var ref_pos: Vector2
	var ref_w: float
	if is_instance_valid(effects_panel) and effects_panel.visible:
		ref_pos = effects_panel.global_position
		ref_w = effects_panel.size.x
	else:
		ref_pos = btn.global_position
		ref_w = btn.size.x
	var btn_pos = btn.global_position
	var btn_size = btn.size
	var vp_size = _menu.get_viewport().get_visible_rect().size
	var panel_w = panel.size.x
	var gap := 16.0
	var x: float
	if _menu._menu_side == 1:
		x = ref_pos.x + ref_w + gap
		if x + panel_w > vp_size.x - 10: x = ref_pos.x - panel_w - gap
		panel.pivot_offset = Vector2(0, panel.size.y / 2.0)
	else:
		x = ref_pos.x - panel_w - gap
		if x < 10: x = ref_pos.x + ref_w + gap
		panel.pivot_offset = Vector2(panel_w, panel.size.y / 2.0)
	var y = btn_pos.y + btn_size.y / 2.0 - panel.size.y / 2.0
	y = clampf(y, 8.0, vp_size.y - panel.size.y - 8.0)
	panel.position = Vector2(x, y)

# ═══════════════════════════════════════════
# 动画预览 Control: 撞击冲击波
# ═══════════════════════════════════════════
class ShockwavePreview extends Control:
	var _time: float = 0.0
	var _waves: Array[Dictionary] = []  # {radius, alpha}
	var _trigger_timer: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		_trigger_timer -= delta
		if _trigger_timer <= 0:
			_trigger_timer = 1.2
			_waves.append({"radius": 8.0, "alpha": 1.0})
			_waves.append({"radius": 3.0, "alpha": 0.5})
		var active: Array[Dictionary] = []
		for w in _waves:
			w["radius"] += 100.0 * delta
			w["alpha"] -= 1.8 * delta
			if w["alpha"] > 0:
				active.append(w)
		_waves = active
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y * 0.55
		var hue = EventBus.ui_hue
		var r = 8.0
		var center = Vector2(cx, cy)
		var body_color = Color.from_hsv(hue, 0.5, 0.8, 0.6)
		draw_circle(center, r, body_color, true, -1.0, true)
		var pupil_c = Color.from_hsv(hue, 0.3, 1.0, 0.9)
		draw_circle(center + Vector2(0, -1), 3.0, pupil_c, true, -1.0, true)
		var ground_y = cy + r + 1.0
		draw_line(Vector2(cx - 40, ground_y), Vector2(cx + 40, ground_y), Color(0.3, 0.4, 0.6, 0.3), 1.0, true)
		for w in _waves:
			var wave_hue = fmod(_time * 0.3 + hue, 1.0)
			var c = Color.from_hsv(wave_hue, 0.6, 1.0, w["alpha"])
			draw_arc(center, w["radius"], 0, TAU, 32, c, 3.0, true)

# ═══════════════════════════════════════════
# 动画预览 Control: 粒子尾流
# ═══════════════════════════════════════════
class TrailPreview extends Control:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 8.0
		var trail_len := 12
		var pet_x = cx + sin(_time * 2.5) * 35.0
		var pet_y = cy + cos(_time * 3.7) * 12.0
		var pet_pos = Vector2(pet_x, pet_y)
		var points = PackedVector2Array()
		var colors = PackedColorArray()
		for i in range(trail_len):
			var t_off = float(i) * 0.04
			var hx = cx + sin((_time - t_off) * 2.5) * 35.0
			var hy = cy + cos((_time - t_off) * 3.7) * 12.0
			points.append(Vector2(hx, hy))
			var ratio = 1.0 - float(i) / trail_len
			var trail_hue = fmod(hue + _time * 0.3 + ratio * 0.3, 1.0)
			var c = Color.from_hsv(trail_hue, 0.65, 1.0, ratio * 0.7)
			colors.append(c)
			var fade_r = r * ratio * 0.85
			var core_c = Color(c.r, c.g, c.b, ratio * 0.15)
			draw_circle(Vector2(hx, hy), fade_r, core_c)
		if points.size() >= 2:
			draw_polyline_colors(points, colors, r * 0.5, true)
		var body_color = Color.from_hsv(hue, 0.5, 0.8, 0.7)
		draw_circle(pet_pos, r, body_color, true, -1.0, true)
		var pupil_offset = Vector2(cos(_time * 2.5) * 2.0, -sin(_time * 3.7) * 1.0)
		var pupil_c = Color.from_hsv(hue, 0.3, 1.0, 0.9)
		draw_circle(pet_pos + pupil_offset, 3.0, pupil_c, true, -1.0, true)

# ═══════════════════════════════════════════
# 动画预览 Control: 静电弧
# ═══════════════════════════════════════════
class ArcPreview extends Control:
	var _time: float = 0.0
	var _regen_timer: float = 0.0
	var _path_cache: PackedVector2Array = []
	var _flash: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		_regen_timer -= delta
		if _flash > 0: _flash = maxf(_flash - delta * 6.0, 0.0)
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 8.0
		var dist = 50.0
		var left_c = Vector2(cx - dist, cy)
		var right_c = Vector2(cx + dist, cy)
		var body_color = Color.from_hsv(hue, 0.5, 0.8, 0.6)
		draw_circle(left_c, r, body_color, true, -1.0, true)
		draw_circle(right_c, r, body_color, true, -1.0, true)
		var pupil_c = Color.from_hsv(hue, 0.3, 1.0, 0.9)
		draw_circle(left_c + Vector2(2, -1), 3.0, pupil_c, true, -1.0, true)
		draw_circle(right_c + Vector2(-2, -1), 3.0, pupil_c, true, -1.0, true)
		if _regen_timer <= 0:
			_regen_timer = 0.07
			_path_cache = _gen_lightning(left_c + Vector2(r, 0), right_c - Vector2(r, 0))
			if randf() < 0.08:
				_flash = 1.0
		if _path_cache.size() < 2:
			return
		var alpha = 0.85 + _flash * 0.15
		var hue_a = hue
		var hue_b = fmod(hue + 0.3, 1.0)
		var glow_colors = PackedColorArray()
		for i in range(_path_cache.size()):
			var t = float(i) / float(_path_cache.size() - 1)
			var h = lerpf(hue_a, hue_b, t)
			glow_colors.append(Color.from_hsv(h, 0.75, 1.0, alpha * 0.55))
		draw_polyline_colors(_path_cache, glow_colors, 7.0, true)
		var core = Color(0.9, 0.95, 1.0, alpha)
		draw_polyline(_path_cache, core, 2.0, true)

	func _gen_lightning(from: Vector2, to: Vector2) -> PackedVector2Array:
		var seg_count := 10
		var dir = to - from
		var perp = Vector2(-dir.y, dir.x).normalized()
		var jitter_strength = 14.0
		var points = PackedVector2Array()
		points.append(from)
		for i in range(1, seg_count):
			var t = float(i) / seg_count
			var base = from.lerp(to, t)
			var jitter = perp * randf_range(-jitter_strength, jitter_strength)
			points.append(base + jitter)
		points.append(to)
		return points

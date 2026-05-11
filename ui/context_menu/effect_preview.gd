# effect_preview.gd — 菜单预览子系统 (RefCounted)
# 负责: 菜单开关/单选项的 hover 动画预览面板
# 支持任意 L3 面板的预览注册，通过 l3_id 动态定位
# 从 context_menu.gd 拆分，遵循 RefCounted 子系统模式
extends RefCounted

var _menu  # context_menu 引用

# ── 预览条目注册表 ──
# key = 唯一ID, value = { panel, ctrl, btn, l3_id }
var _entries: Dictionary = {}

func _init(menu_ref) -> void:
	_menu = menu_ref

# ═══════════════════════════════════════════
# 公共接口
# ═══════════════════════════════════════════

## 构建全部预览 (在所有 L3 面板创建完毕后调用)
func build() -> void:
	# ── 特效预览 (L3: "effects") ──
	_register_toggle("shockwave", "effects", ShockwavePreview.new(), "高速撞击时爆发冲击波", Vector2(140, 100))
	_register_toggle("trail_fx",  "effects", TrailPreview.new(),     "运动轨迹的发光尾迹", Vector2(160, 80))
	_register_toggle("arc_fx",    "effects", ArcPreview.new(),       "宠物间的能量弧线",   Vector2(160, 80))
	# ── 窗口模式预览 (L3: "window_mode") ──
	_register_radio("window_mode", 0, "wm_free",     WindowFreePreview.new(),     "在窗口间自由行走跳跃", Vector2(180, 100))
	_register_radio("window_mode", 1, "wm_confined",  WindowConfinedPreview.new(), "被困在窗口内部无法离开", Vector2(180, 100))
	_register_radio("window_mode", 2, "wm_repelled",  WindowRepelledPreview.new(), "被窗口推开无法进入", Vector2(180, 100))

## 每帧定位跟踪 (由 context_menu._process 调用)
func update_positions() -> void:
	for entry in _entries.values():
		var panel = entry.panel as PanelContainer
		if is_instance_valid(panel) and panel.visible:
			_position_panel(entry)

# ═══════════════════════════════════════════
# 内部: 注册
# ═══════════════════════════════════════════

## 注册 toggle 项预览 (通过 l3_items 查找按钮)
func _register_toggle(setting_id: String, l3_id: String, ctrl: Control, desc_text: String, ctrl_size: Vector2) -> void:
	var btn = _menu._submenu.l3_items.get(setting_id) as Button
	if not btn:
		return
	_add_entry(setting_id, btn, l3_id, ctrl, desc_text, ctrl_size)

## 注册 radio 项预览 (通过 _l3_radio_buttons 查找按钮)
func _register_radio(menu_id: String, value: int, entry_id: String, ctrl: Control, desc_text: String, ctrl_size: Vector2) -> void:
	var radio_group = _menu._submenu._l3_radio_buttons.get(menu_id) as Array
	if not radio_group:
		return
	for item in radio_group:
		if item.value == value:
			_add_entry(entry_id, item.btn, menu_id, ctrl, desc_text, ctrl_size)
			return

## 通用: 创建面板 + 绑定 hover + 写入注册表
func _add_entry(entry_id: String, btn: Button, l3_id: String, ctrl: Control, desc_text: String, ctrl_size: Vector2) -> void:
	var panel = _make_panel(ctrl, desc_text, ctrl_size)
	var entry = { "panel": panel, "ctrl": ctrl, "btn": btn, "l3_id": l3_id }
	_entries[entry_id] = entry
	btn.mouse_entered.connect(func(): _show(entry))
	btn.mouse_exited.connect(func(): _hide(entry))

# ═══════════════════════════════════════════
# 面板生命周期
# ═══════════════════════════════════════════

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
	_position_panel(entry)
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

## 方向感知定位 (紧随对应 L3 面板外侧)
func _position_panel(entry: Dictionary) -> void:
	var btn = entry.btn as Button
	var panel = entry.panel as PanelContainer
	if not is_instance_valid(btn):
		return
	# 动态查找对应的 L3 面板作为定位参考
	var l3_panel = _menu._submenu.l3_panels.get(entry.l3_id)
	var ref_pos: Vector2
	var ref_w: float
	if is_instance_valid(l3_panel) and l3_panel.visible:
		ref_pos = l3_panel.global_position
		ref_w = l3_panel.size.x
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
# 基础预览 Control (共用绘制方法)
# ═══════════════════════════════════════════
class ViewBase extends Control:
	func _draw_holo_pet(center: Vector2, hue: float, r: float = 6.0) -> void:
		# 底层光晕
		var glow_c = Color.from_hsv(hue, 0.6, 1.0, 0.15)
		draw_circle(center, r + 2.5, glow_c, true, -1.0, true)
		# 科技感单体球层叠 (立体发光感，无眼睛)
		var c1 = Color.from_hsv(hue, 0.5, 0.9, 0.5)
		draw_circle(center, r, c1, true, -1.0, true)
		var c2 = Color.from_hsv(hue, 0.3, 1.0, 0.7)
		draw_circle(center, r * 0.7, c2, true, -1.0, true)
		var c3 = Color.from_hsv(hue, 0.1, 1.0, 0.9)
		draw_circle(center, r * 0.3, c3, true, -1.0, true)
		# 锐利的发光边界
		var rim_c = Color.from_hsv(hue, 0.2, 1.0, 0.8)
		draw_arc(center, r, 0, TAU, 24, rim_c, 1.0, true)

# ═══════════════════════════════════════════
# 动画预览 Control: 撞击冲击波
# ═══════════════════════════════════════════
class ShockwavePreview extends ViewBase:
	var _time: float = 0.0
	var _waves: Array[Dictionary] = []
	var _trigger_timer: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		_trigger_timer -= delta
		if _trigger_timer <= 0:
			_trigger_timer = 1.2
			_waves.append({"radius": 6.0, "alpha": 1.0, "thickness": 6.0})
			_waves.append({"radius": 2.4, "alpha": 0.8, "thickness": 2.5})
		var active: Array[Dictionary] = []
		for w in _waves:
			w["radius"] += 150.0 * delta
			w["alpha"] -= 1.6 * delta
			w["thickness"] = maxf(0.5, w["thickness"] - 5.0 * delta)
			if w["alpha"] > 0:
				active.append(w)
		_waves = active
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var r = 6.0
		var ground_y = size.y * 0.75
		var hue = EventBus.ui_hue

		# 宠物跳跃轨迹 (抛物线)
		var t = 1.0 - maxf(0.0, _trigger_timer / 1.2)
		var jump_y = ground_y - r - abs(sin(t * PI)) * 25.0
		var center = Vector2(cx, jump_y)

		# 科技感发光地面线
		draw_line(Vector2(cx - 50, ground_y), Vector2(cx + 50, ground_y), Color(0.3, 0.5, 0.8, 0.2), 2.0, true)
		draw_line(Vector2(cx - 20, ground_y), Vector2(cx + 20, ground_y), Color(0.4, 0.7, 1.0, 0.5), 1.0, true)

		# 以宠物真实中心为圆心的全方位冲击波 (严格匹配实机游戏中的跟随效果)
		for w in _waves:
			var wave_hue = fmod(_time * 0.2 + hue, 1.0)
			var c = Color.from_hsv(wave_hue, 0.6, 1.0, w["alpha"])
			
			# 核心扩散光晕
			var glow_color = c
			glow_color.a *= 0.15
			draw_circle(center, maxf(0.1, w["radius"] - w["thickness"]), glow_color)
			
			# 致密全圆弧
			draw_arc(center, w["radius"], 0, TAU, 32, c, w["thickness"], true)

		_draw_holo_pet(center, hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 粒子尾流
# ═══════════════════════════════════════════
class TrailPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 6.0
		var trail_len := 15
		var points = PackedVector2Array()
		var colors = PackedColorArray()
		
		# 柔和的无限大(Lissajous)轨迹
		var pet_pos = Vector2(cx + sin(_time * 2.5) * 45.0, cy + sin(_time * 5.0) * 15.0)
		
		# 尾迹追踪
		for i in range(trail_len):
			var t_off = float(i) * 0.035
			var hx = cx + sin((_time - t_off) * 2.5) * 45.0
			var hy = cy + sin((_time - t_off) * 5.0) * 15.0
			points.append(Vector2(hx, hy))
			var ratio = 1.0 - float(i) / trail_len
			# 顺滑的色相渐变
			var c = Color.from_hsv(fmod(hue + ratio * 0.2, 1.0), 0.6, 1.0, ratio * 0.7)
			colors.append(c)
			# 每隔几个点画一个残影虚圈
			if i % 3 == 0 and i > 0:
				draw_circle(Vector2(hx, hy), r * ratio * 0.8, Color(c.r, c.g, c.b, ratio * 0.2))

		# 主发光尾迹线
		if points.size() >= 2:
			draw_polyline_colors(points, colors, r * 1.2, true)
			
		_draw_holo_pet(pet_pos, hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 静电弧
# ═══════════════════════════════════════════
class ArcPreview extends ViewBase:
	var _time: float = 0.0
	var _regen_timer: float = 0.0
	var _path_cache: PackedVector2Array = []
	var _flash: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		_regen_timer -= delta
		if _flash > 0: _flash = maxf(_flash - delta * 5.0, 0.0)
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 6.0
		
		# 宠物轻微悬浮游动
		var left_c = Vector2(cx - 35 + sin(_time * 1.2) * 5.0, cy + cos(_time * 1.5) * 3.0)
		var right_c = Vector2(cx + 35 + sin(_time * 1.4) * 4.0, cy + sin(_time * 1.1) * 4.0)

		# 刷新闪电路径
		if _regen_timer <= 0:
			_regen_timer = randf_range(0.04, 0.08)
			_path_cache = _gen_lightning(left_c + Vector2(r, 0), right_c - Vector2(r, 0))
			if randf() < 0.15:
				_flash = 1.0
				
		# 绘制极光电弧
		if _path_cache.size() >= 2:
			var alpha = 0.6 + _flash * 0.4
			var glow_colors = PackedColorArray()
			for i in range(_path_cache.size()):
				var p_ratio = float(i) / _path_cache.size()
				glow_colors.append(Color.from_hsv(fmod(hue + p_ratio*0.2, 1.0), 0.6, 1.0, alpha * 0.6))
			
			draw_polyline_colors(_path_cache, glow_colors, 8.0, true)  # 外发光宽条
			draw_polyline(_path_cache, Color(1, 1, 1, alpha), 1.5, true) # 核心高亮
			
			# 两端电弧集结点的高光
			draw_circle(_path_cache[0], 3.0, Color(1,1,1, alpha*0.8))
			draw_circle(_path_cache[-1], 3.0, Color(1,1,1, alpha*0.8))

		_draw_holo_pet(left_c, hue, r)
		_draw_holo_pet(right_c, hue, r)

	func _gen_lightning(from: Vector2, to: Vector2) -> PackedVector2Array:
		var seg_count := 8
		var dir = to - from
		var perp = Vector2(-dir.y, dir.x).normalized()
		var points = PackedVector2Array()
		points.append(from)
		for i in range(1, seg_count):
			var t = float(i) / seg_count
			var base = from.lerp(to, t)
			var jitter_amp = 18.0 * sin(t * PI) # 中间抖动幅度大
			var jitter = perp * randf_range(-jitter_amp, jitter_amp)
			points.append(base + jitter)
		points.append(to)
		return points

# ═══════════════════════════════════════════
# 动画预览 Control: 窗口模式 - 自由漫游
# ═══════════════════════════════════════════
class WindowFreePreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 6.0
		var win_c = Color(0.2, 0.35, 0.6, 0.35)
		var win_border = Color(0.3, 0.5, 0.8, 0.5)
		
		var w1 = Rect2(cx - 70, cy - 15, 55, 35)
		var w2 = Rect2(cx + 15, cy - 10, 55, 35)
		draw_rect(w1, win_c, true)
		draw_rect(w1, win_border, false, 1.0)
		draw_rect(w2, win_c, true)
		draw_rect(w2, win_border, false, 1.0)
		
		# 窗口顶边/底边高亮
		draw_line(Vector2(w1.position.x, w1.position.y), Vector2(w1.end.x, w1.position.y), Color(0.4, 0.7, 1.0, 0.5), 2.0)
		draw_line(Vector2(w2.position.x + 2, w2.end.y - 1), Vector2(w2.end.x - 2, w2.end.y - 1), Color(0.3, 0.8, 0.5, 0.4), 1.5)
		
		var phase = fmod(_time * 0.55, 1.0)
		var px: float
		var py: float
		
		if phase < 0.35:
			# 在窗口1顶部行走
			var t = phase / 0.35
			px = w1.position.x + 6 + t * (w1.size.x - 12)
			py = w1.position.y - r
		elif phase < 0.5:
			# 跳入窗口2
			var t = (phase - 0.35) / 0.15
			px = lerpf(w1.end.x, w2.position.x + w2.size.x / 2, t)
			var start_y = w1.position.y - r
			var end_y = w2.end.y - r - 2
			py = lerpf(start_y, end_y, t) - sin(t * PI) * 22.0
		elif phase < 0.85:
			# 在窗口2内部游走
			var t = (phase - 0.5) / 0.35
			var inner_left = w2.position.x + r + 3
			var inner_right = w2.end.x - r - 3
			var inner_mid = w2.position.x + w2.size.x / 2
			if t < 0.5:
				px = lerpf(inner_mid, inner_right, t * 2)
			else:
				px = lerpf(inner_right, inner_left, (t - 0.5) * 2)
			py = w2.end.y - r - 2
		else:
			# 跳出
			var t = (phase - 0.85) / 0.15
			px = lerpf(w2.position.x + r + 3, w1.position.x + 6, t)
			var start_y = w2.end.y - r - 2
			var end_y = w1.position.y - r
			py = lerpf(start_y, end_y, t) - sin(t * PI) * 18.0

		# 自由路径虚线残留
		var path_c = Color(0.4, 0.8, 1.0, 0.15)
		for i in range(5):
			var dist_x = px - cx
			draw_circle(Vector2(px - float(i)*sign(dist_x)*2.0, py + float(i)*0.5), 1.5 - float(i)*0.2, path_c)

		_draw_holo_pet(Vector2(px, py), hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 窗口模式 - 窗口封闭
# ═══════════════════════════════════════════
class WindowConfinedPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 6.0
		var win_c = Color(0.2, 0.35, 0.6, 0.35)
		var win_border = Color(0.6, 0.3, 0.3, 0.6)
		
		var win = Rect2(cx - 50, cy - 25, 100, 50)
		draw_rect(win, win_c, true)
		draw_rect(win, win_border, false, 1.5)
		
		# 禁锢指示角标
		var mk = 6.0
		for corner in [win.position, Vector2(win.end.x, win.position.y), Vector2(win.position.x, win.end.y), win.end]:
			var dx = mk if corner.x == win.position.x else -mk
			var dy = mk if corner.y == win.position.y else -mk
			draw_line(corner, corner + Vector2(dx, 0), win_border, 2.0, true)
			draw_line(corner, corner + Vector2(0, dy), win_border, 2.0, true)

		var inner_left = win.position.x + r + 4
		var inner_right = win.end.x - r - 4
		var t_raw = fmod(_time * 0.8, 2.0)
		var t_tri = t_raw if t_raw < 1.0 else 2.0 - t_raw
		var px = inner_left + t_tri * (inner_right - inner_left)
		var py = win.end.y - r - 3
		
		# 碰壁发红阻挡效果
		if t_tri < 0.08 or t_tri > 0.92:
			var flash_a = 0.45
			if t_tri < 0.08:
				draw_line(Vector2(win.position.x, win.position.y + 3), Vector2(win.position.x, win.end.y - 3), Color(1.0, 0.4, 0.3, flash_a), 2.5, true)
			else:
				draw_line(Vector2(win.end.x, win.position.y + 3), Vector2(win.end.x, win.end.y - 3), Color(1.0, 0.4, 0.3, flash_a), 2.5, true)

		_draw_holo_pet(Vector2(px, py), hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 窗口模式 - 窗口排斥
# ═══════════════════════════════════════════
class WindowRepelledPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 6.0
		var win_c = Color(0.2, 0.35, 0.6, 0.35)
		var win_border = Color(0.7, 0.5, 0.2, 0.6)
		
		var win = Rect2(cx - 30, cy - 22, 60, 38)
		draw_rect(win, win_c, true)
		draw_rect(win, win_border, false, 1.5)
		
		# 排斥力场辐射
		var pulse = sin(_time * 4.0) * 0.3 + 0.5
		for i in range(2):
			var expand = float(i + 1) * 5.0 + sin(_time * 3.0 + float(i)) * 2.0
			var fa = pulse * 0.12 * (1.0 - float(i) * 0.4)
			var field_c = Color(0.9, 0.6, 0.2, fa)
			draw_rect(Rect2(win.position.x - expand, win.position.y - expand, win.size.x + expand * 2, win.size.y + expand * 2), field_c, false, 1.0, true)
		
		# 交叉禁止图标
		var cross_c = Color(0.8, 0.35, 0.2, 0.25)
		draw_line(Vector2(cx - 8, cy - 8 + 2), Vector2(cx + 8, cy + 8 + 2), cross_c, 1.5, true)
		draw_line(Vector2(cx + 8, cy - 8 + 2), Vector2(cx - 8, cy + 8 + 2), cross_c, 1.5, true)
		
		var ground_y = win.end.y + 10
		draw_line(Vector2(cx - 80, ground_y), Vector2(cx + 80, ground_y), Color(0.3, 0.4, 0.6, 0.3), 1.0, true)
		
		var cycle = fmod(_time * 0.4, 2.0)
		var px: float
		var py = ground_y - r
		var spark_x = 0.0
		var spark_dir = 1.0
		var show_spark = false
		
		if cycle < 1.0:
			var phase = cycle
			var approach_end = win.position.x - r - 8
			if phase < 0.5:
				px = cx - 75 + (phase / 0.5) * (approach_end - (cx - 75))
			elif phase < 0.65:
				var t = (phase - 0.5) / 0.15
				px = approach_end - sin(t * PI * 0.5) * 18.0
				py -= sin(t * PI) * 10.0
				spark_x = win.position.x - 3
				spark_dir = -1.0
				show_spark = true
			else:
				px = approach_end - 18.0 - ((phase - 0.65) / 0.35) * 20.0
		else:
			var phase = cycle - 1.0
			var approach_end = win.end.x + r + 8
			if phase < 0.5:
				px = cx + 75 - (phase / 0.5) * (cx + 75 - approach_end)
			elif phase < 0.65:
				var t = (phase - 0.5) / 0.15
				px = approach_end + sin(t * PI * 0.5) * 18.0
				py -= sin(t * PI) * 10.0
				spark_x = win.end.x + 3
				spark_dir = 1.0
				show_spark = true
			else:
				px = approach_end + 18.0 + ((phase - 0.65) / 0.35) * 20.0

		# 弹开粒子
		if show_spark:
			var phase_in_cycle = fmod(cycle, 1.0)
			if phase_in_cycle >= 0.48 and phase_in_cycle < 0.62:
				var spark_a = clampf(1.0 - abs(phase_in_cycle - 0.52) / 0.1, 0.0, 1.0) * 0.7
				for i in range(4):
					var angle = spark_dir * PI * 0.5 + (float(i) - 1.5) * 0.35
					var spark_len = 5.0 + float(i) * 2.0
					var sp = Vector2(spark_x, py)
					var ep = sp + Vector2(cos(angle), sin(angle)) * spark_len
					draw_line(sp, ep, Color(1.0, 0.7, 0.2, spark_a), 1.5, true)

		_draw_holo_pet(Vector2(px, py), hue, r)

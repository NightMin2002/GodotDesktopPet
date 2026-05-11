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
	# ── 指令模式预览 (L3: "behavior_mode") ──
	_register_radio("behavior_mode", 0, "bm_free",  BehaviorFreePreview.new(),  "活力满满，随意滚动跳跃", Vector2(180, 100))
	_register_radio("behavior_mode", 1, "bm_quiet", BehaviorQuietPreview.new(), "安安静静，待机休眠不乱跑", Vector2(180, 100))

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
		
		var win = Rect2(cx - 35, cy - 20, 70, 40)
		draw_rect(win, Color(0.2, 0.4, 0.7, 0.15), true)
		draw_rect(win, Color(0.4, 0.6, 1.0, 0.4), false, 1.5)
		
		# 指示向内的法线箭头
		var arrow_c = Color(0.4, 0.7, 1.0, 0.5)
		_draw_dir_arrow(Vector2(win.position.x - 8, cy), Vector2(1, 0), arrow_c)
		_draw_dir_arrow(Vector2(win.end.x + 8, cy), Vector2(-1, 0), arrow_c)
		_draw_dir_arrow(Vector2(cx, win.position.y - 8), Vector2(0, 1), arrow_c)
		_draw_dir_arrow(Vector2(cx, win.end.y + 8), Vector2(0, -1), arrow_c)

		var phase = fmod(_time * 0.5, 1.0)
		var px = cx
		var py = 0.0
		var show_collision = false
		var collision_pt = Vector2.ZERO
		var entry_anim = 0.0
		
		if phase < 0.25:
			# 从高空无障碍落入
			var t = phase / 0.25
			py = lerpf(win.position.y - 35.0, win.end.y - r, t)
			# 检测穿透瞬间，产生空间门涟漪，消除“生硬穿模”感
			if abs(py - win.position.y) < 14.0:
				entry_anim = 1.0 - abs(py - win.position.y) / 14.0
		elif phase < 0.45:
			# 在底部准备起跳
			py = win.end.y - r
		elif phase < 0.65:
			# 起跳撞击天花板并被阻挡 (留出1.5px余量坚决不穿透边框)
			var t = (phase - 0.45) / 0.2
			py = lerpf(win.end.y - r, win.position.y + r + 1.5, t)
			if t > 0.85:
				show_collision = true
				collision_pt = Vector2(cx, win.position.y)
		elif phase < 0.85:
			# 弹回落地
			var t = (phase - 0.65) / 0.2
			py = lerpf(win.position.y + r + 1.5, win.end.y - r, t)
			if t < 0.15:
				show_collision = true
				collision_pt = Vector2(cx, win.position.y)
		else:
			py = win.end.y - r

		# 进入时的单向通行力场波纹
		if entry_anim > 0:
			var portal_c = Color(0.3, 0.9, 1.0, entry_anim * 0.9)
			var w = 18.0 * entry_anim
			draw_line(Vector2(cx - w, win.position.y), Vector2(cx + w, win.position.y), portal_c, 3.0, true)
			draw_arc(Vector2(cx, win.position.y), 10.0 * entry_anim, 0, PI, 16, portal_c, 1.5, true)

		# 撞击天花板的拒止红焰
		if show_collision:
			draw_line(collision_pt - Vector2(18, 0), collision_pt + Vector2(18, 0), Color(1.0, 0.3, 0.3, 0.8), 2.5, true)
			draw_circle(collision_pt, 4.0, Color(1.0, 0.3, 0.3, 0.5))

		_draw_holo_pet(Vector2(px, py), hue, r)

	func _draw_dir_arrow(pos: Vector2, dir: Vector2, color: Color) -> void:
		var p1 = pos + dir * 4.0
		var perp = Vector2(-dir.y, dir.x)
		var p2 = pos - dir * 2.0 + perp * 4.0
		var p3 = pos - dir * 2.0 - perp * 4.0
		draw_colored_polygon(PackedVector2Array([p1, p2, p3]), color)

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
		
		var win = Rect2(cx - 35, cy - 20, 70, 40)
		draw_rect(win, Color(0.7, 0.4, 0.2, 0.15), true)
		draw_rect(win, Color(1.0, 0.6, 0.3, 0.5), false, 1.5)
		
		# 指示向外的法线箭头
		var arrow_c = Color(1.0, 0.6, 0.3, 0.6)
		_draw_dir_arrow(Vector2(win.position.x - 8, cy), Vector2(-1, 0), arrow_c)
		_draw_dir_arrow(Vector2(win.end.x + 8, cy), Vector2(1, 0), arrow_c)
		_draw_dir_arrow(Vector2(cx, win.position.y - 8), Vector2(0, -1), arrow_c)
		_draw_dir_arrow(Vector2(cx, win.end.y + 8), Vector2(0, 1), arrow_c)

		var phase = fmod(_time * 0.5, 1.0)
		var px = cx
		var py = 0.0
		var show_collision = false
		var collision_pt = Vector2.ZERO
		
		# 将撞击点改去左侧墙面，物理上绝对不可能与窗口内部路径重合，彻底杜绝穿模感
		var hit_x = win.position.x - r - 1.5 
		
		if phase < 0.25:
			# 从左侧水平冲刺向窗口
			var t = phase / 0.25
			px = lerpf(cx - 80.0, hit_x, t)
			py = cy
			if t > 0.85:
				show_collision = true
				collision_pt = Vector2(win.position.x, cy)
		elif phase < 0.8:
			# 严格在左侧弹开，做抛物线后空翻重重坠入深渊
			var t = (phase - 0.25) / 0.55
			px = lerpf(hit_x, cx - 70.0, t)
			py = lerpf(cy, cy + 60.0, t) - sin(t * PI) * 15.0
			if t < 0.15:
				show_collision = true
				collision_pt = Vector2(win.position.x, cy)
		else:
			px = -100
			py = -100

		if show_collision:
			# 排斥护盾 (朝左展开)
			draw_arc(collision_pt, 12.0, PI/2, 3*PI/2, 16, Color(1.0, 0.6, 0.2, 0.8), 2.5, true)
			draw_line(collision_pt - Vector2(0, 15), collision_pt + Vector2(0, 15), Color(1.0, 0.7, 0.4, 0.8), 2.5, true)
			draw_circle(collision_pt, 3.0, Color(1.0, 0.8, 0.5, 0.6))

		if px > -50.0:
			_draw_holo_pet(Vector2(px, py), hue, r)

	func _draw_dir_arrow(pos: Vector2, dir: Vector2, color: Color) -> void:
		var p1 = pos + dir * 4.0
		var perp = Vector2(-dir.y, dir.x)
		var p2 = pos - dir * 2.0 + perp * 4.0
		var p3 = pos - dir * 2.0 - perp * 4.0
		draw_colored_polygon(PackedVector2Array([p1, p2, p3]), color)

# ═══════════════════════════════════════════
# 动画预览 Control: 指令 - 自由行动
# ═══════════════════════════════════════════
class BehaviorFreePreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var r = 6.0
		var ground_y = size.y * 0.75
		var hue = EventBus.ui_hue
		
		# 极简发光地面线
		draw_line(Vector2(cx - 60, ground_y), Vector2(cx + 60, ground_y), Color(0.3, 0.5, 0.8, 0.2), 2.0, true)
		draw_line(Vector2(cx - 30, ground_y), Vector2(cx + 30, ground_y), Color(0.4, 0.7, 1.0, 0.5), 1.0, true)
		
		# 相位动画：周期跳跃与左右跑动
		var phase = fmod(_time * 0.6, 1.0)
		var px = cx
		var py = ground_y - r
		
		if phase < 0.3:
			# 向右大跳
			var t = phase / 0.3
			px = lerpf(cx - 40, cx + 10, t)
			py = ground_y - r - sin(t * PI) * 35.0
		elif phase < 0.5:
			# 向左小跳
			var t = (phase - 0.3) / 0.2
			px = lerpf(cx + 10, cx - 20, t)
			py = ground_y - r - sin(t * PI) * 15.0
		elif phase < 0.7:
			# 向右小跳
			var t = (phase - 0.5) / 0.2
			px = lerpf(cx - 20, cx, t)
			py = ground_y - r - sin(t * PI) * 10.0
		elif phase < 1.0:
			# 原地蓄力准备下一次大跳
			var t = (phase - 0.7) / 0.3
			px = cx - 40 * t
			py = ground_y - r
		
		# 残影速度线 (充满活力)
		var path_c = Color.from_hsv(hue, 0.5, 1.0, 0.2)
		for i in range(1, 5):
			# 用微小的延迟采样前面的时间点
			var past_phase = fmod((_time - i * 0.04) * 0.6, 1.0)
			var ppx = cx
			var ppy = ground_y - r
			if past_phase < 0.3:
				var t = past_phase / 0.3
				ppx = lerpf(cx - 40, cx + 10, t)
				ppy = ground_y - r - sin(t * PI) * 35.0
			elif past_phase < 0.5:
				var t = (past_phase - 0.3) / 0.2
				ppx = lerpf(cx + 10, cx - 20, t)
				ppy = ground_y - r - sin(t * PI) * 15.0
			elif past_phase < 0.7:
				var t = (past_phase - 0.5) / 0.2
				ppx = lerpf(cx - 20, cx, t)
				ppy = ground_y - r - sin(t * PI) * 10.0
			elif past_phase < 1.0:
				var t = (past_phase - 0.7) / 0.3
				ppx = cx - 40 * t
				ppy = ground_y - r
			
			draw_circle(Vector2(ppx, ppy), r - i * 0.8, Color(path_c.r, path_c.g, path_c.b, 0.4 - i * 0.08))

		_draw_holo_pet(Vector2(px, py), hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 指令 - 安静待命
# ═══════════════════════════════════════════
class BehaviorQuietPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var r = 6.0
		var ground_y = size.y * 0.75
		var hue = EventBus.ui_hue
		
		# 极简发光地面线
		draw_line(Vector2(cx - 60, ground_y), Vector2(cx + 60, ground_y), Color(0.3, 0.5, 0.8, 0.2), 2.0, true)
		draw_line(Vector2(cx - 30, ground_y), Vector2(cx + 30, ground_y), Color(0.4, 0.7, 1.0, 0.5), 1.0, true)
		
		# 屏幕角落指示器 (表示 retreat_target)
		var corner_x = cx + 55.0
		draw_line(Vector2(corner_x, ground_y), Vector2(corner_x, ground_y - 15.0), Color(0.2, 0.7, 0.9, 0.4), 2.0, true)
		draw_line(Vector2(corner_x, ground_y), Vector2(corner_x - 10.0, ground_y), Color(0.2, 0.7, 0.9, 0.4), 2.0, true)
		
		# 动作流程
		# 0.0~0.25: 滚向角落 (retreat)
		# 0.25~0.4: 停泊到位，加上阻尼稳住
		# 0.4~1.0: 休眠阶段 (hibernate)
		var loop_time = 4.0
		var phase = fmod(_time, loop_time) / loop_time
		var px = cx - 20.0
		var py = ground_y - r
		var drowsy_amt = 0.0
		var show_zzz = false
		
		if phase < 0.25:
			# 滚动寻位
			var t = phase / 0.25
			# 用 ease_out 让它减速停靠
			t = 1.0 - (1.0 - t) * (1.0 - t)
			px = lerpf(cx - 40.0, corner_x - r - 3.0, t)
		elif phase < 0.4:
			# 停靠完毕，开始闭眼
			px = corner_x - r - 3.0
			var t = (phase - 0.25) / 0.15
			drowsy_amt = lerpf(0.0, 0.8, t)
		else:
			# 彻底休眠，呼吸闭眼
			px = corner_x - r - 3.0
			drowsy_amt = 0.8 + sin((phase - 0.4) * TAU * 3.0) * 0.1
			show_zzz = true
		
		var pet_center = Vector2(px, py)
		
		# 本体底座光晕
		var glow_c = Color.from_hsv(hue, 0.6, 1.0, 0.15)
		draw_circle(pet_center, r + 2.5, glow_c, true, -1.0, true)
		# 立体核心网络
		var c1 = Color.from_hsv(hue, 0.5, 0.9, 0.5)
		draw_circle(pet_center, r, c1, true, -1.0, true)
		var c2 = Color.from_hsv(hue, 0.3, 1.0, 0.7)
		draw_circle(pet_center, r * 0.7, c2, true, -1.0, true)
		
		# 休眠挡板 (机械眼睑) 覆盖核心网
		if drowsy_amt > 0.05:
			# 画上半闭的深蓝灰色挡板多边形
			var close_px = r * drowsy_amt * 1.5
			var flat_y = clampf(-r + close_px, -r + 0.1, r - 0.1)
			var dx = sqrt(maxf(0.0, r * r - flat_y * flat_y))
			var pts = PackedVector2Array()
			var arc_steps = 16
			var angle_l = atan2(flat_y, -dx)
			var angle_r = atan2(flat_y, dx)
			var span = angle_r - angle_l
			if span < 0: span += TAU
			for i in range(arc_steps + 1):
				var t = float(i) / float(arc_steps)
				var a = angle_l + span * t
				pts.append(Vector2(cos(a), sin(a)) * r)
			if pts.size() >= 3:
				var shutter_offset = PackedVector2Array()
				for pt in pts:
					shutter_offset.append(pet_center + pt)
				var shutter_c = Color.from_hsv(hue, 0.5, 0.25, 1.0) # 暗色遮罩
				draw_colored_polygon(shutter_offset, shutter_c)
				draw_polyline(shutter_offset, shutter_c, 1.0, true)
				
		# 锐利边界收尾
		var rim_c = Color.from_hsv(hue, 0.2, 1.0, 0.8)
		draw_arc(pet_center, r, 0, TAU, 24, rim_c, 1.0, true)
		
		# 漂浮 Zzz 气泡
		if show_zzz:
			var z_phase = fmod(_time * 0.8, 1.0)
			for i in range(3):
				var offset_phase = fmod(z_phase + float(i) * 0.33, 1.0)
				# 抛物线漂浮 (上飘且微微右偏)
				var zx = pet_center.x + offset_phase * 15.0
				var zy = pet_center.y - r - 8.0 - offset_phase * 25.0
				var alpha = sin(offset_phase * PI) * 0.8
				var z_color = Color(0.5, 0.8, 1.0, alpha)
				var s = 0.5 + offset_phase * 0.8
				
				# 画个缩放的Z折线
				var z_pts = PackedVector2Array([
					Vector2(zx - 3*s, zy - 3*s),
					Vector2(zx + 3*s, zy - 3*s),
					Vector2(zx - 3*s, zy + 3*s),
					Vector2(zx + 3*s, zy + 3*s)
				])
				draw_polyline(z_pts, z_color, 1.2 * s, true)


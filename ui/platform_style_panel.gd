# platform_style_panel.gd — 踏板外观面板 (独立窗口模式)
# 以实时动画预览卡片的形式展示踏板风格选择
# 不跟随宠物，打开后可自由拖拽到任意位置
extends CanvasLayer

var panel: PanelContainer
var _guard_frames := 0

# ── 拖拽相关 ──
var _dragging_panel: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _title_bar: HBoxContainer

# ── 选择状态 ──
var _current_style: int = 0  # -1=随机, 0=能量束, 1=脉冲链, 2=极简
var _cards: Array = []       # StyleCard references

func _ready() -> void:
	layer = 102
	_current_style = SettingsManager.get_int("platform_style", 0)
	FreeRoamSystem.PlatformVisual.style = _current_style
	_build_ui()
	EventBus.show_platform_style_panel.connect(_toggle_panel)
	EventBus.ui_theme_changed.connect(_apply_ui_theme)

func _process(_delta: float) -> void:
	if _guard_frames > 0:
		_guard_frames -= 1

func _clamp_pos(pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 8.0, vp.x - panel.size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - panel.size.y - 8.0)
	return pos

# ── UI 构建 ──

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	# 面板背景
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.12, 0.95)
	bg.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.4)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 0
	bg.content_margin_right = 0
	bg.content_margin_top = 0
	bg.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", bg)
	panel.hide()

	var outer_margin = MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 14)
	outer_margin.add_theme_constant_override("margin_right", 14)
	outer_margin.add_theme_constant_override("margin_top", 0)
	outer_margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(outer_margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	outer_margin.add_child(vbox)

	# ── 标题栏 (可拖拽) ──
	_title_bar = HBoxContainer.new()
	_title_bar.custom_minimum_size = Vector2(0, 34)
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.gui_input.connect(_on_title_bar_input)

	var _title_label = Label.new()
	_title_label.text = "  踏板外观"
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 1.0, 0.9))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(_title_label)

	var close_btn = Button.new()
	close_btn.text = "x"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.6))
	close_btn.add_theme_color_override("font_hover_color", Color(1, 0.3, 0.3, 0.9))
	close_btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(_close_panel)
	_title_bar.add_child(close_btn)

	vbox.add_child(_title_bar)
	vbox.add_child(_make_sep())

	# ── 风格卡片 ──
	var styles = [
		{"id": 0, "name": "能量束", "desc": "三层发光 + 自适应刻度 + 端点光晕"},
		{"id": 1, "name": "脉冲链", "desc": "分段波浪依次点亮 + 流动光效"},
		{"id": 2, "name": "极简", "desc": "简洁细线 + 端点标记"},
		{"id": -1, "name": "随机", "desc": "每个踏板随机选择一种风格"},
	]

	_cards.clear()
	for s in styles:
		var card = _make_style_card(s.id, s.name, s.desc)
		vbox.add_child(card.container)
		_cards.append(card)

	_refresh_selection()
	add_child(panel)

func _make_style_card(style_id: int, title: String, desc: String) -> Dictionary:
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(290, 76)
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# 卡片背景
	var card_bg = StyleBoxFlat.new()
	card_bg.bg_color = Color(0.06, 0.09, 0.18, 0.6)
	card_bg.border_color = Color(0.15, 0.25, 0.4, 0.3)
	card_bg.set_border_width_all(1)
	card_bg.set_corner_radius_all(8)
	card_bg.content_margin_left = 10
	card_bg.content_margin_right = 10
	card_bg.content_margin_top = 8
	card_bg.content_margin_bottom = 8
	container.add_theme_stylebox_override("panel", card_bg)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(vbox)

	# 顶部: 预览区
	var preview = _StylePreview.new()
	preview.style_id = style_id
	preview.custom_minimum_size = Vector2(270, 28)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(preview)

	# 底部: 名称 + 描述
	var info_hbox = HBoxContainer.new()
	info_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_hbox.add_theme_constant_override("separation", 8)

	var indicator = Label.new()
	indicator.add_theme_font_size_override("font_size", 16)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_hbox.add_child(indicator)

	var name_label = Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_hbox.add_child(name_label)

	var desc_label = Label.new()
	desc_label.text = desc
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.65, 0.7))
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_hbox.add_child(desc_label)

	vbox.add_child(info_hbox)

	# 点击事件
	var sid = style_id
	container.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_style(sid)
	)

	return {
		"container": container,
		"bg": card_bg,
		"indicator": indicator,
		"style_id": style_id,
		"preview": preview,
	}

func _refresh_selection() -> void:
	for card in _cards:
		var active = (card.style_id == _current_style)
		card.indicator.text = "●" if active else "○"
		if active:
			card.indicator.add_theme_color_override("font_color",
				Color.from_hsv(EventBus.ui_hue, 0.5, 1.0, 1.0))
			card.bg.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 0.6)
			card.bg.bg_color = Color.from_hsv(EventBus.ui_hue, 0.15, 0.15, 0.7)
		else:
			card.indicator.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 0.5))
			card.bg.border_color = Color(0.15, 0.25, 0.4, 0.3)
			card.bg.bg_color = Color(0.06, 0.09, 0.18, 0.6)

func _select_style(style_id: int) -> void:
	_current_style = style_id
	FreeRoamSystem.PlatformVisual.style = style_id
	SettingsManager.set_int("platform_style", style_id)
	_refresh_selection()

# ── 面板显隐 ──

func _toggle_panel() -> void:
	if panel.visible:
		_close_panel()
	else:
		_open_panel()

func _open_panel() -> void:
	EventBus.context_menu_toggled.emit(true)
	get_window().grab_focus()
	var vp = get_viewport().get_visible_rect().size
	panel.position = Vector2(vp.x / 2.0 - 160, vp.y / 2.0 - 200)
	panel.position = _clamp_pos(panel.position)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.6, 0.6)
	panel.show()
	# 启动预览动画
	for card in _cards:
		card.preview.set_process(true)
	await get_tree().process_frame
	panel.pivot_offset = panel.size / 2.0
	_guard_frames = 5
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

func _close_panel() -> void:
	_dragging_panel = false
	# 停止预览动画 (节省性能)
	for card in _cards:
		card.preview.set_process(false)
	panel.pivot_offset = panel.size / 2.0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.15)
	tween.tween_property(panel, "scale", Vector2(0.5, 0.5), 0.15)
	tween.finished.connect(func():
		panel.hide()
		EventBus.context_menu_toggled.emit(false)
	)

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible or _guard_frames > 0:
		return
	if event is InputEventMouseButton and event.pressed:
		if _dragging_panel:
			return
		var local_mouse = panel.get_local_mouse_position()
		var rect = Rect2(Vector2.ZERO, panel.size)
		if not rect.has_point(local_mouse):
			_close_panel()
			get_viewport().set_input_as_handled()

# ── 标题栏拖拽 ──

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging_panel = true
			_drag_offset = get_viewport().get_mouse_position() - panel.position
		else:
			_dragging_panel = false
	elif event is InputEventMouseMotion and _dragging_panel:
		panel.position = get_viewport().get_mouse_position() - _drag_offset
		panel.position = _clamp_pos(panel.position)

# ── 主题色同步 ──

func _apply_ui_theme(_hue: float) -> void:
	if not is_instance_valid(panel):
		return
	# 面板边框
	var bg = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if bg:
		bg.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.4)
	# 标题文字
	if _title_bar and _title_bar.get_child_count() > 0:
		var title = _title_bar.get_child(0) as Label
		if title:
			title.add_theme_color_override("font_color",
				Color.from_hsv(EventBus.ui_hue, 0.4, 1.0, 0.9))
	# 预览颜色
	for card in _cards:
		if is_instance_valid(card.preview):
			card.preview.platform_color = Color.from_hsv(EventBus.ui_hue, 0.55, 1.0, 0.6)
	_refresh_selection()

# ── 工具 ──

func _make_sep() -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

# ══════════════════════════════════════════════
# 内嵌类: 踏板风格实时预览渲染器
# ══════════════════════════════════════════════

class _StylePreview extends Control:
	var style_id: int = 0
	var platform_color: Color = Color(0.2, 0.6, 1.0, 0.6)
	var _time: float = 0.0

	func _ready() -> void:
		platform_color = Color.from_hsv(EventBus.ui_hue, 0.55, 1.0, 0.6)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var hw = size.x / 2.0 - 16.0
		var cy = size.y / 2.0
		if hw < 1.0:
			return

		var pulse = 0.85 + sin(_time * TAU / 2.5) * 0.15
		var c = Color(platform_color.r, platform_color.g, platform_color.b,
			platform_color.a * pulse)

		# 暗色背景条
		var bg_rect = Rect2(Vector2(16.0, cy - 12.0), Vector2(size.x - 32.0, 24.0))
		draw_rect(bg_rect, Color(0.03, 0.05, 0.1, 0.5), true)

		match style_id:
			0: _draw_energy(hw, cy, c)
			1: _draw_pulse_chain(hw, cy, c)
			2: _draw_minimal(hw, cy, c)
			-1: _draw_random(hw, cy, c)

	# ── 能量束 ──
	func _draw_energy(hw: float, cy: float, c: Color) -> void:
		var cx = size.x / 2.0
		draw_line(Vector2(cx - hw, cy), Vector2(cx + hw, cy),
			Color(c.r, c.g, c.b, c.a * 0.15), 8.0, true)
		draw_line(Vector2(cx - hw, cy), Vector2(cx + hw, cy),
			Color(c.r, c.g, c.b, c.a * 0.3), 4.0, true)
		draw_line(Vector2(cx - hw, cy), Vector2(cx + hw, cy), c, 1.5, true)
		# 刻度线
		var tick_c = Color(c.r, c.g, c.b, c.a * 0.5)
		var tick_count = 6
		for i in range(tick_count):
			var t = float(i + 1) / float(tick_count + 1)
			var tx = lerpf(cx - hw, cx + hw, t)
			draw_line(Vector2(tx, cy - 2.0), Vector2(tx, cy + 2.0), tick_c, 1.0, true)
		# 端点光点
		var dot_c = Color(c.r, c.g, c.b, c.a * 0.9)
		draw_circle(Vector2(cx - hw, cy), 2.5, dot_c, true, -1.0, true)
		draw_circle(Vector2(cx + hw, cy), 2.5, dot_c, true, -1.0, true)
		var halo_c = Color(c.r, c.g, c.b, c.a * 0.25)
		draw_circle(Vector2(cx - hw, cy), 4.5, halo_c, true, -1.0, true)
		draw_circle(Vector2(cx + hw, cy), 4.5, halo_c, true, -1.0, true)
		# 汇聚粒子
		var pc = Color(minf(c.r + 0.2, 1.0), minf(c.g + 0.2, 1.0), 1.0)
		for i in range(3):
			var off = float(i) / 3.0
			var lt = fmod(_time * 0.7 + off, 1.0)
			var lx = lerpf(cx - hw * 0.9, cx, lt)
			var la = sin(lt * PI) * c.a * 0.8
			draw_circle(Vector2(lx, cy), 1.5, Color(pc.r, pc.g, pc.b, la), true, -1.0, true)
			var rt = fmod(_time * 0.7 + off + 0.15, 1.0)
			var rx = lerpf(cx + hw * 0.9, cx, rt)
			var ra = sin(rt * PI) * c.a * 0.8
			draw_circle(Vector2(rx, cy), 1.5, Color(pc.r, pc.g, pc.b, ra), true, -1.0, true)

	# ── 脉冲链 ──
	func _draw_pulse_chain(hw: float, cy: float, c: Color) -> void:
		var cx = size.x / 2.0
		draw_line(Vector2(cx - hw, cy), Vector2(cx + hw, cy),
			Color(c.r, c.g, c.b, c.a * 0.15), 3.0, true)
		var seg_w = 14.0
		var gap = 2.5
		var total = seg_w + gap
		var seg_count = int(hw * 2.0 / total) + 1
		for i in range(seg_count):
			var sx = cx - hw + float(i) * total
			if sx > cx + hw: break
			var ex = minf(sx + seg_w, cx + hw)
			var phase_offset = float(i) * 0.3
			var brightness = 0.3 + 0.7 * maxf(0, sin(_time * 2.0 - phase_offset))
			var seg_c = Color(c.r, c.g, c.b, c.a * brightness)
			draw_line(Vector2(sx, cy), Vector2(ex, cy), seg_c, 2.5, true)
			if brightness > 0.7:
				var glow_a = (brightness - 0.7) / 0.3 * c.a * 0.3
				draw_line(Vector2(sx, cy), Vector2(ex, cy),
					Color(c.r, c.g, c.b, glow_a), 6.0, true)
		var dot_c = Color(c.r, c.g, c.b, c.a * 0.9)
		draw_circle(Vector2(cx - hw, cy), 2.0, dot_c, true, -1.0, true)
		draw_circle(Vector2(cx + hw, cy), 2.0, dot_c, true, -1.0, true)
		# 汇聚粒子
		var pc = Color(minf(c.r + 0.2, 1.0), minf(c.g + 0.2, 1.0), 1.0)
		for j in range(2):
			var off = float(j) / 2.0
			var lt = fmod(_time * 0.7 + off, 1.0)
			var lx = lerpf(cx - hw * 0.9, cx, lt)
			var la = sin(lt * PI) * c.a * 0.7
			draw_circle(Vector2(lx, cy), 1.3, Color(pc.r, pc.g, pc.b, la), true, -1.0, true)
			var rt = fmod(_time * 0.7 + off + 0.15, 1.0)
			var rx = lerpf(cx + hw * 0.9, cx, rt)
			var ra = sin(rt * PI) * c.a * 0.7
			draw_circle(Vector2(rx, cy), 1.3, Color(pc.r, pc.g, pc.b, ra), true, -1.0, true)

	# ── 极简 ──
	func _draw_minimal(hw: float, cy: float, c: Color) -> void:
		var cx = size.x / 2.0
		draw_line(Vector2(cx - hw, cy), Vector2(cx + hw, cy),
			Color(c.r, c.g, c.b, c.a * 0.1), 6.0, true)
		draw_line(Vector2(cx - hw, cy), Vector2(cx + hw, cy),
			Color(c.r, c.g, c.b, c.a * 0.6), 1.0, true)
		var dot_c = Color(c.r, c.g, c.b, c.a * 0.8)
		draw_circle(Vector2(cx - hw, cy), 1.5, dot_c, true, -1.0, true)
		draw_circle(Vector2(cx + hw, cy), 1.5, dot_c, true, -1.0, true)

	# ── 随机 (三段混合展示) ──
	func _draw_random(hw: float, cy: float, c: Color) -> void:
		var cx = size.x / 2.0
		var seg = hw * 2.0 / 3.0
		# 左1/3: 能量束风格
		var s1 = cx - hw
		var e1 = s1 + seg - 4.0
		draw_line(Vector2(s1, cy), Vector2(e1, cy), Color(c.r, c.g, c.b, c.a * 0.3), 4.0, true)
		draw_line(Vector2(s1, cy), Vector2(e1, cy), c, 1.5, true)
		draw_circle(Vector2(s1, cy), 2.0, Color(c.r, c.g, c.b, c.a * 0.9), true, -1.0, true)
		# 中1/3: 脉冲链风格
		var s2 = s1 + seg + 4.0
		var e2 = s2 + seg - 8.0
		var sw = 10.0
		var i_seg = 0
		var px = s2
		while px < e2:
			var ex = minf(px + sw, e2)
			var br = 0.3 + 0.7 * maxf(0, sin(_time * 2.0 - float(i_seg) * 0.4))
			draw_line(Vector2(px, cy), Vector2(ex, cy),
				Color(c.r, c.g, c.b, c.a * br), 2.5, true)
			px = ex + 2.0
			i_seg += 1
		# 右1/3: 极简风格
		var s3 = s2 + seg + 4.0
		var e3 = cx + hw
		draw_line(Vector2(s3, cy), Vector2(e3, cy), Color(c.r, c.g, c.b, c.a * 0.5), 1.0, true)
		draw_circle(Vector2(s3, cy), 1.5, Color(c.r, c.g, c.b, c.a * 0.7), true, -1.0, true)
		draw_circle(Vector2(e3, cy), 1.5, Color(c.r, c.g, c.b, c.a * 0.7), true, -1.0, true)
		# 分隔虚线
		var dash_c = Color(c.r, c.g, c.b, c.a * 0.2)
		draw_line(Vector2(s1 + seg, cy - 6), Vector2(s1 + seg, cy + 6), dash_c, 1.0, true)
		draw_line(Vector2(s2 + seg, cy - 6), Vector2(s2 + seg, cy + 6), dash_c, 1.0, true)

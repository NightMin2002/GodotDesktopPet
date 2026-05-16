# profile_tab_theme.gd — 外观主题 Tab (装置终端)
extends HBoxContainer

const _PetColorPalette = preload("res://entities/pet/pet_color_palette.gd")

# ── 编辑状态 ──
var _target_index: int = 0   # 0=原体, 1~5=分身, -1=UI主题
var _current_hue: float = 0.62
var _current_sat: int = 50
var _current_val: int = 50

# ── 定制化装甲分段滑块 (Cyber Slider) ──
class CyberSlider extends Control:
	signal value_changed(val: int)
	var value: int = 50
	var hue: float = 0.5
	var _hovered: bool = false
	var _dragging: bool = false
	
	func _init() -> void:
		custom_minimum_size.y = 22
		mouse_filter = Control.MOUSE_FILTER_STOP
		
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			if _dragging:
				_update_value(event.position)
			else:
				if event.position.x >= 0 and event.position.x <= size.x and event.position.y >= 0 and event.position.y <= size.y:
					if not _hovered:
						_hovered = true
						queue_redraw()
				else:
					if _hovered:
						_hovered = false
						queue_redraw()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_update_value(event.position)
			else:
				_dragging = false
				
	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			_hovered = true; queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			_hovered = false; queue_redraw()
			
	func _update_value(pos: Vector2) -> void:
		var raw = clampf(pos.x / size.x, 0.0, 1.0)
		var new_val = int(round(raw * 100.0))
		if new_val != value:
			value = new_val
			queue_redraw()
			value_changed.emit(value)
			
	func set_value_no_signal(v: int) -> void:
		value = clampi(v, 0, 100)
		queue_redraw()
			
	func _draw() -> void:
		var w = size.x
		var h = size.y
		
		# 极简底槽
		draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.04, 0.06, 0.6))
		var b_color = Color.from_hsv(hue, 0.4, 0.6) if _hovered else Color.from_hsv(hue, 0.3, 0.4, 0.5)
		draw_rect(Rect2(0, 0, w, h), b_color, false, 1.0)
		
		# 20 个离散装甲块
		var seg_count = 25
		var gap = 2.0
		var margin_x = 4.0
		var margin_y = 4.0
		
		var usable_w = w - margin_x * 2 - gap * (seg_count - 1)
		var seg_w = usable_w / seg_count
		var seg_h = h - margin_y * 2
		
		var fill_ratio = float(value) / 100.0
		var active_segs = int(round(fill_ratio * seg_count))
		
		for i in range(seg_count):
			var rx = margin_x + i * (seg_w + gap)
			var ry = margin_y
			var r = Rect2(rx, ry, seg_w, seg_h)
			
			if i < active_segs:
				var alpha = 1.0 - (float(seg_count - i) / seg_count) * 0.3 # 越靠右越高亮
				var c = Color.from_hsv(hue, 0.7, 0.9, alpha)
				draw_rect(r, c)
			else:
				var dim_c = Color(0.15, 0.18, 0.22, 0.5)
				draw_rect(r, dim_c)
				
		# 游标切线
		if active_segs > 0:
			var cursor_x = margin_x + active_segs * (seg_w + gap) - gap
			draw_line(Vector2(cursor_x, 0), Vector2(cursor_x, h), Color.WHITE, 2.0)

# ── UI 引用 ──
var _target_btns: Array[Button] = []
var _wheel: Control
var _sat_slider: CyberSlider
var _val_slider: CyberSlider
var _sat_label: Label
var _val_label: Label
var _conflict_label: Label
var _dragging_wheel: bool = false

# ── 预设色调 ──
const PRESETS: Array[float] = [0.62, 0.78, 0.33, 0.0, 0.12, 0.92, 0.537, 0.08]
const PRESET_NAMES: Array[String] = ["蓝", "紫", "绿", "红", "金", "粉", "青", "橙"]

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	var scroll = ProfileStyles.make_tab_scroll()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)

	var vbox = ProfileStyles.make_tab_vbox(16)
	
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.add_child(vbox)
	scroll.add_child(margin)

	# Card 1: 目标选择器
	var card_target = _build_cyber_card(vbox, "TGT_LINK", "目标链路分配")
	_build_target_selector(card_target)

	# Card 2: 色彩矩阵
	var card_color = _build_cyber_card(vbox, "CLR_MATRIX", "色彩空间矩阵")
	
	var color_hbox = HBoxContainer.new()
	color_hbox.add_theme_constant_override("separation", 24)
	color_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card_color.add_child(color_hbox)
	
	_build_color_wheel(color_hbox)
	
	var slider_vbox = VBoxContainer.new()
	slider_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_vbox.add_theme_constant_override("separation", 16)
	slider_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	color_hbox.add_child(slider_vbox)
	
	_conflict_label = Label.new()
	_conflict_label.add_theme_font_size_override("font_size", 12)
	_conflict_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35, 0.9))
	_conflict_label.text = ""
	_conflict_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_conflict_label.custom_minimum_size.y = 20
	slider_vbox.add_child(_conflict_label)
	
	_build_sliders(slider_vbox)

	# Card 3: 预设与重置
	var card_presets = _build_cyber_card(vbox, "PRESET_MEM", "快速涂装预设")
	_build_presets(card_presets)
	
	_build_reset_zone(vbox)

	# 科幻滚动指示器
	var indicator = preload("res://ui/profile/cyber_scroll_indicator.gd").new()
	indicator.bind_scroll(scroll)
	add_child(indicator)

func refresh() -> void:
	_target_index = 0
	_load_target_color()
	_rebuild_target_selector()

# ═══════════════════════════════════════════════
#  科幻卡片基建
# ═══════════════════════════════════════════════

func _build_cyber_card(parent: Control, sub_title: String, main_title: String) -> VBoxContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = ProfileStyles.card_style()
	cs.border_width_left = 4
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.7)
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	var group = ProfileStyles.make_tab_vbox(12)
	card.add_child(group)

	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim(sub_title + " //", 11))
	title_row.add_child(ProfileStyles.value_label(main_title, 15))
	group.add_child(title_row)

	var hsep = HSeparator.new()
	hsep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	hsep.add_theme_constant_override("separation", 1)
	group.add_child(hsep)

	return group

# ═══════════════════════════════════════════════
#  目标选择器
# ═══════════════════════════════════════════════

func _build_target_selector(parent: VBoxContainer) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.set_meta("is_target_selector", true)
	parent.add_child(hbox)
	
	if is_inside_tree():
		_populate_target_btns(hbox)
	else:
		ready.connect(func(): if is_instance_valid(hbox): _populate_target_btns(hbox), CONNECT_ONE_SHOT)

func _populate_target_btns(hbox: HBoxContainer) -> void:
	for child in hbox.get_children():
		child.queue_free()
	_target_btns.clear()
	
	# 加入微弱的间隔
	var btn0 = _make_target_btn("SYS_0 (原体)", 0)
	hbox.add_child(btn0)
	_target_btns.append(btn0)

	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instances" in main_node:
		for i in range(1, main_node.pet_instances.size()):
			var btn = _make_target_btn("CLONE_" + str(i) + " (分身)", i)
			hbox.add_child(btn)
			_target_btns.append(btn)
			
	var vsep = VSeparator.new()
	vsep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	hbox.add_child(vsep)

	var ui_btn = _make_target_btn("TERM_UI (终端界面)", -1)
	hbox.add_child(ui_btn)
	_target_btns.append(ui_btn)
	_refresh_target_highlight()

func _rebuild_target_selector() -> void:
	var scroll = get_child(0)
	if not scroll: return
	var margin = scroll.get_node_or_null("MarginContainer")
	if not margin: return
	var vbox = margin.get_child(0)
	for card in vbox.get_children():
		if card is PanelContainer:
			var group = card.get_child(0)
			for child in group.get_children():
				if child.has_meta("is_target_selector"):
					_populate_target_btns(child)
					return

func _make_target_btn(text: String, index: int) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", ProfileStyles.dim())
	btn.add_theme_color_override("font_hover_color", ProfileStyles.bright())
	btn.custom_minimum_size = Vector2(0, 32)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS

	var s = ProfileStyles.small_btn_normal()
	s.content_margin_left = 12; s.content_margin_right = 12
	btn.add_theme_stylebox_override("normal", s)
	
	var h = ProfileStyles.small_btn_hover()
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)

	var idx = index
	btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			_on_target_selected(idx)
	)
	return btn

func _refresh_target_highlight() -> void:
	for btn in _target_btns:
		var s = ProfileStyles.small_btn_normal()
		s.content_margin_left = 12; s.content_margin_right = 12
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_color_override("font_color", ProfileStyles.dim())

	for i in range(_target_btns.size()):
		var btn = _target_btns[i]
		var btn_index: int
		if i == _target_btns.size() - 1:
			btn_index = -1
		else:
			btn_index = i
			
		if btn_index == _target_index:
			var s = ProfileStyles.small_btn_hover()
			s.border_color = Color.from_hsv(_current_hue, 0.8, 1.0, 0.9)
			s.set_border_width_all(2)
			s.content_margin_left = 12; s.content_margin_right = 12
			btn.add_theme_stylebox_override("normal", s)
			btn.add_theme_color_override("font_color", ProfileStyles.bright())

# ═══════════════════════════════════════════════
#  全息雷达色轮 (Mechanical Hue Dial)
# ═══════════════════════════════════════════════

func _build_color_wheel(parent: HBoxContainer) -> void:
	var center_box = CenterContainer.new()
	center_box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(center_box)

	_wheel = Control.new()
	_wheel.custom_minimum_size = Vector2(170, 170)
	_wheel.mouse_filter = Control.MOUSE_FILTER_STOP
	_wheel.draw.connect(_draw_wheel)
	_wheel.gui_input.connect(_wheel_input)
	center_box.add_child(_wheel)

func _draw_wheel() -> void:
	var wsize = _wheel.size
	var center = wsize / 2.0
	var outer_r = min(wsize.x, wsize.y) / 2.0 - 4
	var track_w := 20.0
	var inner_r = outer_r - track_w
	var mid_r = (outer_r + inner_r) / 2.0

	# 1. 绘制带有间隙的离散机械轨道 (36 节段)
	var seg := 36
	var gap := 0.04 # 弧度间隙
	for i in range(seg):
		var a = float(i) / seg * TAU
		var hue = float(i) / seg
		var c = Color.from_hsv(hue, 0.7, 0.85)
		if fmod(_current_hue - hue + 1.0, 1.0) < (1.0/seg * 0.5) or fmod(hue - _current_hue + 1.0, 1.0) < (1.0/seg * 0.5):
			c = Color.from_hsv(hue, 1.0, 1.0) # 高亮离得最近的刻度
			
		_wheel.draw_arc(center, mid_r, a + gap, a + TAU/seg - gap, 8, c, track_w - 4, true)

	var preview_r = inner_r * 0.65
	
	# 2. 内圈雷达准星
	_wheel.draw_circle(center, preview_r + 8, Color(0.04, 0.05, 0.08, 0.95))
	_wheel.draw_arc(center, preview_r + 8, 0, TAU, 64, Color.from_hsv(_current_hue, 0.4, 0.6, 0.5), 1.0, true)
	
	var rot_t = Time.get_ticks_msec() * 0.001
	_wheel.draw_arc(center, preview_r + 4, rot_t, rot_t + PI*0.7, 16, Color.from_hsv(_current_hue, 0.7, 0.9, 0.8), 2.0, true)
	_wheel.draw_arc(center, preview_r + 4, rot_t + PI, rot_t + PI + PI*0.7, 16, Color.from_hsv(_current_hue, 0.7, 0.9, 0.8), 2.0, true)

	# 3. 中心数值读数与发光核心
	var sel_angle = _current_hue * TAU
	var hue_deg = int(round(_current_hue * 360.0)) % 360
	
	# 发光渐变中心
	var core_c = Color.from_hsv(_current_hue, 0.85, 0.9, 0.25)
	_wheel.draw_circle(center, preview_r - 2, core_c)
	
	# 添加数值文本 (HUE: XXX°)
	var f = ThemeDB.fallback_font
	var t_size = f.get_string_size("360°", HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	_wheel.draw_string(f, center + Vector2(-t_size.x/2, t_size.y/2 - 2), "%03d" % hue_deg + "°", HORIZONTAL_ALIGNMENT_CENTER, -1, 15, Color(1,1,1,0.9))

	var sub_size = f.get_string_size("HUE", HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
	_wheel.draw_string(f, center + Vector2(-sub_size.x/2, -t_size.y/2 - 4), "HUE", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.6, 0.7, 0.8, 0.7))

	# 4. 外圈机械游标 (Bracket 指针)
	var dir = Vector2(cos(sel_angle), sin(sel_angle))
	var p_out = center + dir * (outer_r + 5)
	var p_in = center + dir * (inner_r - 5)
	var norm = Vector2(-dir.y, dir.x) * 6
	
	var cursor_poly = PackedVector2Array([
		p_out - norm, p_out + norm,
		center + dir * (outer_r + 1), center + dir * (outer_r + 1), 
		center + dir * (outer_r + 1) + norm*0.5,
		center + dir * (inner_r - 1) + norm*0.5,
		center + dir * (inner_r - 1) - norm*0.5,
		center + dir * (outer_r + 1) - norm*0.5
	])
	# 绘制机械游标
	_wheel.draw_polyline(PackedVector2Array([p_out - norm, p_out + norm, p_in + norm*0.6, p_in - norm*0.6, p_out - norm]), Color.WHITE, 1.5, true)
	# 游标中线上色
	_wheel.draw_line(center + dir * (inner_r), center + dir * outer_r, Color.from_hsv(_current_hue, 0.8, 1.0), 2.0)


func _wheel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_pick_hue(event.position)
				_dragging_wheel = true
			else:
				_dragging_wheel = false
	elif event is InputEventMouseMotion and _dragging_wheel:
		_try_pick_hue(event.position)

func _try_pick_hue(pos: Vector2) -> void:
	var wsize = _wheel.size
	var center = wsize / 2.0
	var outer_r = min(wsize.x, wsize.y) / 2.0
	var inner_r = outer_r - 30.0
	
	# 放宽抓取范围
	var dist = pos.distance_to(center)
	if dist >= inner_r - 15 and dist <= outer_r + 15:
		var angle = atan2(pos.y - center.y, pos.x - center.x)
		_current_hue = fmod(angle / TAU + 1.0, 1.0)
		if is_instance_valid(_sat_slider):
			_sat_slider.hue = _current_hue
			_val_slider.hue = _current_hue
			_sat_slider.queue_redraw()
			_val_slider.queue_redraw()
		_wheel.queue_redraw()
		_apply_color()


func _build_sliders(parent: VBoxContainer) -> void:
	var sat_row = HBoxContainer.new()
	sat_row.add_theme_constant_override("separation", 12)
	sat_row.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(sat_row)

	var sat_tag = ProfileStyles.label_dim("SAT [饱和]")
	sat_tag.custom_minimum_size.x = 64
	sat_row.add_child(sat_tag)

	_sat_slider = CyberSlider.new()
	_sat_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sat_slider.value_changed.connect(func(v): _current_sat = v; _sat_label.text = "%03d" % v; _wheel.queue_redraw(); _apply_color())
	sat_row.add_child(_sat_slider)

	_sat_label = ProfileStyles.value_label("050")
	_sat_label.custom_minimum_size.x = 32
	sat_row.add_child(_sat_label)

	var val_row = HBoxContainer.new()
	val_row.add_theme_constant_override("separation", 12)
	val_row.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(val_row)

	var val_tag = ProfileStyles.label_dim("VAL [明度]")
	val_tag.custom_minimum_size.x = 64
	val_row.add_child(val_tag)

	_val_slider = CyberSlider.new()
	_val_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_val_slider.value_changed.connect(func(v): _current_val = v; _val_label.text = "%03d" % v; _wheel.queue_redraw(); _apply_color())
	val_row.add_child(_val_slider)

	_val_label = ProfileStyles.value_label("050")
	_val_label.custom_minimum_size.x = 32
	val_row.add_child(_val_label)


# ═══════════════════════════════════════════════
#  预设色与控制
# ═══════════════════════════════════════════════

func _build_presets(parent: VBoxContainer) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(hbox)

	for i in range(PRESETS.size()):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(32, 28)
		btn.tooltip_text = PRESET_NAMES[i]
		btn.flat = false
		btn.text = ""
		btn.mouse_filter = Control.MOUSE_FILTER_PASS

		var s = StyleBoxFlat.new()
		s.bg_color = Color.from_hsv(PRESETS[i], 0.8, 0.9)
		s.set_corner_radius_all(0)
		s.set_border_width_all(2)
		s.border_color = Color(0.2, 0.25, 0.3, 0.8)
		btn.add_theme_stylebox_override("normal", s)

		var h = s.duplicate()
		h.border_color = Color.WHITE
		btn.add_theme_stylebox_override("hover", h)
		btn.add_theme_stylebox_override("pressed", h)

		var preset_hue = PRESETS[i]
		btn.pressed.connect(func(): _on_preset(preset_hue))
		hbox.add_child(btn)

func _build_reset_zone(parent: VBoxContainer) -> void:
	var pnl = PanelContainer.new()
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.05, 0.08, 0.5)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.2)
	s.set_corner_radius_all(2)
	s.content_margin_left = 16; s.content_margin_right = 16
	s.content_margin_top = 12; s.content_margin_bottom = 12
	pnl.add_theme_stylebox_override("panel", s)
	parent.add_child(pnl)
	
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	pnl.add_child(hb)
	
	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	
	var title = Label.new()
	title.text = "FACTORY_RESET // 涂装重置"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", ProfileStyles.dim())
	vb.add_child(title)
	
	var desc = Label.new()
	desc.text = "将当前选定目标的涂装恢复出厂设定。分身系统将自动生成不冲突的随机色阶。"
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc)
	
	var btn = Button.new()
	btn.text = "执行重置"
	btn.custom_minimum_size = Vector2(100, 0)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var b_norm = ProfileStyles.small_btn_normal()
	b_norm.content_margin_left = 16; b_norm.content_margin_right = 16
	b_norm.content_margin_top = 8; b_norm.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", b_norm)
	
	var b_hov = ProfileStyles.small_btn_hover()
	b_hov.content_margin_left = 16; b_hov.content_margin_right = 16
	b_hov.content_margin_top = 8; b_hov.content_margin_bottom = 8
	btn.add_theme_stylebox_override("hover", b_hov)
	btn.add_theme_stylebox_override("pressed", b_hov)
	
	hb.add_child(btn)
	
	btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			_on_reset()
	)

# ═══════════════════════════════════════════════
#  事件处理
# ═══════════════════════════════════════════════

func _on_target_selected(index: int) -> void:
	_target_index = index
	_load_target_color()
	_refresh_target_highlight()
	if is_instance_valid(_wheel): _wheel.queue_redraw()

func _load_target_color() -> void:
	if _target_index == -1:
		_current_hue = EventBus.ui_hue
		_current_sat = 50
		_current_val = 50
	else:
		var main_node = get_tree().root.get_node_or_null("Main")
		if main_node and "pet_instances" in main_node:
			var pets: Array = main_node.pet_instances
			if _target_index < pets.size() and is_instance_valid(pets[_target_index]):
				var p = pets[_target_index]
				_current_hue = p.palette.hue
				_current_sat = p.palette.get_sat_percent()
				_current_val = p.palette.get_val_percent()

	if is_instance_valid(_sat_slider):
		_sat_slider.hue = _current_hue
		_sat_slider.set_value_no_signal(_current_sat)
		_val_slider.hue = _current_hue
		_val_slider.set_value_no_signal(_current_val)
		_sat_label.text = "%03d" % _current_sat
		_val_label.text = "%03d" % _current_val
	if is_instance_valid(_wheel):
		_wheel.queue_redraw()

func _on_preset(hue: float) -> void:
	_current_hue = hue
	_current_sat = 50; _current_val = 50
	if is_instance_valid(_sat_slider):
		_sat_slider.hue = _current_hue
		_sat_slider.set_value_no_signal(50)
		_val_slider.hue = _current_hue
		_val_slider.set_value_no_signal(50)
		_sat_label.text = "050"; _val_label.text = "050"
	if is_instance_valid(_wheel): _wheel.queue_redraw()
	_apply_color()

func _on_reset() -> void:
	if _target_index == -1:
		_on_preset(0.537)
	elif _target_index == 0:
		_on_preset(_PetColorPalette.DEFAULT_HUE)
	else:
		_on_preset(_generate_distinct_hue())

func _generate_distinct_hue() -> float:
	var existing: Array[float] = []
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instances" in main_node:
		for i in range(main_node.pet_instances.size()):
			var p = main_node.pet_instances[i]
			if is_instance_valid(p) and p.palette and i != _target_index:
				existing.append(p.palette.hue)
	for _attempt in range(20):
		var candidate = randf()
		var ok = true
		for h in existing:
			var d = absf(candidate - h)
			if minf(d, 1.0 - d) < 0.08:
				ok = false
				break
		if ok:
			return candidate
	return randf()

func _apply_color() -> void:
	_refresh_target_highlight()
	if _target_index == -1:
		EventBus.ui_hue = _current_hue
		EventBus.ui_theme_changed.emit(_current_hue)
		SettingsManager.set_ui_hue(int(_current_hue * 360.0))
		_conflict_label.text = ""
	else:
		var sat_scale = clampf(float(_current_sat) / 100.0 + 0.5, 0.5, 1.5)
		var val_scale = clampf(float(_current_val) / 100.0 + 0.5, 0.5, 1.5)
		EventBus.pet_color_changed.emit(_target_index, _current_hue, sat_scale, val_scale)
		SettingsManager.set_pet_color(_target_index, int(_current_hue * 360.0), _current_sat, _current_val)
		_check_color_conflict()

func _check_color_conflict() -> void:
	var main_node = get_tree().root.get_node_or_null("Main")
	if not main_node or not "pet_instances" in main_node:
		_conflict_label.text = ""
		return
	var pets: Array = main_node.pet_instances
	var closest_name := ""
	var closest_dist := 1.0
	for i in range(pets.size()):
		if i == _target_index or not is_instance_valid(pets[i]) or not pets[i].palette:
			continue
		var other_hue = pets[i].palette.hue
		var d = absf(_current_hue - other_hue)
		d = minf(d, 1.0 - d)
		if d < closest_dist:
			closest_dist = d
			closest_name = "SYS_0 (原体)" if i == 0 else ("CLONE_" + str(i) + " (分身)")
	if closest_dist < 0.06:
		_conflict_label.text = "※ 与「" + closest_name + "」波长高度重合。建议区隔。"
	elif closest_dist < 0.10:
		_conflict_label.text = "※ 与「" + closest_name + "」波长存在耦合可能。"
	else:
		_conflict_label.text = ""

# ═══════════════════════════════════════════════
#  工具
# ═══════════════════════════════════════════════

func _get_pet() -> Node:
	var main_n = get_tree().root.get_node_or_null("Main")
	if main_n and "pet_instances" in main_n and main_n.pet_instances.size() > 0:
		return main_n.pet_instances[0]
	return null

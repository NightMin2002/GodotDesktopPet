# datalog_list_view.gd — 日志卡片 + 标签徽章 渲染
# 纯静态工厂: 不持有状态, 通过参数和回调协作
extends RefCounted

## 渲染日志列表卡片
static func make_log_card(entry: Dictionary, idx: int, selected_idx: int,
		on_select: Callable, make_badge: Callable) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var is_sel = (idx == selected_idx)
	var cs = StyleBoxFlat.new()
	if is_sel:
		cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.20, 0.7)
		cs.border_width_left = 3
		cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.85, 0.8)
	else:
		cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.20, 0.10, 0.3)
		cs.border_width_left = 2
		cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.2)
	cs.set_corner_radius_all(2)
	cs.content_margin_left = 12; cs.content_margin_right = 10
	cs.content_margin_top = 8; cs.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", cs)

	# hover 效果
	var hover_bg = Color.from_hsv(EventBus.ui_hue, 0.28, 0.16, 0.55)
	var normal_bg = cs.bg_color
	card.mouse_entered.connect(func():
		if idx != selected_idx:
			cs.bg_color = hover_bg
			cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.4)
	)
	card.mouse_exited.connect(func():
		if idx != selected_idx:
			cs.bg_color = normal_bg
			cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.2)
	)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# 顶行: 标签 + 时间
	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	var tags = entry.get("tags", [])
	var tag_count = 0
	for tag in tags:
		if tag_count >= 3:
			break
		top_row.add_child(make_badge.call(str(tag), false))
		tag_count += 1

	var time_spacer = Control.new()
	time_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(time_spacer)

	var time_str = entry.get("updated", entry.get("created", ""))
	if time_str.length() >= 16:
		time_str = time_str.substr(0, 16)
	var time_l = Label.new()
	time_l.text = time_str
	time_l.add_theme_font_size_override("font_size", 10)
	time_l.add_theme_color_override("font_color", Color(0.35, 0.40, 0.45, 0.4))
	time_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(time_l)

	# 标题
	var title_text = entry.get("title", "").strip_edges()
	var title_l = Label.new()
	if title_text == "":
		title_l.text = "无标题"
		title_l.add_theme_color_override("font_color", Color(0.40, 0.44, 0.50, 0.4))
	else:
		title_l.text = title_text
		title_l.add_theme_color_override("font_color", Color(0.82, 0.87, 0.92, 0.95) if is_sel else Color(0.68, 0.74, 0.80, 0.85))
	title_l.add_theme_font_size_override("font_size", 14)
	title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_l)

	# 内容预览
	var preview_text = entry.get("content", "").strip_edges()
	if preview_text.length() > 60:
		preview_text = preview_text.substr(0, 60) + "..."
	if preview_text != "":
		var preview_l = Label.new()
		preview_l.text = preview_text
		preview_l.add_theme_font_size_override("font_size", 11)
		preview_l.add_theme_color_override("font_color", Color(0.38, 0.42, 0.48, 0.4))
		preview_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		preview_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(preview_l)

	# 点击选中
	var i_copy = idx
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			on_select.call(i_copy)
	)

	return card

## 标签徽章 (胶囊样式)
static func make_tag_badge(tag_text: String, with_close: bool, on_remove: Callable) -> Control:
	var badge = PanelContainer.new()
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.40, 0.25, 0.65)
	bs.set_corner_radius_all(8)
	bs.set_border_width_all(1)
	bs.border_color = Color.from_hsv(EventBus.ui_hue, 0.45, 0.6, 0.45)
	bs.content_margin_left = 7; bs.content_margin_right = 7
	bs.content_margin_top = 2; bs.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", bs)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE if not with_close else Control.MOUSE_FILTER_PASS

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 3)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(hbox)

	var lbl = Label.new()
	lbl.text = tag_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.45, 0.8, 0.75))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	if with_close:
		var x_btn = Button.new()
		x_btn.text = "x"
		x_btn.add_theme_font_size_override("font_size", 9)
		x_btn.add_theme_color_override("font_color", Color(0.5, 0.35, 0.35, 0.4))
		x_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.4, 0.4, 0.9))
		var x_s = StyleBoxEmpty.new()
		x_btn.add_theme_stylebox_override("normal", x_s)
		x_btn.add_theme_stylebox_override("hover", x_s)
		x_btn.add_theme_stylebox_override("pressed", x_s)
		x_btn.custom_minimum_size = Vector2(12, 12)
		var tag_ref = tag_text
		x_btn.pressed.connect(func(): on_remove.call(tag_ref))
		hbox.add_child(x_btn)

	return badge

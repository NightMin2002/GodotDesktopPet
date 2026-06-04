# sec_visual.gd — 视觉分区 (构建 + 回调 + 特效配色 + 弹性形变)
extends RefCounted



var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _effects_btn: Button
var _elastic_btn: Button
var _hover_btn: Button
var _trail_btn: Button
var _effect_color_btns: Array[Button] = []

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx.make_submenu_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_effects_btn = ctx._make_menu_btn("特效 [+]", Color(1.0, 0.85, 0.3, 1))
	vbox.add_child(_effects_btn)
	ctx._bind_l3_trigger(_effects_btn, "effects", "sec_visual")

	_elastic_btn = ctx._make_menu_btn(ctx.get_radio_title("elastic"), Color(1.0, 0.85, 0.3, 1))
	vbox.add_child(_elastic_btn)
	ctx.register_radio_title("elastic", _elastic_btn)
	ctx._bind_l3_trigger(_elastic_btn, "elastic", "sec_visual")
	
	_trail_btn = ctx._make_menu_btn(ctx.get_radio_title("trail_style"), Color(1.0, 0.85, 0.3, 1))
	vbox.add_child(_trail_btn)
	ctx.register_radio_title("trail_style", _trail_btn)
	ctx._bind_l3_trigger(_trail_btn, "trail_style", "sec_visual")
	
	_hover_btn = ctx._make_menu_btn(ctx.get_radio_title("hover_fx"), Color(1.0, 0.85, 0.3, 1))
	vbox.add_child(_hover_btn)
	ctx.register_radio_title("hover_fx", _hover_btn)
	ctx._bind_l3_trigger(_hover_btn, "hover_fx", "sec_visual")

	ctx.register_l2_panel("sec_visual", panel)

	# L3: 特效开关子菜单
	ctx.create_toggle_group("effects", "effects", 3, "sec_visual")
	_append_effect_color_radio()

	# L3: 弹性形变单选
	ctx.create_radio_group("elastic", 3, "sec_visual")
	
	# L3: 悬停特效单选
	ctx.create_radio_group("hover_fx", 3, "sec_visual")

	# L3: 尾流特效单选
	ctx.create_radio_group("trail_style", 3, "sec_visual")

# ── 特效配色 ──

func _append_effect_color_radio() -> void:
	var effects_panel = ctx._submenu.l3_panels.get("effects")
	if not effects_panel:
		return
	var vbox = effects_panel.get_child(0)

	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 3)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	var label = Label.new()
	label.text = "特效配色"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75, 0.5))
	vbox.add_child(label)

	var saved = ctx.get_radio_value("effect_color_mode")
	_effect_color_btns.clear()
	for item in ctx.get_radio_items("effect_color_mode"):
		var btn = CyberMenuButton.new()

		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.1, 1, 0.9, 1))
		btn.text = item.label + (" [●]" if item.value == saved else " [○]")
		var val = item.value
		btn.pressed.connect(func(): _on_radio_effect_color(val))
		vbox.add_child(btn)
		_effect_color_btns.append(btn)

func _on_radio_effect_color(value: int) -> void:
	ctx.apply_registered_radio("effect_color_mode", value)
	var items = ctx.get_radio_items("effect_color_mode")
	for i in range(_effect_color_btns.size()):
		var item = items[i]
		_effect_color_btns[i].text = item.label + (" [●]" if item.value == value else " [○]")

# sec_visual.gd — 视觉分区 (构建 + 回调 + 特效配色 + 弹性形变)
extends RefCounted

const _CyberMenuBtn = preload("res://ui/context_menu/cyber_menu_button.gd")

var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _effects_btn: Button
var _elastic_btn: Button
var _theme_btn: Button
var _effect_color_btns: Array[Button] = []

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_effects_btn = ctx._make_menu_btn("特效 [+]", Color(1.0, 0.85, 0.3, 1))
	vbox.add_child(_effects_btn)
	ctx._bind_l3_trigger(_effects_btn, "effects", "sec_visual")

	_elastic_btn = ctx._make_menu_btn("弹性 · 关闭 [+]", Color(1.0, 0.85, 0.3, 1))
	vbox.add_child(_elastic_btn)
	ctx._bind_l3_trigger(_elastic_btn, "elastic", "sec_visual")

	_theme_btn = ctx._make_menu_btn("外观主题", Color(1.0, 0.85, 0.3, 1))
	ctx._apply_capsule_style(_theme_btn, Color(0.12, 0.22, 0.42, 0.7), Color(0.4, 0.6, 0.9, 0.5))
	_theme_btn.pressed.connect(func():
		ctx._close_and_emit(EventBus.show_theme_panel)
	)
	vbox.add_child(_theme_btn)

	panel.mouse_entered.connect(func(): ctx._submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.panels["sec_visual"] = panel

	# L3: 特效开关子菜单
	ctx._submenu.create_toggle("effects", [
		{"id": "shockwave", "on": "撞击冲击波 [●]", "off": "撞击冲击波 [○]", "key": "shockwave", "default": true},
		{"id": "trail_fx", "on": "粒子尾流 [●]", "off": "粒子尾流 [○]", "key": "trail_fx", "default": true},
		{"id": "arc_fx", "on": "静电弧 [●]", "off": "静电弧 [○]", "key": "arc_fx", "default": true},
	], 3)
	ctx._submenu._l3_parent_map["effects"] = "sec_visual"
	_append_effect_color_radio()

	# L3: 弹性形变单选
	ctx._submenu.create_radio("elastic", [
		{"value": 0, "label": "关闭", "desc": "标准球体，无弹性效果"},
		{"value": 1, "label": "轻弹", "desc": "自然柔弹，快速恢复"},
		{"value": 2, "label": "果冻", "desc": "QQ弹弹，慢速晃动恢复"},
		{"value": 3, "label": "弹力球", "desc": "弹性十足，强力回弹"},
	], _on_radio_elastic, 3)
	ctx._submenu._l3_parent_map["elastic"] = "sec_visual"

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

	var saved = SettingsManager.get_int("effect_color_mode", 0)
	var labels = ["虹彩模式", "跟随体色"]
	_effect_color_btns.clear()
	for i in range(2):
		var btn = _CyberMenuBtn.new()

		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.1, 1, 0.9, 1))
		btn.text = labels[i] + (" [●]" if i == saved else " [○]")
		var val = i
		btn.pressed.connect(func(): _on_radio_effect_color(val))
		vbox.add_child(btn)
		_effect_color_btns.append(btn)

func _on_radio_effect_color(value: int) -> void:
	SettingsManager.set_int("effect_color_mode", value)
	EventBus.setting_toggled.emit("effect_color_mode", value > 0)
	var labels = ["虹彩模式", "跟随体色"]
	for i in range(_effect_color_btns.size()):
		_effect_color_btns[i].text = labels[i] + (" [●]" if i == value else " [○]")

# ── 弹性形变 ──

func _on_radio_elastic(value: int) -> void:
	SettingsManager.set_int("elastic_mode", value)
	apply_elastic_mode(value, true)

func apply_elastic_mode(value: int, emit_signal: bool) -> void:
	if value == 0:
		_elastic_btn.text = "弹性 · 关闭 [+]"
		if emit_signal:
			EventBus.trigger_squash_test.emit(-1)
	else:
		var names := ["轻弹", "果冻", "弹力球"]
		var idx = clampi(value - 1, 0, 2)
		_elastic_btn.text = "弹性 · " + names[idx] + " [+]"
		if emit_signal:
			EventBus.trigger_squash_test.emit(idx)

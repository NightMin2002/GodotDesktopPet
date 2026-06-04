# sec_behavior.gd — 行为分区 (构建 + 回调 + debug 子菜单)
extends RefCounted



var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _window_mode_btn: Button
var _behavior_mode_btn: Button
var _gait_btn: Button
var _mode_btn: Button

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx.make_submenu_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_window_mode_btn = ctx._make_menu_btn(ctx.get_radio_title("window_mode"), Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_window_mode_btn)
	ctx.register_radio_title("window_mode", _window_mode_btn)
	ctx._bind_l3_trigger(_window_mode_btn, "window_mode", "sec_behavior")

	_behavior_mode_btn = ctx._make_menu_btn(ctx.get_radio_title("behavior_mode"), Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_behavior_mode_btn)
	ctx.register_radio_title("behavior_mode", _behavior_mode_btn)
	ctx._bind_l3_trigger(_behavior_mode_btn, "behavior_mode", "sec_behavior")

	_gait_btn = ctx._make_menu_btn(ctx.get_radio_title("gait"), Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_gait_btn)
	ctx.register_radio_title("gait", _gait_btn)
	ctx._bind_l3_trigger(_gait_btn, "gait", "sec_behavior")

	_mode_btn = ctx._make_menu_btn("模式 [+]", Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_mode_btn)
	ctx._bind_l3_trigger(_mode_btn, "mode", "sec_behavior")

	ctx.register_l2_panel("sec_behavior", panel)

	# L3 子菜单
	ctx.create_radio_group("window_mode", 3, "sec_behavior")
	ctx.create_radio_group("behavior_mode", 3, "sec_behavior")
	ctx.create_radio_group("gait", 3, "sec_behavior")
	ctx.create_toggle_group("mode", "mode", 3, "sec_behavior")
	# 模式子菜单追加踏板外观胶囊
	_append_platform_style_capsule()

func on_behavior_mode_synced(mode: int) -> void:
	ctx.refresh_registered_radio("behavior_mode", mode)

# ── 踏板外观胶囊 ──

func _append_platform_style_capsule() -> void:
	var mode_panel = ctx._submenu.l3_panels.get("mode")
	if not mode_panel: return
	var vbox = mode_panel.get_child(0) as VBoxContainer
	if not vbox: return

	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.8, 1.0, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	var btn = CyberMenuButton.new()
	btn.text = "踏板外观"
	btn.add_theme_font_size_override("font_size", 17)
	ctx._apply_capsule_style(btn,
		Color(0.08, 0.15, 0.3, 0.5),
		Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.35))
	btn.pressed.connect(func():
		ctx._close_and_emit(EventBus.show_platform_style_panel)
	)
	vbox.add_child(btn)



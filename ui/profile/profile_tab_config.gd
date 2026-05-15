# profile_tab_config.gd — 终端配置 Tab (装置终端 Tab 5)
# 系统级开关设置: 随系统唤醒 + 未来扩展
extends HBoxContainer

var _wake_btn: Button
var _wake_status: Label

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 20)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(main_vbox)

	# ── 1. 启动行为 ──
	_build_startup_card(main_vbox)

	# ── 2. 预留区域 ──
	_build_reserved_card(main_vbox)

	# 滚动指示器
	var indicator = preload("res://ui/profile/cyber_scroll_indicator.gd").new()
	indicator.bind_scroll(scroll)
	add_child(indicator)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	build()

# ═══════════════════════════════════════════════
#  启动行为
# ═══════════════════════════════════════════════

func _build_startup_card(parent: VBoxContainer) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.16, 0.45)
	cs.border_width_left = 4
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.7)
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 24; cs.content_margin_right = 24
	cs.content_margin_top = 20; cs.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	# 标题行
	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim("SYS_CONFIG //", 13))
	title_row.add_child(ProfileStyles.make_label("启动行为", 17, Color(0.85, 0.9, 0.95)))
	vbox.add_child(title_row)

	# 描述
	var desc = Label.new()
	desc.text = "控制本机是否在操作系统启动时自动唤醒进入工作状态。"
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	# 开关行
	var switch_row = HBoxContainer.new()
	switch_row.add_theme_constant_override("separation", 16)

	_wake_btn = Button.new()
	_wake_btn.add_theme_font_size_override("font_size", 15)
	_wake_btn.pressed.connect(_on_wake_toggle)
	switch_row.add_child(_wake_btn)

	_wake_status = Label.new()
	_wake_status.add_theme_font_size_override("font_size", 13)
	_wake_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	switch_row.add_child(_wake_status)

	vbox.add_child(switch_row)

	# 异步检测当前状态
	_check_wake_status.call_deferred()

func _check_wake_status() -> void:
	var win_mgr = _get_win_manager()
	if win_mgr and win_mgr.has_method("IsAutoStartEnabled"):
		var on: bool = win_mgr.call("IsAutoStartEnabled")
		_apply_wake_style(on)
	else:
		_apply_wake_style(false)
		_wake_btn.disabled = true
		_wake_status.text = "> 无法访问注册表服务"
		_wake_status.add_theme_color_override("font_color", Color(0.7, 0.5, 0.4, 0.7))

func _on_wake_toggle() -> void:
	var win_mgr = _get_win_manager()
	if not win_mgr or not win_mgr.has_method("SetAutoStart"):
		return
	var current: bool = win_mgr.call("IsAutoStartEnabled")
	var new_val = not current
	win_mgr.call("SetAutoStart", new_val)
	_apply_wake_style(new_val)

func _apply_wake_style(is_on: bool) -> void:
	if not is_instance_valid(_wake_btn):
		return

	var accent = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85)

	if is_on:
		_wake_btn.text = "随系统唤醒 · 已启用"
		var s = StyleBoxFlat.new()
		s.bg_color = Color(accent.r * 0.2, accent.g * 0.2, accent.b * 0.2, 0.6)
		s.border_width_left = 3
		s.border_color = accent
		s.set_corner_radius_all(0)
		s.content_margin_left = 16; s.content_margin_right = 16
		s.content_margin_top = 8; s.content_margin_bottom = 8
		_wake_btn.add_theme_stylebox_override("normal", s)
		var h = s.duplicate()
		h.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.7)
		_wake_btn.add_theme_stylebox_override("hover", h)
		_wake_btn.add_theme_stylebox_override("pressed", h)
		_wake_btn.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
		_wake_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.97, 1.0, 1.0))

		if is_instance_valid(_wake_status):
			_wake_status.text = "> 系统启动时将自动唤醒本机"
			_wake_status.add_theme_color_override("font_color", Color(0.4, 0.7, 0.5, 0.7))
	else:
		_wake_btn.text = "随系统唤醒 · 未启用"
		var s = StyleBoxFlat.new()
		s.bg_color = Color(0.08, 0.1, 0.15, 0.5)
		s.border_width_left = 3
		s.border_color = Color(0.4, 0.45, 0.5, 0.4)
		s.set_corner_radius_all(0)
		s.content_margin_left = 16; s.content_margin_right = 16
		s.content_margin_top = 8; s.content_margin_bottom = 8
		_wake_btn.add_theme_stylebox_override("normal", s)
		var h = s.duplicate()
		h.bg_color = Color(0.12, 0.14, 0.2, 0.6)
		h.border_color = Color(0.5, 0.55, 0.6, 0.5)
		_wake_btn.add_theme_stylebox_override("hover", h)
		_wake_btn.add_theme_stylebox_override("pressed", h)
		_wake_btn.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 0.8))
		_wake_btn.add_theme_color_override("font_hover_color", Color(0.75, 0.8, 0.85, 0.9))

		if is_instance_valid(_wake_status):
			_wake_status.text = "> 需要手动启动"
			_wake_status.add_theme_color_override("font_color", ProfileStyles.dim())

# ═══════════════════════════════════════════════
#  预留区域
# ═══════════════════════════════════════════════

func _build_reserved_card(parent: VBoxContainer) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.04, 0.06, 0.1, 0.4)
	cs.border_width_left = 2
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.3)
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 20; cs.content_margin_right = 20
	cs.content_margin_top = 16; cs.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim("RESERVED //", 12))
	title_row.add_child(ProfileStyles.make_label("扩展配置", 15, Color(0.75, 0.82, 0.9)))
	vbox.add_child(title_row)

	var note = Label.new()
	note.text = "更多配置项将在后续版本中开放。"
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 0.5))
	vbox.add_child(note)

# ═══════════════════════════════════════════════
#  工具
# ═══════════════════════════════════════════════

func _get_win_manager() -> Node:
	var tree = get_tree()
	if not tree: return null
	var main_node = tree.root.get_node_or_null("Main")
	if main_node:
		for child in main_node.get_children():
			if child.get_class() == "WindowsManager" or child.has_method("IsAutoStartEnabled"):
				return child
	return null

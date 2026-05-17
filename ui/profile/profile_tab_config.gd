# profile_tab_config.gd — 终端配置 Tab (装置终端 Tab 5)
# 系统级开关设置: 随系统唤醒 + 全息屏配置
extends HBoxContainer

var _wake_btn: Button
var _wake_status: Label
var _holo_preview_active: bool = false  # 预览状态

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

	# ── 2. 个人终端 ──
	_build_holo_card(main_vbox)

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
#  个人终端 (全息屏参数)
# ═══════════════════════════════════════════════

const _HOLO_DEFAULTS := {"holo_size": 10, "holo_tilt": 0}

var _holo_sliders: Dictionary = {}  # key -> {slider, value_label}

func _build_holo_card(parent: VBoxContainer) -> void:
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
	title_row.add_child(ProfileStyles.label_dim("HOLO_CFG //", 13))
	title_row.add_child(ProfileStyles.make_label("个人终端", 17, Color(0.85, 0.9, 0.95)))
	vbox.add_child(title_row)

	# 描述
	var desc = Label.new()
	desc.text = "调整全息迷你屏幕的投影参数。修改后实时生效。"
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	# 滑条: 屏幕尺寸 (1.0x ~ 2.0x)
	_add_holo_slider(vbox, "holo_size", "屏幕尺寸", 10, 20, 10,
		func(v: int) -> String: return "%.1fx" % (v / 10.0))

	# 滑条: 后仰角度
	_add_holo_slider(vbox, "holo_tilt", "后仰角度", 0, 25, 0,
		func(v: int) -> String: return "%d%%" % v)

	# 按钮行: 预览 + 恢复默认
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)

	# 预览参考按钮
	var preview_btn = _make_config_btn("显示参考")
	preview_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.35, 0.7, 0.6))
	preview_btn.add_theme_color_override("font_hover_color", Color.from_hsv(EventBus.ui_hue, 0.45, 0.9, 0.9))
	preview_btn.pressed.connect(func(): _toggle_holo_preview(preview_btn))
	btn_row.add_child(preview_btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.add_child(spacer)

	# 恢复默认按钮
	var reset_btn = _make_config_btn("[ 恢复默认 ]")
	reset_btn.pressed.connect(_on_holo_reset)
	btn_row.add_child(reset_btn)
	vbox.add_child(btn_row)

## 通用滑条构建器
func _add_holo_slider(parent: VBoxContainer, key: String, label: String,
		min_val: int, max_val: int, default_val: int, formatter: Callable) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	# 标签
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 80
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 0.8))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	# 滑条
	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 1
	slider.value = SettingsManager.get_int(key, default_val)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 20
	# 滑条样式
	var grabber_s = StyleBoxFlat.new()
	grabber_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.9)
	grabber_s.set_corner_radius_all(2)
	grabber_s.content_margin_left = 6; grabber_s.content_margin_right = 6
	grabber_s.content_margin_top = 6; grabber_s.content_margin_bottom = 6
	slider.add_theme_stylebox_override("grabber_area", grabber_s)
	var track_s = StyleBoxFlat.new()
	track_s.bg_color = Color(0.1, 0.12, 0.18, 0.6)
	track_s.set_corner_radius_all(1)
	track_s.content_margin_top = 2; track_s.content_margin_bottom = 2
	slider.add_theme_stylebox_override("slider", track_s)
	row.add_child(slider)

	# 数值
	var val_lbl = Label.new()
	val_lbl.custom_minimum_size.x = 50
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 14)
	val_lbl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.85, 0.85))
	val_lbl.text = formatter.call(int(slider.value))
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(val_lbl)

	parent.add_child(row)

	# 存引用
	_holo_sliders[key] = {"slider": slider, "value_label": val_lbl, "formatter": formatter}

	# 实时联动
	slider.value_changed.connect(func(v: float):
		var iv = int(v)
		SettingsManager.set_int(key, iv)
		val_lbl.text = formatter.call(iv)
	)

## 恢复全息屏默认参数
func _on_holo_reset() -> void:
	for key in _HOLO_DEFAULTS:
		var def_val = _HOLO_DEFAULTS[key]
		SettingsManager.set_int(key, def_val)
		if key in _holo_sliders:
			var entry = _holo_sliders[key]
			entry.slider.value = def_val
			entry.value_label.text = entry.formatter.call(def_val)

## 配置按钮工厂
func _make_config_btn(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 0.6))
	btn.add_theme_color_override("font_hover_color", Color(0.9, 0.5, 0.35, 1.0))
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.12, 0.4)
	s.set_corner_radius_all(0)
	s.set_border_width_all(1)
	s.border_color = Color(0.4, 0.35, 0.3, 0.2)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 4; s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(0.12, 0.08, 0.06, 0.5)
	h.border_color = Color(0.6, 0.35, 0.25, 0.4)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn

## 切换全息屏预览
func _toggle_holo_preview(btn: Button) -> void:
	var pet = _get_pet()
	if not pet or not ("holo_screen" in pet):
		return
	var holo = pet.holo_screen
	if not holo:
		return
	if _holo_preview_active:
		holo.hide()
		_holo_preview_active = false
		btn.text = "显示参考"
	else:
		# 弹出待机屏作为参考
		var vp_w = get_viewport().get_visible_rect().size.x
		var screen_side = -1.0 if pet.global_position.x > vp_w * 0.5 else 1.0
		holo.show_idle(screen_side)
		_holo_preview_active = true
		btn.text = "收起参考"

## 清理预览 (装置终端关闭时调用)
func cleanup() -> void:
	if _holo_preview_active:
		var pet = _get_pet()
		if pet and "holo_screen" in pet and pet.holo_screen:
			pet.holo_screen.hide()
		_holo_preview_active = false

# ═══════════════════════════════════════════════
#  工具
# ═══════════════════════════════════════════════

func _get_pet() -> Node:
	var tree = get_tree()
	if not tree: return null
	var main_n = tree.root.get_node_or_null("Main")
	if main_n and "pet_instances" in main_n and main_n.pet_instances.size() > 0:
		return main_n.pet_instances[0]
	return null

func _get_win_manager() -> Node:
	var tree = get_tree()
	if not tree: return null
	var main_node = tree.root.get_node_or_null("Main")
	if main_node:
		for child in main_node.get_children():
			if child.get_class() == "WindowsManager" or child.has_method("IsAutoStartEnabled"):
				return child
	return null

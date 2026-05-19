# profile_tab_config.gd — 终端配置 Tab (装置终端 Tab 5)
# 系统级开关设置: 随系统唤醒 + 全息屏配置 + 快捷键绑定
extends HBoxContainer

const HotkeyManager = preload("res://core/hotkey_manager.gd")

var _wake_btn: Button
var _wake_status: Label
var _holo_preview_active: bool = false  # 预览状态

# ── 快捷键 ──
var _hotkey_rows: Dictionary = {}  # action -> { combo_label, record_btn, status_label }
var _recording_action: String = ""  # 当前正在录入的 action ("" = 未录入)

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

	# ── 3. 快捷键配置 ──
	_build_hotkey_card(main_vbox)

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

	# 滑条: 屏幕尺寸 (1.0x ~ 1.5x)
	_add_holo_slider(vbox, "holo_size", "屏幕尺寸", 10, 15, 10,
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
		holo.show_idle(screen_side, 0)  # 预览不自动关闭
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
#  快捷键配置
# ═══════════════════════════════════════════════

func _build_hotkey_card(parent: VBoxContainer) -> void:
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
	title_row.add_child(ProfileStyles.label_dim("KEY_BIND //", 13))
	title_row.add_child(ProfileStyles.make_label("快捷键配置", 17, Color(0.85, 0.9, 0.95)))
	vbox.add_child(title_row)

	# 描述
	var desc = Label.new()
	desc.text = "为常用操作绑定全局快捷键。即使本机不在前台也能响应。"
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	# 热键行
	_hotkey_rows.clear()
	var hotkey_mgr = _get_hotkey_mgr()
	for action in HotkeyManager.HOTKEY_DEFS:
		var def = HotkeyManager.HOTKEY_DEFS[action]
		var current = def["default"]
		if hotkey_mgr:
			current = hotkey_mgr.get_binding(action)
			if current == "":
				current = def["default"]
		_add_hotkey_row(vbox, action, _action_label(action), current)

	# 恢复默认按钮
	var btn_row = HBoxContainer.new()
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.add_child(spacer)
	var reset_btn = _make_config_btn("[ 恢复默认 ]")
	reset_btn.pressed.connect(_on_hotkey_reset)
	btn_row.add_child(reset_btn)
	vbox.add_child(btn_row)

func _action_label(action: String) -> String:
	match action:
		"quick_memo": return "快速备忘"
		"profile_panel": return "装置终端"
		"quiet_mode": return "安静待命"
	return action

func _add_hotkey_row(parent: VBoxContainer, action: String, label: String, combo: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	# 启用开关
	var hotkey_mgr = _get_hotkey_mgr()
	var enabled = hotkey_mgr.is_enabled(action) if hotkey_mgr else true
	var toggle = CheckButton.new()
	toggle.button_pressed = enabled
	toggle.custom_minimum_size = Vector2(40, 0)
	toggle.tooltip_text = "启用/禁用此快捷键"
	var act_toggle = action
	toggle.toggled.connect(func(on: bool): _on_hotkey_toggled(act_toggle, on))
	row.add_child(toggle)

	# 操作名
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 80
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 0.8))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	# 组合键显示
	var combo_lbl = Label.new()
	combo_lbl.text = HotkeyManager.format_combo(combo)
	combo_lbl.custom_minimum_size.x = 140
	combo_lbl.add_theme_font_size_override("font_size", 14)
	combo_lbl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.35, 0.85, 0.85) if enabled else Color(0.4, 0.4, 0.4, 0.4))
	combo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(combo_lbl)

	# 录入按钮
	var rec_btn = _make_config_btn("录入")
	rec_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.35, 0.7, 0.6))
	rec_btn.add_theme_color_override("font_hover_color", Color.from_hsv(EventBus.ui_hue, 0.45, 0.9, 0.9))
	var act = action
	rec_btn.pressed.connect(func(): _start_recording(act))
	row.add_child(rec_btn)

	# 状态提示
	var status = Label.new()
	status.text = ""
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color(0.4, 0.7, 0.5, 0.7))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status)

	parent.add_child(row)
	_hotkey_rows[action] = {"combo_label": combo_lbl, "record_btn": rec_btn, "status_label": status, "toggle": toggle, "name_label": lbl}

	# 初始禁用态视觉
	if not enabled:
		_apply_disabled_visual(action)

func _on_hotkey_toggled(action: String, enabled: bool) -> void:
	var hotkey_mgr = _get_hotkey_mgr()
	if hotkey_mgr:
		hotkey_mgr.set_enabled(action, enabled)
	# 视觉反馈
	if enabled:
		_apply_enabled_visual(action)
	else:
		# 如果正在录入这个热键, 先停止
		if _recording_action == action:
			_stop_recording()
		_apply_disabled_visual(action)

func _apply_disabled_visual(action: String) -> void:
	var row = _hotkey_rows.get(action, {})
	if row.is_empty():
		return
	row.combo_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 0.4))
	row.name_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 0.5))
	row.record_btn.disabled = true
	row.record_btn.modulate.a = 0.35
	row.status_label.text = "已禁用"
	row.status_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4, 0.5))

func _apply_enabled_visual(action: String) -> void:
	var row = _hotkey_rows.get(action, {})
	if row.is_empty():
		return
	row.combo_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.35, 0.85, 0.85))
	row.name_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 0.8))
	row.record_btn.disabled = false
	row.record_btn.modulate.a = 1.0
	row.status_label.text = ""

func _start_recording(action: String) -> void:
	# 先注销当前热键 (录入期间不响应)
	var hotkey_mgr = _get_hotkey_mgr()
	if hotkey_mgr:
		hotkey_mgr.unregister(action)
	_recording_action = action
	var row = _hotkey_rows.get(action, {})
	if row.is_empty():
		return
	row.record_btn.text = "按下组合键..."
	row.record_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3, 0.9))
	row.status_label.text = "ESC 取消"
	row.status_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 0.5))
	# 呼吸动画
	var tw = create_tween().set_loops()
	tw.tween_property(row.record_btn, "modulate:a", 0.5, 0.6)
	tw.tween_property(row.record_btn, "modulate:a", 1.0, 0.6)
	row["breath_tween"] = tw

func _stop_recording() -> void:
	if _recording_action == "":
		return
	var row = _hotkey_rows.get(_recording_action, {})
	if not row.is_empty():
		row.record_btn.text = "录入"
		row.record_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.35, 0.7, 0.6))
		row.record_btn.modulate.a = 1.0
		if row.has("breath_tween") and row.breath_tween is Tween:
			row.breath_tween.kill()
	# 重新注册热键
	var hotkey_mgr = _get_hotkey_mgr()
	if hotkey_mgr:
		var combo = hotkey_mgr.get_binding(_recording_action)
		if combo != "":
			hotkey_mgr.rebind(_recording_action, combo)
	_recording_action = ""

func _unhandled_key_input(event: InputEvent) -> void:
	if _recording_action == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return

	# ESC 取消录入
	if event.keycode == KEY_ESCAPE:
		var row = _hotkey_rows.get(_recording_action, {})
		if not row.is_empty():
			row.status_label.text = "已取消"
			row.status_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 0.5))
		_stop_recording()
		get_viewport().set_input_as_handled()
		return

	# 构建组合键字符串
	var combo = HotkeyManager.event_to_combo(event)
	if combo == "":
		return  # 只按了修饰键

	get_viewport().set_input_as_handled()

	# 冲突检测
	var hotkey_mgr = _get_hotkey_mgr()
	var row = _hotkey_rows.get(_recording_action, {})
	if row.is_empty():
		_stop_recording()
		return

	row.combo_label.text = HotkeyManager.format_combo(combo)

	var conflict = {"available": true, "reason": ""}
	if hotkey_mgr:
		conflict = hotkey_mgr.check_conflict(combo, _recording_action)

	if not conflict.available:
		var reason: String = conflict.reason
		if reason.begins_with("internal:"):
			var other_action = reason.substr(9)
			row.status_label.text = "已绑定到 [%s]" % _action_label(other_action)
			row.status_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2, 0.9))
		elif reason == "system":
			row.status_label.text = "系统保留组合键"
			row.status_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2, 0.9))
		elif reason == "occupied":
			row.status_label.text = "已被其他程序占用"
			row.status_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3, 0.9))
		else:
			row.status_label.text = "不可用"
			row.status_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3, 0.9))
		# 不绑定, 保持录入模式让用户重试或 ESC 取消
		return

	# 可用 — 绑定并退出录入
	row.status_label.text = "已绑定"
	row.status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.5, 0.9))
	if hotkey_mgr:
		hotkey_mgr.rebind(_recording_action, combo)
	_stop_recording()

	# 2 秒后清除状态文字
	var tw = create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func():
		if not row.is_empty() and is_instance_valid(row.status_label):
			row.status_label.text = ""
	)

func _on_hotkey_reset() -> void:
	var hotkey_mgr = _get_hotkey_mgr()
	if _recording_action != "":
		_stop_recording()
	for action in HotkeyManager.HOTKEY_DEFS:
		var def = HotkeyManager.HOTKEY_DEFS[action]
		var default_combo: String = def["default"]
		if hotkey_mgr:
			hotkey_mgr.set_enabled(action, true)
			hotkey_mgr.rebind(action, default_combo)
		var row = _hotkey_rows.get(action, {})
		if not row.is_empty():
			row.combo_label.text = HotkeyManager.format_combo(default_combo)
			if row.has("toggle") and is_instance_valid(row.toggle):
				row.toggle.set_pressed_no_signal(true)
			_apply_enabled_visual(action)
			row.status_label.text = "已恢复"
			row.status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.5, 0.7))

func _get_hotkey_mgr() -> Node:
	if not is_inside_tree():
		return null
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "hotkey_mgr" in main_node:
		return main_node.hotkey_mgr
	return null

# ═══════════════════════════════════════════════
#  工具
# ═══════════════════════════════════════════════

func _get_pet() -> Node:
	return ProfileStyles.get_pet(get_tree())

func _get_win_manager() -> Node:
	return ProfileStyles.get_win_manager(get_tree())

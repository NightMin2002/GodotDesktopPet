# memo_popup.gd — 快速备忘弹窗 (CanvasLayer)
# 全局热键触发的轻量记事弹窗, 数据直接写入操作员备忘 (datalogs)
extends CanvasLayer

var _panel: PanelContainer
var _title_edit: LineEdit
var _content_edit: TextEdit
var _is_open: bool = false
var _saving: bool = false  # 防重复保存 (await 期间可能再次触发 Ctrl+S)

func _ready() -> void:
	layer = 10  # 最上层
	EventBus.show_memo_popup.connect(_toggle)

func _toggle() -> void:
	if _is_open:
		_close()
	else:
		_open()

func _open() -> void:
	if _is_open:
		return
	_is_open = true
	_build_ui()
	EventBus.context_menu_toggled.emit(true)
	# 宠物反馈: 全息屏显示录入状态
	var pet = _get_pet()
	if pet and "holo_screen" in pet and pet.holo_screen:
		if not pet.gaming.active and not pet.holo_screen.visible:
			var s: float = -1.0 if pet.global_position.x > pet.boundary_size.x * 0.5 else 1.0
			pet.holo_screen.show_loading("MEMO.REC", s, 0)

func _close() -> void:
	if not _is_open:
		return
	_is_open = false
	# 收起全息屏录入动画 (如果还在显示)
	var pet = _get_pet()
	if pet and "holo_screen" in pet and pet.holo_screen:
		var hs = pet.holo_screen
		if hs.visible and hs.mode == hs.Mode.LOADING:
			hs.hide()
	# 清理所有子节点 (panel + 任何其他 UI)
	for child in get_children():
		child.queue_free()
	_panel = null
	_title_edit = null
	_content_edit = null
	EventBus.context_menu_toggled.emit(false)

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S and event.ctrl_pressed:
			_on_save()
			get_viewport().set_input_as_handled()
	# 点击面板外区域关闭
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_instance_valid(_panel):
			var panel_rect = Rect2(_panel.global_position, _panel.size)
			if not panel_rect.has_point(event.position):
				_close()
				get_viewport().set_input_as_handled()

# ═══════════════════════════════════════════════
#  UI 构建
# ═══════════════════════════════════════════════

func _build_ui() -> void:
	var vp_size = get_viewport().get_visible_rect().size
	var pw := 520.0
	var ph := 380.0

	# 主面板 (无遮罩，桌宠不能覆盖桌面)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(pw, ph)
	_panel.size = Vector2(pw, ph)
	# 绝对定位到屏幕中央
	_panel.position = Vector2((vp_size.x - pw) * 0.5, (vp_size.y - ph) * 0.5)

	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.11, 0.95)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.7, 0.6)
	s.border_width_left = 3
	s.set_corner_radius_all(4)
	s.content_margin_left = 24; s.content_margin_right = 24
	s.content_margin_top = 18; s.content_margin_bottom = 18
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 16
	_panel.add_theme_stylebox_override("panel", s)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	# 标题行
	var header = Label.new()
	header.text = "MEMO_ENTRY //  快速备忘"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.6, 0.5))
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	# 标题输入
	var td = Time.get_datetime_dict_from_system()
	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = "标题"
	_title_edit.text = "备忘 %02d-%02d %02d:%02d" % [td.month, td.day, td.hour, td.minute]
	_title_edit.add_theme_font_size_override("font_size", 16)
	_title_edit.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.95))
	_title_edit.add_theme_color_override("font_placeholder_color", Color(0.40, 0.45, 0.50, 0.5))
	_title_edit.add_theme_color_override("caret_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.9))
	var le_bg = StyleBoxFlat.new()
	le_bg.bg_color = Color(0.04, 0.05, 0.08, 0.5)
	le_bg.set_corner_radius_all(2)
	le_bg.content_margin_left = 10; le_bg.content_margin_right = 10
	le_bg.content_margin_top = 6; le_bg.content_margin_bottom = 6
	_title_edit.add_theme_stylebox_override("normal", le_bg)
	var le_focus = le_bg.duplicate()
	le_focus.border_width_bottom = 1
	le_focus.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.5)
	_title_edit.add_theme_stylebox_override("focus", le_focus)
	vbox.add_child(_title_edit)

	# 正文编辑
	_content_edit = TextEdit.new()
	_content_edit.placeholder_text = "写点什么..."
	_content_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_content_edit.add_theme_font_size_override("font_size", 14)
	_content_edit.add_theme_color_override("font_color", Color(0.80, 0.85, 0.90, 0.95))
	_content_edit.add_theme_color_override("font_placeholder_color", Color(0.40, 0.45, 0.50, 0.5))
	_content_edit.add_theme_color_override("caret_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.9))
	var te_bg = StyleBoxFlat.new()
	te_bg.bg_color = Color(0.04, 0.05, 0.08, 0.5)
	te_bg.set_corner_radius_all(2)
	te_bg.set_content_margin_all(10)
	_content_edit.add_theme_stylebox_override("normal", te_bg)
	var te_focus = te_bg.duplicate()
	te_focus.border_width_bottom = 1
	te_focus.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.5)
	_content_edit.add_theme_stylebox_override("focus", te_focus)
	vbox.add_child(_content_edit)

	# 按钮行
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var cancel_btn = _make_btn("取消", Color(0.5, 0.55, 0.6, 0.6), Color(0.7, 0.75, 0.8, 0.9))
	cancel_btn.pressed.connect(_close)
	btn_row.add_child(cancel_btn)

	var save_btn = _make_btn("保存", Color.from_hsv(EventBus.ui_hue, 0.4, 0.9, 0.9), Color(1, 1, 1, 1))
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)

	# 键盘提示
	var hint = Label.new()
	hint.text = "Ctrl+S 保存 / ESC 取消"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.45, 0.50, 0.55, 0.55))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.add_child(hint)

	add_child(_panel)

	# 聚焦到正文 (先让窗口获得 OS 焦点)
	_deferred_focus.call_deferred()

func _deferred_focus() -> void:
	# 全局热键触发时用户可能在其他应用, Godot 窗口没有 OS 焦点
	# 必须先把窗口拉到前台, 否则 grab_focus 无效
	DisplayServer.window_move_to_foreground()
	await get_tree().process_frame
	if is_instance_valid(_content_edit):
		_content_edit.grab_focus()

func _make_btn(text: String, font_color: Color, hover_color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", hover_color)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.09, 0.14, 0.5)
	s.set_corner_radius_all(2)
	s.set_border_width_all(1)
	s.border_color = Color(0.3, 0.33, 0.38, 0.25)
	s.content_margin_left = 16; s.content_margin_right = 16
	s.content_margin_top = 6; s.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(0.12, 0.10, 0.08, 0.6)
	h.border_color = Color(0.5, 0.45, 0.4, 0.4)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn

# ═══════════════════════════════════════════════
#  保存
# ═══════════════════════════════════════════════

func _on_save() -> void:
	if _saving:
		return
	_saving = true
	var title = _title_edit.text.strip_edges() if is_instance_valid(_title_edit) else ""
	var content = _content_edit.text.strip_edges() if is_instance_valid(_content_edit) else ""
	if title == "" and content == "":
		_saving = false
		_close()
		return

	if title == "":
		var td = Time.get_datetime_dict_from_system()
		title = "备忘 %02d-%02d %02d:%02d" % [td.month, td.day, td.hour, td.minute]

	var now = Time.get_datetime_string_from_system(false, true)
	var entry = {
		"id": "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000],
		"title": title,
		"content": content,
		"tags": [],
		"source": "user",
		"created": now,
		"updated": now,
	}

	var logs = SettingsManager.get_datalogs()
	logs.insert(0, entry)
	SettingsManager.save_datalogs(logs)

	# 宠物反馈: 全息屏打勾确认 (平滑换屏, 骨架不动)
	var pet = _get_pet()
	if pet and "holo_screen" in pet and pet.holo_screen:
		var hs = pet.holo_screen
		var s: float = hs.side if hs.visible else 1.0
		hs.show_done(s, 2.5)

	_saving = false
	_close()

func _get_pet() -> Node:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instance" in main_node:
		return main_node.pet_instance
	return null

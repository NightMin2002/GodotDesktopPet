# reminder_panel.gd — 提醒管理面板
# 跟随宠物上方弹出，提供提醒增删 + 定时触发逻辑
# 支持每日重复 (🔁) 和一次性 (1×) 两种模式
extends CanvasLayer

var panel: PanelContainer
var list_box: VBoxContainer
var hour_spin: SpinBox       # 小时选择 (0-23)
var minute_spin: SpinBox     # 分钟选择 (0-59)
var msg_input: LineEdit
var once_btn: Button        # 一次性/每日 切换按钮

var _add_once := false       # 当前添加模式: false=每日重复, true=一次性
var _check_timer := 0.0
var _fired_keys: Dictionary = {}
var _pet: Node2D
var _guard_frames := 0

func _ready() -> void:
	_build_ui()
	EventBus.show_reminder_panel.connect(_toggle_panel)
	_find_pet.call_deferred()

func _find_pet() -> void:
	var main = get_tree().root.get_node_or_null("Main")
	if main:
		for child in main.get_children():
			if child is RigidBody2D:
				_pet = child
				return

func _process(delta: float) -> void:
	if panel.visible and is_instance_valid(_pet):
		var pet_pos = _pet.get_global_transform_with_canvas().get_origin()
		var target_pos = pet_pos + Vector2(-panel.size.x / 2, -panel.size.y - 50)
		target_pos = _clamp_pos(target_pos)
		panel.position = panel.position.lerp(target_pos, delta * 10.0)
	
	if _guard_frames > 0:
		_guard_frames -= 1
	
	_check_timer += delta
	if _check_timer >= 10.0:
		_check_timer = 0.0
		_check_reminders()

func _clamp_pos(pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 8.0, vp.x - panel.size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - panel.size.y - 8.0)
	return pos

# ── 定时检查 ──

func _check_reminders() -> void:
	var now_dict = Time.get_time_dict_from_system()
	var now_str = "%02d:%02d" % [now_dict["hour"], now_dict["minute"]]
	
	var today = Time.get_date_string_from_system()
	if _fired_keys.get("_date", "") != today:
		_fired_keys = {"_date": today}
	
	var reminders = SettingsManager.get_reminders()
	var to_remove: Array[int] = []  # 需要删除的一次性提醒索引
	
	for i in range(reminders.size()):
		var r = reminders[i]
		if not r.get("on", true):
			continue
		var key = r.get("time", "") + "|" + r.get("msg", "")
		if r.get("time", "") == now_str and not _fired_keys.has(key):
			_fired_keys[key] = true
			EventBus.show_reminder_bubble.emit(r.get("msg", "⏰ 时间到了！"))
			# 一次性提醒：触发后标记删除
			if r.get("once", false):
				to_remove.append(i)
	
	# 从后往前删除，避免索引错位
	if to_remove.size() > 0:
		to_remove.reverse()
		for idx in to_remove:
			reminders.remove_at(idx)
		SettingsManager.save_reminders(reminders)
		# 面板打开时刷新列表
		if panel.visible:
			_refresh_list()

# ── UI 构建 ──

func _build_ui() -> void:
	layer = 101
	
	panel = PanelContainer.new()
	panel.visible = false
	panel.custom_minimum_size = Vector2(340, 0)
	
	# 面板背景: 深色毛玻璃 + 金色边框 + 大圆角
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.10, 0.95)
	style.border_color = Color(1.0, 0.85, 0.3, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(1.0, 0.85, 0.3, 0.1)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	
	# ── 标题 ──
	var title = Label.new()
	title.text = "⏰ 提醒管理"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)
	
	# 分割线
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	sep.add_theme_color_override("separator_color", Color(1, 0.85, 0.3, 0.2))
	vbox.add_child(sep)
	
	# ── 提醒列表 ──
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240) # 限定最大展示高度
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)
	
	# ── 输入区 ──
	var input_sep = HSeparator.new()
	input_sep.add_theme_constant_override("separation", 4)
	input_sep.add_theme_color_override("separator_color", Color(1, 0.85, 0.3, 0.15))
	vbox.add_child(input_sep)
	
	var add_row = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	add_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(add_row)
	
	# 时间选择器 — 小时 SpinBox + 冒号 + 分钟 SpinBox
	hour_spin = _make_time_spinbox(0, 23, 9)
	add_row.add_child(hour_spin)
	
	var colon_label = Label.new()
	colon_label.text = ":"
	colon_label.add_theme_font_size_override("font_size", 20)
	colon_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 0.9))
	add_row.add_child(colon_label)
	
	minute_spin = _make_time_spinbox(0, 59, 0)
	add_row.add_child(minute_spin)
	
	# 消息输入
	msg_input = _make_input("该休息了...", 0, 0)
	msg_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(msg_input)
	
	# 一次性/每日 切换按钮 (纯文字药丸形)
	once_btn = Button.new()
	once_btn.text = "单次" if _add_once else "每日"
	once_btn.tooltip_text = "极简文字切换"
	once_btn.add_theme_font_size_override("font_size", 14)
	once_btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1, 1))
	once_btn.custom_minimum_size = Vector2(46, 32)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.25, 0.4, 0.8)
	btn_style.border_color = Color(0.3, 0.5, 0.7, 0.8)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(6)
	once_btn.add_theme_stylebox_override("normal", btn_style)
	
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.2, 0.35, 0.55, 0.9)
	btn_hover.border_color = Color(0.4, 0.7, 0.9, 1.0)
	once_btn.add_theme_stylebox_override("hover", btn_hover)
	once_btn.add_theme_stylebox_override("pressed", btn_hover)
	once_btn.pressed.connect(_on_once_toggled)
	add_row.add_child(once_btn)
	
	# 添加按钮 (醒目提亮)
	var add_btn = Button.new()
	add_btn.text = "添加"
	add_btn.add_theme_font_size_override("font_size", 14)
	
	# 强制锁定所有状态下的文字颜色为深绿/黑色，防止悬停时变成默认白色导致看不清
	var dark_green = Color(0.05, 0.15, 0.05, 1)
	add_btn.add_theme_color_override("font_color", dark_green)
	add_btn.add_theme_color_override("font_hover_color", dark_green)
	add_btn.add_theme_color_override("font_pressed_color", dark_green)
	add_btn.add_theme_color_override("font_focus_color", dark_green)
	add_btn.custom_minimum_size = Vector2(46, 32)
	
	var add_style = StyleBoxFlat.new()
	add_style.bg_color = Color(0.4, 0.9, 0.6, 0.9)
	add_style.set_corner_radius_all(6)
	add_btn.add_theme_stylebox_override("normal", add_style)
	
	var add_hover = add_style.duplicate()
	add_hover.bg_color = Color(0.5, 1.0, 0.7, 1.0)
	add_btn.add_theme_stylebox_override("hover", add_hover)
	add_btn.add_theme_stylebox_override("pressed", add_hover)
	add_btn.pressed.connect(_on_add_pressed)
	add_row.add_child(add_btn)
	
	_refresh_list()

func _make_time_spinbox(min_val: int, max_val: int, default_val: int) -> SpinBox:
	var spin = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = default_val
	spin.step = 1
	spin.custom_minimum_size = Vector2(72, 0)
	spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.add_theme_font_size_override("font_size", 17)
	# SpinBox 内嵌 LineEdit 的样式
	var line = spin.get_line_edit()
	line.add_theme_font_size_override("font_size", 17)
	line.add_theme_color_override("font_color", Color(0.9, 0.95, 1, 1))
	line.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 内嵌输入框的深色背景
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.06, 0.1, 0.2, 0.8)
	input_style.border_color = Color(0.15, 0.3, 0.5, 0.5)
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(8)
	input_style.content_margin_left = 6
	input_style.content_margin_right = 6
	input_style.content_margin_top = 6
	input_style.content_margin_bottom = 6
	line.add_theme_stylebox_override("normal", input_style)
	var focus_style = input_style.duplicate()
	focus_style.border_color = Color(1, 0.85, 0.3, 0.6)
	line.add_theme_stylebox_override("focus", focus_style)
	# SpinBox 上下箭头区域样式 (使其与面板风格统一)
	var up_style = StyleBoxFlat.new()
	up_style.bg_color = Color(0.08, 0.12, 0.25, 0.8)
	up_style.set_corner_radius_all(4)
	spin.add_theme_stylebox_override("up_background", up_style)
	spin.add_theme_stylebox_override("down_background", up_style)
	var up_hover = up_style.duplicate()
	up_hover.bg_color = Color(0.12, 0.2, 0.4, 0.9)
	spin.add_theme_stylebox_override("up_background_hovered", up_hover)
	spin.add_theme_stylebox_override("down_background_hovered", up_hover)
	var up_pressed = up_style.duplicate()
	up_pressed.bg_color = Color(0.15, 0.25, 0.5, 1.0)
	spin.add_theme_stylebox_override("up_background_pressed", up_pressed)
	spin.add_theme_stylebox_override("down_background_pressed", up_pressed)
	return spin

func _make_input(placeholder: String, min_width: int, max_len: int) -> LineEdit:
	var input = LineEdit.new()
	input.placeholder_text = placeholder
	if min_width > 0:
		input.custom_minimum_size = Vector2(min_width, 0)
	if max_len > 0:
		input.max_length = max_len
	input.add_theme_font_size_override("font_size", 17)
	input.add_theme_color_override("font_color", Color(0.9, 0.95, 1, 1))
	input.add_theme_color_override("font_placeholder_color", Color(0.35, 0.45, 0.55, 0.8))
	# 输入框背景
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.06, 0.1, 0.2, 0.8)
	input_style.border_color = Color(0.15, 0.3, 0.5, 0.5)
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(8)
	input_style.content_margin_left = 10
	input_style.content_margin_right = 10
	input_style.content_margin_top = 6
	input_style.content_margin_bottom = 6
	input.add_theme_stylebox_override("normal", input_style)
	# 聚焦样式
	var focus_style = input_style.duplicate()
	focus_style.border_color = Color(1, 0.85, 0.3, 0.6)
	input.add_theme_stylebox_override("focus", focus_style)
	return input

# ── 列表刷新 ──

func _refresh_list() -> void:
	for child in list_box.get_children():
		child.queue_free()
	
	var reminders = SettingsManager.get_reminders()
	if reminders.is_empty():
		var empty_label = Label.new()
		empty_label.text = "还没有提醒哦~"
		empty_label.add_theme_font_size_override("font_size", 15)
		empty_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.7))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_box.add_child(empty_label)
		return
	
	for i in range(reminders.size()):
		var r = reminders[i]
		var is_on: bool = r.get("on", true)
		var is_once: bool = r.get("once", false)
		
		# 每条提醒的卡片容器
		var card = PanelContainer.new()
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.05, 0.08, 0.16, 0.6) if is_on else Color(0.04, 0.06, 0.12, 0.3)
		card_style.set_corner_radius_all(10)
		card_style.content_margin_left = 12
		card_style.content_margin_right = 8
		card_style.content_margin_top = 8
		card_style.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", card_style)
		
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		
		# 开关指示灯
		var toggle = Button.new()
		toggle.text = "●" if is_on else "○"
		toggle.add_theme_font_size_override("font_size", 14)
		toggle.add_theme_color_override("font_color", Color(0.3, 1, 0.7, 1) if is_on else Color(0.4, 0.4, 0.5, 0.6))
		toggle.add_theme_color_override("font_hover_color", Color(0.5, 1, 0.85, 1))
		toggle.flat = true
		toggle.custom_minimum_size = Vector2(24, 0)
		var idx_t = i
		toggle.pressed.connect(func(): _toggle_reminder(idx_t))
		row.add_child(toggle)
		
		# 时间标签 — 高亮显示
		var time_label = Label.new()
		time_label.text = r.get("time", "??:??")
		time_label.add_theme_font_size_override("font_size", 17)
		time_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1) if is_on else Color(0.5, 0.45, 0.3, 0.5))
		time_label.custom_minimum_size = Vector2(52, 0)
		row.add_child(time_label)
		
		# 消息文本
		var msg_label = Label.new()
		msg_label.text = r.get("msg", "")
		msg_label.add_theme_font_size_override("font_size", 16)
		msg_label.add_theme_color_override("font_color", Color(0.8, 0.88, 0.95, 1) if is_on else Color(0.4, 0.42, 0.45, 0.5))
		msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		msg_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(msg_label)
		
		# 类型标签: 纯文字标牌
		var type_label = Label.new()
		type_label.text = "单次" if is_once else "每日"
		type_label.add_theme_font_size_override("font_size", 12)
		type_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.9) if is_on else Color(0.6, 0.6, 0.6, 0.6))
		
		# 给标签加上底色板
		var t_style = StyleBoxFlat.new()
		t_style.bg_color = Color(0.7, 0.4, 0.2, 0.8) if is_once else Color(0.2, 0.4, 0.7, 0.8)
		if not is_on:
			t_style.bg_color = Color(0.3, 0.3, 0.3, 0.5)
		t_style.set_corner_radius_all(4)
		t_style.content_margin_left = 6
		t_style.content_margin_right = 6
		t_style.content_margin_top = 2
		t_style.content_margin_bottom = 2
		type_label.add_theme_stylebox_override("normal", t_style)
		
		var t_center = CenterContainer.new()
		t_center.add_child(type_label)
		row.add_child(t_center)
		
		# 删除按钮 (红色系药丸设计)
		var del_btn = Button.new()
		del_btn.text = "删除"
		del_btn.add_theme_font_size_override("font_size", 12)
		del_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.8, 0.8) if is_on else Color(0.6, 0.4, 0.4, 0.6))
		del_btn.add_theme_color_override("font_hover_color", Color(1, 0.9, 0.9, 1))
		del_btn.custom_minimum_size = Vector2(40, 24)
		
		var d_style = StyleBoxFlat.new()
		d_style.bg_color = Color(0.6, 0.15, 0.2, 0.5) if is_on else Color(0.3, 0.1, 0.15, 0.3)
		d_style.border_color = Color(0.8, 0.3, 0.3, 0.3)
		d_style.set_border_width_all(1)
		d_style.set_corner_radius_all(6)
		del_btn.add_theme_stylebox_override("normal", d_style)
		
		var d_hover = d_style.duplicate()
		d_hover.bg_color = Color(0.8, 0.2, 0.3, 0.8)
		d_hover.border_color = Color(1.0, 0.4, 0.4, 0.6)
		del_btn.add_theme_stylebox_override("hover", d_hover)
		del_btn.add_theme_stylebox_override("pressed", d_hover)
		
		var idx_d = i
		del_btn.pressed.connect(func(): _delete_reminder(idx_d))
		
		var d_center = CenterContainer.new()
		d_center.add_child(del_btn)
		row.add_child(d_center)
		
		list_box.add_child(card)

# ── 操作 ──

func _on_once_toggled() -> void:
	_add_once = not _add_once
	if _add_once:
		once_btn.text = "单次"
		once_btn.tooltip_text = "时间到了后自动删除"
	else:
		once_btn.text = "每日"
		once_btn.tooltip_text = "每天这个时间都会触发"

func _on_add_pressed() -> void:
	var t = "%02d:%02d" % [int(hour_spin.value), int(minute_spin.value)]
	var m = msg_input.text.strip_edges()
	if m.is_empty():
		m = "⏰ 时间到了！"
	var reminders = SettingsManager.get_reminders()
	reminders.append({"time": t, "msg": m, "on": true, "once": _add_once})
	SettingsManager.save_reminders(reminders)
	msg_input.text = ""
	_refresh_list()


func _toggle_reminder(idx: int) -> void:
	var reminders = SettingsManager.get_reminders()
	if idx < reminders.size():
		reminders[idx]["on"] = not reminders[idx].get("on", true)
		SettingsManager.save_reminders(reminders)
		_refresh_list()

func _delete_reminder(idx: int) -> void:
	var reminders = SettingsManager.get_reminders()
	if idx < reminders.size():
		reminders.remove_at(idx)
		SettingsManager.save_reminders(reminders)
		_refresh_list()

# ── 面板显隐 ──

func _toggle_panel() -> void:
	if panel.visible:
		_close_panel()
	else:
		_open_panel()

func _open_panel() -> void:
	_refresh_list()
	EventBus.context_menu_toggled.emit(true)
	if is_instance_valid(_pet):
		var pet_pos = _pet.get_global_transform_with_canvas().get_origin()
		panel.position = pet_pos + Vector2(-170, -250)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.6, 0.6)
	panel.show()
	await get_tree().process_frame
	panel.pivot_offset = panel.size / 2.0
	_guard_frames = 5
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	await get_tree().process_frame
	await get_tree().process_frame
	hour_spin.get_line_edit().grab_focus()

func _close_panel() -> void:
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
		var local_mouse = panel.get_local_mouse_position()
		var rect = Rect2(Vector2.ZERO, panel.size)
		if not rect.has_point(local_mouse):
			_close_panel()

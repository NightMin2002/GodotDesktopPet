# reminder_panel.gd — 提醒管理面板
# 跟随宠物上方弹出，提供提醒增删 + 定时触发逻辑
extends CanvasLayer

var panel: PanelContainer
var list_box: VBoxContainer
var time_input: LineEdit
var msg_input: LineEdit

var _check_timer := 0.0
var _fired_keys: Dictionary = {}  # 今日已触发的提醒 key
var _pet: Node2D                  # 宠物引用，用于位置跟随
var _guard_frames := 0            # 防止打开瞬间被误关的帧计数

func _ready() -> void:
	_build_ui()
	EventBus.show_reminder_panel.connect(_toggle_panel)
	# 延迟一帧搜索宠物节点
	_find_pet.call_deferred()

func _find_pet() -> void:
	var main = get_tree().root.get_node_or_null("Main")
	if main:
		for child in main.get_children():
			if child is RigidBody2D:
				_pet = child
				return

func _process(delta: float) -> void:
	# 弹性追踪宠物上方
	if panel.visible and is_instance_valid(_pet):
		var pet_pos = _pet.get_global_transform_with_canvas().get_origin()
		var target_pos = pet_pos + Vector2(-panel.size.x / 2, -panel.size.y - 50)
		target_pos = _clamp_pos(target_pos)
		panel.position = panel.position.lerp(target_pos, delta * 10.0)
	
	# 防误关帧计数
	if _guard_frames > 0:
		_guard_frames -= 1
	
	# 每 10 秒检查一次提醒
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
	for r in reminders:
		if not r.get("on", true):
			continue
		var key = r.get("time", "") + "|" + r.get("msg", "")
		if r.get("time", "") == now_str and not _fired_keys.has(key):
			_fired_keys[key] = true
			EventBus.show_reminder_bubble.emit(r.get("msg", "⏰ 时间到了！"))

# ── UI 构建 ──

func _build_ui() -> void:
	layer = 101
	
	panel = PanelContainer.new()
	panel.visible = false
	panel.custom_minimum_size = Vector2(300, 40)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.14, 0.92)
	style.border_color = Color(1.0, 0.85, 0.3, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = "⏰ 提醒管理"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	
	var sep = HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(1, 0.85, 0.3, 0.3))
	vbox.add_child(sep)
	
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 4)
	vbox.add_child(list_box)
	
	# 输入行：[时间] [消息] [+]
	var add_row = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	vbox.add_child(add_row)
	
	time_input = LineEdit.new()
	time_input.placeholder_text = "09:00"
	time_input.custom_minimum_size = Vector2(56, 0)
	time_input.max_length = 5
	time_input.add_theme_font_size_override("font_size", 13)
	time_input.add_theme_color_override("font_color", Color(0.9, 0.95, 1, 1))
	time_input.add_theme_color_override("font_placeholder_color", Color(0.4, 0.5, 0.6, 1))
	add_row.add_child(time_input)
	
	msg_input = LineEdit.new()
	msg_input.placeholder_text = "该休息了..."
	msg_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_input.add_theme_font_size_override("font_size", 13)
	msg_input.add_theme_color_override("font_color", Color(0.9, 0.95, 1, 1))
	msg_input.add_theme_color_override("font_placeholder_color", Color(0.4, 0.5, 0.6, 1))
	add_row.add_child(msg_input)
	
	var add_btn = Button.new()
	add_btn.text = "+"
	add_btn.add_theme_font_size_override("font_size", 16)
	add_btn.add_theme_color_override("font_color", Color(0.3, 1, 0.7, 1))
	add_btn.add_theme_color_override("font_hover_color", Color(0.5, 1, 0.9, 1))
	add_btn.pressed.connect(_on_add_pressed)
	add_row.add_child(add_btn)
	
	# 快速测试按钮
	var test_btn = Button.new()
	test_btn.text = "⚡ 测试触发"
	test_btn.add_theme_font_size_override("font_size", 12)
	test_btn.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 1))
	test_btn.add_theme_color_override("font_hover_color", Color(0.8, 0.9, 1, 1))
	test_btn.flat = true
	test_btn.pressed.connect(_on_test_pressed)
	vbox.add_child(test_btn)
	
	_refresh_list()

# ── 列表刷新 ──

func _refresh_list() -> void:
	for child in list_box.get_children():
		child.queue_free()
	
	var reminders = SettingsManager.get_reminders()
	for i in range(reminders.size()):
		var r = reminders[i]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		
		var is_on: bool = r.get("on", true)
		var toggle = Button.new()
		toggle.text = "●" if is_on else "○"
		toggle.add_theme_font_size_override("font_size", 12)
		toggle.add_theme_color_override("font_color", Color(0.3, 1, 0.7, 1) if is_on else Color(0.5, 0.5, 0.5, 1))
		toggle.flat = true
		var idx_t = i
		toggle.pressed.connect(func(): _toggle_reminder(idx_t))
		row.add_child(toggle)
		
		var label = Label.new()
		label.text = "%s  %s" % [r.get("time", "??:??"), r.get("msg", "")]
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1) if is_on else Color(0.4, 0.4, 0.4, 1))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		
		var del_btn = Button.new()
		del_btn.text = "✕"
		del_btn.add_theme_font_size_override("font_size", 12)
		del_btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4, 1))
		del_btn.add_theme_color_override("font_hover_color", Color(1, 0.6, 0.6, 1))
		del_btn.flat = true
		var idx_d = i
		del_btn.pressed.connect(func(): _delete_reminder(idx_d))
		row.add_child(del_btn)
		
		list_box.add_child(row)

# ── 操作 ──

func _on_add_pressed() -> void:
	var t = time_input.text.strip_edges()
	var m = msg_input.text.strip_edges()
	if t.length() < 3 or not ":" in t:
		return
	if m.is_empty():
		m = "⏰ 时间到了！"
	var reminders = SettingsManager.get_reminders()
	reminders.append({"time": t, "msg": m, "on": true})
	SettingsManager.save_reminders(reminders)
	time_input.text = ""
	msg_input.text = ""
	_refresh_list()

func _on_test_pressed() -> void:
	var reminders = SettingsManager.get_reminders()
	if reminders.size() > 0:
		var last = reminders[reminders.size() - 1]
		EventBus.show_reminder_bubble.emit(last.get("msg", "⏰ 测试！"))
	else:
		EventBus.show_reminder_bubble.emit("⏰ 这是一条测试提醒！")

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
	# 开启全屏穿透接管（否则点击会穿过窗口）
	EventBus.context_menu_toggled.emit(true)
	# 初始位置
	if is_instance_valid(_pet):
		var pet_pos = _pet.get_global_transform_with_canvas().get_origin()
		panel.position = pet_pos + Vector2(-150, -200)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.6, 0.6)
	panel.show()
	# 等一帧让布局计算出 size，再设缩放锚点到面板中心
	await get_tree().process_frame
	panel.pivot_offset = panel.size / 2.0
	_guard_frames = 5  # 前 5 帧不响应外部点击关闭
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	# 延迟 2 帧后聚焦输入框（等待布局完成）
	await get_tree().process_frame
	await get_tree().process_frame
	time_input.grab_focus()

func _close_panel() -> void:
	# 缩放锚点居中 + 穿透恢复延迟到动画结束
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

# reminder_panel.gd — 提醒管理面板
# 跟随宠物上方弹出，提供提醒增删 + 定时触发逻辑
# 支持每日重复和一次性两种模式
extends CanvasLayer

var panel: PanelContainer
var list_box: VBoxContainer
var scroll: ScrollContainer
var msg_input: LineEdit
var once_btn: Button        # 一次性/每日 切换按钮

var _add_once := false       # 当前添加模式: false=每日重复, true=一次性
var _check_timer := 0.0
var _fired_keys: Dictionary = {}
var _pet: Node2D
var _guard_frames := 0

# ── 主题色同步引用 ──
var _title_label: Label
var _panel_style: StyleBoxFlat
var _sep_list: Array = []          # HSeparator 引用
var _roller_adjacent: Dictionary = {}  # meta_key → {highlight, step}

func _ready() -> void:
	_build_ui()
	EventBus.show_reminder_panel.connect(_toggle_panel)
	EventBus.ui_theme_changed.connect(_apply_ui_theme)
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
			# 记为待确认提醒 (用户戳宠物时再次传达)
			if is_instance_valid(_pet) and _pet.has_method("handle_poke"):
				_pet.poke_system.pending_reminders.append({"time": r.get("time", ""), "msg": r.get("msg", "⏰ 时间到了！")})
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
	
	# 面板背景: 深色毛玻璃 + 主题色边框 + 大圆角
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.02, 0.04, 0.10, 0.95)
	_panel_style.border_color = Color.from_hsv(EventBus.ui_hue, 0.7, 1.0, 0.5)
	_panel_style.set_border_width_all(2)
	_panel_style.set_corner_radius_all(16)
	_panel_style.shadow_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.1)
	_panel_style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", _panel_style)
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
	_title_label = Label.new()
	_title_label.text = "提醒管理"
	_title_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 1.0))
	_title_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_title_label)
	
	# 分割线
	var sep = _make_sep()
	vbox.add_child(sep)
	
	# ── 提醒列表 (自适应高度，最大 240px) ──
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 60)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)
	
	# ── 输入区 ──
	var input_sep = _make_sep()
	vbox.add_child(input_sep)
	
	# ── 第一行：时间选择器 + 模式切换 ──
	var time_row = HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 4)
	time_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(time_row)
	
	# 构建拨轮时间选择器: 小时 step=1, 分钟 step=5
	var hour_col = _build_roller(0, 23, 9, "_hour_val", 1)
	time_row.add_child(hour_col)
	
	var colon_label = Label.new()
	colon_label.text = ":"
	colon_label.add_theme_font_size_override("font_size", 22)
	colon_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 0.8))
	time_row.add_child(colon_label)
	
	var minute_col = _build_roller(0, 55, 0, "_minute_val", 5)
	time_row.add_child(minute_col)
	
	# 间距弹簧
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(spacer)
	
	# 一次性/每日 切换按钮 (胶囊式双态)
	once_btn = Button.new()
	once_btn.text = "1x单次" if _add_once else "↻ 每日"
	once_btn.add_theme_font_size_override("font_size", 15)
	once_btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1, 1))
	once_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	once_btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	once_btn.custom_minimum_size = Vector2(72, 36)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.22, 0.38, 0.9)
	btn_style.border_color = Color(0.3, 0.55, 0.8, 0.7)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(18)
	once_btn.add_theme_stylebox_override("normal", btn_style)
	
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.18, 0.32, 0.5, 1.0)
	btn_hover.border_color = Color(0.4, 0.7, 0.95, 1.0)
	once_btn.add_theme_stylebox_override("hover", btn_hover)
	once_btn.add_theme_stylebox_override("pressed", btn_hover)
	once_btn.pressed.connect(_on_once_toggled)
	var once_center = CenterContainer.new()
	once_center.add_child(once_btn)
	time_row.add_child(once_center)
	
	# ── 第二行：消息输入 + 添加按钮 ──
	var msg_row = HBoxContainer.new()
	msg_row.add_theme_constant_override("separation", 8)
	vbox.add_child(msg_row)
	
	# 消息输入
	msg_input = _make_input("输入提醒内容...", 0, 0)
	msg_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_input.text_submitted.connect(func(_t): _on_add_pressed())
	msg_row.add_child(msg_input)
	
	# 添加按钮
	var add_btn = Button.new()
	add_btn.text = "+ 添加"
	add_btn.add_theme_font_size_override("font_size", 15)
	
	var add_fg = Color(0.95, 1.0, 0.95, 1.0)
	add_btn.add_theme_color_override("font_color", add_fg)
	add_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	add_btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	add_btn.add_theme_color_override("font_focus_color", add_fg)
	add_btn.custom_minimum_size = Vector2(72, 36)
	
	var add_style = StyleBoxFlat.new()
	add_style.bg_color = Color(0.18, 0.55, 0.35, 0.85)
	add_style.border_color = Color(0.3, 0.7, 0.5, 0.5)
	add_style.set_border_width_all(1)
	add_style.set_corner_radius_all(18)
	add_btn.add_theme_stylebox_override("normal", add_style)
	
	var add_hover = add_style.duplicate()
	add_hover.bg_color = Color(0.22, 0.65, 0.42, 1.0)
	add_hover.border_color = Color(0.4, 0.85, 0.6, 0.8)
	add_btn.add_theme_stylebox_override("hover", add_hover)
	add_btn.add_theme_stylebox_override("pressed", add_hover)
	add_btn.pressed.connect(_on_add_pressed)
	add_btn.flat = false
	msg_row.add_child(add_btn)
	
	_refresh_list()

# ── 自定义拨轮时间选择器 ──

var _hour_val: int = 9
var _minute_val: int = 0
var _roller_labels: Dictionary = {}  # meta_key → current Label
var _drag_meta: String = ""          # 当前正在拖拽的拨轮 meta_key
var _drag_start_y: float = 0.0
var _drag_accum: float = 0.0

func _build_roller(min_val: int, max_val: int, default_val: int, meta_key: String, step: int = 1) -> VBoxContainer:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# ▲ 递增按钮
	var up_btn = Button.new()
	up_btn.text = "▲"
	up_btn.add_theme_font_size_override("font_size", 10)
	up_btn.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.6))
	up_btn.add_theme_color_override("font_hover_color", Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 1.0))
	up_btn.add_theme_color_override("font_pressed_color", Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 1.0))
	up_btn.custom_minimum_size = Vector2(52, 18)
	_style_roller_btn(up_btn)
	var st = step
	up_btn.pressed.connect(func(): _adjust_roller(meta_key, st, min_val, max_val))
	col.add_child(up_btn)
	
	# ── 数字显示区域 (带底板 + 滚轮/拖拽) ──
	var drum = PanelContainer.new()
	var drum_style = StyleBoxFlat.new()
	drum_style.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.2, 0.5)
	drum_style.border_color = Color(0.12, 0.25, 0.45, 0.4)
	drum_style.set_border_width_all(1)
	drum_style.set_corner_radius_all(8)
	drum_style.content_margin_left = 4
	drum_style.content_margin_right = 4
	drum_style.content_margin_top = 3
	drum_style.content_margin_bottom = 3
	drum.add_theme_stylebox_override("panel", drum_style)
	drum.custom_minimum_size = Vector2(52, 36)
	drum.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var current_label = Label.new()
	current_label.text = "%02d" % default_val
	current_label.add_theme_font_size_override("font_size", 24)
	current_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	current_label.add_theme_color_override("font_outline_color", Color(0.1, 0.2, 0.4, 0.4))
	current_label.add_theme_constant_override("outline_size", 2)
	current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_label.custom_minimum_size = Vector2(44, 28)
	current_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drum.add_child(current_label)
	
	col.add_child(drum)
	
	# 鼠标滚轮 + 拖拽支持
	var mk = meta_key
	var mn = min_val
	var mx = max_val
	drum.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_adjust_roller(mk, st, mn, mx)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_adjust_roller(mk, -st, mn, mx)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_drag_meta = mk
					_drag_start_y = event.position.y
					_drag_accum = 0.0
				else:
					_drag_meta = ""
		elif event is InputEventMouseMotion and _drag_meta == mk:
			_drag_accum += _drag_start_y - event.position.y
			_drag_start_y = event.position.y
			while _drag_accum > 18.0:
				_adjust_roller(mk, st, mn, mx)
				_drag_accum -= 18.0
			while _drag_accum < -18.0:
				_adjust_roller(mk, -st, mn, mx)
				_drag_accum += 18.0
	)
	
	# ▼ 递减按钮
	var down_btn = Button.new()
	down_btn.text = "▼"
	down_btn.add_theme_font_size_override("font_size", 10)
	down_btn.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.6))
	down_btn.add_theme_color_override("font_hover_color", Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 1.0))
	down_btn.add_theme_color_override("font_pressed_color", Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 1.0))
	down_btn.custom_minimum_size = Vector2(52, 18)
	_style_roller_btn(down_btn)
	down_btn.pressed.connect(func(): _adjust_roller(meta_key, -st, min_val, max_val))
	col.add_child(down_btn)
	
	# 保存引用
	set(meta_key, default_val)
	_roller_labels[meta_key] = current_label
	_roller_adjacent[meta_key] = {"highlight": drum, "step": step}
	return col

func _style_roller_btn(btn: Button) -> void:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.08, 0.18, 0.6)
	s.border_color = Color(0.15, 0.28, 0.45, 0.3)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(0.08, 0.15, 0.3, 0.9)
	h.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 0.5)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)

func _adjust_roller(meta_key: String, delta: int, min_val: int, max_val: int) -> void:
	var val: int = get(meta_key)
	val += delta
	if val > max_val: val = min_val
	if val < min_val: val = max_val
	set(meta_key, val)
	if _roller_labels.has(meta_key):
		var label: Label = _roller_labels[meta_key]
		label.text = "%02d" % val
		# 底板弹跳动画 (居中 pivot)
		if _roller_adjacent.has(meta_key):
			var hl = _roller_adjacent[meta_key]["highlight"]
			hl.pivot_offset = hl.size / 2.0
			var tw = create_tween()
			tw.tween_property(hl, "scale", Vector2(1.06, 1.06), 0.05)
			tw.tween_property(hl, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_BACK)

func _wrap_val(val: int, min_val: int, max_val: int) -> int:
	if val > max_val: return min_val
	if val < min_val: return max_val
	return val

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
	focus_style.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 0.6)
	input.add_theme_stylebox_override("focus", focus_style)
	return input

# ── 列表刷新 ──

func _refresh_list() -> void:
	for child in list_box.get_children():
		child.queue_free()
	
	var reminders = SettingsManager.get_reminders()
	
	# 自适应高度: 根据内容数量调整，最大 240px
	var desired_h = reminders.size() * 50 + 10 if reminders.size() > 0 else 60
	scroll.custom_minimum_size.y = clampf(desired_h, 50, 240)
	
	if reminders.is_empty():
		var empty_label = Label.new()
		empty_label.text = "还没有提醒哦~"
		empty_label.add_theme_font_size_override("font_size", 15)
		empty_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.7))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_box.add_child(empty_label)
		panel.reset_size.call_deferred()
		return
	
	for i in range(reminders.size()):
		var r = reminders[i]
		var is_on: bool = r.get("on", true)
		var is_once: bool = r.get("once", false)
		
		# 每条提醒的卡片容器 (hover 效果)
		var card = PanelContainer.new()
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.05, 0.08, 0.16, 0.6) if is_on else Color(0.04, 0.06, 0.12, 0.3)
		card_style.border_color = Color(0.12, 0.2, 0.35, 0.2)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(10)
		card_style.content_margin_left = 12
		card_style.content_margin_right = 8
		card_style.content_margin_top = 8
		card_style.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", card_style)
		# 卡片 hover 效果
		var cs_ref = card_style
		card.mouse_entered.connect(func():
			var hs = cs_ref.duplicate()
			hs.bg_color = Color(0.07, 0.12, 0.22, 0.8) if is_on else Color(0.06, 0.09, 0.16, 0.5)
			hs.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.3)
			card.add_theme_stylebox_override("panel", hs)
		)
		card.mouse_exited.connect(func():
			card.add_theme_stylebox_override("panel", cs_ref)
		)
		
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		
		# 开关指示灯 (带底板)
		var toggle = Button.new()
		toggle.text = "●" if is_on else "○"
		toggle.add_theme_font_size_override("font_size", 14)
		toggle.add_theme_color_override("font_color", Color(0.3, 1, 0.7, 1) if is_on else Color(0.4, 0.4, 0.5, 0.6))
		toggle.add_theme_color_override("font_hover_color", Color(0.5, 1, 0.85, 1))
		toggle.custom_minimum_size = Vector2(28, 28)
		var tg_style = StyleBoxFlat.new()
		tg_style.bg_color = Color(0.08, 0.14, 0.25, 0.5)
		tg_style.set_corner_radius_all(14)
		toggle.add_theme_stylebox_override("normal", tg_style)
		var tg_hover = tg_style.duplicate()
		tg_hover.bg_color = Color(0.12, 0.2, 0.35, 0.8)
		toggle.add_theme_stylebox_override("hover", tg_hover)
		toggle.add_theme_stylebox_override("pressed", tg_hover)
		toggle.flat = false
		var idx_t = i
		toggle.pressed.connect(func(): _toggle_reminder(idx_t))
		row.add_child(toggle)
		
		# 时间标签 — 主题色高亮
		var time_label = Label.new()
		time_label.text = r.get("time", "??:??")
		time_label.add_theme_font_size_override("font_size", 17)
		time_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 1.0) if is_on else Color(0.4, 0.4, 0.45, 0.5))
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
		
		# 类型标签: 跟随主题色体系
		var type_label = Label.new()
		type_label.text = "单次" if is_once else "每日"
		type_label.add_theme_font_size_override("font_size", 12)
		type_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 0.9) if is_on else Color(0.6, 0.6, 0.6, 0.5))
		
		var t_style = StyleBoxFlat.new()
		if not is_on:
			t_style.bg_color = Color(0.25, 0.25, 0.3, 0.4)
		elif is_once:
			# 单次: 暖色调 (偏橙)
			t_style.bg_color = Color.from_hsv(fmod(EventBus.ui_hue + 0.12, 1.0), 0.55, 0.55, 0.8)
		else:
			# 每日: 主题色
			t_style.bg_color = Color.from_hsv(EventBus.ui_hue, 0.55, 0.45, 0.8)
		t_style.set_corner_radius_all(4)
		t_style.content_margin_left = 6
		t_style.content_margin_right = 6
		t_style.content_margin_top = 2
		t_style.content_margin_bottom = 2
		type_label.add_theme_stylebox_override("normal", t_style)
		
		var t_center = CenterContainer.new()
		t_center.add_child(type_label)
		row.add_child(t_center)
		
		# 删除按钮
		var del_btn = Button.new()
		del_btn.text = "删除"
		del_btn.add_theme_font_size_override("font_size", 12)
		del_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.8, 0.8) if is_on else Color(0.6, 0.4, 0.4, 0.6))
		del_btn.add_theme_color_override("font_hover_color", Color(1, 0.9, 0.9, 1))
		del_btn.custom_minimum_size = Vector2(40, 24)
		
		var d_style = StyleBoxFlat.new()
		d_style.bg_color = Color(0.5, 0.12, 0.15, 0.45) if is_on else Color(0.3, 0.1, 0.15, 0.3)
		d_style.border_color = Color(0.7, 0.25, 0.25, 0.3)
		d_style.set_border_width_all(1)
		d_style.set_corner_radius_all(6)
		del_btn.add_theme_stylebox_override("normal", d_style)
		
		var d_hover = d_style.duplicate()
		d_hover.bg_color = Color(0.7, 0.18, 0.22, 0.8)
		d_hover.border_color = Color(1.0, 0.4, 0.4, 0.6)
		del_btn.add_theme_stylebox_override("hover", d_hover)
		del_btn.add_theme_stylebox_override("pressed", d_hover)
		del_btn.flat = false
		
		var idx_d = i
		var card_ref = card
		del_btn.pressed.connect(func(): _delete_reminder_animated(idx_d, card_ref))
		
		var d_center = CenterContainer.new()
		d_center.add_child(del_btn)
		row.add_child(d_center)
		
		list_box.add_child(card)
	
	# 延迟重置面板尺寸，让布局收缩到实际内容大小
	panel.reset_size.call_deferred()

# ── 操作 ──

func _on_once_toggled() -> void:
	_add_once = not _add_once
	once_btn.text = "1x单次" if _add_once else "↻ 每日"

func _on_add_pressed() -> void:
	var t = "%02d:%02d" % [_hour_val, _minute_val]
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

## 带淡出动画的删除
func _delete_reminder_animated(idx: int, card: PanelContainer) -> void:
	card.pivot_offset = card.size / 2.0
	var tw = create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 0.0, 0.15)
	tw.tween_property(card, "scale", Vector2(0.8, 0.8), 0.15)
	tw.finished.connect(func(): _delete_reminder(idx))

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
	msg_input.grab_focus()

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
			get_viewport().set_input_as_handled()

# ── 工具 ──

func _make_sep() -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sep_list.append(sep)
	return sep

# ── 主题色同步 ──

## 运行时 UI 主题色变更: 更新面板边框/标题/分隔线/时间高亮条
func _apply_ui_theme(hue: float) -> void:
	# 面板边框
	if _panel_style:
		_panel_style = _panel_style.duplicate()
		_panel_style.border_color = Color.from_hsv(hue, 0.7, 1.0, 0.5)
		_panel_style.shadow_color = Color.from_hsv(hue, 0.5, 0.8, 0.1)
		panel.add_theme_stylebox_override("panel", _panel_style)
	# 标题色
	if _title_label:
		_title_label.add_theme_color_override("font_color", Color.from_hsv(hue, 0.6, 1.0, 1.0))
	# 分隔线
	for sep in _sep_list:
		if is_instance_valid(sep):
			var s = StyleBoxFlat.new()
			s.bg_color = Color.from_hsv(hue, 0.6, 0.8, 0.15)
			s.set_content_margin_all(0)
			sep.add_theme_stylebox_override("separator", s)
	# 滚筒高亮条
	for key in _roller_adjacent:
		var adj = _roller_adjacent[key]
		if adj.has("highlight") and is_instance_valid(adj["highlight"]):
			var hs = adj["highlight"].get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			hs.bg_color = Color.from_hsv(hue, 0.4, 0.25, 0.5)
			adj["highlight"].add_theme_stylebox_override("panel", hs)
	# 刷新列表 (卡片中时间标签颜色跟随主题)
	if panel.visible:
		_refresh_list()

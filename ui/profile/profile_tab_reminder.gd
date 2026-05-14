# profile_tab_reminder.gd — 定时提醒 Tab (装置终端 Tab 2)
# 科幻机能风提醒列表 + 拨轮时间选择器 + CRUD
# 复用 ProfileStyles 样式工厂，与游戏战绩/能力数据视觉一致
extends HBoxContainer

var _list_vbox: VBoxContainer
var _scroll: ScrollContainer
var _msg_input: LineEdit
var _once_btn: Button
var _add_once := false
var _status_label: Label

# ── 拨轮 ──
var _hour_val: int = 9
var _minute_val: int = 0
var _roller_labels: Dictionary = {}
var _roller_drums: Dictionary = {}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)

	var outer_margin = MarginContainer.new()
	outer_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_margin.add_theme_constant_override("margin_right", 12)
	outer_margin.add_theme_constant_override("margin_bottom", 16)
	_scroll.add_child(outer_margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_margin.add_child(main_vbox)

	# ── 1. 状态概览条 ──
	_build_status_bar(main_vbox)

	# ── 2. 输入区 (时间 + 消息 + 添加) ──
	_build_input_section(main_vbox)

	# ── 3. 提醒列表 ──
	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 12)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_list_vbox)

	_refresh_list()

	# ── 独立科幻滚动指示器 ──
	var indicator = preload("res://ui/profile/cyber_scroll_indicator.gd").new()
	indicator.bind_scroll(_scroll)
	add_child(indicator)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_roller_labels.clear()
	_roller_drums.clear()
	_list_vbox = null
	_msg_input = null
	_once_btn = null
	_status_label = null
	build()

# ═══════════════════════════════════════════════
#  状态概览条
# ═══════════════════════════════════════════════

func _build_status_bar(parent: VBoxContainer) -> void:
	var bar = PanelContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(0.02, 0.04, 0.08, 0.4)
	bs.border_width_bottom = 1
	bs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.15)
	bs.content_margin_left = 12; bs.content_margin_right = 12
	bs.content_margin_top = 8; bs.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", bs)
	parent.add_child(bar)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", ProfileStyles.dim())
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_status_label)
	_update_status()

func _update_status() -> void:
	if not _status_label:
		return
	var reminders = SettingsManager.get_reminders()
	var active_count := 0
	var next_time := ""
	var now_dict = Time.get_time_dict_from_system()
	var now_minutes: int = now_dict["hour"] * 60 + now_dict["minute"]
	var closest_diff := 9999

	for r in reminders:
		if r.get("on", true):
			active_count += 1
			var parts = r.get("time", "00:00").split(":")
			if parts.size() == 2:
				var r_minutes: int = int(parts[0]) * 60 + int(parts[1])
				var diff: int = r_minutes - now_minutes
				if diff <= 0:
					diff += 1440  # 次日
				if diff < closest_diff:
					closest_diff = diff
					next_time = r.get("time", "")

	if reminders.is_empty():
		_status_label.text = "> SYS_SCHEDULER: 无注册日程 · 服务待命中"
	elif active_count == 0:
		_status_label.text = "> SYS_SCHEDULER: %d 条日程已暂停 · 无活跃任务" % reminders.size()
	else:
		var next_str = " · 下次触发 %s" % next_time if next_time != "" else ""
		_status_label.text = "> SYS_SCHEDULER: %d/%d 日程活跃%s" % [active_count, reminders.size(), next_str]

# ═══════════════════════════════════════════════
#  输入区
# ═══════════════════════════════════════════════

func _build_input_section(parent: VBoxContainer) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.16, 0.45)
	cs.border_width_left = 4
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.7)
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 20; cs.content_margin_right = 20
	cs.content_margin_top = 16; cs.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	# 标题行
	var title_row = HBoxContainer.new()
	var t_sub = ProfileStyles.label_dim("NEW_ENTRY //", 13)
	title_row.add_child(t_sub)
	var t_main = ProfileStyles.make_label("注册提醒", 17, Color(0.85, 0.9, 0.95))
	title_row.add_child(t_main)
	vbox.add_child(title_row)

	var hsep = HSeparator.new()
	var s_sep = StyleBoxFlat.new()
	s_sep.border_width_top = 1
	s_sep.border_color = Color(1.0, 1.0, 1.0, 0.05)
	hsep.add_theme_stylebox_override("separator", s_sep)
	hsep.add_theme_constant_override("separation", 1)
	vbox.add_child(hsep)

	# ── 第一行: 拨轮 + 模式切换 ──
	var time_row = HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 6)
	time_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_child(time_row)

	var hour_col = _build_roller(0, 23, 9, "_hour_val", 1)
	time_row.add_child(hour_col)

	var colon_label = ProfileStyles.make_label(":", 26, Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.8))
	time_row.add_child(colon_label)

	# 分钟: step=1, 范围 0~59，支持精确到每一分钟
	var minute_col = _build_roller(0, 59, 0, "_minute_val", 1)
	time_row.add_child(minute_col)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_row.add_child(spacer)

	# 模式切换按钮
	_once_btn = Button.new()
	_once_btn.text = "1x单次" if _add_once else "每日循环"
	_once_btn.add_theme_font_size_override("font_size", 15)
	_once_btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
	_once_btn.add_theme_stylebox_override("normal", ProfileStyles.small_btn_normal())
	_once_btn.add_theme_stylebox_override("hover", ProfileStyles.small_btn_hover())
	_once_btn.add_theme_stylebox_override("pressed", ProfileStyles.small_btn_hover())
	_once_btn.pressed.connect(_on_once_toggled)
	var once_center = CenterContainer.new()
	once_center.add_child(_once_btn)
	time_row.add_child(once_center)

	# ── 第二行: 消息 + 添加 ──
	var msg_row = HBoxContainer.new()
	msg_row.add_theme_constant_override("separation", 8)
	vbox.add_child(msg_row)

	_msg_input = _make_input("输入提醒内容 (留空则使用默认话术)", 0, 0)
	_msg_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_input.text_submitted.connect(func(_t): _on_add_pressed())
	msg_row.add_child(_msg_input)

	var add_btn = Button.new()
	add_btn.text = "+ 注册"
	add_btn.add_theme_font_size_override("font_size", 15)
	add_btn.add_theme_color_override("font_color", Color(0.7, 0.9, 0.8, 0.9))
	var add_s = ProfileStyles.small_btn_normal()
	add_s.border_color = Color.from_hsv(fmod(EventBus.ui_hue + 0.3, 1.0), 0.5, 0.6, 0.5)
	add_btn.add_theme_stylebox_override("normal", add_s)
	var add_h = ProfileStyles.small_btn_hover()
	add_h.border_color = Color.from_hsv(fmod(EventBus.ui_hue + 0.3, 1.0), 0.6, 0.8, 0.7)
	add_btn.add_theme_stylebox_override("hover", add_h)
	add_btn.add_theme_stylebox_override("pressed", add_h)
	add_btn.pressed.connect(_on_add_pressed)
	msg_row.add_child(add_btn)

# ═══════════════════════════════════════════════
#  拨轮时间选择器
# ═══════════════════════════════════════════════

func _build_roller(min_val: int, max_val: int, default_val: int, meta_key: String, step: int = 1) -> VBoxContainer:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	# ▲ 递增
	var up_btn = Button.new()
	up_btn.text = "▲"
	up_btn.add_theme_font_size_override("font_size", 12)
	up_btn.add_theme_color_override("font_color", ProfileStyles.dim())
	up_btn.add_theme_color_override("font_hover_color", ProfileStyles.accent())
	up_btn.add_theme_color_override("font_pressed_color", ProfileStyles.accent())
	up_btn.custom_minimum_size = Vector2(58, 22)
	_style_roller_btn(up_btn)
	var st = step; var mk = meta_key; var mn = min_val; var mx = max_val
	up_btn.pressed.connect(func(): _adjust_roller(mk, st, mn, mx))
	col.add_child(up_btn)

	# 数字显示区
	var drum = PanelContainer.new()
	var drum_style = StyleBoxFlat.new()
	drum_style.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.2, 0.5)
	drum_style.border_width_left = 2
	drum_style.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.4)
	drum_style.set_corner_radius_all(0)
	drum_style.content_margin_left = 4; drum_style.content_margin_right = 4
	drum_style.content_margin_top = 3; drum_style.content_margin_bottom = 3
	drum.add_theme_stylebox_override("panel", drum_style)
	drum.custom_minimum_size = Vector2(60, 42)
	drum.mouse_filter = Control.MOUSE_FILTER_STOP

	var current_label = Label.new()
	current_label.text = "%02d" % default_val
	current_label.add_theme_font_size_override("font_size", 28)
	current_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_label.custom_minimum_size = Vector2(50, 34)
	current_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drum.add_child(current_label)
	col.add_child(drum)

	# 鼠标滚轮支持 (滚轮步进5方便快速拨动，按钮步进1精确微调)
	var wheel_step = 5 if (mx - mn) > 30 else st  # 分钟用5步快拨，小时用1步
	drum.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_adjust_roller(mk, wheel_step, mn, mx)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_adjust_roller(mk, -wheel_step, mn, mx)
	)

	# ▼ 递减
	var down_btn = Button.new()
	down_btn.text = "▼"
	down_btn.add_theme_font_size_override("font_size", 12)
	down_btn.add_theme_color_override("font_color", ProfileStyles.dim())
	down_btn.add_theme_color_override("font_hover_color", ProfileStyles.accent())
	down_btn.add_theme_color_override("font_pressed_color", ProfileStyles.accent())
	down_btn.custom_minimum_size = Vector2(58, 22)
	_style_roller_btn(down_btn)
	down_btn.pressed.connect(func(): _adjust_roller(mk, -st, mn, mx))
	col.add_child(down_btn)

	# 保存引用
	set(meta_key, default_val)
	_roller_labels[meta_key] = current_label
	_roller_drums[meta_key] = drum
	return col

func _style_roller_btn(btn: Button) -> void:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.08, 0.15, 0.4)
	s.set_corner_radius_all(0)
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(0.08, 0.12, 0.25, 0.8)
	h.border_width_bottom = 1
	h.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.4)
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
		# 底板弹跳动画
		if _roller_drums.has(meta_key):
			var hl = _roller_drums[meta_key]
			hl.pivot_offset = hl.size / 2.0
			var tw = create_tween()
			tw.tween_property(hl, "scale", Vector2(1.06, 1.06), 0.05)
			tw.tween_property(hl, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_BACK)

# ═══════════════════════════════════════════════
#  输入框
# ═══════════════════════════════════════════════

func _make_input(placeholder: String, min_width: int, max_len: int) -> LineEdit:
	var input = LineEdit.new()
	input.placeholder_text = placeholder
	if min_width > 0:
		input.custom_minimum_size = Vector2(min_width, 0)
	if max_len > 0:
		input.max_length = max_len
	input.add_theme_font_size_override("font_size", 17)
	input.add_theme_color_override("font_color", Color(0.9, 0.95, 1, 1))
	input.add_theme_color_override("font_placeholder_color", Color(0.35, 0.45, 0.55, 0.6))
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.04, 0.06, 0.12, 0.7)
	input_style.border_width_left = 2
	input_style.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.3)
	input_style.set_corner_radius_all(0)
	input_style.content_margin_left = 10; input_style.content_margin_right = 10
	input_style.content_margin_top = 6; input_style.content_margin_bottom = 6
	input.add_theme_stylebox_override("normal", input_style)
	var focus_style = input_style.duplicate()
	focus_style.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 0.6)
	input.add_theme_stylebox_override("focus", focus_style)
	return input

# ═══════════════════════════════════════════════
#  提醒列表
# ═══════════════════════════════════════════════

func _refresh_list() -> void:
	if not _list_vbox:
		return
	# 立即从场景树移除再释放，防止 queue_free 延迟导致幽灵残留
	var children = _list_vbox.get_children()
	for child in children:
		_list_vbox.remove_child(child)
		child.queue_free()

	var reminders = SettingsManager.get_reminders()

	# 更新状态条
	_update_status()

	if reminders.is_empty():
		var note_pnl = PanelContainer.new()
		var n_s = StyleBoxFlat.new()
		n_s.bg_color = Color(0, 0, 0, 0)
		n_s.border_width_left = 2
		n_s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.6, 0.3)
		n_s.content_margin_left = 8
		note_pnl.add_theme_stylebox_override("panel", n_s)
		var note = ProfileStyles.label_dim("> SYS_REPORT: 当前无已注册提醒日程。系统待命中。", 14)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_pnl.add_child(note)
		_list_vbox.add_child(note_pnl)
		return

	# 列表标题
	var header = HBoxContainer.new()
	header.add_child(ProfileStyles.label_dim("SCHEDULE_LOG //", 12))
	header.add_child(ProfileStyles.make_label("已注册日程 [%d]" % reminders.size(), 16, Color(0.75, 0.82, 0.9)))
	_list_vbox.add_child(header)

	for i in range(reminders.size()):
		var r = reminders[i]
		_add_reminder_card(r, i)

func _add_reminder_card(r: Dictionary, idx: int) -> void:
	var is_on: bool = r.get("on", true)
	var is_once: bool = r.get("once", false)

	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.16, 0.45) if is_on else Color(0.06, 0.07, 0.1, 0.3)
	cs.border_width_left = 4
	if not is_on:
		cs.border_color = Color(0.3, 0.3, 0.35, 0.3)
	else:
		cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.7)
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 16; cs.content_margin_right = 12
	cs.content_margin_top = 10; cs.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", cs)

	# 卡片 hover
	var cs_ref = cs
	card.mouse_entered.connect(func():
		if not is_instance_valid(card): return
		var hs = cs_ref.duplicate()
		hs.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.5) if is_on else Color(0.4, 0.4, 0.45, 0.4)
		card.add_theme_stylebox_override("panel", hs)
	)
	card.mouse_exited.connect(func():
		if not is_instance_valid(card): return
		card.add_theme_stylebox_override("panel", cs_ref)
	)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	# 开关指示灯
	var toggle = Button.new()
	toggle.text = "●" if is_on else "○"
	toggle.add_theme_font_size_override("font_size", 16)
	toggle.add_theme_color_override("font_color", Color(0.3, 1, 0.7, 1) if is_on else Color(0.4, 0.4, 0.5, 0.5))
	toggle.add_theme_color_override("font_hover_color", Color(0.5, 1, 0.85, 1))
	toggle.custom_minimum_size = Vector2(32, 32)
	var tg_s = StyleBoxFlat.new()
	tg_s.bg_color = Color(0.06, 0.1, 0.2, 0.4)
	tg_s.set_corner_radius_all(0)
	toggle.add_theme_stylebox_override("normal", tg_s)
	var tg_h = tg_s.duplicate()
	tg_h.bg_color = Color(0.1, 0.16, 0.3, 0.7)
	toggle.add_theme_stylebox_override("hover", tg_h)
	toggle.add_theme_stylebox_override("pressed", tg_h)
	var idx_t = idx
	toggle.pressed.connect(func(): _toggle_reminder(idx_t))
	row.add_child(toggle)

	# 注册日期面板 (放在时间左侧，带边框层级感)
	var created = r.get("created", "")
	if created != "":
		# 显示完整时间戳，兼容旧格式 ("2026-05-14" → 仅显示日期)
		var display_date = created
		var date_pnl = PanelContainer.new()
		var dp_s = StyleBoxFlat.new()
		dp_s.bg_color = Color(0.04, 0.06, 0.1, 0.5) if is_on else Color(0.04, 0.05, 0.07, 0.3)
		dp_s.border_width_left = 2
		dp_s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.35) if is_on else Color(0.25, 0.25, 0.3, 0.2)
		dp_s.set_corner_radius_all(0)
		dp_s.content_margin_left = 8; dp_s.content_margin_right = 8
		dp_s.content_margin_top = 4; dp_s.content_margin_bottom = 4
		date_pnl.add_theme_stylebox_override("panel", dp_s)
		var date_lbl = Label.new()
		date_lbl.text = display_date
		date_lbl.add_theme_font_size_override("font_size", 12)
		date_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 0.7) if is_on else Color(0.35, 0.38, 0.4, 0.4))
		date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		date_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		date_pnl.add_child(date_lbl)
		row.add_child(date_pnl)

	# 时间标签
	var time_label = Label.new()
	time_label.text = r.get("time", "??:??")
	time_label.add_theme_font_size_override("font_size", 22)
	time_label.add_theme_color_override("font_color", ProfileStyles.accent() if is_on else Color(0.4, 0.4, 0.45, 0.5))
	time_label.custom_minimum_size = Vector2(60, 0)
	row.add_child(time_label)

	# 消息
	var msg_label = Label.new()
	msg_label.text = r.get("msg", "")
	msg_label.add_theme_font_size_override("font_size", 16)
	msg_label.add_theme_color_override("font_color", Color(0.80, 0.86, 0.92, 0.9) if is_on else Color(0.4, 0.42, 0.45, 0.5))
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(msg_label)

	# 触发状态 (今日已触发 / 待触发 / 已过期)
	if is_on:
		var trigger_text := _get_trigger_status(r)
		if trigger_text != "":
			var trig_lbl = Label.new()
			trig_lbl.text = trigger_text
			trig_lbl.add_theme_font_size_override("font_size", 12)
			trig_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.5, 0.6))
			trig_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(trig_lbl)

	# 类型标签
	var type_label = Label.new()
	type_label.text = "单次" if is_once else "每日"
	type_label.add_theme_font_size_override("font_size", 13)
	type_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.8) if is_on else Color(0.5, 0.5, 0.5, 0.4))
	var t_style = StyleBoxFlat.new()
	if not is_on:
		t_style.bg_color = Color(0.2, 0.2, 0.25, 0.3)
	elif is_once:
		t_style.bg_color = Color.from_hsv(fmod(EventBus.ui_hue + 0.12, 1.0), 0.45, 0.4, 0.7)
	else:
		t_style.bg_color = Color.from_hsv(EventBus.ui_hue, 0.45, 0.35, 0.7)
	t_style.set_corner_radius_all(2)
	t_style.content_margin_left = 6; t_style.content_margin_right = 6
	t_style.content_margin_top = 2; t_style.content_margin_bottom = 2
	type_label.add_theme_stylebox_override("normal", t_style)
	var t_center = CenterContainer.new()
	t_center.add_child(type_label)
	row.add_child(t_center)

	# 删除按钮
	var del_btn = Button.new()
	del_btn.text = "注销"
	del_btn.add_theme_font_size_override("font_size", 13)
	del_btn.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5, 0.7) if is_on else Color(0.5, 0.35, 0.35, 0.5))
	del_btn.add_theme_color_override("font_hover_color", Color(1, 0.7, 0.7, 1))
	var d_s = StyleBoxFlat.new()
	d_s.bg_color = Color(0.15, 0.05, 0.05, 0.4)
	d_s.border_width_left = 2
	d_s.border_color = Color(0.6, 0.25, 0.25, 0.3)
	d_s.set_corner_radius_all(0)
	d_s.content_margin_left = 8; d_s.content_margin_right = 8
	d_s.content_margin_top = 3; d_s.content_margin_bottom = 3
	del_btn.add_theme_stylebox_override("normal", d_s)
	var d_h = d_s.duplicate()
	d_h.bg_color = Color(0.3, 0.08, 0.08, 0.7)
	d_h.border_color = Color(0.8, 0.35, 0.35, 0.5)
	del_btn.add_theme_stylebox_override("hover", d_h)
	del_btn.add_theme_stylebox_override("pressed", d_h)
	var idx_d = idx; var card_ref = card
	del_btn.pressed.connect(func(): _delete_reminder_animated(idx_d, card_ref))
	var d_center = CenterContainer.new()
	d_center.add_child(del_btn)
	row.add_child(d_center)

	_list_vbox.add_child(card)

## 判断单条提醒的当日触发状态
func _get_trigger_status(r: Dictionary) -> String:
	var now_dict = Time.get_time_dict_from_system()
	var now_minutes: int = now_dict["hour"] * 60 + now_dict["minute"]
	var parts = r.get("time", "00:00").split(":")
	if parts.size() != 2:
		return ""
	var r_minutes: int = int(parts[0]) * 60 + int(parts[1])
	if r_minutes < now_minutes:
		if r.get("once", false):
			return "待触发"  # 单次的还没到时间或已过（但还存在说明没触发过）
		return "今日已过"
	elif r_minutes == now_minutes:
		return "触发中"
	else:
		var diff = r_minutes - now_minutes
		if diff <= 60:
			return "%d分钟后" % diff
		return "待触发"

# ═══════════════════════════════════════════════
#  操作
# ═══════════════════════════════════════════════

func _on_once_toggled() -> void:
	_add_once = not _add_once
	if _once_btn:
		_once_btn.text = "1x单次" if _add_once else "每日循环"

func _on_add_pressed() -> void:
	var t = "%02d:%02d" % [_hour_val, _minute_val]
	var m = _msg_input.text.strip_edges() if _msg_input else ""
	if m.is_empty():
		m = "时间节点已到达。"
	var reminders = SettingsManager.get_reminders()
	var now_dt = Time.get_datetime_string_from_system().replace("T", " ")
	reminders.append({"time": t, "msg": m, "on": true, "once": _add_once, "created": now_dt})
	SettingsManager.save_reminders(reminders)
	if _msg_input:
		_msg_input.text = ""
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

func _delete_reminder_animated(idx: int, card: PanelContainer) -> void:
	if not is_instance_valid(card):
		_delete_reminder(idx)
		return
	card.pivot_offset = card.size / 2.0
	var tw = create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 0.0, 0.15)
	tw.tween_property(card, "scale", Vector2(0.8, 0.8), 0.15)
	tw.finished.connect(func(): _delete_reminder(idx))

# datalog_window_cards.gd — 窗口活动报告卡片渲染
# 将 window_data 结构化数据渲染为应用卡片网格
extends RefCounted

## 渲染窗口卡片到 container
## window_data: { "procName": { process, titles, focus_sec, first_seen, last_active } }
static func render(container: Control, window_data: Dictionary) -> void:
	for child in container.get_children():
		child.queue_free()

	if window_data.is_empty():
		var hint = Label.new()
		hint.text = "本次会话未检测到窗口活动"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.4))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(hint)
		return

	# 按前台时长排序
	var sorted = []
	for proc_name in window_data:
		var info: Dictionary = window_data[proc_name]
		sorted.append([proc_name, info])
	sorted.sort_custom(func(a, b): return a[1].get("focus_sec", 0) > b[1].get("focus_sec", 0))

	# 网格容器
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(grid)

	for item in sorted:
		var proc_name: String = item[0]
		var info: Dictionary = item[1]
		var card = _make_app_card(proc_name, info)
		grid.add_child(card)

## 单个应用卡片
static func _make_app_card(proc_name: String, info: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cs = StyleBoxFlat.new()
	cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.20, 0.10, 0.45)
	cs.set_corner_radius_all(3)
	cs.set_border_width_all(1)
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.25, 0.35, 0.2)
	cs.border_width_top = 2
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.55, 0.4)
	cs.content_margin_left = 10; cs.content_margin_right = 10
	cs.content_margin_top = 8; cs.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", cs)

	var base_bg = Color.from_hsv(EventBus.ui_hue, 0.20, 0.10, 0.45)
	var base_bd = Color.from_hsv(EventBus.ui_hue, 0.4, 0.55, 0.4)
	var hover_bg = Color.from_hsv(EventBus.ui_hue, 0.30, 0.20, 0.65)
	var hover_bd = Color.from_hsv(EventBus.ui_hue, 0.6, 0.9, 0.8)

	card.mouse_entered.connect(func():
		var tw = card.create_tween()
		tw.set_parallel(true)
		tw.tween_property(cs, "bg_color", hover_bg, 0.15).set_trans(Tween.TRANS_SINE)
		tw.tween_property(cs, "border_color", hover_bd, 0.15)
	)
	card.mouse_exited.connect(func():
		var tw = card.create_tween()
		tw.set_parallel(true)
		tw.tween_property(cs, "bg_color", base_bg, 0.3).set_trans(Tween.TRANS_SINE)
		tw.tween_property(cs, "border_color", base_bd, 0.3)
	)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# 进程名 (标题行)
	var name_lbl = Label.new()
	name_lbl.text = proc_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95, 0.9))
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(name_lbl)

	# 前台时长
	var focus_sec: int = info.get("focus_sec", 0)
	var time_str = _format_duration(focus_sec)
	var time_lbl = Label.new()
	time_lbl.text = time_str
	time_lbl.add_theme_font_size_override("font_size", 11)
	if focus_sec > 0:
		time_lbl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.8, 0.7))
	else:
		time_lbl.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.4))
	vbox.add_child(time_lbl)

	# 窗口标题 (最多显示 2 条)
	var titles: Array = info.get("titles", [])
	var show_count = mini(2, titles.size())
	for i in range(show_count):
		var t = str(titles[i])
		if t.length() > 35:
			t = t.substr(0, 35) + "..."
		var t_lbl = Label.new()
		t_lbl.text = t
		t_lbl.add_theme_font_size_override("font_size", 10)
		t_lbl.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.4))
		t_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		vbox.add_child(t_lbl)
	if titles.size() > 2:
		var more = Label.new()
		more.text = "+%d 个窗口" % (titles.size() - 2)
		more.add_theme_font_size_override("font_size", 10)
		more.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 0.3))
		vbox.add_child(more)

	# 时间范围
	var first = info.get("first_seen", "")
	var last = info.get("last_active", "")
	if first != "" and last != "":
		var range_lbl = Label.new()
		range_lbl.text = "%s ~ %s" % [first, last]
		range_lbl.add_theme_font_size_override("font_size", 9)
		range_lbl.add_theme_color_override("font_color", Color(0.3, 0.4, 0.5, 0.3))
		vbox.add_child(range_lbl)

	return card

static func _format_duration(sec: int) -> String:
	if sec >= 3600:
		return "前台 %dh %dm" % [sec / 3600, (sec % 3600) / 60]
	elif sec >= 60:
		return "前台 %dm %ds" % [sec / 60, sec % 60]
	elif sec > 0:
		return "前台 %ds" % sec
	else:
		return "仅检测到"

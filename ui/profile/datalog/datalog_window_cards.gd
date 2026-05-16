# datalog_window_cards.gd — 窗口活动报告卡片渲染
# 将 window_data 结构化数据渲染为带有目标锁定+雷达标尺动效的应用卡片网格
extends RefCounted

## 渲染窗口卡片到 container
static func render(container: Control, window_data: Dictionary, window_delta: Dictionary = {}) -> void:
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
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(grid)

	for item in sorted:
		var proc_name: String = item[0]
		var info: Dictionary = item[1]
		var delta_info: Dictionary = window_delta.get(proc_name, {})
		var card = _make_app_card(proc_name, info, delta_info)
		grid.add_child(card)

static func _make_app_card(proc_name: String, info: Dictionary, delta_info: Dictionary = {}) -> Control:
	var card = AppCard.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# 进程名 (标题行)
	var name_row = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_row)

	var name_lbl = Label.new()
	name_lbl.text = proc_name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_lbl)

	# 新增进程标记
	if delta_info.get("is_new", false):
		var new_badge = Label.new()
		new_badge.text = "NEW"
		new_badge.add_theme_font_size_override("font_size", 9)
		new_badge.add_theme_color_override("font_color", Color(0.3, 0.95, 0.5, 0.9))
		name_row.add_child(new_badge)

	# 前台时长 + 增量
	var time_row = HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 6)
	time_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(time_row)

	var focus_sec: int = info.get("focus_sec", 0)
	var time_str = _format_duration(focus_sec)
	var time_lbl = Label.new()
	time_lbl.text = time_str
	time_lbl.add_theme_font_size_override("font_size", 13)
	if focus_sec > 0:
		time_lbl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.95, 0.9))
	else:
		time_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.6))
	time_row.add_child(time_lbl)

	# 增量绿字 (+XXm)
	var delta_sec: int = delta_info.get("focus_sec_delta", 0)
	if delta_sec > 0:
		var delta_lbl = Label.new()
		delta_lbl.text = "+%s" % _format_delta_duration(delta_sec)
		delta_lbl.add_theme_font_size_override("font_size", 11)
		delta_lbl.add_theme_color_override("font_color", Color(0.3, 0.95, 0.5, 0.85))
		time_row.add_child(delta_lbl)

	# 窗口标题 (最多显示 2 条)
	var titles: Array = info.get("titles", [])
	var show_count = mini(2, titles.size())
	for i in range(show_count):
		var t = str(titles[i])
		if t.length() > 35:
			t = t.substr(0, 35) + "..."
		var t_lbl = Label.new()
		t_lbl.text = t
		t_lbl.add_theme_font_size_override("font_size", 12)
		t_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 0.8))
		t_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		vbox.add_child(t_lbl)
	if titles.size() > 2:
		var more = Label.new()
		more.text = "+%d 个窗口" % (titles.size() - 2)
		more.add_theme_font_size_override("font_size", 12)
		more.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75, 0.6))
		vbox.add_child(more)

	# 时间范围
	var first = info.get("first_seen", "")
	var last = info.get("last_active", "")
	if first != "" and last != "":
		var range_lbl = Label.new()
		range_lbl.text = "%s ~ %s" % [first, last]
		range_lbl.add_theme_font_size_override("font_size", 11)
		range_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 0.65))
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

## 增量时长格式化 (用于绿字 +XX 显示)
static func _format_delta_duration(sec: int) -> String:
	if sec >= 3600:
		return "%dh%dm" % [sec / 3600, (sec % 3600) / 60]
	elif sec >= 60:
		return "%dm%ds" % [sec / 60, sec % 60]
	else:
		return "%ds" % sec

# 自定义卡片渲染器: 实现防伪跟随光标 + 机械装甲锁定效果
class AppCard extends MarginContainer:
	var is_hovered: bool = false
	var hover_t: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		clip_contents = false  # 允许绘制超出的机械装甲线
		
		# 强制使用 Margin 代替原来 PanelContainer 的内边距
		add_theme_constant_override("margin_left", 12)
		add_theme_constant_override("margin_right", 12)
		add_theme_constant_override("margin_top", 10)
		add_theme_constant_override("margin_bottom", 10)
		
		mouse_entered.connect(func():
			is_hovered = true
			set_process(true)
			queue_redraw()
		)
		mouse_exited.connect(func():
			is_hovered = false
			queue_redraw()
		)

	func _process(delta: float) -> void:
		var needs_redraw = false
		if is_hovered:
			if hover_t < 1.0:
				hover_t = min(hover_t + delta * 6.0, 1.0)
			needs_redraw = true # 鼠标在移动，需要频繁重绘跟踪线
		else:
			if hover_t > 0.0:
				hover_t = max(hover_t - delta * 5.0, 0.0)
				needs_redraw = true
			else:
				set_process(false)
				
		if needs_redraw:
			queue_redraw()

	func _draw() -> void:
		var rect = Rect2(Vector2.ZERO, size)
		var ui_hue = EventBus.ui_hue
		
		# === 1. 绘制底层填充 ===
		var base_bg = Color.from_hsv(ui_hue, 0.20, 0.10, 0.35)
		var hover_bg = Color.from_hsv(ui_hue, 0.30, 0.15, 0.55)
		draw_rect(rect, base_bg.lerp(hover_bg, hover_t))
		
		# 基础微光边框 (常态下顶部较亮)
		var base_line = Color.from_hsv(ui_hue, 0.4, 0.55, 0.3)
		var dim_line = Color.from_hsv(ui_hue, 0.25, 0.35, 0.15)
		draw_line(Vector2(0, 0), Vector2(size.x, 0), base_line, 1.0)
		draw_line(Vector2(size.x, 0), Vector2(size.x, size.y), dim_line, 1.0)
		draw_line(Vector2(size.x, size.y), Vector2(0, size.y), dim_line, 1.0)
		draw_line(Vector2(0, size.y), Vector2(0, 0), dim_line, 1.0)
		
		# === 2. 瞄准与边框跟随机制 ===
		if hover_t > 0.0:
			var mouse_pos = get_local_mouse_position()
			var accent = Color.from_hsv(ui_hue, 0.5, 0.9, 0.85 * hover_t)
			
			# 四周悬浮装甲锁定框 (从外向内咬合动画)
			var offset = 6.0 * (1.0 - hover_t)
			var length = 8.0 + 4.0 * hover_t
			var th = 1.5
			
			# 左上
			draw_polyline(PackedVector2Array([
				Vector2(-offset, length - offset),
				Vector2(-offset, -offset),
				Vector2(length - offset, -offset)
			]), accent, th)
			# 右上
			draw_polyline(PackedVector2Array([
				Vector2(size.x - length + offset, -offset),
				Vector2(size.x + offset, -offset),
				Vector2(size.x + offset, length - offset)
			]), accent, th)
			# 左下
			draw_polyline(PackedVector2Array([
				Vector2(-offset, size.y - length + offset),
				Vector2(-offset, size.y + offset),
				Vector2(length - offset, size.y + offset)
			]), accent, th)
			# 右下
			draw_polyline(PackedVector2Array([
				Vector2(size.x - length + offset, size.y + offset),
				Vector2(size.x + offset, size.y + offset),
				Vector2(size.x + offset, size.y - length + offset)
			]), accent, th)
			
			# === 3. X/Y 轴游标标尺跟随 ===
			if is_hovered:
				var mx = clamp(mouse_pos.x, 0, size.x)
				var my = clamp(mouse_pos.y, 0, size.y)
				var line_len = 16.0
				var line_th = 2.0
				
				# 掐断超出边框的部分，保证光刃严格在 0 到 size 的实线范围内滑动
				var x_start = clamp(mx - line_len, 0, size.x)
				var x_end = clamp(mx + line_len, 0, size.x)
				var y_start = clamp(my - line_len, 0, size.y)
				var y_end = clamp(my + line_len, 0, size.y)
				
				# X轴光刃 (上下边框)
				draw_line(Vector2(x_start, 0), Vector2(x_end, 0), accent, line_th)
				draw_line(Vector2(x_start, size.y), Vector2(x_end, size.y), accent, line_th)
				# Y轴光刃 (左右边框)
				draw_line(Vector2(0, y_start), Vector2(0, y_end), accent, line_th)
				draw_line(Vector2(size.x, y_start), Vector2(size.x, y_end), accent, line_th)

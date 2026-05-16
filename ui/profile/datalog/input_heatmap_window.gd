# input_heatmap_window.gd — 键鼠输入热力全图 (CanvasLayer 面板, 与装置终端一致)
# 用 _draw() 自绘完整键盘布局 + 鼠标三键, 每个键显示对应计数
# 由 datalog_tab.gd 创建并传入 input_data
extends CanvasLayer

# ── 数据 ──
var _key_data: Dictionary = {}
var _mouse_data: Dictionary = {}

# ── 布局常量 (基于面板实际尺寸动态缩放) ──
var _key_w := 50.0
var _key_h := 46.0
var _key_gap := 4.0
var _margin := 36.0
var _header_h := 80.0

# ── 内部 ──
var _panel: PanelContainer
var _canvas: Control
var _frame_drawer: Control
var _is_open: bool = false
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _time_passed: float = 0.0

# 键盘布局
var _rows: Array = []

# 统计缓存
var _total_keys: int = 0
var _total_mouse: int = 0
var _top_key: String = ""
var _top_count: int = 0
var _avg_count: float = 0.0     # 有效键平均值
var _delta_mode: bool = false   # delta 模式
var _mode_btn: Button           # 模式切换按钮

# ── 面板尺寸 ──
var _panel_w: float = 1100
var _panel_h: float = 640

func _ready() -> void:
	layer = 100  # 在装置终端之上
	_calc_sizes()
	_build_ui()
	_build_layout()

func _calc_sizes() -> void:
	var vp := get_viewport().get_visible_rect().size
	_panel_w = clampf(vp.x * 0.82, 1000, 1600)
	_panel_h = clampf(vp.y * 0.82, 580, 900)
	# 根据面板大小动态调整键帽尺寸
	var scale := minf(_panel_w / 1300.0, _panel_h / 680.0)
	_key_w = 50.0 * scale
	_key_h = 46.0 * scale
	_key_gap = 4.0 * scale
	_margin = 36.0 * scale
	_header_h = 80.0 * scale

func _process(delta: float) -> void:
	if _is_open:
		_time_passed += delta
		if is_instance_valid(_frame_drawer):
			_frame_drawer.queue_redraw()

# ═══════════════════════════════════════════════
#  UI 构建
# ═══════════════════════════════════════════════

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(_panel_w, _panel_h)
	var ps := StyleBoxEmpty.new()
	_panel.add_theme_stylebox_override("panel", ps)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)
	
	# 机能边框绘制层
	_frame_drawer = Control.new()
	_frame_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_drawer.draw.connect(_on_frame_draw)
	_panel.add_child(_frame_drawer)
	
	# 主内容 margin
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 36)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.add_child(margin)
	
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(outer)
	
	# 标题栏
	var title_bar := _build_title_bar()
	outer.add_child(title_bar)
	
	# 分隔线
	var hsep := HSeparator.new()
	hsep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	hsep.add_theme_constant_override("separation", 1)
	hsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(hsep)
	
	# 自绘画布
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_on_draw)
	outer.add_child(_canvas)

func _build_title_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.gui_input.connect(_on_title_bar_input)
	
	var title := Label.new()
	title.text = "输入行为热力全图"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.70, 0.80, 0.92, 0.9))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(title)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_PASS  # 拖拽区域
	bar.add_child(spacer)
	
	# 模式切换按钮
	_mode_btn = Button.new()
	_mode_btn.text = "绝对值"
	_mode_btn.add_theme_font_size_override("font_size", 13)
	var ms := StyleBoxFlat.new()
	ms.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.15, 0.6)
	ms.set_border_width_all(1)
	ms.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.5, 0.4)
	ms.set_corner_radius_all(3)
	ms.content_margin_left = 10; ms.content_margin_right = 10
	ms.content_margin_top = 3; ms.content_margin_bottom = 3
	_mode_btn.add_theme_stylebox_override("normal", ms)
	var mh := ms.duplicate()
	mh.bg_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.22, 0.7)
	mh.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.7, 0.6)
	_mode_btn.add_theme_stylebox_override("hover", mh)
	_mode_btn.add_theme_stylebox_override("pressed", mh)
	_mode_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.85, 0.85))
	_mode_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 0.95))
	_mode_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	_mode_btn.pressed.connect(_toggle_mode)
	bar.add_child(_mode_btn)
	
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4, 0.7))
	close_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.4, 0.35, 1.0))
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.08, 0.08, 0.5)
	cs.set_corner_radius_all(4)
	cs.set_border_width_all(1)
	cs.border_color = Color(0.5, 0.2, 0.2, 0.3)
	cs.content_margin_left = 10; cs.content_margin_right = 10
	cs.content_margin_top = 3; cs.content_margin_bottom = 3
	close_btn.add_theme_stylebox_override("normal", cs)
	var ch := cs.duplicate()
	ch.bg_color = Color(0.25, 0.1, 0.1, 0.7)
	ch.border_color = Color(0.8, 0.3, 0.3, 0.5)
	close_btn.add_theme_stylebox_override("hover", ch)
	close_btn.add_theme_stylebox_override("pressed", ch)
	close_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	close_btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close_panel()
	)
	bar.add_child(close_btn)
	
	return bar

# ═══════════════════════════════════════════════
#  拖拽
# ═══════════════════════════════════════════════

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = _panel.get_global_mouse_position() - _panel.position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_dragging = false
			return
		_panel.position = _clamp_pos(_panel.get_global_mouse_position() - _drag_offset)

func _clamp_pos(pos: Vector2) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - _panel_w - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - _panel_h - 4.0))
	return pos

# ═══════════════════════════════════════════════
#  面板开关
# ═══════════════════════════════════════════════

func set_data(key_data: Dictionary, mouse_data: Dictionary) -> void:
	_key_data = key_data
	_mouse_data = mouse_data
	_compute_stats()
	if _canvas:
		_canvas.queue_redraw()

func open_panel() -> void:
	_is_open = true
	# 通知 DWM 穿透系统: 面板打开, 禁用穿透
	EventBus.context_menu_toggled.emit(true)
	var vp := get_viewport().get_visible_rect().size
	_panel.position = Vector2((vp.x - _panel_w) * 0.5, (vp.y - _panel_h) * 0.5)
	_panel.pivot_offset = Vector2(_panel_w * 0.5, _panel_h * 0.5)
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	_panel.show()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close_panel() -> void:
	_is_open = false
	# 通知 DWM 穿透系统: 面板关闭, 恢复穿透
	EventBus.context_menu_toggled.emit(false)
	_panel.pivot_offset = _panel.size / 2.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.1)
	tween.tween_property(_panel, "scale", Vector2(0.85, 0.85), 0.1)
	tween.finished.connect(func(): _panel.hide())

func _compute_stats() -> void:
	_total_keys = 0
	_top_key = ""
	_top_count = 0
	var key_count := 0  # 有效键数量
	for k in _key_data:
		var v := int(_key_data[k])
		_total_keys += v
		if v > 0:
			key_count += 1
		if v > _top_count:
			_top_count = v
			_top_key = k
	_total_mouse = int(_mouse_data.get("left_clicks", 0)) + int(_mouse_data.get("right_clicks", 0)) + int(_mouse_data.get("middle_clicks", 0))
	_avg_count = float(_total_keys) / float(maxi(key_count, 1))

func _toggle_mode() -> void:
	_delta_mode = not _delta_mode
	_mode_btn.text = "基准偏差" if _delta_mode else "绝对值"
	if _canvas:
		_canvas.queue_redraw()

# ═══════════════════════════════════════════════
#  键盘布局定义
# ═══════════════════════════════════════════════

func _build_layout() -> void:
	var row_fn: Array = []
	row_fn.append(["Esc", "Escape", 1.0])
	row_fn.append(["", "", 0.5])
	for i in range(1, 13):
		row_fn.append(["F%d" % i, "F%d" % i, 1.0])
		if i == 4 or i == 8:
			row_fn.append(["", "", 0.25])
	
	var row_num: Array = [
		["`", "`", 1.0],
		["1", "1", 1.0], ["2", "2", 1.0], ["3", "3", 1.0], ["4", "4", 1.0], ["5", "5", 1.0],
		["6", "6", 1.0], ["7", "7", 1.0], ["8", "8", 1.0], ["9", "9", 1.0], ["0", "0", 1.0],
		["-", "-", 1.0], ["=", "=", 1.0],
		["Bksp", "Backspace", 2.0],
	]
	
	var row_q: Array = [
		["Tab", "Tab", 1.5],
		["Q", "Q", 1.0], ["W", "W", 1.0], ["E", "E", 1.0], ["R", "R", 1.0], ["T", "T", 1.0],
		["Y", "Y", 1.0], ["U", "U", 1.0], ["I", "I", 1.0], ["O", "O", 1.0], ["P", "P", 1.0],
		["[", "[", 1.0], ["]", "]", 1.0],
		["\\", "\\", 1.5],
	]
	
	var row_a: Array = [
		["Caps", "CapsLock", 1.75],
		["A", "A", 1.0], ["S", "S", 1.0], ["D", "D", 1.0], ["F", "F", 1.0], ["G", "G", 1.0],
		["H", "H", 1.0], ["J", "J", 1.0], ["K", "K", 1.0], ["L", "L", 1.0],
		[";", ";", 1.0], ["'", "'", 1.0],
		["Enter", "Enter", 2.25],
	]
	
	var row_z: Array = [
		["Shift", "VK_A0", 2.25],
		["Z", "Z", 1.0], ["X", "X", 1.0], ["C", "C", 1.0], ["V", "V", 1.0], ["B", "B", 1.0],
		["N", "N", 1.0], ["M", "M", 1.0],
		[",", ",", 1.0], [".", ".", 1.0], ["/", "/", 1.0],
		["Shift", "VK_A1", 2.75],
	]
	
	var row_sp: Array = [
		["Ctrl", "VK_A2", 1.5],
		["Win", "VK_5B", 1.0],
		["Alt", "VK_A4", 1.25],
		["Space", "Space", 6.25],
		["Alt", "VK_A5", 1.25],
		["Win", "VK_5C", 1.0],
		["Ctrl", "VK_A3", 1.5],
	]
	
	_rows = [row_fn, row_num, row_q, row_a, row_z, row_sp]

# ═══════════════════════════════════════════════
#  机能边框渲染 (复用装置终端样式)
# ═══════════════════════════════════════════════

func _on_frame_draw() -> void:
	if not _frame_drawer: return
	var hue := EventBus.ui_hue
	var w := _frame_drawer.size.x
	var h := _frame_drawer.size.y
	
	var c_l := 30.0
	var pts := PackedVector2Array()
	pts.append(Vector2(c_l, 0))
	pts.append(Vector2(w, 0))
	pts.append(Vector2(w, h - c_l))
	pts.append(Vector2(w - c_l, h))
	pts.append(Vector2(0, h))
	pts.append(Vector2(0, c_l))
	pts.append(Vector2(c_l, 0))
	
	_frame_drawer.draw_polygon(pts, PackedColorArray([Color(0.025, 0.035, 0.065, 0.96)]))
	_frame_drawer.draw_polyline(pts, Color.from_hsv(hue, 0.4, 0.7, 0.4), 1.2, true)
	
	# 刻度线
	var tick_c := Color.from_hsv(hue, 0.5, 0.8, 0.25)
	var cx := w * 0.5
	var i := -30
	while i <= 30:
		var tx := cx + i * 8.0
		var ty_len: float = 3.0 if i % 5 != 0 else 7.0
		if tx > c_l and tx < w - c_l:
			_frame_drawer.draw_line(Vector2(tx, 0), Vector2(tx, ty_len), tick_c, 1.0)
		i += 1
	
	# 呼吸切角
	var breathe := (sin(_time_passed * 4.0) * 0.5 + 0.5) * 0.6 + 0.4
	var br_c := Color.from_hsv(hue, 0.6, 0.9, 0.8 * breathe)
	_frame_drawer.draw_line(pts[5], pts[6], br_c, 3.0, true)
	_frame_drawer.draw_line(pts[2], pts[3], br_c, 3.0, true)
	
	# 直角 L 托座
	var ll := 16.0
	_frame_drawer.draw_polyline(PackedVector2Array([
		pts[1] + Vector2(-ll, 0), pts[1], pts[1] + Vector2(0, ll)
	]), br_c, 3.0, true)
	_frame_drawer.draw_polyline(PackedVector2Array([
		pts[4] + Vector2(ll, 0), pts[4], pts[4] + Vector2(0, -ll)
	]), br_c, 3.0, true)

# ═══════════════════════════════════════════════
#  主绘制
# ═══════════════════════════════════════════════

func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var hue := EventBus.ui_hue
	var kw := _key_w
	var kh := _key_h
	var gap := _key_gap
	var unit := kw + gap
	
	# 计算色彩基准
	var max_count := 1
	var max_delta := 1.0
	for k in _key_data:
		var v := int(_key_data[k])
		if v > max_count: max_count = v
		var d := absf(float(v) - _avg_count)
		if d > max_delta: max_delta = d
	for k in ["left_clicks", "right_clicks", "middle_clicks"]:
		var v := int(_mouse_data.get(k, 0))
		if v > max_count: max_count = v
	
	# 背景网格
	_draw_bg_grid(hue)
	
	# 顶部摘要
	_draw_header(font, hue)
	
	var ox := _margin
	var oy := _header_h
	
	# 区域: 功能键
	_draw_section_label(font, ox, oy, "SYS_FUNC // 系统功能键", hue)
	oy += 16
	
	for row_idx in range(_rows.size()):
		var row: Array = _rows[row_idx]
		var x := ox
		
		if row_idx == 1:
			oy += 10
			_draw_section_label(font, ox, oy, "ALPHA_MATRIX // 主键位矩阵", hue)
			oy += 16
		if row_idx == 5:
			_draw_section_label(font, ox, oy, "MOD_CTRL // 指令修饰层", hue)
			oy += 16
		
		for key_def in row:
			var label: String = key_def[0]
			var data_key: String = key_def[1]
			var w_mult: float = key_def[2]
			var key_width: float = w_mult * kw + (w_mult - 1.0) * gap if w_mult > 0 else 0.0
			
			if label == "":
				x += key_width + gap
				continue
			
			var count := int(_key_data.get(data_key, 0))
			_draw_key_cap(x, oy, key_width, kh, label, count, max_count, max_delta, font, hue)
			x += key_width + gap
		
		oy += kh + gap
	
	# 导航区
	var nav_ox := ox + 15.5 * unit + 28
	var nav_label_oy := oy - (kh + gap) * 4 - 12
	_draw_section_label(font, nav_ox, nav_label_oy, "NAV // 导航阵列", hue)
	
	var sp_oy := nav_label_oy + 16
	var sp_keys := [
		["Ins", "Insert"], ["Home", "Home"], ["PgUp", "PageUp"],
		["Del", "Delete"], ["End", "End"],   ["PgDn", "PageDown"],
	]
	for i in range(sp_keys.size()):
		var col := i % 3
		var row := i / 3
		_draw_key_cap(nav_ox + col * unit, sp_oy + row * (kh + gap),
			kw, kh, sp_keys[i][0], int(_key_data.get(sp_keys[i][1], 0)),
			max_count, max_delta, font, hue)
	
	var arrow_oy := sp_oy + 2 * (kh + gap) + 10
	var arrow_map := [
		[1, 0, "^", "Up"], [0, 1, "<", "Left"],
		[1, 1, "v", "Down"], [2, 1, ">", "Right"],
	]
	for a in arrow_map:
		_draw_key_cap(nav_ox + a[0] * unit, arrow_oy + a[1] * (kh + gap),
			kw, kh, a[2], int(_key_data.get(a[3], 0)),
			max_count, max_delta, font, hue)
	
	# 鼠标
	var mouse_ox := nav_ox + 4 * unit + 40
	var mouse_oy := _header_h
	_draw_section_label(font, mouse_ox, mouse_oy, "IO_DEVICE // 定位装置", hue)
	mouse_oy += 16
	_draw_mouse(mouse_ox, mouse_oy, font, max_count, hue)

# ═══════════════════════════════════════════════
#  背景网格
# ═══════════════════════════════════════════════

func _draw_bg_grid(hue: float) -> void:
	var w := _canvas.size.x
	var h := _canvas.size.y
	var gc := Color.from_hsv(hue, 0.12, 0.06, 0.10)
	var step := 40.0
	var x := 0.0
	while x < w:
		_canvas.draw_line(Vector2(x, 0), Vector2(x, h), gc, 1.0)
		x += step
	var y := 0.0
	while y < h:
		_canvas.draw_line(Vector2(0, y), Vector2(w, y), gc, 1.0)
		y += step

# ═══════════════════════════════════════════════
#  顶部统计摘要
# ═══════════════════════════════════════════════

func _draw_header(font: Font, hue: float) -> void:
	var ox := _margin
	var oy := 4.0
	
	var stat_color := Color(0.55, 0.62, 0.72, 0.75)
	var val_color := Color.from_hsv(hue, 0.4, 0.90, 0.95)
	
	_canvas.draw_string(font, Vector2(ox, oy + 18), "KEYSTROKES //",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stat_color)
	_canvas.draw_string(font, Vector2(ox + 115, oy + 18), _format_count(_total_keys),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, val_color)
	
	_canvas.draw_string(font, Vector2(ox + 210, oy + 18), "CLICKS //",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stat_color)
	_canvas.draw_string(font, Vector2(ox + 298, oy + 18), _format_count(_total_mouse),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, val_color)
	
	if _top_key != "":
		_canvas.draw_string(font, Vector2(ox + 380, oy + 18), "PEAK //",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stat_color)
		var peak_text := "%s (%s)" % [_top_key, _format_count(_top_count)]
		_canvas.draw_string(font, Vector2(ox + 450, oy + 18), peak_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.from_hsv(0.10, 0.65, 0.95, 0.95))
	
	# delta 模式额外显示平均值
	if _delta_mode:
		_canvas.draw_string(font, Vector2(ox + 620, oy + 18), "AVG //",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stat_color)
		_canvas.draw_string(font, Vector2(ox + 670, oy + 18), "%.1f" % _avg_count,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.from_hsv(0.55, 0.4, 0.90, 0.90))
	
	# 分隔线
	_canvas.draw_line(Vector2(ox, oy + 28), Vector2(ox + 750, oy + 28),
		Color.from_hsv(hue, 0.4, 0.5, 0.15), 1.0)
	
	# 人设注释
	var note := "-- 本机仅做行为采集。数据解读是操作员的事。 --"
	if _delta_mode:
		note = "-- 基准偏差模式: 偏暧 = 低于均值, 偏暖 = 高于均值。不关我事。 --"
	_canvas.draw_string(font, Vector2(ox, oy + 44), note,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.40, 0.45, 0.55, 0.40))

# ═══════════════════════════════════════════════
#  区域标签
# ═══════════════════════════════════════════════

func _draw_section_label(font: Font, x: float, y: float, text: String, hue: float) -> void:
	_canvas.draw_string(font, Vector2(x, y + 10), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color.from_hsv(hue, 0.25, 0.55, 0.40))

# ═══════════════════════════════════════════════
#  键帽绘制
# ═══════════════════════════════════════════════

func _draw_key_cap(x: float, y: float, w: float, h: float, label: String,
		count: int, max_count: int, max_delta: float, font: Font, hue: float) -> void:
	
	var heat: Color
	if _delta_mode and count > 0:
		heat = _delta_heat_color(count, max_delta, hue)
	else:
		heat = _heat_color(count, max_count, hue)
	
	# 底座
	var base_color := heat.darkened(0.4)
	base_color.a = 0.55
	_canvas.draw_rect(Rect2(x, y + 2, w, h), base_color)
	
	# 顶面
	_canvas.draw_rect(Rect2(x, y, w, h - 2), heat)
	
	# 顶部高光
	if count > 0:
		var hl := heat.lightened(0.3)
		hl.a = 0.25
		_canvas.draw_line(Vector2(x + 2, y + 1), Vector2(x + w - 2, y + 1), hl, 1.0)
	
	# 边框
	var ba := 0.20 if count == 0 else lerpf(0.30, 0.55, clampf(float(count) / float(max_count), 0.0, 1.0))
	_canvas.draw_rect(Rect2(x, y, w, h), Color.from_hsv(hue, 0.2, 0.45, ba), false, 1.0)
	
	# 高频发光
	if count > 0:
		var glow_t := clampf(float(count) / float(max_count), 0.0, 1.0)
		if _delta_mode:
			var delta := float(count) - _avg_count
			glow_t = clampf(absf(delta) / max_delta, 0.0, 1.0)
		if glow_t > 0.4:
			var glow_hue := hue
			if _delta_mode:
				glow_hue = 0.08 if float(count) > _avg_count else 0.6
			var glow := Color.from_hsv(glow_hue, 0.5, 0.8, (glow_t - 0.4) * 0.2)
			_canvas.draw_rect(Rect2(x - 1, y - 1, w + 2, h + 2), glow, false, 2.0)
	
	# 键名
	var fs := 12
	if label.length() <= 1:
		fs = 16
	elif label.length() <= 3:
		fs = 13
	
	var text_color: Color
	if count == 0:
		text_color = Color(0.50, 0.55, 0.65, 0.65)
	else:
		var t := clampf(float(count) / float(max_count), 0.0, 1.0)
		text_color = Color(1.0, 1.0, 1.0, lerpf(0.75, 1.0, t))
	
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tx := x + (w - tw) * 0.5
	var ty := y + (h - 2) * 0.5 + (1 if count == 0 else -1)
	_canvas.draw_string(font, Vector2(tx, ty), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	
	# 计数 / 偏差值
	if count > 0:
		var cs: String
		var count_color: Color
		if _delta_mode:
			var delta := int(round(float(count) - _avg_count))
			if delta >= 0:
				cs = "+%s" % _format_count(delta)
				count_color = Color.from_hsv(0.08, 0.6, 0.95, 0.90)  # 暖橙
			else:
				cs = "-%s" % _format_count(-delta)
				count_color = Color.from_hsv(0.58, 0.5, 0.85, 0.85)  # 冷蓝
		else:
			cs = _format_count(count)
			count_color = Color.from_hsv(0.35, 0.55, 0.90, 0.90)
		var csz := 10
		var cw := font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, csz).x
		_canvas.draw_string(font, Vector2(x + w - cw - 3, y + h - 5),
			cs, HORIZONTAL_ALIGNMENT_LEFT, -1, csz, count_color)

# ═══════════════════════════════════════════════
#  鼠标绘制
# ═══════════════════════════════════════════════

func _draw_mouse(ox: float, oy: float, font: Font, max_count: int, hue: float) -> void:
	var mw := 140.0
	var mh := 210.0
	var btn_h := 85.0
	var mid_w := 24.0
	var side_w := (mw - mid_w) / 2.0
	var r := 22.0

	# 外壳填充 (圆角近似)
	var body_c := Color(0.06, 0.07, 0.10, 0.85)
	_canvas.draw_rect(Rect2(ox, oy + r, mw, mh - r * 2), body_c)
	_canvas.draw_rect(Rect2(ox + r, oy, mw - r * 2, mh), body_c)
	_canvas.draw_circle(Vector2(ox + r, oy + r), r, body_c)
	_canvas.draw_circle(Vector2(ox + mw - r, oy + r), r, body_c)
	_canvas.draw_circle(Vector2(ox + r, oy + mh - r), r, body_c)
	_canvas.draw_circle(Vector2(ox + mw - r, oy + mh - r), r, body_c)
	
	# 轮廓
	var outline := Color.from_hsv(hue, 0.2, 0.40, 0.35)
	_canvas.draw_arc(Vector2(ox + r, oy + r), r, PI * 0.5, PI, 16, outline, 1.5)
	_canvas.draw_arc(Vector2(ox + mw - r, oy + r), r, 0, PI * 0.5, 16, outline, 1.5)
	_canvas.draw_arc(Vector2(ox + r, oy + mh - r), r, PI, PI * 1.5, 16, outline, 1.5)
	_canvas.draw_arc(Vector2(ox + mw - r, oy + mh - r), r, PI * 1.5, PI * 2.0, 16, outline, 1.5)
	_canvas.draw_line(Vector2(ox + r, oy), Vector2(ox + mw - r, oy), outline, 1.5)
	_canvas.draw_line(Vector2(ox + r, oy + mh), Vector2(ox + mw - r, oy + mh), outline, 1.5)
	_canvas.draw_line(Vector2(ox, oy + r), Vector2(ox, oy + mh - r), outline, 1.5)
	_canvas.draw_line(Vector2(ox + mw, oy + r), Vector2(ox + mw, oy + mh - r), outline, 1.5)
	
	# 分隔线
	_canvas.draw_line(Vector2(ox + side_w, oy + 4), Vector2(ox + side_w, oy + btn_h),
		Color.from_hsv(hue, 0.15, 0.3, 0.3), 1.0)
	_canvas.draw_line(Vector2(ox + side_w + mid_w, oy + 4), Vector2(ox + side_w + mid_w, oy + btn_h),
		Color.from_hsv(hue, 0.15, 0.3, 0.3), 1.0)
	_canvas.draw_line(Vector2(ox + 4, oy + btn_h), Vector2(ox + mw - 4, oy + btn_h),
		Color.from_hsv(hue, 0.15, 0.3, 0.25), 1.0)
	
	# 左键
	var lc := int(_mouse_data.get("left_clicks", 0))
	_canvas.draw_rect(Rect2(ox + 3, oy + 3, side_w - 3, btn_h - 4), _heat_color(lc, max_count, hue))
	_canvas.draw_string(font, Vector2(ox + 16, oy + 35), "L",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.75, 0.80, 0.88, 0.75) if lc == 0 else Color(1.0, 1.0, 1.0, 0.95))
	if lc > 0:
		_canvas.draw_string(font, Vector2(ox + 8, oy + btn_h - 10),
			_format_count(lc), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color.from_hsv(0.35, 0.55, 0.90, 0.90))
	
	# 中键
	var mc := int(_mouse_data.get("middle_clicks", 0))
	var mid_x := ox + side_w
	var wheel_y := oy + 14
	var wheel_h := btn_h - 30
	_canvas.draw_rect(Rect2(mid_x + 3, wheel_y, mid_w - 6, wheel_h), _heat_color(mc, max_count, hue))
	_canvas.draw_rect(Rect2(mid_x + 3, wheel_y, mid_w - 6, wheel_h), Color.from_hsv(hue, 0.2, 0.4, 0.3), false, 1.0)
	for i in range(4):
		var ly := wheel_y + 6 + i * 9
		_canvas.draw_line(Vector2(mid_x + 5, ly), Vector2(mid_x + mid_w - 5, ly),
			Color(0.4, 0.45, 0.55, 0.35), 1.0)
	if mc > 0:
		_canvas.draw_string(font, Vector2(mid_x + 2, oy + btn_h - 10),
			_format_count(mc), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color.from_hsv(0.35, 0.55, 0.90, 0.90))
	
	# 右键
	var rc := int(_mouse_data.get("right_clicks", 0))
	var rx := ox + side_w + mid_w
	_canvas.draw_rect(Rect2(rx, oy + 3, side_w - 3, btn_h - 4), _heat_color(rc, max_count, hue))
	_canvas.draw_string(font, Vector2(rx + 22, oy + 35), "R",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.75, 0.80, 0.88, 0.75) if rc == 0 else Color(1.0, 1.0, 1.0, 0.95))
	if rc > 0:
		_canvas.draw_string(font, Vector2(rx + 8, oy + btn_h - 10),
			_format_count(rc), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color.from_hsv(0.35, 0.55, 0.90, 0.90))
	
	# 底部总计
	var sy := oy + mh + 18
	var dim := Color(0.50, 0.55, 0.65, 0.55)
	_canvas.draw_string(font, Vector2(ox, sy), "L: %s" % _format_count(lc),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	_canvas.draw_string(font, Vector2(ox + 50, sy), "M: %s" % _format_count(mc),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	_canvas.draw_string(font, Vector2(ox + 100, sy), "R: %s" % _format_count(rc),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	
	var dist_px := int(_mouse_data.get("distance_px", 0))
	if dist_px > 0:
		_canvas.draw_string(font, Vector2(ox, sy + 16),
			"移动: %.1f m" % (float(dist_px) / 3780.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)

# ═══════════════════════════════════════════════
#  工具函数
# ═══════════════════════════════════════════════

func _heat_color(count: int, max_count: int, hue: float) -> Color:
	if count == 0:
		return Color(0.045, 0.05, 0.07, 0.45)
	var t := clampf(float(count) / float(max_count), 0.0, 1.0)
	var h := lerpf(hue + 0.05, 0.12, t)
	var s := lerpf(0.25, 0.65, t)
	var v := lerpf(0.10, 0.32, t)
	return Color.from_hsv(fmod(h, 1.0), s, v, 0.85)

## delta 发散色阶: 低于均值 → 冷蓝, 等于均值 → 中性, 高于均值 → 暖橙
func _delta_heat_color(count: int, max_delta: float, hue: float) -> Color:
	var delta := float(count) - _avg_count
	var t := clampf(absf(delta) / max_delta, 0.0, 1.0)
	if delta >= 0:
		# 高于均值: 偏暖 (橙/黄)
		var h := lerpf(0.12, 0.06, t)   # hue: 黄绿 → 橙
		var s := lerpf(0.20, 0.70, t)
		var v := lerpf(0.10, 0.35, t)
		return Color.from_hsv(h, s, v, 0.85)
	else:
		# 低于均值: 偏冷 (蓝/青)
		var h := lerpf(hue, 0.60, t)     # hue: 主题色 → 深蓝
		var s := lerpf(0.15, 0.55, t)
		var v := lerpf(0.08, 0.22, t)
		return Color.from_hsv(h, s, v, 0.85)

func _format_count(count: int) -> String:
	if count >= 10000:
		return "%.0fk" % (float(count) / 1000.0)
	if count >= 1000:
		return "%.1fk" % (float(count) / 1000.0)
	return str(count)

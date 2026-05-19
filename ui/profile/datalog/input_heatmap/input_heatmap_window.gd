extends CanvasLayer

var _key_data: Dictionary = {}
var _mouse_data: Dictionary = {}
var _combo_data: Dictionary = {}

var _key_w := 50.0
var _key_h := 46.0
var _key_gap := 4.0
var _margin := 36.0
var _header_h := 80.0

var _panel: PanelContainer
var _canvas: Control
var _frame_drawer: Control
var _is_open: bool = false
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _time_passed: float = 0.0

var _rows: Array = []
var _key_nodes: Array[CyberKey] = []
var _mouse_node: CyberMouse

var _total_keys: int = 0
var _total_mouse: int = 0
var _top_key: String = ""
var _top_count: int = 0
var _avg_count: float = 0.0
var _delta_mode: bool = false
var _mode_btn: Button

var _title_text: String = "输入行为热力全图"
var _subtitle_text: String = ""  # 自定义副标题 (为空则用默认)
var _unused_count: int = 0  # 从未按过的键数量
var _active_count: int = 0  # 按过的键数量
var _title_label: Label      # 标题 Label 引用
var _layout_bottom_y: float = 0.0  # 所有键盘元素的最大底部 Y 坐标

# ── 组合键排行区 ──
var _combo_scroll: ScrollContainer
var _combo_vbox: VBoxContainer
var _combo_label: Label
var _combo_sep: Control  # 分隔线
var _combo_wrapper: HBoxContainer  # CyberScrollIndicator 包装器

var _panel_w: float = 1100
var _panel_h: float = 640

func _ready() -> void:
	layer = 100
	_calc_sizes()
	_build_ui()
	_build_layout()

func _calc_sizes() -> void:
	var vp := get_viewport().get_visible_rect().size
	_panel_w = clampf(vp.x * 0.88, 1100, 1800)
	_panel_h = clampf(vp.y * 0.88, 640, 1050)
	var scale := minf(_panel_w / 1500.0, _panel_h / 820.0)
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
		# 精确区域穿透 (不阻塞面板外的桌面交互)
		var pet = _get_pet()
		if pet and is_instance_valid(_panel):
			pet.set_overlay_rect("heatmap", Rect2(_panel.position, Vector2(_panel_w, _panel_h)))

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(_panel_w, _panel_h)
	var ps := StyleBoxEmpty.new()
	_panel.add_theme_stylebox_override("panel", ps)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)
	
	_frame_drawer = Control.new()
	_frame_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_drawer.draw.connect(_on_frame_draw)
	_panel.add_child(_frame_drawer)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(36))
	margin.add_theme_constant_override("margin_right", int(36))
	margin.add_theme_constant_override("margin_top", int(28))
	margin.add_theme_constant_override("margin_bottom", int(36))
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
	
	outer.add_child(_build_title_bar())
	
	var hsep := HSeparator.new()
	if class_name_exists("ProfileStyles"):
		hsep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	hsep.add_theme_constant_override("separation", 1)
	hsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(hsep)
	
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_on_draw)
	outer.add_child(_canvas)

func class_name_exists(name: String) -> bool:
	return ProjectSettings.has_setting("autoload/" + name) or ClassDB.class_exists(name)

func _build_title_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.gui_input.connect(_on_title_bar_input)
	
	_title_label = Label.new()
	_title_label.text = _title_text
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.70, 0.80, 0.92, 0.9))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_title_label)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(spacer)
	
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

func set_data(key_data: Dictionary, mouse_data: Dictionary, combo_data: Dictionary = {}) -> void:
	_key_data = key_data
	_mouse_data = mouse_data
	_combo_data = combo_data
	_compute_stats()
	
	var hue := EventBus.ui_hue
	var max_c := 1
	var max_d := 1.0
	for k in _key_data:
		var v := int(_key_data[k])
		if v > max_c: max_c = v
		var d := absf(float(v) - _avg_count)
		if d > max_d: max_d = d
	for k in ["left_clicks", "right_clicks", "middle_clicks"]:
		var v := int(_mouse_data.get(k, 0))
		if v > max_c: max_c = v
		
	for node in _key_nodes:
		var c := int(_key_data.get(node.data_key, 0))
		node.set_stats(c, max_c, max_d, _avg_count, _delta_mode, hue)
		
	if is_instance_valid(_mouse_node):
		_mouse_node.set_stats(_mouse_data, max_c, hue)
		
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()
	
	_rebuild_combo_list()

## 设置自定义标题和副标题
func set_title(title: String, subtitle: String = "") -> void:
	_title_text = title
	_subtitle_text = subtitle
	if is_instance_valid(_title_label):
		_title_label.text = title

func open_panel() -> void:
	_is_open = true
	var vp := get_viewport().get_visible_rect().size
	_panel.position = Vector2((vp.x - _panel_w) * 0.5, (vp.y - _panel_h) * 0.5)
	_panel.pivot_offset = Vector2(_panel_w * 0.5, _panel_h * 0.5)
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	_panel.show()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close_panel() -> void:
	_is_open = false
	var pet = _get_pet()
	if pet:
		pet.remove_overlay_rect("heatmap")
	_panel.pivot_offset = _panel.size / 2.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.1)
	tween.tween_property(_panel, "scale", Vector2(0.85, 0.85), 0.1)
	tween.finished.connect(func(): _panel.hide())

func _compute_stats() -> void:
	_total_keys = 0
	_top_key = ""
	_top_count = 0
	_active_count = 0
	var key_count := 0
	for k in _key_data:
		var v := int(_key_data[k])
		_total_keys += v
		if v > 0: key_count += 1
		if v > _top_count:
			_top_count = v
			_top_key = k
	_active_count = key_count
	# 统计未使用的键 (基于布局中的所有键位)
	var total_layout_keys := _key_nodes.size()
	var used_in_layout := 0
	for node in _key_nodes:
		if int(_key_data.get(node.data_key, 0)) > 0:
			used_in_layout += 1
	_unused_count = total_layout_keys - used_in_layout
	_total_mouse = int(_mouse_data.get("left_clicks", 0)) + int(_mouse_data.get("right_clicks", 0)) + int(_mouse_data.get("middle_clicks", 0))
	_avg_count = float(_total_keys) / float(maxi(key_count, 1))

func _toggle_mode() -> void:
	_delta_mode = not _delta_mode
	_mode_btn.text = "基准偏差" if _delta_mode else "绝对值"
	set_data(_key_data, _mouse_data)

func _add_label(txt: String, px: float, py: float, c: Color, fs: int = 11) -> void:
	var lbl = Label.new()
	lbl.text = txt
	lbl.position = Vector2(px, py)
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color", c)
	_canvas.add_child(lbl)

func _build_layout() -> void:
	for n in _key_nodes: n.queue_free()
	_key_nodes.clear()
	if is_instance_valid(_mouse_node): _mouse_node.queue_free()
	
	var row_fn: Array = []
	row_fn.append(["Esc", "Escape", 1.0])
	row_fn.append(["", "", 0.5])
	for i in range(1, 13):
		row_fn.append(["F%d" % i, "F%d" % i, 1.0])
		if i == 4 or i == 8: row_fn.append(["", "", 0.25])
	
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
		["[", "[", 1.0], ["]", "]", 1.0], ["\\", "\\", 1.5],
	]
	
	var row_a: Array = [
		["Caps", "CapsLock", 1.75],
		["A", "A", 1.0], ["S", "S", 1.0], ["D", "D", 1.0], ["F", "F", 1.0], ["G", "G", 1.0],
		["H", "H", 1.0], ["J", "J", 1.0], ["K", "K", 1.0], ["L", "L", 1.0],
		[";", ";", 1.0], ["'", "'", 1.0], ["Enter", "Enter", 2.25],
	]
	
	var row_z: Array = [
		["Shift", "VK_A0", 2.25],
		["Z", "Z", 1.0], ["X", "X", 1.0], ["C", "C", 1.0], ["V", "V", 1.0], ["B", "B", 1.0],
		["N", "N", 1.0], ["M", "M", 1.0], [",", ",", 1.0], [".", ".", 1.0], ["/", "/", 1.0],
		["Shift", "VK_A1", 2.75],
	]
	
	var row_sp: Array = [
		["Ctrl", "VK_A2", 1.5],
		["Win", "VK_5B", 1.0], ["Alt", "VK_A4", 1.25],
		["Space", "Space", 6.25],
		["Alt", "VK_A5", 1.25], ["Win", "VK_5C", 1.0], ["Ctrl", "VK_A3", 1.5],
	]
	
	_rows = [row_fn, row_num, row_q, row_a, row_z, row_sp]
	var ox := _margin
	var oy := _header_h
	
	_add_label("SYS_FUNC // 系统功能键", ox, oy, Color.from_hsv(EventBus.ui_hue, 0.25, 0.55, 0.40))
	oy += 16
	
	for row_idx in range(_rows.size()):
		var row: Array = _rows[row_idx]
		var x := ox
		if row_idx == 1:
			oy += 10
			_add_label("ALPHA_MATRIX // 主键位矩阵", ox, oy, Color.from_hsv(EventBus.ui_hue, 0.25, 0.55, 0.40))
			oy += 16
		if row_idx == 5:
			_add_label("MOD_CTRL // 指令修饰层", ox, oy, Color.from_hsv(EventBus.ui_hue, 0.25, 0.55, 0.40))
			oy += 16
		
		for key_def in row:
			var lbl: String = key_def[0]
			var dk: String = key_def[1]
			var w_mult: float = key_def[2]
			var kw: float = w_mult * _key_w + (w_mult - 1.0) * _key_gap if w_mult > 0 else 0.0
			
			if lbl == "":
				x += kw + _key_gap
				continue
			
			var kn = CyberKey.new()
			kn._init_key(lbl, dk)
			kn.position = Vector2(x, oy)
			kn.size = Vector2(kw, _key_h)
			_canvas.add_child(kn)
			_key_nodes.append(kn)
			x += kw + _key_gap
		oy += _key_h + _key_gap
	var main_kb_bottom := oy  # 主键盘底部
	
	# ── 右侧元素统一对齐到数字行顶部 ──
	# 数字行顶部 = header + SYS_FUNC标签(16) + F键行(key_h+gap) + 间距(10) + ALPHA标签(16)
	var right_top_y := _header_h + 16 + (_key_h + _key_gap) + 10 + 16
	
	var nav_ox := ox + 15.5 * (_key_w + _key_gap) + 20
	_add_label("NAV // 导航阵列", nav_ox, right_top_y - 16, Color.from_hsv(EventBus.ui_hue, 0.25, 0.55, 0.40))
	
	var sp_oy := right_top_y
	var sp_keys := [
		["Ins", "Insert"], ["Home", "Home"], ["PgUp", "PageUp"],
		["Del", "Delete"], ["End", "End"],   ["PgDn", "PageDown"],
	]
	for i in range(sp_keys.size()):
		var col := i % 3
		var r := i / 3
		var kn = CyberKey.new()
		kn._init_key(sp_keys[i][0], sp_keys[i][1])
		kn.position = Vector2(nav_ox + col * (_key_w + _key_gap), sp_oy + r * (_key_h + _key_gap))
		kn.size = Vector2(_key_w, _key_h)
		_canvas.add_child(kn)
		_key_nodes.append(kn)
	
	var arrow_oy := sp_oy + 2 * (_key_h + _key_gap) + 10
	var arrow_map := [
		[1, 0, "^", "Up"], [0, 1, "<", "Left"],
		[1, 1, "v", "Down"], [2, 1, ">", "Right"],
	]
	for a in arrow_map:
		var kn = CyberKey.new()
		kn._init_key(a[2], a[3])
		kn.position = Vector2(nav_ox + a[0] * (_key_w + _key_gap), arrow_oy + a[1] * (_key_h + _key_gap))
		kn.size = Vector2(_key_w, _key_h)
		_canvas.add_child(kn)
		_key_nodes.append(kn)
	var arrow_bottom := arrow_oy + 2 * (_key_h + _key_gap)
	
	# ── 小键盘区 (Numpad) ──
	var num_ox := nav_ox + 3.5 * (_key_w + _key_gap) + 10
	_add_label("NUMPAD // 数值输入", num_ox, right_top_y - 16, Color.from_hsv(EventBus.ui_hue, 0.25, 0.55, 0.40))
	var num_oy := right_top_y
	
	# 小键盘布局: 5行 x 4列
	var nk_w := _key_w * 0.9
	var nk_h := _key_h * 0.9
	var nk_gap := _key_gap
	
	# Row 0: NumLock, /, *, -
	var num_row0 := [["NLk", "NumLock"], ["/", "Num/"], ["*", "Num*"], ["-", "Num-"]]
	for i in range(num_row0.size()):
		var kn = CyberKey.new()
		kn._init_key(num_row0[i][0], num_row0[i][1])
		kn.position = Vector2(num_ox + i * (nk_w + nk_gap), num_oy)
		kn.size = Vector2(nk_w, nk_h)
		_canvas.add_child(kn)
		_key_nodes.append(kn)
	num_oy += nk_h + nk_gap
	
	# Row 1: 7, 8, 9 + Num+ (2行高)
	var num_row1 := [["7", "Num7"], ["8", "Num8"], ["9", "Num9"]]
	for i in range(num_row1.size()):
		var kn = CyberKey.new()
		kn._init_key(num_row1[i][0], num_row1[i][1])
		kn.position = Vector2(num_ox + i * (nk_w + nk_gap), num_oy)
		kn.size = Vector2(nk_w, nk_h)
		_canvas.add_child(kn)
		_key_nodes.append(kn)
	var plus_kn = CyberKey.new()
	plus_kn._init_key("+", "Num+")
	plus_kn.position = Vector2(num_ox + 3 * (nk_w + nk_gap), num_oy)
	plus_kn.size = Vector2(nk_w, nk_h * 2 + nk_gap)
	_canvas.add_child(plus_kn)
	_key_nodes.append(plus_kn)
	num_oy += nk_h + nk_gap
	
	# Row 2: 4, 5, 6
	var num_row2 := [["4", "Num4"], ["5", "Num5"], ["6", "Num6"]]
	for i in range(num_row2.size()):
		var kn = CyberKey.new()
		kn._init_key(num_row2[i][0], num_row2[i][1])
		kn.position = Vector2(num_ox + i * (nk_w + nk_gap), num_oy)
		kn.size = Vector2(nk_w, nk_h)
		_canvas.add_child(kn)
		_key_nodes.append(kn)
	num_oy += nk_h + nk_gap
	
	# Row 3: 1, 2, 3 + NumEnter (2行高)
	var num_row3 := [["1", "Num1"], ["2", "Num2"], ["3", "Num3"]]
	for i in range(num_row3.size()):
		var kn = CyberKey.new()
		kn._init_key(num_row3[i][0], num_row3[i][1])
		kn.position = Vector2(num_ox + i * (nk_w + nk_gap), num_oy)
		kn.size = Vector2(nk_w, nk_h)
		_canvas.add_child(kn)
		_key_nodes.append(kn)
	var enter_kn = CyberKey.new()
	enter_kn._init_key("Ent", "Enter")
	enter_kn.position = Vector2(num_ox + 3 * (nk_w + nk_gap), num_oy)
	enter_kn.size = Vector2(nk_w, nk_h * 2 + nk_gap)
	_canvas.add_child(enter_kn)
	_key_nodes.append(enter_kn)
	num_oy += nk_h + nk_gap
	
	# Row 4: Num0 (2列宽) + Num.
	var zero_kn = CyberKey.new()
	zero_kn._init_key("0", "Num0")
	zero_kn.position = Vector2(num_ox, num_oy)
	zero_kn.size = Vector2(nk_w * 2 + nk_gap, nk_h)
	_canvas.add_child(zero_kn)
	_key_nodes.append(zero_kn)
	var dot_kn = CyberKey.new()
	dot_kn._init_key(".", "Num.")
	dot_kn.position = Vector2(num_ox + 2 * (nk_w + nk_gap), num_oy)
	dot_kn.size = Vector2(nk_w, nk_h)
	_canvas.add_child(dot_kn)
	_key_nodes.append(dot_kn)
	var numpad_bottom := num_oy + nk_h + nk_gap
	
	# ── 鼠标 (IO_DEVICE) ── 放在小键盘右侧
	var mouse_ox := num_ox + 4.5 * (nk_w + nk_gap) + 10
	var mouse_oy := right_top_y - 16
	_add_label("IO_DEVICE // 定位装置", mouse_ox, mouse_oy, Color.from_hsv(EventBus.ui_hue, 0.25, 0.55, 0.40))
	mouse_oy += 16
	_mouse_node = CyberMouse.new()
	_mouse_node.position = Vector2(mouse_ox, mouse_oy)
	_mouse_node.size = Vector2(140.0, 210.0)
	_canvas.add_child(_mouse_node)
	
	# 统一底部: 取所有元素的最大 Y
	_layout_bottom_y = maxf(main_kb_bottom, maxf(arrow_bottom, numpad_bottom))
	
	# ── 组合键排行区 (键盘下方空白, 延迟到布局完成后构建) ──
	_build_combo_section.call_deferred()

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
	
	var tick_c := Color.from_hsv(hue, 0.5, 0.8, 0.25)
	var cx := w * 0.5
	var i := -30
	while i <= 30:
		var tx := cx + i * 8.0
		var ty_len: float = 3.0 if i % 5 != 0 else 7.0
		if tx > c_l and tx < w - c_l:
			_frame_drawer.draw_line(Vector2(tx, 0), Vector2(tx, ty_len), tick_c, 1.0)
		i += 1
	
	var breathe := (sin(_time_passed * 4.0) * 0.5 + 0.5) * 0.6 + 0.4
	var br_c := Color.from_hsv(hue, 0.6, 0.9, 0.8 * breathe)
	_frame_drawer.draw_line(pts[5], pts[6], br_c, 3.0, true)
	_frame_drawer.draw_line(pts[2], pts[3], br_c, 3.0, true)
	
	var ll := 16.0
	_frame_drawer.draw_polyline(PackedVector2Array([
		pts[1] + Vector2(-ll, 0), pts[1], pts[1] + Vector2(0, ll)
	]), br_c, 3.0, true)
	_frame_drawer.draw_polyline(PackedVector2Array([
		pts[4] + Vector2(ll, 0), pts[4], pts[4] + Vector2(0, -ll)
	]), br_c, 3.0, true)

func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var hue := EventBus.ui_hue
	
	var w := _canvas.size.x
	var h := _canvas.size.y
	var gc := Color.from_hsv(hue, 0.12, 0.06, 0.10)
	var step := 40.0
	var xp := 0.0
	while xp < w:
		_canvas.draw_line(Vector2(xp, 0), Vector2(xp, h), gc, 1.0)
		xp += step
	var yp := 0.0
	while yp < h:
		_canvas.draw_line(Vector2(0, yp), Vector2(w, yp), gc, 1.0)
		yp += step
		
	var ox := _margin
	var oy := 4.0
	var stat_color := Color(0.55, 0.62, 0.72, 0.75)
	var val_color := Color.from_hsv(hue, 0.4, 0.90, 0.95)
	
	_canvas.draw_string(font, Vector2(ox, oy + 18), "KEYSTROKES //", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stat_color)
	_canvas.draw_string(font, Vector2(ox + 115, oy + 18), HeatUtil.format_count(_total_keys), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, val_color)
	
	_canvas.draw_string(font, Vector2(ox + 210, oy + 18), "CLICKS //", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stat_color)
	_canvas.draw_string(font, Vector2(ox + 298, oy + 18), HeatUtil.format_count(_total_mouse), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, val_color)
	
	if _top_key != "":
		_canvas.draw_string(font, Vector2(ox + 380, oy + 18), "PEAK //", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stat_color)
		var peak_text := "%s (%s)" % [_top_key, HeatUtil.format_count(_top_count)]
		_canvas.draw_string(font, Vector2(ox + 450, oy + 18), peak_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.from_hsv(0.10, 0.65, 0.95, 0.95))
	
	if _delta_mode:
		_canvas.draw_string(font, Vector2(ox + 620, oy + 18), "AVG //", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stat_color)
		_canvas.draw_string(font, Vector2(ox + 670, oy + 18), "%.1f" % _avg_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.from_hsv(0.55, 0.4, 0.90, 0.90))
	else:
		# 未使用/已使用键位统计
		var unused_ox := ox + 620
		if _unused_count > 0:
			_canvas.draw_string(font, Vector2(unused_ox, oy + 18), "IDLE //", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stat_color)
			_canvas.draw_string(font, Vector2(unused_ox + 55, oy + 18), "%d" % _unused_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.from_hsv(0.0, 0.45, 0.85, 0.80))
			_canvas.draw_string(font, Vector2(unused_ox + 95, oy + 18), "ACTIVE //", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, stat_color)
			_canvas.draw_string(font, Vector2(unused_ox + 170, oy + 18), "%d" % _active_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.from_hsv(0.35, 0.55, 0.90, 0.90))
	
	_canvas.draw_line(Vector2(ox, oy + 28), Vector2(ox + 950, oy + 28), Color.from_hsv(hue, 0.4, 0.5, 0.15), 1.0)
	
	var note: String
	if _subtitle_text != "":
		note = _subtitle_text
	elif _delta_mode:
		note = "-- 基准偏差模式: 偏蓝 = 低于均值, 偏橙 = 高于均值。不关我事。 --"
	else:
		note = "-- 本机仅做行为采集。数据解读是操作员的事。 --"
	_canvas.draw_string(font, Vector2(ox, oy + 44), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.40, 0.45, 0.55, 0.40))

## 构建组合键排行区域 (ScrollContainer + CyberScrollIndicator)
func _build_combo_section() -> void:
	var hue := EventBus.ui_hue
	var ox := _margin
	var oy := _layout_bottom_y + 10
	# 全宽: canvas 宽度减去两侧 margin
	var canvas_w := _canvas.size.x if is_instance_valid(_canvas) else _panel_w
	var area_w := canvas_w - _margin * 2
	# 可用高度
	var canvas_h := _canvas.size.y if is_instance_valid(_canvas) else _panel_h
	var available_h := canvas_h - oy - 8
	if available_h < 40:
		return
	
	# 区域标题
	_combo_label = Label.new()
	_combo_label.text = "COMBO_FREQ // 组合键频次"
	_combo_label.position = Vector2(ox, oy)
	_combo_label.add_theme_font_size_override("font_size", 11)
	_combo_label.add_theme_color_override("font_color", Color.from_hsv(hue, 0.25, 0.55, 0.40))
	_canvas.add_child(_combo_label)
	oy += 16
	
	# 分隔线 (全宽)
	_combo_sep = Control.new()
	_combo_sep.position = Vector2(ox, oy)
	_combo_sep.size = Vector2(area_w, 1)
	var sep_w := area_w  # 捕获到闭包
	_combo_sep.draw.connect(func():
		_combo_sep.draw_line(Vector2.ZERO, Vector2(sep_w, 0), Color.from_hsv(hue, 0.3, 0.4, 0.15), 1.0)
	)
	_canvas.add_child(_combo_sep)
	oy += 5
	
	# ScrollContainer (先不设绝对位置, 由 wrapper 管理)
	_combo_scroll = ScrollContainer.new()
	_combo_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_combo_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_combo_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_combo_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# 透明背景
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color.TRANSPARENT
	_combo_scroll.add_theme_stylebox_override("panel", scroll_bg)
	_canvas.add_child(_combo_scroll)
	
	# 内容容器
	_combo_vbox = VBoxContainer.new()
	_combo_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_combo_vbox.add_theme_constant_override("separation", 0)
	_combo_scroll.add_child(_combo_vbox)
	
	# 用项目统一的科幻滚动指示器替换原生滚动条
	_combo_wrapper = CyberScrollIndicator.wrap(_combo_scroll)
	# wrapper 继承绝对定位 (因为 _canvas 是手动布局)
	_combo_wrapper.position = Vector2(ox, oy)
	_combo_wrapper.size = Vector2(area_w, available_h - 22)
	
	# 构建完成后立即填充数据 (因为 set_data 可能已在 deferred 之前调用过)
	_rebuild_combo_list()

## 重建组合键列表
func _rebuild_combo_list() -> void:
	if not is_instance_valid(_combo_vbox):
		return
	# 清空旧内容
	for child in _combo_vbox.get_children():
		child.queue_free()
	
	# 显示/隐藏组合键区域
	var has_data := not _combo_data.is_empty()
	if is_instance_valid(_combo_label): _combo_label.visible = has_data
	if is_instance_valid(_combo_sep): _combo_sep.visible = has_data
	if is_instance_valid(_combo_wrapper): _combo_wrapper.visible = has_data
	if not has_data:
		return
	
	# 排序
	var sorted: Array = []
	for k in _combo_data:
		sorted.append([k, int(_combo_data[k])])
	sorted.sort_custom(func(a, b): return a[1] > b[1])
	
	var max_val: int = int(sorted[0][1]) if not sorted.is_empty() else 1
	var hue := EventBus.ui_hue
	
	# 全宽三栏布局
	var canvas_w := _canvas.size.x if is_instance_valid(_canvas) else _panel_w
	var area_w := canvas_w - _margin * 2 - 50  # 减去滚动指示器宽度
	var row_h := 18.0
	_build_combo_tri_col(sorted, max_val, hue, area_w, row_h)

## 三栏布局
func _build_combo_tri_col(sorted: Array, max_val: int, hue: float, area_w: float, row_h: float) -> void:
	var col_gap := 20.0
	var col_w := (area_w - col_gap * 2) / 3.0
	var third := ceili(sorted.size() / 3.0)
	
	for r in range(third):
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", int(col_gap))
		
		for c in range(3):
			var data_idx := r + c * third
			if data_idx < sorted.size():
				var item := _create_combo_row(data_idx, sorted[data_idx][0], int(sorted[data_idx][1]), max_val, hue, col_w, row_h)
				hbox.add_child(item)
			else:
				# 占位: 保持列宽一致
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(col_w, row_h)
				hbox.add_child(spacer)
		
		_combo_vbox.add_child(hbox)

## 创建单行组合键条目
func _create_combo_row(idx: int, combo_name: String, count: int, max_val: int, hue: float, w: float, h: float) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(w, h)
	row.size = Vector2(w, h)
	
	var t := clampf(float(count) / float(maxi(max_val, 1)), 0.0, 1.0)
	
	# 用 draw 一次性渲染整行
	row.draw.connect(func():
		var font := ThemeDB.fallback_font
		var dim_c := Color(0.45, 0.50, 0.58, 0.50)
		var name_c := Color(0.70, 0.78, 0.88, 0.82)
		var count_c := Color.from_hsv(hue, 0.35, 0.85, 0.80)
		
		# 序号
		var idx_text := "%d." % (idx + 1)
		row.draw_string(font, Vector2(0, h - 4), idx_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim_c)
		
		# 组合键名
		var name_ox := 22.0
		var name_w := font.get_string_size(combo_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		row.draw_string(font, Vector2(name_ox, h - 4), combo_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, name_c)
		
		# 次数
		var count_text := HeatUtil.format_count(count)
		var count_w := font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		row.draw_string(font, Vector2(w - count_w, h - 4), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, count_c)
		
		# 频次条 (名字后 8px 到次数前 8px)
		var bar_ox := name_ox + name_w + 8.0
		var bar_end := w - count_w - 8
		var bar_max_w := bar_end - bar_ox
		if bar_max_w > 10:
			var bar_y := h - 11.0
			var bar_h := 4.0
			var bar_bg := Color.from_hsv(hue, 0.15, 0.08, 0.20)
			row.draw_rect(Rect2(bar_ox, bar_y, bar_max_w, bar_h), bar_bg)
			var fill_w := bar_max_w * t
			if fill_w > 0.5:
				var fill_c := Color.from_hsv(hue, 0.40, 0.30, 0.50).lerp(Color.from_hsv(0.10, 0.55, 0.50, 0.65), t)
				row.draw_rect(Rect2(bar_ox, bar_y, fill_w, bar_h), fill_c)
	)
	return row

func _get_pet() -> Node:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instance" in main_node:
		return main_node.pet_instance
	return null

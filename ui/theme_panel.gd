# theme_panel.gd — 外观主题面板
# 管理: 宠物颜色 + UI 主题色的自定义
# 包含: 色轮(Canvas绘制) + 目标选择器 + S/V 滑块 + 预设色
extends CanvasLayer

const _PetColorPalette = preload("res://entities/pet/pet_color_palette.gd")

var panel: PanelContainer
var _pet: Node2D
var _guard_frames := 0

# ── 当前编辑状态 ──
var _target_index: int = 0   # 0=原体, 1~5=分身, -1=UI主题
var _current_hue: float = 0.62
var _current_sat: int = 50   # 0~100 (50=默认1.0x)
var _current_val: int = 50

# ── UI 引用 ──
var _target_btns: Array[Button] = []
var _wheel: Control
var _sat_slider: HSlider
var _val_slider: HSlider
var _sat_label: Label
var _val_label: Label
var _conflict_label: Label       # 撞色提示
var _title_label: Label          # 标题引用 (用于主题色同步)
var _dragging_wheel: bool = false

# ── 预设色调 ──
const PRESETS: Array[float] = [0.62, 0.78, 0.33, 0.0, 0.12, 0.92, 0.537, 0.08]
const PRESET_NAMES: Array[String] = ["蓝", "紫", "绿", "红", "金", "粉", "青", "橙"]

func _ready() -> void:
	layer = 102
	_build_ui()
	EventBus.show_theme_panel.connect(_toggle_panel)

# ── 主循环 ──

func _process(delta: float) -> void:
	if panel.visible and is_instance_valid(_pet):
		var pet_pos = _pet.get_global_transform_with_canvas().get_origin()
		var target_pos = pet_pos + Vector2(-panel.size.x / 2, -panel.size.y - 50)
		target_pos = _clamp_pos(target_pos)
		panel.position = panel.position.lerp(target_pos, delta * 10.0)
	if _guard_frames > 0:
		_guard_frames -= 1

func _clamp_pos(pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 8.0, vp.x - panel.size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - panel.size.y - 8.0)
	return pos

# ── UI 构建 ──

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.visible = false
	panel.custom_minimum_size = Vector2(280, 0)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.10, 0.95)
	style.border_color = Color.from_hsv(EventBus.ui_hue, 0.7, 1.0, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.shadow_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.1)
	style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	# 标题
	_title_label = Label.new()
	_title_label.text = "外观主题"
	_title_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 1.0, 0.9))
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)
	
	# 分割线
	vbox.add_child(_make_sep())
	
	# 目标选择器
	_build_target_selector(vbox)
	
	# 色轮
	_build_color_wheel(vbox)
	
	# 撞色提示
	_conflict_label = Label.new()
	_conflict_label.add_theme_font_size_override("font_size", 12)
	_conflict_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35, 0.9))
	_conflict_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_conflict_label.text = ""
	vbox.add_child(_conflict_label)
	
	# S/V 滑块
	_build_sliders(vbox)
	
	# 预设色
	vbox.add_child(_make_sep())
	_build_presets(vbox)
	
	# 重置按钮
	var reset_btn = Button.new()
	reset_btn.text = "重置默认"
	reset_btn.add_theme_font_size_override("font_size", 14)
	reset_btn.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75, 0.7))
	reset_btn.add_theme_color_override("font_hover_color", Color(0.9, 0.4, 0.35, 1))
	reset_btn.flat = true
	reset_btn.pressed.connect(_on_reset)
	vbox.add_child(reset_btn)

func _build_target_selector(parent: VBoxContainer) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(hbox)
	
	_target_btns.clear()
	# 原体按钮
	var btn0 = _make_target_btn("原体", 0)
	hbox.add_child(btn0)
	_target_btns.append(btn0)
	
	# 分身按钮 (动态，根据当前存在的克隆体数量)
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instances" in main_node:
		for i in range(1, main_node.pet_instances.size()):
			var btn = _make_target_btn("分身" + str(i), i)
			hbox.add_child(btn)
			_target_btns.append(btn)
	
	# UI 主题按钮
	var ui_btn = _make_target_btn("界面", -1)
	hbox.add_child(ui_btn)
	_target_btns.append(ui_btn)
	
	_refresh_target_highlight()

func _make_target_btn(text: String, index: int) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.custom_minimum_size = Vector2(48, 28)
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.12, 0.2, 0.6)
	s.set_corner_radius_all(14)
	s.set_border_width_all(1)
	s.border_color = Color(0.2, 0.3, 0.45, 0.4)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color(0.12, 0.18, 0.3, 0.8)
	h.border_color = Color(0.3, 0.5, 0.7, 0.6)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	
	var idx = index
	btn.pressed.connect(func(): _on_target_selected(idx))
	return btn

func _refresh_target_highlight() -> void:
	for btn in _target_btns:
		var s = btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		s.border_color = Color(0.2, 0.3, 0.45, 0.4)
		s.set_border_width_all(1)
		btn.add_theme_stylebox_override("normal", s)
	
	# 高亮当前选中
	for i in range(_target_btns.size()):
		var btn = _target_btns[i]
		var btn_index: int
		if i == _target_btns.size() - 1:
			btn_index = -1  # UI 按钮始终是最后一个
		else:
			btn_index = i
		if btn_index == _target_index:
			var s = btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
			s.border_color = Color.from_hsv(_current_hue, 0.8, 1.0, 0.9)
			s.set_border_width_all(2)
			btn.add_theme_stylebox_override("normal", s)

# ── 色轮 ──

func _build_color_wheel(parent: VBoxContainer) -> void:
	var center_box = CenterContainer.new()
	parent.add_child(center_box)
	
	_wheel = Control.new()
	_wheel.custom_minimum_size = Vector2(180, 180)
	_wheel.mouse_filter = Control.MOUSE_FILTER_STOP
	_wheel.draw.connect(_draw_wheel)
	_wheel.gui_input.connect(_wheel_input)
	center_box.add_child(_wheel)

func _draw_wheel() -> void:
	var size = _wheel.size
	var center = size / 2.0
	var outer_r = min(size.x, size.y) / 2.0 - 4
	var ring_w := 18.0
	var inner_r = outer_r - ring_w
	var mid_r = (outer_r + inner_r) / 2.0
	
	# HSV 色环 (120段)
	var seg := 120
	for i in range(seg):
		var a0 = float(i) / seg * TAU
		var a1 = float(i + 1) / seg * TAU
		var hue = float(i) / seg
		var c = Color.from_hsv(hue, 0.85, 1.0)
		_wheel.draw_arc(center, mid_r, a0, a1, 3, c, ring_w, true)
	
	# 中心预览圆
	var preview_r = inner_r * 0.55
	_wheel.draw_circle(center, preview_r + 2, Color(0.15, 0.2, 0.3, 0.8))
	var preview_s = clampf(0.85 * (float(_current_sat) / 100.0 + 0.5), 0.0, 1.0)
	var preview_v = clampf(1.0 * (float(_current_val) / 100.0 + 0.5), 0.0, 1.0)
	_wheel.draw_circle(center, preview_r, Color.from_hsv(_current_hue, preview_s, preview_v))
	
	# 选择指示器 (色环上的白色圆点)
	var sel_angle = _current_hue * TAU
	var sel_pos = center + Vector2(cos(sel_angle), sin(sel_angle)) * mid_r
	_wheel.draw_circle(sel_pos, 11, Color(0, 0, 0, 0.3))
	_wheel.draw_circle(sel_pos, 9, Color.WHITE)
	_wheel.draw_circle(sel_pos, 6, Color.from_hsv(_current_hue, 0.85, 1.0))

func _wheel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_pick_hue(event.position)
				_dragging_wheel = true
			else:
				_dragging_wheel = false
	elif event is InputEventMouseMotion and _dragging_wheel:
		_try_pick_hue(event.position)

func _try_pick_hue(pos: Vector2) -> void:
	var size = _wheel.size
	var center = size / 2.0
	var outer_r = min(size.x, size.y) / 2.0 - 4
	var inner_r = outer_r - 18.0
	var dist = pos.distance_to(center)
	
	# 允许比环稍宽的拖拽范围 (更容易操作)
	if dist >= inner_r - 10 and dist <= outer_r + 10:
		var angle = atan2(pos.y - center.y, pos.x - center.x)
		_current_hue = fmod(angle / TAU + 1.0, 1.0)
		_wheel.queue_redraw()
		_apply_color()

# ── 滑块 ──

func _build_sliders(parent: VBoxContainer) -> void:
	# 饱和度
	var sat_row = HBoxContainer.new()
	sat_row.add_theme_constant_override("separation", 8)
	parent.add_child(sat_row)
	
	var sat_tag = Label.new()
	sat_tag.text = "饱和度"
	sat_tag.add_theme_font_size_override("font_size", 13)
	sat_tag.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75, 0.7))
	sat_tag.custom_minimum_size.x = 50
	sat_row.add_child(sat_tag)
	
	_sat_slider = HSlider.new()
	_sat_slider.min_value = 0
	_sat_slider.max_value = 100
	_sat_slider.value = 50
	_sat_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sat_slider.value_changed.connect(func(v): _current_sat = int(v); _sat_label.text = str(int(v)); _wheel.queue_redraw(); _apply_color())
	sat_row.add_child(_sat_slider)
	
	_sat_label = Label.new()
	_sat_label.text = "50"
	_sat_label.add_theme_font_size_override("font_size", 13)
	_sat_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
	_sat_label.custom_minimum_size.x = 28
	sat_row.add_child(_sat_label)
	
	# 明度
	var val_row = HBoxContainer.new()
	val_row.add_theme_constant_override("separation", 8)
	parent.add_child(val_row)
	
	var val_tag = Label.new()
	val_tag.text = "明  度"
	val_tag.add_theme_font_size_override("font_size", 13)
	val_tag.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75, 0.7))
	val_tag.custom_minimum_size.x = 50
	val_row.add_child(val_tag)
	
	_val_slider = HSlider.new()
	_val_slider.min_value = 0
	_val_slider.max_value = 100
	_val_slider.value = 50
	_val_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_val_slider.value_changed.connect(func(v): _current_val = int(v); _val_label.text = str(int(v)); _wheel.queue_redraw(); _apply_color())
	val_row.add_child(_val_slider)
	
	_val_label = Label.new()
	_val_label.text = "50"
	_val_label.add_theme_font_size_override("font_size", 13)
	_val_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
	_val_label.custom_minimum_size.x = 28
	val_row.add_child(_val_label)

# ── 预设色 ──

func _build_presets(parent: VBoxContainer) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(hbox)
	
	for i in range(PRESETS.size()):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(26, 26)
		btn.tooltip_text = PRESET_NAMES[i]
		btn.flat = false
		btn.text = ""
		
		var s = StyleBoxFlat.new()
		s.bg_color = Color.from_hsv(PRESETS[i], 0.8, 0.9)
		s.set_corner_radius_all(13)
		s.set_border_width_all(2)
		s.border_color = Color(0.3, 0.35, 0.4, 0.5)
		btn.add_theme_stylebox_override("normal", s)
		
		var h = s.duplicate()
		h.border_color = Color.WHITE
		btn.add_theme_stylebox_override("hover", h)
		btn.add_theme_stylebox_override("pressed", h)
		
		var preset_hue = PRESETS[i]
		btn.pressed.connect(func(): _on_preset(preset_hue))
		hbox.add_child(btn)

# ── 事件处理 ──

func _on_target_selected(index: int) -> void:
	_target_index = index
	_load_target_color()
	_refresh_target_highlight()
	_wheel.queue_redraw()

func _load_target_color() -> void:
	if _target_index == -1:
		# UI 主题
		_current_hue = EventBus.ui_hue
		_current_sat = 50
		_current_val = 50
	else:
		var main_node = get_tree().root.get_node_or_null("Main")
		if main_node and "pet_instances" in main_node:
			var pets: Array = main_node.pet_instances
			if _target_index < pets.size() and is_instance_valid(pets[_target_index]):
				var p = pets[_target_index]
				_current_hue = p.palette.hue
				_current_sat = p.palette.get_sat_percent()
				_current_val = p.palette.get_val_percent()
	
	_sat_slider.set_value_no_signal(_current_sat)
	_val_slider.set_value_no_signal(_current_val)
	_sat_label.text = str(_current_sat)
	_val_label.text = str(_current_val)

func _on_preset(hue: float) -> void:
	_current_hue = hue
	_current_sat = 50
	_current_val = 50
	_sat_slider.set_value_no_signal(50)
	_val_slider.set_value_no_signal(50)
	_sat_label.text = "50"
	_val_label.text = "50"
	_wheel.queue_redraw()
	_apply_color()

func _on_reset() -> void:
	if _target_index == -1:
		_on_preset(0.537)  # UI 默认青色
	elif _target_index == 0:
		_on_preset(_PetColorPalette.DEFAULT_HUE)  # 原体默认蓝色
	else:
		# 分身：重新随机一个不撞色的色调
		_on_preset(_generate_distinct_hue())

## 生成与现有宠物色调不撞的随机 hue
func _generate_distinct_hue() -> float:
	var existing: Array[float] = []
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instances" in main_node:
		for i in range(main_node.pet_instances.size()):
			var p = main_node.pet_instances[i]
			if is_instance_valid(p) and p.palette and i != _target_index:
				existing.append(p.palette.hue)
	for _attempt in range(20):
		var candidate = randf()
		var ok = true
		for h in existing:
			var d = absf(candidate - h)
			if minf(d, 1.0 - d) < 0.08:
				ok = false
				break
		if ok:
			return candidate
	return randf()

func _apply_color() -> void:
	_refresh_target_highlight()
	if _target_index == -1:
		# UI 主题色
		EventBus.ui_hue = _current_hue
		EventBus.ui_theme_changed.emit(_current_hue)
		SettingsManager.set_ui_hue(int(_current_hue * 360.0))
		# 同步面板自身的边框和标题
		_sync_panel_theme(_current_hue)
		_conflict_label.text = ""
	else:
		# 宠物颜色
		var sat_scale = clampf(float(_current_sat) / 100.0 + 0.5, 0.5, 1.5)
		var val_scale = clampf(float(_current_val) / 100.0 + 0.5, 0.5, 1.5)
		EventBus.pet_color_changed.emit(_target_index, _current_hue, sat_scale, val_scale)
		SettingsManager.set_pet_color(_target_index, int(_current_hue * 360.0), _current_sat, _current_val)
		# 撞色检测
		_check_color_conflict()

## 检测当前选色是否与其他宠物过于接近
func _check_color_conflict() -> void:
	var main_node = get_tree().root.get_node_or_null("Main")
	if not main_node or not "pet_instances" in main_node:
		_conflict_label.text = ""
		return
	var pets: Array = main_node.pet_instances
	var closest_name := ""
	var closest_dist := 1.0
	for i in range(pets.size()):
		if i == _target_index or not is_instance_valid(pets[i]) or not pets[i].palette:
			continue
		var other_hue = pets[i].palette.hue
		var d = absf(_current_hue - other_hue)
		d = minf(d, 1.0 - d)
		if d < closest_dist:
			closest_dist = d
			closest_name = "原体" if i == 0 else ("分身" + str(i))
	if closest_dist < 0.06:
		_conflict_label.text = "* 与「" + closest_name + "」色调非常接近"
	elif closest_dist < 0.10:
		_conflict_label.text = "* 与「" + closest_name + "」色调较接近"
	else:
		_conflict_label.text = ""

## 同步面板自身的边框和标题色 (界面主题变更时)
func _sync_panel_theme(hue: float) -> void:
	var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style = style.duplicate()
		style.border_color = Color.from_hsv(hue, 0.7, 1.0, 0.6)
		style.shadow_color = Color.from_hsv(hue, 0.5, 0.8, 0.1)
		panel.add_theme_stylebox_override("panel", style)
	if _title_label:
		_title_label.add_theme_color_override("font_color", Color.from_hsv(hue, 0.5, 1.0, 0.9))

# ── 面板显隐 ──

func _toggle_panel() -> void:
	if panel.visible:
		_close_panel()
	else:
		_open_panel()

func _open_panel() -> void:
	_find_pet()
	_target_index = 0
	_load_target_color()
	# 刷新目标选择器 (分身可能变了)
	var parent_vbox = panel.get_child(0).get_child(0)
	var old_selector = parent_vbox.get_child(2)  # 目标选择器在 title, sep 之后
	old_selector.queue_free()
	await get_tree().process_frame
	var new_hbox = HBoxContainer.new()
	new_hbox.add_theme_constant_override("separation", 6)
	new_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_target_btns.clear()
	var btn0 = _make_target_btn("原体", 0)
	new_hbox.add_child(btn0)
	_target_btns.append(btn0)
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instances" in main_node:
		for i in range(1, main_node.pet_instances.size()):
			var btn = _make_target_btn("分身" + str(i), i)
			new_hbox.add_child(btn)
			_target_btns.append(btn)
	var ui_btn = _make_target_btn("界面", -1)
	new_hbox.add_child(ui_btn)
	_target_btns.append(ui_btn)
	parent_vbox.add_child(new_hbox)
	parent_vbox.move_child(new_hbox, 2)
	_refresh_target_highlight()
	
	EventBus.context_menu_toggled.emit(true)
	if is_instance_valid(_pet):
		var pet_pos = _pet.get_global_transform_with_canvas().get_origin()
		panel.position = pet_pos + Vector2(-140, -panel.size.y - 50)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.6, 0.6)
	panel.show()
	await get_tree().process_frame
	panel.pivot_offset = panel.size / 2.0
	_guard_frames = 5
	_wheel.queue_redraw()
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

func _close_panel() -> void:
	panel.pivot_offset = panel.size / 2.0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.15)
	tween.tween_property(panel, "scale", Vector2(0.5, 0.5), 0.15)
	tween.finished.connect(func():
		panel.hide()
		EventBus.context_menu_toggled.emit(false)
	)

func _find_pet() -> void:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instance" in main_node:
		_pet = main_node.pet_instance

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible or _guard_frames > 0:
		return
	if event is InputEventMouseButton and event.pressed:
		var local_mouse = panel.get_local_mouse_position()
		var rect = Rect2(Vector2.ZERO, panel.size)
		if not rect.has_point(local_mouse):
			_close_panel()

# ── 工具 ──

func _make_sep() -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

# pet_profile_panel.gd — 装置终端面板 (骨架)
# 职责: 面板框架、标题栏、Tab 切换、围栏物理、开关动画
# 内容模块: ui/profile/ 目录下的独立文件
extends CanvasLayer

# ── 面板尺寸 ──
var _panel_w: float = 750
var _panel_h: float = 520

# ── 引用 ──
var panel: PanelContainer
var _title_bar: Control
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _tab_btns: Array[Button] = []
var _tab_contents: Array[Control] = []
var _current_tab: int = 0
var _left_column  # ProfileLeftColumn
var _is_open: bool = false

var _fx_mode: int = 0
var _fx_btn: Button
var _fx_names: Array[String] = ["特效: 故障", "特效: 关闭"]
var _glitch_mat: ShaderMaterial

var _transition_rect: ColorRect
var _tab_tween: Tween
var _tab_btn_tweens: Array[Tween] = []

var _frame_drawer: Control
var _time_passed: float = 0.0

# ── 档案围栏 ──
var _confine_walls: Array[StaticBody2D] = []

func _ready() -> void:
	_calc_panel_size()
	_build_ui()
	EventBus.show_pet_profile.connect(_on_toggle)
	EventBus.show_pet_profile_reminder.connect(_on_show_reminder_tab)
	EventBus.ui_theme_changed.connect(_on_ui_theme_changed)

func _calc_panel_size() -> void:
	var vp = get_viewport().get_visible_rect().size
	_panel_w = clampf(vp.x * 0.80, 850, 1600)
	_panel_h = clampf(vp.y * 0.80, 600, 1000)

func _clamp_pos(pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - _panel_w - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - _panel_h - 4.0))
	return pos

# ═══════════════════════════════════════════════
#  主循环
# ═══════════════════════════════════════════════

func _process(delta: float) -> void:
	if panel and _is_open:
		_time_passed += delta
		if is_instance_valid(_frame_drawer):
			_frame_drawer.queue_redraw()
		if _confine_walls.size() > 0:
			_sync_confine_walls()
		var pet = _get_pet()
		if pet:
			pet.overlay_rect = Rect2(panel.position, Vector2(_panel_w, _panel_h))

# ═══════════════════════════════════════════════
#  UI 构建
# ═══════════════════════════════════════════════

func _build_ui() -> void:
	layer = -1

	# ── 面板容器 ──
	panel = PanelContainer.new()
	panel.visible = false
	panel.custom_minimum_size = Vector2(_panel_w, _panel_h)
	var ps = StyleBoxEmpty.new()
	panel.add_theme_stylebox_override("panel", ps)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)

	_frame_drawer = Control.new()
	_frame_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_drawer.draw.connect(_on_frame_drawer_draw)
	panel.add_child(_frame_drawer)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 32)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(margin)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(outer)

	# ── 标题栏 ──
	_title_bar = _build_title_bar()
	outer.add_child(_title_bar)

	# ── 分隔线 ──
	var hsep = HSeparator.new()
	hsep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	hsep.add_theme_constant_override("separation", 1)
	hsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(hsep)

	# ── 双栏主体 ──
	var split = HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(split)

	# ── 左栏 (模块) ──
	_left_column = preload("res://ui/profile/profile_left_column.gd").new()
	_left_column.build()
	split.add_child(_left_column)

	# ── 竖分隔线 ──
	var vsep = VSeparator.new()
	var vs_s = StyleBoxFlat.new()
	vs_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.2)
	vs_s.set_content_margin_all(0)
	vsep.add_theme_stylebox_override("separator", vs_s)
	vsep.add_theme_constant_override("separation", 1)
	vsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.add_child(vsep)

	# ── 右栏 ──
	var right_col = VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.mouse_filter = Control.MOUSE_FILTER_PASS
	split.add_child(right_col)

	# 标签栏
	var tab_bar = _build_tab_bar()
	right_col.add_child(tab_bar)

	# 标签内容区
	var tab_content_area = PanelContainer.new()
	tab_content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tca_s = StyleBoxFlat.new()
	tca_s.bg_color = Color(0.02, 0.03, 0.06, 0.5)
	tca_s.set_corner_radius_all(0)
	tca_s.set_content_margin_all(12)
	tab_content_area.add_theme_stylebox_override("panel", tca_s)
	tab_content_area.mouse_filter = Control.MOUSE_FILTER_PASS
	ProfileStyles.add_tech_brackets(tab_content_area, 5.0, 0.0)
	right_col.add_child(tab_content_area)

	var tab_stack = Control.new()
	tab_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	tab_content_area.add_child(tab_stack)

	# ── 注册 Tab 模块 ──
	var tab0 = preload("res://ui/profile/profile_tab_records.gd").new()
	tab0.build()
	tab0.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_stack.add_child(tab0)
	_tab_contents.append(tab0)

	var tab1 = preload("res://ui/profile/profile_tab_ability.gd").new()
	tab1.build()
	tab1.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_stack.add_child(tab1)
	_tab_contents.append(tab1)

	var tab2 = preload("res://ui/profile/profile_tab_reminder.gd").new()
	tab2.build()
	tab2.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_stack.add_child(tab2)
	_tab_contents.append(tab2)

	var tab3 = preload("res://ui/profile/datalog/datalog_tab.gd").new()
	tab3.build()
	tab3.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_stack.add_child(tab3)
	_tab_contents.append(tab3)

	var tab4 = preload("res://ui/profile/profile_tab_theme.gd").new()
	tab4.build()
	tab4.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_stack.add_child(tab4)
	_tab_contents.append(tab4)

	var tab5 = preload("res://ui/profile/profile_tab_syscheck.gd").new()
	tab5.build()
	tab5.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_stack.add_child(tab5)
	_tab_contents.append(tab5)

	var tab6 = preload("res://ui/profile/profile_tab_about.gd").new()
	tab6.build()
	tab6.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_stack.add_child(tab6)
	_tab_contents.append(tab6)

	var tab7 = preload("res://ui/profile/profile_tab_config.gd").new()
	tab7.build()
	tab7.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_stack.add_child(tab7)
	_tab_contents.append(tab7)

	# ── 转场特效覆盖层 ──
	_transition_rect = ColorRect.new()
	_transition_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_rect.visible = false
	
	_glitch_mat = ShaderMaterial.new()
	_glitch_mat.shader = load("res://ui/profile/glitch_transition.gdshader")
	_glitch_mat.set_shader_parameter("glitch_power", 0.0)

	_transition_rect.material = _glitch_mat
	tab_stack.add_child(_transition_rect)

	_switch_tab(0, true)

# ═══════════════════════════════════════════════
#  标题栏
# ═══════════════════════════════════════════════

func _build_title_bar() -> Control:
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.gui_input.connect(_on_title_bar_input)

	var title = Label.new()
	title.text = "装置终端"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.70, 0.80, 0.92, 0.9))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4, 0.7))
	close_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.4, 0.35, 1.0))
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.08, 0.08, 0.5)
	cs.set_corner_radius_all(4)
	cs.set_border_width_all(1)
	cs.border_color = Color(0.5, 0.2, 0.2, 0.3)
	cs.content_margin_left = 10; cs.content_margin_right = 10
	cs.content_margin_top = 3; cs.content_margin_bottom = 3
	close_btn.add_theme_stylebox_override("normal", cs)
	var ch = cs.duplicate()
	ch.bg_color = Color(0.25, 0.1, 0.1, 0.7)
	ch.border_color = Color(0.8, 0.3, 0.3, 0.5)
	close_btn.add_theme_stylebox_override("hover", ch)
	close_btn.add_theme_stylebox_override("pressed", ch)
	close_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	close_btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			_close_panel()
	)
	bar.add_child(close_btn)

	return bar

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			_dragging = true
			_drag_offset = panel.get_global_mouse_position() - panel.position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		# 安全检查: 鼠标左键没按住说明松手事件丢失了，自动取消拖拽
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_dragging = false
			return
		panel.position = _clamp_pos(panel.get_global_mouse_position() - _drag_offset)

# ═══════════════════════════════════════════════
#  标签切换
# ═══════════════════════════════════════════════

func _build_tab_bar() -> HBoxContainer:
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)

	var tabs = ["游戏战绩", "能力数据", "定时提醒", "数据日志", "外观主题", "机体诊断", "关于", "终端配置"]
	
	for i in range(tabs.size()):
		var btn = Button.new()
		btn.text = tabs[i]
		btn.add_theme_font_size_override("font_size", 15)
		btn.flat = false
		
		# 使用唯一的 StyleBox 以便用 Tween 进行平滑色彩插值
		var s = StyleBoxFlat.new()
		s.set_corner_radius_all(0)
		s.border_width_bottom = 2
		s.border_color = Color(0, 0, 0, 0)
		s.content_margin_left = 8; s.content_margin_right = 8
		s.content_margin_top = 6; s.content_margin_bottom = 6
		s.bg_color = Color(0.06, 0.08, 0.14, 0.3)
		
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_stylebox_override("hover", s)   # 共用实例，废弃引擎自带硬切
		btn.add_theme_stylebox_override("pressed", s) 
		btn.add_theme_stylebox_override("focus", s)
		btn.add_theme_color_override("font_color", Color(0.50, 0.60, 0.70, 0.7))
		btn.add_theme_color_override("font_hover_color", Color(0.50, 0.60, 0.70, 0.7))
		btn.add_theme_color_override("font_pressed_color", Color(0.50, 0.60, 0.70, 0.7))
		
		var idx = i
		btn.pressed.connect(func(): _switch_tab(idx))
		btn.mouse_entered.connect(func(): _animate_tab_btn(idx, true))
		btn.mouse_exited.connect(func(): _animate_tab_btn(idx, false))
		
		_tab_btns.append(btn)
		bar.add_child(btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_fx_btn = Button.new()
	_fx_btn.text = _fx_names[_fx_mode]
	_fx_btn.add_theme_font_size_override("font_size", 13)
	var fs = StyleBoxFlat.new()
	fs.bg_color = Color(0.1, 0.4, 0.2, 0.4)
	fs.set_corner_radius_all(3)
	fs.content_margin_left = 12; fs.content_margin_right = 12
	fs.border_width_bottom = 2; fs.border_color = Color(0.2, 0.7, 0.4)
	_fx_btn.add_theme_stylebox_override("normal", fs)
	_fx_btn.add_theme_stylebox_override("hover", fs)
	_fx_btn.add_theme_stylebox_override("pressed", fs)
	_fx_btn.pressed.connect(func():
		_fx_mode = (_fx_mode + 1) % 2
		_fx_btn.text = _fx_names[_fx_mode]
	)
	bar.add_child(_fx_btn)

	return bar

func _switch_tab(idx: int, instant: bool = false) -> void:
	if idx == _current_tab and _tab_contents.size() > 0 and _tab_contents[_current_tab].visible and not instant:
		return

	if instant or not is_instance_valid(_transition_rect) or not _is_open:
		_current_tab = idx
		for i in range(_tab_contents.size()):
			_tab_contents[i].visible = (i == idx)
		_refresh_tab_styles()
		return

	if _tab_tween and _tab_tween.is_valid():
		_tab_tween.kill()

	# 先更新按钮的高亮状态让点击有即时反馈
	_current_tab = idx
	_refresh_tab_styles()

	if _fx_mode == 1:
		# 兜底：无动效切换
		if is_instance_valid(_transition_rect):
			_transition_rect.visible = false
		for i in range(_tab_contents.size()):
			_tab_contents[i].visible = (i == idx)
		return

	_tab_tween = create_tween()
	_transition_rect.visible = true

	if _fx_mode == 0:
		_transition_rect.material = _glitch_mat
		_tab_tween.tween_method(func(v): _transition_rect.material.set_shader_parameter("glitch_power", v), 0.0, 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tab_tween.tween_callback(func():
			for i in range(_tab_contents.size()):
				_tab_contents[i].visible = (i == idx)
		)
		_tab_tween.tween_method(func(v): _transition_rect.material.set_shader_parameter("glitch_power", v), 1.0, 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tab_tween.tween_callback(func():
			_transition_rect.visible = false
		)

func _refresh_tab_styles() -> void:
	if _tab_btn_tweens.size() < _tab_btns.size():
		_tab_btn_tweens.resize(_tab_btns.size())
	for i in range(_tab_btns.size()):
		var btn = _tab_btns[i]
		# 强制手动触发刷新
		_animate_tab_btn(i, btn.is_hovered() if btn.has_method("is_hovered") else false)

func _animate_tab_btn(idx: int, is_hovered: bool) -> void:
	if idx < 0 or idx >= _tab_btns.size(): return
	var btn = _tab_btns[idx]
	var is_active = (idx == _current_tab)
	
	if _tab_btn_tweens.size() <= idx:
		_tab_btn_tweens.resize(idx + 1)
		
	if _tab_btn_tweens[idx] and _tab_btn_tweens[idx].is_valid():
		_tab_btn_tweens[idx].kill()
		
	var t = create_tween().set_parallel(true)
	_tab_btn_tweens[idx] = t
	
	var s = btn.get_theme_stylebox("normal") as StyleBoxFlat
	if not s: return
	
	var accent = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85)
	var target_bg: Color
	var target_border: Color
	var target_font: Color
	
	if is_active:
		target_bg = Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15, 0.6)
		target_border = accent
		target_font = Color(0.85, 0.92, 1.0, 1.0)
	else:
		if is_hovered:
			target_bg = Color(0.10, 0.12, 0.20, 0.5)
			# 悬停时透出幽弱的主题底边
			target_border = accent * Color(1.0, 1.0, 1.0, 0.3) 
			target_font = Color(0.60, 0.70, 0.80, 0.9)
		else:
			target_bg = Color(0.06, 0.08, 0.14, 0.3)
			target_border = Color(0, 0, 0, 0)
			target_font = Color(0.50, 0.60, 0.70, 0.7)
			
	var duration = 0.2
	t.tween_property(s, "bg_color", target_bg, duration).set_trans(Tween.TRANS_SINE)
	t.tween_property(s, "border_color", target_border, duration).set_trans(Tween.TRANS_SINE)
	
	var current_font = btn.get_theme_color("font_color")
	t.tween_method(func(c): 
		btn.add_theme_color_override("font_color", c)
		btn.add_theme_color_override("font_hover_color", c)
		btn.add_theme_color_override("font_pressed_color", c)
	, current_font, target_font, duration).set_trans(Tween.TRANS_SINE)

# ═══════════════════════════════════════════════
#  面板开关
# ═══════════════════════════════════════════════

func _on_toggle() -> void:
	if panel.visible:
		_close_panel()
	else:
		_open_panel()

func _open_panel() -> void:
	_is_open = true
	_refresh_data()
	var vp = get_viewport().get_visible_rect().size
	panel.position = _clamp_pos(Vector2(
		(vp.x - _panel_w) * 0.5,
		(vp.y - _panel_h) * 0.5
	))
	panel.pivot_offset = Vector2(_panel_w * 0.5, _panel_h * 0.5)
	panel.scale = Vector2(0.85, 0.85)
	panel.modulate.a = 0.0
	panel.show()
	_create_confine_walls()
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _close_panel() -> void:
	_is_open = false
	_dragging = false
	_destroy_confine_walls()
	var pet = _get_pet()
	if pet:
		pet.overlay_rect = Rect2()
	panel.pivot_offset = panel.size / 2.0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.1)
	tween.tween_property(panel, "scale", Vector2(0.85, 0.85), 0.1)
	tween.finished.connect(func():
		panel.hide()
	)

func _refresh_data() -> void:
	# 刷新左栏
	if _left_column and _left_column.has_method("refresh"):
		_left_column.refresh()
	# 刷新各 Tab
	for tab in _tab_contents:
		if is_instance_valid(tab) and tab.has_method("refresh"):
			tab.refresh()
	_switch_tab(_current_tab, true)

# ═══════════════════════════════════════════════
#  档案围栏 (单向碰撞墙)
# ═══════════════════════════════════════════════

func _get_pet() -> Node:
	var main_n = get_tree().root.get_node_or_null("Main")
	if main_n and "pet_instances" in main_n and main_n.pet_instances.size() > 0:
		return main_n.pet_instances[0]
	return null

func _get_main_node() -> Node:
	return get_tree().root.get_node_or_null("Main")

func _create_confine_walls() -> void:
	_destroy_confine_walls()
	var main_node = _get_main_node()
	if not main_node:
		return
	var rect = Rect2(panel.position, Vector2(_panel_w, _panel_h))
	var t := 6.0
	_confine_walls.append(_make_wall(main_node,
		Vector2(rect.position.x + rect.size.x / 2, rect.end.y),
		Vector2(rect.size.x, t), 0.0))
	_confine_walls.append(_make_wall(main_node,
		Vector2(rect.position.x + rect.size.x / 2, rect.position.y),
		Vector2(rect.size.x, t), PI))
	_confine_walls.append(_make_wall(main_node,
		Vector2(rect.position.x, rect.position.y + rect.size.y / 2),
		Vector2(rect.size.y, t), PI / 2))
	_confine_walls.append(_make_wall(main_node,
		Vector2(rect.end.x, rect.position.y + rect.size.y / 2),
		Vector2(rect.size.y, t), -PI / 2))

func _make_wall(parent: Node, pos: Vector2, shape_size: Vector2, rot: float) -> StaticBody2D:
	var wall = StaticBody2D.new()
	wall.position = pos
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = shape_size
	col.shape = shape
	col.one_way_collision = true
	col.one_way_collision_margin = 20.0
	col.rotation = rot
	wall.add_child(col)
	parent.add_child(wall)
	return wall

func _sync_confine_walls() -> void:
	if _confine_walls.size() != 4:
		return
	var rect = Rect2(panel.position, Vector2(_panel_w, _panel_h))
	_confine_walls[0].position = Vector2(rect.position.x + rect.size.x / 2, rect.end.y)
	_confine_walls[1].position = Vector2(rect.position.x + rect.size.x / 2, rect.position.y)
	_confine_walls[2].position = Vector2(rect.position.x, rect.position.y + rect.size.y / 2)
	_confine_walls[3].position = Vector2(rect.end.x, rect.position.y + rect.size.y / 2)

func _destroy_confine_walls() -> void:
	for wall in _confine_walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_confine_walls.clear()

# ═══════════════════════════════════════════════
#  自定义机能画板渲染
# ═══════════════════════════════════════════════

func _on_frame_drawer_draw() -> void:
	if not _frame_drawer: return
	var hue = EventBus.ui_hue
	var w = _frame_drawer.size.x
	var h = _frame_drawer.size.y
	
	# 1. 计算六边形切角多边形
	var c_l = 30.0 # 切角段尺寸
	var pts = PackedVector2Array()
	pts.append(Vector2(c_l, 0))          # 左上结束
	pts.append(Vector2(w, 0))            # 右上顶点 (不切)
	pts.append(Vector2(w, h - c_l))      # 右下开始
	pts.append(Vector2(w - c_l, h))      # 右下结束
	pts.append(Vector2(0, h))            # 左下顶点 (不切)
	pts.append(Vector2(0, c_l))          # 左上开始
	pts.append(Vector2(c_l, 0))          # 闭合
	
	# 2. 绘制深色磨砂背景
	var bg_c = Color(0.03, 0.05, 0.09, 0.95)
	_frame_drawer.draw_polygon(pts, PackedColorArray([bg_c]))
	
	# 3. 绘制主边界线
	var border_c = Color.from_hsv(hue, 0.4, 0.7, 0.4)
	_frame_drawer.draw_polyline(pts, border_c, 1.2, true)
	
	# 4. 绘制机甲边缘刻度线 (Tick Marks)
	var tick_c = Color.from_hsv(hue, 0.5, 0.8, 0.3)
	var cx = w * 0.5
	for i in range(-25, 26):
		var tx = cx + i * 8.0
		var ty_len = 3.0 if i % 5 != 0 else 7.0
		if tx > c_l and tx < w - c_l:
			_frame_drawer.draw_line(Vector2(tx, 0), Vector2(tx, ty_len), tick_c, 1.0)
			
	var cy = h * 0.5
	for i in range(-15, 16):
		var ty = cy + i * 8.0
		var tx_len = 3.0 if i % 5 != 0 else 7.0
		if ty > c_l and ty < h - c_l:
			_frame_drawer.draw_line(Vector2(0, ty), Vector2(tx_len, ty), tick_c, 1.0)
			
	# 5. 动态心跳呼吸锁扣
	var breathe = (sin(_time_passed * 4.0) * 0.5 + 0.5) * 0.6 + 0.4 # 0.4 ~ 1.0
	var br_c = Color.from_hsv(hue, 0.6, 0.9, 0.8 * breathe)
	var br_lw = 3.0
	
	# 切角加持
	_frame_drawer.draw_line(pts[5], pts[6], br_c, br_lw, true) # 左上切角
	_frame_drawer.draw_line(pts[2], pts[3], br_c, br_lw, true) # 右下切角
	
	# 直角加持 (小 L 型托座)
	var L_len = 16.0
	_frame_drawer.draw_polyline(PackedVector2Array([
		pts[1] + Vector2(-L_len, 0), pts[1], pts[1] + Vector2(0, L_len)
	]), br_c, br_lw, true)
	_frame_drawer.draw_polyline(PackedVector2Array([
		pts[4] + Vector2(L_len, 0), pts[4], pts[4] + Vector2(0, -L_len)
	]), br_c, br_lw, true)
	
	# 6. 电流游走 (Data Flow Runner)
	var total_len = 0.0
	var segs = []
	for i in range(6):
		var p1 = pts[i]
		var p2 = pts[i+1]
		var d = p1.distance_to(p2)
		segs.append({ "p1": p1, "p2": p2, "dist": d, "offset": total_len })
		total_len += d
		
	var runner_len = 150.0 # 游走电流长度
	var speed = 700.0 # px/s
	var current_head = fmod(_time_passed * speed, total_len)
	var highlight_c = Color.from_hsv(hue, 0.4, 0.95, 0.9)
	var glow_c = Color.from_hsv(hue, 0.6, 0.95, 0.3)
	
	for wrap in range(-1, 2):
		var head = current_head + wrap * total_len
		var tail = head - runner_len
		if tail >= total_len or head <= 0:
			continue
			
		var start_d = maxf(0.0, tail)
		var end_d = minf(total_len, head)
		
		for seg in segs:
			var s_offset = seg.offset
			var e_offset = seg.offset + seg.dist
			if end_d <= s_offset or start_d >= e_offset:
				continue
				
			var t_start = maxf(0.0, start_d - s_offset) / seg.dist
			var t_end = minf(seg.dist, end_d - s_offset) / seg.dist
			var p_s = seg.p1.lerp(seg.p2, t_start)
			var p_e = seg.p1.lerp(seg.p2, t_end)
			
			_frame_drawer.draw_line(p_s, p_e, glow_c, 6.0, true)
			_frame_drawer.draw_line(p_s, p_e, highlight_c, 2.0, true)

# ═══════════════════════════════════════════════
#  UI 主题色同步
# ═══════════════════════════════════════════════

func _on_ui_theme_changed(hue: float) -> void:
	_refresh_tab_styles()

## 从菜单直接跳到定时提醒 Tab
func _on_show_reminder_tab() -> void:
	if not panel.visible:
		_open_panel()
	_switch_tab(2)

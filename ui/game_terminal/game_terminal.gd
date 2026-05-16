# game_terminal.gd — 游戏终端面板 (骨架)
# 职责: 面板框架、标题栏、内容区域、围栏物理、开关动画
# 视觉定位: "战术终端" — 对称八角切角 + 扫描线 + 靶向准星
# 内容模块: ui/game_terminal/ 目录下的独立文件
extends CanvasLayer

# ── 终端状态枚举 ──
enum TerminalState { CLOSED, LOBBY, LOADING, PLAYING, PAUSED, RESULT }

# ── 面板尺寸 ──
var _panel_w: float = 700
var _panel_h: float = 520

# ── 引用 ──
var panel: SubViewportContainer        # 外层容器 (拖拽/动画/围栏的目标)
var _panel_viewport: SubViewport       # 面板渲染视口 (纹理捕获源 → 全息屏)
var _panel_inner: PanelContainer       # 内层面板 (实际 UI 内容)
var _title_bar: Control
var _title_label: Label
var _status_label: Label
var _hud_bar: PanelContainer        # 顶部 HUD 槽位
var _content_area: PanelContainer   # 中央内容区
var _content_stack: Control         # 内容区堆叠容器
var _footer_bar: PanelContainer     # 底部操作栏
var _footer_hbox: HBoxContainer     # 底栏内容
var _lobby_placeholder: Control     # 大厅占位视觉
var _active_game: Control = null    # 当前活跃游戏控件
var _active_game_name: String = "" # 当前游戏名称
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _is_open: bool = false
var _state: int = TerminalState.CLOSED

var _frame_drawer: Control
var _time_passed: float = 0.0

# ── 围栏 ──
var _confine_walls: Array[StaticBody2D] = []

# ═══════════════════════════════════════════════
#  生命周期
# ═══════════════════════════════════════════════

func _ready() -> void:
	_calc_panel_size()
	_build_ui()
	EventBus.show_game_terminal.connect(_on_toggle)
	EventBus.ui_theme_changed.connect(_on_ui_theme_changed)

func _calc_panel_size() -> void:
	var vp = get_viewport().get_visible_rect().size
	_panel_w = clampf(vp.x * 0.60, 620, 1100)
	_panel_h = clampf(vp.y * 0.72, 480, 860)

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

	# ── 外层: SubViewportContainer (拖拽/动画/围栏的目标) ──
	panel = SubViewportContainer.new()
	panel.visible = false
	panel.custom_minimum_size = Vector2(_panel_w, _panel_h)
	panel.size = Vector2(_panel_w, _panel_h)
	panel.stretch = true
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)

	# ── 渲染视口 (全局纹理捕获源 → 全息屏) ──
	_panel_viewport = SubViewport.new()
	_panel_viewport.size = Vector2i(int(_panel_w), int(_panel_h))
	_panel_viewport.transparent_bg = true
	_panel_viewport.handle_input_locally = true
	_panel_viewport.gui_disable_input = false
	_panel_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	panel.add_child(_panel_viewport)

	# ── 内层: PanelContainer (实际 UI 内容) ──
	_panel_inner = PanelContainer.new()
	_panel_inner.custom_minimum_size = Vector2(_panel_w, _panel_h)
	_panel_inner.size = Vector2(_panel_w, _panel_h)
	var ps = StyleBoxEmpty.new()
	_panel_inner.add_theme_stylebox_override("panel", ps)
	_panel_inner.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel_viewport.add_child(_panel_inner)

	# ── 自定义边框绘制层 ──
	_frame_drawer = Control.new()
	_frame_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_drawer.draw.connect(_on_frame_draw)
	_panel_inner.add_child(_frame_drawer)

	# ── 外边距容器 ──
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 28)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel_inner.add_child(margin)

	# ── 主布局 ──
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(outer)

	# ── 标题栏 ──
	_title_bar = _build_title_bar()
	outer.add_child(_title_bar)

	# ── 分隔线 ──
	var hsep = HSeparator.new()
	hsep.add_theme_stylebox_override("separator", GameTerminalStyles.separator_style())
	hsep.add_theme_constant_override("separation", 1)
	hsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(hsep)

	# ── HUD 状态条 (预留槽位) ──
	_hud_bar = _build_hud_bar()
	outer.add_child(_hud_bar)

	# ── 中央内容区 ──
	_content_area = _build_content_area()
	outer.add_child(_content_area)

	# ── 底部操作栏 (预留槽位) ──
	_footer_bar = _build_footer_bar()
	outer.add_child(_footer_bar)

# ═══════════════════════════════════════════════
#  标题栏
# ═══════════════════════════════════════════════

func _build_title_bar() -> Control:
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.gui_input.connect(_on_title_bar_input)

	_title_label = Label.new()
	_title_label.text = "游戏终端"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.70, 0.80, 0.92, 0.9))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_title_label)

	# 状态标签
	_status_label = Label.new()
	_status_label.text = "STANDBY"
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", GameTerminalStyles.status_active())
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_status_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "断开"
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4, 0.7))
	close_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.4, 0.35, 1.0))
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.08, 0.08, 0.5)
	cs.set_corner_radius_all(0)
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
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_dragging = false
			return
		panel.position = _clamp_pos(panel.get_global_mouse_position() - _drag_offset)

# ═══════════════════════════════════════════════
#  HUD 状态条
# ═══════════════════════════════════════════════

func _build_hud_bar() -> PanelContainer:
	var bar = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", GameTerminalStyles.status_bar_bg())
	bar.custom_minimum_size.y = 28
	bar.mouse_filter = Control.MOUSE_FILTER_PASS

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(hbox)

	# 占位: 未来会放计分器/计时器/回合指示
	var slot_hint = GameTerminalStyles.dim_label("[ HUD 数据槽位 ]", 12)
	hbox.add_child(slot_hint)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	var mode_hint = GameTerminalStyles.dim_label("LOBBY", 12)
	hbox.add_child(mode_hint)

	GameTerminalStyles.add_tech_brackets(bar, 5.0, 0.0)
	return bar

# ═══════════════════════════════════════════════
#  中央内容区
# ═══════════════════════════════════════════════

func _build_content_area() -> PanelContainer:
	var area = PanelContainer.new()
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.add_theme_stylebox_override("panel", GameTerminalStyles.content_area_bg())
	area.mouse_filter = Control.MOUSE_FILTER_PASS
	GameTerminalStyles.add_tech_brackets(area, 6.0, 0.0)

	# 内容堆叠容器 (大厅和游戏共用)
	_content_stack = Control.new()
	_content_stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	area.add_child(_content_stack)

	# ── 大厅 ──
	_lobby_placeholder = _build_lobby_placeholder()
	_content_stack.add_child(_lobby_placeholder)

	return area

func _build_lobby_placeholder() -> Control:
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS

	# 终端标识
	var logo_label = Label.new()
	logo_label.text = "GAME TERMINAL"
	logo_label.add_theme_font_size_override("font_size", 26)
	logo_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.6, 0.2))
	logo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(logo_label)

	# 分隔
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", GameTerminalStyles.separator_style())
	sep.add_theme_constant_override("separation", 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.custom_minimum_size.x = 200
	vbox.add_child(sep)

	# ── 游戏卡片 (从注册表自动生成) ──
	for entry in GAME_REGISTRY:
		var card = _build_game_card(entry.name, entry.desc, func(): _launch_terminal_game(entry.id))
		vbox.add_child(card)

	# 状态提示
	var hint = Label.new()
	hint.text = "选择目标开始推演"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 0.35))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint)

	center.add_child(vbox)
	return center

## 构建游戏选择卡片
func _build_game_card(title: String, desc: String, on_press: Callable) -> PanelContainer:
	var card = PanelContainer.new()
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.05, 0.07, 0.12, 0.5)
	cs.set_border_width_all(1)
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.25)
	cs.set_corner_radius_all(0)
	cs.content_margin_left = 20; cs.content_margin_right = 20
	cs.content_margin_top = 14; cs.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", cs)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.custom_minimum_size.x = 240

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)

	var t = Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", GameTerminalStyles.bright())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)

	var d = Label.new()
	d.text = desc
	d.add_theme_font_size_override("font_size", 12)
	d.add_theme_color_override("font_color", GameTerminalStyles.dim())
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(d)

	# hover 效果
	var normal_border = cs.border_color
	card.mouse_entered.connect(func():
		cs.bg_color = Color(0.08, 0.10, 0.18, 0.6)
		cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.5)
	)
	card.mouse_exited.connect(func():
		cs.bg_color = Color(0.05, 0.07, 0.12, 0.5)
		cs.border_color = normal_border
	)

	# 点击
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			on_press.call()
	)

	GameTerminalStyles.add_tech_brackets(card, 4.0, 0.0)
	return card

# ═══════════════════════════════════════════════
#  底部操作栏
# ═══════════════════════════════════════════════

func _build_footer_bar() -> PanelContainer:
	var bar = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", GameTerminalStyles.status_bar_bg())
	bar.custom_minimum_size.y = 24
	bar.mouse_filter = Control.MOUSE_FILTER_PASS

	_footer_hbox = HBoxContainer.new()
	_footer_hbox.add_theme_constant_override("separation", 8)
	_footer_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(_footer_hbox)

	var hint = GameTerminalStyles.dim_label("选择推演目标", 11)
	_footer_hbox.add_child(hint)

	return bar

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
	_state = TerminalState.LOBBY
	_update_status_display()
	# 保底恢复大厅 (上次直接断开可能残留隐藏状态)
	if is_instance_valid(_lobby_placeholder):
		_lobby_placeholder.visible = true
	_title_label.text = "游戏终端"
	_update_footer_for_lobby()
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
	_state = TerminalState.CLOSED
	_dragging = false
	_cleanup_active_game()
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

func _update_status_display() -> void:
	if not is_instance_valid(_status_label):
		return
	match _state:
		TerminalState.LOBBY:
			_status_label.text = "STANDBY"
			_status_label.add_theme_color_override("font_color", GameTerminalStyles.status_active())
		TerminalState.LOADING:
			_status_label.text = "LOADING"
			_status_label.add_theme_color_override("font_color", GameTerminalStyles.status_warning())
		TerminalState.PLAYING:
			_status_label.text = "IN GAME"
			_status_label.add_theme_color_override("font_color", GameTerminalStyles.accent())
		TerminalState.PAUSED:
			_status_label.text = "PAUSED"
			_status_label.add_theme_color_override("font_color", GameTerminalStyles.status_warning())
		TerminalState.RESULT:
			_status_label.text = "RESULT"
			_status_label.add_theme_color_override("font_color", GameTerminalStyles.bright())

# ═══════════════════════════════════════════════
#  围栏 (单向碰撞墙)
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
	# 底部
	_confine_walls.append(_make_wall(main_node,
		Vector2(rect.position.x + rect.size.x / 2, rect.end.y),
		Vector2(rect.size.x, t), 0.0))
	# 顶部
	_confine_walls.append(_make_wall(main_node,
		Vector2(rect.position.x + rect.size.x / 2, rect.position.y),
		Vector2(rect.size.x, t), PI))
	# 左侧
	_confine_walls.append(_make_wall(main_node,
		Vector2(rect.position.x, rect.position.y + rect.size.y / 2),
		Vector2(rect.size.y, t), PI / 2))
	# 右侧
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
#  自定义战术终端边框渲染
# ═══════════════════════════════════════════════

func _on_frame_draw() -> void:
	if not _frame_drawer: return
	var hue = EventBus.ui_hue
	var w = _frame_drawer.size.x
	var h = _frame_drawer.size.y

	# 1. 对称八角切角多边形 (四角全切)
	var c_l = 24.0  # 切角段尺寸
	var pts = PackedVector2Array()
	pts.append(Vector2(c_l, 0))           # TL 结束
	pts.append(Vector2(w - c_l, 0))       # TR 开始
	pts.append(Vector2(w, c_l))           # TR 结束
	pts.append(Vector2(w, h - c_l))       # BR 开始
	pts.append(Vector2(w - c_l, h))       # BR 结束
	pts.append(Vector2(c_l, h))           # BL 开始
	pts.append(Vector2(0, h - c_l))       # BL 结束
	pts.append(Vector2(0, c_l))           # TL 开始
	pts.append(Vector2(c_l, 0))           # 闭合

	# 2. 深色磨砂背景
	var bg_c = Color(0.025, 0.04, 0.08, 0.96)
	_frame_drawer.draw_polygon(pts, PackedColorArray([bg_c]))

	# 3. 主边界线
	var border_c = Color.from_hsv(hue, 0.45, 0.65, 0.4)
	_frame_drawer.draw_polyline(pts, border_c, 1.2, true)

	# 4. 四角切角加持 (脉冲呼吸)
	var pulse = (sin(_time_passed * 3.0) * 0.5 + 0.5) * 0.5 + 0.5  # 0.5 ~ 1.0
	var corner_c = Color.from_hsv(hue, 0.6, 0.9, 0.7 * pulse)
	var corner_lw = 2.5
	# TL 切角
	_frame_drawer.draw_line(pts[7], pts[0], corner_c, corner_lw, true)
	# TR 切角
	_frame_drawer.draw_line(pts[1], pts[2], corner_c, corner_lw, true)
	# BR 切角
	_frame_drawer.draw_line(pts[3], pts[4], corner_c, corner_lw, true)
	# BL 切角
	_frame_drawer.draw_line(pts[5], pts[6], corner_c, corner_lw, true)

	# 5. 靶向准星 (四角外侧十字线标记)
	var aim_c = Color.from_hsv(hue, 0.5, 0.85, 0.5 * pulse)
	var aim_len = 10.0
	var aim_gap = 4.0
	# TL 准星
	var tl = Vector2(0, 0)
	_frame_drawer.draw_line(tl + Vector2(-aim_gap, c_l * 0.5), tl + Vector2(-aim_gap - aim_len, c_l * 0.5), aim_c, 1.0)
	_frame_drawer.draw_line(tl + Vector2(c_l * 0.5, -aim_gap), tl + Vector2(c_l * 0.5, -aim_gap - aim_len), aim_c, 1.0)
	# TR 准星
	var tr = Vector2(w, 0)
	_frame_drawer.draw_line(tr + Vector2(aim_gap, c_l * 0.5), tr + Vector2(aim_gap + aim_len, c_l * 0.5), aim_c, 1.0)
	_frame_drawer.draw_line(tr + Vector2(-c_l * 0.5, -aim_gap), tr + Vector2(-c_l * 0.5, -aim_gap - aim_len), aim_c, 1.0)
	# BR 准星
	var br = Vector2(w, h)
	_frame_drawer.draw_line(br + Vector2(aim_gap, -c_l * 0.5), br + Vector2(aim_gap + aim_len, -c_l * 0.5), aim_c, 1.0)
	_frame_drawer.draw_line(br + Vector2(-c_l * 0.5, aim_gap), br + Vector2(-c_l * 0.5, aim_gap + aim_len), aim_c, 1.0)
	# BL 准星
	var bl = Vector2(0, h)
	_frame_drawer.draw_line(bl + Vector2(-aim_gap, -c_l * 0.5), bl + Vector2(-aim_gap - aim_len, -c_l * 0.5), aim_c, 1.0)
	_frame_drawer.draw_line(bl + Vector2(c_l * 0.5, aim_gap), bl + Vector2(c_l * 0.5, aim_gap + aim_len), aim_c, 1.0)

	# 6. 水平扫描线 (从上到下循环扫过)
	var scan_period = 4.0  # 扫描周期 (秒)
	var scan_t = fmod(_time_passed, scan_period) / scan_period  # 0~1
	var scan_y = lerpf(0, h, scan_t)
	var scan_alpha = 1.0 - absf(scan_t - 0.5) * 2.0  # 中部最亮，两端淡出
	var scan_c = Color.from_hsv(hue, 0.4, 0.95, 0.12 * scan_alpha)
	var scan_glow = Color.from_hsv(hue, 0.5, 0.95, 0.04 * scan_alpha)
	# 泛光 (宽)
	_frame_drawer.draw_line(Vector2(0, scan_y), Vector2(w, scan_y), scan_glow, 12.0)
	# 核心 (细)
	_frame_drawer.draw_line(Vector2(0, scan_y), Vector2(w, scan_y), scan_c, 1.5)

	# 7. 底部居中刻度线
	var tick_c = Color.from_hsv(hue, 0.4, 0.7, 0.25)
	var cx = w * 0.5
	for i in range(-20, 21):
		var tx = cx + i * 10.0
		var ty_len = 3.0 if i % 5 != 0 else 6.0
		if tx > c_l + 4 and tx < w - c_l - 4:
			_frame_drawer.draw_line(Vector2(tx, h), Vector2(tx, h - ty_len), tick_c, 1.0)

	# 8. 左侧居中刻度线
	var cy = h * 0.5
	for i in range(-12, 13):
		var ty = cy + i * 10.0
		var tx_len = 3.0 if i % 5 != 0 else 6.0
		if ty > c_l + 4 and ty < h - c_l - 4:
			_frame_drawer.draw_line(Vector2(0, ty), Vector2(tx_len, ty), tick_c, 1.0)

# ═══════════════════════════════════════════════
#  游戏生命周期
# ═══════════════════════════════════════════════

# ── 游戏注册表 (新增游戏只需加一条) ──
const GAME_REGISTRY := [
	{ "id": "ttt", "name": "策略矩阵", "desc": "3x3 决策推演",
	  "script": preload("res://ui/game_terminal/terminal_ttt.gd") },
	{ "id": "minesweeper", "name": "威胁评估", "desc": "9x9 雷区扫描",
	  "script": preload("res://ui/game_terminal/terminal_minesweeper.gd") },
	{ "id": "2048", "name": "矩阵叠加", "desc": "4x4 数值融合",
	  "script": preload("res://ui/game_terminal/terminal_2048.gd") },
	{ "id": "snake", "name": "路径规划", "desc": "15x15 线性延伸",
	  "script": preload("res://ui/game_terminal/terminal_snake.gd") },
]

## 启动终端内置游戏
func _launch_terminal_game(game_id: String) -> void:
	if _active_game:
		return
	var entry = null
	for g in GAME_REGISTRY:
		if g.id == game_id:
			entry = g
			break
	if not entry:
		return

	var game: Control = entry.script.new()
	game.build()
	game.game_over.connect(_on_game_over)

	_active_game = game
	_active_game_name = entry.name

	# 隐藏大厅，显示游戏 (直接挂内容区，由面板级 SubViewport 统一捕获)
	_lobby_placeholder.visible = false
	_content_stack.add_child(_active_game)

	# 更新终端显示
	_state = TerminalState.PLAYING
	_title_label.text = "游戏终端 // " + entry.name
	_update_status_display()
	_update_footer_for_game()

	# 激活全息投影
	_activate_holo_preview()

func _on_game_over(result: int) -> void:
	_state = TerminalState.RESULT
	_update_status_display()

func _cleanup_active_game() -> void:
	# 断开全息投影
	_deactivate_holo_preview()
	if _active_game and is_instance_valid(_active_game):
		_active_game.queue_free()
	_active_game = null
	_active_game_name = ""

func _return_to_lobby() -> void:
	_cleanup_active_game()
	_lobby_placeholder.visible = true
	_state = TerminalState.LOBBY
	_title_label.text = "游戏终端"
	_update_status_display()
	_update_footer_for_lobby()

# ═══════════════════════════════════════════════
#  全息投影联动
# ═══════════════════════════════════════════════

## 返回全终端面板纹理 (供全息屏 texture_provider 回调)
func get_game_texture() -> Texture2D:
	if is_instance_valid(_panel_viewport):
		return _panel_viewport.get_texture()
	return null

## 激活全息屏投影 (GAME 模式)
func _activate_holo_preview() -> void:
	var pet = _get_pet()
	if not pet or not ("holo_screen" in pet):
		return
	var holo = pet.holo_screen
	if not holo:
		return
	# 根据宠物位置决定全息屏方向
	var vp_w = get_viewport().get_visible_rect().size.x
	var screen_side = -1.0 if pet.global_position.x > vp_w * 0.5 else 1.0
	holo.show_game(get_game_texture, screen_side, true)  # lock=true: 锁定宠物+踏板

## 断开全息屏投影
func _deactivate_holo_preview() -> void:
	var pet = _get_pet()
	if not pet or not ("holo_screen" in pet):
		return
	var holo = pet.holo_screen
	if not holo:
		return
	# 只在当前是 GAME 模式时才关闭 (避免干扰其他模式)
	if holo.mode == 1:  # Mode.GAME = 1
		holo.hide()

## 更新底栏: 游戏中
func _update_footer_for_game() -> void:
	if not _footer_hbox: return
	for c in _footer_hbox.get_children():
		c.queue_free()

	var back_btn = Button.new()
	back_btn.text = "返回大厅"
	back_btn.add_theme_font_size_override("font_size", 12)
	back_btn.add_theme_color_override("font_color", Color(0.6, 0.5, 0.4, 0.7))
	back_btn.add_theme_color_override("font_hover_color", Color(0.9, 0.5, 0.35, 1.0))
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(0.1, 0.08, 0.06, 0.3)
	bs.set_corner_radius_all(0)
	bs.set_border_width_all(1)
	bs.border_color = Color(0.4, 0.3, 0.2, 0.2)
	bs.content_margin_left = 8; bs.content_margin_right = 8
	bs.content_margin_top = 2; bs.content_margin_bottom = 2
	back_btn.add_theme_stylebox_override("normal", bs)
	var bh = bs.duplicate()
	bh.bg_color = Color(0.15, 0.1, 0.08, 0.5)
	bh.border_color = Color(0.6, 0.35, 0.25, 0.4)
	back_btn.add_theme_stylebox_override("hover", bh)
	back_btn.add_theme_stylebox_override("pressed", bh)
	back_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	back_btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			_return_to_lobby()
	)
	_footer_hbox.add_child(back_btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer_hbox.add_child(spacer)

	var game_hint = GameTerminalStyles.dim_label(_active_game_name, 11)
	_footer_hbox.add_child(game_hint)

## 更新底栏: 大厅
func _update_footer_for_lobby() -> void:
	if not _footer_hbox: return
	for c in _footer_hbox.get_children():
		c.queue_free()
	var hint = GameTerminalStyles.dim_label("选择推演目标", 11)
	_footer_hbox.add_child(hint)

# ═══════════════════════════════════════════════
#  UI 主题色同步
# ═══════════════════════════════════════════════

func _on_ui_theme_changed(_hue: float) -> void:
	pass  # frame_drawer 每帧读 EventBus.ui_hue, 自动跟随

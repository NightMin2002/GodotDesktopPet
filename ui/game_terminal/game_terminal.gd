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
var _active_game_id: String = ""   # 当前游戏ID
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _is_open: bool = false
var _state: int = TerminalState.CLOSED

var _frame_drawer: Control
var _time_passed: float = 0.0

# ── HUD ──
var _hud_hbox: HBoxContainer        # HUD 内部容器
var _hud_slot_labels: Dictionary = {} # slot_id -> Label
var _hud_mode_label: Label           # 右侧状态指示
var _hud_record_label: Label = null  # 战绩标签

# ── 自玩模式 ──
var _auto_play: bool = false          # 是否正在自玩
var _auto_visible: bool = false       # true=观战模式(面板可见), false=后台模式(面板透明)
var _auto_timer: Timer = null         # AI 操作定时器
var _auto_blocker: Control = null     # 观战模式输入拦截层
const AUTO_PLAY_INTERVAL := 0.4       # AI 操作间隔 (秒)

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
	EventBus.panel_focus_requested.connect(_on_panel_focus)

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
			pet.set_overlay_rect("game_terminal", Rect2(panel.position, Vector2(_panel_w, _panel_h)))
		# HUD 数据轮询 (PLAYING 状态下每帧从游戏拉取)
		if _state == TerminalState.PLAYING and _active_game:
			_update_hud()
		# 注册面板矩形 (供层级管理用)
		EventBus._active_panel_rects[_PANEL_ID] = { "rect": Rect2(panel.position, Vector2(_panel_w, _panel_h)), "layer": layer }
	else:
		# ── 兜底自检: 面板已关闭但残留未清理 ──
		_sanity_check()

func _input(event: InputEvent) -> void:
	if _is_open and event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = event.position
		if Rect2(panel.position, Vector2(_panel_w, _panel_h)).has_point(pos):
			# 如果我在底层, 检查点击位置是否被更高层面板覆盖
			if layer < -1:
				for pid in EventBus._active_panel_rects:
					if pid != _PANEL_ID:
						var info = EventBus._active_panel_rects[pid]
						if info.layer > layer and info.rect.has_point(pos):
							return  # 被更高层面板覆盖, 跳过
			_bring_to_front()

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
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color(0.70, 0.80, 0.92, 0.9))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_title_label)

	# 状态标签
	_status_label = Label.new()
	_status_label.text = "STANDBY"
	_status_label.add_theme_font_size_override("font_size", 15)
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
	close_btn.add_theme_font_size_override("font_size", 15)
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
	bar.custom_minimum_size.y = 34
	bar.mouse_filter = Control.MOUSE_FILTER_PASS

	_hud_hbox = HBoxContainer.new()
	_hud_hbox.add_theme_constant_override("separation", 16)
	_hud_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(_hud_hbox)

	# 初始大厅状态
	_hud_record_label = GameTerminalStyles.dim_label("// 选择推演目标", 14)
	_hud_hbox.add_child(_hud_record_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_hbox.add_child(spacer)

	_hud_mode_label = GameTerminalStyles.dim_label("STANDBY", 14)
	_hud_mode_label.add_theme_color_override("font_color", GameTerminalStyles.status_active())
	_hud_hbox.add_child(_hud_mode_label)

	GameTerminalStyles.add_tech_brackets(bar, 5.0, 0.0)
	return bar

## 从活跃游戏轮询 HUD 数据并更新槽位
func _update_hud() -> void:
	if not _active_game or not _active_game.has_method("get_hud_data"):
		return
	var data: Dictionary = _active_game.get_hud_data()
	for slot_id in data:
		if slot_id in _hud_slot_labels:
			var info = data[slot_id]
			var lbl: Label = _hud_slot_labels[slot_id]
			var text = "%s: %s" % [str(info.get("label", slot_id)), str(info.get("value", ""))]
			if lbl.text != text:
				lbl.text = text
			var c = info.get("color", null)
			if c is Color:
				lbl.add_theme_color_override("font_color", c)

## 从游戏初始化 HUD 槽位
func _setup_hud_for_game() -> void:
	_clear_hud_slots()
	if not _active_game or not _active_game.has_method("get_hud_data"):
		return
	var data: Dictionary = _active_game.get_hud_data()
	# 按 data 的 key 顺序插入到 mode_label 之前
	var insert_idx := 0
	for slot_id in data:
		var info = data[slot_id]
		var text = "%s: %s" % [str(info.get("label", slot_id)), str(info.get("value", ""))]
		var c = info.get("color", GameTerminalStyles.dim())
		var lbl = GameTerminalStyles.make_label(text, 14, c if c is Color else GameTerminalStyles.dim())
		_hud_hbox.add_child(lbl)
		_hud_hbox.move_child(lbl, insert_idx)
		_hud_slot_labels[slot_id] = lbl
		insert_idx += 1
	# 战绩摘要 (紧跟数据槽位之后)
	var record_text = _get_record_summary(_active_game_id)
	if record_text != "":
		_hud_record_label.text = record_text
		_hud_record_label.visible = true
	else:
		_hud_record_label.visible = false

## 清空 HUD 槽位 (回到大厅状态)
func _clear_hud_slots() -> void:
	for lbl in _hud_slot_labels.values():
		if is_instance_valid(lbl):
			lbl.queue_free()
	_hud_slot_labels.clear()
	if is_instance_valid(_hud_record_label):
		_hud_record_label.text = "// 选择推演目标"
		_hud_record_label.visible = true

## 更新 HUD 右侧状态指示
func _update_hud_mode() -> void:
	if not is_instance_valid(_hud_mode_label):
		return
	match _state:
		TerminalState.LOBBY:
			_hud_mode_label.text = "STANDBY"
			_hud_mode_label.add_theme_color_override("font_color", GameTerminalStyles.status_active())
		TerminalState.PLAYING:
			if _auto_play:
				_hud_mode_label.text = "AUTO"
				_hud_mode_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.95, 0.75))
			else:
				_hud_mode_label.text = "IN GAME"
				_hud_mode_label.add_theme_color_override("font_color", GameTerminalStyles.accent())
		TerminalState.RESULT:
			_hud_mode_label.text = "RESULT"
			_hud_mode_label.add_theme_color_override("font_color", GameTerminalStyles.bright())
		_:
			_hud_mode_label.text = _state_to_string(_state)
			_hud_mode_label.add_theme_color_override("font_color", GameTerminalStyles.dim())

func _state_to_string(s: int) -> String:
	match s:
		TerminalState.CLOSED: return "CLOSED"
		TerminalState.LOBBY: return "STANDBY"
		TerminalState.LOADING: return "LOADING"
		TerminalState.PLAYING: return "IN GAME"
		TerminalState.PAUSED: return "PAUSED"
		TerminalState.RESULT: return "RESULT"
	return "UNKNOWN"

# ═══════════════════════════════════════════════
#  战绩持久化
# ═══════════════════════════════════════════════

func _record_key(game_id: String, suffix: String) -> String:
	return "terminal_" + game_id + "_" + suffix

func _save_record(game_id: String, result: int) -> void:
	if game_id == "":
		return
	match result:
		0: # 胜
			var w = SettingsManager.get_int(_record_key(game_id, "wins"), 0)
			SettingsManager.set_int(_record_key(game_id, "wins"), w + 1)
		1: # 负
			var l = SettingsManager.get_int(_record_key(game_id, "losses"), 0)
			SettingsManager.set_int(_record_key(game_id, "losses"), l + 1)
		2: # 平
			var d = SettingsManager.get_int(_record_key(game_id, "draws"), 0)
			SettingsManager.set_int(_record_key(game_id, "draws"), d + 1)
	# 保存最佳分数 (如果游戏提供)
	if _active_game and _active_game.has_method("get_best_score"):
		var score: int = _active_game.get_best_score()
		var old_best = SettingsManager.get_int(_record_key(game_id, "best"), 0)
		if score > old_best:
			SettingsManager.set_int(_record_key(game_id, "best"), score)

func _get_record_summary(game_id: String) -> String:
	if game_id == "":
		return ""
	var w = SettingsManager.get_int(_record_key(game_id, "wins"), 0)
	var l = SettingsManager.get_int(_record_key(game_id, "losses"), 0)
	var d = SettingsManager.get_int(_record_key(game_id, "draws"), 0)
	var best = SettingsManager.get_int(_record_key(game_id, "best"), 0)
	var parts: Array[String] = []
	if w + l + d == 0:
		return "// 首次推演"
	parts.append("%dW" % w)
	parts.append("%dL" % l)
	if d > 0:
		parts.append("%dD" % d)
	if best > 0:
		parts.append("BEST:%d" % best)
	return "// " + " / ".join(parts)

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
	var outer = MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 8)
	outer.add_theme_constant_override("margin_right", 8)
	outer.add_theme_constant_override("margin_top", 4)
	outer.add_theme_constant_override("margin_bottom", 4)
	outer.mouse_filter = Control.MOUSE_FILTER_PASS

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── 终端标识行 ──
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line_l = HSeparator.new()
	line_l.add_theme_stylebox_override("separator", GameTerminalStyles.separator_style())
	line_l.add_theme_constant_override("separation", 1)
	line_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(line_l)

	var logo_label = Label.new()
	logo_label.text = "GAME TERMINAL"
	logo_label.add_theme_font_size_override("font_size", 17)
	logo_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.65, 0.3))
	logo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(logo_label)

	var line_r = HSeparator.new()
	line_r.add_theme_stylebox_override("separator", GameTerminalStyles.separator_style())
	line_r.add_theme_constant_override("separation", 1)
	line_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(line_r)

	vbox.add_child(header)

	# ── 游戏卡片网格 (2列) ──
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL

	for entry in GAME_REGISTRY:
		var card = _build_game_card(entry, func(): _launch_terminal_game(entry.id))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(card)

	vbox.add_child(grid)

	# ── 底部状态提示 ──
	var hint = Label.new()
	hint.text = "选择目标开始推演 // %d 项可用" % GAME_REGISTRY.size()
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.30, 0.40, 0.50, 0.3))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint)

	outer.add_child(vbox)
	return outer

## 构建大厅游戏卡片 (网格版)
func _build_game_card(entry: Dictionary, on_press: Callable) -> PanelContainer:
	var card = PanelContainer.new()
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.04, 0.06, 0.11, 0.55)
	cs.set_border_width_all(1)
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.25, 0.45, 0.2)
	cs.set_corner_radius_all(0)
	cs.content_margin_left = 14; cs.content_margin_right = 14
	cs.content_margin_top = 14; cs.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", cs)
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(vb)

	# ── 图标区 (自绘) ──
	var icon_area = _LobbyIcon.new()
	icon_area.game_id = entry.id
	icon_area.custom_minimum_size = Vector2(0, 100)
	icon_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(icon_area)

	# ── 标题 ──
	var t = Label.new()
	t.text = entry.name
	t.add_theme_font_size_override("font_size", 21)
	t.add_theme_color_override("font_color", GameTerminalStyles.bright())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)

	# ── 描述 ──
	var d = Label.new()
	d.text = entry.desc
	d.add_theme_font_size_override("font_size", 15)
	d.add_theme_color_override("font_color", GameTerminalStyles.dim())
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(d)

	# ── 战绩角标 ──
	var record = _get_record_summary(entry.id)
	if record != "":
		var rec_lbl = Label.new()
		rec_lbl.text = record.replace("// ", "")
		rec_lbl.add_theme_font_size_override("font_size", 14)
		rec_lbl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.7, 0.35))
		rec_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rec_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(rec_lbl)

	# ── 委托推演按钮 (支持自玩的游戏) ──
	if entry.get("auto", false):
		var auto_btn = Button.new()
		auto_btn.text = "[ 委托推演 ]"
		auto_btn.add_theme_font_size_override("font_size", 14)
		auto_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.25, 0.6, 0.45))
		auto_btn.add_theme_color_override("font_hover_color", Color.from_hsv(EventBus.ui_hue, 0.45, 0.85, 0.8))
		auto_btn.add_theme_color_override("font_pressed_color", Color.from_hsv(EventBus.ui_hue, 0.5, 1.0, 0.9))
		# 极简样式: 透明背景
		var ab_normal = StyleBoxFlat.new()
		ab_normal.bg_color = Color(0.04, 0.06, 0.12, 0.3)
		ab_normal.set_border_width_all(1)
		ab_normal.border_color = Color.from_hsv(EventBus.ui_hue, 0.2, 0.4, 0.15)
		ab_normal.set_corner_radius_all(0)
		ab_normal.content_margin_left = 6; ab_normal.content_margin_right = 6
		ab_normal.content_margin_top = 2; ab_normal.content_margin_bottom = 2
		auto_btn.add_theme_stylebox_override("normal", ab_normal)
		var ab_hover = ab_normal.duplicate()
		ab_hover.bg_color = Color(0.06, 0.08, 0.16, 0.5)
		ab_hover.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.7, 0.3)
		auto_btn.add_theme_stylebox_override("hover", ab_hover)
		auto_btn.add_theme_stylebox_override("pressed", ab_hover)
		auto_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		auto_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		auto_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# 居中
		var btn_center = CenterContainer.new()
		btn_center.mouse_filter = Control.MOUSE_FILTER_PASS
		btn_center.add_child(auto_btn)
		vb.add_child(btn_center)
		# 点击: 启动可见自玩
		var gid = entry.id
		auto_btn.pressed.connect(func(): _launch_visible_auto_game(gid))

	# ── hover 效果 ──
	card.mouse_entered.connect(func():
		cs.bg_color = Color(0.07, 0.09, 0.16, 0.65)
		cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.45)
		if is_instance_valid(icon_area):
			icon_area._hovered = true
			icon_area.queue_redraw()
	)
	card.mouse_exited.connect(func():
		cs.bg_color = Color(0.04, 0.06, 0.11, 0.55)
		cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.25, 0.45, 0.2)
		if is_instance_valid(icon_area):
			icon_area._hovered = false
			icon_area.queue_redraw()
	)

	# ── 点击 ──
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			on_press.call()
	)

	GameTerminalStyles.add_tech_brackets(card, 4.0, 0.0)
	return card

## 可见自玩: 面板保持打开, AI 在终端内自动操作 (观战模式)
func _launch_visible_auto_game(game_id: String) -> void:
	_auto_play = true
	_auto_visible = true
	_launch_terminal_game(game_id)
	_auto_start_timer()
	_update_hud_mode()
	_show_auto_blocker()

# ═══════════════════════════════════════════════
#  大厅图标渲染器 (内嵌类)
# ═══════════════════════════════════════════════

class _LobbyIcon extends Control:
	var game_id: String = ""
	var _hovered: bool = false
	var _time: float = 0.0
	# ── Snake demo ──
	var _s_pos: float = 0.0
	var _s_len: int = 4
	var _s_food: float = -1.0
	var _s_growing: bool = true

	func _process(delta: float) -> void:
		_time += delta
		if game_id == "snake":
			_s_pos += delta * 80.0
		queue_redraw()

	func _draw() -> void:
		var hue = EventBus.ui_hue
		var w = size.x
		var h = size.y
		var cx = w * 0.5
		var cy = h * 0.5
		var alpha_base = 0.55 if _hovered else 0.35
		var alpha_hi = 0.9 if _hovered else 0.6
		var line_c = Color.from_hsv(hue, 0.4, 0.75, alpha_base)
		var accent_c = Color.from_hsv(hue, 0.55, 0.9, alpha_hi)
		var t = _time

		match game_id:
			"ttt":
				# ── 井字棋: 放大网格 + 脉冲标记 + 扫描线 ──
				var gs = minf(w, h) * 0.75
				var cs = gs / 3.0
				var ox = cx - gs * 0.5
				var oy = cy - gs * 0.5
				# 网格线
				for i in range(1, 3):
					draw_line(Vector2(ox + i * cs, oy + 3), Vector2(ox + i * cs, oy + gs - 3), line_c, 1.0)
					draw_line(Vector2(ox + 3, oy + i * cs), Vector2(ox + gs - 3, oy + i * cs), line_c, 1.0)
				# 十字瞄准节点 (网格交叉点)
				var cross_c = Color.from_hsv(hue, 0.3, 0.7, alpha_base * 0.7)
				for gx in range(1, 3):
					for gy in range(1, 3):
						var px = ox + cs * gx
						var py = oy + cs * gy
						draw_line(Vector2(px - 3, py), Vector2(px + 3, py), cross_c, 1.0, true)
						draw_line(Vector2(px, py - 3), Vector2(px, py + 3), cross_c, 1.0, true)
				# X at [0,0] — 分离线段 + 脉冲
				var pad = cs * 0.22
				var x_pulse = sin(t * 2.0) * 0.12 + 0.88
				var x_c = Color.from_hsv(hue, 0.3, 0.9, alpha_hi * x_pulse)
				var gap_x = cs * 0.06
				var arm = cs * 0.5 - pad
				var c00 = Vector2(ox + cs * 0.5, oy + cs * 0.5)
				draw_line(c00 + Vector2(-gap_x, -gap_x), c00 + Vector2(-gap_x - arm, -gap_x - arm), x_c, 2.0, true)
				draw_line(c00 + Vector2(gap_x, gap_x), c00 + Vector2(gap_x + arm, gap_x + arm), x_c, 2.0, true)
				draw_line(c00 + Vector2(gap_x, -gap_x), c00 + Vector2(gap_x + arm, -gap_x - arm), x_c, 2.0, true)
				draw_line(c00 + Vector2(-gap_x, gap_x), c00 + Vector2(-gap_x - arm, gap_x + arm), x_c, 2.0, true)
				# O at [1,1] — 留缺口圆弧 + 脉冲
				var o_pulse = sin(t * 2.5 + 1.0) * 0.08 + 0.92
				var o_r = cs * 0.32 * o_pulse
				var o_c = Color(0.9, 0.55, 0.3, alpha_hi)
				draw_arc(Vector2(ox + cs * 1.5, oy + cs * 1.5), o_r, -PI * 0.48 + 0.12, PI * 1.52 - 0.12, 28, o_c, 2.0, true)
				# X at [2,0]
				var c20 = Vector2(ox + cs * 2.5, oy + cs * 0.5)
				draw_line(c20 + Vector2(-gap_x, -gap_x), c20 + Vector2(-gap_x - arm, -gap_x - arm), x_c, 2.0, true)
				draw_line(c20 + Vector2(gap_x, gap_x), c20 + Vector2(gap_x + arm, gap_x + arm), x_c, 2.0, true)
				draw_line(c20 + Vector2(gap_x, -gap_x), c20 + Vector2(gap_x + arm, -gap_x - arm), x_c, 2.0, true)
				draw_line(c20 + Vector2(-gap_x, gap_x), c20 + Vector2(-gap_x - arm, gap_x + arm), x_c, 2.0, true)
				# 扫描线
				var scan_y = oy + fmod(t * 30.0, gs)
				draw_line(Vector2(ox, scan_y), Vector2(ox + gs, scan_y), Color.from_hsv(hue, 0.3, 0.8, 0.1), 1.0)

			"minesweeper":
				# ── 扫雷: 放大网格 + 脉冲雷芯 + 辐射刺 + 旗帜 ──
				var gs = minf(w, h) * 0.7
				var cs = gs / 3.0
				var ox = cx - gs * 0.5
				var oy = cy - gs * 0.5
				# 网格
				for i in range(4):
					draw_line(Vector2(ox + i * cs, oy), Vector2(ox + i * cs, oy + gs), line_c, 0.5)
					draw_line(Vector2(ox, oy + i * cs), Vector2(ox + gs, oy + i * cs), line_c, 0.5)
				# 雷芯 — 脉冲 + 泛光 + 十字/对角刺
				var mc = Vector2(ox + cs * 1.5, oy + cs * 1.5)
				var mine_pulse = sin(t * 3.0) * 0.12 + 0.88
				var mr = cs * 0.3 * mine_pulse
				draw_circle(mc, mr + 4, Color(0.9, 0.2, 0.15, 0.1 * mine_pulse), true, -1.0, true)
				draw_circle(mc, mr, Color(0.9, 0.25, 0.2, alpha_hi), true, -1.0, true)
				var spike_c = Color(0.95, 0.3, 0.25, 0.55 * mine_pulse)
				var sl = mr * 1.6
				draw_line(mc - Vector2(sl, 0), mc + Vector2(sl, 0), spike_c, 1.5, true)
				draw_line(mc - Vector2(0, sl), mc + Vector2(0, sl), spike_c, 1.5, true)
				var dsl = sl * 0.7
				draw_line(mc - Vector2(dsl, dsl), mc + Vector2(dsl, dsl), spike_c, 1.0, true)
				draw_line(mc - Vector2(dsl, -dsl), mc + Vector2(dsl, -dsl), spike_c, 1.0, true)
				# 高光点
				draw_circle(mc + Vector2(-mr * 0.3, -mr * 0.3), mr * 0.18, Color(1.0, 0.6, 0.5, 0.5), true, -1.0, true)
				# 旗帜 at [0,0]
				var fc = Vector2(ox + cs * 0.5, oy + cs * 0.5)
				draw_line(fc + Vector2(0, -cs * 0.35), fc + Vector2(0, cs * 0.25), Color(0.7, 0.8, 0.9, alpha_base), 1.5, true)
				var flag_pts = PackedVector2Array([
					fc + Vector2(0, -cs * 0.35),
					fc + Vector2(cs * 0.32, -cs * 0.17),
					fc + Vector2(0, 0),
				])
				draw_colored_polygon(flag_pts, accent_c)
				# 数字 "2"
				var font = ThemeDB.fallback_font
				draw_string(font, Vector2(ox + cs * 2.12, oy + cs * 0.72), "2", HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.65), Color(0.2, 0.75, 0.3, alpha_hi))

			"2048":
				# ── 2048: 2x2 矩阵 + 高级数字 + 发光顶块 ──
				var gs = minf(w, h) * 0.65
				var cs = gs * 0.45
				var gap = gs * 0.06
				var ox = cx - gs * 0.5
				var oy = cy - gs * 0.5
				var tiles = [2, 64, 256, 2048]
				var colors = [
					Color(0.14, 0.20, 0.32, 0.55),
					Color(0.68, 0.22, 0.14, 0.7),
					Color(0.68, 0.58, 0.12, 0.75),
					Color(0.82, 0.78, 0.22, 0.85),
				]
				var font = ThemeDB.fallback_font
				for row in range(2):
					for col in range(2):
						var idx = row * 2 + col
						var rx = ox + col * (cs + gap)
						var ry = oy + row * (cs + gap)
						# 2048 块发光动画
						if tiles[idx] == 2048:
							var glow = sin(t * 2.0) * 0.1 + 0.15
							draw_rect(Rect2(rx - 2, ry - 2, cs + 4, cs + 4), Color(0.9, 0.85, 0.3, glow))
						draw_rect(Rect2(rx, ry, cs, cs), colors[idx])
						var txt = str(tiles[idx])
						var fs = 16 if tiles[idx] < 100 else (13 if tiles[idx] < 1000 else 11)
						var ts = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
						draw_string(font, Vector2(rx + (cs - ts.x) * 0.5, ry + cs * 0.5 + ts.y * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.9, 0.95, alpha_hi))
				# 外框
				var total = cs * 2 + gap
				draw_rect(Rect2(ox - 1, oy - 1, total + 2, total + 2), Color.from_hsv(hue, 0.3, 0.55, 0.15), false, 1.0)

			"snake":
				# ── 贪吃蛇: 沿卡片边缘巡航 + 交替伸缩 ──
				var margin = 3.0
				var pw = w - margin * 2
				var ph = h - margin * 2
				var perim = 2.0 * (pw + ph)
				var seg_gap = 14.0
				# 食物初始化
				if _s_food < 0:
					_s_food = fmod(_s_pos + perim * 0.4, perim)
				# 吃食检测
				var head_p = fmod(_s_pos, perim)
				var d2f = absf(head_p - _s_food)
				d2f = minf(d2f, perim - d2f)
				if d2f < seg_gap * 0.8:
					if _s_growing:
						_s_len += 1
						if _s_len >= 18:
							_s_growing = false
					else:
						_s_len -= 1
						if _s_len <= 3:
							_s_growing = true
					_s_food = fmod(head_p + perim * randf_range(0.2, 0.45), perim)
				# 绘制蛇身
				var s = 12.0
				for i in range(_s_len):
					var sp = fmod(_s_pos - float(i) * seg_gap + perim * 999.0, perim)
					var pt = _perim_pt(sp, margin, pw, ph, perim)
					var a_val = lerpf(0.15, alpha_hi, 1.0 - float(i) / float(_s_len))
					if i == 0:
						# 蛇头泛光
						draw_rect(Rect2(pt.x - s * 0.5 - 1.5, pt.y - s * 0.5 - 1.5, s + 3, s + 3), Color.from_hsv(hue, 0.35, 0.8, 0.12))
						draw_rect(Rect2(pt.x - s * 0.5, pt.y - s * 0.5, s, s), accent_c)
					else:
						draw_rect(Rect2(pt.x - s * 0.5, pt.y - s * 0.5, s, s), Color.from_hsv(hue, 0.4, 0.7, a_val))
				# 食物脉冲
				var fpt = _perim_pt(_s_food, margin, pw, ph, perim)
				var pulse = sin(t * 4.0) * 0.2 + 0.8
				draw_circle(fpt, 4.5 * pulse, Color(0.9, 0.55, 0.3, 0.12), true, -1.0, true)
				draw_circle(fpt, 3.5 * pulse, Color(0.9, 0.55, 0.3, alpha_hi), true, -1.0, true)

			"tetris":
				# ── 俄罗斯方块: 底部堆叠 + 下落 T 块 + ghost ──
				var gs = minf(w, h) * 0.75
				var cols_n = 6
				var rows_n = 8
				var cs = gs / maxf(cols_n, rows_n)
				var ox = cx - cols_n * cs * 0.5
				var oy = cy - rows_n * cs * 0.5 + cs
				# 预设底部堆叠 (3 行残留)
				var stack = [
					[1,1,0,0,1,1],
					[1,1,1,0,1,1],
					[1,1,1,1,1,1],  # 满行 (闪烁)
				]
				var stack_colors = ["S", "J", "L", "T", "Z", "I"]
				for row_i in range(stack.size()):
					var ry = rows_n - stack.size() + row_i
					for col_i in range(cols_n):
						if stack[row_i][col_i] == 1:
							var bx = ox + col_i * cs
							var by = oy + ry * cs
							var is_full_row = (row_i == stack.size() - 1)
							var flash = sin(t * 4.0) * 0.2 + 0.8 if is_full_row else 1.0
							var pc = Color.from_hsv(fmod(hue + col_i * 0.08, 1.0), 0.35, 0.6 * flash, alpha_base * flash)
							draw_rect(Rect2(bx, by, cs - 1, cs - 1), pc)
				# 下落 T 块 (脉冲)
				var t_cells = [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)]
				var fall_y = fmod(t * 0.6, 1.0) * (rows_n - 4)  # 循环下落
				var t_pulse = sin(t * 3.0) * 0.1 + 0.9
				for c in t_cells:
					var bx = ox + (c.x + 1) * cs
					var by = oy + (c.y + fall_y) * cs
					# ghost (底部投影)
					var ghost_y = oy + (c.y + rows_n - 4) * cs
					draw_rect(Rect2(bx, ghost_y, cs - 1, cs - 1), Color.from_hsv(hue, 0.3, 0.6, 0.08))
					# 活动块
					var ac = Color.from_hsv(fmod(hue + 0.16, 1.0), 0.55, 0.9 * t_pulse, alpha_hi)
					draw_rect(Rect2(bx, by, cs - 1, cs - 1), ac)
				# 网格点
				var grid_c = Color.from_hsv(hue, 0.2, 0.5, 0.08)
				for gx in range(1, cols_n):
					for gy in range(1, rows_n):
						draw_circle(Vector2(ox + gx * cs, oy + gy * cs), 0.6, grid_c, true, -1.0, true)
				# 外框
				draw_rect(Rect2(ox, oy, cols_n * cs, rows_n * cs), Color.from_hsv(hue, 0.4, 0.6, 0.15), false, 1.0)

			_:
				# 默认: 问号
				var font = ThemeDB.fallback_font
				draw_string(font, Vector2(cx - 8, cy + 10), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, accent_c)

		# 底部薄分隔线
		draw_line(Vector2(8, h - 1), Vector2(w - 8, h - 1), Color.from_hsv(hue, 0.3, 0.5, 0.1), 1.0)

	## 周长坐标 → 2D 坐标 (矩形路径: 右→下→左→上)
	func _perim_pt(p: float, m: float, pw: float, ph: float, perim: float) -> Vector2:
		var pp = fmod(p, perim)
		if pp < 0: pp += perim
		if pp < pw:
			return Vector2(m + pp, m)
		pp -= pw
		if pp < ph:
			return Vector2(m + pw, m + pp)
		pp -= ph
		if pp < pw:
			return Vector2(m + pw - pp, m + ph)
		pp -= pw
		return Vector2(m, m + ph - pp)

# ═══════════════════════════════════════════════
#  底部操作栏
# ═══════════════════════════════════════════════

func _build_footer_bar() -> PanelContainer:
	var bar = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", GameTerminalStyles.status_bar_bg())
	bar.custom_minimum_size.y = 30
	bar.mouse_filter = Control.MOUSE_FILTER_PASS

	_footer_hbox = HBoxContainer.new()
	_footer_hbox.add_theme_constant_override("separation", 8)
	_footer_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(_footer_hbox)

	var hint = GameTerminalStyles.dim_label("选择推演目标", 12)
	_footer_hbox.add_child(hint)

	return bar

# ═══════════════════════════════════════════════
#  面板层级 (点击置顶)
# ═══════════════════════════════════════════════

const _PANEL_ID := "game_terminal"

func _bring_to_front() -> void:
	if layer != -1:
		EventBus.panel_focus_requested.emit(_PANEL_ID)

func _on_panel_focus(panel_id: String) -> void:
	if not _is_open:
		return
	if panel_id == _PANEL_ID:
		layer = -1   # 置顶
	else:
		layer = -2   # 降到后面

# ═══════════════════════════════════════════════
#  面板开关
# ═══════════════════════════════════════════════

func _on_toggle() -> void:
	if _is_open:
		_close_panel()
	else:
		_open_panel()

func _open_panel() -> void:
	_is_open = true
	EventBus.panel_focus_requested.emit(_PANEL_ID)
	_state = TerminalState.LOBBY
	_update_status_display()
	_update_hud_mode()
	_clear_hud_slots()
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
	EventBus._active_panel_rects.erase(_PANEL_ID)
	_force_full_cleanup()
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
	return ProfileStyles.get_pet(get_tree())

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
	{ "id": "ttt", "name": "策略矩阵", "desc": "3x3 决策推演", "auto": false,
	  "script": preload("res://ui/game_terminal/terminal_ttt.gd") },
	{ "id": "minesweeper", "name": "威胁评估", "desc": "9x9 雷区扫描", "auto": true,
	  "script": preload("res://ui/game_terminal/terminal_minesweeper.gd") },
	{ "id": "2048", "name": "矩阵叠加", "desc": "4x4 数值融合", "auto": true,
	  "script": preload("res://ui/game_terminal/terminal_2048.gd") },
	{ "id": "snake", "name": "路径规划", "desc": "15x15 线性延伸", "auto": true,
	  "script": preload("res://ui/game_terminal/terminal_snake.gd") },
	{ "id": "tetris", "name": "结构堆叠", "desc": "10x20 方块序列", "auto": true,
	  "script": preload("res://ui/game_terminal/terminal_tetris.gd") },
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
	if game.has_signal("game_started"):
		game.game_started.connect(_on_game_restarted)

	_active_game = game
	_active_game_name = entry.name
	_active_game_id = entry.id

	# 隐藏大厅，显示游戏 (直接挂内容区，由面板级 SubViewport 统一捕获)
	_lobby_placeholder.visible = false
	_content_stack.add_child(_active_game)

	# 更新终端显示
	_state = TerminalState.PLAYING
	_title_label.text = "游戏终端 // " + entry.name
	_update_status_display()
	_update_hud_mode()
	_setup_hud_for_game()
	_update_footer_for_game()

	# 激活全息投影
	_activate_holo_preview()

func _on_game_over(result: int) -> void:
	_state = TerminalState.RESULT
	_update_status_display()
	_update_hud_mode()
	# 战绩持久化
	_save_record(_active_game_id, result)
	# 刷新 HUD 战绩显示
	if is_instance_valid(_hud_record_label):
		var summary = _get_record_summary(_active_game_id)
		if summary != "":
			_hud_record_label.text = summary
	# 自玩处理
	if _auto_play:
		_auto_stop_timer()
		if _auto_visible:
			# 观战模式: 延迟后自动重开继续推演
			_auto_restart_after_delay()

## 观战模式: 延迟后自动重开游戏
func _auto_restart_after_delay() -> void:
	await get_tree().create_timer(2.0).timeout
	# 延迟期间用户可能已接手或退出
	if not _auto_play or not _auto_visible:
		return
	if not _active_game or not is_instance_valid(_active_game):
		return
	if _active_game.has_method("start_game"):
		_active_game.start_game()
	_auto_start_timer()

func _on_game_restarted() -> void:
	# 重开时恢复 PLAYING 状态
	if _state != TerminalState.PLAYING:
		_state = TerminalState.PLAYING
		_update_status_display()
		_update_hud_mode()

func _cleanup_active_game() -> void:
	# 断开全息投影
	_deactivate_holo_preview()
	if _active_game and is_instance_valid(_active_game):
		_active_game.queue_free()
	_active_game = null
	_active_game_name = ""
	_active_game_id = ""

func _return_to_lobby() -> void:
	_force_full_cleanup()
	_clear_hud_slots()
	_lobby_placeholder.visible = true
	_state = TerminalState.LOBBY
	_title_label.text = "游戏终端"
	_update_status_display()
	_update_hud_mode()
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

	var back_btn = _make_footer_btn("返回大厅", func(): _return_to_lobby())
	_footer_hbox.add_child(back_btn)

	# 观战模式: 加“接手操作”按钮
	if _auto_play and _auto_visible:
		var takeover_btn = _make_footer_btn("接手操作", func(): _takeover_from_auto())
		# 用主题色突出显示
		takeover_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.45, 0.85, 0.75))
		takeover_btn.add_theme_color_override("font_hover_color", Color.from_hsv(EventBus.ui_hue, 0.5, 1.0, 1.0))
		_footer_hbox.add_child(takeover_btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer_hbox.add_child(spacer)

	var mode_hint = _active_game_name
	if _auto_play and _auto_visible:
		mode_hint += " // AUTO"
	var game_hint = GameTerminalStyles.dim_label(mode_hint, 13)
	_footer_hbox.add_child(game_hint)

## 底栏按钮工厂 (避免重复样式代码)
func _make_footer_btn(text: String, on_press: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(0.6, 0.5, 0.4, 0.7))
	btn.add_theme_color_override("font_hover_color", Color(0.9, 0.5, 0.35, 1.0))
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(0.1, 0.08, 0.06, 0.3)
	bs.set_corner_radius_all(0)
	bs.set_border_width_all(1)
	bs.border_color = Color(0.4, 0.3, 0.2, 0.2)
	bs.content_margin_left = 8; bs.content_margin_right = 8
	bs.content_margin_top = 2; bs.content_margin_bottom = 2
	btn.add_theme_stylebox_override("normal", bs)
	var bh = bs.duplicate()
	bh.bg_color = Color(0.15, 0.1, 0.08, 0.5)
	bh.border_color = Color(0.6, 0.35, 0.25, 0.4)
	btn.add_theme_stylebox_override("hover", bh)
	btn.add_theme_stylebox_override("pressed", bh)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			on_press.call()
	)
	return btn

## 接手操作: 从自玩切换为手动模式
func _takeover_from_auto() -> void:
	_auto_play = false
	_auto_visible = false
	_auto_stop_timer()
	_hide_auto_blocker()
	_update_hud_mode()
	_update_footer_for_game()  # 重建底栏 (移除接手按钮)

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

# ═══════════════════════════════════════════════
#  委托推演 (观战模式 AI 操作)
# ═══════════════════════════════════════════════

## 启动 AI 操作定时器
func _auto_start_timer() -> void:
	_auto_stop_timer()
	_auto_timer = Timer.new()
	_auto_timer.wait_time = AUTO_PLAY_INTERVAL
	_auto_timer.timeout.connect(_auto_play_step)
	add_child(_auto_timer)
	_auto_timer.start()

## 停止 AI 操作定时器
func _auto_stop_timer() -> void:
	if is_instance_valid(_auto_timer):
		_auto_timer.stop()
		_auto_timer.queue_free()
	_auto_timer = null

## AI 每步操作 (Timer 回调)
func _auto_play_step() -> void:
	if not _auto_play or not _active_game:
		return
	if _state != TerminalState.PLAYING:
		return
	if _active_game.has_method("auto_play_step"):
		_active_game.auto_play_step()

## 显示输入拦截层 (观战模式: 屏蔽游戏区域的用户输入)
func _show_auto_blocker() -> void:
	_hide_auto_blocker()
	if not is_instance_valid(_content_stack):
		return
	_auto_blocker = Control.new()
	_auto_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_auto_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	# 吃掉键盘输入
	_auto_blocker.focus_mode = Control.FOCUS_ALL
	_auto_blocker.gui_input.connect(func(event: InputEvent):
		_auto_blocker.accept_event()
	)
	_content_stack.add_child(_auto_blocker)
	# 确保在最上层
	_content_stack.move_child(_auto_blocker, _content_stack.get_child_count() - 1)
	_auto_blocker.grab_focus()

## 隐藏输入拦截层
func _hide_auto_blocker() -> void:
	if is_instance_valid(_auto_blocker):
		_auto_blocker.queue_free()
	_auto_blocker = null


# ═══════════════════════════════════════════════
#  统一清理 + 兜底自检
# ═══════════════════════════════════════════════

## 统一清理入口: 所有退出路径都走这里
## 以后新增需要清理的产物, 只需在此处添加
func _force_full_cleanup() -> void:
	# 自玩状态
	if _auto_play:
		_auto_play = false
		_auto_visible = false
	_auto_stop_timer()
	_hide_auto_blocker()
	# 游戏 + 全息投影
	_cleanup_active_game()
	# 围栏墙
	_destroy_confine_walls()
	# DWM 穿透矩形
	var pet = _get_pet()
	if pet:
		pet.remove_overlay_rect("game_terminal")
	# 拖拽
	_dragging = false

## 兜底自检: 面板已关闭时检测残留产物, 自动修复 + 打日志
## 由 _process 在 _is_open==false 时调用
func _sanity_check() -> void:
	var issues: PackedStringArray = []
	if is_instance_valid(_auto_timer):
		_auto_stop_timer()
		issues.append("auto_timer")
	if is_instance_valid(_auto_blocker):
		_hide_auto_blocker()
		issues.append("auto_blocker")
	if _confine_walls.size() > 0:
		_destroy_confine_walls()
		issues.append("confine_walls")
	if _active_game and is_instance_valid(_active_game):
		_cleanup_active_game()
		issues.append("active_game")
	if _auto_play:
		_auto_play = false
		_auto_visible = false
		issues.append("auto_play_flag")
	# 注意: overlay_rects 由各面板独立管理 (key 注册/注销), 无需在此清理
	if not issues.is_empty():
		print("[GameTerminal] 兜底自检修复: ", ", ".join(issues))

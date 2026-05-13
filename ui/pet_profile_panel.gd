# pet_profile_panel.gd — 装置档案面板
# 左栏: 宠物线稿 + 身份信息 | 右栏: 标签页 (游戏战绩/能力数据)
extends CanvasLayer

# ── 常量 ──
const BIRTH_DATE := "2026.04.07 14:08:17"  # 出厂日期 (GitHub 首次提交 e1c7656)
const MODEL_NAME := "桌面观测单元"
const UNIT_ID := "#0001"

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
var _avatar_ctrl: Control
var _level_bar_fill: Panel
var _level_bar_bg: Panel
var _level_label: Label
var _xp_label: Label
var _rate_label: Label
var _days_label: Label
var _launch_label: Label

func _ready() -> void:
	_calc_panel_size()
	_build_ui()
	EventBus.show_pet_profile.connect(_on_toggle)
	EventBus.ui_theme_changed.connect(_on_ui_theme_changed)

func _calc_panel_size() -> void:
	var vp = get_viewport().get_visible_rect().size
	_panel_w = clampf(vp.x * 0.55, 650, 1100)
	_panel_h = clampf(vp.y * 0.55, 420, 700)

func _clamp_pos(pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - _panel_w - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - _panel_h - 4.0))
	return pos

# ═══════════════════════════════════════════════
#  UI 构建
# ═══════════════════════════════════════════════

func _build_ui() -> void:
	layer = 101

	# ── 面板容器 ──
	panel = PanelContainer.new()
	panel.visible = false
	panel.custom_minimum_size = Vector2(_panel_w, _panel_h)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.06, 0.13, 0.97)
	ps.set_border_width_all(1)
	ps.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.85, 0.5)
	ps.set_corner_radius_all(10)
	ps.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(margin)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(outer)

	# ── 标题栏 ──
	_title_bar = _build_title_bar()
	outer.add_child(_title_bar)

	# ── 分隔线 ──
	var hsep = HSeparator.new()
	var sep_s = StyleBoxFlat.new()
	sep_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.2)
	sep_s.set_content_margin_all(0)
	hsep.add_theme_stylebox_override("separator", sep_s)
	hsep.add_theme_constant_override("separation", 1)
	outer.add_child(hsep)

	# ── 双栏主体 ──
	var split = HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(split)

	# ── 左栏 ──
	var left_col = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.custom_minimum_size.x = 210
	split.add_child(left_col)

	# 头像区域
	_avatar_ctrl = _PetAvatar.new()
	_avatar_ctrl.custom_minimum_size = Vector2(180, 180)
	_avatar_ctrl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left_col.add_child(_avatar_ctrl)

	# 身份信息
	_build_identity_section(left_col)

	# ── 竖分隔线 ──
	var vsep = VSeparator.new()
	var vs_s = StyleBoxFlat.new()
	vs_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.2)
	vs_s.set_content_margin_all(0)
	vsep.add_theme_stylebox_override("separator", vs_s)
	vsep.add_theme_constant_override("separation", 1)
	split.add_child(vsep)

	# ── 右栏 ──
	var right_col = VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_col)

	# 标签栏
	var tab_bar = _build_tab_bar()
	right_col.add_child(tab_bar)

	# 标签内容区
	var tab_content_area = PanelContainer.new()
	tab_content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tca_s = StyleBoxFlat.new()
	tca_s.bg_color = Color(0.03, 0.05, 0.10, 0.5)
	tca_s.set_corner_radius_all(6)
	tca_s.set_content_margin_all(12)
	tab_content_area.add_theme_stylebox_override("panel", tca_s)
	right_col.add_child(tab_content_area)

	var tab_stack = Control.new()
	tab_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_content_area.add_child(tab_stack)

	# Tab 0: 游戏战绩
	var tab0 = _build_tab_game_records()
	tab0.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_stack.add_child(tab0)
	_tab_contents.append(tab0)

	# Tab 1: 能力数据
	var tab1 = _build_tab_ability_data()
	tab1.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_stack.add_child(tab1)
	_tab_contents.append(tab1)

	_switch_tab(0)

# ── 标题栏 ──

func _build_title_bar() -> Control:
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_title_bar_input)

	var title = Label.new()
	title.text = "装置档案"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.70, 0.80, 0.92, 0.9))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 13)
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
	close_btn.pressed.connect(_close_panel)
	bar.add_child(close_btn)

	return bar

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = panel.get_global_mouse_position() - panel.position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		panel.position = _clamp_pos(panel.get_global_mouse_position() - _drag_offset)

# ── 身份信息 ──

func _build_identity_section(parent: VBoxContainer) -> void:
	var dim = Color(0.45, 0.55, 0.65, 0.55)
	var bright = Color(0.75, 0.85, 0.95, 0.9)
	var accent = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.9)

	_add_info_row(parent, "型号", MODEL_NAME, dim, bright)
	_add_info_row(parent, "编号", UNIT_ID, dim, accent)
	_add_info_row(parent, "出厂", BIRTH_DATE, dim, bright)

	var launch_date = SettingsManager.get_first_launch_date()
	# 格式化: "2026-05-13T20:28:11" → "2026.05.13 20:28:11"
	var formatted = launch_date.replace("-", ".").replace("T", " ")
	_launch_label = _add_info_row(parent, "启用", formatted, dim, bright)

	# 运行天数

	_days_label = _add_info_row(parent, "运行", _calc_running_time(), dim, accent)



func _add_info_row(parent: VBoxContainer, label_text: String, value_text: String, dim: Color, bright: Color) -> Label:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", dim)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.custom_minimum_size.x = 38
	row.add_child(lbl)

	var val = Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 15)
	val.add_theme_color_override("font_color", bright)
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(val)

	parent.add_child(row)
	return val

func _calc_running_time() -> String:
	var launch_str = SettingsManager.get_first_launch_date()
	# 解析 "2026-05-13T20:28:11" 格式
	var date_part = launch_str.split("T")[0] if "T" in launch_str else launch_str.split(" ")[0]
	var time_part = launch_str.split("T")[1] if "T" in launch_str else "00:00:00"
	var dp = date_part.split("-")
	var tp = time_part.split(":")
	if dp.size() < 3:
		return "0 天 00:00:00"
	var launch_dict = {
		"year": int(dp[0]), "month": int(dp[1]), "day": int(dp[2]),
		"hour": int(tp[0]) if tp.size() > 0 else 0,
		"minute": int(tp[1]) if tp.size() > 1 else 0,
		"second": int(tp[2]) if tp.size() > 2 else 0,
	}
	var now = Time.get_datetime_dict_from_system()
	var launch_unix = Time.get_unix_time_from_datetime_dict(launch_dict)
	var now_unix = Time.get_unix_time_from_datetime_dict(now)
	var diff = maxi(0, int(now_unix - launch_unix))
	var days = diff / 86400
	var hours = (diff % 86400) / 3600
	var mins = (diff % 3600) / 60
	var secs = diff % 60
	return "%d 天 %02d:%02d:%02d" % [days, hours, mins, secs]

# ── 标签栏 ──

func _build_tab_bar() -> HBoxContainer:
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)

	var tabs = ["游戏战绩", "能力数据"]
	for i in range(tabs.size()):
		var btn = Button.new()
		btn.text = tabs[i]
		btn.add_theme_font_size_override("font_size", 14)
		btn.flat = false
		var idx = i
		btn.pressed.connect(func(): _switch_tab(idx))
		_tab_btns.append(btn)
		bar.add_child(btn)

	return bar

func _switch_tab(idx: int) -> void:
	_current_tab = idx
	for i in range(_tab_contents.size()):
		_tab_contents[i].visible = (i == idx)
	_refresh_tab_styles()

func _refresh_tab_styles() -> void:
	var accent = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85)
	for i in range(_tab_btns.size()):
		var btn = _tab_btns[i]
		var is_active = (i == _current_tab)
		if is_active:
			var s = StyleBoxFlat.new()
			s.bg_color = Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15, 0.6)
			s.set_corner_radius_all(4)
			s.border_width_bottom = 2
			s.border_color = accent
			s.content_margin_left = 12; s.content_margin_right = 12
			s.content_margin_top = 6; s.content_margin_bottom = 6
			btn.add_theme_stylebox_override("normal", s)
			btn.add_theme_stylebox_override("hover", s)
			btn.add_theme_stylebox_override("pressed", s)
			btn.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
		else:
			var s = StyleBoxFlat.new()
			s.bg_color = Color(0.06, 0.08, 0.14, 0.3)
			s.set_corner_radius_all(4)
			s.content_margin_left = 12; s.content_margin_right = 12
			s.content_margin_top = 6; s.content_margin_bottom = 6
			btn.add_theme_stylebox_override("normal", s)
			var h = s.duplicate()
			h.bg_color = Color(0.10, 0.12, 0.20, 0.5)
			btn.add_theme_stylebox_override("hover", h)
			btn.add_theme_stylebox_override("pressed", h)
			btn.add_theme_color_override("font_color", Color(0.50, 0.60, 0.70, 0.7))

# ── Tab 0: 游戏战绩 ──

func _build_tab_game_records() -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# 对局记录 2×2 网格
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	# 四个游戏卡片
	_add_game_card(grid, "策略矩阵", "tic_tac_toe", "ttt")
	_add_game_card(grid, "威胁评估", "minesweeper", "ms")
	_add_game_card(grid, "矩阵叠加", "2048", "2048")
	_add_game_card(grid, "路径规划", "snake", "snake")

	return scroll

func _add_game_card(parent: GridContainer, display_name: String, game_id: String, _card_type: String) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.08, 0.14, 0.5)
	cs.set_corner_radius_all(6)
	cs.set_border_width_all(1)
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.2)
	cs.content_margin_left = 12; cs.content_margin_right = 12
	cs.content_margin_top = 10; cs.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# 游戏名
	var title = Label.new()
	title.text = display_name
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.9, 0.9))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	var dim = Color(0.45, 0.55, 0.65, 0.6)
	var val_c = Color(0.65, 0.78, 0.92, 0.85)

	if game_id == "tic_tac_toe":
		var w = SettingsManager.get_int("game_tic_tac_toe_wins", 0)
		var l = SettingsManager.get_int("game_tic_tac_toe_losses", 0)
		var d = SettingsManager.get_int("game_tic_tac_toe_draws", 0)
		_add_stat_row(vbox, "胜 %d  负 %d  平 %d" % [w, l, d], val_c)
	else:
		for side_info in [["用户", "game_%s_" % game_id], ["宠物", "game_%s_auto_" % game_id]]:
			var side_name: String = side_info[0]
			var prefix: String = side_info[1]
			var txt: String
			match game_id:
				"2048":
					var best = SettingsManager.get_int(prefix + "best", 0)
					var tile = SettingsManager.get_int(prefix + "best_tile", 0)
					txt = "%s: 最高 %d" % [side_name, best]
					if tile > 0:
						txt += "  最大块 %d" % tile
				"snake":
					var bl = SettingsManager.get_int(prefix + "best_len", 3)
					var gm = SettingsManager.get_int(prefix + "games", 0)
					txt = "%s: 最长 %d  局数 %d" % [side_name, bl, gm]
				"minesweeper":
					var w = SettingsManager.get_int(prefix + "wins", 0)
					var l = SettingsManager.get_int(prefix + "losses", 0)
					txt = "%s: 通关 %d  触雷 %d" % [side_name, w, l]
				_:
					txt = "%s: --" % side_name
			var c = val_c if side_name == "用户" else dim
			_add_stat_row(vbox, txt, c)

func _add_stat_row(parent: VBoxContainer, text: String, color: Color) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)

# ── Tab 1: 能力数据 ──

func _build_tab_ability_data() -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var lv_info = SettingsManager.get_gaming_level_progress()
	var accent = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.9)
	var dim = Color(0.45, 0.55, 0.65, 0.55)
	var bright = Color(0.75, 0.85, 0.95, 0.9)

	# 等级标题
	_level_label = Label.new()
	_level_label.text = "游戏熟练度  Lv.%d" % lv_info.level
	_level_label.add_theme_font_size_override("font_size", 18)
	_level_label.add_theme_color_override("font_color", accent)
	vbox.add_child(_level_label)

	# XP 进度条
	var bar_w := 320.0
	_level_bar_bg = Panel.new()
	_level_bar_bg.custom_minimum_size = Vector2(bar_w, 8)
	var bar_bg_s = StyleBoxFlat.new()
	bar_bg_s.bg_color = Color(0.08, 0.10, 0.18, 0.6)
	bar_bg_s.set_corner_radius_all(4)
	_level_bar_bg.add_theme_stylebox_override("panel", bar_bg_s)
	vbox.add_child(_level_bar_bg)

	_level_bar_fill = Panel.new()
	_level_bar_fill.position = Vector2.ZERO
	_level_bar_fill.size = Vector2(bar_w * clampf(lv_info.progress, 0, 1), 8)
	var bar_fill_s = StyleBoxFlat.new()
	bar_fill_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.8)
	bar_fill_s.set_corner_radius_all(4)
	_level_bar_fill.add_theme_stylebox_override("panel", bar_fill_s)
	_level_bar_bg.add_child(_level_bar_fill)

	# XP 数值
	_xp_label = Label.new()
	if lv_info.level >= SettingsManager.MAX_LEVEL:
		_xp_label.text = "经验值: %d (MAX)" % lv_info.xp
	else:
		_xp_label.text = "经验值: %d / %d" % [lv_info.xp, lv_info.xp_next]
	_xp_label.add_theme_font_size_override("font_size", 14)
	_xp_label.add_theme_color_override("font_color", bright)
	vbox.add_child(_xp_label)

	# 失误率
	_rate_label = Label.new()
	_rate_label.text = "操作失误率: %.1f%%" % (lv_info.rate * 100.0)
	_rate_label.add_theme_font_size_override("font_size", 14)
	_rate_label.add_theme_color_override("font_color", dim)
	vbox.add_child(_rate_label)

	# 等级说明
	var note = Label.new()
	note.text = "熟练度随对局自动积累。等级越高，自主操作失误率越低。"
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.4))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(note)

	return scroll

# ═══════════════════════════════════════════════
#  宠物线稿头像 (内嵌类)
# ═══════════════════════════════════════════════

class _PetAvatar extends Control:
	var _hue: float = 0.537

	func _ready() -> void:
		_hue = EventBus.ui_hue
		EventBus.ui_theme_changed.connect(func(h): _hue = h; queue_redraw())

	func _draw() -> void:
		var cx = size.x * 0.5
		var cy = size.y * 0.5  # 正中
		var R = minf(size.x, size.y) * 0.38  # 球体半径
		var stroke_c = Color.from_hsv(_hue, 0.4, 0.85, 0.7)
		var stroke_dim = Color.from_hsv(_hue, 0.3, 0.6, 0.4)
		var highlight_c = Color.from_hsv(_hue, 0.2, 1.0, 0.85)
		var center = Vector2(cx, cy)
		var lw := 1.5  # 线宽

		# 1. 外壳 (双层描边)
		draw_arc(center, R + 1.2, 0, TAU, 64, stroke_c, lw, true)
		draw_arc(center, R, 0, TAU, 64, stroke_c, lw, true)

		# 2. 内部细环 (border ring)
		var border_r = R * 0.85
		draw_arc(center, border_r, 0, TAU, 64, Color(stroke_c, 0.5), 1.0, true)

		# 3. 深色内圆
		var base_r = R * 0.68
		draw_arc(center, base_r, 0, TAU, 48, stroke_dim, lw, true)

		# 4. 四个三角翼 (十字方向)
		var tip_dist = border_r - 1.0
		for i in range(4):
			var angle = float(i) * PI / 2.0 + PI / 4.0
			var tip = center + Vector2(cos(angle), sin(angle)) * tip_dist
			var half_hw = PI / 10.0
			var left_b = center + Vector2(cos(angle - half_hw), sin(angle - half_hw)) * (base_r * 0.95)
			var right_b = center + Vector2(cos(angle + half_hw), sin(angle + half_hw)) * (base_r * 0.95)
			draw_polyline(PackedVector2Array([left_b, tip, right_b]), stroke_dim, lw, true)

		# 5. 巩膜圆
		var sclera_r = R * 0.54
		draw_arc(center, sclera_r, 0, TAU, 48, stroke_c, lw, true)

		# 6. 虹膜三层 (正视前方，眼球居中)
		draw_arc(center, R * 0.42, 0, TAU, 40, stroke_c, lw, true)
		draw_arc(center, R * 0.28, 0, TAU, 32, stroke_c, lw, true)
		draw_arc(center, R * 0.16, 0, TAU, 24, stroke_dim, lw, true)

		# 7. 高光点 (左上角)
		var hl_pos = center + Vector2(-R * 0.08, -R * 0.10)
		draw_circle(hl_pos, R * 0.06, highlight_c)

# ═══════════════════════════════════════════════
#  面板开关
# ═══════════════════════════════════════════════

func _on_toggle() -> void:
	if panel.visible:
		_close_panel()
	else:
		_open_panel()

func _open_panel() -> void:
	EventBus.context_menu_toggled.emit(true)
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
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _close_panel() -> void:
	_dragging = false
	panel.pivot_offset = panel.size / 2.0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.1)
	tween.tween_property(panel, "scale", Vector2(0.85, 0.85), 0.1)
	tween.finished.connect(func():
		panel.hide()
		EventBus.context_menu_toggled.emit(false)
	)

func _refresh_data() -> void:
	var lv_info = SettingsManager.get_gaming_level_progress()
	var accent = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.9)

	if _level_label:
		_level_label.text = "游戏熟练度  Lv.%d" % lv_info.level
		_level_label.add_theme_color_override("font_color", accent)
	if _xp_label:
		if lv_info.level >= SettingsManager.MAX_LEVEL:
			_xp_label.text = "经验值: %d (MAX)" % lv_info.xp
		else:
			_xp_label.text = "经验值: %d / %d" % [lv_info.xp, lv_info.xp_next]
	if _level_bar_fill and _level_bar_bg:
		var bar_w = _level_bar_bg.custom_minimum_size.x
		_level_bar_fill.size = Vector2(bar_w * clampf(lv_info.progress, 0, 1), 8)
		var fs = _level_bar_fill.get_theme_stylebox("panel") as StyleBoxFlat
		if fs:
			fs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.8)
	if _rate_label:
		_rate_label.text = "操作失误率: %.1f%%" % (lv_info.rate * 100.0)
	if _days_label:
		_days_label.text = _calc_running_time()

	# 刷新游戏战绩 Tab (重建内容)
	if _tab_contents.size() > 0 and is_instance_valid(_tab_contents[0]):
		var old_tab = _tab_contents[0]
		var parent_node = old_tab.get_parent()
		old_tab.queue_free()
		var new_tab = _build_tab_game_records()
		new_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
		parent_node.add_child(new_tab)
		parent_node.move_child(new_tab, 0)
		_tab_contents[0] = new_tab
	# 刷新能力数据 Tab
	if _tab_contents.size() > 1 and is_instance_valid(_tab_contents[1]):
		var old_tab1 = _tab_contents[1]
		var parent_node1 = old_tab1.get_parent()
		old_tab1.queue_free()
		var new_tab1 = _build_tab_ability_data()
		new_tab1.set_anchors_preset(Control.PRESET_FULL_RECT)
		parent_node1.add_child(new_tab1)
		_tab_contents[1] = new_tab1
	_switch_tab(_current_tab)

# ═══════════════════════════════════════════════
#  UI 主题色
# ═══════════════════════════════════════════════

func _on_ui_theme_changed(hue: float) -> void:
	var ps = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if ps:
		ps = ps.duplicate()
		ps.border_color = Color.from_hsv(hue, 0.6, 0.85, 0.5)
		panel.add_theme_stylebox_override("panel", ps)
	_refresh_tab_styles()

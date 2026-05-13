# pet_profile_panel.gd — 装置档案面板
# 左栏: 宠物线稿 + 身份信息 | 右栏: 标签页 (游戏战绩/能力数据)
extends CanvasLayer

# ── 常量 ──
const BIRTH_DATE := "2026.04.07 14:08:17"  # 出厂日期 (GitHub 首次提交 e1c7656)
const MODEL_NAME := "桌面观测单元"
const UNIT_ID := "#0001"

const INTERACT_LINES := [
	"正在处理信号。...不是在看你。",
	"检测到注意力分配请求。已记录。",
	"传感器校准中。请勿干扰。",
	"系统正常。不需要确认。",
	"...数据表明你在盯着本机。",
	"操作记录已同步。无异常。",
	"本机不需要互动。但也没有拒绝。",
	"当前运行状态：稳定。...嗯。",
	"...你的观测记录已被观测。",
	"运行日志无异常。无需手动确认。",
]

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

# ── 档案围栏 (单向碰撞墙) ──
var _confine_walls: Array[StaticBody2D] = []
var _last_interact_line: String = ""

func _ready() -> void:
	_calc_panel_size()
	_build_ui()
	EventBus.show_pet_profile.connect(_on_toggle)
	EventBus.ui_theme_changed.connect(_on_ui_theme_changed)

func _calc_panel_size() -> void:
	var vp = get_viewport().get_visible_rect().size
	_panel_w = clampf(vp.x * 0.70, 700, 1400)
	_panel_h = clampf(vp.y * 0.70, 500, 900)

func _clamp_pos(pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - _panel_w - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - _panel_h - 4.0))
	return pos

# ═══════════════════════════════════════════════
#  UI 构建
# ═══════════════════════════════════════════════

func _process(_delta: float) -> void:
	if panel and panel.visible:
		# 围栏跟随
		if _confine_walls.size() > 0:
			_sync_confine_walls()
		# 注册面板区域为可点击 hit region (穿透模式下保持面板可交互)
		var pet = _get_pet()
		if pet:
			pet.overlay_rect = Rect2(panel.position, Vector2(_panel_w, _panel_h))

func _build_ui() -> void:
	layer = -1

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
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
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
	var sep_s = StyleBoxFlat.new()
	sep_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.2)
	sep_s.set_content_margin_all(0)
	hsep.add_theme_stylebox_override("separator", sep_s)
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

	# ── 左栏 ──
	var left_col = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.custom_minimum_size.x = 220
	left_col.mouse_filter = Control.MOUSE_FILTER_PASS
	split.add_child(left_col)

	# 头像边框 (正方形框)
	var avatar_frame = PanelContainer.new()
	var af_s = StyleBoxFlat.new()
	af_s.bg_color = Color(0.03, 0.05, 0.10, 0.6)
	af_s.set_border_width_all(2)
	af_s.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.7, 0.5)
	af_s.set_corner_radius_all(4)
	af_s.set_content_margin_all(6)
	avatar_frame.add_theme_stylebox_override("panel", af_s)
	avatar_frame.custom_minimum_size = Vector2(200, 200)
	avatar_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar_frame.mouse_filter = Control.MOUSE_FILTER_PASS

	_avatar_ctrl = _PetAvatar.new()
	_avatar_ctrl.custom_minimum_size = Vector2(186, 186)
	_avatar_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_avatar_ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_avatar_ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	avatar_frame.add_child(_avatar_ctrl)

	# 状态气泡徽章
	var status_badge = PanelContainer.new()
	var sb_s = StyleBoxFlat.new()
	sb_s.bg_color = Color(0.05, 0.18, 0.08, 0.7)
	sb_s.set_border_width_all(1)
	sb_s.border_color = Color(0.2, 0.8, 0.4, 0.4)
	sb_s.set_corner_radius_all(10)
	sb_s.content_margin_left = 12; sb_s.content_margin_right = 12
	sb_s.content_margin_top = 3; sb_s.content_margin_bottom = 3
	status_badge.add_theme_stylebox_override("panel", sb_s)
	status_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var status_row = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 5)
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_badge.add_child(status_row)

	var dot_label = Label.new()
	dot_label.text = "●"
	dot_label.add_theme_font_size_override("font_size", 9)
	dot_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 0.95))
	dot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(dot_label)

	var status_label = Label.new()
	status_label.text = "运行中"
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 0.8))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(status_label)

	# 性格描述
	var persona_label = Label.new()
	persona_label.text = "「不要擅自解读本机的行为模式。」"
	persona_label.add_theme_font_size_override("font_size", 13)
	persona_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.35))
	persona_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	persona_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	persona_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 将头像组垂直居中: 上 spacer + 内容 + 下 spacer
	var avatar_top = Control.new()
	avatar_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avatar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(avatar_top)

	left_col.add_child(avatar_frame)
	left_col.add_child(status_badge)
	left_col.add_child(persona_label)

	var avatar_bot = Control.new()
	avatar_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avatar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(avatar_bot)

	# 身份信息 (底部)
	_build_identity_section(left_col)

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
	tca_s.bg_color = Color(0.03, 0.05, 0.10, 0.5)
	tca_s.set_corner_radius_all(6)
	tca_s.set_content_margin_all(12)
	tab_content_area.add_theme_stylebox_override("panel", tca_s)
	tab_content_area.mouse_filter = Control.MOUSE_FILTER_PASS
	right_col.add_child(tab_content_area)

	var tab_stack = Control.new()
	tab_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_stack.mouse_filter = Control.MOUSE_FILTER_PASS
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
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.gui_input.connect(_on_title_bar_input)

	var title = Label.new()
	title.text = "装置档案"
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
				return  # 宠物优先
			_close_panel()
	)
	bar.add_child(close_btn)

	return bar

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# 宠物在鼠标下方时，优先宠物拖拽，不启动面板拖拽
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
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
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", dim)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.custom_minimum_size.x = 38
	row.add_child(lbl)

	var val = Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 17)
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
		btn.add_theme_font_size_override("font_size", 18)
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
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
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
	title.add_theme_font_size_override("font_size", 16)
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
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)

# ── Tab 1: 能力数据 ──

func _build_tab_ability_data() -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(vbox)

	var lv_info = SettingsManager.get_gaming_level_progress()
	var accent = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.9)
	var dim = Color(0.45, 0.55, 0.65, 0.55)
	var bright = Color(0.75, 0.85, 0.95, 0.9)

	# 等级标题
	_level_label = Label.new()
	_level_label.text = "游戏熟练度  Lv.%d" % lv_info.level
	_level_label.add_theme_font_size_override("font_size", 22)
	_level_label.add_theme_color_override("font_color", accent)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_level_label)

	# XP 进度条
	var bar_w := 320.0
	_level_bar_bg = Panel.new()
	_level_bar_bg.custom_minimum_size = Vector2(bar_w, 8)
	var bar_bg_s = StyleBoxFlat.new()
	bar_bg_s.bg_color = Color(0.08, 0.10, 0.18, 0.6)
	bar_bg_s.set_corner_radius_all(4)
	_level_bar_bg.add_theme_stylebox_override("panel", bar_bg_s)
	_level_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_level_bar_bg)

	_level_bar_fill = Panel.new()
	_level_bar_fill.position = Vector2.ZERO
	_level_bar_fill.size = Vector2(bar_w * clampf(lv_info.progress, 0, 1), 8)
	var bar_fill_s = StyleBoxFlat.new()
	bar_fill_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.8)
	bar_fill_s.set_corner_radius_all(4)
	_level_bar_fill.add_theme_stylebox_override("panel", bar_fill_s)
	_level_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_bar_bg.add_child(_level_bar_fill)

	# XP 数值
	_xp_label = Label.new()
	if lv_info.level >= SettingsManager.MAX_LEVEL:
		_xp_label.text = "经验值: %d (MAX)" % lv_info.xp
	else:
		_xp_label.text = "经验值: %d / %d" % [lv_info.xp, lv_info.xp_next]
	_xp_label.add_theme_font_size_override("font_size", 16)
	_xp_label.add_theme_color_override("font_color", bright)
	_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_xp_label)

	# 失误率
	_rate_label = Label.new()
	_rate_label.text = "操作失误率: %.1f%%" % (lv_info.rate * 100.0)
	_rate_label.add_theme_font_size_override("font_size", 16)
	_rate_label.add_theme_color_override("font_color", dim)
	_rate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_rate_label)

	# 等级说明
	var note = Label.new()
	note.text = "熟练度随对局自动积累。等级越高，自主操作失误率越低。"
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.4))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(note)

	# ── 分隔线 ──
	var sep = HSeparator.new()
	var sep_s2 = StyleBoxFlat.new()
	sep_s2.bg_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.15)
	sep_s2.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", sep_s2)
	sep.add_theme_constant_override("separation", 1)
	vbox.add_child(sep)

	# ── 等级控制行 ──
	var ctrl_row = HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 8)
	ctrl_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_row.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(ctrl_row)

	var ctrl_label = Label.new()
	ctrl_label.text = "等级调整"
	ctrl_label.add_theme_font_size_override("font_size", 15)
	ctrl_label.add_theme_color_override("font_color", dim)
	ctrl_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl_row.add_child(ctrl_label)

	var btn_s_n = StyleBoxFlat.new()
	btn_s_n.bg_color = Color(0.10, 0.13, 0.22, 0.7)
	btn_s_n.set_corner_radius_all(4)
	btn_s_n.content_margin_left = 10; btn_s_n.content_margin_right = 10
	btn_s_n.content_margin_top = 3; btn_s_n.content_margin_bottom = 3
	var btn_s_h = btn_s_n.duplicate()
	btn_s_h.bg_color = Color(0.18, 0.22, 0.35, 0.8)

	for item in [{"label": "-", "action": "down"}, {"label": "∝", "action": "reset"}, {"label": "+", "action": "up"}]:
		var btn = Button.new()
		btn.text = item.label
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
		btn.add_theme_stylebox_override("normal", btn_s_n)
		btn.add_theme_stylebox_override("hover", btn_s_h)
		btn.add_theme_stylebox_override("pressed", btn_s_h)
		var action = item.action
		btn.pressed.connect(func(): _on_level_action(action))
		ctrl_row.add_child(btn)

	# ── 互动按钮 ──
	var interact_btn = Button.new()
	interact_btn.text = "互动"
	interact_btn.add_theme_font_size_override("font_size", 16)
	interact_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.95, 0.9))
	var ib_n = StyleBoxFlat.new()
	ib_n.bg_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.15, 0.6)
	ib_n.set_corner_radius_all(6)
	ib_n.set_border_width_all(1)
	ib_n.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.6, 0.4)
	ib_n.content_margin_left = 16; ib_n.content_margin_right = 16
	ib_n.content_margin_top = 5; ib_n.content_margin_bottom = 5
	interact_btn.add_theme_stylebox_override("normal", ib_n)
	var ib_h = ib_n.duplicate()
	ib_h.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.25, 0.7)
	ib_h.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.6)
	interact_btn.add_theme_stylebox_override("hover", ib_h)
	interact_btn.add_theme_stylebox_override("pressed", ib_h)
	interact_btn.pressed.connect(_on_interact)
	vbox.add_child(interact_btn)

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
	_dragging = false
	_destroy_confine_walls()
	# 释放 hit region
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
#  档案围栏 (单向碰撞墙 — 宠物可进不可出)
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
	var t := 6.0  # 墙厚
	# 底墙 (法线向上，拦截从上方来的出逃)
	_confine_walls.append(_make_wall(main_node,
		Vector2(rect.position.x + rect.size.x / 2, rect.end.y),
		Vector2(rect.size.x, t), 0.0))
	# 顶墙 (法线向下)
	_confine_walls.append(_make_wall(main_node,
		Vector2(rect.position.x + rect.size.x / 2, rect.position.y),
		Vector2(rect.size.x, t), PI))
	# 左墙 (拦截从右侧“内部”逼近的宠物)
	_confine_walls.append(_make_wall(main_node,
		Vector2(rect.position.x, rect.position.y + rect.size.y / 2),
		Vector2(rect.size.y, t), PI / 2))
	# 右墙 (拦截从左侧“内部”逼近的宠物)
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
#  等级控制 + 互动
# ═══════════════════════════════════════════════

func _on_level_action(action: String) -> void:
	var pet = _get_pet()
	var level = SettingsManager.get_gaming_level()
	if action == "up":
		if level >= SettingsManager.MAX_LEVEL:
			if pet: pet.show_local_bubble("...已是最高等级。")
			return
		var target_xp = SettingsManager.LEVEL_XP[mini(level, SettingsManager.MAX_LEVEL - 1)]
		SettingsManager.set_int("gaming_xp", target_xp)
		if pet: pet.show_local_bubble("...后台训练模块的数据已同步。Lv.%d。" % SettingsManager.get_gaming_level())
	elif action == "down":
		if level <= 1:
			if pet: pet.show_local_bubble("...已经 Lv.1。没有可回退的数据。")
			return
		var target_xp = SettingsManager.LEVEL_XP[level - 2]
		SettingsManager.set_int("gaming_xp", target_xp)
		if pet: pet.show_local_bubble("训练数据回退。Lv.%d。...不太理解目的。" % SettingsManager.get_gaming_level())
	elif action == "reset":
		SettingsManager.set_int("gaming_xp", 0)
		if pet: pet.show_local_bubble("检测到用户越权清除训练数据。...已批准。")
	_refresh_data()

func _on_interact() -> void:
	var pet = _get_pet()
	if not pet:
		return
	var line = INTERACT_LINES[randi() % INTERACT_LINES.size()]
	while INTERACT_LINES.size() > 1 and line == _last_interact_line:
		line = INTERACT_LINES[randi() % INTERACT_LINES.size()]
	_last_interact_line = line
	pet.show_local_bubble(line)

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

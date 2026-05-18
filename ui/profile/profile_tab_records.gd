# profile_tab_records.gd — 游戏战绩 Tab
# [占位符状态] 战绩数据接入待规划，当前展示结构骨架
extends HBoxContainer

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER # 彻底隐形原生滚动条
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# 为了不让卡片紧挨着边缘，套一层边距
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.add_child(vbox)
	scroll.add_child(margin)

	_add_game_card(vbox, "策略矩阵", "tic_tac_toe")
	_add_game_card(vbox, "威胁评估", "minesweeper")
	_add_game_card(vbox, "矩阵叠加", "2048")
	_add_game_card(vbox, "路径规划", "snake")
	_add_game_card(vbox, "结构堆叠", "tetris")

	# ── 底部占位说明区 ──
	_build_placeholder_zone(vbox)
	
	# ── 独立科幻滚动指示器 ──
	var indicator = preload("res://ui/profile/cyber_scroll_indicator.gd").new()
	indicator.bind_scroll(scroll)
	add_child(indicator)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	build()

# ── 工业质感复古终端排版 (水平分栏样式) ──
func _add_game_card(parent: Control, display_name: String, game_id: String) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.16, 0.45) # 融入主题色的水晶玻璃底，消除死沉的致郁感
	cs.border_width_left = 4
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.7) # 强化左侧生命呼吸线
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 20; cs.content_margin_right = 20
	cs.content_margin_top = 16; cs.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	# 标题行
	var title_row = HBoxContainer.new()
	var t_sub = Label.new()
	t_sub.text = "DATA_LOG //"
	t_sub.add_theme_font_size_override("font_size", 11)
	t_sub.add_theme_color_override("font_color", Color(0.35, 0.4, 0.45))
	title_row.add_child(t_sub)

	var t_main = Label.new()
	t_main.text = display_name
	t_main.add_theme_font_size_override("font_size", 15)
	t_main.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95)) # 高级亮白灰字
	title_row.add_child(t_main)
	vbox.add_child(title_row)

	var hsep = HSeparator.new()
	var s_sep = StyleBoxFlat.new()
	s_sep.border_width_top = 1
	s_sep.border_color = Color(1.0, 1.0, 1.0, 0.05) # 极微弱的透亮分割线
	hsep.add_theme_stylebox_override("separator", s_sep)
	hsep.add_theme_constant_override("separation", 1)
	vbox.add_child(hsep)

	# 左右分栏数据区
	var content_area = HBoxContainer.new()
	content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.add_theme_constant_override("separation", 24)
	vbox.add_child(content_area)

	var txt_fac_sys = Color.from_hsv(EventBus.ui_hue, 0.3, 0.7) # 带点微光的系统侧标签
	var txt_fac_usr = Color.from_hsv(EventBus.ui_hue, 0.4, 0.9)
	var val_sys = Color.from_hsv(EventBus.ui_hue, 0.2, 0.85, 0.9) # 透亮不刺眼的数据晶灰，告别死灰质感
	var val_usr = Color.from_hsv(EventBus.ui_hue, 0.6, 0.95) # USR 数据强烈高亮

	# [占位符] 所有游戏均以 "—" 填充，待战绩系统规划后接入
	if game_id == "tic_tac_toe":
		_build_faction_group(content_area, "GLOBAL > 评估结果", txt_fac_usr, [
			{"lbl": "获胜", "val": "—", "c": val_usr},
			{"lbl": "落败", "val": "—", "c": txt_fac_sys},
			{"lbl": "平局", "val": "—", "c": txt_fac_sys}
		])
	else:
		var sys_stats: Array = []
		var usr_stats: Array = []
		match game_id:
			"2048":
				sys_stats.append({"lbl": "推演极限", "val": "—", "c": val_sys})
				sys_stats.append({"lbl": "单块算力", "val": "—", "c": val_sys})
				usr_stats.append({"lbl": "历史最高", "val": "—", "c": val_usr})
				usr_stats.append({"lbl": "单块极限", "val": "—", "c": val_usr})
			"snake":
				sys_stats.append({"lbl": "最长寻路", "val": "—", "c": val_sys})
				sys_stats.append({"lbl": "推演局数", "val": "—", "c": val_sys})
				usr_stats.append({"lbl": "最长存活", "val": "—", "c": val_usr})
				usr_stats.append({"lbl": "投入局数", "val": "—", "c": val_usr})
			"minesweeper":
				sys_stats.append({"lbl": "清除威胁", "val": "—", "c": val_sys})
				sys_stats.append({"lbl": "算力超载", "val": "—", "c": txt_fac_sys})
				usr_stats.append({"lbl": "排除威胁", "val": "—", "c": val_usr})
				usr_stats.append({"lbl": "触雷损毁", "val": "—", "c": txt_fac_sys})
			"tetris":
				sys_stats.append({"lbl": "算力封顶", "val": "—", "c": val_sys})
				sys_stats.append({"lbl": "阵列降维", "val": "—", "c": val_sys})
				usr_stats.append({"lbl": "最高得分", "val": "—", "c": val_usr})
				usr_stats.append({"lbl": "总消行数", "val": "—", "c": val_usr})
		
		# 添加系统与玩家并排比对
		_build_faction_group(content_area, "SYS > 本机系统", txt_fac_sys, sys_stats)
		var vsep = VSeparator.new()
		var s_vs = StyleBoxFlat.new()
		s_vs.border_width_left = 1
		s_vs.border_color = Color(1.0, 1.0, 1.0, 0.04) # 微弱的区分线
		s_vs.content_margin_top = 8; s_vs.content_margin_bottom = 8
		vsep.add_theme_stylebox_override("separator", s_vs)
		content_area.add_child(vsep)
		_build_faction_group(content_area, "USR > 操作员", txt_fac_usr, usr_stats)

func _build_faction_group(parent: Control, fac_name: String, fac_color: Color, stat_array: Array) -> void:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 8)
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var fn = Label.new()
	fn.text = fac_name
	fn.add_theme_font_size_override("font_size", 11)
	fn.add_theme_color_override("font_color", fac_color)
	group.add_child(fn)
	
	var stat_grid = HBoxContainer.new()
	stat_grid.add_theme_constant_override("separation", 10)
	stat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(stat_grid)
	
	for stat in stat_array:
		_add_stat_cell(stat_grid, stat.lbl, stat.val, stat.c)
	parent.add_child(group)

func _add_stat_cell(parent: Control, lbl: String, val: String, val_color: Color) -> void:
	var pnl = PanelContainer.new()
	pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.08, 0.5) # 极深的带色凹槽背景，不纯黑不死板
	s.border_width_left = 2
	s.border_color = Color(val_color.r, val_color.g, val_color.b, maxf(val_color.a * 0.6, 0.3))
	s.set_corner_radius_all(2)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 8; s.content_margin_bottom = 8
	pnl.add_theme_stylebox_override("panel", s)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", -1)
	
	var l = Label.new()
	l.text = lbl
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	vb.add_child(l)
	
	var v = Label.new()
	v.text = val
	v.add_theme_font_size_override("font_size", 17)
	v.add_theme_color_override("font_color", val_color)
	vb.add_child(v)
	
	pnl.add_child(vb)
	parent.add_child(pnl)

# ── 占位说明区 (原数据归零功能暂停，战绩系统规划后重新接入) ──
func _build_placeholder_zone(parent: Control) -> void:
	var pnl = PanelContainer.new()
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.06, 0.10, 0.4)
	s.set_border_width_all(1)
	s.border_color = Color(0.3, 0.4, 0.6, 0.25)
	s.set_corner_radius_all(2)
	s.content_margin_left = 16; s.content_margin_right = 16
	s.content_margin_top = 12; s.content_margin_bottom = 12
	pnl.add_theme_stylebox_override("panel", s)
	parent.add_child(pnl)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pnl.add_child(vb)
	
	var title = Label.new()
	title.text = "STATUS // 数据接入待规划"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.7))
	vb.add_child(title)
	
	var desc = Label.new()
	desc.text = "战绩持久化系统尚未接入。当前展示为结构占位符。"
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc)

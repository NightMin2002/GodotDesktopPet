# profile_tab_records.gd — 游戏战绩 Tab
extends ScrollContainer

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	var vbox = ProfileStyles.make_tab_vbox(10)
	add_child(vbox)

	# 对局记录 2 列网格 (自动换行，第 5 张卡独占行)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	_add_game_card(grid, "策略矩阵", "tic_tac_toe")
	_add_game_card(grid, "威胁评估", "minesweeper")
	_add_game_card(grid, "矩阵叠加", "2048")
	_add_game_card(grid, "路径规划", "snake")
	_add_game_card(grid, "结构堆叠", "tetris")

	# ── 底部清除按钮 ──
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	var reset_btn = Button.new()
	reset_btn.text = "数据归零"
	reset_btn.flat = true
	reset_btn.add_theme_font_size_override("font_size", 11)
	reset_btn.add_theme_color_override("font_color", Color(0.45, 0.35, 0.35, 0.4))
	reset_btn.add_theme_color_override("font_hover_color", Color(0.85, 0.3, 0.3, 0.7))
	reset_btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.2, 0.2, 0.9))
	reset_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	reset_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var state := {"pending": false}
	reset_btn.pressed.connect(func():
		if not state.pending:
			state.pending = true
			reset_btn.text = "确认清除全部战绩？"
			reset_btn.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3, 0.7))
			# 3 秒后自动恢复
			var tw = reset_btn.create_tween()
			tw.tween_interval(3.0)
			tw.tween_callback(func():
				if is_instance_valid(reset_btn):
					state.pending = false
					reset_btn.text = "数据归零"
					reset_btn.add_theme_color_override("font_color", Color(0.45, 0.35, 0.35, 0.4))
			)
		else:
			state.pending = false
			_clear_all_game_records()
			refresh()
	)
	vbox.add_child(reset_btn)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	build()

# ── 清除全部战绩 ──

func _clear_all_game_records() -> void:
	# 枚举所有游戏的存储 key 全部归零
	var game_keys := [
		# tic_tac_toe (无 auto 分栏)
		"game_tic_tac_toe_wins", "game_tic_tac_toe_losses", "game_tic_tac_toe_draws",
		# minesweeper
		"game_minesweeper_wins", "game_minesweeper_losses",
		"game_minesweeper_auto_wins", "game_minesweeper_auto_losses",
		# 2048
		"game_2048_best", "game_2048_best_tile",
		"game_2048_auto_best", "game_2048_auto_best_tile",
		# snake
		"game_snake_best_len", "game_snake_games",
		"game_snake_auto_best_len", "game_snake_auto_games",
		# tetris
		"game_tetris_best", "game_tetris_games", "game_tetris_lines",
		"game_tetris_auto_best", "game_tetris_auto_games", "game_tetris_auto_lines",
	]
	for key in game_keys:
		SettingsManager.set_int(key, 0)

# ── 游戏机能风看板阵列 ──

func _add_game_card(parent: GridContainer, display_name: String, game_id: String) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", ProfileStyles.card_style())
	ProfileStyles.add_tech_brackets(card, 5.0)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	# 一级主标题
	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim("分析模块 //", 10))
	title_row.add_child(ProfileStyles.title_label(display_name, 15))
	vbox.add_child(title_row)

	var hsep = HSeparator.new()
	hsep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	vbox.add_child(hsep)
	
	var v_stats = VBoxContainer.new()
	v_stats.add_theme_constant_override("separation", 12)
	vbox.add_child(v_stats)

	if game_id == "tic_tac_toe":
		var w = SettingsManager.get_int("game_tic_tac_toe_wins", 0)
		var l = SettingsManager.get_int("game_tic_tac_toe_losses", 0)
		var d = SettingsManager.get_int("game_tic_tac_toe_draws", 0)
		_build_faction_group(v_stats, "综合评估结果", [
			{"lbl": "获胜", "val": w, "c": ProfileStyles.val_color()},
			{"lbl": "落败", "val": l, "c": ProfileStyles.dim()},
			{"lbl": "平局", "val": d, "c": ProfileStyles.dim()}
		])
	else:
		for side_info in [["SYS > 本机系统", "game_%s_auto_" % game_id, false], ["USR > 操作员", "game_%s_" % game_id, true]]:
			var side_name: String = side_info[0]
			var prefix: String = side_info[1]
			var is_usr: bool = side_info[2]
			var c = ProfileStyles.val_color() if is_usr else ProfileStyles.dim()
			
			var stats_data = []
			match game_id:
				"2048":
					var best = SettingsManager.get_int(prefix + "best", 0)
					var tile = SettingsManager.get_int(prefix + "best_tile", 0)
					stats_data.append({"lbl": "历史最高", "val": best, "c": c})
					if tile > 0:
						stats_data.append({"lbl": "单块极限", "val": tile, "c": c})
				"snake":
					var bl = SettingsManager.get_int(prefix + "best_len", 3)
					var gm = SettingsManager.get_int(prefix + "games", 0)
					stats_data.append({"lbl": "最长存活", "val": bl, "c": c})
					stats_data.append({"lbl": "投入局数", "val": gm, "c": c})
				"minesweeper":
					var w = SettingsManager.get_int(prefix + "wins", 0)
					var l = SettingsManager.get_int(prefix + "losses", 0)
					stats_data.append({"lbl": "排除威胁", "val": w, "c": c})
					stats_data.append({"lbl": "触雷损毁", "val": l, "c": c})
				"tetris":
					var best = SettingsManager.get_int(prefix + "best", 0)
					var lines = SettingsManager.get_int(prefix + "lines", 0)
					var gm = SettingsManager.get_int(prefix + "games", 0)
					stats_data.append({"lbl": "最高得分", "val": best, "c": c})
					stats_data.append({"lbl": "总消行数", "val": lines, "c": c})
					stats_data.append({"lbl": "堆叠局数", "val": gm, "c": c})
					
			_build_faction_group(v_stats, side_name, stats_data)


# ── 数据流式插槽渲染工厂 ──

func _build_faction_group(parent: Control, faction_name: String, stat_array: Array) -> void:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 6)
	
	# 二级标签头部
	var fac_row = HBoxContainer.new()
	fac_row.add_theme_constant_override("separation", 6)
	var dot = Panel.new()
	dot.custom_minimum_size = Vector2(4, 4)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ds = StyleBoxFlat.new()
	ds.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8)
	dot.add_theme_stylebox_override("panel", ds)
	fac_row.add_child(dot)
	
	var fac_lbl = ProfileStyles.label_dim(faction_name, 11)
	fac_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.8))
	fac_row.add_child(fac_lbl)
	group.add_child(fac_row)
	
	# 等宽数据格栅
	var stat_grid = HBoxContainer.new()
	stat_grid.add_theme_constant_override("separation", 8)
	stat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(stat_grid)
	
	for stat in stat_array:
		_add_stat_cell(stat_grid, stat.lbl, str(stat.val), stat.c)
		
	parent.add_child(group)

func _add_stat_cell(parent: Control, lbl: String, val: String, val_color: Color) -> void:
	var pnl = PanelContainer.new()
	pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# 数据槽包裹样式
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.01, 0.02, 0.05, 0.3)
	s.border_width_left = 2
	s.border_width_bottom = 1
	s.border_color = Color(val_color.r, val_color.g, val_color.b, maxf(val_color.a, 0.5))
	s.content_margin_left = 8; s.content_margin_right = 8
	s.content_margin_top = 4; s.content_margin_bottom = 4
	pnl.add_theme_stylebox_override("panel", s)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	vb.add_child(ProfileStyles.label_dim(lbl, 10))
	vb.add_child(ProfileStyles.make_label(val, 16, val_color))
	pnl.add_child(vb)
	
	parent.add_child(pnl)

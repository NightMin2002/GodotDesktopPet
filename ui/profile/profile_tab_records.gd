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

	# 对局记录 2x2 网格
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

func refresh() -> void:
	# 完全重建内容
	for child in get_children():
		child.queue_free()
	build()

# ── 游戏卡片 ──

func _add_game_card(parent: GridContainer, display_name: String, game_id: String) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", ProfileStyles.card_style())
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	vbox.add_child(ProfileStyles.make_label(
		display_name, 16,
		Color.from_hsv(EventBus.ui_hue, 0.4, 0.9, 0.9)
	))

	var dim = ProfileStyles.dim()
	var val_c = ProfileStyles.val_color()

	if game_id == "tic_tac_toe":
		var w = SettingsManager.get_int("game_tic_tac_toe_wins", 0)
		var l = SettingsManager.get_int("game_tic_tac_toe_losses", 0)
		var d = SettingsManager.get_int("game_tic_tac_toe_draws", 0)
		_add_stat(vbox, "胜 %d  负 %d  平 %d" % [w, l, d], val_c)
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
			_add_stat(vbox, txt, c)

func _add_stat(parent: VBoxContainer, text: String, color: Color) -> void:
	parent.add_child(ProfileStyles.make_label(text, 14, color))

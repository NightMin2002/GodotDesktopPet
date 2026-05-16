# terminal_ttt.gd — 终端原生井字棋 (策略矩阵)
# 直接在游戏终端内容区渲染，_draw 自绘 + minimax AI
# 自包含: 棋盘 + 输入 + AI + 结算覆盖 + 重开按钮
extends Control

signal game_started
signal game_over(result: int)  # 0=玩家胜, 1=AI胜, 2=平局

# ── 棋盘状态 ──
var _board: Array[int] = [0,0,0, 0,0,0, 0,0,0]  # 0=空, 1=玩家(X), 2=AI(O)
var _game_active: bool = false
var _player_turn: bool = true
var _hover_cell: int = -1
var _win_line: Array[int] = []
var _result: int = -1  # -1=进行中, 0=胜, 1=负, 2=平

# ── 布局 ──
var _grid_size: float = 0.0
var _grid_origin: Vector2 = Vector2.ZERO
var _cell_size: float = 0.0
var _time: float = 0.0

# ── 结算 UI ──
var _result_overlay: Control = null
var _result_label: Label = null
var _restart_btn: Button = null

# ══════════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════════

func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	gui_input.connect(_on_input)
	_build_result_overlay()
	start_game()

func _process(delta: float) -> void:
	_time += delta
	# 胜负线动画 或 hover 时持续重绘
	if _win_line.size() > 0 or _game_active:
		queue_redraw()

func start_game() -> void:
	_board = [0,0,0, 0,0,0, 0,0,0]
	_game_active = true
	_player_turn = true
	_hover_cell = -1
	_win_line = []
	_result = -1
	if _result_overlay:
		_result_overlay.visible = false
	game_started.emit()
	queue_redraw()

# ══════════════════════════════════════════════
#  布局计算
# ══════════════════════════════════════════════

func _calc_layout() -> void:
	var available = minf(size.x, size.y) * 0.78
	_grid_size = available
	_cell_size = _grid_size / 3.0
	_grid_origin = Vector2(
		(size.x - _grid_size) * 0.5,
		(size.y - _grid_size) * 0.5
	)

func _cell_rect(idx: int) -> Rect2:
	var row = idx / 3
	var col = idx % 3
	return Rect2(
		_grid_origin + Vector2(col * _cell_size, row * _cell_size),
		Vector2(_cell_size, _cell_size)
	)

func _cell_center(idx: int) -> Vector2:
	return _cell_rect(idx).get_center()

func _hit_test(pos: Vector2) -> int:
	for i in range(9):
		if _cell_rect(i).has_point(pos):
			return i
	return -1

# ══════════════════════════════════════════════
#  输入
# ══════════════════════════════════════════════

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var old = _hover_cell
		_hover_cell = _hit_test(event.position)
		if old != _hover_cell:
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _game_active or not _player_turn:
			return
		var cell = _hit_test(event.position)
		if cell >= 0 and _board[cell] == 0:
			_place(cell, 1)
			_check_end()
			if _game_active:
				_player_turn = false
				get_tree().create_timer(0.35).timeout.connect(_ai_move)

func _place(idx: int, player: int) -> void:
	_board[idx] = player
	queue_redraw()

# ══════════════════════════════════════════════
#  Minimax AI
# ══════════════════════════════════════════════

func _ai_move() -> void:
	if not _game_active:
		return
	var best = _minimax_best()
	if best >= 0:
		_place(best, 2)
		_check_end()
	_player_turn = true

func _minimax_best() -> int:
	var best_score = -999
	var best_move = -1
	for i in range(9):
		if _board[i] == 0:
			_board[i] = 2
			var score = _minimax(false, 0)
			_board[i] = 0
			if score > best_score:
				best_score = score
				best_move = i
	return best_move

func _minimax(is_ai: bool, depth: int) -> int:
	var winner = _check_winner()
	if winner == 2: return 10 - depth
	if winner == 1: return depth - 10
	if _is_full(): return 0

	if is_ai:
		var best = -999
		for i in range(9):
			if _board[i] == 0:
				_board[i] = 2
				best = maxi(best, _minimax(false, depth + 1))
				_board[i] = 0
		return best
	else:
		var best = 999
		for i in range(9):
			if _board[i] == 0:
				_board[i] = 1
				best = mini(best, _minimax(true, depth + 1))
				_board[i] = 0
		return best

# ══════════════════════════════════════════════
#  胜负检测
# ══════════════════════════════════════════════

const _LINES = [
	[0,1,2],[3,4,5],[6,7,8],
	[0,3,6],[1,4,7],[2,5,8],
	[0,4,8],[2,4,6]
]

func _check_winner() -> int:
	for line in _LINES:
		if _board[line[0]] != 0 and _board[line[0]] == _board[line[1]] and _board[line[1]] == _board[line[2]]:
			return _board[line[0]]
	return 0

func _is_full() -> bool:
	for cell in _board:
		if cell == 0: return false
	return true

func _check_end() -> void:
	var winner = _check_winner()
	if winner > 0:
		_game_active = false
		_find_win_line(winner)
		_result = 0 if winner == 1 else 1
		_show_result()
		game_over.emit(_result)
	elif _is_full():
		_game_active = false
		_result = 2
		_show_result()
		game_over.emit(_result)

func _find_win_line(winner: int) -> void:
	for line in _LINES:
		if _board[line[0]] == winner and _board[line[1]] == winner and _board[line[2]] == winner:
			_win_line = [line[0], line[1], line[2]]
			return

# ══════════════════════════════════════════════
#  结算覆盖层
# ══════════════════════════════════════════════

func _build_result_overlay() -> void:
	_result_overlay = PanelContainer.new()
	_result_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_overlay.visible = false
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.03, 0.06, 0.75)
	s.set_corner_radius_all(0)
	_result_overlay.add_theme_stylebox_override("panel", s)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_result_overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	center.add_child(vbox)

	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 24)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_result_label)

	_restart_btn = Button.new()
	_restart_btn.text = "再来一局"
	_restart_btn.add_theme_font_size_override("font_size", 16)
	var bs = GameTerminalStyles.small_btn_normal()
	bs.content_margin_left = 24; bs.content_margin_right = 24
	bs.content_margin_top = 8; bs.content_margin_bottom = 8
	_restart_btn.add_theme_stylebox_override("normal", bs)
	_restart_btn.add_theme_stylebox_override("hover", GameTerminalStyles.small_btn_hover())
	_restart_btn.add_theme_stylebox_override("pressed", GameTerminalStyles.small_btn_hover())
	_restart_btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.9))
	_restart_btn.add_theme_color_override("font_hover_color", GameTerminalStyles.accent())
	_restart_btn.pressed.connect(start_game)
	vbox.add_child(_restart_btn)

	add_child(_result_overlay)

var _result_lines_win := ["...算你赢。", "结果在预测范围内。", "数据偏差已记录。"]
var _result_lines_lose := ["意料之中。", "对局分析完毕。胜率: 100%。", "推演结束。"]
var _result_lines_draw := ["...势均力敌。", "决策树收敛。", "对称博弈。"]

func _show_result() -> void:
	if not _result_overlay:
		return
	var lines: Array
	var color: Color
	match _result:
		0:
			lines = _result_lines_win
			color = GameTerminalStyles.status_active()
		1:
			lines = _result_lines_lose
			color = Color(0.9, 0.55, 0.3, 0.9)
		2:
			lines = _result_lines_draw
			color = GameTerminalStyles.dim()
	_result_label.text = lines[randi() % lines.size()]
	_result_label.add_theme_color_override("font_color", color)
	_result_overlay.visible = true

# ══════════════════════════════════════════════
#  渲染
# ══════════════════════════════════════════════

func _draw() -> void:
	_calc_layout()
	var hue = EventBus.ui_hue

	# ── 棋盘底色 ──
	var grid_bg = Color(0.03, 0.05, 0.08, 0.3)
	draw_rect(Rect2(_grid_origin, Vector2(_grid_size, _grid_size)), grid_bg)

	# ── 网格线 ──
	var line_c = Color.from_hsv(hue, 0.3, 0.55, 0.35)
	for i in range(1, 3):
		var x = _grid_origin.x + i * _cell_size
		draw_line(Vector2(x, _grid_origin.y + 4), Vector2(x, _grid_origin.y + _grid_size - 4), line_c, 1.5)
		var y = _grid_origin.y + i * _cell_size
		draw_line(Vector2(_grid_origin.x + 4, y), Vector2(_grid_origin.x + _grid_size - 4, y), line_c, 1.5)

	# ── 格位坐标标注 (战术风格) ──
	var coord_c = Color.from_hsv(hue, 0.2, 0.4, 0.15)
	var coord_labels = ["A1","A2","A3","B1","B2","B3","C1","C2","C3"]
	for i in range(9):
		var cr = _cell_rect(i)
		var font = ThemeDB.fallback_font
		draw_string(font, cr.position + Vector2(4, 13), coord_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, coord_c)

	# ── 悬停高亮 ──
	if _hover_cell >= 0 and _game_active and _player_turn and _board[_hover_cell] == 0:
		var hr = _cell_rect(_hover_cell).grow(-2)
		draw_rect(hr, Color.from_hsv(hue, 0.3, 0.5, 0.06))
		# 预览 X (虚化)
		var preview_c = Color.from_hsv(hue, 0.5, 0.8, 0.15)
		var ctr = _cell_center(_hover_cell)
		var pad = _cell_size * 0.22
		var half = _cell_size * 0.5 - pad
		draw_line(ctr + Vector2(-half, -half), ctr + Vector2(half, half), preview_c, 2.0, true)
		draw_line(ctr + Vector2(half, -half), ctr + Vector2(-half, half), preview_c, 2.0, true)

	# ── 棋子 ──
	var pad = _cell_size * 0.22
	for i in range(9):
		if _board[i] == 0: continue
		var center = _cell_center(i)
		var half = _cell_size * 0.5 - pad
		if _board[i] == 1:
			# X — 玩家 (主题色)
			var x_c = Color.from_hsv(hue, 0.6, 0.95, 0.9)
			var x_glow = Color.from_hsv(hue, 0.5, 0.95, 0.15)
			draw_line(center + Vector2(-half, -half), center + Vector2(half, half), x_glow, 8.0, true)
			draw_line(center + Vector2(half, -half), center + Vector2(-half, half), x_glow, 8.0, true)
			draw_line(center + Vector2(-half, -half), center + Vector2(half, half), x_c, 2.5, true)
			draw_line(center + Vector2(half, -half), center + Vector2(-half, half), x_c, 2.5, true)
		else:
			# O — AI (琥珀色)
			var o_c = Color(0.9, 0.55, 0.3, 0.85)
			var o_glow = Color(0.9, 0.55, 0.3, 0.12)
			draw_arc(center, half, 0, TAU, 48, o_glow, 8.0, true)
			draw_arc(center, half, 0, TAU, 48, o_c, 2.0, true)

	# ── 胜负线 ──
	if _win_line.size() == 3:
		var pulse = (sin(_time * 8.0) * 0.3 + 0.7)
		var wc: Color
		if _result == 0:
			wc = Color.from_hsv(hue, 0.5, 1.0, pulse)
		else:
			wc = Color(0.9, 0.35, 0.3, pulse)
		var p1 = _cell_center(_win_line[0])
		var p2 = _cell_center(_win_line[2])
		draw_line(p1, p2, Color(wc.r, wc.g, wc.b, 0.12), 20.0, true)
		draw_line(p1, p2, wc, 3.5, true)

	# ── 外框包边 ──
	var frame_c = Color.from_hsv(hue, 0.4, 0.6, 0.2)
	draw_rect(Rect2(_grid_origin, Vector2(_grid_size, _grid_size)), frame_c, false, 1.0)

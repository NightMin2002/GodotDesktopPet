# terminal_ttt.gd — 终端原生井字棋 (策略矩阵)
# 直接在游戏终端内容区渲染，_draw 自绘 + minimax AI
# 精密仪器风格 (移植自旧版 games/tic_tac_toe)
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

# ── 落子动画 ──
var _cell_anims: Array[float] = [0.0,0.0,0.0, 0.0,0.0,0.0, 0.0,0.0,0.0]  # 每格动画进度 0→1

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

## HUD 协议: 返回当前游戏状态数据
func get_hud_data() -> Dictionary:
	var turn_text: String
	var turn_color: Color
	if not _game_active:
		turn_text = "已结束"
		turn_color = GameTerminalStyles.dim()
	elif _player_turn:
		turn_text = "USR"
		turn_color = GameTerminalStyles.status_active()
	else:
		turn_text = "SYS"
		turn_color = GameTerminalStyles.status_warning()
	# 统计棋子数
	var placed := 0
	for cell in _board:
		if cell != 0:
			placed += 1
	return {
		"turn": { "label": "回合", "value": turn_text, "color": turn_color },
		"moves": { "label": "落子", "value": "%d/9" % placed, "color": GameTerminalStyles.dim() },
	}

## 自玩 AI: 每步操作 (终端骨架通过 Timer 调用)
func auto_play_step() -> void:
	if not _game_active or not _player_turn:
		return
	# 用 minimax 为“玩家”找最佳位置 (AI 代玩玩家)
	var best = _minimax_best_for_player()
	if best >= 0 and _board[best] == 0:
		_place(best, 1)
		_check_end()
		if _game_active:
			_player_turn = false
			get_tree().create_timer(0.35).timeout.connect(_ai_move)

## 为玩家方找最佳棋位 (纯 minimax, 玩家希望最小化 AI 得分)
func _minimax_best_for_player() -> int:
	var best_score = 999
	var best_move = -1
	for i in range(9):
		if _board[i] == 0:
			_board[i] = 1
			var score = _minimax(true, 0)
			_board[i] = 0
			if score < best_score:
				best_score = score
				best_move = i
	return best_move

func _process(delta: float) -> void:
	_time += delta
	# 落子弹射动画
	var needs_redraw := false
	for i in range(9):
		if _cell_anims[i] < 1.0:
			_cell_anims[i] = minf(_cell_anims[i] + delta * 8.0, 1.0)
			needs_redraw = true
	if _win_line.size() > 0 or _game_active or needs_redraw:
		queue_redraw()

func start_game() -> void:
	_board = [0,0,0, 0,0,0, 0,0,0]
	_cell_anims = [0.0,0.0,0.0, 0.0,0.0,0.0, 0.0,0.0,0.0]
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
	_cell_anims[idx] = 0.0  # 触发弹射动画
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
	var d = GameTerminalStyles.create_result_overlay("再来一局", start_game)
	_result_overlay = d.overlay
	_result_label = d.label
	_restart_btn = d.btn
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
	GameTerminalStyles.show_result_overlay(_result_overlay, _result_label, lines[randi() % lines.size()], color)

# ══════════════════════════════════════════════
#  渲染
# ══════════════════════════════════════════════

func _draw() -> void:
	_calc_layout()
	var hue = EventBus.ui_hue
	var cw = _cell_size
	var ch = _cell_size
	var is_ended = _win_line.size() > 0 or (_board.find(0) == -1 and _win_line.size() == 0)

	# ── 网格线: 极细低存在感基准轴 ──
	var line_color = Color.from_hsv(hue, 0.2, 0.4, 0.15)
	var cross_color = Color.from_hsv(hue, 0.3, 0.7, 0.4)
	for i in range(1, 3):
		var x = _grid_origin.x + i * cw
		var y = _grid_origin.y + i * ch
		draw_line(Vector2(x, _grid_origin.y + ch * 0.1), Vector2(x, _grid_origin.y + _grid_size - ch * 0.1), line_color, 1.0, true)
		draw_line(Vector2(_grid_origin.x + cw * 0.1, y), Vector2(_grid_origin.x + _grid_size - cw * 0.1, y), line_color, 1.0, true)

	# ── 四个十字瞄准节点 ──
	for gx in range(1, 3):
		for gy in range(1, 3):
			var px = _grid_origin.x + cw * gx
			var py = _grid_origin.y + ch * gy
			draw_line(Vector2(px - 3, py), Vector2(px + 3, py), cross_color, 1.0, true)
			draw_line(Vector2(px, py - 3), Vector2(px, py + 3), cross_color, 1.0, true)

	# ── 格位坐标标注 ──
	var coord_c = Color.from_hsv(hue, 0.2, 0.4, 0.15)
	var coord_labels = ["A1","A2","A3","B1","B2","B3","C1","C2","C3"]
	for i in range(9):
		var cr = _cell_rect(i)
		var font = ThemeDB.fallback_font
		draw_string(font, cr.position + Vector2(4, 13), coord_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, coord_c)

	# ── 悬停: 四角锁定框 [ ] ──
	if _hover_cell >= 0 and _board[_hover_cell] == 0 and not is_ended:
		var hcx = _cell_center(_hover_cell).x
		var hcy = _cell_center(_hover_cell).y
		var hr = minf(cw, ch) * 0.35
		var brk = 6.0
		var c = Color.from_hsv(hue, 0.4, 0.9, 0.3)
		# 左上
		draw_line(Vector2(hcx - hr, hcy - hr), Vector2(hcx - hr + brk, hcy - hr), c, 1.2, true)
		draw_line(Vector2(hcx - hr, hcy - hr), Vector2(hcx - hr, hcy - hr + brk), c, 1.2, true)
		# 右上
		draw_line(Vector2(hcx + hr, hcy - hr), Vector2(hcx + hr - brk, hcy - hr), c, 1.2, true)
		draw_line(Vector2(hcx + hr, hcy - hr), Vector2(hcx + hr, hcy - hr + brk), c, 1.2, true)
		# 左下
		draw_line(Vector2(hcx - hr, hcy + hr), Vector2(hcx - hr + brk, hcy + hr), c, 1.2, true)
		draw_line(Vector2(hcx - hr, hcy + hr), Vector2(hcx - hr, hcy + hr - brk), c, 1.2, true)
		# 右下
		draw_line(Vector2(hcx + hr, hcy + hr), Vector2(hcx + hr - brk, hcy + hr), c, 1.2, true)
		draw_line(Vector2(hcx + hr, hcy + hr), Vector2(hcx + hr, hcy + hr - brk), c, 1.2, true)

	# ── 棋子 (精密仪器风格) ──
	for i in range(9):
		if _board[i] == 0:
			continue
		var center = _cell_center(i)
		var anim_t = _cell_anims[i]
		var scale_t = _ease_out_expo(anim_t)
		if scale_t < 0.01:
			continue

		var is_winning_cell = _win_line.has(i)
		var dim_alpha = 1.0
		# 结束后非连线格子变暗
		if _win_line.size() > 0 and not is_winning_cell:
			dim_alpha = 0.2
		# 平局全部变暗
		if _board.find(0) == -1 and _win_line.size() == 0:
			dim_alpha = 0.4

		if _board[i] == 1:
			_draw_precision_x(center, cw, hue, scale_t, dim_alpha)
		else:
			_draw_precision_o(center, cw, hue, scale_t, dim_alpha)

	# ── 极简终局判定线 ──
	if _win_line.size() == 3:
		var p1 = _cell_center(_win_line[0])
		var p2 = _cell_center(_win_line[2])
		var line_c = Color.from_hsv(hue, 0.2, 1.0, 0.9)
		# 锐利实线
		draw_line(p1, p2, line_c, 2.0, true)
		# 起止端微小终端框
		draw_rect(Rect2(p1 - Vector2(3, 3), Vector2(6, 6)), line_c, false, 1.0)
		draw_rect(Rect2(p2 - Vector2(3, 3), Vector2(6, 6)), line_c, false, 1.0)

	# ── 外框包边 ──
	var frame_c = Color.from_hsv(hue, 0.4, 0.6, 0.2)
	draw_rect(Rect2(_grid_origin, Vector2(_grid_size, _grid_size)), frame_c, false, 1.0)

# ══════════════════════════════════════════════
#  精密仪器棋子渲染 (移植自旧版)
# ══════════════════════════════════════════════

func _draw_precision_x(center: Vector2, cell_size: float, hue: float, scale_t: float, dim_alpha: float) -> void:
	var c = Color.from_hsv(hue, 0.3, 0.9, dim_alpha)
	var gap = cell_size * 0.05
	var arm = cell_size * 0.25 * scale_t

	# 像两对分离的线段汇聚，中间留空
	draw_line(center + Vector2(-gap, -gap), center + Vector2(-gap - arm, -gap - arm), c, 1.5, true)
	draw_line(center + Vector2(gap, gap), center + Vector2(gap + arm, gap + arm), c, 1.5, true)
	draw_line(center + Vector2(gap, -gap), center + Vector2(gap + arm, -gap - arm), c, 1.5, true)
	draw_line(center + Vector2(-gap, gap), center + Vector2(-gap - arm, gap + arm), c, 1.5, true)

	# 落子瞬间的极亮中心闪光点
	if scale_t < 1.0:
		var flash = Color.from_hsv(hue, 0.1, 1.0, (1.0 - scale_t) * dim_alpha)
		draw_circle(center, 2.0 + scale_t * 2.0, flash)

func _draw_precision_o(center: Vector2, cell_size: float, hue: float, scale_t: float, dim_alpha: float) -> void:
	var ai_hue = fmod(hue + 0.45, 1.0)
	var c = Color.from_hsv(ai_hue, 0.4, 0.95, dim_alpha)
	var r = cell_size * 0.25 * scale_t

	# 极简锐利圆弧 (留一个小缺口)
	var start_angle = -PI / 2 + 0.15
	var end_angle = PI * 1.5 - 0.15
	draw_arc(center, r, start_angle, end_angle, 32, c, 1.5, true)

	# 圆弧缺口两端的闭合横线 (仪表盘风格)
	var p1 = center + Vector2(cos(start_angle), sin(start_angle)) * r
	var p2 = center + Vector2(cos(end_angle), sin(end_angle)) * r
	var t1 = (p1 - center).normalized().rotated(PI / 2) * 2.0
	var t2 = (p2 - center).normalized().rotated(PI / 2) * 2.0
	draw_line(p1 - t1, p1 + t1, c, 1.0, true)
	draw_line(p2 - t2, p2 + t2, c, 1.0, true)

	# 落子瞬间内部瞄准纹理
	if scale_t < 1.0:
		var flash = Color.from_hsv(ai_hue, 0.1, 1.0, (1.0 - scale_t) * dim_alpha)
		draw_arc(center, r * 0.6, 0, TAU, 16, flash, 1.0, true)

func _ease_out_expo(t: float) -> float:
	return 1.0 if t == 1.0 else 1.0 - pow(2.0, -10.0 * t)

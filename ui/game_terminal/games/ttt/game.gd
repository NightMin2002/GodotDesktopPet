# game.gd — 终端井字棋 (策略矩阵)
# 精密仪器风格 (移植自旧版 games/tic_tac_toe)
# 自包含: 棋盘 + 输入 + AI + 话术 + 结算覆盖
extends TerminalGameBase

func get_game_id() -> String: return "ttt"
func get_game_name() -> String: return "策略矩阵"
func get_game_desc() -> String: return "3x3 决策推演"
func supports_auto_play() -> bool: return false


# ══════════════════════════════════════════════
#  话术常量池 (洗牌防重复)
# ══════════════════════════════════════════════

const _POOL_START := [
	"对弈协议启动。",
	"策略矩阵初始化完毕。",
	"推演开始。先手属于操作员。",
	"棋盘已就绪。请落子。",
	"新局。本机已准备完毕。",
	"决策空间已重置。",
]
const _POOL_PLAYER_MOVE := [
	"...已记录。",
	"收到。",
	"标记完成。轮到本机。",
	"嗯。",
	"位置已标记。",
	"...操作员的选择。",
	"记录在案。",
	"收到输入。",
]
const _POOL_AI_MOVE := [
	"最优解已计算。",
	"落子。",
	"...显而易见的选择。",
	"推演完成。",
	"这步不需要思考。",
	"决策树剪枝完毕。",
	"...预期之内。",
]
const _POOL_AI_WIN := [
	"预测到的结局。",
	"推演结果与预期一致。",
	"胜负已定。这不是炫耀。",
	"...本机的运算是精确的。",
	"结果: 符合预期。",
	"分析完毕。胜者: 本机。",
	"...这不算欺负你。算法本来就是这样的。",
]
const _POOL_PLAYER_WIN := [
	"...硬件抖动。不算。",
	"检测到异常分支。请求复盘。",
	"...这次不计入统计。",
	"...散热异常导致决策偏差。",
	"数据波动。建议重赛。",
	"...不承认这个结果。",
	"...显然是操作员作弊。无法证实也无法证伪。",
]
const _POOL_DRAW := [
	"收敛于均衡态。符合预期。",
	"平局。操作员的防御尚可。",
	"...不负不胜。可接受的结果。",
	"纳什均衡。双方均无失误。",
	"平手。本机选择不评价。",
	"...旗鼓相当。仅此一次。",
]

# ══════════════════════════════════════════════
#  状态变量
# ══════════════════════════════════════════════

# ── 棋盘 ──
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
var _cell_anims: Array[float] = [0.0,0.0,0.0, 0.0,0.0,0.0, 0.0,0.0,0.0]

# ── 结算 UI ──
var _restart_btn: Button = null

# ── 话术气泡 ──
var _chat_log: Array = []             # [{text, birth}]
const _CHAT_MAX := 5                  # 最大可见气泡数
const _CHAT_STAY := 5.0               # 持续秒数
const _CHAT_FADE := 1.5               # 淡出秒数
var _chat_area_x: float = 0.0
var _chat_area_w: float = 0.0
var _q_start: Array = []
var _q_player_move: Array = []
var _q_ai_move: Array = []
var _q_ai_win: Array = []
var _q_player_win: Array = []
var _q_draw: Array = []

# ══════════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════════

func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	gui_input.connect(_on_input)
	_build_restart_btn()
	start_game()

func _process(delta: float) -> void:
	_time += delta
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
	_chat_log.clear()
	_time = 0.0
	if is_instance_valid(_restart_btn):
		_restart_btn.visible = false
	_say(_pick(_q_start, _POOL_START))
	game_started.emit()
	queue_redraw()

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
	var best = _minimax_best_for_player()
	if best >= 0 and _board[best] == 0:
		_place(best, 1)
		_check_end()
		if _game_active:
			_player_turn = false
			get_tree().create_timer(0.35).timeout.connect(_ai_move)

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

# ══════════════════════════════════════════════
#  话术系统
# ══════════════════════════════════════════════

func _say(text: String) -> void:
	_chat_log.push_front({ "text": text, "birth": _time })
	if _chat_log.size() > _CHAT_MAX:
		_chat_log.resize(_CHAT_MAX)

## 从洗牌队列取一条 (空了就重填+洗牌)
func _pick(queue: Array, pool: Array) -> String:
	if queue.is_empty():
		queue.append_array(pool)
		queue.shuffle()
	return queue.pop_back()

# ══════════════════════════════════════════════
#  布局计算
# ══════════════════════════════════════════════

func _calc_layout() -> void:
	var w = size.x
	var h = size.y
	var chat_ratio = 0.28
	var grid_area_w = w * (1.0 - chat_ratio)
	var available = minf(grid_area_w * 0.88, (h - 40) * 0.78)
	_grid_size = available
	_cell_size = _grid_size / 3.0
	_grid_origin = Vector2(
		(grid_area_w - _grid_size) * 0.5,
		(h - _grid_size) * 0.5
	)
	_chat_area_x = grid_area_w + 2
	_chat_area_w = w - _chat_area_x - 4

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
			_say(_pick(_q_player_move, _POOL_PLAYER_MOVE))
			_check_end()
			if _game_active:
				_player_turn = false
				get_tree().create_timer(0.35).timeout.connect(_ai_move)

func _place(idx: int, player: int) -> void:
	_board[idx] = player
	_cell_anims[idx] = 0.0
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
		if not _check_end():
			_say(_pick(_q_ai_move, _POOL_AI_MOVE))
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

## 检查并处理终局，返回 true 表示游戏结束
func _check_end() -> bool:
	var winner = _check_winner()
	if winner > 0:
		_game_active = false
		_find_win_line(winner)
		_result = 0 if winner == 1 else 1
		_show_result()
		game_over.emit(_result)
		return true
	elif _is_full():
		_game_active = false
		_result = 2
		_show_result()
		game_over.emit(_result)
		return true
	return false

func _find_win_line(winner: int) -> void:
	for line in _LINES:
		if _board[line[0]] == winner and _board[line[1]] == winner and _board[line[2]] == winner:
			_win_line = [line[0], line[1], line[2]]
			return

# ══════════════════════════════════════════════
#  结算覆盖层
# ══════════════════════════════════════════════

func _build_restart_btn() -> void:
	_restart_btn = Button.new()
	_restart_btn.text = "重新推演"
	_restart_btn.focus_mode = Control.FOCUS_NONE
	_restart_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_restart_btn.add_theme_font_size_override("font_size", 12)
	var hue = EventBus.ui_hue
	_restart_btn.add_theme_color_override("font_color", Color.from_hsv(hue, 0.3, 0.8, 0.7))
	_restart_btn.add_theme_color_override("font_hover_color", Color.from_hsv(hue, 0.4, 1.0, 0.95))
	var sn = StyleBoxFlat.new()
	sn.bg_color = Color(0.06, 0.08, 0.14, 0.7)
	sn.set_border_width_all(1)
	sn.border_color = Color.from_hsv(hue, 0.3, 0.5, 0.25)
	sn.set_corner_radius_all(0)
	sn.content_margin_left = 8; sn.content_margin_right = 8
	sn.content_margin_top = 4; sn.content_margin_bottom = 4
	_restart_btn.add_theme_stylebox_override("normal", sn)
	var sh = sn.duplicate()
	sh.bg_color = Color(0.10, 0.14, 0.22, 0.8)
	sh.border_color = Color.from_hsv(hue, 0.4, 0.8, 0.4)
	_restart_btn.add_theme_stylebox_override("hover", sh)
	_restart_btn.add_theme_stylebox_override("pressed", sh)
	_restart_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_restart_btn.pressed.connect(start_game)
	_restart_btn.visible = false
	add_child(_restart_btn)

func _show_result() -> void:
	var speech: String
	match _result:
		0: speech = _pick(_q_player_win, _POOL_PLAYER_WIN)
		1: speech = _pick(_q_ai_win, _POOL_AI_WIN)
		2: speech = _pick(_q_draw, _POOL_DRAW)
	_say(speech)
	if is_instance_valid(_restart_btn):
		_restart_btn.visible = true

# ══════════════════════════════════════════════
#  渲染: 棋盘 + 网格 + 悬停 + 棋子 + 终局线
# ══════════════════════════════════════════════

func _draw() -> void:
	_calc_layout()
	var hue = EventBus.ui_hue
	var cw = _cell_size
	var ch = _cell_size
	var is_ended = _win_line.size() > 0 or (_board.find(0) == -1 and _win_line.size() == 0)

	# ── 顶部 HUD ──
	var font = ThemeDB.fallback_font
	if font:
		var lbl_c = Color.from_hsv(hue, 0.3, 0.7, 0.5)
		var turn_text: String
		var turn_color: Color
		if not _game_active:
			turn_text = "END"
			turn_color = GameTerminalStyles.dim()
		elif _player_turn:
			turn_text = "USR"
			turn_color = GameTerminalStyles.status_active()
		else:
			turn_text = "SYS"
			turn_color = GameTerminalStyles.status_warning()
		var placed := 0
		for cell in _board:
			if cell != 0:
				placed += 1
		# 左: 回合
		draw_string(font, Vector2(_grid_origin.x, _grid_origin.y - 10.0), "TURN",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lbl_c)
		draw_string(font, Vector2(_grid_origin.x + 40, _grid_origin.y - 10.0), turn_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, turn_color)
		# 右: 落子
		draw_string(font, Vector2(_grid_origin.x + _grid_size - 68, _grid_origin.y - 10.0), "MOVE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lbl_c)
		draw_string(font, Vector2(_grid_origin.x + _grid_size - 24, _grid_origin.y - 10.0), "%d/9" % placed,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameTerminalStyles.dim())

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
		draw_string(font, cr.position + Vector2(4, 13), coord_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, coord_c)

	# ── 悬停: 四角锁定框 [ ] ──
	if _hover_cell >= 0 and _board[_hover_cell] == 0 and not is_ended:
		var hcx = _cell_center(_hover_cell).x
		var hcy = _cell_center(_hover_cell).y
		var hr = minf(cw, ch) * 0.35
		var brk = 6.0
		var c = Color.from_hsv(hue, 0.4, 0.9, 0.3)
		draw_line(Vector2(hcx - hr, hcy - hr), Vector2(hcx - hr + brk, hcy - hr), c, 1.2, true)
		draw_line(Vector2(hcx - hr, hcy - hr), Vector2(hcx - hr, hcy - hr + brk), c, 1.2, true)
		draw_line(Vector2(hcx + hr, hcy - hr), Vector2(hcx + hr - brk, hcy - hr), c, 1.2, true)
		draw_line(Vector2(hcx + hr, hcy - hr), Vector2(hcx + hr, hcy - hr + brk), c, 1.2, true)
		draw_line(Vector2(hcx - hr, hcy + hr), Vector2(hcx - hr + brk, hcy + hr), c, 1.2, true)
		draw_line(Vector2(hcx - hr, hcy + hr), Vector2(hcx - hr, hcy + hr - brk), c, 1.2, true)
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
		if _win_line.size() > 0 and not is_winning_cell:
			dim_alpha = 0.2
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
		draw_line(p1, p2, line_c, 2.0, true)
		draw_rect(Rect2(p1 - Vector2(3, 3), Vector2(6, 6)), line_c, false, 1.0)
		draw_rect(Rect2(p2 - Vector2(3, 3), Vector2(6, 6)), line_c, false, 1.0)

	# ── 外框包边 ──
	var frame_c = Color.from_hsv(hue, 0.4, 0.6, 0.2)
	draw_rect(Rect2(_grid_origin, Vector2(_grid_size, _grid_size)), frame_c, false, 1.0)

	# ── 右侧聊天气泡 ──
	if font and _chat_log.size() > 0:
		var bubble_y = _grid_origin.y + _grid_size  # 从底部开始向上堆叠
		var fs = 12
		for i in range(_chat_log.size()):
			var msg = _chat_log[i]
			var age = _time - msg.birth
			# 生命周期 alpha
			var a: float
			if age < 0.25:
				a = age / 0.25
			elif age < _CHAT_STAY:
				a = 1.0
			elif age < _CHAT_STAY + _CHAT_FADE:
				a = 1.0 - (age - _CHAT_STAY) / _CHAT_FADE
			else:
				continue
			# 测量文字尺寸
			var text_size = font.get_multiline_string_size(msg.text, HORIZONTAL_ALIGNMENT_LEFT, _chat_area_w - 12, fs)
			var bubble_h = text_size.y + 10
			bubble_y -= bubble_h + 4
			# 气泡背景
			var bg = Rect2(_chat_area_x, bubble_y, _chat_area_w, bubble_h)
			draw_rect(bg, Color(0.05, 0.07, 0.12, 0.65 * a))
			draw_rect(bg, Color.from_hsv(hue, 0.25, 0.5, 0.15 * a), false, 1.0)
			# 文字
			var text_c = Color.from_hsv(hue, 0.12, 0.75, 0.85 * a)
			draw_multiline_string(font, Vector2(_chat_area_x + 6, bubble_y + fs + 2), msg.text,
				HORIZONTAL_ALIGNMENT_LEFT, _chat_area_w - 12, fs, -1, text_c)

	# ── 重开按钮定位 (聊天区底部) ──
	if is_instance_valid(_restart_btn) and _restart_btn.visible:
		_restart_btn.position = Vector2(_chat_area_x, _grid_origin.y + _grid_size + 6)
		_restart_btn.size = Vector2(_chat_area_w, 26)

# ══════════════════════════════════════════════
#  渲染: 精密仪器棋子 (移植自旧版)
# ══════════════════════════════════════════════

func _draw_precision_x(center: Vector2, cell_size: float, hue: float, scale_t: float, dim_alpha: float) -> void:
	var c = Color.from_hsv(hue, 0.3, 0.9, dim_alpha)
	var gap = cell_size * 0.05
	var arm = cell_size * 0.25 * scale_t
	# 两对分离线段，中间留空
	draw_line(center + Vector2(-gap, -gap), center + Vector2(-gap - arm, -gap - arm), c, 1.5, true)
	draw_line(center + Vector2(gap, gap), center + Vector2(gap + arm, gap + arm), c, 1.5, true)
	draw_line(center + Vector2(gap, -gap), center + Vector2(gap + arm, -gap - arm), c, 1.5, true)
	draw_line(center + Vector2(-gap, gap), center + Vector2(-gap - arm, gap + arm), c, 1.5, true)
	# 落子闪光
	if scale_t < 1.0:
		var flash = Color.from_hsv(hue, 0.1, 1.0, (1.0 - scale_t) * dim_alpha)
		draw_circle(center, 2.0 + scale_t * 2.0, flash)

func _draw_precision_o(center: Vector2, cell_size: float, hue: float, scale_t: float, dim_alpha: float) -> void:
	var ai_hue = fmod(hue + 0.45, 1.0)
	var c = Color.from_hsv(ai_hue, 0.4, 0.95, dim_alpha)
	var r = cell_size * 0.25 * scale_t
	# 留缺口圆弧
	var start_angle = -PI / 2 + 0.15
	var end_angle = PI * 1.5 - 0.15
	draw_arc(center, r, start_angle, end_angle, 32, c, 1.5, true)
	# 缺口两端闭合横线
	var p1 = center + Vector2(cos(start_angle), sin(start_angle)) * r
	var p2 = center + Vector2(cos(end_angle), sin(end_angle)) * r
	var t1 = (p1 - center).normalized().rotated(PI / 2) * 2.0
	var t2 = (p2 - center).normalized().rotated(PI / 2) * 2.0
	draw_line(p1 - t1, p1 + t1, c, 1.0, true)
	draw_line(p2 - t2, p2 + t2, c, 1.0, true)
	# 落子瞄准纹理
	if scale_t < 1.0:
		var flash = Color.from_hsv(ai_hue, 0.1, 1.0, (1.0 - scale_t) * dim_alpha)
		draw_arc(center, r * 0.6, 0, TAU, 16, flash, 1.0, true)

func _ease_out_expo(t: float) -> float:
	return 1.0 if t == 1.0 else 1.0 - pow(2.0, -10.0 * t)

# game.gd — 策略矩阵 (井字棋)
# 3x3 决策推演小游戏，不可击败的 minimax AI
# 全部 UI 通过代码构建，风格与宠物面板系统一致
extends BaseGame

# ── 游戏状态 ──
var _board: Array[int] = [0,0,0, 0,0,0, 0,0,0]  # 0=空, 1=玩家(X), 2=AI(O)
var _game_over: bool = false
var _player_turn: bool = true

# ── UI 引用 ──
var _host: CanvasLayer = null
var _pet: Node2D = null
var _panel: PanelContainer = null
var _grid: Control = null
var _status_label: Label = null
var _score_label: Label = null
var _title_bar: HBoxContainer = null
var _restart_btn: Button = null

# ── 拖拽 ──
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

# ── 战绩 ──
var _wins: int = 0
var _losses: int = 0
var _draws: int = 0

# ── 话术池 (洗牌防重复) ──
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
	"结果：符合预期。",
	"分析完毕。胜者：本机。",
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

# 洗牌队列 (用完重填)
var _q_start: Array = []
var _q_player_move: Array = []
var _q_ai_move: Array = []
var _q_ai_win: Array = []
var _q_player_win: Array = []
var _q_draw: Array = []

func _pick(queue: Array, pool: Array) -> String:
	if queue.is_empty():
		queue.append_array(pool)
		queue.shuffle()
	return queue.pop_back()

# ── BaseGame 接口 ──

func get_game_id() -> String: return "tic_tac_toe"
func get_game_name() -> String: return "策略矩阵"
func get_game_desc() -> String: return "3x3 决策推演"

func start(host: CanvasLayer, pet: Node2D) -> void:
	_host = host
	_pet = pet
	_build_ui()
	_reset_board()
	_say(_pick(_q_start, _POOL_START))

func cleanup() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

# ══════════════════════════════════════════════
# UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(280, 0)

	# 面板背景
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.12, 0.95)
	bg.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.4)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 0
	bg.content_margin_right = 0
	bg.content_margin_top = 0
	bg.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", bg)

	var outer = MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 14)
	outer.add_theme_constant_override("margin_right", 14)
	outer.add_theme_constant_override("margin_top", 0)
	outer.add_theme_constant_override("margin_bottom", 4)
	_panel.add_child(outer)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	outer.add_child(vbox)

	# ── 标题栏 ──
	_title_bar = HBoxContainer.new()
	_title_bar.custom_minimum_size = Vector2(0, 34)
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP

	var title = Label.new()
	title.text = "  策略矩阵"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 1.0, 0.9))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(title)

	var close_btn = Button.new()
	close_btn.text = "x"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.6))
	close_btn.add_theme_color_override("font_hover_color", Color(1, 0.3, 0.3, 0.9))
	close_btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	close_btn.pressed.connect(func(): game_finished.emit(Result.DRAW); _on_close())
	_title_bar.add_child(close_btn)

	vbox.add_child(_title_bar)
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.15)
	sep_style.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", sep_style)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# ── 状态栏 ──
	_status_label = Label.new()
	_status_label.text = "操作员先手"
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.5, 0.65, 0.8, 0.8))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	# ── 棋盘 ──
	_grid = _BoardRenderer.new()
	_grid.custom_minimum_size = Vector2(252, 252)
	(_grid as _BoardRenderer).cell_clicked.connect(_on_cell_clicked)
	vbox.add_child(_grid)

	# ── 战绩 ──
	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 12)
	_score_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.6))
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_score_label()
	vbox.add_child(_score_label)

	# ── 再来一局 ──
	_restart_btn = Button.new()
	_restart_btn.text = "再来一局"
	_restart_btn.flat = true
	_restart_btn.add_theme_font_size_override("font_size", 14)
	_restart_btn.add_theme_color_override("font_color", Color(0.5, 0.65, 0.8, 0.7))
	_restart_btn.add_theme_color_override("font_hover_color", Color.from_hsv(EventBus.ui_hue, 0.5, 1.0))
	_restart_btn.pressed.connect(_on_restart)
	_restart_btn.hide()
	vbox.add_child(_restart_btn)

	# ── 输入处理 (拖拽 + 点击外部关闭) ──
	_panel.gui_input.connect(_on_panel_input)

	# 定位到宠物附近
	_host.add_child(_panel)
	_position_near_pet()

	# 弹入动画
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.6, 0.6)
	await _host.get_tree().process_frame
	_panel.pivot_offset = _panel.size / 2.0
	var tween = _host.create_tween().set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

func _position_near_pet() -> void:
	var vp = _host.get_viewport().get_visible_rect().size
	var pet_pos := Vector2(vp.x / 2.0, vp.y / 2.0)
	if is_instance_valid(_pet):
		pet_pos = _pet.get_global_transform_with_canvas().get_origin()
	var pw := _panel.custom_minimum_size.x
	var ph := 400.0
	var gap := 60.0
	var x: float
	if pet_pos.x > vp.x * 0.5:
		x = pet_pos.x - pw - gap
	else:
		x = pet_pos.x + gap
	var y = pet_pos.y - ph * 0.4
	x = clampf(x, 8.0, vp.x - pw - 8.0)
	y = clampf(y, 8.0, vp.y - ph - 8.0)
	_panel.position = Vector2(x, y)

# ══════════════════════════════════════════════
# 游戏逻辑
# ══════════════════════════════════════════════

func _reset_board() -> void:
	_board = [0,0,0, 0,0,0, 0,0,0]
	_game_over = false
	_player_turn = true
	_restart_btn.hide()
	_status_label.text = "操作员先手"
	(_grid as _BoardRenderer).set_win_line([])
	(_grid as _BoardRenderer).set_board(_board, -1)

func _on_cell_clicked(index: int) -> void:
	if _game_over or not _player_turn:
		return
	if _board[index] != 0:
		return
	# 玩家落子
	_board[index] = 1
	_player_turn = false
	(_grid as _BoardRenderer).set_board(_board, index)
	_say(_pick(_q_player_move, _POOL_PLAYER_MOVE))

	var win_line = _check_winner(1)
	if win_line.size() > 0:
		_end_game(Result.WIN, win_line)
		return
	if _is_full():
		_end_game(Result.DRAW, [])
		return

	# AI 落子 (延迟模拟思考)
	_status_label.text = "本机推演中..."
	await _host.get_tree().create_timer(0.4 + randf() * 0.3).timeout
	if _game_over:
		return
	var ai_move = _minimax_best_move()
	_board[ai_move] = 2
	(_grid as _BoardRenderer).set_board(_board, ai_move)
	_say(_pick(_q_ai_move, _POOL_AI_MOVE))

	var ai_win_line = _check_winner(2)
	if ai_win_line.size() > 0:
		_end_game(Result.LOSE, ai_win_line)
		return
	if _is_full():
		_end_game(Result.DRAW, [])
		return

	_player_turn = true
	_status_label.text = "操作员回合"

func _end_game(result: Result, win_line: Array) -> void:
	_game_over = true
	(_grid as _BoardRenderer).set_win_line(win_line)
	match result:
		Result.WIN:
			_wins += 1
			_status_label.text = "...异常分支"
			_say(_pick(_q_player_win, _POOL_PLAYER_WIN))
		Result.LOSE:
			_losses += 1
			_status_label.text = "预测到的结局"
			_say(_pick(_q_ai_win, _POOL_AI_WIN))
		Result.DRAW:
			_draws += 1
			_status_label.text = "均衡态"
			_say(_pick(_q_draw, _POOL_DRAW))
	_update_score_label()
	_restart_btn.show()
	game_finished.emit(result)

func _on_restart() -> void:
	_reset_board()
	_say(_pick(_q_start, _POOL_START))

func _on_close() -> void:
	if is_instance_valid(_panel):
		_panel.pivot_offset = _panel.size / 2.0
		var tween = _host.create_tween().set_parallel(true)
		tween.tween_property(_panel, "modulate:a", 0.0, 0.15)
		tween.tween_property(_panel, "scale", Vector2(0.5, 0.5), 0.15)
		tween.finished.connect(func():
			if is_instance_valid(_panel):
				_panel.queue_free()
			# 通知 GameManager 清理
			var main_node = _host.get_tree().root.get_node_or_null("Main")
			if main_node and "game_mgr" in main_node and main_node.game_mgr:
				main_node.game_mgr.close_game()
		)

func _update_score_label() -> void:
	if _score_label:
		_score_label.text = "胜 " + str(_wins) + "  负 " + str(_losses) + "  平 " + str(_draws)

# ── 宠物说话 ──
func _say(text: String) -> void:
	EventBus.force_show_bubble.emit(text)

# ══════════════════════════════════════════════
# Minimax AI
# ══════════════════════════════════════════════

func _minimax_best_move() -> int:
	# 首手优化: 只有 1 颗棋子时，最优应答是确定的，跳过搜索
	var occupied := 0
	for cell in _board:
		if cell != 0:
			occupied += 1
	if occupied == 1:
		# 对手下了中心 → 下角; 下了其他 → 下中心
		if _board[4] != 0:
			return [0, 2, 6, 8].pick_random()
		return 4

	# Alpha-Beta 剪枝 minimax
	var best_score := -999
	var best_move := -1
	for i in range(9):
		if _board[i] == 0:
			_board[i] = 2
			var score = _minimax(false, 0, -999, 999)
			_board[i] = 0
			if score > best_score:
				best_score = score
				best_move = i
	return best_move

func _minimax(is_ai: bool, depth: int, alpha: int, beta: int) -> int:
	var ai_line = _check_winner(2)
	if ai_line.size() > 0:
		return 10 - depth
	var player_line = _check_winner(1)
	if player_line.size() > 0:
		return depth - 10
	if _is_full():
		return 0

	if is_ai:
		var best := -999
		for i in range(9):
			if _board[i] == 0:
				_board[i] = 2
				best = maxi(best, _minimax(false, depth + 1, alpha, beta))
				_board[i] = 0
				alpha = maxi(alpha, best)
				if beta <= alpha:
					break
		return best
	else:
		var best := 999
		for i in range(9):
			if _board[i] == 0:
				_board[i] = 1
				best = mini(best, _minimax(true, depth + 1, alpha, beta))
				_board[i] = 0
				beta = mini(beta, best)
				if beta <= alpha:
					break
		return best

# ══════════════════════════════════════════════
# 判定
# ══════════════════════════════════════════════

const WIN_PATTERNS := [
	[0,1,2], [3,4,5], [6,7,8],  # 行
	[0,3,6], [1,4,7], [2,5,8],  # 列
	[0,4,8], [2,4,6],            # 对角线
]

func _check_winner(player: int) -> Array:
	for pattern in WIN_PATTERNS:
		if _board[pattern[0]] == player and _board[pattern[1]] == player and _board[pattern[2]] == player:
			return pattern
	return []

func _is_full() -> bool:
	for cell in _board:
		if cell == 0:
			return false
	return true

# ══════════════════════════════════════════════
# 面板拖拽
# ══════════════════════════════════════════════

func _on_panel_input(event: InputEvent) -> void:
	if not is_instance_valid(_panel):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# 只在标题栏区域启动拖拽
		var local = _panel.get_local_mouse_position()
		if event.pressed and local.y < 40.0:
			_dragging = true
			_drag_offset = _host.get_viewport().get_mouse_position() - _panel.position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var vp = _host.get_viewport().get_visible_rect().size
		var new_pos = _host.get_viewport().get_mouse_position() - _drag_offset
		new_pos.x = clampf(new_pos.x, 8.0, vp.x - _panel.size.x - 8.0)
		new_pos.y = clampf(new_pos.y, 8.0, vp.y - _panel.size.y - 8.0)
		_panel.position = new_pos

# ══════════════════════════════════════════════
# 内嵌类: 棋盘渲染器
# ══════════════════════════════════════════════

class _BoardRenderer extends Control:
	signal cell_clicked(index: int)

	var _board: Array[int] = [0,0,0, 0,0,0, 0,0,0]
	var _last_move: int = -1
	var _win_line: Array = []
	var _hover_cell: int = -1
	var _anim_time: float = 0.0
	var _cell_anims: Array[float] = [0,0,0, 0,0,0, 0,0,0]  # 每个格子的动画进度

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_board(board: Array[int], last_move: int) -> void:
		_board = board.duplicate()
		_last_move = last_move
		if last_move >= 0 and last_move < 9:
			_cell_anims[last_move] = 0.0
		queue_redraw()

	func set_win_line(line: Array) -> void:
		_win_line = line
		queue_redraw()

	func _process(delta: float) -> void:
		_anim_time += delta
		var needs_redraw := false
		for i in range(9):
			if _cell_anims[i] < 1.0:
				_cell_anims[i] = minf(_cell_anims[i] + delta * 4.0, 1.0)
				needs_redraw = true
		if _win_line.size() > 0:
			needs_redraw = true
		if needs_redraw:
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var cell = _pos_to_cell(event.position)
			if cell >= 0:
				cell_clicked.emit(cell)
		elif event is InputEventMouseMotion:
			var new_hover = _pos_to_cell(event.position)
			if new_hover != _hover_cell:
				_hover_cell = new_hover
				queue_redraw()

	func _mouse_exited() -> void:
		_hover_cell = -1
		queue_redraw()

	func _pos_to_cell(pos: Vector2) -> int:
		var cell_w = size.x / 3.0
		var cell_h = size.y / 3.0
		var col = int(pos.x / cell_w)
		var row = int(pos.y / cell_h)
		if col < 0 or col > 2 or row < 0 or row > 2:
			return -1
		return row * 3 + col

	func _draw() -> void:
		var w = size.x
		var h = size.y
		var cw = w / 3.0
		var ch = h / 3.0
		var hue = EventBus.ui_hue

		# 背景
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.1, 0.4), true)

		# 网格线
		var line_color = Color.from_hsv(hue, 0.3, 0.6, 0.3)
		for i in range(1, 3):
			draw_line(Vector2(cw * i, 4), Vector2(cw * i, h - 4), line_color, 1.5, true)
			draw_line(Vector2(4, ch * i), Vector2(w - 4, ch * i), line_color, 1.5, true)

		# hover 高亮
		if _hover_cell >= 0 and _board[_hover_cell] == 0:
			var hx = float(_hover_cell % 3) * cw
			var hy = float(_hover_cell / 3) * ch
			draw_rect(Rect2(Vector2(hx + 2, hy + 2), Vector2(cw - 4, ch - 4)),
				Color.from_hsv(hue, 0.2, 0.3, 0.15), true)

		# 棋子
		for i in range(9):
			if _board[i] == 0:
				continue
			var cx = (float(i % 3) + 0.5) * cw
			var cy = (float(i / 3) + 0.5) * ch
			var anim_t = _cell_anims[i]
			var scale_t = _ease_out_back(anim_t)
			var r = minf(cw, ch) * 0.28 * scale_t
			if r < 1.0:
				continue
			if _board[i] == 1:
				_draw_x(Vector2(cx, cy), r, hue, i == _last_move)
			else:
				_draw_o(Vector2(cx, cy), r, hue, i == _last_move)

		# 胜利线
		if _win_line.size() == 3:
			var start_idx = _win_line[0]
			var end_idx = _win_line[2]
			var sx = (float(start_idx % 3) + 0.5) * cw
			var sy = (float(start_idx / 3) + 0.5) * ch
			var ex = (float(end_idx % 3) + 0.5) * cw
			var ey = (float(end_idx / 3) + 0.5) * ch
			var pulse = 0.7 + sin(_anim_time * TAU * 1.5) * 0.3
			var win_color = Color.from_hsv(hue, 0.6, 1.0, pulse)
			draw_line(Vector2(sx, sy), Vector2(ex, ey), win_color, 3.0, true)
			# 光晕
			var glow_color = Color.from_hsv(hue, 0.4, 1.0, pulse * 0.2)
			draw_line(Vector2(sx, sy), Vector2(ex, ey), glow_color, 8.0, true)

	func _draw_x(center: Vector2, r: float, hue: float, is_last: bool) -> void:
		var color = Color.from_hsv(hue, 0.5, 1.0, 0.9) if not is_last \
			else Color.from_hsv(hue, 0.6, 1.0, 1.0)
		var offset = r * 0.7
		draw_line(center + Vector2(-offset, -offset), center + Vector2(offset, offset), color, 2.5, true)
		draw_line(center + Vector2(offset, -offset), center + Vector2(-offset, offset), color, 2.5, true)
		if is_last:
			var glow = Color.from_hsv(hue, 0.3, 1.0, 0.15)
			draw_circle(center, r, glow, true, -1.0, true)

	func _draw_o(center: Vector2, r: float, hue: float, is_last: bool) -> void:
		# AI用互补色
		var ai_hue = fmod(hue + 0.45, 1.0)
		var color = Color.from_hsv(ai_hue, 0.5, 1.0, 0.9) if not is_last \
			else Color.from_hsv(ai_hue, 0.6, 1.0, 1.0)
		draw_arc(center, r * 0.65, 0, TAU, 32, color, 2.5, true)
		if is_last:
			var glow = Color.from_hsv(ai_hue, 0.3, 1.0, 0.15)
			draw_circle(center, r, glow, true, -1.0, true)

	func _ease_out_back(t: float) -> float:
		var c1 := 1.70158
		var c3 := c1 + 1.0
		return 1.0 + c3 * pow(t - 1.0, 3) + c1 * pow(t - 1.0, 2)

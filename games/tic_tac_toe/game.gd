# game.gd — 策略矩阵 (井字棋)
# 3x3 决策推演小游戏，不可击败的 minimax AI
# 全部 UI 通过代码构建，风格与宠物面板系统一致
extends BaseGame

# ── 游戏状态 ──
var _board: Array[int] = [0,0,0, 0,0,0, 0,0,0]  # 0=空, 1=玩家(X), 2=AI(O)
var _game_over: bool = false
var _player_turn: bool = true
var _last_move: int = -1

# ── UI 引用 ──
var _panel: PanelContainer = null
var _grid: Control = null
var _score_label: RichTextLabel = null

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

func get_tutorial_steps() -> Array[Dictionary]:
	return [
		{"text": "这个游戏在你们人类世界叫\"井字棋\"。"},
		{"text": "规则很简单。你点一个，本机点一个。"},
		{"text": "三个标记连成一线。仅此而已。"},
		{"text": "在博弈论中这叫\"已解游戏\"。最优解下胜率为 0%。"},
		{"text": "...换一种说法，你是无法赢本机的。"},
		{"text": "...不过，本机不介意陪你验证这个结论。"},
	]

func start() -> void:
	_build_ui()
	_reset_board()
	_say(_pick(_q_start, _POOL_START))

func cleanup() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_grid = null
	_score_label = null
	super.cleanup()

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
	bg.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", bg)

	var outer = MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 14)
	outer.add_theme_constant_override("margin_right", 14)
	outer.add_theme_constant_override("margin_top", 0)
	outer.add_theme_constant_override("margin_bottom", 4)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(outer)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(vbox)

	# ── 棋盘 ──
	_grid = _BoardRenderer.new()
	_grid.custom_minimum_size = Vector2(252, 252)
	(_grid as _BoardRenderer).cell_clicked.connect(_on_cell_clicked)
	vbox.add_child(_grid)

	# ── 战绩 (RichTextLabel + BBCode 彩色) ──
	var score_rich = RichTextLabel.new()
	score_rich.bbcode_enabled = true
	score_rich.fit_content = true
	score_rich.scroll_active = false
	score_rich.custom_minimum_size = Vector2(0, 20)
	score_rich.add_theme_font_size_override("normal_font_size", 12)
	score_rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_label = score_rich
	_update_score_label()
	vbox.add_child(score_rich)

	# ── 输入处理 (拖拽 + 点击外部关闭) ──
	_panel.gui_input.connect(_on_panel_input)
	_panel.resized.connect(sync_viewport_size)  # 面板大小变化时同步 SubViewport

	# 挂载到 SubViewport (先挂载→等布局→同步大小→定位)
	game_viewport.add_child(_panel)
	await game_viewport.get_tree().process_frame  # 等 UI 布局完成
	sync_viewport_size()  # 同步 SubViewport 大小到面板实际尺寸

	# 用实际面板尺寸定位，确保不超出屏幕
	_position_near_pet()

	# 弹入动画 (作用于 Container，因为它是屏幕上的实际显示元素)
	game_container.modulate.a = 0.0
	game_container.scale = Vector2(0.6, 0.6)
	game_container.pivot_offset = game_container.size / 2.0
	var tween = game_container.create_tween().set_parallel(true)
	tween.tween_property(game_container, "modulate:a", 1.0, 0.2)
	tween.tween_property(game_container, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

	# 悬浮组件 (标题气泡 + 侧边按钮 + 重开按钮)
	_setup_floating_chrome(get_game_name(), _on_close, _on_restart)

func _position_near_pet() -> void:
	var vp = screen_size
	var pet_pos := Vector2(vp.x / 2.0, vp.y / 2.0)
	if is_instance_valid(_pet):
		pet_pos = _pet.get_global_transform_with_canvas().get_origin()
	var pw := game_container.size.x if game_container.size.x > 10 else 280.0
	var ph := game_container.size.y if game_container.size.y > 10 else 400.0
	# 获取全息屏区域 (避让用)
	var holo_rect := Rect2()
	if is_instance_valid(_pet) and _pet.gaming and _pet.gaming.active:
		holo_rect = _pet.gaming.get_holo_screen_rect()
	# 间距: 面板在宠物对面 (和全息屏同侧), 但要避开全息屏
	var pet_r := 30.0
	var base_gap := pet_r + pet_r * 1.2 + pet_r * 1.5
	var x: float
	if pet_pos.x > vp.x * 0.5:
		x = pet_pos.x - pw - base_gap
		# 检查是否和全息屏重叠 (全息屏也在左侧)
		if holo_rect.size.x > 0:
			var panel_right = x + pw
			if panel_right > holo_rect.position.x:
				x = holo_rect.position.x - pw - 8.0
	else:
		x = pet_pos.x + base_gap
		# 检查是否和全息屏重叠 (全息屏也在右侧)
		if holo_rect.size.x > 0:
			var holo_right = holo_rect.position.x + holo_rect.size.x
			if x < holo_right:
				x = holo_right + 8.0
	var y = pet_pos.y - ph * 0.35
	var bottom_reserve := _RESTART_GAP + _RESTART_RESERVE.y + _RESTART_GAP
	x = clampf(x, 8.0, vp.x - pw - 8.0)
	y = clampf(y, 8.0, vp.y - ph - bottom_reserve)
	game_container.position = Vector2(x, y)

func _clamp_panel_to_screen() -> void:
	if not is_instance_valid(game_container):
		return
	var vp = screen_size
	var pos = game_container.position
	pos.x = clampf(pos.x, 8.0, vp.x - game_container.size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - game_container.size.y - 8.0)
	game_container.position = pos
	_update_chrome_positions()

# ══════════════════════════════════════════════
# 游戏逻辑
# ══════════════════════════════════════════════

func _reset_board() -> void:
	_board = [0,0,0, 0,0,0, 0,0,0]
	_game_over = false
	_player_turn = true
	_hide_restart_bubble()
	_say("操作员先手")
	(_grid as _BoardRenderer).set_win_line([])
	(_grid as _BoardRenderer).set_board(_board, -1)
	_last_move = -1

func _on_cell_clicked(index: int) -> void:
	if _game_over or not _player_turn:
		return
	if _board[index] != 0:
		return
	# 玩家落子
	_board[index] = 1
	_player_turn = false
	_last_move = index
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
	_say("本机推演中...")
	await game_viewport.get_tree().create_timer(0.4 + randf() * 0.3).timeout
	if _game_over:
		return
	var ai_move = _minimax_best_move()
	_board[ai_move] = 2
	_last_move = ai_move
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
	_say("操作员回合")

func _end_game(result: Result, win_line: Array) -> void:
	_game_over = true
	(_grid as _BoardRenderer).set_win_line(win_line)
	match result:
		Result.WIN:
			_wins += 1
			_say(_pick(_q_player_win, _POOL_PLAYER_WIN))
		Result.LOSE:
			_losses += 1
			_say(_pick(_q_ai_win, _POOL_AI_WIN))
		Result.DRAW:
			_draws += 1
			_say(_pick(_q_draw, _POOL_DRAW))
	_update_score_label()
	_show_restart_bubble()
	# 按钮显示后重新确保不超出屏幕
	await game_viewport.get_tree().process_frame
	_clamp_panel_to_screen()
	game_finished.emit(result)

func _on_restart() -> void:
	_reset_board()
	_say(_pick(_q_start, _POOL_START))

func _on_close() -> void:
	# 游戏进行中关闭 → 算认输 (不走 _end_game，面板要关了没必要更新 UI)
	if not _game_over:
		_game_over = true
		_losses += 1
		game_finished.emit(Result.LOSE)
		# 吐槽通过宠物气泡显示 (面板即将关闭，_say 看不到)
		if is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
			_pet.show_local_bubble("对弈中断。...这算你认输。")
	_animate_chrome_out()
	if is_instance_valid(game_container):
		game_container.pivot_offset = game_container.size / 2.0
		var tween = game_container.create_tween().set_parallel(true)
		tween.tween_property(game_container, "modulate:a", 0.0, 0.15)
		tween.tween_property(game_container, "scale", Vector2(0.5, 0.5), 0.15)
		tween.finished.connect(func():
			EventBus.close_game_requested.emit()
		)

func _update_score_label() -> void:
	if not _score_label:
		return
	var hue = EventBus.ui_hue
	# 胜=青绿调, 负=暗红调, 平=灰蓝调
	var win_c = Color.from_hsv(fmod(hue + 0.15, 1.0), 0.45, 0.85).to_html(false)
	var lose_c = Color(0.85, 0.35, 0.35).to_html(false)
	var draw_c = Color(0.45, 0.55, 0.65).to_html(false)
	var dim = Color(0.4, 0.5, 0.6, 0.5).to_html(false)
	_score_label.text = (
		"[center][color=#" + dim + "]胜 [/color][color=#" + win_c + "]" + str(_wins)
		+ "[/color]    [color=#" + dim + "]负 [/color][color=#" + lose_c + "]" + str(_losses)
		+ "[/color]    [color=#" + dim + "]平 [/color][color=#" + draw_c + "]" + str(_draws)
		+ "[/color][/center]"
	)

# ── 宠物发言 (已统一到 BaseGame._say()) ──

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
	if not is_instance_valid(game_container):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# 只在发言区域启动拖拽
		var local = _panel.get_local_mouse_position()
		if event.pressed and local.y < 50.0:  # 上部区域可拖拽
			_dragging = true
			_drag_offset = game_container.get_viewport().get_mouse_position() - game_container.position
			EventBus.drag_started.emit()
		else:
			if _dragging:
				EventBus.drag_ended.emit()
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var vp = screen_size
		var new_pos = game_container.get_viewport().get_mouse_position() - _drag_offset
		new_pos.x = clampf(new_pos.x, 8.0, vp.x - game_container.size.x - 8.0)
		new_pos.y = clampf(new_pos.y, 8.0, vp.y - game_container.size.y - 8.0)
		game_container.position = new_pos
		_update_chrome_positions()

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
	var _has_last_move: bool = false  # 是否有最新落子 (驱动脉冲动画)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		set_process(false)

	func set_board(board: Array[int], last_move: int) -> void:
		_board = board.duplicate()
		_last_move = last_move
		_has_last_move = last_move >= 0 and last_move < 9
		if _has_last_move:
			_cell_anims[last_move] = 0.0
			set_process(true)
		queue_redraw()

	func set_win_line(line: Array) -> void:
		_win_line = line
		if line.size() > 0:
			set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		_anim_time += delta
		var needs_redraw := false
		var all_done := true
		for i in range(9):
			if _cell_anims[i] < 1.0:
				_cell_anims[i] = minf(_cell_anims[i] + delta * 4.0, 1.0)
				needs_redraw = true
				all_done = false
		if _win_line.size() > 0:
			needs_redraw = true
			all_done = false
		# 最新落子脉冲动画 (持续到下一次落子覆盖)
		if _has_last_move:
			needs_redraw = true
			all_done = false
		if needs_redraw:
			queue_redraw()
		elif all_done:
			set_process(false)

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

		# 网格线: 科技风十字交叉 + 交叉点光点
		var line_color = Color.from_hsv(hue, 0.3, 0.6, 0.25)
		var node_color = Color.from_hsv(hue, 0.4, 0.8, 0.35)
		for i in range(1, 3):
			draw_line(Vector2(cw * i, 4), Vector2(cw * i, h - 4), line_color, 1.5, true)
			draw_line(Vector2(4, ch * i), Vector2(w - 4, ch * i), line_color, 1.5, true)
		# 四个交叉点小光点
		for gx in range(1, 3):
			for gy in range(1, 3):
				draw_circle(Vector2(cw * gx, ch * gy), 2.5, node_color, true, -1.0, true)

		# hover 预览: 空格子上显示半透明 X 轮廓
		if _hover_cell >= 0 and _board[_hover_cell] == 0:
			var hx = (float(_hover_cell % 3) + 0.5) * cw
			var hy = (float(_hover_cell / 3) + 0.5) * ch
			var hr = minf(cw, ch) * 0.28
			# 淡色背景
			draw_rect(Rect2(
				Vector2(float(_hover_cell % 3) * cw + 2, float(_hover_cell / 3) * ch + 2),
				Vector2(cw - 4, ch - 4)),
				Color.from_hsv(hue, 0.2, 0.3, 0.12), true)
			# 半透明 X 预览
			var preview_c = Color.from_hsv(hue, 0.3, 0.8, 0.2)
			var off = hr * 0.7
			draw_line(Vector2(hx - off, hy - off), Vector2(hx + off, hy + off), preview_c, 2.0, true)
			draw_line(Vector2(hx + off, hy - off), Vector2(hx - off, hy + off), preview_c, 2.0, true)

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
			# 外层宽光晕
			draw_line(Vector2(sx, sy), Vector2(ex, ey),
				Color.from_hsv(hue, 0.3, 1.0, pulse * 0.15), 10.0, true)
			# 中层光晕
			draw_line(Vector2(sx, sy), Vector2(ex, ey),
				Color.from_hsv(hue, 0.5, 1.0, pulse * 0.3), 5.0, true)
			# 核心亮线
			draw_line(Vector2(sx, sy), Vector2(ex, ey),
				Color.from_hsv(hue, 0.6, 1.0, pulse), 2.5, true)
			# 端点光球
			var ep_glow = Color.from_hsv(hue, 0.5, 1.0, pulse * 0.6)
			draw_circle(Vector2(sx, sy), 4.0, ep_glow, true, -1.0, true)
			draw_circle(Vector2(ex, ey), 4.0, ep_glow, true, -1.0, true)

	func _draw_x(center: Vector2, r: float, hue: float, is_last: bool) -> void:
		var base_alpha := 0.85 if not is_last else 1.0
		var color = Color.from_hsv(hue, 0.55, 1.0, base_alpha)
		var offset = r * 0.7

		if is_last:
			# 菱形高亮背景 (匹配 X 几何)
			var pulse = 0.12 + sin(_anim_time * TAU * 1.2) * 0.05
			var diamond = PackedVector2Array([
				center + Vector2(0, -r),
				center + Vector2(r, 0),
				center + Vector2(0, r),
				center + Vector2(-r, 0),
			])
			var diamond_c = Color.from_hsv(hue, 0.35, 0.9, pulse)
			draw_colored_polygon(diamond, diamond_c)
			# 菱形边框
			var border_c = Color.from_hsv(hue, 0.5, 1.0, pulse * 1.8)
			for di in range(4):
				draw_line(diamond[di], diamond[(di + 1) % 4], border_c, 1.0, true)

		# 外层光晕线 (粗、半透明)
		var glow_c = Color.from_hsv(hue, 0.3, 1.0, base_alpha * 0.2)
		draw_line(center + Vector2(-offset, -offset), center + Vector2(offset, offset), glow_c, 6.0, true)
		draw_line(center + Vector2(offset, -offset), center + Vector2(-offset, offset), glow_c, 6.0, true)

		# 主交叉线
		draw_line(center + Vector2(-offset, -offset), center + Vector2(offset, offset), color, 2.5, true)
		draw_line(center + Vector2(offset, -offset), center + Vector2(-offset, offset), color, 2.5, true)

		# 四个端点小刻度 (科技感细节)
		var tick = r * 0.15
		var ends = [
			Vector2(-offset, -offset), Vector2(offset, offset),
			Vector2(offset, -offset), Vector2(-offset, offset),
		]
		var tick_c = Color.from_hsv(hue, 0.4, 0.9, base_alpha * 0.6)
		for ep in ends:
			var p = center + ep
			draw_line(p + Vector2(-tick, 0), p + Vector2(tick, 0), tick_c, 1.0, true)
			draw_line(p + Vector2(0, -tick), p + Vector2(0, tick), tick_c, 1.0, true)

	func _draw_o(center: Vector2, r: float, hue: float, is_last: bool) -> void:
		var ai_hue = fmod(hue + 0.45, 1.0)
		var base_alpha := 0.85 if not is_last else 1.0
		var color = Color.from_hsv(ai_hue, 0.55, 1.0, base_alpha)
		var ring_r = r * 0.65

		if is_last:
			# 圆形高亮背景
			var pulse = 0.12 + sin(_anim_time * TAU * 1.2) * 0.05
			draw_circle(center, r, Color.from_hsv(ai_hue, 0.35, 0.9, pulse), true, -1.0, true)
			# 外圈描边
			draw_arc(center, r, 0, TAU, 48,
				Color.from_hsv(ai_hue, 0.5, 1.0, pulse * 1.8), 1.0, true)

		# 外层光晕圆环
		draw_arc(center, ring_r, 0, TAU, 32,
			Color.from_hsv(ai_hue, 0.3, 1.0, base_alpha * 0.2), 6.0, true)

		# 主圆环 (留一个小缺口, 科技风)
		var gap_start = fmod(_anim_time * 0.5, TAU) if is_last else 0.0
		var gap_size = 0.3 if is_last else 0.0  # 最新落子有旋转缺口
		if gap_size > 0.0:
			draw_arc(center, ring_r, gap_start + gap_size, gap_start + TAU, 30, color, 2.5, true)
		else:
			draw_arc(center, ring_r, 0, TAU, 32, color, 2.5, true)

		# 内层细圈 (更小、更淡)
		var inner_c = Color.from_hsv(ai_hue, 0.4, 0.8, base_alpha * 0.35)
		draw_arc(center, ring_r * 0.55, 0, TAU, 24, inner_c, 1.0, true)

		# 轨道光点 (最新落子才显示)
		if is_last:
			var dot_angle = fmod(_anim_time * 2.0, TAU)
			var dot_pos = center + Vector2(cos(dot_angle), sin(dot_angle)) * ring_r
			draw_circle(dot_pos, 2.5, Color.from_hsv(ai_hue, 0.5, 1.0, 0.8), true, -1.0, true)
			draw_circle(dot_pos, 5.0, Color.from_hsv(ai_hue, 0.3, 1.0, 0.2), true, -1.0, true)

	func _ease_out_back(t: float) -> float:
		var c1 := 1.70158
		var c3 := c1 + 1.0
		return 1.0 + c3 * pow(t - 1.0, 3) + c1 * pow(t - 1.0, 2)

# game.gd — 策略矩阵 (井字棋)
# 3x3 决策推演小游戏，不可击败的 minimax AI
# 全部 UI 通过代码构建，风格与宠物面板系统一致
extends BaseGame

# ── 游戏状态 ──
var _board: Array[int] = [0,0,0, 0,0,0, 0,0,0]  # 0=空, 1=玩家(X), 2=AI(O)

var _player_turn: bool = true
var _last_move: int = -1

# ── UI 引用 ──
var _panel: PanelContainer = null
var _grid: Control = null
var _score_label: RichTextLabel = null
var _eye: Control = null

# ── 战绩 (_wins/_losses 在 BaseGame 中) ──
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

# _pick() 已统一到 BaseGame 基类

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
	_load_scores()
	_draws = SettingsManager.get_int(_score_key("draws"), 0)
	_build_ui()
	_reset_board()
	_say(_pick(_q_start, _POOL_START))

func cleanup() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_grid = null
	_score_label = null
	_eye = null
	super.cleanup()

# ══════════════════════════════════════════════
# UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	var skel = _create_panel_skeleton(280, {"left": 14, "right": 14, "top": 0, "bottom": 4, "separation": 8})
	_panel = skel.panel
	var vbox = skel.vbox

	# ── 全局扫描背景(故障风) ──
	var glitch_bg = _GlitchBg.new()
	glitch_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	glitch_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(glitch_bg)
	# 将 vbox 父节点移到最前 (glitch_bg 在后面)
	_panel.move_child(_panel.get_child(0), _panel.get_child_count() - 1)

	# ── 顶部视觉中枢 (机械单眼) ──
	_eye = _EyeRenderer.new()
	_eye.custom_minimum_size = Vector2(0, 36)
	vbox.add_child(_eye)

	# ── 棋盘 ──
	_grid = _BoardRenderer.new()
	_grid.custom_minimum_size = Vector2(252, 252)
	(_grid as _BoardRenderer).cell_clicked.connect(_on_cell_clicked)
	vbox.add_child(_grid)

	# ── 战绩 (RichTextLabel + BBCode 彩色) ──
	_score_label = _create_score_rich_label()
	_update_labels()
	vbox.add_child(_score_label)

	# ── 输入处理 + 挂载 + 弹入动画 + 悬浮组件 (统一流程)
	await _mount_panel(_panel)

# ══════════════════════════════════════════════
# 游戏逻辑
# ══════════════════════════════════════════════

func _reset_board() -> void:
	if _eye:
		_eye.look_at_mouse()
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
	await game_viewport.get_tree().create_timer(0.1 + randf() * 0.15).timeout
	if _game_over:
		return
	var ai_move = _minimax_best_move()
	_board[ai_move] = 2
	_last_move = ai_move
	(_grid as _BoardRenderer).set_board(_board, ai_move)
	_say(_pick(_q_ai_move, _POOL_AI_MOVE))

	# 凝视刚落子的位置
	if _eye:
		var grid = _grid as _BoardRenderer
		var local_c = grid.get_cell_center(ai_move)
		_eye.look_at_pos(grid.get_global_transform() * local_c)
	
	# 短暂注视落子，快狠准
	await game_viewport.get_tree().create_timer(0.4).timeout
	if _eye and not _game_over:
		_eye.look_at_mouse()

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
	_update_labels()
	_save_scores()
	SettingsManager.set_int(_score_key("draws"), _draws)
	_show_restart_bubble()
	# 按钮显示后重新确保不超出屏幕
	await game_viewport.get_tree().process_frame
	_clamp_panel_to_screen()
	game_finished.emit(result)

func _on_restart() -> void:
	_reset_board()
	_say(_pick(_q_start, _POOL_START))

func _on_close_extra_cleanup() -> void:
	SettingsManager.set_int(_score_key("draws"), _draws)

func get_close_speech_pool() -> Array:
	return ["对弈中断。...这算你认输。"]

# 井字棋没有自玩模式, 不需要 get_auto_close_lines

func _update_labels() -> void:
	var hue = EventBus.ui_hue

	if _score_label:
		# 胜=青绿调, 负=暗红调, 平=灰蓝调
		var win_c = Color.from_hsv(fmod(hue + 0.15, 1.0), 0.45, 0.85).to_html(false)
		var lose_c = Color(0.85, 0.35, 0.35).to_html(false)
		var draw_c = Color(0.45, 0.55, 0.65).to_html(false)
		var dim = Color(0.4, 0.5, 0.6, 0.5).to_html(false)
		
		# 统一字符串格式化结构
		_score_label.text = "[center]" \
			+ "[color=#%s]胜 [/color][color=#%s]%d[/color]    " % [dim, win_c, _wins] \
			+ "[color=#%s]负 [/color][color=#%s]%d[/color]    " % [dim, lose_c, _losses] \
			+ "[color=#%s]平 [/color][color=#%s]%d[/color]" % [dim, draw_c, _draws] \
			+ "[/center]"

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
	var _has_last_move: bool = false  # 是否有最新落子

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
				# 极快的运算效率：更快的动画进度
				_cell_anims[i] = minf(_cell_anims[i] + delta * 8.0, 1.0)
				needs_redraw = true
				all_done = false
		if _win_line.size() > 0:
			needs_redraw = true
			all_done = false
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

	func get_cell_center(index: int) -> Vector2:
		var cw = size.x / 3.0
		var ch = size.y / 3.0
		var col = index % 3
		var row = int(index / 3)
		return Vector2((float(col) + 0.5) * cw, (float(row) + 0.5) * ch)

	func _draw() -> void:
		var w = size.x
		var h = size.y
		var cw = w / 3.0
		var ch = h / 3.0
		var hue = EventBus.ui_hue
		
		var is_ended = _win_line.size() > 0 or (_board.find(0) == -1 and _win_line.size() == 0)

		# 取消大面积半透明底色，仅保留网格
		# 网格线: 极细、极低存在感的基准轴
		var line_color = Color.from_hsv(hue, 0.2, 0.4, 0.15)
		var cross_color = Color.from_hsv(hue, 0.3, 0.7, 0.4)
		for i in range(1, 3):
			draw_line(Vector2(cw * i, ch * 0.1), Vector2(cw * i, h - ch * 0.1), line_color, 1.0, true)
			draw_line(Vector2(cw * 0.1, ch * i), Vector2(w - cw * 0.1, ch * i), line_color, 1.0, true)
		
		# 四个高精度十字瞄准节点
		for gx in range(1, 3):
			for gy in range(1, 3):
				var px = cw * gx
				var py = ch * gy
				draw_line(Vector2(px - 3, py), Vector2(px + 3, py), cross_color, 1.0, true)
				draw_line(Vector2(px, py - 3), Vector2(px, py + 3), cross_color, 1.0, true)

		# Hover 预览: 边角锁定框 [ ]
		if _hover_cell >= 0 and _board[_hover_cell] == 0 and not is_ended:
			var hcx = (float(_hover_cell % 3) + 0.5) * cw
			var hcy = (float(_hover_cell / 3) + 0.5) * ch
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

		# 棋子
		for i in range(9):
			if _board[i] == 0:
				continue
			var cx = (float(i % 3) + 0.5) * cw
			var cy = (float(i / 3) + 0.5) * ch
			var anim_t = _cell_anims[i]
			var scale_t = _ease_out_expo(anim_t)
			
			if scale_t < 0.01:
				continue
				
			var is_winning_cell = _win_line.has(i)
			var dim_alpha = 1.0
			# 如果游戏结束，降低非连线格子的透明度
			if _win_line.size() > 0 and not is_winning_cell:
				dim_alpha = 0.2
			# 平局所有都变暗一点
			if _board.find(0) == -1 and _win_line.size() == 0:
				dim_alpha = 0.4
			
			var block_size = minf(cw, ch)
			if _board[i] == 1:
				_draw_precision_x(Vector2(cx, cy), block_size, hue, scale_t, dim_alpha)
			else:
				_draw_precision_o(Vector2(cx, cy), block_size, hue, scale_t, dim_alpha)

		# 极简终局判定线
		if _win_line.size() == 3:
			var start_idx = _win_line[0]
			var end_idx = _win_line[2]
			var sx = (float(start_idx % 3) + 0.5) * cw
			var sy = (float(start_idx / 3) + 0.5) * ch
			var ex = (float(end_idx % 3) + 0.5) * cw
			var ey = (float(end_idx / 3) + 0.5) * ch
			
			var line_c = Color.from_hsv(hue, 0.2, 1.0, 0.9)
			# 锐利、高对比度的实线，不再糊一堆光晕
			draw_line(Vector2(sx, sy), Vector2(ex, ey), line_c, 2.0, true)
			# 起止点的微小终端框
			draw_rect(Rect2(Vector2(sx, sy) - Vector2(3, 3), Vector2(6, 6)), line_c, false, 1.0)
			draw_rect(Rect2(Vector2(ex, ey) - Vector2(3, 3), Vector2(6, 6)), line_c, false, 1.0)

	func _draw_precision_x(center: Vector2, cell_size: float, hue: float, scale_t: float, dim_alpha: float) -> void:
		var c = Color.from_hsv(hue, 0.3, 0.9, dim_alpha)
		var gap = cell_size * 0.05
		var arm = cell_size * 0.25 * scale_t
		
		# 像两对分离的线段汇聚，中间留空
		draw_line(center + Vector2(-gap, -gap), center + Vector2(-gap - arm, -gap - arm), c, 1.5, true)
		draw_line(center + Vector2(gap, gap), center + Vector2(gap + arm, gap + arm), c, 1.5, true)
		
		draw_line(center + Vector2(gap, -gap), center + Vector2(gap + arm, -gap - arm), c, 1.5, true)
		draw_line(center + Vector2(-gap, gap), center + Vector2(-gap - arm, gap + arm), c, 1.5, true)
		
		# 落子瞬间的一个极亮中心点 (随 scale_t 放大后迅速模糊消失)
		if scale_t < 1.0:
			var flash = Color.from_hsv(hue, 0.1, 1.0, (1.0 - scale_t) * dim_alpha)
			draw_circle(center, 2.0 + scale_t * 2.0, flash)

	func _draw_precision_o(center: Vector2, cell_size: float, hue: float, scale_t: float, dim_alpha: float) -> void:
		var ai_hue = fmod(hue + 0.45, 1.0)
		var c = Color.from_hsv(ai_hue, 0.4, 0.95, dim_alpha)
		var r = cell_size * 0.25 * scale_t
		
		# 极简锐利的单层圆弧 (留一个小缺口, 不再滚动)
		var start_angle = -PI / 2 + 0.15 
		var end_angle = PI * 1.5 - 0.15
		
		# 16~32 边缘分辨率
		draw_arc(center, r, start_angle, end_angle, 32, c, 1.5, true)
		
		# 圆弧缺口两端的闭合横线 (类似仪表盘)
		var p1 = center + Vector2(cos(start_angle), sin(start_angle)) * r
		var p2 = center + Vector2(cos(end_angle), sin(end_angle)) * r
		# 获取切向方向
		var t1 = (p1 - center).normalized().rotated(PI/2) * 2.0
		var t2 = (p2 - center).normalized().rotated(PI/2) * 2.0
		draw_line(p1 - t1, p1 + t1, c, 1.0, true)
		draw_line(p2 - t2, p2 + t2, c, 1.0, true)

		# 落子瞬间的内部瞄准纹理
		if scale_t < 1.0:
			var flash = Color.from_hsv(ai_hue, 0.1, 1.0, (1.0 - scale_t) * dim_alpha)
			draw_arc(center, r * 0.6, 0, TAU, 16, flash, 1.0, true)

	func _ease_out_expo(t: float) -> float:
		return 1.0 if t == 1.0 else 1.0 - pow(2.0, -10.0 * t)

# ══════════════════════════════════════════════
# 机械单眼与故障背景
# ══════════════════════════════════════════════

class _EyeRenderer extends Control:
	var _target_mode := 0 # 0=mouse, 1=fixed
	var _fixed_target := Vector2.ZERO
	var _pupil_pos := Vector2.ZERO
	
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)
		
	func look_at_mouse() -> void:
		_target_mode = 0
		
	func look_at_pos(global_p: Vector2) -> void:
		_target_mode = 1
		# 转换全局坐标到局部
		_fixed_target = get_global_transform().affine_inverse() * global_p

	func _process(delta: float) -> void:
		var c = size / 2.0
		var target: Vector2
		if _target_mode == 0:
			target = get_local_mouse_position()
		else:
			target = _fixed_target
			
		var diff = target - c
		var target_offset = diff * 0.15
		
		# 针对半径为7.5的复刻圆眼，外框 hw=30, hh=12
		# 安全间隙重估为 rx=21.0, ry=3.5 
		var dist = abs(target_offset.x) / 21.0 + abs(target_offset.y) / 3.5
		if dist > 1.0:
			target_offset /= dist
			
		_pupil_pos = _pupil_pos.lerp(target_offset, delta * 15.0)
		queue_redraw()
		
	func _draw() -> void:
		# 利用全局色与偏移打造单眼质感
		var hue = EventBus.ui_hue
		var c = size / 2.0
		
		# 外层晶状体边框：锐利菱形向两侧延伸连线
		var c_frame = Color.from_hsv(hue, 0.2, 0.5, 0.5)
		var hw = 30.0
		var hh = 12.0
		var frame_pts = PackedVector2Array([
			c + Vector2(-hw, 0), c + Vector2(0, -hh),
			c + Vector2(hw, 0), c + Vector2(0, hh)
		])
		draw_polyline(frame_pts + PackedVector2Array([frame_pts[0]]), c_frame, 1.5, true)
		
		draw_line(Vector2(20, c.y), c + Vector2(-hw - 8, 0), c_frame, 1.0, true)
		draw_line(c + Vector2(hw + 8, 0), Vector2(size.x - 20, c.y), c_frame, 1.0, true)

		var center = c + _pupil_pos
		
		# ================= 极简机能圆环 =================
		# 完全摈弃光晕和动画，与外围大菱形相同风格的高锐度线条
		var c_pupil = Color.from_hsv(hue, 0.2, 0.7, 0.8)
		
		# 外层极简空心圆环
		draw_arc(center, 5.5, 0, TAU, 32, c_pupil, 1.5, true)
		
		# 中心代表聚焦的纯色极小实心点
		draw_circle(center, 1.2, c_pupil, true, -1.0, true)
		# ===================================================

class _GlitchBg extends Control:
	var _time: float = 0.0
	
	func _ready() -> void:
		set_process(true)
		
	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()
			
	func _draw() -> void:
		var hue = EventBus.ui_hue
		
		# 极简背景：无噪波，只有一根极其克制、缓慢循环扫过的光学扫描线
		var scan_y = fmod(_time * 40.0, size.y + 40.0) - 20.0
		
		# 扫描带宽光晕
		var c_band = Color.from_hsv(hue, 0.3, 0.9, 0.03)
		draw_rect(Rect2(0, scan_y, size.x, 12.0), c_band)
		
		# 中心实线 (激光刻度感)
		var c_core = Color.from_hsv(hue, 0.5, 1.0, 0.06)
		draw_rect(Rect2(0, scan_y + 5.0, size.x, 1.0), c_core)

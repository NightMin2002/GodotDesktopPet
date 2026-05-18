# game.gd — 终端五子棋 (连珠推演)
# _draw 自绘 + 鼠标落子 + 威胁评估 AI + 右侧聊天气泡
extends TerminalGameBase

func get_game_id() -> String: return "gomoku"
func get_game_name() -> String: return "连珠推演"
func get_game_desc() -> String: return "15x15 态势博弈"
func supports_auto_play() -> bool: return true

const SIZE := 15
const WIN_COUNT := 5

# ── 话术池 ──
const _POOL_START := ["棋盘已校准。先手执黑。", "态势推演启动。", "连珠协议就绪。请落子。", "新局。矩阵已清空。"]
const _POOL_PLAYER := ["收到。", "...已记录。", "位置已标记。", "嗯。", "收到输入。"]
const _POOL_AI := ["最优落点已计算。", "落子。", "...预期之内。", "决策完成。", "这步不需要犹豫。"]
const _POOL_AI_WIN := ["五连已达成。推演结束。", "...本机的计算是精确的。", "胜负已定。", "态势收敛。胜者: 本机。"]
const _POOL_PLAYER_WIN := ["...数据波动。建议重赛。", "检测到异常序列。", "...散热模块干扰了决策。", "不承认这个结果。"]
const _POOL_DRAW := ["棋盘已满。平局。", "...空间耗尽。可接受的结果。"]
const _POOL_HINT := [
	"...不是在提醒你。只是觉得这么赢没意思。",
	"...你确定不看看那边？",
	"检测到关键节点。不是在帮你。",
	"提醒一下，不是因为在乎你。",
	"临界态势。仅作参考。",
]
const _POOL_UNDO := [
	"...悔棋？记录在案。",
	"允许重来。不是因为心软。",
	"...操作已撤回。下不为例。",
	"数据回滚完成。别养成习惯。",
]

# ── 状态 ──
var _board: Array[int] = []  # 0=空, 1=玩家, 2=AI
var _game_active: bool = false
var _player_turn: bool = true
var _hover: Vector2i = Vector2i(-1, -1)
var _last_move: Vector2i = Vector2i(-1, -1)
var _win_cells: Array[Vector2i] = []
var _result: int = -1
var _move_count: int = 0
var _time: float = 0.0
var _stone_births: Array[float] = []
var _threat_cells: Array[Vector2i] = []
var _history: Array[Vector2i] = []  # 落子历史 (顺序)
var _undo_enabled: bool = true
var _q_hint: Array = []
var _q_undo: Array = []

# ── 布局 ──
var _grid_origin: Vector2 = Vector2.ZERO
var _cell_size: float = 0.0
var _grid_px: float = 0.0

# ── 结算/操作按钮 ──
var _restart_btn: Button = null
var _undo_btn: Button = null

# ── 设置菜单 ──
var _hint_enabled: bool = true
var _menu_open: bool = false
var _menu_btn_rect: Rect2 = Rect2()
var _menu_full_rect: Rect2 = Rect2()  # 按钮+面板合并区域
var _menu_items: Array = []
var _menu_item_rects: Array[Rect2] = []

# ── 聊天气泡 ──
var _chat_log: Array = []
const _CHAT_MAX := 5
const _CHAT_STAY := 5.0
const _CHAT_FADE := 1.5
var _chat_area_x: float = 0.0
var _chat_area_w: float = 0.0
var _q_start: Array = []
var _q_player: Array = []
var _q_ai: Array = []
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
	_menu_items = [
		{ "id": "hint", "label": "态势提示", "enabled": true },
		{ "id": "undo", "label": "允许悔棋", "enabled": true },
	]
	_build_restart_btn()
	_build_undo_btn()
	start_game()

func _process(delta: float) -> void:
	_time += delta
	if _game_active or _chat_log.size() > 0 or _win_cells.size() > 0:
		queue_redraw()

func start_game() -> void:
	_board.resize(SIZE * SIZE)
	_stone_births.resize(SIZE * SIZE)
	for i in range(SIZE * SIZE):
		_board[i] = 0
		_stone_births[i] = -10.0
	_game_active = true
	_player_turn = true
	_hover = Vector2i(-1, -1)
	_last_move = Vector2i(-1, -1)
	_win_cells.clear()
	_result = -1
	_move_count = 0
	_chat_log.clear()
	_time = 0.0
	_threat_cells.clear()
	_history.clear()
	if is_instance_valid(_restart_btn):
		_restart_btn.visible = false
	_update_undo_btn()
	_say(_pick(_q_start, _POOL_START))
	game_started.emit()
	queue_redraw()

func get_hud_data() -> Dictionary: return {}
func get_best_score() -> int: return _move_count

# ══════════════════════════════════════════════
#  话术
# ══════════════════════════════════════════════

func _say(text: String) -> void:
	_chat_log.push_front({ "text": text, "birth": _time })
	if _chat_log.size() > _CHAT_MAX:
		_chat_log.resize(_CHAT_MAX)

func _pick(queue: Array, pool: Array) -> String:
	if queue.is_empty():
		queue.append_array(pool)
		queue.shuffle()
	return queue.pop_back()

# ══════════════════════════════════════════════
#  布局
# ══════════════════════════════════════════════

func _calc_layout() -> void:
	var w = size.x
	var h = size.y
	var chat_ratio = 0.25
	var grid_area_w = w * (1.0 - chat_ratio)
	var header_h = 28.0
	var avail_w = grid_area_w - 16.0
	var avail_h = h - header_h - 8.0
	_cell_size = minf(avail_w / (SIZE - 1), avail_h / (SIZE - 1))
	_grid_px = _cell_size * (SIZE - 1)
	_grid_origin = Vector2(
		(grid_area_w - _grid_px) * 0.5,
		header_h + (avail_h - _grid_px) * 0.5
	)
	_chat_area_x = grid_area_w + 2
	_chat_area_w = w - _chat_area_x - 4

# ══════════════════════════════════════════════
#  输入
# ══════════════════════════════════════════════

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pos = event.position
		var old = _hover
		_hover = _pos_to_grid(pos)
		# 菜单悬浮检测
		var in_menu = _menu_btn_rect.has_point(pos)
		if _menu_open:
			in_menu = in_menu or _menu_full_rect.has_point(pos)
		if in_menu != _menu_open:
			_menu_open = in_menu
		if old != _hover or true:
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var pos = event.position
		# 菜单点击
		if _menu_open:
			for i in range(_menu_item_rects.size()):
				if _menu_item_rects[i].has_point(pos):
					_toggle_setting(_menu_items[i].id)
					queue_redraw()
					return
		if not _game_active or not _player_turn:
			return
		var gp = _pos_to_grid(event.position)
		if gp.x < 0:
			return
		if _board[gp.y * SIZE + gp.x] != 0:
			return
		_threat_cells.clear()
		_place(gp.x, gp.y, 1)
		_say(_pick(_q_player, _POOL_PLAYER))
		if _check_win(gp.x, gp.y, 1):
			_end_game(0)
			return
		if _move_count >= SIZE * SIZE:
			_end_game(2)
			return
		_player_turn = false
		_update_undo_btn()
		get_tree().create_timer(0.3).timeout.connect(_ai_move)

func _pos_to_grid(pos: Vector2) -> Vector2i:
	var rel = pos - _grid_origin
	var gx = roundi(rel.x / _cell_size)
	var gy = roundi(rel.y / _cell_size)
	if gx < 0 or gx >= SIZE or gy < 0 or gy >= SIZE:
		return Vector2i(-1, -1)
	var snap = _grid_origin + Vector2(gx * _cell_size, gy * _cell_size)
	if pos.distance_to(snap) > _cell_size * 0.45:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)

func _place(bx: int, by: int, color: int) -> void:
	var idx = by * SIZE + bx
	_board[idx] = color
	_stone_births[idx] = _time
	_last_move = Vector2i(bx, by)
	_move_count += 1
	_history.append(Vector2i(bx, by))

## 悔棋: 撤回最近一轮 (玩家+AI 各退一步)
func _undo() -> void:
	if not _game_active or not _player_turn or not _undo_enabled:
		return
	if _history.size() < 2:
		return
	# 撤回 AI 的最后一手
	var ai_pos = _history.pop_back()
	_board[ai_pos.y * SIZE + ai_pos.x] = 0
	_stone_births[ai_pos.y * SIZE + ai_pos.x] = -10.0
	# 撤回玩家的最后一手
	var pl_pos = _history.pop_back()
	_board[pl_pos.y * SIZE + pl_pos.x] = 0
	_stone_births[pl_pos.y * SIZE + pl_pos.x] = -10.0
	_move_count -= 2
	_last_move = _history.back() if _history.size() > 0 else Vector2i(-1, -1)
	_scan_threats()
	_say(_pick(_q_undo, _POOL_UNDO))
	_update_undo_btn()
	queue_redraw()

# ══════════════════════════════════════════════
#  AI (威胁评估)
# ══════════════════════════════════════════════

func _ai_move() -> void:
	if not _game_active:
		return
	var best = _find_best(2)
	_place(best.x, best.y, 2)
	_say(_pick(_q_ai, _POOL_AI))
	if _check_win(best.x, best.y, 2):
		_end_game(1)
		return
	if _move_count >= SIZE * SIZE:
		_end_game(2)
		return
	_player_turn = true
	_scan_threats()
	_update_undo_btn()

func auto_play_step() -> void:
	if not _game_active or not _player_turn:
		return
	var best = _find_best(1)
	_place(best.x, best.y, 1)
	if _check_win(best.x, best.y, 1):
		_end_game(0)
		return
	if _move_count >= SIZE * SIZE:
		_end_game(2)
		return
	_player_turn = false
	get_tree().create_timer(0.3).timeout.connect(_ai_move)

func _find_best(color: int) -> Vector2i:
	if _move_count == 0:
		return Vector2i(SIZE / 2, SIZE / 2)
	var opp = 3 - color
	var best_score = -1
	var best_pos = Vector2i(SIZE / 2, SIZE / 2)
	for y in range(SIZE):
		for x in range(SIZE):
			if _board[y * SIZE + x] != 0:
				continue
			if not _has_neighbor(x, y):
				continue
			var atk = _eval_pos(x, y, color)
			var def = _eval_pos(x, y, opp)
			var score: int
			if atk >= 100000:
				score = atk + 100000
			elif def >= 100000:
				score = def + 50000
			else:
				score = atk + int(def * 0.9)
			if score > best_score:
				best_score = score
				best_pos = Vector2i(x, y)
	return best_pos

func _has_neighbor(bx: int, by: int) -> bool:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx == 0 and dy == 0:
				continue
			var nx = bx + dx
			var ny = by + dy
			if nx >= 0 and nx < SIZE and ny >= 0 and ny < SIZE:
				if _board[ny * SIZE + nx] != 0:
					return true
	return false

func _eval_pos(bx: int, by: int, color: int) -> int:
	var total = 0
	var dirs = [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,-1)]
	for d in dirs:
		var count = 1
		var open_ends = 0
		# 正向
		var i = 1
		while true:
			var nx = bx + d.x * i; var ny = by + d.y * i
			if nx < 0 or nx >= SIZE or ny < 0 or ny >= SIZE: break
			if _board[ny * SIZE + nx] == color: count += 1; i += 1
			else:
				if _board[ny * SIZE + nx] == 0: open_ends += 1
				break
		# 反向
		i = 1
		while true:
			var nx = bx - d.x * i; var ny = by - d.y * i
			if nx < 0 or nx >= SIZE or ny < 0 or ny >= SIZE: break
			if _board[ny * SIZE + nx] == color: count += 1; i += 1
			else:
				if _board[ny * SIZE + nx] == 0: open_ends += 1
				break
		# 评分
		if count >= 5: total += 100000
		elif count == 4: total += 10000 if open_ends == 2 else (1000 if open_ends == 1 else 0)
		elif count == 3: total += 1000 if open_ends == 2 else (100 if open_ends == 1 else 0)
		elif count == 2: total += 100 if open_ends == 2 else (10 if open_ends == 1 else 0)
		elif count == 1: total += 10 if open_ends == 2 else (1 if open_ends == 1 else 0)
	return total

# ══════════════════════════════════════════════
#  胜负检测
# ══════════════════════════════════════════════

func _check_win(bx: int, by: int, color: int) -> bool:
	var dirs = [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,-1)]
	for d in dirs:
		var cells: Array[Vector2i] = [Vector2i(bx, by)]
		for sign in [1, -1]:
			var i = 1
			while true:
				var nx = bx + d.x * i * sign; var ny = by + d.y * i * sign
				if nx < 0 or nx >= SIZE or ny < 0 or ny >= SIZE: break
				if _board[ny * SIZE + nx] == color: cells.append(Vector2i(nx, ny)); i += 1
				else: break
		if cells.size() >= WIN_COUNT:
			_win_cells = cells
			return true
	return false

## 切换设置项
func _toggle_setting(id: String) -> void:
	for item in _menu_items:
		if item.id == id:
			item.enabled = not item.enabled
			if id == "hint":
				_hint_enabled = item.enabled
				if not _hint_enabled:
					_threat_cells.clear()
			elif id == "undo":
				_undo_enabled = item.enabled
			break

## 扫描 AI 威胁点 (AI 有活路的三连/四连位置)
func _scan_threats() -> void:
	_threat_cells.clear()
	if not _hint_enabled:
		return
	var dirs = [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,-1)]
	for y in range(SIZE):
		for x in range(SIZE):
			if _board[y * SIZE + x] != 0:
				continue
			for d in dirs:
				var count = 1
				var open_ends = 0
				for sign in [1, -1]:
					var i = 1
					while true:
						var nx = x + d.x * i * sign; var ny = y + d.y * i * sign
						if nx < 0 or nx >= SIZE or ny < 0 or ny >= SIZE: break
						if _board[ny * SIZE + nx] == 2: count += 1; i += 1
						else:
							if _board[ny * SIZE + nx] == 0: open_ends += 1
							break
				# count=5+: 必杀 (4连+此位=5连)
				# count=4 且有活路: 活三/冲四，还能堵
				# count=4 两端全死: 不提示
				var threat = count >= 5 or (count >= 4 and open_ends > 0)
				if threat and Vector2i(x, y) not in _threat_cells:
					_threat_cells.append(Vector2i(x, y))

func _end_game(result: int) -> void:
	_game_active = false
	_result = result
	match result:
		0: _say(_pick(_q_player_win, _POOL_PLAYER_WIN))
		1: _say(_pick(_q_ai_win, _POOL_AI_WIN))
		2: _say(_pick(_q_draw, _POOL_DRAW))
	if is_instance_valid(_restart_btn):
		_restart_btn.visible = true
	game_over.emit(result)

# ══════════════════════════════════════════════
#  重开按钮
# ══════════════════════════════════════════════

func _build_restart_btn() -> void:
	_restart_btn = Button.new()
	_restart_btn.text = "重新推演"
	_restart_btn.focus_mode = Control.FOCUS_NONE
	_restart_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_restart_btn.add_theme_font_size_override("font_size", 12)
	_restart_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_restart_btn.add_theme_stylebox_override("normal", GameTerminalStyles.small_btn_normal())
	_restart_btn.add_theme_stylebox_override("hover", GameTerminalStyles.small_btn_hover())
	_restart_btn.add_theme_stylebox_override("pressed", GameTerminalStyles.small_btn_hover())
	_restart_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_restart_btn.pressed.connect(start_game)
	_restart_btn.visible = false
	add_child(_restart_btn)

func _build_undo_btn() -> void:
	_undo_btn = Button.new()
	_undo_btn.text = "悔棋 (Ctrl+Z)"
	_undo_btn.focus_mode = Control.FOCUS_NONE
	_undo_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_undo_btn.add_theme_font_size_override("font_size", 12)
	_undo_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_undo_btn.add_theme_stylebox_override("normal", GameTerminalStyles.small_btn_normal())
	_undo_btn.add_theme_stylebox_override("hover", GameTerminalStyles.small_btn_hover())
	_undo_btn.add_theme_stylebox_override("pressed", GameTerminalStyles.small_btn_hover())
	_undo_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_undo_btn.pressed.connect(_undo)
	_undo_btn.visible = false
	add_child(_undo_btn)

func _update_undo_btn() -> void:
	if not is_instance_valid(_undo_btn):
		return
	_undo_btn.visible = _game_active and _player_turn and _undo_enabled and _history.size() >= 2

# ══════════════════════════════════════════════
#  渲染
# ══════════════════════════════════════════════

func _draw() -> void:
	_calc_layout()
	var hue = EventBus.ui_hue
	var font = ThemeDB.fallback_font

	# ── 顶部 HUD ──
	if font:
		var lbl_c = Color.from_hsv(hue, 0.3, 0.7, 0.5)
		var turn_text = "END" if not _game_active else ("USR" if _player_turn else "SYS")
		var turn_color = GameTerminalStyles.dim() if not _game_active else (GameTerminalStyles.status_active() if _player_turn else GameTerminalStyles.status_warning())
		draw_string(font, Vector2(_grid_origin.x, _grid_origin.y - 10.0), "TURN",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lbl_c)
		draw_string(font, Vector2(_grid_origin.x + 40, _grid_origin.y - 10.0), turn_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, turn_color)
		draw_string(font, Vector2(_grid_origin.x + _grid_px - 56, _grid_origin.y - 10.0), "MOVE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lbl_c)
		draw_string(font, Vector2(_grid_origin.x + _grid_px - 12, _grid_origin.y - 10.0), str(_move_count),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameTerminalStyles.dim())

	# ── 设置菜单 (聊天区顶部) ──
	if font:
		var menu_fs = 12
		var menu_y = _grid_origin.y - 12.0
		var btn_text = "⚙ 部署配置"
		var btn_c = GameTerminalStyles.bright() if _menu_open else GameTerminalStyles.dim()
		draw_string(font, Vector2(_chat_area_x, menu_y), btn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, menu_fs, btn_c)
		_menu_btn_rect = Rect2(_chat_area_x - 2, menu_y - 14, _chat_area_w, 18)
		if _menu_open:
			var panel_y = menu_y + 4
			var row_h = 24
			var panel_h = _menu_items.size() * row_h + 8
			var panel_rect = Rect2(_chat_area_x - 2, panel_y, _chat_area_w + 4, panel_h)
			_menu_full_rect = _menu_btn_rect.merge(panel_rect)
			draw_rect(panel_rect, GameTerminalStyles.bg_deep())
			draw_rect(panel_rect, GameTerminalStyles.border_base(), false, 2.0)
			_menu_item_rects.clear()
			for i in range(_menu_items.size()):
				var item = _menu_items[i]
				var iy = panel_y + 4 + i * row_h
				var ir = Rect2(_chat_area_x - 2, iy, _chat_area_w + 4, row_h)
				_menu_item_rects.append(ir)
				var check = "[■]" if item.enabled else "[ ]"
				var ic = GameTerminalStyles.accent() if item.enabled else GameTerminalStyles.dim()
				draw_string(font, Vector2(_chat_area_x + 6, iy + 17), check + " " + item.label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, menu_fs, ic)

	# ── 棋盘网格 ──
	var line_c = GameTerminalStyles.border_base()
	line_c.a *= 0.5
	var aa = GameTerminalStyles.get_current_theme_id() != "retro"
	for i in range(SIZE):
		var offset = i * _cell_size
		draw_line(_grid_origin + Vector2(0, offset), _grid_origin + Vector2(_grid_px, offset), line_c, 1.0, aa)
		draw_line(_grid_origin + Vector2(offset, 0), _grid_origin + Vector2(offset, _grid_px), line_c, 1.0, aa)

	# ── 星位 ──
	var star_r = maxf(2.0, _cell_size * 0.1)
	var star_c = line_c
	star_c.a += 0.3
	for sp in [Vector2i(3,3), Vector2i(3,11), Vector2i(11,3), Vector2i(11,11), Vector2i(7,7)]:
		if aa:
			draw_circle(_grid_origin + Vector2(sp.x * _cell_size, sp.y * _cell_size), star_r, star_c, true, -1.0, true)
		else:
			draw_rect(Rect2(_grid_origin + Vector2(sp.x * _cell_size - star_r, sp.y * _cell_size - star_r), Vector2(star_r*2, star_r*2)), star_c)

	# ── 悬停指示 ──
	if _hover.x >= 0 and _game_active and _player_turn:
		if _board[_hover.y * SIZE + _hover.x] == 0:
			var hp = _grid_origin + Vector2(_hover.x * _cell_size, _hover.y * _cell_size)
			var hr = _cell_size * 0.4
			var hc = GameTerminalStyles.dim()
			if aa:
				draw_circle(hp, hr*0.5, hc, true, -1.0, true)
			else:
				var hl = 6.0
				draw_line(hp - Vector2(hr, hr), hp - Vector2(hr - hl, hr), hc, 2)
				draw_line(hp - Vector2(hr, hr), hp - Vector2(hr, hr - hl), hc, 2)
				draw_line(hp + Vector2(hr, -hr), hp + Vector2(hr - hl, -hr), hc, 2)
				draw_line(hp + Vector2(hr, -hr), hp + Vector2(hr, -hr + hl), hc, 2)
				draw_line(hp + Vector2(-hr, hr), hp + Vector2(-hr + hl, hr), hc, 2)
				draw_line(hp + Vector2(-hr, hr), hp + Vector2(-hr, hr - hl), hc, 2)
				draw_line(hp + Vector2(hr, hr), hp + Vector2(hr - hl, hr), hc, 2)
				draw_line(hp + Vector2(hr, hr), hp + Vector2(hr, hr - hl), hc, 2)

	# ── 威胁标记 (脉冲警告) ──
	if _threat_cells.size() > 0 and _game_active:
		var warn_c = GameTerminalStyles.status_warning()
		warn_c.a = sin(_time * 4.0) * 0.3 + 0.5
		var tr = _cell_size * 0.42
		for tc in _threat_cells:
			var tp = _grid_origin + Vector2(tc.x * _cell_size, tc.y * _cell_size)
			if aa:
				draw_arc(tp, tr, 0, TAU, 20, warn_c, 1.5, true)
			else:
				draw_rect(Rect2(tp - Vector2(tr, tr), Vector2(tr*2, tr*2)), warn_c, false, 2.0)
			var cross = _cell_size * 0.15
			draw_line(tp - Vector2(cross, 0), tp + Vector2(cross, 0), warn_c, 2.0, aa)
			draw_line(tp - Vector2(0, cross), tp + Vector2(0, cross), warn_c, 2.0, aa)

	# ── 棋子 (带弹出动画) ──
	var stone_half = _cell_size * 0.38
	var ai_hue = fmod(hue + 0.45, 1.0)
	var is_retro = GameTerminalStyles.get_current_theme_id() == "retro"
	for y in range(SIZE):
		for x in range(SIZE):
			var v = _board[y * SIZE + x]
			if v == 0: continue
			var pos = _grid_origin + Vector2(x * _cell_size, y * _cell_size)
			var is_win = Vector2i(x, y) in _win_cells
			var is_last = Vector2i(x, y) == _last_move
			
			# 颜色与透明度
			var base_c = GameTerminalStyles.accent() if v == 1 else Color.from_hsv(ai_hue, 0.6, 0.9)
			var age = _time - _stone_births[y * SIZE + x]
			var t = clampf(age / 0.18, 0.0, 1.0)
			var ease_t = 1.0 - pow(1.0 - t, 3.0)
			var cur_s = stone_half * ease_t
			if cur_s < 0.5: continue
			
			var final_c = base_c
			final_c.a = 1.0 if is_win else 0.75
			
			# 绘制本体
			if is_retro:
				# 实心方块像素风
				var rect = Rect2(pos - Vector2(cur_s, cur_s), Vector2(cur_s * 2, cur_s * 2))
				draw_rect(rect, final_c)
				# 加一点内圈高对比度刻画
				if cur_s > 4.0:
					draw_rect(Rect2(pos - Vector2(cur_s-3, cur_s-3), Vector2((cur_s-3)*2, (cur_s-3)*2)), GameTerminalStyles.bg_deep())
					draw_rect(Rect2(pos - Vector2(2, 2), Vector2(4, 4)), final_c)
				# 最后一手闪光框
				if is_last and t >= 1.0:
					var lr = Rect2(pos - Vector2(cur_s+2, cur_s+2), Vector2((cur_s+2)*2, (cur_s+2)*2))
					draw_rect(lr, GameTerminalStyles.bright(), false, 2.0)
			else:
				# 极简圆润风格
				draw_circle(pos, cur_s, final_c, true, -1.0, true)
				if is_last and t >= 1.0:
					draw_arc(pos, cur_s + 2.0, 0, TAU, 20, Color(1,1,1,0.6), 1.5, true)
			
			# 落点涟漪
			if t < 1.0:
				var flash_a = (1.0 - t) * 0.5
				var flash_r = cur_s + (1.0 - t) * cur_s
				var flash_c = base_c
				flash_c.a = flash_a
				if is_retro:
					draw_rect(Rect2(pos - Vector2(flash_r, flash_r), Vector2(flash_r * 2, flash_r * 2)), flash_c, false, 2.0)
				else:
					draw_arc(pos, flash_r, 0, TAU, 20, flash_c, 1.5, true)

	# ── 外框 ──
	var frame_pad = 6.0
	draw_rect(Rect2(_grid_origin - Vector2(frame_pad, frame_pad), Vector2(_grid_px + frame_pad*2, _grid_px + frame_pad*2)),
		GameTerminalStyles.border_base(), false, 2.0 if is_retro else 1.0)

	# ── 右侧聊天气泡 ──
	if font and _chat_log.size() > 0:
		var bubble_y = _grid_origin.y + _grid_px
		var fs = 12
		for i in range(_chat_log.size()):
			var msg = _chat_log[i]
			var age = _time - msg.birth
			var a: float
			if age < 0.25: a = age / 0.25
			elif age < _CHAT_STAY: a = 1.0
			elif age < _CHAT_STAY + _CHAT_FADE: a = 1.0 - (age - _CHAT_STAY) / _CHAT_FADE
			else: continue
			var text_size = font.get_multiline_string_size(msg.text, HORIZONTAL_ALIGNMENT_LEFT, _chat_area_w - 12, fs)
			var bubble_h = text_size.y + 10
			bubble_y -= bubble_h + 6
			var bg = Rect2(_chat_area_x, bubble_y, _chat_area_w, bubble_h)
			
			# 使用 GameTerminalStyles 来决定底色
			var fill_c = GameTerminalStyles.bg_deep()
			fill_c.a = 0.8 * a
			draw_rect(bg, fill_c)
			var bc = GameTerminalStyles.border_base()
			bc.a = a
			draw_rect(bg, bc, false, 2.0 if is_retro else 1.0)
			
			var tc = GameTerminalStyles.bright()
			tc.a = a
			draw_multiline_string(font, Vector2(_chat_area_x + 6, bubble_y + fs + 2), msg.text,
				HORIZONTAL_ALIGNMENT_LEFT, _chat_area_w - 12, fs, -1, tc)

	# ── 按钮定位 ──
	if is_instance_valid(_undo_btn):
		_undo_btn.position = Vector2(_chat_area_x, _grid_origin.y + 24)
		_undo_btn.size = Vector2(_chat_area_w, 24)
	if is_instance_valid(_restart_btn) and _restart_btn.visible:
		_restart_btn.position = Vector2(_chat_area_x, _grid_origin.y + _grid_px - 26)
		_restart_btn.size = Vector2(_chat_area_w, 28)

func _unhandled_key_input(event: InputEvent) -> void:
	if not _game_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and event.ctrl_pressed:
			_undo()

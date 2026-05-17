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

func _build_undo_btn() -> void:
	_undo_btn = Button.new()
	_undo_btn.text = "悔棋 (Ctrl+Z)"
	_undo_btn.focus_mode = Control.FOCUS_NONE
	_undo_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_undo_btn.add_theme_font_size_override("font_size", 11)
	var hue = EventBus.ui_hue
	_undo_btn.add_theme_color_override("font_color", Color.from_hsv(hue, 0.2, 0.65, 0.6))
	_undo_btn.add_theme_color_override("font_hover_color", Color.from_hsv(hue, 0.4, 1.0, 0.9))
	var sn = StyleBoxFlat.new()
	sn.bg_color = Color(0.05, 0.07, 0.12, 0.5)
	sn.set_border_width_all(1)
	sn.border_color = Color.from_hsv(hue, 0.2, 0.4, 0.2)
	sn.set_corner_radius_all(0)
	sn.content_margin_left = 6; sn.content_margin_right = 6
	sn.content_margin_top = 3; sn.content_margin_bottom = 3
	_undo_btn.add_theme_stylebox_override("normal", sn)
	var sh = sn.duplicate()
	sh.bg_color = Color(0.08, 0.12, 0.20, 0.7)
	sh.border_color = Color.from_hsv(hue, 0.3, 0.7, 0.3)
	_undo_btn.add_theme_stylebox_override("hover", sh)
	_undo_btn.add_theme_stylebox_override("pressed", sh)
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
		var menu_fs = 11
		var menu_y = _grid_origin.y - 10.0
		var btn_text = "⚙ 设置"
		var btn_c = Color.from_hsv(hue, 0.2, 0.6, 0.5 if not _menu_open else 0.8)
		draw_string(font, Vector2(_chat_area_x, menu_y), btn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, menu_fs, btn_c)
		_menu_btn_rect = Rect2(_chat_area_x - 2, menu_y - 14, _chat_area_w, 18)
		# 展开面板
		if _menu_open:
			var panel_y = menu_y + 4
			var row_h = 22
			var panel_h = _menu_items.size() * row_h + 8
			var panel_rect = Rect2(_chat_area_x - 2, panel_y, _chat_area_w + 4, panel_h)
			_menu_full_rect = _menu_btn_rect.merge(panel_rect)
			draw_rect(panel_rect, Color(0.04, 0.06, 0.10, 0.85))
			draw_rect(panel_rect, Color.from_hsv(hue, 0.25, 0.5, 0.25), false, 1.0)
			_menu_item_rects.clear()
			for i in range(_menu_items.size()):
				var item = _menu_items[i]
				var iy = panel_y + 4 + i * row_h
				var ir = Rect2(_chat_area_x - 2, iy, _chat_area_w + 4, row_h)
				_menu_item_rects.append(ir)
				var check = "[x]" if item.enabled else "[ ]"
				var ic = Color.from_hsv(hue, 0.3, 0.8, 0.75) if item.enabled else Color.from_hsv(hue, 0.1, 0.5, 0.4)
				draw_string(font, Vector2(_chat_area_x + 2, iy + 15), check + " " + item.label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, menu_fs, ic)

	# ── 棋盘网格 ──
	var line_c = Color.from_hsv(hue, 0.15, 0.4, 0.25)
	for i in range(SIZE):
		var offset = i * _cell_size
		draw_line(_grid_origin + Vector2(0, offset), _grid_origin + Vector2(_grid_px, offset), line_c, 1.0, true)
		draw_line(_grid_origin + Vector2(offset, 0), _grid_origin + Vector2(offset, _grid_px), line_c, 1.0, true)

	# 星位
	var star_r = maxf(2.0, _cell_size * 0.1)
	var star_c = Color.from_hsv(hue, 0.2, 0.5, 0.35)
	for sp in [Vector2i(3,3), Vector2i(3,11), Vector2i(11,3), Vector2i(11,11), Vector2i(7,7)]:
		draw_circle(_grid_origin + Vector2(sp.x * _cell_size, sp.y * _cell_size), star_r, star_c, true, -1.0, true)

	# ── 悬停指示 ──
	if _hover.x >= 0 and _game_active and _player_turn:
		if _board[_hover.y * SIZE + _hover.x] == 0:
			var hp = _grid_origin + Vector2(_hover.x * _cell_size, _hover.y * _cell_size)
			var hr = _cell_size * 0.38
			draw_circle(hp, hr, Color.from_hsv(hue, 0.4, 0.9, 0.15), true, -1.0, true)
			draw_arc(hp, hr, 0, TAU, 24, Color.from_hsv(hue, 0.4, 0.9, 0.3), 1.0, true)

	# ── 威胁标记 (脉冲警告) ──
	if _threat_cells.size() > 0 and _game_active:
		var pulse = sin(_time * 4.0) * 0.15 + 0.55
		var warn_c = Color(0.95, 0.35, 0.25, pulse)
		var tr = _cell_size * 0.42
		for tc in _threat_cells:
			var tp = _grid_origin + Vector2(tc.x * _cell_size, tc.y * _cell_size)
			draw_arc(tp, tr, 0, TAU, 20, warn_c, 1.5, true)
			# 十字瞄准
			var cross = _cell_size * 0.15
			draw_line(tp - Vector2(cross, 0), tp + Vector2(cross, 0), warn_c, 1.0, true)
			draw_line(tp - Vector2(0, cross), tp + Vector2(0, cross), warn_c, 1.0, true)

	# ── 棋子 (带弹出动画) ──
	var stone_r = _cell_size * 0.4
	var ai_hue = fmod(hue + 0.45, 1.0)
	for y in range(SIZE):
		for x in range(SIZE):
			var v = _board[y * SIZE + x]
			if v == 0: continue
			var pos = _grid_origin + Vector2(x * _cell_size, y * _cell_size)
			var is_win = Vector2i(x, y) in _win_cells
			var is_last = Vector2i(x, y) == _last_move
			var ch = hue if v == 1 else ai_hue
			var sat = 0.5 if v == 1 else 0.45
			# 动画缩放
			var age = _time - _stone_births[y * SIZE + x]
			var t = clampf(age / 0.18, 0.0, 1.0)
			var ease_t = 1.0 - pow(1.0 - t, 3.0)  # ease-out cubic
			var r = stone_r * ease_t
			if r < 0.5: continue
			var ca = (0.9 if is_win else 0.7) * ease_t
			draw_circle(pos, r, Color.from_hsv(ch, sat, 0.95, ca), true, -1.0, true)
			# 落点闪光涟漪
			if t < 1.0:
				var flash_a = (1.0 - t) * 0.5
				var flash_r = stone_r * (1.0 + (1.0 - t) * 0.8)
				draw_arc(pos, flash_r, 0, TAU, 20, Color.from_hsv(ch, 0.2, 1.0, flash_a), 1.5, true)
			# 最后一手标记
			if is_last and t >= 1.0:
				draw_arc(pos, stone_r + 1.5, 0, TAU, 20, Color.from_hsv(ch, 0.3, 1.0, 0.4), 1.5, true)

	# ── 外框 ──
	draw_rect(Rect2(_grid_origin - Vector2(4, 4), Vector2(_grid_px + 8, _grid_px + 8)),
		Color.from_hsv(hue, 0.3, 0.5, 0.15), false, 1.0)

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
			bubble_y -= bubble_h + 4
			var bg = Rect2(_chat_area_x, bubble_y, _chat_area_w, bubble_h)
			draw_rect(bg, Color(0.05, 0.07, 0.12, 0.65 * a))
			draw_rect(bg, Color.from_hsv(hue, 0.25, 0.5, 0.15 * a), false, 1.0)
			draw_multiline_string(font, Vector2(_chat_area_x + 6, bubble_y + fs + 2), msg.text,
				HORIZONTAL_ALIGNMENT_LEFT, _chat_area_w - 12, fs, -1, Color.from_hsv(hue, 0.12, 0.75, 0.85 * a))

	# ── 按钮定位 ──
	# 悔棋按钮: 设置菜单下方
	if is_instance_valid(_undo_btn):
		_undo_btn.position = Vector2(_chat_area_x, _grid_origin.y + 20)
		_undo_btn.size = Vector2(_chat_area_w, 24)
	# 重开按钮: 棋盘底部下方
	if is_instance_valid(_restart_btn) and _restart_btn.visible:
		_restart_btn.position = Vector2(_chat_area_x, _grid_origin.y + _grid_px + 6)
		_restart_btn.size = Vector2(_chat_area_w, 26)

func _unhandled_key_input(event: InputEvent) -> void:
	if not _game_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and event.ctrl_pressed:
			_undo()

# terminal_2048.gd — 终端原生 2048 (矩阵叠加)
# _draw 自绘 + 键盘方向键滑动
extends Control

signal game_started
signal game_over(result: int)  # 0=胜(达到2048), 1=负(无法移动)

const GRID := 4
const WIN_VAL := 2048

var _board: Array = []
var _score: int = 0
var _game_active: bool = false
var _result: int = -1
var _time: float = 0.0
var _won_shown: bool = false

var _grid_origin: Vector2 = Vector2.ZERO
var _cell_size: float = 0.0
const _GAP := 4.0

var _result_overlay: PanelContainer
var _result_label: Label
var _restart_btn: Button

# 方块背景色
const TILE_BG := {
	0:    Color(0.06, 0.08, 0.12, 0.3),
	2:    Color(0.14, 0.20, 0.32, 0.7),
	4:    Color(0.18, 0.26, 0.40, 0.7),
	8:    Color(0.50, 0.35, 0.15, 0.75),
	16:   Color(0.58, 0.36, 0.12, 0.8),
	32:   Color(0.62, 0.28, 0.16, 0.8),
	64:   Color(0.68, 0.22, 0.14, 0.85),
	128:  Color(0.62, 0.52, 0.14, 0.85),
	256:  Color(0.68, 0.58, 0.12, 0.85),
	512:  Color(0.72, 0.62, 0.10, 0.85),
	1024: Color(0.78, 0.68, 0.14, 0.9),
	2048: Color(0.82, 0.78, 0.22, 0.95),
}

func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_result_overlay()
	start_game()

## HUD 协议: 得分 + 最大块
func get_hud_data() -> Dictionary:
	var score_c = GameTerminalStyles.status_warning() if _score > 0 else GameTerminalStyles.dim()
	return {
		"score": { "label": "SCORE", "value": str(_score), "color": score_c },
		"max": { "label": "MAX", "value": str(_max_tile()), "color": GameTerminalStyles.dim() },
	}

## 最佳分数 (供终端持久化)
func get_best_score() -> int:
	return _score

## 自玩 AI: 每步操作 (贪心策略: 优先向左/向下)
func auto_play_step() -> void:
	if not _game_active:
		return
	# 优先方向序列: 左 → 下 → 上 → 右 (角落策略)
	# _slide_* 内部已有 _after_slide 检测, 无效移动不会产生副作用
	var old = _board.duplicate()
	_slide_left()
	if _board != old: return
	_slide_down()
	if _board != old: return
	_slide_up()
	if _board != old: return
	_slide_right()

func _process(delta: float) -> void:
	_time += delta
	if _game_active:
		if Input.is_action_just_pressed("ui_up"):
			_slide_up()
		elif Input.is_action_just_pressed("ui_right"):
			_slide_right()
		elif Input.is_action_just_pressed("ui_down"):
			_slide_down()
		elif Input.is_action_just_pressed("ui_left"):
			_slide_left()
	queue_redraw()

func start_game() -> void:
	_board.resize(GRID * GRID)
	for i in range(GRID * GRID):
		_board[i] = 0
	_score = 0
	_game_active = true
	_result = -1
	_won_shown = false
	_time = 0.0
	_spawn_tile()
	_spawn_tile()
	if is_instance_valid(_result_overlay):
		_result_overlay.visible = false
	game_started.emit()
	queue_redraw()

# ══════════════════════════════════════════════
#  布局
# ══════════════════════════════════════════════

func _calc_layout() -> void:
	var w = size.x
	var h = size.y
	var header_h = 36.0
	var avail = minf(w - 16.0, h - header_h - 8.0)
	_cell_size = (avail - _GAP * (GRID - 1)) / GRID
	var total = _cell_size * GRID + _GAP * (GRID - 1)
	_grid_origin = Vector2(
		(w - total) * 0.5,
		header_h + (h - header_h - total) * 0.5
	)

func _cell_rect(idx: int) -> Rect2:
	var col = idx % GRID
	var row = idx / GRID
	return Rect2(
		_grid_origin + Vector2(col * (_cell_size + _GAP), row * (_cell_size + _GAP)),
		Vector2(_cell_size, _cell_size)
	)

# ══════════════════════════════════════════════
#  核心逻辑
# ══════════════════════════════════════════════

func _merge_line(line: Array) -> Array:
	var compact = []
	for v in line:
		if v != 0:
			compact.append(v)
	var merged = []
	var i = 0
	while i < compact.size():
		if i + 1 < compact.size() and compact[i] == compact[i + 1]:
			merged.append(compact[i] * 2)
			_score += compact[i] * 2
			i += 2
		else:
			merged.append(compact[i])
			i += 1
	while merged.size() < GRID:
		merged.append(0)
	return merged

func _slide_left() -> void:
	var old = _board.duplicate()
	for row in range(GRID):
		var line = []
		for col in range(GRID):
			line.append(_board[row * GRID + col])
		line = _merge_line(line)
		for col in range(GRID):
			_board[row * GRID + col] = line[col]
	_after_slide(old)

func _slide_right() -> void:
	var old = _board.duplicate()
	for row in range(GRID):
		var line = []
		for col in range(GRID):
			line.append(_board[row * GRID + col])
		line.reverse()
		line = _merge_line(line)
		line.reverse()
		for col in range(GRID):
			_board[row * GRID + col] = line[col]
	_after_slide(old)

func _slide_up() -> void:
	var old = _board.duplicate()
	for col in range(GRID):
		var line = []
		for row in range(GRID):
			line.append(_board[row * GRID + col])
		line = _merge_line(line)
		for row in range(GRID):
			_board[row * GRID + col] = line[row]
	_after_slide(old)

func _slide_down() -> void:
	var old = _board.duplicate()
	for col in range(GRID):
		var line = []
		for row in range(GRID):
			line.append(_board[row * GRID + col])
		line.reverse()
		line = _merge_line(line)
		line.reverse()
		for row in range(GRID):
			_board[row * GRID + col] = line[row]
	_after_slide(old)

func _after_slide(old: Array) -> void:
	if _board != old:
		_spawn_tile()
		_check_state()
	queue_redraw()

func _spawn_tile() -> void:
	var empty = []
	for i in range(GRID * GRID):
		if _board[i] == 0:
			empty.append(i)
	if empty.size() == 0:
		return
	_board[empty[randi() % empty.size()]] = 2 if randf() < 0.9 else 4

func _has_moves() -> bool:
	for i in range(GRID * GRID):
		if _board[i] == 0:
			return true
	for row in range(GRID):
		for col in range(GRID):
			var v = _board[row * GRID + col]
			if col + 1 < GRID and _board[row * GRID + col + 1] == v:
				return true
			if row + 1 < GRID and _board[(row + 1) * GRID + col] == v:
				return true
	return false

func _max_tile() -> int:
	var m = 0
	for v in _board:
		if v > m:
			m = v
	return m

func _check_state() -> void:
	if _max_tile() >= WIN_VAL and not _won_shown:
		_won_shown = true
		_game_active = false
		_result = 0
		_show_result()
		game_over.emit(0)
		return
	if not _has_moves():
		_game_active = false
		_result = 1
		_show_result()
		game_over.emit(1)

# ══════════════════════════════════════════════
#  结算覆盖层
# ══════════════════════════════════════════════

func _build_result_overlay() -> void:
	var d = GameTerminalStyles.create_result_overlay("[ 重新叠加 ]", start_game)
	_result_overlay = d.overlay
	_result_label = d.label
	_restart_btn = d.btn
	add_child(_result_overlay)

var _result_lines_win := ["矩阵峰值已达。", "数据叠加极限。", "2048...目标达成。"]
var _result_lines_lose := ["矩阵已饱和。", "操作空间耗尽。", "叠加中断。"]

func _show_result() -> void:
	if not is_instance_valid(_result_overlay):
		return
	var lines = _result_lines_win if _result == 0 else _result_lines_lose
	var text = lines[randi() % lines.size()]
	text += "\n得分: %d / 最大值: %d" % [_score, _max_tile()]
	var c = GameTerminalStyles.status_active() if _result == 0 else Color(0.9, 0.35, 0.3, 0.9)
	GameTerminalStyles.show_result_overlay(_result_overlay, _result_label, text, c)

# ══════════════════════════════════════════════
#  渲染
# ══════════════════════════════════════════════

func _draw() -> void:
	_calc_layout()
	var hue = EventBus.ui_hue
	var font = ThemeDB.fallback_font

	# 底板
	var total = _cell_size * GRID + _GAP * (GRID - 1)
	draw_rect(Rect2(_grid_origin - Vector2(3, 3), Vector2(total + 6, total + 6)), Color(0.04, 0.06, 0.10, 0.5))

	# 方块
	for i in range(GRID * GRID):
		var cr = _cell_rect(i)
		var val = _board[i]
		var bg = TILE_BG.get(val, TILE_BG[2048])
		draw_rect(cr, bg)
		if val > 0:
			var text = str(val)
			var fs = 24 if val < 100 else (20 if val < 1000 else 16)
			var tc = Color(0.85, 0.9, 0.95) if val >= 8 else Color(0.5, 0.6, 0.75)
			var ts = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			var pos = cr.get_center() - ts * 0.5 + Vector2(0, ts.y * 0.35)
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)

	# 外框
	draw_rect(Rect2(_grid_origin - Vector2(1, 1), Vector2(total + 2, total + 2)), Color.from_hsv(hue, 0.4, 0.6, 0.2), false, 1.0)

	# 操作提示
	if _game_active:
		var hint_y = _grid_origin.y + total + 18
		draw_string(font, Vector2(_grid_origin.x, hint_y), "方向键滑动", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.4, 0.5, 0.3))

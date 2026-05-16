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
	_result_overlay = PanelContainer.new()
	_result_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_overlay.visible = false
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.03, 0.06, 0.75)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(20)
	_result_overlay.add_theme_stylebox_override("panel", s)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_result_label)

	_restart_btn = Button.new()
	_restart_btn.text = "[ 重新叠加 ]"
	_restart_btn.add_theme_font_size_override("font_size", 13)
	_restart_btn.add_theme_stylebox_override("normal", GameTerminalStyles.small_btn_normal())
	_restart_btn.add_theme_stylebox_override("hover", GameTerminalStyles.small_btn_hover())
	_restart_btn.add_theme_stylebox_override("pressed", GameTerminalStyles.small_btn_hover())
	_restart_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_restart_btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.9))
	_restart_btn.add_theme_color_override("font_hover_color", GameTerminalStyles.accent())
	_restart_btn.pressed.connect(start_game)
	vbox.add_child(_restart_btn)

	add_child(_result_overlay)

var _result_lines_win := ["矩阵峰值已达。", "数据叠加极限。", "2048...目标达成。"]
var _result_lines_lose := ["矩阵已饱和。", "操作空间耗尽。", "叠加中断。"]

func _show_result() -> void:
	if not is_instance_valid(_result_overlay):
		return
	var lines = _result_lines_win if _result == 0 else _result_lines_lose
	var text = lines[randi() % lines.size()]
	text += "\n得分: %d / 最大值: %d" % [_score, _max_tile()]
	_result_label.text = text
	var c = GameTerminalStyles.status_active() if _result == 0 else Color(0.9, 0.35, 0.3, 0.9)
	_result_label.add_theme_color_override("font_color", c)
	_result_overlay.visible = true

# ══════════════════════════════════════════════
#  渲染
# ══════════════════════════════════════════════

func _draw() -> void:
	_calc_layout()
	var hue = EventBus.ui_hue
	var font = ThemeDB.fallback_font

	# 状态栏
	var status_y = _grid_origin.y - 8.0
	draw_string(font, Vector2(_grid_origin.x + 2, status_y), "SCORE: %d" % _score, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GameTerminalStyles.status_warning())
	var max_str = "MAX: %d" % _max_tile()
	var max_w = font.get_string_size(max_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, 12).x
	var grid_end_x = _grid_origin.x + _cell_size * GRID + _GAP * (GRID - 1)
	draw_string(font, Vector2(grid_end_x - max_w - 2, status_y), max_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.6, 0.7, 0.6))

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
		draw_string(font, Vector2(_grid_origin.x, hint_y), "方向键滑动", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.4, 0.5, 0.3))

# terminal_snake.gd — 终端原生贪吃蛇 (路径规划)
# _draw 自绘 + 键盘方向键
extends Control

signal game_started
signal game_over(result: int)  # 1=负 (蛇没有胜利条件)

const COLS := 15
const ROWS := 15
const TICK_BASE := 0.18
const TICK_MIN := 0.06

var _snake: Array[Vector2i] = []
var _dir: Vector2i = Vector2i(1, 0)
var _next_dir: Vector2i = Vector2i(1, 0)
var _food: Vector2i = Vector2i(-1, -1)
var _game_active: bool = false
var _result: int = -1
var _score: int = 0
var _tick_acc: float = 0.0
var _tick_interval: float = TICK_BASE
var _time: float = 0.0

var _grid_origin: Vector2 = Vector2.ZERO
var _cell_size: float = 0.0

var _result_overlay: PanelContainer
var _result_label: Label
var _restart_btn: Button

func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_result_overlay()
	start_game()

func _process(delta: float) -> void:
	_time += delta
	if _game_active:
		# 方向输入 (防 180 度转向)
		if Input.is_action_just_pressed("ui_up") and _dir != Vector2i(0, 1):
			_next_dir = Vector2i(0, -1)
		elif Input.is_action_just_pressed("ui_down") and _dir != Vector2i(0, -1):
			_next_dir = Vector2i(0, 1)
		elif Input.is_action_just_pressed("ui_left") and _dir != Vector2i(1, 0):
			_next_dir = Vector2i(-1, 0)
		elif Input.is_action_just_pressed("ui_right") and _dir != Vector2i(-1, 0):
			_next_dir = Vector2i(1, 0)
		# 移动节拍
		_tick_acc += delta
		if _tick_acc >= _tick_interval:
			_tick_acc -= _tick_interval
			_move()
	queue_redraw()

func start_game() -> void:
	_snake.clear()
	var cx = COLS / 2
	var cy = ROWS / 2
	_snake.append(Vector2i(cx, cy))
	_snake.append(Vector2i(cx - 1, cy))
	_snake.append(Vector2i(cx - 2, cy))
	_dir = Vector2i(1, 0)
	_next_dir = Vector2i(1, 0)
	_game_active = true
	_result = -1
	_score = 0
	_tick_acc = 0.0
	_tick_interval = TICK_BASE
	_time = 0.0
	_spawn_food()
	if is_instance_valid(_result_overlay):
		_result_overlay.visible = false
	game_started.emit()
	queue_redraw()

# ══════════════════════════════════════════════
#  核心逻辑
# ══════════════════════════════════════════════

func _move() -> void:
	_dir = _next_dir
	var head = _snake[0] + _dir
	# 撞墙
	if head.x < 0 or head.x >= COLS or head.y < 0 or head.y >= ROWS:
		_die()
		return
	# 撞自己 (尾巴即将移除所以跳过最后一节)
	for i in range(_snake.size() - 1):
		if _snake[i] == head:
			_die()
			return
	_snake.insert(0, head)
	if head == _food:
		_score += 1
		_tick_interval = maxf(TICK_MIN, TICK_BASE - _score * 0.008)
		_spawn_food()
	else:
		_snake.pop_back()

func _die() -> void:
	_game_active = false
	_result = 1
	_show_result()
	game_over.emit(1)

func _spawn_food() -> void:
	var empty: Array[Vector2i] = []
	for x in range(COLS):
		for y in range(ROWS):
			var pos = Vector2i(x, y)
			if pos not in _snake:
				empty.append(pos)
	if empty.size() > 0:
		_food = empty[randi() % empty.size()]

# ══════════════════════════════════════════════
#  布局
# ══════════════════════════════════════════════

func _calc_layout() -> void:
	var w = size.x
	var h = size.y
	var header_h = 28.0
	var avail_w = w - 12.0
	var avail_h = h - header_h - 6.0
	_cell_size = minf(avail_w / COLS, avail_h / ROWS)
	var grid_w = _cell_size * COLS
	var grid_h = _cell_size * ROWS
	_grid_origin = Vector2(
		(w - grid_w) * 0.5,
		header_h + (avail_h - grid_h) * 0.5
	)

# ══════════════════════════════════════════════
#  结算覆盖层
# ══════════════════════════════════════════════

func _build_result_overlay() -> void:
	var d = GameTerminalStyles.create_result_overlay("[ 重新规划 ]", start_game)
	_result_overlay = d.overlay
	_result_label = d.label
	_restart_btn = d.btn
	add_child(_result_overlay)

var _result_lines := ["路径中断。", "规划失败。碰撞已记录。", "...信号丢失。"]

func _show_result() -> void:
	if not is_instance_valid(_result_overlay):
		return
	var text = _result_lines[randi() % _result_lines.size()]
	text += "\n路径长度: %d / 速度: %d%%" % [_score + 3, int(TICK_BASE / _tick_interval * 100)]
	GameTerminalStyles.show_result_overlay(_result_overlay, _result_label, text, Color(0.9, 0.35, 0.3, 0.9))

# ══════════════════════════════════════════════
#  渲染
# ══════════════════════════════════════════════

func _draw() -> void:
	_calc_layout()
	var hue = EventBus.ui_hue
	var font = ThemeDB.fallback_font

	# 状态栏
	var status_y = _grid_origin.y - 6.0
	var len_c = GameTerminalStyles.status_active()
	draw_string(font, Vector2(_grid_origin.x + 2, status_y), "LEN: %d" % (_score + 3), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, len_c)
	var spd_str = "SPD: %d%%" % int(TICK_BASE / _tick_interval * 100)
	var spd_w = font.get_string_size(spd_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, 12).x
	var grid_end_x = _grid_origin.x + COLS * _cell_size
	draw_string(font, Vector2(grid_end_x - spd_w - 2, status_y), spd_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GameTerminalStyles.status_warning())

	# 网格背景
	var grid_size = Vector2(COLS * _cell_size, ROWS * _cell_size)
	draw_rect(Rect2(_grid_origin, grid_size), Color(0.03, 0.04, 0.07, 0.3))

	# 网格点
	var dot_c = Color(0.2, 0.3, 0.4, 0.12)
	for x in range(1, COLS):
		for y in range(1, ROWS):
			draw_circle(_grid_origin + Vector2(x * _cell_size, y * _cell_size), 0.7, dot_c, true, -1.0, true)

	# 食物 (脉冲)
	if _food.x >= 0:
		var fc = _grid_origin + Vector2((_food.x + 0.5) * _cell_size, (_food.y + 0.5) * _cell_size)
		var pulse = sin(_time * 5.0) * 0.2 + 0.8
		var fr = _cell_size * 0.35 * pulse
		draw_circle(fc, fr + 2, Color(0.9, 0.55, 0.3, 0.15), true, -1.0, true)
		draw_circle(fc, fr, Color(0.9, 0.55, 0.3, 0.85), true, -1.0, true)

	# 蛇身
	for i in range(_snake.size()):
		var pos = _snake[i]
		var cr = Rect2(
			_grid_origin + Vector2(pos.x * _cell_size + 1, pos.y * _cell_size + 1),
			Vector2(_cell_size - 2, _cell_size - 2)
		)
		if i == 0:
			# 蛇头: 亮色 + 泛光
			draw_rect(cr, Color.from_hsv(hue, 0.5, 0.9, 0.9))
			draw_rect(cr.grow(1), Color.from_hsv(hue, 0.4, 0.8, 0.2), false, 1.5, true)
		else:
			var alpha = lerpf(0.7, 0.3, float(i) / float(_snake.size()))
			draw_rect(cr, Color.from_hsv(hue, 0.4, 0.7, alpha))

	# 外框
	draw_rect(Rect2(_grid_origin, grid_size), Color.from_hsv(hue, 0.4, 0.6, 0.2), false, 1.0)

	# 操作提示
	if _game_active:
		var hint_y = _grid_origin.y + grid_size.y + 16
		draw_string(font, Vector2(_grid_origin.x, hint_y), "方向键控制", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.4, 0.5, 0.3))

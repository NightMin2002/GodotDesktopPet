# game.gd — 终端贪吃蛇 (路径规划)
# 圆形管道蛇身 + 平滑移动动画
extends TerminalGameBase

func get_game_id() -> String: return "snake"
func get_game_name() -> String: return "路径规划"
func get_game_desc() -> String: return "15x15 线性延伸"
func supports_auto_play() -> bool: return true

const COLS := 15
const ROWS := 15
const TICK_BASE := 0.18
const TICK_MIN  := 0.06

var _snake: Array[Vector2i] = []
var _prev_snake: Array[Vector2i] = []  # 上一 tick 前的快照
var _ate_last: bool = false            # 上一 tick 是否吃到食物
var _vanish_tail: Vector2i = Vector2i(-1, -1)  # 消失中的旧尾巴

var _dir: Vector2i = Vector2i(1, 0)
var _next_dir: Vector2i = Vector2i(1, 0)
var _food: Vector2i = Vector2i(-1, -1)
var _game_active: bool = false
var _waiting_input: bool = true
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

# ══════════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════════

func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_result_overlay()
	start_game()

func get_hud_data() -> Dictionary:
	var spd_pct = int(TICK_BASE / _tick_interval * 100)
	var spd_c = GameTerminalStyles.status_warning() if spd_pct > 100 else GameTerminalStyles.dim()
	return {
		"len": {"label": "LEN", "value": str(_score + 3), "color": GameTerminalStyles.status_active()},
		"spd": {"label": "SPD", "value": "%d%%" % spd_pct, "color": spd_c},
	}

func get_best_score() -> int: return _score

func auto_play_step() -> void:
	if not _game_active: return
	if _waiting_input: _waiting_input = false
	var head = _snake[0]
	var best_dir = _dir; var best_dist = 9999
	for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
		if d == -_dir: continue
		var np = head + d
		if np.x < 0 or np.x >= COLS or np.y < 0 or np.y >= ROWS: continue
		var safe = true
		for i in range(_snake.size() - 1):
			if _snake[i] == np: safe = false; break
		if not safe: continue
		var dist = absi(np.x - _food.x) + absi(np.y - _food.y)
		if dist < best_dist: best_dist = dist; best_dir = d
	_next_dir = best_dir

func _process(delta: float) -> void:
	_time += delta
	if _game_active:
		var dir_pressed := false
		if Input.is_action_just_pressed("ui_up") and _dir != Vector2i(0,1):
			_next_dir = Vector2i(0,-1); dir_pressed = true
		elif Input.is_action_just_pressed("ui_down") and _dir != Vector2i(0,-1):
			_next_dir = Vector2i(0,1); dir_pressed = true
		elif Input.is_action_just_pressed("ui_left") and _dir != Vector2i(1,0):
			_next_dir = Vector2i(-1,0); dir_pressed = true
		elif Input.is_action_just_pressed("ui_right") and _dir != Vector2i(-1,0):
			_next_dir = Vector2i(1,0); dir_pressed = true
		if _waiting_input:
			if dir_pressed: _waiting_input = false
			else: queue_redraw(); return
		_tick_acc += delta
		if _tick_acc >= _tick_interval:
			_tick_acc -= _tick_interval
			_move()
	queue_redraw()

func start_game() -> void:
	_snake.clear(); _prev_snake.clear()
	var cx = COLS / 2; var cy = ROWS / 2
	_snake.append(Vector2i(cx, cy))
	_snake.append(Vector2i(cx-1, cy))
	_snake.append(Vector2i(cx-2, cy))
	_prev_snake = _snake.duplicate()
	_dir = Vector2i(1,0); _next_dir = Vector2i(1,0)
	_game_active = true; _waiting_input = true; _result = -1
	_score = 0; _tick_acc = 0.0; _tick_interval = TICK_BASE
	_time = 0.0; _ate_last = false; _vanish_tail = Vector2i(-1,-1)
	_spawn_food()
	if is_instance_valid(_result_overlay): _result_overlay.visible = false
	game_started.emit(); queue_redraw()

# ══════════════════════════════════════════════
#  核心逻辑
# ══════════════════════════════════════════════

func _move() -> void:
	_prev_snake = _snake.duplicate()
	_dir = _next_dir
	var head = _snake[0] + _dir
	if head.x < 0 or head.x >= COLS or head.y < 0 or head.y >= ROWS:
		_die(); return
	for i in range(_snake.size() - 1):
		if _snake[i] == head: _die(); return
	_snake.insert(0, head)
	if head == _food:
		_ate_last = true
		_vanish_tail = Vector2i(-1,-1)
		_score += 1
		_tick_interval = maxf(TICK_MIN, TICK_BASE - _score * 0.008)
		_spawn_food()
	else:
		_ate_last = false
		_vanish_tail = _prev_snake.back()  # 将要消失的尾巴
		_snake.pop_back()

func _die() -> void:
	_game_active = false; _result = 1; _show_result(); game_over.emit(1)

func _spawn_food() -> void:
	var empty: Array[Vector2i] = []
	for x in range(COLS):
		for y in range(ROWS):
			var pos = Vector2i(x, y)
			if pos not in _snake: empty.append(pos)
	if empty.size() > 0: _food = empty[randi() % empty.size()]

# ══════════════════════════════════════════════
#  布局
# ══════════════════════════════════════════════

func _calc_layout() -> void:
	var header_h = 36.0
	var avail_w = size.x - 12.0
	var avail_h = size.y - header_h - 6.0
	_cell_size = minf(avail_w / COLS, avail_h / ROWS)
	var grid_w = _cell_size * COLS; var grid_h = _cell_size * ROWS
	_grid_origin = Vector2((size.x - grid_w) * 0.5, header_h + (avail_h - grid_h) * 0.5)

func _cell_center(cell: Vector2i) -> Vector2:
	return _grid_origin + Vector2((cell.x + 0.5) * _cell_size, (cell.y + 0.5) * _cell_size)

# ══════════════════════════════════════════════
#  结算
# ══════════════════════════════════════════════

func _build_result_overlay() -> void:
	var d = GameTerminalStyles.create_result_overlay("[ 重新规划 ]", start_game)
	_result_overlay = d.overlay; _result_label = d.label; _restart_btn = d.btn
	add_child(_result_overlay)

func _show_result() -> void:
	if not is_instance_valid(_result_overlay): return
	var lines := ["路径中断。", "规划失败。碰撞已记录。", "...信号丢失。"]
	var text = lines[randi() % lines.size()]
	text += "\n路径长度: %d / 速度: %d%%" % [_score + 3, int(TICK_BASE / _tick_interval * 100)]
	GameTerminalStyles.show_result_overlay(_result_overlay, _result_label, text, Color(0.9, 0.35, 0.3, 0.9))

# ══════════════════════════════════════════════
#  渲染
# ══════════════════════════════════════════════

func _draw() -> void:
	_calc_layout()
	var hue  = EventBus.ui_hue
	var font = ThemeDB.fallback_font
	var grid_w = _cell_size * COLS
	var grid_h = _cell_size * ROWS
	var grid_size = Vector2(grid_w, grid_h)

	# ── HUD 双框分组 ──
	if font:
		var hud_h = 26.0
		var hud_y = _grid_origin.y - hud_h - 5.0
		var box_w = grid_w * 0.38
		var lbl_c = Color.from_hsv(hue, 0.3, 0.65, 0.5)

		var lx = _grid_origin.x
		_draw_hud_box(lx, hud_y, box_w, hud_h, hue)
		draw_string(font, Vector2(lx+6, hud_y+10), "LEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lbl_c)
		draw_string(font, Vector2(lx+6, hud_y+22), str(_score+3), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GameTerminalStyles.status_active())

		var rx = lx + box_w + (grid_w - box_w * 2.0)
		_draw_hud_box(rx, hud_y, box_w, hud_h, hue)
		var spd_pct = int(TICK_BASE / _tick_interval * 100)
		var spd_c = GameTerminalStyles.status_warning() if spd_pct > 100 else GameTerminalStyles.dim()
		draw_string(font, Vector2(rx+6, hud_y+10), "SPD", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lbl_c)
		draw_string(font, Vector2(rx+6, hud_y+22), "%d%%" % spd_pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, spd_c)

	# ── 网格背景 ──
	draw_rect(Rect2(_grid_origin, grid_size), Color(0.03, 0.04, 0.07, 0.35))

	# 网格点阵
	var dot_c = Color(0.2, 0.3, 0.4, 0.10)
	for x in range(1, COLS):
		for y in range(1, ROWS):
			draw_circle(_grid_origin + Vector2(x * _cell_size, y * _cell_size), 0.6, dot_c, true, -1.0, true)

	# ── 食物 (脉冲圆 + 外圈泛光) ──
	if _food.x >= 0:
		var fc = _cell_center(_food)
		var pulse = sin(_time * 5.0) * 0.18 + 0.82
		var fr = _cell_size * 0.32 * pulse
		draw_circle(fc, fr * 1.8, Color(0.9, 0.55, 0.3, 0.10), true, -1.0, true)
		draw_circle(fc, fr, Color(0.9, 0.55, 0.3, 0.88), true, -1.0, true)
		# 高光点
		draw_circle(fc + Vector2(-fr*0.3, -fr*0.3), fr * 0.28, Color(1.0, 0.85, 0.65, 0.55), true, -1.0, true)

	# ── 蛇身: 方形数据流管道 + 平滑插值 ──
	var t = clampf(_tick_acc / max(_tick_interval, 0.001), 0.0, 1.0)
	var n = _snake.size()
	var pn = _prev_snake.size()

	# 计算每节蛇的视觉中心 (插值)
	var vis: Array[Vector2] = []
	for i in range(n):
		var cur = _cell_center(_snake[i])
		if i < pn:
			vis.append(_cell_center(_prev_snake[i]).lerp(cur, t))
		else:
			vis.append(cur)

	# 消失中的旧尾巴
	var tail_vis := Vector2(-1, -1)
	var tail_alpha := 0.0
	if not _ate_last and _vanish_tail.x >= 0:
		var tv_from = _cell_center(_vanish_tail)
		var tv_to   = vis.back() if vis.size() > 0 else tv_from
		tail_vis   = tv_from.lerp(tv_to, t)
		tail_alpha = 1.0 - t

	# 方块尺寸: 无间隙贴合
	var seg = _cell_size
	var head_color = Color.from_hsv(hue, 0.55, 0.95, 0.92)
	var tail_color = Color.from_hsv(hue, 0.30, 0.45, 0.30)

	# 消失尾巴 (淡出，方块缩小)
	if tail_alpha > 0.01 and tail_vis.x >= 0:
		var tc = tail_color
		tc.a = tail_color.a * tail_alpha
		var s = seg * tail_alpha
		draw_rect(Rect2(tail_vis - Vector2(s, s) * 0.5, Vector2(s, s)), tc)

	# 从尾到头画方块 (头在最顶层)
	for i in range(n - 1, -1, -1):
		var frac = float(i) / float(max(n - 1, 1))  # 0=head, 1=tail
		var c = head_color.lerp(tail_color, frac)
		# 无间隙方块 (整格填充)
		var half = seg * 0.5
		draw_rect(Rect2(vis[i] - Vector2(half, half), Vector2(seg, seg)), c)

	# 转角填充: 相邻两节间补一个方块，消除缝隙
	for i in range(n - 1):
		var frac = (float(i) + 0.5) / float(max(n - 1, 1))
		var c = head_color.lerp(tail_color, frac)
		var mid = (vis[i] + vis[i + 1]) * 0.5
		var half = seg * 0.5
		draw_rect(Rect2(mid - Vector2(half, half), Vector2(seg, seg)), c)

	# 蛇头: 轻微高亮边框 (区别于身体)
	if vis.size() > 0:
		var half = seg * 0.5
		draw_rect(Rect2(vis[0] - Vector2(half, half), Vector2(seg, seg)),
			Color.from_hsv(hue, 0.4, 1.0, 0.20), false, 1.5)

	# ── 外框 ──
	draw_rect(Rect2(_grid_origin, grid_size), Color.from_hsv(hue, 0.4, 0.6, 0.2), false, 1.0)

	# ── 操作提示 ──
	if _game_active and font:
		var hint_y = _grid_origin.y + grid_h + 14
		var hint_text = "按方向键开始" if _waiting_input else "方向键控制"
		var hint_a = (sin(_time * 3.0) * 0.15 + 0.45) if _waiting_input else 0.25
		draw_string(font, Vector2(_grid_origin.x, hint_y), hint_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.4, 0.5, hint_a))

func _draw_hud_box(x: float, y: float, w: float, h: float, hue: float) -> void:
	var r = Rect2(x, y, w, h)
	draw_rect(r, Color(0.04, 0.06, 0.12, 0.7))
	draw_rect(r, Color.from_hsv(hue, 0.45, 0.55, 0.25), false, 1.0)
	draw_rect(r.grow(-2.0), Color.from_hsv(hue, 0.25, 0.35, 0.10), false, 1.0)

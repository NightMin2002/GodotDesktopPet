# game.gd — 终端俄罗斯方块 (结构堆叠)
# _draw 自绘 10x20 场地 + 侧栏 (NEXT/HOLD) + SRS 旋转 + 7-bag + 锁定延迟 + 消行动画
extends TerminalGameBase

func get_game_id() -> String: return "tetris"
func get_game_name() -> String: return "结构堆叠"
func get_game_desc() -> String: return "10x20 方块序列"
func supports_auto_play() -> bool: return true

# ══════════════════════════════════════════════
#  常量
# ══════════════════════════════════════════════

const COLS := 10
const ROWS := 20

# ── 方块定义 (SRS 标准) ──
const PIECES := {
	"I": [
		[Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(3,1)],
		[Vector2i(2,0), Vector2i(2,1), Vector2i(2,2), Vector2i(2,3)],
		[Vector2i(0,2), Vector2i(1,2), Vector2i(2,2), Vector2i(3,2)],
		[Vector2i(1,0), Vector2i(1,1), Vector2i(1,2), Vector2i(1,3)],
	],
	"O": [
		[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
		[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
		[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
		[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
	],
	"T": [
		[Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)],
		[Vector2i(1,0), Vector2i(1,1), Vector2i(2,1), Vector2i(1,2)],
		[Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(1,2)],
		[Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,2)],
	],
	"S": [
		[Vector2i(1,0), Vector2i(2,0), Vector2i(0,1), Vector2i(1,1)],
		[Vector2i(1,0), Vector2i(1,1), Vector2i(2,1), Vector2i(2,2)],
		[Vector2i(1,1), Vector2i(2,1), Vector2i(0,2), Vector2i(1,2)],
		[Vector2i(0,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,2)],
	],
	"Z": [
		[Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(2,1)],
		[Vector2i(2,0), Vector2i(1,1), Vector2i(2,1), Vector2i(1,2)],
		[Vector2i(0,1), Vector2i(1,1), Vector2i(1,2), Vector2i(2,2)],
		[Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(0,2)],
	],
	"J": [
		[Vector2i(0,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)],
		[Vector2i(1,0), Vector2i(2,0), Vector2i(1,1), Vector2i(1,2)],
		[Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(2,2)],
		[Vector2i(1,0), Vector2i(1,1), Vector2i(0,2), Vector2i(1,2)],
	],
	"L": [
		[Vector2i(2,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)],
		[Vector2i(1,0), Vector2i(1,1), Vector2i(1,2), Vector2i(2,2)],
		[Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(0,2)],
		[Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(1,2)],
	],
}

const PIECE_TYPES := ["I", "O", "T", "S", "Z", "J", "L"]

# SRS 踢墙数据
const WALL_KICK_NORMAL := {
	"0>1": [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,-1), Vector2i(0,2), Vector2i(-1,2)],
	"1>0": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(0,-2), Vector2i(1,-2)],
	"1>2": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(0,-2), Vector2i(1,-2)],
	"2>1": [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,-1), Vector2i(0,2), Vector2i(-1,2)],
	"2>3": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,-1), Vector2i(0,2), Vector2i(1,2)],
	"3>2": [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,1), Vector2i(0,-2), Vector2i(-1,-2)],
	"3>0": [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,-1), Vector2i(0,2), Vector2i(-1,2)],
	"0>3": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(0,-2), Vector2i(1,-2)],
}
const WALL_KICK_I := {
	"0>1": [Vector2i(0,0), Vector2i(-2,0), Vector2i(1,0), Vector2i(-2,1), Vector2i(1,-2)],
	"1>0": [Vector2i(0,0), Vector2i(2,0), Vector2i(-1,0), Vector2i(2,-1), Vector2i(-1,2)],
	"1>2": [Vector2i(0,0), Vector2i(-1,0), Vector2i(2,0), Vector2i(-1,-2), Vector2i(2,1)],
	"2>1": [Vector2i(0,0), Vector2i(1,0), Vector2i(-2,0), Vector2i(1,2), Vector2i(-2,-1)],
	"2>3": [Vector2i(0,0), Vector2i(2,0), Vector2i(-1,0), Vector2i(2,-1), Vector2i(-1,2)],
	"3>2": [Vector2i(0,0), Vector2i(-2,0), Vector2i(1,0), Vector2i(-2,1), Vector2i(1,-2)],
	"3>0": [Vector2i(0,0), Vector2i(1,0), Vector2i(-2,0), Vector2i(1,2), Vector2i(-2,-1)],
	"0>3": [Vector2i(0,0), Vector2i(-1,0), Vector2i(2,0), Vector2i(-1,-2), Vector2i(2,1)],
}

# 方块颜色偏移 (基于 ui_hue)
const PIECE_HUE_OFFSETS := {
	"I": 0.00, "O": 0.08, "T": 0.16, "S": 0.24,
	"Z": 0.32, "J": 0.40, "L": 0.48,
}

# 速度/锁定
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15
const DAS_DELAY := 0.170
const DAS_REPEAT := 0.050
const CLEAR_DURATION := 0.25

# ══════════════════════════════════════════════
#  游戏状态
# ══════════════════════════════════════════════

var _field: Array = []
var _current_type: String = ""
var _current_rot: int = 0
var _current_pos: Vector2i = Vector2i.ZERO
var _hold_type: String = ""
var _hold_used: bool = false
var _bag: Array[String] = []
var _next_type: String = ""

var _score: int = 0
var _lines_cleared: int = 0
var _level: int = 1
var _drop_interval: float = 1.0
var _drop_timer: float = 0.0
var _lock_timer: float = -1.0
var _lock_resets: int = 0

var _das_dir: int = 0
var _das_timer: float = 0.0
var _das_charged: bool = false
var _soft_drop: bool = false

var _clearing_rows: Array[int] = []
var _clear_timer: float = -1.0

var _game_active: bool = false
var _result: int = -1
var _time: float = 0.0

# ── 布局 ──
var _cell_size: float = 0.0
var _field_origin: Vector2 = Vector2.ZERO
var _sidebar_x: float = 0.0
var _left_sidebar_x: float = 0.0

# ── 结算覆盖层 ──
var _result_overlay: PanelContainer
var _result_label: Label
var _restart_btn: Button

# ══════════════════════════════════════════════
#  终端接口
# ══════════════════════════════════════════════

func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	_build_result_overlay()
	start_game()
	grab_focus()

## HUD 协议: 分数 + 等级 + 消行
func get_hud_data() -> Dictionary:
	var lv_c = GameTerminalStyles.status_warning() if _level >= 10 else GameTerminalStyles.status_active()
	return {
		"scr": { "label": "SCR", "value": str(_score), "color": GameTerminalStyles.bright() },
		"lv":  { "label": "LV",  "value": str(_level), "color": lv_c },
		"ln":  { "label": "LN",  "value": str(_lines_cleared), "color": GameTerminalStyles.dim() },
	}

## 最佳分数
func get_best_score() -> int:
	return _score

## 自玩 AI: 每步操作 — 评估所有可能放置, 选最优硬降
func auto_play_step() -> void:
	if not _game_active:
		return
	if _clear_timer >= 0.0:
		return
	# AI 决策: 寻找最优放置
	var best = _ai_find_best_placement()
	if best.is_empty():
		_hard_drop()
		return
	var target_rot: int = best["rot"]
	var target_x: int = best["x"]
	# 随机小失误 (防止 AI 太完美)
	if randf() < 0.03:
		target_x = clampi(target_x + (randi() % 3 - 1), 0, COLS - 1)
	# 执行: 先旋转
	var rot_diff = (target_rot - _current_rot + 4) % 4
	for _i in range(rot_diff):
		if not _try_rotate(1):
			break
	# 再移动
	var dx = target_x - _current_pos.x
	if dx < 0:
		for _i in range(-dx):
			if not _try_move(-1):
				break
	elif dx > 0:
		for _i in range(dx):
			if not _try_move(1):
				break
	# 硬降
	_hard_drop()

# ══════════════════════════════════════════════
#  帧循环
# ══════════════════════════════════════════════

func _process(delta: float) -> void:
	_time += delta
	if _game_active:
		_handle_input()
		_update_logic(delta)
	queue_redraw()

func _handle_input() -> void:
	if _clear_timer >= 0.0:
		return
	# 旋转
	if Input.is_action_just_pressed("ui_up"):
		_try_rotate(1)
	# 硬降
	if Input.is_action_just_pressed("ui_accept"):  # 空格
		_hard_drop()
		return
	# Hold (C 键通过 _unhandled_key_input 处理)
	# 左右
	if Input.is_action_just_pressed("ui_left") and _das_dir != -1:
		_try_move(-1)
		_das_dir = -1
		_das_timer = 0.0
		_das_charged = false
	elif Input.is_action_just_pressed("ui_right") and _das_dir != 1:
		_try_move(1)
		_das_dir = 1
		_das_timer = 0.0
		_das_charged = false
	# 释放方向
	if not Input.is_action_pressed("ui_left") and _das_dir == -1:
		_das_dir = 0
	if not Input.is_action_pressed("ui_right") and _das_dir == 1:
		_das_dir = 0
	# 软降
	_soft_drop = Input.is_action_pressed("ui_down")

func _unhandled_key_input(event: InputEvent) -> void:
	if not _game_active or _clear_timer >= 0.0:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Hold: Shift / C
	var kc = event.keycode
	var pkc = event.physical_keycode
	if kc == KEY_SHIFT or pkc == KEY_C:
		_do_hold()

func _update_logic(delta: float) -> void:
	# 消行动画
	if _clear_timer >= 0.0:
		_clear_timer += delta
		if _clear_timer >= CLEAR_DURATION:
			_do_clear_rows()
		return

	# DAS
	if _das_dir != 0:
		_das_timer += delta
		if not _das_charged:
			if _das_timer >= DAS_DELAY:
				_das_charged = true
				_das_timer = 0.0
				_try_move(_das_dir)
		else:
			if _das_timer >= DAS_REPEAT:
				_das_timer -= DAS_REPEAT
				_try_move(_das_dir)

	# 下落
	var effective_interval = _drop_interval
	if _soft_drop:
		effective_interval = minf(_drop_interval, 0.05)
	_drop_timer += delta
	if _drop_timer >= effective_interval:
		_drop_timer = 0.0
		if not _try_drop():
			if _lock_timer < 0.0:
				_lock_timer = 0.0
		else:
			_lock_timer = -1.0
			if _soft_drop:
				_score += 1

	# 锁定延迟
	if _lock_timer >= 0.0:
		if _is_valid_position(_current_type, _current_rot, _current_pos + Vector2i(0, 1)):
			_lock_timer = -1.0
		else:
			_lock_timer += delta
			if _lock_timer >= LOCK_DELAY:
				_lock_piece()

# ══════════════════════════════════════════════
#  游戏生命周期
# ══════════════════════════════════════════════

func start_game() -> void:
	_field.clear()
	for _y in range(ROWS):
		var row: Array[String] = []
		row.resize(COLS)
		row.fill("")
		_field.append(row)
	_score = 0
	_lines_cleared = 0
	_level = 1
	_drop_interval = 1.0
	_drop_timer = 0.0
	_lock_timer = -1.0
	_lock_resets = 0
	_game_active = true
	_result = -1
	_hold_type = ""
	_hold_used = false
	_bag.clear()
	_clearing_rows.clear()
	_clear_timer = -1.0
	_das_dir = 0
	_das_timer = 0.0
	_das_charged = false
	_soft_drop = false
	_time = 0.0
	_next_type = _bag_next()
	_spawn_piece()
	if is_instance_valid(_result_overlay):
		_result_overlay.visible = false
	game_started.emit()
	grab_focus()
	queue_redraw()

# ══════════════════════════════════════════════
#  核心逻辑
# ══════════════════════════════════════════════

func _bag_next() -> String:
	if _bag.is_empty():
		for p in PIECE_TYPES:
			_bag.append(p)
		_bag.shuffle()
	return _bag.pop_back()

func _spawn_piece() -> void:
	_current_type = _next_type
	_next_type = _bag_next()
	_current_rot = 0
	_current_pos = Vector2i(3, 0)
	if _current_type == "I":
		_current_pos = Vector2i(3, -1)
	elif _current_type == "O":
		_current_pos = Vector2i(4, 0)
	_hold_used = false
	_lock_timer = -1.0
	_lock_resets = 0
	if not _is_valid_position(_current_type, _current_rot, _current_pos):
		_die()

func _do_hold() -> void:
	if _hold_used:
		return
	_hold_used = true
	if _hold_type == "":
		_hold_type = _current_type
		_spawn_piece()
	else:
		var prev = _hold_type
		_hold_type = _current_type
		_current_type = prev
		_current_rot = 0
		_current_pos = Vector2i(3, 0)
		if _current_type == "I":
			_current_pos = Vector2i(3, -1)
		elif _current_type == "O":
			_current_pos = Vector2i(4, 0)
		_lock_timer = -1.0
		_lock_resets = 0

func _get_cells(ptype: String, rot: int, pos: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in PIECES[ptype][rot]:
		cells.append(pos + offset)
	return cells

func _is_valid_position(ptype: String, rot: int, pos: Vector2i) -> bool:
	for cell in _get_cells(ptype, rot, pos):
		if cell.x < 0 or cell.x >= COLS:
			return false
		if cell.y >= ROWS:
			return false
		if cell.y >= 0 and _field[cell.y][cell.x] != "":
			return false
	return true

func _try_move(dx: int) -> bool:
	var new_pos = _current_pos + Vector2i(dx, 0)
	if _is_valid_position(_current_type, _current_rot, new_pos):
		_current_pos = new_pos
		_reset_lock_if_grounded()
		return true
	return false

func _try_drop() -> bool:
	var new_pos = _current_pos + Vector2i(0, 1)
	if _is_valid_position(_current_type, _current_rot, new_pos):
		_current_pos = new_pos
		return true
	return false

func _try_rotate(direction: int) -> bool:
	if _current_type == "O":
		return false
	var new_rot = (_current_rot + direction + 4) % 4
	var kick_key = "%d>%d" % [_current_rot, new_rot]
	var kick_table = WALL_KICK_I if _current_type == "I" else WALL_KICK_NORMAL
	if not kick_table.has(kick_key):
		return false
	for kick in kick_table[kick_key]:
		var new_pos = _current_pos + kick
		if _is_valid_position(_current_type, new_rot, new_pos):
			_current_pos = new_pos
			_current_rot = new_rot
			_reset_lock_if_grounded()
			return true
	return false

func _hard_drop() -> void:
	var dist := 0
	while _try_drop():
		dist += 1
	_score += dist * 2
	_lock_piece()

func _get_ghost_pos() -> Vector2i:
	var ghost = _current_pos
	while _is_valid_position(_current_type, _current_rot, ghost + Vector2i(0, 1)):
		ghost += Vector2i(0, 1)
	return ghost

func _lock_piece() -> void:
	for cell in _get_cells(_current_type, _current_rot, _current_pos):
		if cell.y >= 0 and cell.y < ROWS and cell.x >= 0 and cell.x < COLS:
			_field[cell.y][cell.x] = _current_type
	# 检查消行
	var cleared: Array[int] = []
	for y in range(ROWS):
		var full := true
		for x in range(COLS):
			if _field[y][x] == "":
				full = false
				break
		if full:
			cleared.append(y)
	if cleared.size() > 0:
		_clearing_rows = cleared
		_clear_timer = 0.0
		var pts := [0, 100, 300, 500, 800]
		_score += pts[mini(cleared.size(), 4)]
	else:
		_spawn_piece()

func _do_clear_rows() -> void:
	_clearing_rows.sort()
	_clearing_rows.reverse()
	for row_idx in _clearing_rows:
		_field.remove_at(row_idx)
	for _i in range(_clearing_rows.size()):
		var empty_row: Array[String] = []
		empty_row.resize(COLS)
		empty_row.fill("")
		_field.insert(0, empty_row)
	_lines_cleared += _clearing_rows.size()
	var new_level = mini(_lines_cleared / 10 + 1, 15)
	if new_level > _level:
		_level = new_level
		_drop_interval = maxf(0.1, 1.0 - (_level - 1) * 0.06)
	_clearing_rows.clear()
	_clear_timer = -1.0
	_spawn_piece()

func _reset_lock_if_grounded() -> void:
	if not _is_valid_position(_current_type, _current_rot, _current_pos + Vector2i(0, 1)):
		if _lock_resets < MAX_LOCK_RESETS:
			_lock_timer = 0.0
			_lock_resets += 1

func _die() -> void:
	_game_active = false
	_result = 1
	_show_result()
	game_over.emit(1)

# ══════════════════════════════════════════════
#  AI 自玩
# ══════════════════════════════════════════════

func _ai_find_best_placement() -> Dictionary:
	var best_score := -99999.0
	var best := {}
	for rot in range(4):
		var cells = PIECES[_current_type][rot]
		var min_x := 999
		var max_x := -999
		for c in cells:
			min_x = mini(min_x, c.x)
			max_x = maxi(max_x, c.x)
		for col in range(-min_x, COLS - max_x):
			var pos = Vector2i(col, _current_pos.y)
			if not _is_valid_position(_current_type, rot, pos):
				continue
			while _is_valid_position(_current_type, rot, pos + Vector2i(0, 1)):
				pos += Vector2i(0, 1)
			var temp_field = _copy_field()
			var piece_cells = _get_cells(_current_type, rot, pos)
			for cell in piece_cells:
				if cell.y >= 0 and cell.y < ROWS and cell.x >= 0 and cell.x < COLS:
					temp_field[cell.y][cell.x] = _current_type
			var eval_score = _evaluate_field(temp_field)
			if eval_score > best_score:
				best_score = eval_score
				best = {"rot": rot, "x": col}
	return best

func _copy_field() -> Array:
	var copy: Array = []
	for row in _field:
		copy.append(row.duplicate())
	return copy

func _evaluate_field(field: Array) -> float:
	var aggregate_height := 0
	var complete_lines := 0
	var holes := 0
	var bumpiness := 0
	var heights: Array[int] = []
	heights.resize(COLS)
	for x in range(COLS):
		var h := 0
		for y in range(ROWS):
			if field[y][x] != "":
				h = ROWS - y
				break
		heights[x] = h
		aggregate_height += h
	for y in range(ROWS):
		var full := true
		for x in range(COLS):
			if field[y][x] == "":
				full = false
				break
		if full:
			complete_lines += 1
	for x in range(COLS):
		var found_block := false
		for y in range(ROWS):
			if field[y][x] != "":
				found_block = true
			elif found_block:
				holes += 1
	for x in range(COLS - 1):
		bumpiness += absi(heights[x] - heights[x + 1])
	return -0.51 * aggregate_height + 0.76 * complete_lines * 10.0 - 0.36 * holes - 0.18 * bumpiness

# ══════════════════════════════════════════════
#  布局计算
# ══════════════════════════════════════════════

func _calc_layout() -> void:
	var w = size.x
	var h = size.y
	var header_h = 6.0
	var side_ratio = 0.18  # 每侧侧栏占总宽比
	var field_area_w = w * (1.0 - side_ratio * 2)
	var field_area_h = h - header_h - 6.0
	# 场地按 10:20 比例缩放
	_cell_size = minf(field_area_w / COLS, field_area_h / ROWS)
	var field_w = _cell_size * COLS
	var field_h = _cell_size * ROWS
	var side_w = w * side_ratio
	# 场地居中 (左右对称侧栏)
	_field_origin = Vector2(
		side_w + (field_area_w - field_w) * 0.5,
		header_h + (field_area_h - field_h) * 0.5
	)
	_left_sidebar_x = side_w * 0.12
	_sidebar_x = _field_origin.x + field_w + _cell_size * 0.6

# ══════════════════════════════════════════════
#  结算覆盖层
# ══════════════════════════════════════════════

func _build_result_overlay() -> void:
	var d = GameTerminalStyles.create_result_overlay("[ 重新堆叠 ]", start_game)
	_result_overlay = d.overlay
	_result_label = d.label
	_restart_btn = d.btn
	add_child(_result_overlay)

var _result_lines := [
	"矩阵溢出。堆叠失败。",
	"...空间耗尽。结构崩塌。",
	"方块填满。操作极限到此为止。",
	"溢出了。...已记录。",
]

func _show_result() -> void:
	if not is_instance_valid(_result_overlay):
		return
	var text = _result_lines[randi() % _result_lines.size()]
	text += "\n消除: %d 行 / 得分: %d / Lv.%d" % [_lines_cleared, _score, _level]
	GameTerminalStyles.show_result_overlay(_result_overlay, _result_label, text, Color(0.9, 0.35, 0.3, 0.9))

# ══════════════════════════════════════════════
#  渲染
# ══════════════════════════════════════════════

func _draw() -> void:
	_calc_layout()
	var hue = EventBus.ui_hue
	var font = ThemeDB.fallback_font
	var field_w = _cell_size * COLS
	var field_h = _cell_size * ROWS

	# ── 场地背景 ──
	draw_rect(Rect2(_field_origin, Vector2(field_w, field_h)), Color.from_hsv(hue, 0.35, 0.06, 0.95))

	# 扫描线
	var scan_y = fmod(_time * 30.0, field_h + 30.0) - 15.0
	draw_rect(Rect2(_field_origin.x, _field_origin.y + scan_y, field_w, 10.0), Color.from_hsv(hue, 0.3, 0.9, 0.025))
	draw_rect(Rect2(_field_origin.x, _field_origin.y + scan_y + 4.0, field_w, 1.0), Color.from_hsv(hue, 0.5, 1.0, 0.05))

	# ── 网格刻度 (+) ──
	var grid_color = Color.from_hsv(hue, 0.2, 0.5, 0.10)
	for x in range(COLS + 1):
		for y in range(ROWS + 1):
			var px = _field_origin.x + x * _cell_size
			var py = _field_origin.y + y * _cell_size
			draw_line(Vector2(px - 1.5, py), Vector2(px + 1.5, py), grid_color, 1.0, true)
			draw_line(Vector2(px, py - 1.5), Vector2(px, py + 1.5), grid_color, 1.0, true)

	# ── 已固定方块 ──
	for y in range(ROWS):
		var in_clear = _clearing_rows.has(y)
		for x in range(COLS):
			if _field[y][x] != "":
				var cell_color = _get_piece_color(_field[y][x], false)
				var cx = _field_origin.x + x * _cell_size
				var cy = _field_origin.y + y * _cell_size
				if in_clear:
					var t = clampf(_clear_timer / CLEAR_DURATION, 0.0, 1.0)
					cell_color = cell_color.lerp(Color.WHITE, (1.0 - t) * 0.6)
					var shrink = t * _cell_size * 0.5
					var rect = Rect2(cx + shrink, cy + shrink, _cell_size - shrink * 2, _cell_size - shrink * 2)
					if rect.size.x > 0 and rect.size.y > 0:
						draw_rect(rect, cell_color)
						draw_rect(rect, cell_color.darkened(0.4), false, 1.0)
				else:
					var rect = Rect2(cx, cy, _cell_size, _cell_size)
					draw_rect(rect, cell_color)
					draw_rect(rect, cell_color.darkened(0.4), false, 1.0)

	# ── Ghost piece ──
	if _current_type != "" and _game_active and _clear_timer < 0.0:
		var ghost_pos = _get_ghost_pos()
		if ghost_pos != _current_pos:
			var ghost_color = _get_piece_color(_current_type, true)
			ghost_color.a = 0.15
			for cell in _get_cells(_current_type, _current_rot, ghost_pos):
				if cell.y >= 0:
					var rect = Rect2(
						_field_origin.x + cell.x * _cell_size,
						_field_origin.y + cell.y * _cell_size,
						_cell_size, _cell_size
					)
					draw_rect(rect, ghost_color)
					draw_rect(rect, ghost_color.lightened(0.3), false, 1.0)

	# ── 当前活动方块 ──
	if _current_type != "" and _game_active and _clear_timer < 0.0:
		var active_color = _get_piece_color(_current_type, true)
		for cell in _get_cells(_current_type, _current_rot, _current_pos):
			if cell.y >= 0:
				var rect = Rect2(
					_field_origin.x + cell.x * _cell_size,
					_field_origin.y + cell.y * _cell_size,
					_cell_size, _cell_size
				)
				draw_rect(rect, active_color)
				draw_rect(rect, active_color.darkened(0.3), false, 1.0)

	# ── 场地边框 ──
	draw_rect(Rect2(_field_origin, Vector2(field_w, field_h)),
		Color.from_hsv(hue, 0.4, 0.7, 0.3), false, 1.0)

	# ── 右侧栏: NEXT / HOLD ──
	if font:
		var label_c = Color.from_hsv(hue, 0.3, 0.7, 0.5)
		var sidebar_cell = _cell_size * 0.65

		# NEXT
		draw_string(font, Vector2(_sidebar_x, _field_origin.y + 12.0), "NEXT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_c)
		_draw_piece_preview(_next_type, _sidebar_x, _field_origin.y + 18.0, sidebar_cell)

		# HOLD
		var hold_y = _field_origin.y + _cell_size * 5.0
		draw_string(font, Vector2(_sidebar_x, hold_y), "HOLD",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_c)
		_draw_piece_preview(_hold_type, _sidebar_x, hold_y + 6.0, sidebar_cell)

	# ── 左侧栏: SCORE / LEVEL / LINES ──
	if font:
		var lbl_c = Color.from_hsv(hue, 0.3, 0.7, 0.5)
		var val_c = Color.from_hsv(hue, 0.4, 0.9, 0.8)
		var lx = _left_sidebar_x
		var ly = _field_origin.y + 12.0
		var gap = _cell_size * 3.2

		# SCORE
		draw_string(font, Vector2(lx, ly), "SCORE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lbl_c)
		draw_string(font, Vector2(lx, ly + 18.0), str(_score),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GameTerminalStyles.bright())

		# LEVEL
		ly += gap
		var lv_c = GameTerminalStyles.status_warning() if _level >= 10 else GameTerminalStyles.status_active()
		draw_string(font, Vector2(lx, ly), "LEVEL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lbl_c)
		draw_string(font, Vector2(lx, ly + 18.0), str(_level),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, lv_c)

		# LINES
		ly += gap
		draw_string(font, Vector2(lx, ly), "LINES",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lbl_c)
		draw_string(font, Vector2(lx, ly + 18.0), str(_lines_cleared),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, val_c)

	# ── Game Over 覆盖 ──
	if not _game_active and font:
		draw_rect(Rect2(_field_origin, Vector2(field_w, field_h)), Color(0.02, 0.0, 0.0, 0.6))
		var go_c = Color.from_hsv(0.0, 0.6, 0.9, 0.8)
		var text_x = _field_origin.x + field_w * 0.5 - 36.0
		var text_y = _field_origin.y + field_h * 0.5 - 8.0
		draw_string(font, Vector2(text_x, text_y), "OVERFLOW",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, go_c)

	# ── 操作提示 ──
	if _game_active and font:
		var hint_y = _field_origin.y + field_h + 14
		var hint_text = "方向键 + 空格(硬降) + C(暂存)"
		draw_string(font, Vector2(_field_origin.x, hint_y), hint_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.4, 0.5, 0.3))

func _draw_piece_preview(ptype: String, sx: float, sy: float, ps: float) -> void:
	if ptype == "":
		return
	var cells = PIECES[ptype][0]
	var color = _get_piece_color(ptype, true)
	var min_x := 999
	var max_x := -999
	var min_y := 999
	var max_y := -999
	for c in cells:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_y = mini(min_y, c.y)
		max_y = maxi(max_y, c.y)
	var pw = (max_x - min_x + 1) * ps
	var ph = (max_y - min_y + 1) * ps
	var ox = sx + 4.0
	var oy = sy + 4.0
	for c in cells:
		var rx = ox + (c.x - min_x) * ps
		var ry = oy + (c.y - min_y) * ps
		draw_rect(Rect2(rx, ry, ps, ps), color)
		draw_rect(Rect2(rx, ry, ps, ps), color.darkened(0.3), false, 1.0)

func _get_piece_color(ptype: String, is_active: bool) -> Color:
	var hue = EventBus.ui_hue
	var offset = PIECE_HUE_OFFSETS.get(ptype, 0.0)
	var h = fmod(hue + offset, 1.0)
	if is_active:
		return Color.from_hsv(h, 0.6, 0.9, 0.95)
	else:
		return Color.from_hsv(h, 0.45, 0.7, 0.85)

# game.gd — 终端 2048 (矩阵叠加)
# 完整动画系统: 滑动幽灵 + 弹入 + 合并脉冲
extends TerminalGameBase

func get_game_id() -> String: return "2048"
func get_game_name() -> String: return "矩阵叠加"
func get_game_desc() -> String: return "4x4 数值融合"
func supports_auto_play() -> bool: return true

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

# ── 弹入/脉冲动画 ──
var _tile_scale: Array = []   # float[16]
var _tile_target: Array = []  # float[16]
var _tile_phase: Array = []   # int[16]  0=idle 1=spawn 2=merge

# ── 滑动幽灵系统 ──
const _SLIDE_DUR := 0.10
var _sliding: bool = false
var _ghosts: Array = []        # [{val,from_c,to_c,t}]
var _board_after: Array = []
var _pending_merged: Array = []

var _result_overlay: PanelContainer
var _result_label: Label
var _restart_btn: Button

# ══════════════════════════════════════════════
#  色彩 / 字体辅助
# ══════════════════════════════════════════════

func _tile_color(val: int) -> Color:
	var h = EventBus.ui_hue
	match val:
		0:    return Color(0.04, 0.06, 0.10, 0.35)
		2:    return Color.from_hsv(h, 0.55, 0.22, 0.90)
		4:    return Color.from_hsv(h, 0.62, 0.32, 0.92)
		8:    return Color.from_hsv(fmod(h+0.07,1.0), 0.72, 0.48, 0.93)
		16:   return Color.from_hsv(fmod(h+0.15,1.0), 0.78, 0.58, 0.93)
		32:   return Color.from_hsv(fmod(h+0.22,1.0), 0.82, 0.68, 0.93)
		64:   return Color.from_hsv(fmod(h+0.30,1.0), 0.86, 0.78, 0.94)
		128:  return Color.from_hsv(fmod(h+0.38,1.0), 0.88, 0.88, 0.95)
		256:  return Color.from_hsv(fmod(h+0.46,1.0), 0.82, 0.95, 0.96)
		512:  return Color.from_hsv(fmod(h+0.54,1.0), 0.68, 0.98, 1.00)
		1024: return Color.from_hsv(fmod(h+0.62,1.0), 0.48, 1.00, 1.00)
		2048: return Color.from_hsv(fmod(h+0.70,1.0), 0.18, 1.00, 1.00)
		_:    return Color(0.95, 0.95, 1.00, 1.00)

func _font_size(val: int) -> int:
	var base = int(_cell_size * 0.42)
	if val < 100:    return base
	elif val < 1000:  return int(base * 0.78)
	elif val < 10000: return int(base * 0.62)
	else:             return int(base * 0.50)

# ══════════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════════

func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_result_overlay()
	start_game()

func get_hud_data() -> Dictionary:
	var sc = GameTerminalStyles.status_warning() if _score > 0 else GameTerminalStyles.dim()
	return {
		"score": {"label": "SCORE", "value": str(_score), "color": sc},
		"max":   {"label": "MAX",   "value": str(_max_tile()), "color": GameTerminalStyles.dim()},
	}

func get_best_score() -> int: return _score

func auto_play_step() -> void:
	if not _game_active or _sliding: return
	_slide_left();  if _sliding: return
	_slide_down();  if _sliding: return
	_slide_up();    if _sliding: return
	_slide_right()

func _process(delta: float) -> void:
	_time += delta
	var dirty := false

	if _sliding:
		var done := true
		for g in _ghosts:
			if g.t < 1.0:
				g.t = minf(g.t + delta / _SLIDE_DUR, 1.0)
				if g.t < 1.0: done = false
		dirty = true
		if done: _finish_slide()

	for i in range(GRID * GRID):
		match _tile_phase[i]:
			1:
				_tile_scale[i] = minf(_tile_scale[i] + delta * 12.0, 1.0)
				if _tile_scale[i] >= 1.0: _tile_phase[i] = 0
				dirty = true
			2:
				_tile_scale[i] = minf(_tile_scale[i] + delta * 18.0, _tile_target[i])
				if _tile_scale[i] >= _tile_target[i]:
					if _tile_target[i] > 1.0: _tile_target[i] = 1.0
					else: _tile_phase[i] = 0; _tile_scale[i] = 1.0
				dirty = true

	if _game_active and not _sliding:
		if Input.is_action_just_pressed("ui_up"):    _slide_up()
		elif Input.is_action_just_pressed("ui_right"): _slide_right()
		elif Input.is_action_just_pressed("ui_down"):  _slide_down()
		elif Input.is_action_just_pressed("ui_left"):  _slide_left()

	if dirty or _game_active: queue_redraw()

func start_game() -> void:
	_board.resize(GRID * GRID)
	_tile_scale.resize(GRID * GRID)
	_tile_target.resize(GRID * GRID)
	_tile_phase.resize(GRID * GRID)
	for i in range(GRID * GRID):
		_board[i] = 0
		_tile_scale[i] = 1.0; _tile_target[i] = 1.0; _tile_phase[i] = 0
	_score = 0; _game_active = true; _result = -1
	_won_shown = false; _time = 0.0; _sliding = false; _ghosts.clear()
	_spawn_direct(); _spawn_direct()
	if is_instance_valid(_result_overlay): _result_overlay.visible = false
	game_started.emit(); queue_redraw()

# ══════════════════════════════════════════════
#  布局
# ══════════════════════════════════════════════

func _calc_layout() -> void:
	var avail = minf(size.x - 16.0, size.y - 42.0 - 8.0)
	_cell_size = (avail - _GAP * (GRID - 1)) / GRID
	var total = _cell_size * GRID + _GAP * (GRID - 1)
	_grid_origin = Vector2((size.x - total) * 0.5, 42.0 + (size.y - 42.0 - total) * 0.5)

func _cell_rect(idx: int) -> Rect2:
	var col = idx % GRID; var row = idx / GRID
	return Rect2(_grid_origin + Vector2(col*(_cell_size+_GAP), row*(_cell_size+_GAP)), Vector2(_cell_size,_cell_size))

func _cell_center(idx: int) -> Vector2:
	return _cell_rect(idx).get_center()

# ══════════════════════════════════════════════
#  核心逻辑
# ══════════════════════════════════════════════

## 合并一行，返回 {result, merged, moves, score_delta}
## moves: [{from_li, to_li, val}]  行内索引
func _merge_tracked(line: Array) -> Dictionary:
	var compact = []; var src = []
	for i in range(line.size()):
		if line[i] != 0: compact.append(line[i]); src.append(i)
	var result = []; var moves = []; var merged = []; var sd = 0
	var i = 0
	while i < compact.size():
		if i+1 < compact.size() and compact[i] == compact[i+1]:
			var nv = compact[i] * 2
			result.append(nv)
			var dst = result.size()-1
			moves.append({from_li=src[i],   to_li=dst, val=compact[i]})
			moves.append({from_li=src[i+1], to_li=dst, val=compact[i]})
			merged.append(dst); sd += nv; i += 2
		else:
			result.append(compact[i])
			moves.append({from_li=src[i], to_li=result.size()-1, val=compact[i]}); i += 1
	while result.size() < GRID: result.append(0)
	return {result=result, merged=merged, moves=moves, score_delta=sd}

func _do_slide(get_line: Callable, set_line: Callable, to_global: Callable) -> void:
	if _sliding: return
	_calc_layout()
	var new_board = _board.duplicate()
	var all_merged: Array = []; var all_moves: Array = []; var total_score = 0
	for axis in range(GRID):
		var line = get_line.call(axis)
		var data = _merge_tracked(line)
		set_line.call(axis, data.result, new_board)
		total_score += data.score_delta
		for dst in data.merged: all_merged.append(to_global.call(axis, dst, false))
		for m in data.moves:
			all_moves.append({
				from_gi = to_global.call(axis, m.from_li, true),
				to_gi   = to_global.call(axis, m.to_li,   false),
				val     = m.val
			})
	if new_board == _board: return
	_score += total_score
	_start_slide(new_board, all_merged, all_moves)

func _slide_left() -> void:
	_do_slide(
		func(row): return [_board[row*GRID+0],_board[row*GRID+1],_board[row*GRID+2],_board[row*GRID+3]],
		func(row, res, nb): for c in range(GRID): nb[row*GRID+c] = res[c],
		func(row, li, _r): return row*GRID+li
	)

func _slide_right() -> void:
	_do_slide(
		func(row): return [_board[row*GRID+3],_board[row*GRID+2],_board[row*GRID+1],_board[row*GRID+0]],
		func(row, res, nb): for c in range(GRID): nb[row*GRID+(GRID-1-c)] = res[c],
		func(row, li, _r): return row*GRID+(GRID-1-li)
	)

func _slide_up() -> void:
	_do_slide(
		func(col): return [_board[0*GRID+col],_board[1*GRID+col],_board[2*GRID+col],_board[3*GRID+col]],
		func(col, res, nb): for r in range(GRID): nb[r*GRID+col] = res[r],
		func(col, li, _r): return li*GRID+col
	)

func _slide_down() -> void:
	_do_slide(
		func(col): return [_board[3*GRID+col],_board[2*GRID+col],_board[1*GRID+col],_board[0*GRID+col]],
		func(col, res, nb): for r in range(GRID): nb[(GRID-1-r)*GRID+col] = res[r],
		func(col, li, _r): return (GRID-1-li)*GRID+col
	)

func _start_slide(new_board: Array, merged: Array, moves: Array) -> void:
	_ghosts.clear()
	for m in moves:
		_ghosts.append({val=m.val, from_c=_cell_center(m.from_gi), to_c=_cell_center(m.to_gi), t=0.0})
	_board_after = new_board; _pending_merged = merged; _sliding = true

func _finish_slide() -> void:
	_sliding = false; _board = _board_after.duplicate(); _ghosts.clear()
	var sp = _spawn_direct()
	if sp >= 0: _tile_scale[sp]=0.0; _tile_target[sp]=1.0; _tile_phase[sp]=1
	for idx in _pending_merged: _tile_scale[idx]=1.0; _tile_target[idx]=1.2; _tile_phase[idx]=2
	_pending_merged.clear(); _check_state(); queue_redraw()

func _spawn_direct() -> int:
	var empty = []
	for i in range(GRID * GRID): if _board[i] == 0: empty.append(i)
	if empty.size() == 0: return -1
	var idx = empty[randi() % empty.size()]
	_board[idx] = 2 if randf() < 0.9 else 4
	return idx

func _has_moves() -> bool:
	for i in range(GRID*GRID): if _board[i] == 0: return true
	for r in range(GRID):
		for c in range(GRID):
			var v = _board[r*GRID+c]
			if c+1 < GRID and _board[r*GRID+c+1] == v: return true
			if r+1 < GRID and _board[(r+1)*GRID+c] == v: return true
	return false

func _max_tile() -> int:
	var m = 0
	for v in _board:
		if v > m: m = v
	return m

func _check_state() -> void:
	if _max_tile() >= WIN_VAL and not _won_shown:
		_won_shown = true; _game_active = false; _result = 0; _show_result(); game_over.emit(0); return
	if not _has_moves():
		_game_active = false; _result = 1; _show_result(); game_over.emit(1)

# ══════════════════════════════════════════════
#  结算
# ══════════════════════════════════════════════

func _build_result_overlay() -> void:
	var d = GameTerminalStyles.create_result_overlay("[ 重新叠加 ]", start_game)
	_result_overlay = d.overlay; _result_label = d.label; _restart_btn = d.btn
	add_child(_result_overlay)

func _show_result() -> void:
	if not is_instance_valid(_result_overlay): return
	var lines = ["矩阵峰值已达。","数据叠加极限。","2048...目标达成。"] if _result==0 else ["矩阵已饱和。","操作空间耗尽。","叠加中断。"]
	var text = lines[randi()%lines.size()] + "\n得分: %d / 最大值: %d" % [_score, _max_tile()]
	var c = GameTerminalStyles.status_active() if _result==0 else Color(0.9,0.35,0.3,0.9)
	GameTerminalStyles.show_result_overlay(_result_overlay, _result_label, text, c)

# ══════════════════════════════════════════════
#  渲染
# ══════════════════════════════════════════════

func _ease_out_quad(t: float) -> float: return 1.0-(1.0-t)*(1.0-t)

func _draw_tile(center: Vector2, val: int, sc: float, font: Font) -> void:
	if sc <= 0.01 or val < 0: return
	var cs = _cell_size * sc
	var rect = Rect2(center - Vector2(cs,cs)*0.5, Vector2(cs,cs))
	draw_rect(rect, _tile_color(val))
	if val > 0:
		draw_rect(rect, Color(0,0,0,0.55), false, 2.0)
		draw_rect(rect.grow(-2.0), Color(1,1,1,0.14), false, 1.0)
		if font:
			var text = str(val); var fs = _font_size(val)
			var tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tpos = Vector2(center.x - tw*0.5, center.y + (font.get_ascent(fs)-font.get_descent(fs))*0.5)
			draw_string(font, tpos+Vector2(1,1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0,0,0,0.8))
			draw_string(font, tpos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1,1,1,0.95))
	else:
		draw_rect(rect, Color.from_hsv(EventBus.ui_hue,0.2,0.4,0.08), false, 1.0)

func _draw() -> void:
	_calc_layout()
	var hue = EventBus.ui_hue
	var font = ThemeDB.fallback_font
	var total = _cell_size * GRID + _GAP * (GRID-1)

	# HUD
	if font:
		var hud_h=28.0; var hud_y=_grid_origin.y-hud_h-6.0
		var box_w=total*0.44; var lx=_grid_origin.x
		_draw_hud_box(lx, hud_y, box_w, hud_h, hue)
		var lbl_c=Color.from_hsv(hue,0.3,0.65,0.5)
		var sc=GameTerminalStyles.status_warning() if _score>0 else GameTerminalStyles.dim()
		draw_string(font, Vector2(lx+6,hud_y+11), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lbl_c)
		draw_string(font, Vector2(lx+6,hud_y+24), str(_score), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, sc)
		var rx=lx+box_w+(total-box_w*2.0)
		_draw_hud_box(rx, hud_y, box_w, hud_h, hue)
		draw_string(font, Vector2(rx+6,hud_y+11), "MAX", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lbl_c)
		draw_string(font, Vector2(rx+6,hud_y+24), str(_max_tile()), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameTerminalStyles.dim())

	# 底板
	draw_rect(Rect2(_grid_origin-Vector2(3,3), Vector2(total+6,total+6)), Color(0.03,0.05,0.09,0.6))

	if _sliding:
		# 空格底色
		for i in range(GRID*GRID):
			var cr = _cell_rect(i)
			draw_rect(cr, _tile_color(0))
			draw_rect(cr, Color.from_hsv(hue,0.2,0.4,0.06), false, 1.0)
		# 幽灵方块 (插值位置)
		for g in _ghosts:
			var et = _ease_out_quad(g.t)
			_draw_tile(g.from_c.lerp(g.to_c, et), g.val, 1.0, font)
	else:
		for i in range(GRID*GRID):
			_draw_tile(_cell_rect(i).get_center(), _board[i], _tile_scale[i], font)

	# 外框
	draw_rect(Rect2(_grid_origin-Vector2(1,1), Vector2(total+2,total+2)),
		Color.from_hsv(hue,0.4,0.6,0.2), false, 1.0)

	if _game_active and not _sliding and font:
		draw_string(font, Vector2(_grid_origin.x, _grid_origin.y+total+16), "方向键滑动",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3,0.4,0.5,0.28))

func _draw_hud_box(x:float,y:float,w:float,h:float,hue:float)->void:
	var r=Rect2(x,y,w,h)
	draw_rect(r, Color(0.04,0.06,0.12,0.7))
	draw_rect(r, Color.from_hsv(hue,0.45,0.55,0.25), false, 1.0)
	draw_rect(r.grow(-2.0), Color.from_hsv(hue,0.25,0.35,0.10), false, 1.0)

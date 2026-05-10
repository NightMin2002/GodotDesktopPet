# game.gd — 2048 (矩阵叠加)
# 滑动合并同值方块, 4x4 网格, 目标达到 2048
extends BaseGame

# ══════════════════════════════════════════════
# 常量 + 状态
# ══════════════════════════════════════════════

const GRID = 4
const CELL_SIZE = 58
const CELL_GAP = 5
const SWIPE_THRESHOLD = 25.0

# ── UI 引用 ──
var _panel: PanelContainer = null
var _board_area: Control = null  # 棋盘区域 (手动布局, 支持滑动动画)
var _cells: Array = []       # Array[Array[PanelContainer]]
var _cell_labels: Array = [] # Array[Array[Label]]
var _score_value: Label = null
var _best_value: Label = null

# ── 游戏状态 ──
var _board: Array = []  # Array[Array[int]] 4x4, 0=空
var _score: int = 0
var _best: int = 0
var _game_over: bool = false
var _reached_2048: bool = false
var _animating: bool = false  # 动画进行中, 阻止输入

# ── 滑动输入 ──
var _swipe_start: Vector2 = Vector2.ZERO
var _swiping: bool = false

# ── 话术池 ──
const _POOL_START = [
	"4x4矩阵。合并同值元素。目标: 2048。",
	"熵增游戏。...合并就对了。",
	"规则: 滑动，合并，别让矩阵填满。",
	"数学期望不重要。滑就行了。",
]
const _POOL_MILESTONE = [
	"数据密度在增长。",
	"合并效率...尚可。",
	"...继续。",
	"矩阵状态良好。",
	"运算进度正常。",
]
const _POOL_WIN = [
	"2048...只是基础目标。要继续吗？",
	"达到阈值。本机...略感意外。",
	"目标达成。不过矩阵还可以继续叠加。",
]
const _POOL_LOSE = [
	"矩阵已满。无有效操作。",
	"运算终止。...下次试试角落策略。",
	"空间耗尽。建议重新初始化。",
]
const _POOL_CLOSE_MID = [
	"运算中断。...这算你放弃。",
	"矩阵数据未持久化。终止。",
]

var _q_start: Array = []
var _q_milestone: Array = []
var _q_win: Array = []
var _q_lose: Array = []
var _q_close: Array = []

# ── 里程碑话术触发阈值 ──
var _next_milestone: int = 500

# ══════════════════════════════════════════════
# BaseGame 接口
# ══════════════════════════════════════════════

func get_game_id() -> String: return "2048"
func get_game_name() -> String: return "矩阵叠加"
func get_game_desc() -> String: return "滑动合并同值方块，目标达到2048"
func get_default_panel_size() -> Vector2: return Vector2(280, 360)

func get_tutorial_steps() -> Array[Dictionary]:
	return [
		{"text": "这是一个4x4矩阵的数值合并游戏。"},
		{"text": "滑动方向: 方向键 / WASD / 鼠标拖拽方向。"},
		{"text": "相同数值的方块碰撞时会合并为两倍。"},
		{"text": "目标: 合成 2048。...本机不确定你能做到。"},
	]

func start() -> void:
	_build_ui()
	_reset_game()
	_say(_pick(_q_start, _POOL_START))

func cleanup() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_cells.clear()
	_cell_labels.clear()
	super.cleanup()

# ══════════════════════════════════════════════
# UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(GRID * CELL_SIZE + (GRID + 1) * CELL_GAP + 28, 0)

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
	outer.add_theme_constant_override("margin_top", 8)
	outer.add_theme_constant_override("margin_bottom", 6)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(outer)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(vbox)

	# ── 分数栏 ──
	var score_row = HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 8)
	score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(score_row)

	_score_value = _create_score_box(score_row, "分数", "0")
	_best_value = _create_score_box(score_row, "最高", "0")

	# ── 棋盘 ──
	var board_wrapper = PanelContainer.new()
	board_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var board_bg = StyleBoxFlat.new()
	board_bg.bg_color = Color(0.06, 0.08, 0.15, 0.8)
	board_bg.set_corner_radius_all(8)
	board_bg.content_margin_left = CELL_GAP
	board_bg.content_margin_right = CELL_GAP
	board_bg.content_margin_top = CELL_GAP
	board_bg.content_margin_bottom = CELL_GAP
	board_wrapper.add_theme_stylebox_override("panel", board_bg)
	vbox.add_child(board_wrapper)

	var board_size = GRID * CELL_SIZE + (GRID - 1) * CELL_GAP
	_board_area = Control.new()
	_board_area.custom_minimum_size = Vector2(board_size, board_size)
	_board_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_wrapper.add_child(_board_area)

	_cells.clear()
	_cell_labels.clear()
	for y in range(GRID):
		var row_cells: Array = []
		var row_labels: Array = []
		for x in range(GRID):
			var cell = PanelContainer.new()
			cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
			cell.size = Vector2(CELL_SIZE, CELL_SIZE)
			cell.position = _cell_pos(x, y)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var cell_bg = StyleBoxFlat.new()
			cell_bg.bg_color = Color(0.08, 0.10, 0.18, 0.5)
			cell_bg.set_corner_radius_all(6)
			cell.add_theme_stylebox_override("panel", cell_bg)

			var label = Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 22)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(label)

			_board_area.add_child(cell)
			row_cells.append(cell)
			row_labels.append(label)
		_cells.append(row_cells)
		_cell_labels.append(row_labels)

	# ── 键盘输入 ──
	_panel.focus_mode = Control.FOCUS_ALL
	_panel.gui_input.connect(_on_game_input)

	# ── 挂载 + 弹入动画 + 悬浮组件 ──
	await _mount_panel(_panel)

	# 获取焦点 (键盘输入需要)
	if is_instance_valid(_panel):
		_panel.call_deferred("grab_focus")

## 创建分数展示盒
func _create_score_box(parent: HBoxContainer, title: String, initial: String) -> Label:
	var wrapper = PanelContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrapper_bg = StyleBoxFlat.new()
	wrapper_bg.bg_color = Color(0.06, 0.08, 0.16, 0.6)
	wrapper_bg.set_corner_radius_all(6)
	wrapper_bg.content_margin_left = 8
	wrapper_bg.content_margin_right = 8
	wrapper_bg.content_margin_top = 4
	wrapper_bg.content_margin_bottom = 4
	wrapper.add_theme_stylebox_override("panel", wrapper_bg)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(col)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.add_theme_color_override("font_color", Color(0.45, 0.55, 0.70))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title_lbl)

	var value_lbl = Label.new()
	value_lbl.text = initial
	value_lbl.add_theme_font_size_override("font_size", 16)
	value_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96))
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(value_lbl)

	parent.add_child(wrapper)
	return value_lbl

# ══════════════════════════════════════════════
# 游戏逻辑
# ══════════════════════════════════════════════

func _reset_game() -> void:
	_board.clear()
	for y in range(GRID):
		var row: Array = []
		for x in range(GRID):
			row.append(0)
		_board.append(row)
	_score = 0
	_game_over = false
	_reached_2048 = false
	_next_milestone = 500
	_spawn_tile()
	_spawn_tile()
	_update_cells()
	_update_score()
	_hide_restart_bubble()

## 生成新方块, 返回位置 (供动画用)
func _spawn_tile() -> Vector2i:
	var empty: Array = []
	for y in range(GRID):
		for x in range(GRID):
			if _board[y][x] == 0:
				empty.append(Vector2i(x, y))
	if empty.is_empty():
		return Vector2i(-1, -1)
	var pos = empty[randi() % empty.size()]
	_board[pos.y][pos.x] = 2 if randf() < 0.9 else 4
	return pos

## 格子屏幕位置计算
func _cell_pos(x: int, y: int) -> Vector2:
	return Vector2(x * (CELL_SIZE + CELL_GAP), y * (CELL_SIZE + CELL_GAP))

func _do_move(dir: Vector2i) -> void:
	if _game_over or _animating:
		return
	# 快照旧状态
	var old_board: Array = []
	for y in range(GRID):
		old_board.append(_board[y].duplicate())
	# 执行移动 + 跟踪轨迹
	var move_data = _move_tracked(dir)
	if not move_data.moved:
		return
	_animating = true
	var hue = EventBus.ui_hue
	# 创建克隆覆盖层 (所有旧方块的视觉副本)
	var clones: Array = []
	for y in range(GRID):
		for x in range(GRID):
			if old_board[y][x] != 0:
				var c = _make_clone(old_board[y][x], Vector2i(x, y), hue)
				clones.append(c)
	# 隐藏真实格子
	for y in range(GRID):
		for x in range(GRID):
			_cells[y][x].modulate.a = 0.0
	# 计算每个克隆的目标位置
	var dest_map: Dictionary = {}  # "x,y" -> Vector2i
	for m in move_data.tile_moves:
		dest_map[str(m.from.x) + "," + str(m.from.y)] = m.to
	# 滑动动画
	var duration = 0.1
	var tw = _board_area.create_tween().set_parallel(true)
	for c in clones:
		var key = str(c.pos.x) + "," + str(c.pos.y)
		if key in dest_map:
			var target = _cell_pos(dest_map[key].x, dest_map[key].y)
			tw.tween_property(c.node, "position", target, duration) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func():
		# 清除克隆
		for cl in clones:
			if is_instance_valid(cl.node):
				cl.node.queue_free()
		# 生成新方块 + 显示最终状态
		var spawn_pos = _spawn_tile()
		_update_cells()
		_update_score()
		for yy in range(GRID):
			for xx in range(GRID):
				_cells[yy][xx].modulate.a = 1.0
		# 合并脉冲 + 新方块弹入
		_animate_merged(move_data.merged)
		if spawn_pos != Vector2i(-1, -1):
			_animate_spawn(spawn_pos)
		_animating = false
		# 里程碑话术
		if _score >= _next_milestone:
			_next_milestone = _score + 500 - (_score % 500)
			if randf() < 0.4:
				_say(_pick(_q_milestone, _POOL_MILESTONE))
		# 检查游戏结束
		if _check_game_over():
			_game_over = true
			_say(_pick(_q_lose, _POOL_LOSE))
			_show_restart_bubble()
			game_finished.emit(Result.WIN if _reached_2048 else Result.LOSE)
	)

## 创建方块视觉克隆 (用于滑动动画)
func _make_clone(value: int, pos: Vector2i, hue: float) -> Dictionary:
	var cell = PanelContainer.new()
	cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	cell.size = Vector2(CELL_SIZE, CELL_SIZE)
	cell.position = _cell_pos(pos.x, pos.y)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg = StyleBoxFlat.new()
	bg.bg_color = _get_tile_color(value, hue)
	bg.set_corner_radius_all(6)
	cell.add_theme_stylebox_override("panel", bg)
	var label = Label.new()
	label.text = str(value)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _get_font_size(value))
	label.add_theme_color_override("font_color", _get_text_color(value))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(label)
	_board_area.add_child(cell)
	return {node = cell, pos = pos}

## 执行移动 + 返回移动跟踪数据
func _move_tracked(dir: Vector2i) -> Dictionary:
	var tile_moves: Array = []  # [{from: Vector2i, to: Vector2i}]
	var merged_positions: Array = []  # [Vector2i]
	var moved = false
	if dir.x != 0:
		for y in range(GRID):
			var line: Array = []
			for x in range(GRID): line.append(_board[y][x])
			if dir.x > 0: line.reverse()
			var data = _compress_and_merge_tracked(line)
			if dir.x > 0: data.result.reverse()
			for x in range(GRID):
				if _board[y][x] != data.result[x]: moved = true
				_board[y][x] = data.result[x]
			for m in data.moves:
				var fx = m.from if dir.x < 0 else (GRID - 1 - m.from)
				var tx = m.to if dir.x < 0 else (GRID - 1 - m.to)
				tile_moves.append({from = Vector2i(fx, y), to = Vector2i(tx, y)})
			for mi in data.merged:
				var mx = mi if dir.x < 0 else (GRID - 1 - mi)
				merged_positions.append(Vector2i(mx, y))
	else:
		for x in range(GRID):
			var line: Array = []
			for y in range(GRID): line.append(_board[y][x])
			if dir.y > 0: line.reverse()
			var data = _compress_and_merge_tracked(line)
			if dir.y > 0: data.result.reverse()
			for y in range(GRID):
				if _board[y][x] != data.result[y]: moved = true
				_board[y][x] = data.result[y]
			for m in data.moves:
				var fy = m.from if dir.y < 0 else (GRID - 1 - m.from)
				var ty = m.to if dir.y < 0 else (GRID - 1 - m.to)
				tile_moves.append({from = Vector2i(x, fy), to = Vector2i(x, ty)})
			for mi in data.merged:
				var my = mi if dir.y < 0 else (GRID - 1 - mi)
				merged_positions.append(Vector2i(x, my))
	return {moved = moved, tile_moves = tile_moves, merged = merged_positions}

## 压缩合并 + 返回移动跟踪
func _compress_and_merge_tracked(line: Array) -> Dictionary:
	var compressed: Array = []
	var src: Array = []  # 源索引
	for i in range(line.size()):
		if line[i] != 0:
			compressed.append(line[i])
			src.append(i)
	var result: Array = []
	var moves: Array = []  # [{from: int, to: int}]
	var merged: Array = []  # 合并位置索引
	var i = 0
	while i < compressed.size():
		if i + 1 < compressed.size() and compressed[i] == compressed[i + 1]:
			var new_val = compressed[i] * 2
			result.append(new_val)
			var dest = result.size() - 1
			moves.append({from = src[i], to = dest})
			moves.append({from = src[i + 1], to = dest})
			merged.append(dest)
			_score += new_val
			if new_val >= 2048 and not _reached_2048:
				_reached_2048 = true
				_say(_pick(_q_win, _POOL_WIN))
			i += 2
		else:
			result.append(compressed[i])
			var dest = result.size() - 1
			moves.append({from = src[i], to = dest})
			i += 1
	while result.size() < GRID:
		result.append(0)
	return {result = result, moves = moves, merged = merged}

func _check_game_over() -> bool:
	for y in range(GRID):
		for x in range(GRID):
			if _board[y][x] == 0:
				return false
	for y in range(GRID):
		for x in range(GRID):
			var val = _board[y][x]
			if x + 1 < GRID and _board[y][x + 1] == val:
				return false
			if y + 1 < GRID and _board[y + 1][x] == val:
				return false
	return true

# ══════════════════════════════════════════════
# UI 更新
# ══════════════════════════════════════════════

func _update_cells() -> void:
	var hue = EventBus.ui_hue
	for y in range(GRID):
		for x in range(GRID):
			var val = _board[y][x]
			var label = _cell_labels[y][x]
			var cell = _cells[y][x]

			label.text = str(val) if val > 0 else ""

			# 格子背景色
			var cell_bg = StyleBoxFlat.new()
			cell_bg.bg_color = _get_tile_color(val, hue)
			cell_bg.set_corner_radius_all(6)
			cell.add_theme_stylebox_override("panel", cell_bg)

			# 文字样式
			label.add_theme_color_override("font_color", _get_text_color(val))
			label.add_theme_font_size_override("font_size", _get_font_size(val))

## 新方块弹入动画 (scale 0 -> 1)
func _animate_spawn(pos: Vector2i) -> void:
	var cell = _cells[pos.y][pos.x]
	if not is_instance_valid(cell):
		return
	cell.pivot_offset = cell.size / 2.0
	cell.scale = Vector2(0.1, 0.1)
	var tw = cell.create_tween()
	tw.tween_property(cell, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 合并脉冲动画 (scale 1 -> 1.15 -> 1)
func _animate_merged(positions: Array) -> void:
	for pos in positions:
		var cell = _cells[pos.y][pos.x]
		if not is_instance_valid(cell):
			continue
		cell.pivot_offset = cell.size / 2.0
		var tw = cell.create_tween()
		tw.tween_property(cell, "scale", Vector2(1.15, 1.15), 0.08)
		tw.tween_property(cell, "scale", Vector2.ONE, 0.08)

func _update_score() -> void:
	if _score_value:
		_score_value.text = str(_score)
	if _score > _best:
		_best = _score
	if _best_value:
		_best_value.text = str(_best)

func _get_tile_color(value: int, hue: float) -> Color:
	match value:
		0: return Color(0.08, 0.10, 0.18, 0.5)
		2: return Color.from_hsv(hue, 0.35, 0.20)
		4: return Color.from_hsv(hue, 0.38, 0.25)
		8: return Color.from_hsv(hue, 0.42, 0.32)
		16: return Color.from_hsv(hue, 0.46, 0.40)
		32: return Color.from_hsv(hue, 0.50, 0.48)
		64: return Color.from_hsv(hue, 0.52, 0.55)
		128: return Color.from_hsv(hue, 0.48, 0.62)
		256: return Color.from_hsv(hue, 0.42, 0.70)
		512: return Color.from_hsv(hue, 0.36, 0.78)
		1024: return Color.from_hsv(hue, 0.30, 0.85)
		2048: return Color.from_hsv(hue, 0.25, 0.92)
		_: return Color.from_hsv(hue, 0.20, 0.96)

func _get_text_color(value: int) -> Color:
	if value == 0:
		return Color.TRANSPARENT
	elif value <= 4:
		return Color(0.55, 0.62, 0.78)
	elif value <= 64:
		return Color(0.88, 0.92, 0.98)
	else:
		return Color.WHITE

func _get_font_size(value: int) -> int:
	if value < 100: return 24
	elif value < 1000: return 20
	elif value < 10000: return 16
	else: return 13

# ══════════════════════════════════════════════
# 输入处理
# ══════════════════════════════════════════════

func _on_game_input(event: InputEvent) -> void:
	if _game_over or _animating:
		return

	# 键盘: 方向键 + WASD (physical_keycode 绕过输入法拦截)
	if event is InputEventKey and event.pressed and not event.echo:
		var dir := Vector2i.ZERO
		var kc = event.keycode
		var pkc = event.physical_keycode
		if kc == KEY_UP or pkc == KEY_W: dir = Vector2i(0, -1)
		elif kc == KEY_DOWN or pkc == KEY_S: dir = Vector2i(0, 1)
		elif kc == KEY_LEFT or pkc == KEY_A: dir = Vector2i(-1, 0)
		elif kc == KEY_RIGHT or pkc == KEY_D: dir = Vector2i(1, 0)
		if dir != Vector2i.ZERO:
			_do_move(dir)
		return

	# 鼠标滑动 (游戏区域, 上部 50px 留给面板拖拽)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local = _panel.get_local_mouse_position()
		if event.pressed and local.y >= 50.0:
			_swipe_start = event.position
			_swiping = true
		elif _swiping:
			_swiping = false
			var delta = event.position - _swipe_start
			if delta.length() > SWIPE_THRESHOLD:
				_handle_swipe(delta)

func _handle_swipe(delta: Vector2) -> void:
	if abs(delta.x) > abs(delta.y):
		_do_move(Vector2i(1, 0) if delta.x > 0 else Vector2i(-1, 0))
	else:
		_do_move(Vector2i(0, 1) if delta.y > 0 else Vector2i(0, -1))

# ══════════════════════════════════════════════
# 关闭 + 重开
# ══════════════════════════════════════════════

func _on_restart() -> void:
	_reset_game()
	_say(_pick(_q_start, _POOL_START))

func _on_close_cleanup() -> bool:
	if not _game_over:
		_game_over = true
		game_finished.emit(Result.LOSE)
		if is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
			_pet.show_local_bubble(_pick(_q_close, _POOL_CLOSE_MID))
	return true

# ══════════════════════════════════════════════
# 话术系统
# ══════════════════════════════════════════════

func _pick(queue: Array, pool: Array) -> String:
	if queue.is_empty():
		queue.append_array(pool)
		queue.shuffle()
	return queue.pop_back()

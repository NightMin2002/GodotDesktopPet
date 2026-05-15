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
var _best_tile: int = 0  # 最大单块数字 (2048/4096...)

var _reached_2048: bool = false
var _animating: bool = false  # 动画进行中, 阻止输入
var _simulating: bool = false # 模拟移动检测中, 跳过副作用 (话术等)

# ── 自动操作 (AI 自玩) ──
# (_auto_play / _auto_timer 已在 BaseGame 中)

# ── 滑动输入 ──
var _swipe_start: Vector2 = Vector2.ZERO
var _swiping: bool = false

# ── 话术池 ──
const _POOL_START = [
	"4x4矩阵。合并同值元素。目标: 2048。",
	"熵增游戏。...合并即可。",
	"规则: 滑动，合并，别让矩阵填满。",
	"数学期望不重要。滑动即可。",
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
	_load_scores()
	_best = SettingsManager.get_int(_score_key("best"), 0)
	_best_tile = SettingsManager.get_int(_score_key("best_tile"), 0)
	_build_ui()
	_reset_game()
	_say(_pick(_q_start, _POOL_START))

func cleanup() -> void:
	_stop_auto_play()
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
	var skel = _create_panel_skeleton(GRID * CELL_SIZE + (GRID + 1) * CELL_GAP + 28, {"left": 14, "right": 14, "top": 12, "bottom": 6, "separation": 8})
	_panel = skel.panel
	var vbox = skel.vbox

	# ── 分数栏 ──
	var score_row = HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 8)
	score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(score_row)

	_score_value = _create_score_box(score_row, "[ MERGE ]", "0")
	_best_value = _create_score_box(score_row, "[ PEAK ]", "0")

	# ── 双方对比行 ──
	var my_best = SettingsManager.get_int(_score_key("best"), 0)
	var pet_best = SettingsManager.get_int(_other_score_key("best"), 0)
	_create_compare_row(vbox, "操作员: %d | 本机: %d" % [my_best, pet_best])

	# ── 棋盘 ──
	var board_wrapper = PanelContainer.new()
	board_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var board_bg = StyleBoxFlat.new()
	board_bg.bg_color = Color(0.02, 0.03, 0.08, 0.85)
	board_bg.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.4)
	board_bg.set_border_width_all(1)
	board_bg.set_corner_radius_all(0)
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
			var hue = EventBus.ui_hue
			var cell_bg = StyleBoxFlat.new()
			cell_bg.bg_color = _get_tile_color(0, hue)
			cell_bg.border_color = Color.from_hsv(hue, 0.4, 0.5, 0.15)
			cell_bg.set_border_width_all(1)
			cell_bg.set_corner_radius_all(0)
			cell.add_theme_stylebox_override("panel", cell_bg)

			var label = Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 22)
			label.add_theme_constant_override("outline_size", 5)
			label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
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
	wrapper_bg.bg_color = Color(0.03, 0.04, 0.10, 0.8)
	wrapper_bg.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.3)
	wrapper_bg.set_border_width_all(1)
	wrapper_bg.set_corner_radius_all(0)
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
			_add_gaming_xp(5 + _score / 500 * 5)  # 基础 5 + 分数加成
			_save_best()
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
	bg.border_color = Color.from_hsv(hue, 0.5, 0.6, 0.4)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(0)
	cell.add_theme_stylebox_override("panel", bg)
	var label = Label.new()
	label.text = str(value)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _get_font_size(value))
	label.add_theme_color_override("font_color", _get_text_color(value))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
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
			if new_val > _best_tile:
				_best_tile = new_val
			if new_val >= 2048 and not _reached_2048 and not _simulating:
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
			cell_bg.border_color = Color.from_hsv(hue, 0.5, 0.6, 0.4) if val > 0 else Color.from_hsv(hue, 0.4, 0.5, 0.15)
			cell_bg.set_border_width_all(1)
			cell_bg.set_corner_radius_all(0)
			cell.add_theme_stylebox_override("panel", cell_bg)

			# 文字样式
			label.add_theme_color_override("font_color", _get_text_color(val))
			label.add_theme_font_size_override("font_size", _get_font_size(val))
			label.add_theme_constant_override("outline_size", 5 if val > 0 else 0)
			label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))

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
	if _compare_label:
		var other_best = SettingsManager.get_int(_other_score_key("best"), 0)
		_compare_label.text = "操作员: %d | 本机: %d" % ([_best, other_best] if not _auto_play else [other_best, _best])

## 保存最高分到 SettingsManager
func _save_best() -> void:
	if _takeover:
		return  # 用户接管自玩局，战绩作废
	SettingsManager.set_int(_score_key("best"), _best)
	SettingsManager.set_int(_score_key("best_tile"), _best_tile)

func _get_tile_color(value: int, hue: float) -> Color:
	match value:
		0: return Color(0.03, 0.04, 0.08, 0.85)
		2: return Color.from_hsv(hue, 0.60, 0.25, 0.95)
		4: return Color.from_hsv(hue, 0.65, 0.35, 0.95)
		8: return Color.from_hsv(fmod(hue + 0.08, 1.0), 0.70, 0.45, 0.95)
		16: return Color.from_hsv(fmod(hue + 0.16, 1.0), 0.75, 0.55, 0.95)
		32: return Color.from_hsv(fmod(hue + 0.24, 1.0), 0.80, 0.65, 0.95)
		64: return Color.from_hsv(fmod(hue + 0.32, 1.0), 0.85, 0.75, 0.95)
		128: return Color.from_hsv(fmod(hue + 0.40, 1.0), 0.90, 0.85, 0.95)
		256: return Color.from_hsv(fmod(hue + 0.48, 1.0), 0.85, 0.95, 0.95)
		512: return Color.from_hsv(fmod(hue + 0.56, 1.0), 0.70, 0.98, 1.0)
		1024: return Color.from_hsv(fmod(hue + 0.64, 1.0), 0.50, 1.0, 1.0)
		2048: return Color.from_hsv(fmod(hue + 0.72, 1.0), 0.20, 1.0, 1.0)
		_: return Color(0.9, 0.9, 1.0, 1.0)

func _get_text_color(value: int) -> Color:
	if value == 0:
		return Color.TRANSPARENT
	elif value <= 4:
		return Color(0.6, 0.7, 0.85)
	elif value <= 64:
		return Color(0.9, 0.95, 1.0)
	else:
		return Color(1.0, 1.0, 1.0)

func _get_font_size(value: int) -> int:
	if value < 100: return 24
	elif value < 1000: return 20
	elif value < 10000: return 16
	else: return 13

# ══════════════════════════════════════════════
# 输入处理
# ══════════════════════════════════════════════

func _on_game_input(event: InputEvent) -> void:
	# 用户输入 -> 接管自动操作
	if _auto_play:
		var dominated = false
		if event is InputEventKey and event.pressed and not event.echo:
			dominated = true
		elif event is InputEventMouseButton and event.pressed:
			dominated = true
		if dominated:
			_stop_auto_play()
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

func _on_close_extra_cleanup() -> void:
	_save_best()

func get_close_speech_pool() -> Array:
	return _POOL_CLOSE_MID

func get_auto_close_lines() -> Array:
	return ["...？", "...训练中断。", "运算被终止了。"]

# ══════════════════════════════════════════════
# 话术系统
# ══════════════════════════════════════════════

# _pick() 已统一到 BaseGame 基类

# ══════════════════════════════════════════════
# 自动操作 (AI 自玩)
# ══════════════════════════════════════════════

func get_auto_start_lines() -> Array:
	return [
		"逻辑训练程序启动。",
		"...运算热身。",
		"矩阵推演开始。...想打扰的话，由你接手。",
		"自主训练。...观看可以。",
	]

func get_auto_play_interval() -> float:
	return 0.5

func _get_takeover_lines() -> Array:
	return ["...交给你了。", "操作权移交。", "你来？...好。", "接手确认。"]

func _auto_play_step() -> void:
	if not _auto_play:
		return
	if _game_over:
		_auto_finish_and_close()
		return
	# 自玩达到 2048: 主动收手
	if _reached_2048:
		_game_over = true
		_save_best()
		game_finished.emit(Result.WIN)
		if is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
			var win_lines = [
				"...矩阵推演完成。合并模块运行正常。",
				"...2048。目标达成。自行退出。",
				"...运算结束。结果在预期范围内。",
			]
			_pet.show_local_bubble(win_lines[randi() % win_lines.size()])
		_auto_finish_and_close()
		return
	if _animating:
		return
	var dir = _ai_pick_move()
	if dir != Vector2i.ZERO:
		_do_move(dir)
	if is_instance_valid(_auto_timer):
		# 操作速度受等级影响 (Lv.1: 0.4~0.7s → Lv.10: 0.08~0.2s)
		var rate = _get_mistake_rate()
		var spd_factor = 1.0 - rate / 0.10
		var lo = lerpf(0.4, 0.08, spd_factor)
		var hi = lerpf(0.7, 0.2, spd_factor)
		_auto_timer.wait_time = randf_range(lo, hi)

## AI 策略: Expectimax 搜索 (期望最大化)
func _ai_pick_move() -> Vector2i:
	# 按熟练度决定失误率
	if randf() < _get_mistake_rate():
		var dirs = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]
		dirs.shuffle()
		for d in dirs:
			if _would_move(d):
				return d
		return Vector2i.ZERO

	# Expectimax 搜索 (空格少时加深)
	var empty_count = _count_empty_sim(_board)
	var depth = 3 if empty_count <= 6 else 2
	var best_dir = Vector2i.ZERO
	var best_score = -1e18
	for dir in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
		var sim = _sim_move(_board, dir)
		if not sim.moved:
			continue
		var score = _expectimax(sim.board, depth - 1, false)
		if score > best_score:
			best_score = score
			best_dir = dir
	return best_dir

## Expectimax 递归
func _expectimax(board: Array, depth: int, is_max: bool) -> float:
	if depth <= 0:
		return _eval_board(board)
	if is_max:
		var best = -1e18
		var any_moved = false
		for dir in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
			var sim = _sim_move(board, dir)
			if not sim.moved:
				continue
			any_moved = true
			best = maxf(best, _expectimax(sim.board, depth - 1, false))
		return best if any_moved else _eval_board(board)
	else:
		# 期望层: 枚举空格 x {2, 4}
		var empties: Array = []
		for y in range(GRID):
			for x in range(GRID):
				if board[y][x] == 0:
					empties.append(Vector2i(x, y))
		if empties.is_empty():
			return _eval_board(board)
		# 空格过多时采样 (性能)
		if empties.size() > 6:
			empties.shuffle()
			empties.resize(6)
		var total = 0.0
		for cell in empties:
			for val in [2, 4]:
				var prob = 0.9 if val == 2 else 0.1
				var nb = _copy_board(board)
				nb[cell.y][cell.x] = val
				total += prob * _expectimax(nb, depth - 1, true)
		return total / empties.size()

## 纯函数: 模拟移动 (不碰游戏状态)
func _sim_move(board: Array, dir: Vector2i) -> Dictionary:
	var nb: Array = []
	for y in range(GRID):
		nb.append(board[y].duplicate())
	var moved = false
	if dir.x != 0:
		for y in range(GRID):
			var line: Array = []
			for x in range(GRID): line.append(nb[y][x])
			if dir.x > 0: line.reverse()
			var res = _sim_compress(line)
			if dir.x > 0: res.reverse()
			for x in range(GRID):
				if nb[y][x] != res[x]: moved = true
				nb[y][x] = res[x]
	else:
		for x in range(GRID):
			var line: Array = []
			for y in range(GRID): line.append(nb[y][x])
			if dir.y > 0: line.reverse()
			var res = _sim_compress(line)
			if dir.y > 0: res.reverse()
			for y in range(GRID):
				if nb[y][x] != res[y]: moved = true
				nb[y][x] = res[y]
	return {board = nb, moved = moved}

## 压缩合并 (纯函数, 返回行数组)
func _sim_compress(line: Array) -> Array:
	var c: Array = []
	for v in line:
		if v != 0: c.append(v)
	var res: Array = []
	var i = 0
	while i < c.size():
		if i + 1 < c.size() and c[i] == c[i + 1]:
			res.append(c[i] * 2)
			i += 2
		else:
			res.append(c[i])
			i += 1
	while res.size() < GRID:
		res.append(0)
	return res

func _copy_board(board: Array) -> Array:
	var nb: Array = []
	for y in range(GRID):
		nb.append(board[y].duplicate())
	return nb

func _count_empty_sim(board: Array) -> int:
	var count = 0
	for y in range(GRID):
		for x in range(GRID):
			if board[y][x] == 0: count += 1
	return count

## 棋盘评估: 单调性 + 平滑度 + 空格数 + 角落奖励
func _eval_board(board: Array) -> float:
	var empty = 0
	var max_val = 0
	for y in range(GRID):
		for x in range(GRID):
			if board[y][x] == 0: empty += 1
			if board[y][x] > max_val: max_val = board[y][x]

	# 单调性: 行/列递增或递减倾向
	var mono = 0.0
	for y in range(GRID):
		var inc = 0.0; var dec = 0.0
		for x in range(GRID - 1):
			var a = _log2(board[y][x]); var b = _log2(board[y][x + 1])
			if a > b: dec += b - a
			else: inc += a - b
		mono += maxf(inc, dec)
	for x in range(GRID):
		var inc = 0.0; var dec = 0.0
		for y in range(GRID - 1):
			var a = _log2(board[y][x]); var b = _log2(board[y + 1][x])
			if a > b: dec += b - a
			else: inc += a - b
		mono += maxf(inc, dec)

	# 平滑度: 相邻差异惩罚
	var smooth = 0.0
	for y in range(GRID):
		for x in range(GRID):
			if board[y][x] > 0:
				var v = _log2(board[y][x])
				if x + 1 < GRID and board[y][x + 1] > 0:
					smooth -= absf(v - _log2(board[y][x + 1]))
				if y + 1 < GRID and board[y + 1][x] > 0:
					smooth -= absf(v - _log2(board[y + 1][x]))

	# 角落奖励
	var corner = 0.0
	if max_val == board[0][0] or max_val == board[0][3] or \
	   max_val == board[3][0] or max_val == board[3][3]:
		corner = _log2(max_val)

	return mono * 1.0 + smooth * 0.1 + float(empty) * 2.7 + corner * 1.0

func _log2(val: int) -> float:
	return log(val) / log(2) if val > 0 else 0.0

## 检测某个方向是否有效 (不修改状态)
func _would_move(dir: Vector2i) -> bool:
	var saved_board: Array = []
	for y in range(GRID):
		saved_board.append(_board[y].duplicate())
	var saved_score = _score
	var saved_2048 = _reached_2048
	# 模拟模式: 阻止副作用 (如 _say 话术触发)
	_simulating = true
	var data = _move_tracked(dir)
	var moved = data.moved
	# 恢复状态
	_simulating = false
	_board = saved_board
	_score = saved_score
	_reached_2048 = saved_2048
	return moved

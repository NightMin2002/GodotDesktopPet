# game.gd — 结构堆叠 (俄罗斯方块)
# 10x20 方块序列优化, 标准 Tetris 规则 + SRS 旋转 + 7-bag 随机
# 使用内嵌 _GridRenderer (Control) 自绘网格
extends BaseGame

# ── 常量 ──
const COLS := 10           # 列数
const ROWS := 20           # 行数 (可见区域)
const CELL := 16           # 每格像素
const FIELD_W := COLS * CELL
const FIELD_H := ROWS * CELL
const SIDEBAR_W := 60      # 侧栏宽度 (NEXT/HOLD)
const SIDEBAR_GAP := 8     # 侧栏与场地间距

# ── 方块定义 (SRS 标准) ──
# 每种方块 4 个旋转状态, 每个状态 4 个格子的偏移
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

# ── 游戏状态 ──
var _field: Array = []                  # 20行×10列, "" 或 方块类型名
var _current_type: String = ""          # 当前方块类型
var _current_rot: int = 0               # 当前旋转状态 (0~3)
var _current_pos: Vector2i = Vector2i.ZERO  # 当前方块左上角位置 (grid coords)
var _hold_type: String = ""             # 暂存方块类型
var _hold_used: bool = false            # 本次是否已使用暂存
var _bag: Array[String] = []            # 7-bag 随机队列
var _next_type: String = ""             # 下一个方块

var _score: int = 0
var _lines_cleared: int = 0
var _level: int = 1
var _drop_interval: float = 1.0        # 当前下落间隔
var _drop_timer: float = 0.0           # 下落计时
var _lock_timer: float = -1.0          # 锁定延迟计时 (<0=未着地)
var _lock_resets: int = 0              # 锁定重置次数
const MAX_LOCK_RESETS := 15
const LOCK_DELAY := 0.5
const MAX_LEVEL := 15          # 自玩满级主动结束

# DAS (Delayed Auto Shift)
var _das_dir: int = 0                  # -1=左, 0=无, 1=右
var _das_timer: float = 0.0
var _das_charged: bool = false
const DAS_DELAY := 0.170
const DAS_REPEAT := 0.050

# 软降
var _soft_drop: bool = false

# 消行动画
var _clearing_rows: Array[int] = []    # 正在消除的行号
var _clear_timer: float = -1.0
const CLEAR_DURATION := 0.25

# ── UI 引用 ──
var _panel: PanelContainer = null
var _grid_renderer = null
var _score_label: Label = null
var _level_label: Label = null
var _lines_label: Label = null

# ── 话术池 ──
const _POOL_START := [
	"结构优化开始。堆叠效率决定一切。",
	"方块序列已加载。操作员负责排列。",
	"逻辑堆叠训练。消行即正义。",
	"10x20 矩阵。填满即消除。",
]
const _POOL_CLEAR := [
	"结构消除。效率可接受。",
	"数据整理完成。",
	"...排列合理。",
	"行消除确认。",
]
const _POOL_TETRIS := [
	"四行同消。...运算效率不错。",
	"TETRIS 达成。本机已记录。",
	"完美消除。...不是在夸你。",
	"四线清除。操作员的空间推理还行。",
]
const _POOL_LEVEL_UP := [
	"速度提升。Lv.%d。跟上。",
	"...加速。反应时间测试。Lv.%d。",
	"频率上升。Lv.%d。",
]
const _POOL_LOSE := [
	"矩阵溢出。堆叠失败。",
	"...空间耗尽。结构崩塌。",
	"方块填满。操作员的极限到此为止。",
	"堆叠终止。最终评估: %d 行。",
	"溢出了。...本机记录在案。",
]

var _q_start: Array = []
var _q_clear: Array = []
var _q_tetris: Array = []
var _q_level_up: Array = []
var _q_lose: Array = []

# ══════════════════════════════════════════════
# 内嵌渲染器
# ══════════════════════════════════════════════

# ══════════════════════════════════════════════
# BaseGame 接口
# ══════════════════════════════════════════════

func get_game_id() -> String: return "tetris"
func get_game_name() -> String: return "结构堆叠"
func get_game_desc() -> String: return "方块序列优化。消除即正义。"
func get_default_panel_size() -> Vector2: return Vector2(FIELD_W + SIDEBAR_W + SIDEBAR_GAP + 28, 420)

func get_tutorial_steps() -> Array[Dictionary]:
	return [
		{"text": "方块会从顶部下落。"},
		{"text": "← → 移动，↑ 旋转，↓ 加速下落。"},
		{"text": "空格键硬降 — 方块直接落到底。"},
		{"text": "填满一整行即消除。四行同消 = TETRIS。"},
		{"text": "Shift 或 C — 暂存当前方块，下次取出。"},
		{"text": "方块堆到顶部就结束。...不复杂。"},
	]

func start() -> void:
	_load_scores()
	_build_ui()
	_reset_game()
	_say(_pick(_q_start, _POOL_START))

func cleanup() -> void:
	_stop_auto_play()
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_grid_renderer = null
	_score_label = null
	_level_label = null
	_lines_label = null
	super.cleanup()

# ══════════════════════════════════════════════
# UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	var skel = _create_panel_skeleton(FIELD_W + SIDEBAR_W + SIDEBAR_GAP + 28, {"left": 10, "right": 10, "top": 8, "bottom": 6, "separation": 4})
	_panel = skel.panel
	var vbox = skel.vbox

	# ── 顶部信息栏 ──
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	var hue = EventBus.ui_hue
	_score_label = Label.new()
	_score_label.text = "[ SCORE ] 0"
	_score_label.add_theme_font_size_override("font_size", 12)
	_score_label.add_theme_color_override("font_color", Color.from_hsv(fmod(hue + 0.05, 1.0), 0.5, 0.9, 0.9))
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_score_label)

	_level_label = Label.new()
	_level_label.text = "[ LV ] 1"
	_level_label.add_theme_font_size_override("font_size", 12)
	_level_label.add_theme_color_override("font_color", Color.from_hsv(fmod(hue + 0.15, 1.0), 0.45, 0.85, 0.8))
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_level_label)

	# ── 双方对比行 ──
	var my_best = SettingsManager.get_int(_score_key("best"), 0)
	var pet_best = SettingsManager.get_int(_other_score_key("best"), 0)
	_create_compare_row(vbox, "操作员: %d | 本机: %d" % [my_best, pet_best])

	# ── 游戏区域 (场地 + 侧栏) ──
	var grid_wrapper = CenterContainer.new()
	vbox.add_child(grid_wrapper)

	_grid_renderer = GridRenderer.new()
	_grid_renderer.game = self
	_grid_renderer.custom_minimum_size = Vector2(FIELD_W + SIDEBAR_GAP + SIDEBAR_W, FIELD_H)
	grid_wrapper.add_child(_grid_renderer)

	# ── 消行计数 ──
	_lines_label = Label.new()
	_lines_label.text = "[ LINE ] 0"
	_lines_label.add_theme_font_size_override("font_size", 12)
	_lines_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.6))
	_lines_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lines_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_lines_label)

	# ── 战绩标签 ──
	_score_label_rich = _create_score_rich_label()
	_update_score_rich()
	vbox.add_child(_score_label_rich)

	await _mount_panel(_panel)

var _score_label_rich: RichTextLabel = null

# ══════════════════════════════════════════════
# 游戏逻辑
# ══════════════════════════════════════════════

func _reset_game() -> void:
	# 初始化场地
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
	_game_over = false
	_hold_type = ""
	_hold_used = false
	_bag.clear()
	_clearing_rows.clear()
	_clear_timer = -1.0
	_das_dir = 0
	_das_timer = 0.0
	_das_charged = false
	_soft_drop = false

	_next_type = _bag_next()
	_spawn_piece()
	_update_labels()
	_hide_restart_bubble()
	if is_instance_valid(_grid_renderer):
		_grid_renderer.queue_redraw()

## 7-bag 随机: 从袋中取一个, 袋空则重新填充洗牌
func _bag_next() -> String:
	if _bag.is_empty():
		for p in PIECE_TYPES:
			_bag.append(p)
		_bag.shuffle()
	return _bag.pop_back()

## 生成新方块
func _spawn_piece() -> void:
	_current_type = _next_type
	_next_type = _bag_next()
	_current_rot = 0
	# 生成位置: 居中偏上
	_current_pos = Vector2i(3, 0)
	if _current_type == "I":
		_current_pos = Vector2i(3, -1)
	elif _current_type == "O":
		_current_pos = Vector2i(4, 0)
	_hold_used = false
	_lock_timer = -1.0
	_lock_resets = 0

	# 检查是否与已有方块重叠 → Game Over
	if not _is_valid_position(_current_type, _current_rot, _current_pos):
		_end_game()

## Hold 暂存
func _do_hold() -> void:
	if _hold_used:
		return
	_hold_used = true
	if _hold_type == "":
		_hold_type = _current_type
		_spawn_piece()
	else:
		var prev_hold = _hold_type
		_hold_type = _current_type
		_current_type = prev_hold
		_current_rot = 0
		_current_pos = Vector2i(3, 0)
		if _current_type == "I":
			_current_pos = Vector2i(3, -1)
		elif _current_type == "O":
			_current_pos = Vector2i(4, 0)
		_lock_timer = -1.0
		_lock_resets = 0

## 获取方块当前旋转状态下的格子世界坐标
func _get_cells(ptype: String, rot: int, pos: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in PIECES[ptype][rot]:
		cells.append(pos + offset)
	return cells

## 检查位置是否合法 (不越界, 不重叠)
func _is_valid_position(ptype: String, rot: int, pos: Vector2i) -> bool:
	for cell in _get_cells(ptype, rot, pos):
		if cell.x < 0 or cell.x >= COLS:
			return false
		if cell.y >= ROWS:
			return false
		# y < 0 允许 (方块还在顶部外面)
		if cell.y >= 0 and _field[cell.y][cell.x] != "":
			return false
	return true

## 尝试左右移动
func _try_move(dx: int) -> bool:
	var new_pos = _current_pos + Vector2i(dx, 0)
	if _is_valid_position(_current_type, _current_rot, new_pos):
		_current_pos = new_pos
		_reset_lock_if_grounded()
		return true
	return false

## 尝试下移一行
func _try_drop() -> bool:
	var new_pos = _current_pos + Vector2i(0, 1)
	if _is_valid_position(_current_type, _current_rot, new_pos):
		_current_pos = new_pos
		return true
	return false

## SRS 旋转
func _try_rotate(direction: int) -> bool:
	if _current_type == "O":
		return false  # O 方块不旋转
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

## 硬降: 直接落到底
func _hard_drop() -> void:
	var dist := 0
	while _try_drop():
		dist += 1
	_score += dist * 2
	_lock_piece()

## 计算 ghost piece 位置 (硬降投影)
func _get_ghost_pos() -> Vector2i:
	var ghost = _current_pos
	while _is_valid_position(_current_type, _current_rot, ghost + Vector2i(0, 1)):
		ghost += Vector2i(0, 1)
	return ghost

## 锁定方块到场地
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
		# 分数
		var pts := [0, 100, 300, 500, 800]
		_score += pts[mini(cleared.size(), 4)]
		# 话术
		if cleared.size() >= 4:
			_say(_pick(_q_tetris, _POOL_TETRIS))
		elif randf() < 0.2:
			_say(_pick(_q_clear, _POOL_CLEAR))
	else:
		_spawn_piece()

## 执行消行 (动画结束后调用)
func _do_clear_rows() -> void:
	# 从下往上删除已消行
	_clearing_rows.sort()
	_clearing_rows.reverse()
	for row_idx in _clearing_rows:
		_field.remove_at(row_idx)
	# 在顶部补空行
	for _i in range(_clearing_rows.size()):
		var empty_row: Array[String] = []
		empty_row.resize(COLS)
		empty_row.fill("")
		_field.insert(0, empty_row)

	_lines_cleared += _clearing_rows.size()
	# 更新等级
	var new_level = mini(_lines_cleared / 10 + 1, 15)
	if new_level > _level:
		var text = _pick(_q_level_up, _POOL_LEVEL_UP)
		if "%d" in text:
			_say(text % new_level)
		else:
			_say(text)
		_level = new_level
		_drop_interval = maxf(0.1, 1.0 - (_level - 1) * 0.1)
		# 自玩满级 → 主动收手
		if _auto_play and _level >= MAX_LEVEL:
			_clearing_rows.clear()
			_clear_timer = -1.0
			_end_game_maxed()
			return

	_clearing_rows.clear()
	_clear_timer = -1.0
	_update_labels()
	_spawn_piece()

## 锁定延迟重置 (着地状态下移动/旋转后调用)
func _reset_lock_if_grounded() -> void:
	if not _is_valid_position(_current_type, _current_rot, _current_pos + Vector2i(0, 1)):
		# 已着地
		if _lock_resets < MAX_LOCK_RESETS:
			_lock_timer = 0.0
			_lock_resets += 1

## 游戏结束 (溢出)
func _end_game() -> void:
	_game_over = true
	_persist_scores()
	# 话术
	var text = _pick(_q_lose, _POOL_LOSE)
	if "%d" in text:
		_say(text % _lines_cleared)
	else:
		_say(text)
	_update_labels()
	_show_restart_bubble()
	game_finished.emit(Result.LOSE)

## 自玩满级主动结束 (能力展示完成)
func _end_game_maxed() -> void:
	_game_over = true
	_persist_scores()
	if is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
		_pet.show_local_bubble("...自检完成。堆叠模块运行正常。")
	_update_labels()
	_show_restart_bubble()
	game_finished.emit(Result.WIN)

## 持久化战绩 (公用)
func _persist_scores() -> void:
	if _takeover:
		return  # 用户接管自玩局，战绩作废
	var best = SettingsManager.get_int(_score_key("best"), 0)
	if _score > best:
		SettingsManager.set_int(_score_key("best"), _score)
	var games = SettingsManager.get_int(_score_key("games"), 0) + 1
	SettingsManager.set_int(_score_key("games"), games)
	SettingsManager.set_int(_score_key("lines"), SettingsManager.get_int(_score_key("lines"), 0) + _lines_cleared)
	if _compare_label:
		var my_best_score = SettingsManager.get_int(_score_key("best"), 0)
		var pet_best_score = SettingsManager.get_int(_other_score_key("best"), 0)
		if _auto_play:
			_compare_label.text = "操作员: %d | 本机: %d" % [pet_best_score, my_best_score]
		else:
			_compare_label.text = "操作员: %d | 本机: %d" % [my_best_score, pet_best_score]
	_add_gaming_xp(5 + _lines_cleared / 10 * 5)
	_save_scores()
	_update_score_rich()

func _on_restart() -> void:
	_reset_game()
	_say(_pick(_q_start, _POOL_START))

func _on_close_extra_cleanup() -> void:
	_persist_scores()

func get_close_speech_pool() -> Array:
	return ["堆叠中断。...这算你放弃。"]

func get_auto_close_lines() -> Array:
	return ["...？", "...堆叠中断。", "结构优化被终止了。"]

# ══════════════════════════════════════════════
# 输入处理
# ══════════════════════════════════════════════

func _on_grid_input(event: InputEvent) -> void:
	if _game_over:
		return
	if _clear_timer >= 0.0:
		return  # 消行动画中禁止输入
	if _auto_play:
		if (event is InputEventKey and event.pressed and not event.echo) or \
		   (event is InputEventMouseButton and event.pressed):
			_stop_auto_play()
			return

	if not (event is InputEventKey):
		return

	var kc = event.keycode
	var pkc = event.physical_keycode

	if event.pressed:
		if not event.echo:
			# 单次按键
			if kc == KEY_UP or pkc == KEY_W:
				_try_rotate(1)
			elif kc == KEY_SPACE:
				_hard_drop()
			elif kc == KEY_SHIFT or pkc == KEY_C:
				_do_hold()
			elif kc == KEY_LEFT or pkc == KEY_A:
				_try_move(-1)
				_das_dir = -1
				_das_timer = 0.0
				_das_charged = false
			elif kc == KEY_RIGHT or pkc == KEY_D:
				_try_move(1)
				_das_dir = 1
				_das_timer = 0.0
				_das_charged = false
			elif kc == KEY_DOWN or pkc == KEY_S:
				_soft_drop = true
		else:
			# echo (长按) — DAS 在 _grid_process 中处理
			pass
	else:
		# 松键
		if kc == KEY_LEFT or pkc == KEY_A:
			if _das_dir == -1:
				_das_dir = 0
		elif kc == KEY_RIGHT or pkc == KEY_D:
			if _das_dir == 1:
				_das_dir = 0
		elif kc == KEY_DOWN or pkc == KEY_S:
			_soft_drop = false

# ══════════════════════════════════════════════
# 帧更新
# ══════════════════════════════════════════════

func _grid_process(delta: float) -> void:
	if _game_over:
		if is_instance_valid(_grid_renderer):
			_grid_renderer.queue_redraw()
		return

	# 消行动画
	if _clear_timer >= 0.0:
		_clear_timer += delta
		if _clear_timer >= CLEAR_DURATION:
			_do_clear_rows()
		if is_instance_valid(_grid_renderer):
			_grid_renderer.queue_redraw()
		return

	# DAS (长按连续移动)
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

	# 下落 (软降加速)
	var effective_interval = _drop_interval
	if _soft_drop:
		effective_interval = minf(_drop_interval, 0.05)
	_drop_timer += delta
	if _drop_timer >= effective_interval:
		_drop_timer = 0.0
		if not _try_drop():
			# 着地
			if _lock_timer < 0.0:
				_lock_timer = 0.0
		else:
			_lock_timer = -1.0  # 还在空中
			if _soft_drop:
				_score += 1

	# 锁定延迟
	if _lock_timer >= 0.0:
		# 检查是否还在着地状态
		if _is_valid_position(_current_type, _current_rot, _current_pos + Vector2i(0, 1)):
			# 不再着地 (移动后脱离)
			_lock_timer = -1.0
		else:
			_lock_timer += delta
			if _lock_timer >= LOCK_DELAY:
				_lock_piece()

	_update_labels()
	if is_instance_valid(_grid_renderer):
		_grid_renderer.queue_redraw()

# ══════════════════════════════════════════════
# 渲染
# ══════════════════════════════════════════════

func _render(canvas: Control) -> void:
	var hue = EventBus.ui_hue

	# ── 场地背景 ──
	var bg_c = Color.from_hsv(hue, 0.35, 0.06, 0.95)
	canvas.draw_rect(Rect2(0, 0, FIELD_W, FIELD_H), bg_c)

	# 扫描线
	var time = Time.get_ticks_msec() / 1000.0
	var scan_y = fmod(time * 30.0, FIELD_H + 30.0) - 15.0
	var c_band = Color.from_hsv(hue, 0.3, 0.9, 0.025)
	canvas.draw_rect(Rect2(0, scan_y, FIELD_W, 10.0), c_band)
	var c_core = Color.from_hsv(hue, 0.5, 1.0, 0.05)
	canvas.draw_rect(Rect2(0, scan_y + 4.0, FIELD_W, 1.0), c_core)

	# ── 网格刻度 (+) ──
	var grid_color = Color.from_hsv(hue, 0.2, 0.5, 0.10)
	for x in range(COLS + 1):
		for y in range(ROWS + 1):
			var px = x * CELL
			var py = y * CELL
			canvas.draw_line(Vector2(px - 2, py), Vector2(px + 2, py), grid_color, 1.0, true)
			canvas.draw_line(Vector2(px, py - 2), Vector2(px, py + 2), grid_color, 1.0, true)

	# ── 已固定方块 ──
	for y in range(ROWS):
		# 消行动画中跳过正在消除的行
		var in_clear = _clearing_rows.has(y)
		for x in range(COLS):
			if _field[y][x] != "":
				var cell_color = _get_piece_color(_field[y][x], false)
				if in_clear:
					# 消行闪白 + 收缩
					var t = clampf(_clear_timer / CLEAR_DURATION, 0.0, 1.0)
					cell_color = cell_color.lerp(Color.WHITE, (1.0 - t) * 0.6)
					var shrink = t * CELL * 0.5
					var rect = Rect2(x * CELL + shrink, y * CELL + shrink, CELL - shrink * 2, CELL - shrink * 2)
					if rect.size.x > 0 and rect.size.y > 0:
						canvas.draw_rect(rect, cell_color)
						canvas.draw_rect(rect, cell_color.darkened(0.4), false, 1.0)
				else:
					var rect = Rect2(x * CELL, y * CELL, CELL, CELL)
					canvas.draw_rect(rect, cell_color)
					canvas.draw_rect(rect, cell_color.darkened(0.4), false, 1.0)

	# ── Ghost piece (落地投影) ──
	if _current_type != "" and not _game_over and _clear_timer < 0.0:
		var ghost_pos = _get_ghost_pos()
		if ghost_pos != _current_pos:
			var ghost_color = _get_piece_color(_current_type, true)
			ghost_color.a = 0.15
			for cell in _get_cells(_current_type, _current_rot, ghost_pos):
				if cell.y >= 0:
					var rect = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
					canvas.draw_rect(rect, ghost_color)
					canvas.draw_rect(rect, ghost_color.lightened(0.3), false, 1.0)

	# ── 当前活动方块 ──
	if _current_type != "" and not _game_over and _clear_timer < 0.0:
		var active_color = _get_piece_color(_current_type, true)
		for cell in _get_cells(_current_type, _current_rot, _current_pos):
			if cell.y >= 0:
				var rect = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
				canvas.draw_rect(rect, active_color)
				canvas.draw_rect(rect, active_color.darkened(0.3), false, 1.0)

	# ── 场地边框 ──
	var border_c = Color.from_hsv(hue, 0.4, 0.7, 0.3)
	canvas.draw_rect(Rect2(0, 0, FIELD_W, FIELD_H), border_c, false, 1.0)

	# ── 侧栏 ──
	var sx = FIELD_W + SIDEBAR_GAP
	var dim_c = Color(0.4, 0.5, 0.6, 0.5)

	# NEXT 预览
	_draw_sidebar_label(canvas, sx, 0, "NEXT", hue)
	_draw_piece_preview(canvas, _next_type, sx, 18)

	# HOLD 预览
	_draw_sidebar_label(canvas, sx, 80, "HOLD", hue)
	_draw_piece_preview(canvas, _hold_type, sx, 98)

	# LINE 计数
	_draw_sidebar_label(canvas, sx, 160, "LINE", hue)
	var font = ThemeDB.fallback_font
	if font:
		canvas.draw_string(font, Vector2(sx + SIDEBAR_W / 2.0 - 8.0, 192.0), str(_lines_cleared), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.from_hsv(hue, 0.4, 0.9, 0.8))

	# ── Game Over 覆盖 ──
	if _game_over:
		canvas.draw_rect(Rect2(0, 0, FIELD_W, FIELD_H), Color(0.02, 0.0, 0.0, 0.6))
		if font:
			var go_c = Color.from_hsv(0.0, 0.6, 0.9, 0.8)
			canvas.draw_string(font, Vector2(FIELD_W / 2.0 - 36.0, FIELD_H / 2.0 - 8.0), "OVERFLOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, go_c)
			var sub_c = Color(0.5, 0.6, 0.7, 0.6)
			canvas.draw_string(font, Vector2(FIELD_W / 2.0 - 30.0, FIELD_H / 2.0 + 14.0), "SCORE: %d" % _score, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sub_c)

## 侧栏标签
func _draw_sidebar_label(canvas: Control, x: float, y: float, text: String, hue: float) -> void:
	var font = ThemeDB.fallback_font
	if font:
		var label_c = Color.from_hsv(hue, 0.3, 0.7, 0.5)
		canvas.draw_string(font, Vector2(x + 4.0, y + 12.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_c)

## 方块预览绘制
func _draw_piece_preview(canvas: Control, ptype: String, sx: float, sy: float) -> void:
	if ptype == "":
		return
	var cells = PIECES[ptype][0]
	var hue = EventBus.ui_hue
	var color = _get_piece_color(ptype, true)
	var ps := 10  # 预览格子大小
	# 计算中心偏移
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
	var ox = sx + (SIDEBAR_W - pw) / 2.0
	var oy = sy + (50 - ph) / 2.0

	for c in cells:
		var rx = ox + (c.x - min_x) * ps
		var ry = oy + (c.y - min_y) * ps
		canvas.draw_rect(Rect2(rx, ry, ps, ps), color)
		canvas.draw_rect(Rect2(rx, ry, ps, ps), color.darkened(0.3), false, 1.0)

## 获取方块颜色
func _get_piece_color(ptype: String, is_active: bool) -> Color:
	var hue = EventBus.ui_hue
	var offset = PIECE_HUE_OFFSETS.get(ptype, 0.0)
	var h = fmod(hue + offset, 1.0)
	if is_active:
		return Color.from_hsv(h, 0.6, 0.9, 0.95)
	else:
		return Color.from_hsv(h, 0.45, 0.7, 0.85)

## 更新标签
func _update_labels() -> void:
	if _score_label:
		_score_label.text = "[ SCORE ] %d" % _score
	if _level_label:
		_level_label.text = "[ LV ] %d" % _level
	if _lines_label:
		_lines_label.text = "[ LINE ] %d" % _lines_cleared

func _update_score_rich() -> void:
	if not _score_label_rich:
		return
	var hue = EventBus.ui_hue
	var dim = Color(0.4, 0.5, 0.6, 0.5).to_html(false)
	var best_c = Color.from_hsv(fmod(hue + 0.15, 1.0), 0.45, 0.85).to_html(false)
	var lose_c = Color(0.85, 0.35, 0.35).to_html(false)
	var best = SettingsManager.get_int(_score_key("best"), 0)
	var total_lines = SettingsManager.get_int(_score_key("lines"), 0)
	var game_count = SettingsManager.get_int(_score_key("games"), 0)
	_score_label_rich.text = (
		"[center][color=#" + dim + "]最高 [/color][color=#" + best_c + "]" + str(best)
		+ "[/color]    [color=#" + dim + "]总行 [/color][color=#" + best_c + "]" + str(total_lines)
		+ "[/color]    [color=#" + dim + "]局数 [/color][color=#" + lose_c + "]" + str(game_count)
		+ "[/color][/center]"
	)

# ══════════════════════════════════════════════
# 自动操作 (AI 自玩)
# ══════════════════════════════════════════════

func get_auto_start_lines() -> Array:
	return [
		"结构堆叠自主训练启动。",
		"...排列演练。",
		"自主堆叠开始。...想接手就按任意键。",
		"训练中。...观摩可以。",
	]

func get_auto_play_interval() -> float:
	var rate = _get_mistake_rate()
	return lerpf(0.08, 0.4, rate / 0.10)

func _get_takeover_lines() -> Array:
	return ["...你来？排列交给你。", "操作权移交。堆叠继续。"]

func _auto_play_step() -> void:
	if not _auto_play:
		return
	if _game_over:
		_auto_finish_and_close()
		return
	if _clear_timer >= 0.0:
		return

	# AI 决策: 找最优 (旋转, 列位)
	var best = _ai_find_best_placement()
	if best.is_empty():
		# 无解, 直接硬降
		_hard_drop()
		return

	var target_rot: int = best["rot"]
	var target_x: int = best["x"]

	# 随机失误
	if randf() < _get_mistake_rate():
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

## AI: 计算最优放置
func _ai_find_best_placement() -> Dictionary:
	var best_score := -99999.0
	var best := {}

	for rot in range(4):
		# 找出该旋转下的所有可达列位
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
			# 模拟硬降
			while _is_valid_position(_current_type, rot, pos + Vector2i(0, 1)):
				pos += Vector2i(0, 1)
			# 锁定到临时场地
			var temp_field = _copy_field()
			var piece_cells = _get_cells(_current_type, rot, pos)
			for cell in piece_cells:
				if cell.y >= 0 and cell.y < ROWS and cell.x >= 0 and cell.x < COLS:
					temp_field[cell.y][cell.x] = _current_type
			# 评估
			var eval_score = _evaluate_field(temp_field)
			if eval_score > best_score:
				best_score = eval_score
				best = {"rot": rot, "x": col}

	return best

## 复制场地
func _copy_field() -> Array:
	var copy: Array = []
	for row in _field:
		copy.append(row.duplicate())
	return copy

## AI 评估函数
func _evaluate_field(field: Array) -> float:
	var aggregate_height := 0
	var complete_lines := 0
	var holes := 0
	var bumpiness := 0

	var heights: Array[int] = []
	heights.resize(COLS)

	# 每列高度
	for x in range(COLS):
		var h := 0
		for y in range(ROWS):
			if field[y][x] != "":
				h = ROWS - y
				break
		heights[x] = h
		aggregate_height += h

	# 完整行数
	for y in range(ROWS):
		var full := true
		for x in range(COLS):
			if field[y][x] == "":
				full = false
				break
		if full:
			complete_lines += 1

	# 空洞数
	for x in range(COLS):
		var found_block := false
		for y in range(ROWS):
			if field[y][x] != "":
				found_block = true
			elif found_block:
				holes += 1

	# 凹凸度
	for x in range(COLS - 1):
		bumpiness += absi(heights[x] - heights[x + 1])

	return -0.51 * aggregate_height + 0.76 * complete_lines * 10.0 - 0.36 * holes - 0.18 * bumpiness

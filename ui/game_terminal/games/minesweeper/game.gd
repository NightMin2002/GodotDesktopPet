# game.gd — 终端扫雷 (威胁评估)
# 直接在游戏终端内容区渲染，_draw 自绘
# 自包含: 雷区 + 输入 + 洪泛揭开 + 结算覆盖 + 重开按钮
extends TerminalGameBase

func get_game_id() -> String: return "minesweeper"
func get_game_name() -> String: return "威胁评估"
func get_game_desc() -> String: return "9x9 雷区扫描"
func supports_auto_play() -> bool: return true

# ── 棋盘参数 ──
const COLS := 9
const ROWS := 9
const MINE_COUNT := 10

# ── 单元格状态 ──
# _mines[i]: true=有雷
# _revealed[i]: true=已揭开
# _flagged[i]: true=已插旗
# _adjacent[i]: 相邻雷数 (0-8)
var _mines: Array = []
var _revealed: Array = []
var _flagged: Array = []
var _adjacent: Array = []

# ── 游戏状态 ──
var _game_active: bool = false
var _first_click: bool = true  # 首次点击保证不踩雷
var _result: int = -1           # 0=胜, 1=负
var _hover_cell: int = -1
var _time: float = 0.0
var _mines_remaining: int = MINE_COUNT  # 剩余标记数
var _revealed_count: int = 0
var _death_cell: int = -1  # 踩到的雷的格位

# ── 布局缓存 ──
var _grid_origin: Vector2 = Vector2.ZERO
var _cell_size: float = 0.0

# ── 结算覆盖 ──
var _result_overlay: PanelContainer
var _result_label: Label
var _restart_btn: Button

func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	gui_input.connect(_on_input)
	_build_result_overlay()
	start_game()

## HUD 协议: 剩余雷数 + 用时
func get_hud_data() -> Dictionary:
	var remain_c = GameTerminalStyles.status_warning() if _mines_remaining > 0 else GameTerminalStyles.status_active()
	var time_str = "%02d:%02d" % [int(_time) / 60, int(_time) % 60]
	return {
		"mines": { "label": "MINES", "value": str(_mines_remaining), "color": remain_c },
		"time": { "label": "TIME", "value": time_str, "color": GameTerminalStyles.dim() },
	}

## 自玩 AI: 每步操作
func auto_play_step() -> void:
	if not _game_active:
		return
	# 首次点击: 随机选一个格子
	if _first_click:
		var cell = randi() % (COLS * ROWS)
		_on_reveal(cell)
		return
	# 策略: 找已揭开数字格周围的确定安全格
	var safe_cells: Array[int] = []
	var flaggable: Array[int] = []
	for i in range(COLS * ROWS):
		if not _revealed[i] or _mines[i] or _adjacent[i] <= 0:
			continue
		# 数周围未揭开/未插旗的格子
		var hidden: Array[int] = []
		var flags := 0
		for n in _neighbors(i):
			if _flagged[n]:
				flags += 1
			elif not _revealed[n]:
				hidden.append(n)
		if hidden.is_empty():
			continue
		# 旗帜数 == 数字: 周围所有隐藏格都安全
		if flags == _adjacent[i]:
			for h in hidden:
				if h not in safe_cells:
					safe_cells.append(h)
		# 隐藏格 + 旗帜 == 数字: 所有隐藏格都是雷
		elif hidden.size() + flags == _adjacent[i]:
			for h in hidden:
				if not _flagged[h] and h not in flaggable:
					flaggable.append(h)
	# 优先揭开安全格
	if safe_cells.size() > 0:
		_on_reveal(safe_cells[randi() % safe_cells.size()])
		return
	# 插旗
	if flaggable.size() > 0:
		_on_flag(flaggable[randi() % flaggable.size()])
		return
	# 兜底: 随机揭开一个未揭开未插旗的格子
	var unknown: Array[int] = []
	for i in range(COLS * ROWS):
		if not _revealed[i] and not _flagged[i]:
			unknown.append(i)
	if unknown.size() > 0:
		_on_reveal(unknown[randi() % unknown.size()])

func _process(delta: float) -> void:
	_time += delta
	if _game_active or _death_cell >= 0:
		queue_redraw()

func start_game() -> void:
	_mines = []
	_revealed = []
	_flagged = []
	_adjacent = []
	_mines.resize(COLS * ROWS)
	_revealed.resize(COLS * ROWS)
	_flagged.resize(COLS * ROWS)
	_adjacent.resize(COLS * ROWS)
	for i in range(COLS * ROWS):
		_mines[i] = false
		_revealed[i] = false
		_flagged[i] = false
		_adjacent[i] = 0
	_game_active = true
	_first_click = true
	_result = -1
	_hover_cell = -1
	_death_cell = -1
	_mines_remaining = MINE_COUNT
	_revealed_count = 0
	_time = 0.0
	if is_instance_valid(_result_overlay):
		_result_overlay.visible = false
	game_started.emit()
	queue_redraw()

# ══════════════════════════════════════════════
#  布局计算
# ══════════════════════════════════════════════

func _calc_layout() -> void:
	var w = size.x
	var h = size.y
	# 上方留空间给状态栏
	var header_h = 28.0
	var avail_w = w - 16.0  # 两侧 8px 边距
	var avail_h = h - header_h - 8.0
	_cell_size = minf(avail_w / COLS, avail_h / ROWS)
	var grid_w = _cell_size * COLS
	var grid_h = _cell_size * ROWS
	_grid_origin = Vector2(
		(w - grid_w) * 0.5,
		header_h + (avail_h - grid_h) * 0.5
	)

func _cell_rect(idx: int) -> Rect2:
	var col = idx % COLS
	var row = idx / COLS
	return Rect2(
		_grid_origin + Vector2(col * _cell_size, row * _cell_size),
		Vector2(_cell_size, _cell_size)
	)

func _cell_at(pos: Vector2) -> int:
	for i in range(COLS * ROWS):
		if _cell_rect(i).has_point(pos):
			return i
	return -1

func _neighbors(idx: int) -> Array[int]:
	var result: Array[int] = []
	var col = idx % COLS
	var row = idx / COLS
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var nr = row + dr
			var nc = col + dc
			if nr >= 0 and nr < ROWS and nc >= 0 and nc < COLS:
				result.append(nr * COLS + nc)
	return result

# ══════════════════════════════════════════════
#  雷区生成
# ══════════════════════════════════════════════

func _generate_mines(safe_cell: int) -> void:
	# 首次点击的格子及其周围保证安全
	var safe_zone: Array[int] = [safe_cell]
	safe_zone.append_array(_neighbors(safe_cell))

	var candidates: Array[int] = []
	for i in range(COLS * ROWS):
		if i not in safe_zone:
			candidates.append(i)

	# 随机选雷
	candidates.shuffle()
	for i in range(mini(MINE_COUNT, candidates.size())):
		_mines[candidates[i]] = true

	# 计算每格相邻雷数
	for i in range(COLS * ROWS):
		if _mines[i]:
			_adjacent[i] = -1
			continue
		var count = 0
		for n in _neighbors(i):
			if _mines[n]:
				count += 1
		_adjacent[i] = count

# ══════════════════════════════════════════════
#  输入
# ══════════════════════════════════════════════

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var old = _hover_cell
		_hover_cell = _cell_at(event.position)
		if _hover_cell != old:
			queue_redraw()
		return

	if not _game_active:
		return

	if event is InputEventMouseButton and event.pressed:
		var cell = _cell_at(event.position)
		if cell < 0:
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_reveal(cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_flag(cell)

func _on_reveal(cell: int) -> void:
	if _flagged[cell] or _revealed[cell]:
		return

	# 首次点击: 生成雷区
	if _first_click:
		_first_click = false
		_generate_mines(cell)

	if _mines[cell]:
		# 踩雷
		_death_cell = cell
		_game_active = false
		_reveal_all_mines()
		_result = 1
		_show_result()
		game_over.emit(1)
		return

	# 洪泛揭开
	_flood_reveal(cell)
	_check_win()

func _on_flag(cell: int) -> void:
	if _revealed[cell]:
		return
	_flagged[cell] = not _flagged[cell]
	_mines_remaining += -1 if _flagged[cell] else 1
	queue_redraw()

func _flood_reveal(cell: int) -> void:
	if cell < 0 or cell >= COLS * ROWS:
		return
	if _revealed[cell] or _flagged[cell] or _mines[cell]:
		return
	_revealed[cell] = true
	_revealed_count += 1
	# 空格递归展开
	if _adjacent[cell] == 0:
		for n in _neighbors(cell):
			_flood_reveal(n)

func _reveal_all_mines() -> void:
	for i in range(COLS * ROWS):
		if _mines[i]:
			_revealed[i] = true

func _check_win() -> void:
	# 所有非雷格都揭开 = 胜利
	if _revealed_count >= COLS * ROWS - MINE_COUNT:
		_game_active = false
		_result = 0
		# 自动标记所有未标旗的雷
		for i in range(COLS * ROWS):
			if _mines[i] and not _flagged[i]:
				_flagged[i] = true
		_mines_remaining = 0
		_show_result()
		game_over.emit(0)

# ══════════════════════════════════════════════
#  结算覆盖层
# ══════════════════════════════════════════════

func _build_result_overlay() -> void:
	var d = GameTerminalStyles.create_result_overlay("[ 重新扫描 ]", start_game)
	_result_overlay = d.overlay
	_result_label = d.label
	_restart_btn = d.btn
	add_child(_result_overlay)

var _result_lines_win := ["区域已肃清。", "威胁已全部标记。", "扫描完毕。零遗漏。"]
var _result_lines_lose := ["触发未知装置。", "扫描中断。损失已记录。", "...危险区域踩踏。"]

func _show_result() -> void:
	if not is_instance_valid(_result_overlay):
		return
	var lines = _result_lines_win if _result == 0 else _result_lines_lose
	var c = GameTerminalStyles.status_active() if _result == 0 else Color(0.9, 0.35, 0.3, 0.9)
	GameTerminalStyles.show_result_overlay(_result_overlay, _result_label, lines[randi() % lines.size()], c)

# ══════════════════════════════════════════════
#  渲染
# ══════════════════════════════════════════════

# 数字颜色 (1-8)
const NUM_COLORS := [
	Color(0.3, 0.6, 1.0),    # 1 — 蓝
	Color(0.2, 0.75, 0.3),   # 2 — 绿
	Color(0.95, 0.3, 0.3),   # 3 — 红
	Color(0.5, 0.25, 0.85),  # 4 — 紫
	Color(0.85, 0.45, 0.2),  # 5 — 橙
	Color(0.2, 0.8, 0.8),    # 6 — 青
	Color(0.7, 0.7, 0.7),    # 7 — 灰
	Color(0.9, 0.9, 0.5),    # 8 — 黄
]

func _draw() -> void:
	_calc_layout()
	var hue = EventBus.ui_hue
	var font = ThemeDB.fallback_font

	# ── 顶部 HUD ──
	if font:
		var lbl_c = Color.from_hsv(hue, 0.3, 0.7, 0.5)
		var remain_c = GameTerminalStyles.status_warning() if _mines_remaining > 0 else GameTerminalStyles.status_active()
		var time_str = "%02d:%02d" % [int(_time) / 60, int(_time) % 60]
		# 左: MINES
		draw_string(font, Vector2(_grid_origin.x, _grid_origin.y - 10.0), "MINES",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lbl_c)
		draw_string(font, Vector2(_grid_origin.x + 46, _grid_origin.y - 10.0), str(_mines_remaining),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, remain_c)
		# 右: TIME
		var grid_w = _cell_size * COLS
		draw_string(font, Vector2(_grid_origin.x + grid_w - 80, _grid_origin.y - 10.0), "TIME",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lbl_c)
		draw_string(font, Vector2(_grid_origin.x + grid_w - 42, _grid_origin.y - 10.0), time_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameTerminalStyles.dim())

	# ── 网格 ──
	for i in range(COLS * ROWS):
		var cr = _cell_rect(i)
		var inr = cr.grow(-1)  # 内部区域 (留 1px 间距)

		if _revealed[i]:
			# 已揭开
			if _mines[i]:
				# 雷
				var mine_bg = Color(0.3, 0.05, 0.05, 0.7) if i == _death_cell else Color(0.08, 0.06, 0.04, 0.5)
				draw_rect(inr, mine_bg)
				_draw_mine(cr, hue)
			else:
				# 空地/数字
				draw_rect(inr, Color(0.03, 0.04, 0.07, 0.3))
				if _adjacent[i] > 0:
					_draw_number(cr, _adjacent[i])
		else:
			# 未揭开
			var base_bg = Color(0.06, 0.08, 0.14, 0.6)
			# 悬停高亮
			if i == _hover_cell and _game_active:
				base_bg = Color(0.10, 0.14, 0.22, 0.7)
			draw_rect(inr, base_bg)
			# 暗色网格纹理
			draw_rect(inr, Color(0.12, 0.16, 0.24, 0.15), false, 0.5)

			if _flagged[i]:
				_draw_flag(cr, hue)

	# ── 网格线 ──
	var grid_c = Color.from_hsv(hue, 0.3, 0.4, 0.12)
	for c in range(COLS + 1):
		var x = _grid_origin.x + c * _cell_size
		draw_line(Vector2(x, _grid_origin.y), Vector2(x, _grid_origin.y + ROWS * _cell_size), grid_c, 0.5)
	for r in range(ROWS + 1):
		var y = _grid_origin.y + r * _cell_size
		draw_line(Vector2(_grid_origin.x, y), Vector2(_grid_origin.x + COLS * _cell_size, y), grid_c, 0.5)

	# ── 外框 ──
	var frame_c = Color.from_hsv(hue, 0.4, 0.6, 0.2)
	draw_rect(Rect2(_grid_origin, Vector2(COLS * _cell_size, ROWS * _cell_size)), frame_c, false, 1.0)

# ── 绘制地雷 ──
func _draw_mine(cr: Rect2, hue: float) -> void:
	var center = cr.get_center()
	var r = _cell_size * 0.28
	# 外圈泛光
	draw_circle(center, r + 3, Color(0.9, 0.2, 0.15, 0.15), true, -1.0, true)
	# 核心
	draw_circle(center, r, Color(0.9, 0.25, 0.2, 0.85), true, -1.0, true)
	# 十字刺
	var spike_c = Color(0.95, 0.3, 0.25, 0.7)
	var spike_len = r * 1.5
	draw_line(center - Vector2(spike_len, 0), center + Vector2(spike_len, 0), spike_c, 1.5, true)
	draw_line(center - Vector2(0, spike_len), center + Vector2(0, spike_len), spike_c, 1.5, true)
	# 对角刺
	var diag = spike_len * 0.7
	draw_line(center - Vector2(diag, diag), center + Vector2(diag, diag), spike_c, 1.0, true)
	draw_line(center - Vector2(diag, -diag), center + Vector2(diag, -diag), spike_c, 1.0, true)
	# 高光点
	draw_circle(center + Vector2(-r * 0.3, -r * 0.3), r * 0.2, Color(1.0, 0.6, 0.5, 0.6), true, -1.0, true)

# ── 绘制数字 ──
func _draw_number(cr: Rect2, num: int) -> void:
	var font = ThemeDB.fallback_font
	var text = str(num)
	var c = NUM_COLORS[clampi(num - 1, 0, 7)]
	var font_size = int(_cell_size * 0.55)
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos = cr.get_center() - text_size * 0.5 + Vector2(0, text_size.y * 0.35)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)

# ── 绘制旗帜 ──
func _draw_flag(cr: Rect2, hue: float) -> void:
	var center = cr.get_center()
	var s = _cell_size * 0.25
	var flag_c = Color.from_hsv(hue, 0.6, 0.9, 0.9)
	# 旗杆
	var pole_top = center + Vector2(0, -s * 1.2)
	var pole_bottom = center + Vector2(0, s * 0.8)
	draw_line(pole_top, pole_bottom, Color(0.7, 0.8, 0.9, 0.7), 1.5, true)
	# 旗面 (三角形)
	var flag_pts = PackedVector2Array([
		pole_top,
		pole_top + Vector2(s * 1.2, s * 0.5),
		pole_top + Vector2(0, s * 1.0),
	])
	draw_colored_polygon(flag_pts, flag_c)
	# 底座
	draw_line(center + Vector2(-s * 0.6, s * 0.8), center + Vector2(s * 0.6, s * 0.8), Color(0.5, 0.6, 0.7, 0.5), 2.0, true)

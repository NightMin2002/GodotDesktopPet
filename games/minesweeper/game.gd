# game.gd — 威胁评估 (扫雷)
# 9x9 区域扫描小游戏，经典扫雷规则
# UI 使用 Godot Control 节点树 (GridContainer + Panel 格子)
# 与井字棋的 Canvas 自绘方式形成互补，验证 SubViewport 通用性
extends BaseGame

# ── 常量 ──
const COLS := 9
const ROWS := 9
const MINE_COUNT := 10
const CELL_SIZE := 30  # 每个格子的边长 (px)

# ── 数字颜色生成辅助 ──
func _get_num_color(num: int, hue: float) -> Color:
	match num:
		1: return Color.from_hsv(hue, 0.2, 0.8, 0.9)
		2: return Color.from_hsv(hue, 0.4, 0.9, 1.0)
		3: return Color.from_hsv(fmod(hue + 0.9, 1.0), 0.6, 0.95, 1.0) # -> hue - 0.1 (yellow/orange)
		4: return Color.from_hsv(fmod(hue + 0.8, 1.0), 0.8, 1.0, 1.0) # -> hue - 0.2 (red/purple)
		5: return Color.from_hsv(fmod(hue + 0.1, 1.0), 0.8, 1.0, 1.0) # -> hue + 0.1
		_: return Color(1.0, 0.2, 0.2, 1.0) # 6-8 高危红色

# ── 游戏状态 ──
var _mines: Array[bool] = []       # 是否有雷
var _revealed: Array[bool] = []    # 是否已揭开
var _flagged: Array[bool] = []     # 是否插旗
var _adjacent: Array[int] = []     # 周围雷数 (0-8)

var _game_won: bool = false
var _first_click: bool = true      # 首次点击保证不踩雷
var _remaining: int = 0            # 剩余非雷格子数
var _flag_count: int = 0           # 已插旗数

# ── 计时 ──
var _timer_running: bool = false
var _elapsed: float = 0.0
var _timer_label: Label = null


# ── UI 引用 ──
var _panel: PanelContainer = null
var _grid_container: GridContainer = null
var _cells: Array[PanelContainer] = []  # 81 个格子面板
var _cell_labels: Array[Label] = []     # 81 个格子文字
var _score_label: RichTextLabel = null
var _mine_count_label: Label = null

# ── 拖拽 ──
# (已统一到 BaseGame._on_panel_input)

# (_wins/_losses 已统一到 BaseGame)
# ── 动画 ──
var _exploded_cell: int = -1  # 爆炸格子索引
var _hover_idx: int = -1       # 鼠标悬停格子

# ── 自动操作 (AI 自玩) ──
# (_auto_play / _auto_timer 已在 BaseGame 中)

# ── 话术池 (洗牌防重复) ──
const _POOL_START := [
	"区域扫描初始化。请标记威胁源。",
	"威胁评估协议启动。",
	"新区域已部署。开始排查。",
	"扫描区域就绪。操作员请落点。",
	"评估协议已重置。",
]
const _POOL_SAFE := [
	"安全区确认。",
	"无威胁。",
	"...继续。",
	"落点清除。",
	"该区域已排除。",
	"安全。",
]
const _POOL_FLAG := [
	"威胁标记已记录。",
	"标记完成。",
	"...记录在案。",
	"威胁源已锁定。",
]
const _POOL_UNFLAG := [
	"标记已撤销。",
	"...取消标记。",
]
const _POOL_LOSE := [
	"...排查失败。操作员的概率判断有待校准。",
	"爆破触发。建议复习贝叶斯定理。",
	"...轰。本机已记录数据。",
	"检测到致命失误。评估中止。",
	"...区域已损毁。错误率 +1。",
	"操作员引爆了威胁源。...遗憾。",
]
const _POOL_WIN := [
	"区域已清除。...效率尚可。",
	"零误判。...超出预期。仅此一次。",
	"全区排查完毕。评估结果：合格。",
	"...完美清除。本机表示肯定。",
	"威胁源已全部标定。操作员通过评估。",
]
const _POOL_CLOSE_MID := [
	"评估中断。...这算你放弃。",
	"未完成的扫描。记录为失败。",
]

var _q_start: Array = []
var _q_safe: Array = []
var _q_flag: Array = []
var _q_unflag: Array = []
var _q_lose: Array = []
var _q_win: Array = []

# _pick() 已统一到 BaseGame 基类

# ── BaseGame 接口 ──

func get_game_id() -> String: return "minesweeper"
func get_game_name() -> String: return "威胁评估"
func get_game_desc() -> String: return "区域扫描"

func get_tutorial_steps() -> Array[Dictionary]:
	return [
		{"text": "左键点击格子 → 揭开该区域"},
		{"text": "数字 = 周围 8 格内的威胁源数量"},
		{"text": "右键点击 → 插旗标记疑似威胁源"},
		{"text": "揭开所有安全区域即可通过评估"},
		{"text": "首次点击保证安全，不会引爆"},
	]

func get_default_panel_size() -> Vector2:
	return Vector2(310, 500)

func start() -> void:
	_load_scores()
	_build_ui()
	_reset_game()
	_say(_pick(_q_start, _POOL_START))

func cleanup() -> void:
	_timer_running = false
	_stop_auto_play()
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_grid_container = null
	_cells.clear()
	_cell_labels.clear()
	_score_label = null
	_mine_count_label = null
	_timer_label = null
	super.cleanup()  # 清理悬浮组件 + 教程面板

# ══════════════════════════════════════════════
# UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(COLS * CELL_SIZE + 32, 0)

	# 面板背景
	_panel.add_theme_stylebox_override("panel", _create_game_panel_bg())

	var outer = MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 14)
	outer.add_theme_constant_override("margin_right", 14)
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_bottom", 4)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(outer)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(vbox)

	# ── 信息栏 (剩余雷数 + 计时) ──
	var info_wrapper = PanelContainer.new()
	info_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info_bg = StyleBoxFlat.new()
	info_bg.bg_color = Color(0.02, 0.03, 0.08, 0.8) # 机能风暗背景
	info_bg.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.7, 0.3)
	info_bg.set_border_width_all(1)
	info_bg.set_corner_radius_all(0) # 直角
	info_bg.content_margin_left = 10
	info_bg.content_margin_right = 10
	info_bg.content_margin_top = 4
	info_bg.content_margin_bottom = 4
	info_wrapper.add_theme_stylebox_override("panel", info_bg)

	var info_bar = HBoxContainer.new()
	info_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_bar.add_theme_constant_override("separation", 8)

	_mine_count_label = Label.new()
	_mine_count_label.text = "[ THREAT ]  %02d" % MINE_COUNT
	_mine_count_label.add_theme_font_size_override("font_size", 13)
	_mine_count_label.add_theme_color_override("font_color", Color.from_hsv(fmod(EventBus.ui_hue + 0.05, 1.0), 0.5, 0.9, 0.9))
	_mine_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mine_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_bar.add_child(_mine_count_label)

	_timer_label = Label.new()
	_timer_label.text = "[ TIME ]  00:00"
	_timer_label.add_theme_font_size_override("font_size", 13)
	_timer_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75, 0.8))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_bar.add_child(_timer_label)

	info_wrapper.add_child(info_bar)
	vbox.add_child(info_wrapper)

	# ── 双方对比行 ──
	var my_w = SettingsManager.get_int(_score_key("wins"), 0)
	var my_l = SettingsManager.get_int(_score_key("losses"), 0)
	var pet_w = SettingsManager.get_int(_other_score_key("wins"), 0)
	var pet_l = SettingsManager.get_int(_other_score_key("losses"), 0)
	_compare_label = Label.new()
	_compare_label.text = "操作员: %d/%d | 本机: %d/%d" % [my_w, my_w + my_l, pet_w, pet_w + pet_l]
	_compare_label.add_theme_font_size_override("font_size", 11)
	_compare_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.6))
	_compare_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compare_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_compare_label)

	# ── 雷区格子 (Control 节点树方式) ──
	var grid_wrapper = CenterContainer.new()
	grid_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_grid_container = GridContainer.new()
	_grid_container.columns = COLS
	# 极简激光网格：更小的缝隙
	_grid_container.add_theme_constant_override("h_separation", 1)
	_grid_container.add_theme_constant_override("v_separation", 1)
	_grid_container.mouse_filter = Control.MOUSE_FILTER_STOP

	_cells.clear()
	_cell_labels.clear()
	for i in range(ROWS * COLS):
		var cell = PanelContainer.new()
		cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# 取消棋盘格，采用全息冷感单色
		var cell_bg = StyleBoxFlat.new()
		cell_bg.bg_color = Color(0.04, 0.05, 0.1, 0.7)
		cell_bg.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.15)
		cell_bg.set_border_width_all(1)
		cell_bg.set_corner_radius_all(0) # 直角机能风
		cell_bg.set_content_margin_all(0)
		cell.add_theme_stylebox_override("panel", cell_bg)
		# 格子文字 (数字/旗/雷)
		var lbl = Label.new()
		lbl.text = ""
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(lbl)
		# 交互信号 + hover
		var idx = i  # 闭包捕获
		cell.gui_input.connect(func(event: InputEvent): _on_cell_input(idx, event))
		cell.mouse_entered.connect(func(): _on_cell_hover(idx))
		cell.mouse_exited.connect(func(): _on_cell_unhover(idx))
		_grid_container.add_child(cell)
		_cells.append(cell)
		_cell_labels.append(lbl)

	grid_wrapper.add_child(_grid_container)
	vbox.add_child(grid_wrapper)

	# ── 战绩 ──
	var score_rich = RichTextLabel.new()
	score_rich.bbcode_enabled = true
	score_rich.fit_content = true
	score_rich.scroll_active = false
	score_rich.custom_minimum_size = Vector2(0, 20)
	score_rich.add_theme_font_size_override("normal_font_size", 12)
	score_rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_label = score_rich
	_update_score_label()
	vbox.add_child(score_rich)

	# ── 输入处理 + 挂载 + 弹入动画 + 悬浮组件 (统一流程)
	await _mount_panel(_panel)

	# 启动计时器 process
	_panel.set_process(true)
	_panel.set_meta("_game_ref", self)
	if not _panel.is_inside_tree():
		await _panel.tree_entered
	_start_timer_loop()

func _start_timer_loop() -> void:
	while is_instance_valid(_panel) and _panel.is_inside_tree():
		await _panel.get_tree().process_frame
		if _timer_running:
			_elapsed += _panel.get_process_delta_time()
			if _timer_label:
				var mins = int(_elapsed) / 60
				var secs = int(_elapsed) % 60
				_timer_label.text = "[ TIME ]  %02d:%02d" % [mins, secs]

# ══════════════════════════════════════════════
# 游戏逻辑
# ══════════════════════════════════════════════

func _reset_game() -> void:
	_mines.clear()
	_revealed.clear()
	_flagged.clear()
	_adjacent.clear()
	_mines.resize(ROWS * COLS)
	_revealed.resize(ROWS * COLS)
	_flagged.resize(ROWS * COLS)
	_adjacent.resize(ROWS * COLS)
	_mines.fill(false)
	_revealed.fill(false)
	_flagged.fill(false)
	_adjacent.fill(0)
	_game_over = false
	_game_won = false
	_first_click = true
	_remaining = ROWS * COLS - MINE_COUNT
	_flag_count = 0
	_exploded_cell = -1
	_hover_idx = -1
	_elapsed = 0.0
	_timer_running = false
	if _timer_label:
		_timer_label.text = "[ TIME ]  00:00"
	if _mine_count_label:
		_mine_count_label.text = "[ THREAT ]  %02d" % MINE_COUNT
	_hide_restart_bubble()
	_refresh_all_cells()

func _generate_mines(safe_idx: int) -> void:
	# 首次点击位置及周围 8 格不放雷
	var safe_set: Dictionary = {}
	safe_set[safe_idx] = true
	var sr = safe_idx / COLS
	var sc = safe_idx % COLS
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			var nr = sr + dr
			var nc = sc + dc
			if nr >= 0 and nr < ROWS and nc >= 0 and nc < COLS:
				safe_set[nr * COLS + nc] = true
	# 随机放雷
	var candidates: Array[int] = []
	for i in range(ROWS * COLS):
		if not safe_set.has(i):
			candidates.append(i)
	candidates.shuffle()
	for i in range(mini(MINE_COUNT, candidates.size())):
		_mines[candidates[i]] = true
	# 计算相邻雷数
	for r in range(ROWS):
		for c in range(COLS):
			if _mines[r * COLS + c]:
				_adjacent[r * COLS + c] = -1
				continue
			var count := 0
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					if dr == 0 and dc == 0:
						continue
					var nr = r + dr
					var nc = c + dc
					if nr >= 0 and nr < ROWS and nc >= 0 and nc < COLS:
						if _mines[nr * COLS + nc]:
							count += 1
			_adjacent[r * COLS + c] = count

func _on_cell_input(idx: int, event: InputEvent) -> void:
	if _game_over:
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	# 用户输入 -> 接管自动操作
	if _auto_play:
		_stop_auto_play()
	if event.button_index == MOUSE_BUTTON_LEFT:
		_reveal_cell(idx)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_toggle_flag(idx)

func _reveal_cell(idx: int) -> void:
	if _revealed[idx] or _flagged[idx]:
		return
	if _first_click:
		_first_click = false
		_generate_mines(idx)
		_timer_running = true
	if _mines[idx]:
		# 踩雷
		_exploded_cell = idx
		_revealed[idx] = true
		_end_game(false)
		return
	# 安全
	var newly = _flood_reveal(idx)
	_refresh_all_cells()
	_animate_reveal(newly)
	if _remaining <= 0:
		_end_game(true)
	else:
		# 低频率说话，不是每次都说
		if randf() < 0.2:
			_say(_pick(_q_safe, _POOL_SAFE))

func _flood_reveal(idx: int) -> Array[int]:
	# BFS 递归揭开, 返回新揭开的格子列表
	var newly: Array[int] = []
	var queue: Array[int] = [idx]
	while queue.size() > 0:
		var cur = queue.pop_front()
		if _revealed[cur]:
			continue
		# 自动清除非雷格子的误旗 (BFS 展开时可能遇到)
		if _flagged[cur]:
			_flagged[cur] = false
			_flag_count -= 1
		_revealed[cur] = true
		_remaining -= 1
		newly.append(cur)
		# 如果是 0 (无邻雷)，展开周围
		if _adjacent[cur] == 0:
			var r = cur / COLS
			var c = cur % COLS
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					if dr == 0 and dc == 0:
						continue
					var nr = r + dr
					var nc = c + dc
					if nr >= 0 and nr < ROWS and nc >= 0 and nc < COLS:
						var ni = nr * COLS + nc
						if not _revealed[ni] and not _mines[ni]:
							queue.append(ni)
	return newly

func _toggle_flag(idx: int) -> void:
	if _revealed[idx]:
		return
	if _first_click:
		return  # 还没点开过，不让插旗
	if not _flagged[idx] and _flag_count >= MINE_COUNT:
		return  # 旗帜数已达雷数上限
	_flagged[idx] = not _flagged[idx]
	if _flagged[idx]:
		_flag_count += 1
		if randf() < 0.25:
			_say(_pick(_q_flag, _POOL_FLAG))
	else:
		_flag_count -= 1
		if randf() < 0.3:
			_say(_pick(_q_unflag, _POOL_UNFLAG))
	_mine_count_label.text = "[ THREAT ]  %02d" % max(0, MINE_COUNT - _flag_count)
	_refresh_cell(idx)

func _end_game(won: bool) -> void:
	_game_over = true
	_game_won = won
	_timer_running = false
	if won:
		_wins += 1
		_add_gaming_xp(40)
		_say(_pick(_q_win, _POOL_WIN))
		# 胜利: 自动标记所有雷
		for i in range(ROWS * COLS):
			if _mines[i]:
				_flagged[i] = true
		_flag_count = MINE_COUNT
		_mine_count_label.text = "[ THREAT ]  00"
		# 显示最终用时
		var mins = int(_elapsed) / 60
		var secs = int(_elapsed) % 60
		_timer_label.text = "[ TIME ]  %02d:%02d" % [mins, secs]
	else:
		_losses += 1
		_add_gaming_xp(5)
		_say(_pick(_q_lose, _POOL_LOSE))
		# 揭开所有雷 + 标出错误插旗
		for i in range(ROWS * COLS):
			if _mines[i]:
				_revealed[i] = true
	_refresh_all_cells()
	_update_score_label()
	_save_scores()
	if _compare_label:
		var my_w = SettingsManager.get_int(_score_key("wins"), 0)
		var my_l = SettingsManager.get_int(_score_key("losses"), 0)
		var pet_w = SettingsManager.get_int(_other_score_key("wins"), 0)
		var pet_l = SettingsManager.get_int(_other_score_key("losses"), 0)
		_compare_label.text = "操作员: %d/%d | 本机: %d/%d" % ([my_w, my_w + my_l, pet_w, pet_w + pet_l] if not _auto_play else [pet_w, pet_w + pet_l, my_w, my_w + my_l])
	_show_restart_bubble()
	# 确保面板不超出屏幕
	if is_instance_valid(game_viewport):
		await game_viewport.get_tree().process_frame
		_clamp_panel_to_screen()
	game_finished.emit(Result.WIN if won else Result.LOSE)

func _on_restart() -> void:
	_reset_game()
	_say(_pick(_q_start, _POOL_START))

func _on_close_cleanup() -> bool:
	var was_auto = _auto_play
	if not _game_over:
		_game_over = true
		_timer_running = false
		_losses += 1
		_save_scores()
		game_finished.emit(Result.LOSE)
		if is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
			if was_auto:
				var auto_close_lines = ["...？", "...扫描中断。", "威胁评估被终止了。"]
				_pet.show_local_bubble(auto_close_lines[randi() % auto_close_lines.size()])
			else:
				_pet.show_local_bubble(_pick(_q_lose, _POOL_CLOSE_MID))
	return true

# ══════════════════════════════════════════════
# 格子视觉更新 (Control 节点方式)
# ══════════════════════════════════════════════

func _refresh_all_cells() -> void:
	for i in range(ROWS * COLS):
		_refresh_cell(i)

func _refresh_cell(idx: int) -> void:
	if idx < 0 or idx >= _cells.size():
		return
	var cell = _cells[idx]
	var lbl = _cell_labels[idx]
	var hue = EventBus.ui_hue
	var cell_bg = cell.get_theme_stylebox("panel") as StyleBoxFlat
	if not cell_bg:
		cell_bg = StyleBoxFlat.new()
		cell.add_theme_stylebox_override("panel", cell_bg)

	var is_hovered = (idx == _hover_idx)
	cell_bg.set_corner_radius_all(0) # 直角机能风

	if _revealed[idx]:
		if _mines[idx]:
			# 雷: 极简十字交叉+故障红
			if idx == _exploded_cell:
				cell_bg.bg_color = Color(0.40, 0.02, 0.02, 0.95)
				cell_bg.border_color = Color(1.0, 0.15, 0.15, 0.9)
				cell_bg.set_border_width_all(1)
				lbl.text = "[※]"
				lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25, 1.0))
				lbl.add_theme_font_size_override("font_size", 14)
			else:
				cell_bg.bg_color = Color(0.12, 0.02, 0.02, 0.85)
				cell_bg.border_color = Color(0.8, 0.15, 0.15, 0.3)
				cell_bg.set_border_width_all(1)
				lbl.text = "※"
				lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 0.7))
				lbl.add_theme_font_size_override("font_size", 14)
			cell.mouse_default_cursor_shape = Control.CURSOR_ARROW
		else:
			# 安全格: 背景透空，显示数字
			cell_bg.bg_color = Color(0.01, 0.02, 0.05, 0.2)
			cell_bg.border_color = Color.from_hsv(hue, 0.15, 0.3, 0.05)
			cell_bg.set_border_width_all(1)
			cell.mouse_default_cursor_shape = Control.CURSOR_ARROW
			var num = _adjacent[idx]
			if num > 0:
				lbl.text = str(num)
				var c: Color = _get_num_color(num, hue)
				lbl.add_theme_color_override("font_color", c)
				lbl.add_theme_font_size_override("font_size", 14 if num < 3 else 15)
			else:
				lbl.text = ""
	elif _flagged[idx]:
		# 旗帜: 锁定标记 ◬
		var is_wrong = _game_over and not _game_won and not _mines[idx]
		if is_wrong:
			cell_bg.bg_color = Color(0.20, 0.05, 0.05, 0.8)
			cell_bg.border_color = Color(0.8, 0.2, 0.2, 0.5)
			cell_bg.set_border_width_all(1)
			lbl.text = "ERR"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 0.9))
			lbl.add_theme_font_size_override("font_size", 10)
		else:
			cell_bg.bg_color = Color.from_hsv(hue, 0.4, 0.25, 0.95)
			cell_bg.border_color = Color.from_hsv(hue, 0.7, 0.9, 0.5)
			cell_bg.set_border_width_all(1)
			lbl.text = "◬"
			lbl.add_theme_color_override("font_color", Color.from_hsv(hue, 0.8, 1.0, 0.95))
			lbl.add_theme_font_size_override("font_size", 13)
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		# 未揭开: 暗黑机能风涂层 - 增加明度，强化物理实体感
		var base_c = Color.from_hsv(hue, 0.3, 0.2, 0.95)
		if is_hovered and not _game_over:
			base_c = Color.from_hsv(hue, 0.5, 0.35, 0.95)
			cell_bg.border_color = Color.from_hsv(hue, 0.8, 0.9, 0.6)
		else:
			cell_bg.border_color = Color.from_hsv(hue, 0.5, 0.6, 0.3)
		cell_bg.bg_color = base_c
		cell_bg.set_border_width_all(1)
		lbl.text = ""
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 胜利时: 已标记的雷高亮为绿色安全符号
	if _game_won and _mines[idx] and _flagged[idx]:
		cell_bg.bg_color = Color(0.05, 0.15, 0.08, 0.9)
		cell_bg.border_color = Color.from_hsv(fmod(hue + 0.15, 1.0), 0.6, 1.0, 0.5)
		cell_bg.set_border_width_all(1)
		lbl.text = "✓"
		lbl.add_theme_color_override("font_color", Color.from_hsv(fmod(hue + 0.15, 1.0), 0.5, 1.0, 1.0))
		lbl.add_theme_font_size_override("font_size", 14)

func _on_cell_hover(idx: int) -> void:
	if _hover_idx == idx:
		return
	var old = _hover_idx
	_hover_idx = idx
	if old >= 0:
		_refresh_cell(old)
	_refresh_cell(idx)

func _on_cell_unhover(idx: int) -> void:
	if _hover_idx != idx:
		return
	_hover_idx = -1
	_refresh_cell(idx)

func _animate_reveal(cells: Array[int]) -> void:
	if not is_instance_valid(game_viewport):
		return
	var hue = EventBus.ui_hue
	var flash_color = Color.from_hsv(hue, 0.35, 0.55, 0.7)
	for i in range(cells.size()):
		var idx = cells[i]
		if idx < 0 or idx >= _cells.size():
			continue
		var cell = _cells[idx]
		var cell_bg = cell.get_theme_stylebox("panel") as StyleBoxFlat
		if not cell_bg:
			continue
		var target_bg = cell_bg.bg_color
		# 亮色闪光 → 渐变回正常暗色
		cell_bg.bg_color = flash_color
		var delay = minf(float(i) * 0.018, 0.35)
		var tween = game_viewport.create_tween()
		tween.tween_interval(delay)
		tween.tween_property(cell_bg, "bg_color", target_bg, 0.45).set_ease(Tween.EASE_OUT)

# ══════════════════════════════════════════════
# 面板辅助
# ══════════════════════════════════════════════

func _update_score_label() -> void:
	if not _score_label:
		return
	var hue = EventBus.ui_hue
	var win_c = Color.from_hsv(fmod(hue + 0.15, 1.0), 0.45, 0.85).to_html(false)
	var lose_c = Color(0.85, 0.35, 0.35).to_html(false)
	var dim = Color(0.4, 0.5, 0.6, 0.5).to_html(false)
	_score_label.text = (
		"[center][color=#" + dim + "]排除 [/color][color=#" + win_c + "]" + str(_wins)
		+ "[/color]    [color=#" + dim + "]引爆 [/color][color=#" + lose_c + "]" + str(_losses)
		+ "[/color][/center]"
	)

# 面板定位/拖拽/clamp 已统一到 BaseGame

# ══════════════════════════════════════════════
# 自动操作 (AI 自玩)
# ══════════════════════════════════════════════

## 启动自动操作模式
func _start_auto_play() -> void:
	_auto_play = true
	var auto_start_lines = [
		"威胁源扫描训练启动。",
		"...危险区域演练。",
		"自主扫雷开始。...想接手就点。",
		"训练中。...观摩可以。",
	]
	if is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
		_pet.show_local_bubble(auto_start_lines[randi() % auto_start_lines.size()])
	if is_instance_valid(game_viewport):
		await game_viewport.get_tree().create_timer(0.6).timeout
	if not _auto_play or not is_instance_valid(game_container):
		return
	_auto_fade(AUTO_PLAY_ALPHA)
	_auto_create_timer(0.4)

func _get_takeover_lines() -> Array:
	return ["...你来？好。", "操作权移交。", "接手确认。...小心地雷。"]

func _auto_play_step() -> void:
	if not _auto_play:
		return
	if _game_over:
		_auto_finish_and_close()
		return
	var action = _ai_pick_action()
	if action.type == "reveal":
		_reveal_cell(action.idx)
	elif action.type == "flag":
		if not _flagged[action.idx]:
			_toggle_flag(action.idx)
	if is_instance_valid(_auto_timer):
		# 操作速度受等级影响 (Lv.1: 0.5~0.9s → Lv.10: 0.1~0.25s)
		var rate = _get_mistake_rate()  # 0.10→0.0
		var spd_factor = 1.0 - rate / 0.10  # 0.0→1.0
		var lo = lerpf(0.5, 0.1, spd_factor)
		var hi = lerpf(0.9, 0.25, spd_factor)
		_auto_timer.wait_time = randf_range(lo, hi)

## AI 策略: 约束求解 + 概率猜测
func _ai_pick_action() -> Dictionary:
	# 首次点击: 选中心附近
	if _first_click:
		var center = (ROWS / 2) * COLS + (COLS / 2)
		return {type = "reveal", idx = center}
	
	# ── 第一轮: 确定性推理 ──
	var safe_cells: Array[int] = []   # 确定安全
	var mine_cells: Array[int] = []   # 确定是雷
	
	for i in range(ROWS * COLS):
		if not _revealed[i] or _adjacent[i] <= 0:
			continue
		# 这个已揭开的数字格周围的未揭开格子
		var r = i / COLS
		var c = i % COLS
		var unrevealed: Array[int] = []
		var flagged_count := 0
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				if dr == 0 and dc == 0: continue
				var nr = r + dr
				var nc = c + dc
				if nr < 0 or nr >= ROWS or nc < 0 or nc >= COLS: continue
				var ni = nr * COLS + nc
				if _flagged[ni]:
					flagged_count += 1
				elif not _revealed[ni]:
					unrevealed.append(ni)
		var remaining_mines = _adjacent[i] - flagged_count
		if remaining_mines == 0 and unrevealed.size() > 0:
			# 周围雷全标完了, 剩下的都安全
			for ui in unrevealed:
				if ui not in safe_cells:
					safe_cells.append(ui)
		elif remaining_mines == unrevealed.size() and unrevealed.size() > 0:
			# 剩下的未揭开格全是雷
			for ui in unrevealed:
				if ui not in mine_cells:
					mine_cells.append(ui)
	
	# 优先提交确定的雷 (插旗)
	if mine_cells.size() > 0:
		return {type = "flag", idx = mine_cells[randi() % mine_cells.size()]}
	# 然后揭开确定安全的
	if safe_cells.size() > 0:
		return {type = "reveal", idx = safe_cells[randi() % safe_cells.size()]}
	
	# ── 第二轮: 概率猜测 (角落优先) ──
	var candidates: Array[int] = []
	for i in range(ROWS * COLS):
		if not _revealed[i] and not _flagged[i]:
			candidates.append(i)
	if candidates.is_empty():
		return {type = "reveal", idx = 0}  # fallback
	
	# 角落 > 边缘 > 内部 (角落雷的概率统计上更低)
	var corners: Array[int] = []
	var edges: Array[int] = []
	var inner: Array[int] = []
	for ci in candidates:
		var cr = ci / COLS
		var cc = ci % COLS
		var is_corner = (cr == 0 or cr == ROWS - 1) and (cc == 0 or cc == COLS - 1)
		var is_edge = cr == 0 or cr == ROWS - 1 or cc == 0 or cc == COLS - 1
		if is_corner:
			corners.append(ci)
		elif is_edge:
			edges.append(ci)
		else:
			inner.append(ci)
	
	# 按熟练度决定失误率
	if randf() < _get_mistake_rate():
		return {type = "reveal", idx = candidates[randi() % candidates.size()]}
	if corners.size() > 0:
		return {type = "reveal", idx = corners[randi() % corners.size()]}
	if edges.size() > 0:
		return {type = "reveal", idx = edges[randi() % edges.size()]}
	return {type = "reveal", idx = inner[randi() % inner.size()]}

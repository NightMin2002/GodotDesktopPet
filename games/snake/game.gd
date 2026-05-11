# game.gd — 路径规划 (贪吃蛇)
# 12x12 网格导航训练，收集能量单元，避免碰壁和自撞
# 使用内嵌 _GridRenderer (Control) 自绘网格, 支持平滑移动插值和过渡动画
extends BaseGame

# ── 常量 ──
const GRID := 12          # 12x12 格
const CELL := 20          # 每格像素
const GRID_PX := GRID * CELL

# 方向向量
const DIR_UP := Vector2i(0, -1)
const DIR_DOWN := Vector2i(0, 1)
const DIR_LEFT := Vector2i(-1, 0)
const DIR_RIGHT := Vector2i(1, 0)

# ── 游戏状态 ──
var _snake: Array[Vector2i] = []     # [0] = 头
var _dir: Vector2i = DIR_RIGHT
var _next_dir: Vector2i = DIR_RIGHT  # 缓冲输入
var _food: Vector2i = Vector2i(-1, -1)
var _score: int = 0

var _game_won: bool = false
var _started: bool = false            # 等待首次输入
var _tick_timer: Timer = null

# ── 动画状态 ──
var _prev_snake: Array[Vector2i] = [] # 上一 tick 的蛇位置 (平滑插值用)
var _tick_elapsed: float = 0.0        # 当前 tick 已过时间
var _food_time: float = 0.0           # 食物脉冲动画
var _food_spawn_t: float = 0.0        # 食物出现动画 (0→1)
var _death_time: float = -1.0         # 死亡动画计时 (<0=未死)
var _eat_flash: float = 0.0           # 吃到食物时的闪光
var _just_ate: bool = false           # 本 tick 是否刚吃了食物

# ── UI 引用 ──
var _panel: PanelContainer = null
var _grid_renderer = null  # _GridRenderer 实例
var _score_label: RichTextLabel = null
var _info_label: Label = null
var _record_label: RichTextLabel = null
var _best_length: int = 0  # 历史最长记录 (持久化)
var _compare_label: Label = null

# ── 话术池 (洗牌防重复) ──
const _POOL_START := [
	"路径规划训练初始化。",
	"单元收集协议启动。...小心边界。",
	"导航训练准备就绪。",
	"路线优化演练。...别撞墙。",
]
const _POOL_EAT := [
	"单元回收。",
	"...不错。",
	"能量捕获确认。",
	"收集效率可接受。",
	"继续。",
]
const _POOL_MILESTONE := [
	"路径延伸中。...保持专注。",
	"规模扩张明显。小心尾部。",
	"...越来越长了。",
]
const _POOL_WIN := [
	"...路径规划完成。满分。",
	"全域覆盖达成。...不可思议。",
]
const _POOL_LOSE := [
	"路径规划失败。碰撞检测触发。",
	"导航中断。...再来。",
	"...撞了。",
	"路线不通。重新规划。",
]
const _POOL_CLOSE_MID := [
	"规划中断。...这算你放弃。",
	"导航训练终止。",
]

var _q_start: Array = []
var _q_eat: Array = []
var _q_milestone: Array = []
var _q_win: Array = []
var _q_lose: Array = []

# (_auto_play / _auto_timer 已在 BaseGame 中)

# ══════════════════════════════════════════════
# 内嵌渲染器 (Control 节点)
# ══════════════════════════════════════════════

class _GridRenderer extends Control:
	var game

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		grab_focus()

	func _draw() -> void:
		if game:
			game._render(self)

	func _gui_input(event: InputEvent) -> void:
		if game:
			game._on_grid_input(event)

	func _process(delta: float) -> void:
		if game:
			game._grid_process(delta)

# ══════════════════════════════════════════════
# BaseGame 接口
# ══════════════════════════════════════════════

func get_game_id() -> String: return "snake"
func get_game_name() -> String: return "路径规划"
func get_game_desc() -> String: return "单元收集导航训练"

func get_tutorial_pages() -> Array:
	return [
		{"text": "方向键 / WASD 控制移动方向"},
		{"text": "收集能量单元 (亮点) 来延伸路径"},
		{"text": "撞到墙壁或自身即为失败"},
		{"text": "速度会随路径长度逐渐加快"},
	]

func get_default_panel_size() -> Vector2:
	return Vector2(310, 380)

func start() -> void:
	_load_scores()
	_best_length = SettingsManager.get_int(_score_key("best_len"), 3)
	_build_ui()
	_reset_game()
	_say(_pick(_q_start, _POOL_START))

func cleanup() -> void:
	_stop_auto_play()
	if is_instance_valid(_tick_timer):
		_tick_timer.stop()
		_tick_timer.queue_free()
		_tick_timer = null
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_grid_renderer = null
	_score_label = null
	_info_label = null
	_record_label = null
	super.cleanup()

# ══════════════════════════════════════════════
# UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(GRID_PX + 28, 0)
	_panel.add_theme_stylebox_override("panel", _create_game_panel_bg())

	var outer = MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 10)
	outer.add_theme_constant_override("margin_right", 10)
	outer.add_theme_constant_override("margin_top", 8)
	outer.add_theme_constant_override("margin_bottom", 6)
	_panel.add_child(outer)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	outer.add_child(vbox)

	# 顶部: 分数 + 长度
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	vbox.add_child(header)

	_score_label = RichTextLabel.new()
	_score_label.bbcode_enabled = true
	_score_label.fit_content = true
	_score_label.scroll_active = false
	_score_label.custom_minimum_size = Vector2(120, 18)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_score_label)

	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.6))
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_info_label)

	# ── 双方对比行 ──
	var my_len = SettingsManager.get_int(_score_key("best_len"), 3)
	var pet_len = SettingsManager.get_int(_other_score_key("best_len"), 3)
	_compare_label = Label.new()
	_compare_label.text = "我的最长: %d | 宠物最长: %d" % [my_len, pet_len]
	_compare_label.add_theme_font_size_override("font_size", 11)
	_compare_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.6))
	_compare_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compare_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_compare_label)

	# 网格区域
	var grid_wrapper = CenterContainer.new()
	vbox.add_child(grid_wrapper)

	_grid_renderer = _GridRenderer.new()
	_grid_renderer.game = self
	_grid_renderer.custom_minimum_size = Vector2(GRID_PX, GRID_PX)
	grid_wrapper.add_child(_grid_renderer)

	# 战绩标签
	_record_label = RichTextLabel.new()
	_record_label.bbcode_enabled = true
	_record_label.fit_content = true
	_record_label.scroll_active = false
	_record_label.custom_minimum_size = Vector2(0, 18)
	vbox.add_child(_record_label)

	_mount_panel(_panel)

	# 创建游戏 tick 定时器
	_tick_timer = Timer.new()
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_tick)
	game_viewport.add_child(_tick_timer)

# ══════════════════════════════════════════════
# 游戏逻辑
# ══════════════════════════════════════════════

func _reset_game() -> void:
	_snake.clear()
	_prev_snake.clear()
	var cx = GRID / 2
	var cy = GRID / 2
	for i in range(3):
		_snake.append(Vector2i(cx - i, cy))
	_prev_snake = _snake.duplicate()
	_dir = DIR_RIGHT
	_next_dir = DIR_RIGHT
	_score = 0
	_game_over = false
	_game_won = false
	_started = false
	_food_time = 0.0
	_food_spawn_t = 0.0
	_death_time = -1.0
	_eat_flash = 0.0
	_tick_elapsed = 0.0
	_just_ate = false
	_spawn_food()
	_update_speed()
	_update_labels()
	_hide_restart_bubble()
	if is_instance_valid(_tick_timer):
		_tick_timer.stop()
	if is_instance_valid(_grid_renderer):
		_grid_renderer.queue_redraw()

func _spawn_food() -> void:
	var occupied: Dictionary = {}
	for seg in _snake:
		occupied[seg] = true
	var empty: Array[Vector2i] = []
	for y in range(GRID):
		for x in range(GRID):
			var p = Vector2i(x, y)
			if not occupied.has(p):
				empty.append(p)
	if empty.is_empty():
		_end_game(true)
		return
	_food = empty[randi() % empty.size()]
	_food_spawn_t = 0.0  # 触发出现动画

func _update_speed() -> void:
	var spd = maxf(0.06, 0.20 - _snake.size() * 0.004)
	if is_instance_valid(_tick_timer):
		_tick_timer.wait_time = spd

func _tick() -> void:
	if _game_over:
		return
	# AI 模式: 每个 tick 都重新决策 (保证反应速度)
	if _auto_play:
		var picked = _ai_pick_dir()
		if picked != Vector2i.ZERO:
			_next_dir = picked
	# 保存上一帧位置 (插值用)
	_prev_snake = _snake.duplicate()
	_tick_elapsed = 0.0
	_just_ate = false

	_dir = _next_dir
	var head = _snake[0]
	var next_pos = head + _dir

	# 碰壁
	if next_pos.x < 0 or next_pos.x >= GRID or next_pos.y < 0 or next_pos.y >= GRID:
		_end_game(false)
		return
	# 自撞 (不检查尾巴最后一节)
	for i in range(_snake.size() - 1):
		if _snake[i] == next_pos:
			_end_game(false)
			return

	_snake.insert(0, next_pos)

	if next_pos == _food:
		_score += 10
		_just_ate = true
		_eat_flash = 1.0
		_add_gaming_xp(2)
		_update_speed()
		_spawn_food()
		if _snake.size() % 15 == 0:
			_say(_pick(_q_milestone, _POOL_MILESTONE))
		elif randf() < 0.12:
			_say(_pick(_q_eat, _POOL_EAT))
	else:
		_snake.pop_back()

	_update_labels()

func _end_game(won: bool) -> void:
	_game_over = true
	_game_won = won
	_death_time = 0.0
	if is_instance_valid(_tick_timer):
		_tick_timer.stop()
	# 更新最长记录
	if _snake.size() > _best_length:
		_best_length = _snake.size()
		SettingsManager.set_int(_score_key("best_len"), _best_length)
	if _compare_label:
		var other_len = SettingsManager.get_int(_other_score_key("best_len"), 3)
		_compare_label.text = "我的最长: %d | 宠物最长: %d" % ([_best_length, other_len] if not _auto_play else [other_len, _best_length])
	if won:
		_wins += 1
		_add_gaming_xp(50)
		_say(_pick(_q_win, _POOL_WIN))
	else:
		_losses += 1
		_add_gaming_xp(5)
		_say(_pick(_q_lose, _POOL_LOSE))
	_update_labels()
	_save_scores()
	_show_restart_bubble()
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
		if is_instance_valid(_tick_timer):
			_tick_timer.stop()
		_losses += 1
		_save_scores()
		game_finished.emit(Result.LOSE)
		if is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
			if was_auto:
				var lines = ["...？", "...导航中断。", "路径规划被终止了。"]
				_pet.show_local_bubble(lines[randi() % lines.size()])
			else:
				_pet.show_local_bubble(_pick(_q_lose, _POOL_CLOSE_MID))
	return true

# ══════════════════════════════════════════════
# 输入处理
# ══════════════════════════════════════════════

func _on_grid_input(event: InputEvent) -> void:
	if _game_over:
		return
	if _auto_play:
		if (event is InputEventKey and event.pressed and not event.echo) or \
		   (event is InputEventMouseButton and event.pressed):
			_stop_auto_play()
			return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var new_dir := Vector2i.ZERO
	var kc = event.keycode
	var pkc = event.physical_keycode
	if kc == KEY_UP or pkc == KEY_W: new_dir = DIR_UP
	elif kc == KEY_DOWN or pkc == KEY_S: new_dir = DIR_DOWN
	elif kc == KEY_LEFT or pkc == KEY_A: new_dir = DIR_LEFT
	elif kc == KEY_RIGHT or pkc == KEY_D: new_dir = DIR_RIGHT
	else: return
	if new_dir == -_dir:
		return
	_next_dir = new_dir
	if not _started:
		_started = true
		if is_instance_valid(_tick_timer):
			_tick_timer.start()

# ══════════════════════════════════════════════
# 帧更新 (动画驱动)
# ══════════════════════════════════════════════

func _grid_process(delta: float) -> void:
	_food_time += delta
	_tick_elapsed += delta
	# 食物出现动画 (0→1, 0.3 秒)
	if _food_spawn_t < 1.0:
		_food_spawn_t = minf(_food_spawn_t + delta / 0.3, 1.0)
	# 吃到闪光衰减
	if _eat_flash > 0.0:
		_eat_flash = maxf(0.0, _eat_flash - delta * 4.0)
	# 死亡动画
	if _death_time >= 0.0:
		_death_time += delta
	if is_instance_valid(_grid_renderer):
		_grid_renderer.queue_redraw()

# ══════════════════════════════════════════════
# 渲染
# ══════════════════════════════════════════════

## 将网格坐标转为像素中心
func _cell_center(pos: Vector2i) -> Vector2:
	return Vector2(float(pos.x * CELL) + CELL * 0.5, float(pos.y * CELL) + CELL * 0.5)

## 获取插值进度 (0=上一tick位置, 1=当前位置)
func _get_lerp_t() -> float:
	if not is_instance_valid(_tick_timer) or _tick_timer.wait_time <= 0:
		return 1.0
	return clampf(_tick_elapsed / _tick_timer.wait_time, 0.0, 1.0)

func _render(canvas: Control) -> void:
	var hue = EventBus.ui_hue
	var lerp_t = _get_lerp_t()

	# ── 背景 ──
	canvas.draw_rect(Rect2(0, 0, GRID_PX, GRID_PX), Color(0.03, 0.04, 0.08, 0.95))

	# 吃到闪光 (全屏微闪)
	if _eat_flash > 0.01:
		var flash_c = Color.from_hsv(hue, 0.3, 0.4, _eat_flash * 0.15)
		canvas.draw_rect(Rect2(0, 0, GRID_PX, GRID_PX), flash_c)

	# ── 网格线 ──
	var grid_color = Color.from_hsv(hue, 0.15, 0.2, 0.10)
	for i in range(GRID + 1):
		var p = float(i * CELL)
		canvas.draw_line(Vector2(p, 0), Vector2(p, GRID_PX), grid_color, 1.0, true)
		canvas.draw_line(Vector2(0, p), Vector2(GRID_PX, p), grid_color, 1.0, true)

	# ── 食物 ──
	if _food.x >= 0:
		var pulse = 0.7 + sin(_food_time * TAU / 1.5) * 0.3
		var food_color = Color.from_hsv(fmod(hue + 0.15, 1.0), 0.7, 1.0, pulse)
		var fc = _cell_center(_food)
		# 出现动画 (缩放弹入)
		var spawn_scale = 1.0
		if _food_spawn_t < 1.0:
			# ease out back
			var t = _food_spawn_t
			spawn_scale = 1.0 - pow(1.0 - t, 3.0) * (1.0 + 2.5 * (1.0 - t))
			spawn_scale = clampf(spawn_scale, 0.0, 1.2)
		# 外发光
		var glow_r = CELL * 0.7 * spawn_scale
		var glow_color = Color(food_color.r, food_color.g, food_color.b, pulse * 0.2)
		canvas.draw_circle(fc, glow_r, glow_color, true, -1.0, true)
		# 中光晕
		canvas.draw_circle(fc, CELL * 0.45 * spawn_scale, Color(food_color.r, food_color.g, food_color.b, pulse * 0.35), true, -1.0, true)
		# 内核
		canvas.draw_circle(fc, CELL * 0.25 * spawn_scale, food_color, true, -1.0, true)

	# ── 蛇身 ──
	var snake_len = _snake.size()
	if snake_len == 0:
		return

	# 计算每个节段的视觉位置 (平滑插值)
	var visual_pos: Array[Vector2] = []
	for i in range(snake_len):
		var cur_c = _cell_center(_snake[i])
		if i < _prev_snake.size() and not _game_over:
			var prev_c = _cell_center(_prev_snake[i])
			visual_pos.append(prev_c.lerp(cur_c, lerp_t))
		else:
			visual_pos.append(cur_c)

	# 从尾到头画, 头在最上层
	for i in range(snake_len - 1, -1, -1):
		var t = float(i) / maxf(1.0, float(snake_len - 1))  # 0=头, 1=尾
		var seg_sat = lerpf(0.65, 0.25, t)
		var seg_val = lerpf(0.95, 0.35, t)
		var seg_alpha = lerpf(1.0, 0.65, t)
		var seg_color = Color.from_hsv(hue, seg_sat, seg_val, seg_alpha)

		# 死亡动画: 身体闪红
		if _death_time >= 0.0:
			var death_flash = sin(_death_time * TAU * 3.0) * 0.5 + 0.5
			var death_blend = minf(_death_time * 2.0, 1.0) * 0.6
			seg_color = seg_color.lerp(Color(1.0, 0.15, 0.1, seg_alpha), death_blend * death_flash)

		var vc = visual_pos[i]
		var seg_r = lerpf(CELL * 0.42, CELL * 0.32, t)  # 头粗尾细

		# 连接段: 在相邻节段之间画矩形连接
		if i < snake_len - 1:
			var next_c = visual_pos[i + 1]
			var dx = next_c.x - vc.x
			var dy = next_c.y - vc.y
			var conn_w = seg_r * 1.4  # 连接带宽度
			if absf(dx) > 1.0:
				# 水平连接
				var cy = vc.y
				var x1 = minf(vc.x, next_c.x)
				var x2 = maxf(vc.x, next_c.x)
				canvas.draw_rect(Rect2(x1, cy - conn_w * 0.5, x2 - x1, conn_w), seg_color)
			elif absf(dy) > 1.0:
				# 垂直连接
				var cx = vc.x
				var y1 = minf(vc.y, next_c.y)
				var y2 = maxf(vc.y, next_c.y)
				canvas.draw_rect(Rect2(cx - conn_w * 0.5, y1, conn_w, y2 - y1), seg_color)

		# 节段圆形
		canvas.draw_circle(vc, seg_r, seg_color, true, -1.0, true)

		# 头部光环
		if i == 0:
			var ring_c = Color.from_hsv(hue, 0.5, 1.0, 0.2)
			canvas.draw_arc(vc, seg_r + 1.5, 0, TAU, 24, ring_c, 1.0, true)

	# ── 死亡覆盖 ──
	if _death_time >= 0.0:
		var overlay_alpha = minf(_death_time * 1.5, 0.45)
		canvas.draw_rect(Rect2(0, 0, GRID_PX, GRID_PX), Color(0.05, 0.0, 0.0, overlay_alpha))
		# 碰撞点红圈脉冲
		if not _game_won and snake_len > 0:
			var head_c = _cell_center(_snake[0])
			var crash_pulse = sin(_death_time * TAU * 2.0) * 0.3 + 0.5
			canvas.draw_circle(head_c, CELL * 0.6, Color(1.0, 0.2, 0.1, crash_pulse * 0.5), true, -1.0, true)
			canvas.draw_arc(head_c, CELL * 0.7, 0, TAU, 20, Color(1.0, 0.3, 0.2, crash_pulse * 0.4), 1.5, true)

# ══════════════════════════════════════════════
# 标签更新
# ══════════════════════════════════════════════

func _update_labels() -> void:
	if not _score_label:
		return
	var hue = EventBus.ui_hue
	var accent = Color.from_hsv(hue, 0.5, 0.9).to_html(false)
	var dim = Color(0.4, 0.5, 0.6, 0.5).to_html(false)
	_score_label.text = "[color=#" + dim + "]分数 [/color][color=#" + accent + "]" + str(_score) + "[/color]"
	_info_label.text = "长度: %d" % _snake.size()
	if _record_label:
		var best_c = Color.from_hsv(fmod(hue + 0.15, 1.0), 0.45, 0.85).to_html(false)
		var lose_c = Color(0.85, 0.35, 0.35).to_html(false)
		_record_label.text = (
			"[center][color=#" + dim + "]最长 [/color][color=#" + best_c + "]" + str(_best_length)
			+ "[/color]    [color=#" + dim + "]碰撞 [/color][color=#" + lose_c + "]" + str(_losses)
			+ "[/color][/center]"
		)

# ══════════════════════════════════════════════
# 自动操作 (AI 自玩)
# ══════════════════════════════════════════════

func _start_auto_play() -> void:
	_auto_play = true
	var auto_start_lines = [
		"路径规划自主训练启动。",
		"...导航演练。",
		"自主导航开始。...想接手就按方向键。",
		"训练中。...观摩可以。",
	]
	if is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
		_pet.show_local_bubble(auto_start_lines[randi() % auto_start_lines.size()])
	if is_instance_valid(game_viewport):
		await game_viewport.get_tree().create_timer(0.6).timeout
	if not _auto_play or not is_instance_valid(game_container):
		return
	_auto_fade(AUTO_PLAY_ALPHA)
	if not _started:
		_started = true
		if is_instance_valid(_tick_timer):
			_tick_timer.start()
	# 自玩定时器仅用于检测游戏结束 (AI 决策在 _tick 里)
	_auto_create_timer(0.5)

func _get_takeover_lines() -> Array:
	return ["...你来？好。", "操作权移交。", "接手确认。...小心尾巴。"]

func _auto_play_step() -> void:
	if not _auto_play:
		return
	# 仅检测游戏结束 (AI 决策已在 _tick 中处理)
	if _game_over:
		_auto_finish_and_close()

## AI 策略: 贪心寻路 + 开放空间评估 + 安全回退
func _ai_pick_dir() -> Vector2i:
	var head = _snake[0]
	var options = [DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]
	options.erase(-_dir)

	# 按熟练度决定失误率
	if randf() < _get_mistake_rate():
		options.shuffle()
		for d in options:
			if _is_safe(head + d):
				return d
		return _dir

	# 评分每个安全方向
	var best_dir = Vector2i.ZERO
	var best_score = -9999.0
	for d in options:
		var next_pos = head + d
		if not _is_safe(next_pos):
			continue
		var score := 0.0
		var dist_now = absi(head.x - _food.x) + absi(head.y - _food.y)
		var dist_new = absi(next_pos.x - _food.x) + absi(next_pos.y - _food.y)
		if dist_new < dist_now:
			score += 10.0
		score += minf(float(_count_reachable(next_pos)), 80.0) * 0.3
		if score > best_score:
			best_score = score
			best_dir = d

	# 安全回退: 没有评分方向时, 选可达空间最大的安全方向
	if best_dir == Vector2i.ZERO:
		var fallback_dir = Vector2i.ZERO
		var fallback_reach = -1
		for d in options:
			if _is_safe(head + d):
				var reach = _count_reachable(head + d)
				if reach > fallback_reach:
					fallback_reach = reach
					fallback_dir = d
		if fallback_dir != Vector2i.ZERO:
			return fallback_dir
		# 真的无路可走 (必死)
		return _dir

	return best_dir

func _is_safe(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= GRID or pos.y < 0 or pos.y >= GRID:
		return false
	for i in range(_snake.size() - 1):
		if _snake[i] == pos:
			return false
	return true

func _count_reachable(from: Vector2i) -> int:
	var visited: Dictionary = {}
	for i in range(_snake.size() - 1):
		visited[_snake[i]] = true
	var queue: Array[Vector2i] = [from]
	visited[from] = true
	var count := 0
	# 搜索深度受等级影响 (Lv.1: 60 → Lv.10: 144=全图)
	var level = SettingsManager.get_gaming_level()
	var max_steps: int = 60 + level * 9  # 60→150
	while queue.size() > 0 and count < max_steps:
		var cur = queue.pop_front()
		count += 1
		for d in [DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]:
			var np = cur + d
			if np.x >= 0 and np.x < GRID and np.y >= 0 and np.y < GRID and not visited.has(np):
				visited[np] = true
				queue.append(np)
	return count

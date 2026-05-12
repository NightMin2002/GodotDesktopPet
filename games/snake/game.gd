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
var _bg_pupil_pos: Vector2 = Vector2.ZERO # 背景单眼的平滑插值位置

# ── Hamiltonian Cycle (AI 自玩用) ──
var _cycle_order: Array = []     # [y][x] → 回路序号 (0..143)
var _cycle_path: Array = []      # [序号] → Vector2i 位置

# ── UI 引用 ──
var _panel: PanelContainer = null
var _grid_renderer = null  # _GridRenderer 实例
var _score_label: RichTextLabel = null
var _info_label: Label = null
var _record_label: RichTextLabel = null
var _best_length: int = 0  # 历史最长记录 (持久化)


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
	var skel = _create_panel_skeleton(GRID_PX + 28, {"left": 10, "right": 10, "top": 8, "bottom": 6, "separation": 6})
	_panel = skel.panel
	var vbox = skel.vbox

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
	_create_compare_row(vbox, "我的最长: %d | 宠物最长: %d" % [my_len, pet_len])

	# 网格区域
	var grid_wrapper = CenterContainer.new()
	vbox.add_child(grid_wrapper)

	_grid_renderer = GridRenderer.new()
	_grid_renderer.game = self
	_grid_renderer.custom_minimum_size = Vector2(GRID_PX, GRID_PX)
	grid_wrapper.add_child(_grid_renderer)

	# 战绩标签
	_record_label = _create_score_rich_label()
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
	_build_hamiltonian_cycle()
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
		_add_gaming_xp(50)
		_say(_pick(_q_win, _POOL_WIN))
	else:
		_add_gaming_xp(5)
		_say(_pick(_q_lose, _POOL_LOSE))
	# 记录局数
	var games = SettingsManager.get_int(_score_key("games"), 0) + 1
	SettingsManager.set_int(_score_key("games"), games)
	_update_labels()
	_show_restart_bubble()
	if is_instance_valid(game_viewport):
		await game_viewport.get_tree().process_frame
		_clamp_panel_to_screen()
	game_finished.emit(Result.WIN if won else Result.LOSE)

func _on_restart() -> void:
	_reset_game()
	_say(_pick(_q_start, _POOL_START))

func _on_close_extra_cleanup() -> void:
	if is_instance_valid(_tick_timer):
		_tick_timer.stop()
	var games = SettingsManager.get_int(_score_key("games"), 0) + 1
	SettingsManager.set_int(_score_key("games"), games)

func get_close_speech_pool() -> Array:
	return _POOL_CLOSE_MID

func get_auto_close_lines() -> Array:
	return ["...？", "...导航中断。", "路径规划被终止了。"]

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
	
	# 更新背景监控单眼的追踪插值
	var c = Vector2(GRID_PX / 2.0, GRID_PX / 2.0)
	var target: Vector2
	if _snake.size() > 0:
		# 利用 lerp_t 获取比格子跳跃更平滑的物理位置
		var lerp_t = _get_lerp_t()
		var cur_c = _cell_center(_snake[0])
		if _prev_snake.size() > 0 and not _game_over:
			var prev_c = _cell_center(_prev_snake[0])
			target = prev_c.lerp(cur_c, lerp_t)
		else:
			target = cur_c
	else:
		target = c
		
	var diff = target - c
	var target_offset = diff * 0.2
	# 背景巨眼框尺寸: hw=80, hh=30
	var dist = abs(target_offset.x) / 55.0 + abs(target_offset.y) / 12.0
	if dist > 1.0:
		target_offset /= dist
		
	_bg_pupil_pos = _bg_pupil_pos.lerp(target_offset, delta * 12.0)

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
	# 去掉厚重的纯色，加入统一的激光扫描线背景
	var bg_c = Color.from_hsv(hue, 0.4, 0.05, 0.95)
	canvas.draw_rect(Rect2(0, 0, GRID_PX, GRID_PX), bg_c)
	
	# ── 巨型深潜监视眼 ──
	var eye_c = Vector2(GRID_PX / 2.0, GRID_PX / 2.0)
	var c_frame = Color.from_hsv(hue, 0.2, 0.5, 0.15) # 极低透明度，藏在暗处
	var hw = 80.0
	var hh = 30.0
	var frame_pts = PackedVector2Array([
		eye_c + Vector2(-hw, 0), eye_c + Vector2(0, -hh),
		eye_c + Vector2(hw, 0), eye_c + Vector2(0, hh)
	])
	canvas.draw_polyline(frame_pts + PackedVector2Array([frame_pts[0]]), c_frame, 2.0, true)
	
	canvas.draw_line(Vector2(20, eye_c.y), eye_c + Vector2(-hw - 8, 0), c_frame, 1.0, true)
	canvas.draw_line(eye_c + Vector2(hw + 8, 0), Vector2(GRID_PX - 20, eye_c.y), c_frame, 1.0, true)

	var pupil_center = eye_c + _bg_pupil_pos
	var c_pupil = Color.from_hsv(hue, 0.2, 0.7, 0.25) # 微亮，隐藏在背景与扫描线之间
	
	canvas.draw_arc(pupil_center, 15.0, 0, TAU, 32, c_pupil, 2.5, true)
	canvas.draw_circle(pupil_center, 3.5, c_pupil, true, -1.0, true)
	
	var scan_y = fmod(_food_time * 40.0, GRID_PX + 40.0) - 20.0
	var c_band = Color.from_hsv(hue, 0.3, 0.9, 0.03)
	canvas.draw_rect(Rect2(0, scan_y, GRID_PX, 12.0), c_band)
	var c_core = Color.from_hsv(hue, 0.5, 1.0, 0.06)
	canvas.draw_rect(Rect2(0, scan_y + 5.0, GRID_PX, 1.0), c_core)

	if _eat_flash > 0.01:
		var flash_c = Color.from_hsv(hue, 0.3, 0.4, _eat_flash * 0.15)
		canvas.draw_rect(Rect2(0, 0, GRID_PX, GRID_PX), flash_c)

	# ── 阵列网格 ──
	# 使用极微小的十字针脚替代死板的长线，营造医疗/军工测量仪感
	var grid_color = Color.from_hsv(hue, 0.2, 0.5, 0.15)
	for x in range(GRID + 1):
		for y in range(GRID + 1):
			var cx = x * CELL
			var cy = y * CELL
			canvas.draw_line(Vector2(cx - 2, cy), Vector2(cx + 2, cy), grid_color, 1.0, true)
			canvas.draw_line(Vector2(cx, cy - 2), Vector2(cx, cy + 2), grid_color, 1.0, true)

	# ── 食物 (定位信标) ──
	if _food.x >= 0:
		var pulse = 0.7 + sin(_food_time * TAU / 1.0) * 0.3
		var food_color = Color.from_hsv(fmod(hue + 0.15, 1.0), 0.7, 1.0, pulse)
		var fc = _cell_center(_food)
		
		var spawn_scale = 1.0
		if _food_spawn_t < 1.0:
			var t = _food_spawn_t
			spawn_scale = 1.0 - pow(1.0 - t, 3.0) * (1.0 + 2.5 * (1.0 - t))
			spawn_scale = clampf(spawn_scale, 0.0, 1.2)
			
		# 画一个边长受控的空心旋转菱形
		var hs = CELL * 0.35 * spawn_scale
		var rot = _food_time * 2.0
		var pts = PackedVector2Array()
		for i in range(4):
			var a = rot + i * PI / 2.0
			pts.append(fc + Vector2(cos(a), sin(a)) * hs)
		pts.append(pts[0])
		canvas.draw_polyline(pts, food_color, 1.2, true)
		
		# 中心十字微芯
		var cross_s = CELL * 0.15 * spawn_scale
		canvas.draw_line(fc - Vector2(cross_s, 0), fc + Vector2(cross_s, 0), food_color, 1.0, true)
		canvas.draw_line(fc - Vector2(0, cross_s), fc + Vector2(0, cross_s), food_color, 1.0, true)
		
		# 极简外对焦锁定框 [ ]
		var bracket_d = CELL * 0.45
		var br_color = Color.from_hsv(fmod(hue + 0.15, 1.0), 0.5, 1.0, pulse * 0.3)
		var brk_len = 3.0
		if spawn_scale >= 0.99:
			canvas.draw_line(fc + Vector2(-bracket_d, -bracket_d), fc + Vector2(-bracket_d+brk_len, -bracket_d), br_color, 1.0, true)
			canvas.draw_line(fc + Vector2(-bracket_d, -bracket_d), fc + Vector2(-bracket_d, -bracket_d+brk_len), br_color, 1.0, true)
			canvas.draw_line(fc + Vector2(bracket_d, bracket_d), fc + Vector2(bracket_d-brk_len, bracket_d), br_color, 1.0, true)
			canvas.draw_line(fc + Vector2(bracket_d, bracket_d), fc + Vector2(bracket_d, bracket_d-brk_len), br_color, 1.0, true)

	# ── 数据链路 (蛇身) ──
	var snake_len = _snake.size()
	if snake_len == 0:
		return

	var visual_pos: Array[Vector2] = []
	for i in range(snake_len):
		var cur_c = _cell_center(_snake[i])
		if i < _prev_snake.size() and not _game_over:
			var prev_c = _cell_center(_prev_snake[i])
			visual_pos.append(prev_c.lerp(cur_c, lerp_t))
		else:
			visual_pos.append(cur_c)

	# 独立方块切片，摒弃连线形成进度条视效
	for i in range(snake_len - 1, -1, -1):
		var t = float(i) / maxf(1.0, float(snake_len - 1))  # 0=头, 1=尾
		var seg_sat = lerpf(0.65, 0.25, t)
		var seg_val = lerpf(0.95, 0.35, t)
		var seg_alpha = lerpf(1.0, 0.65, t)
		var seg_color = Color.from_hsv(hue, seg_sat, seg_val, seg_alpha)

		if _death_time >= 0.0:
			var death_flash = sin(_death_time * TAU * 3.0) * 0.5 + 0.5
			var death_blend = minf(_death_time * 2.0, 1.0) * 0.6
			seg_color = seg_color.lerp(Color(1.0, 0.15, 0.1, seg_alpha), death_blend * death_flash)

		var vc = visual_pos[i]
		
		# 方块大小随着头到尾平滑收缩，创造透视纵深感
		var side = lerpf(CELL * 0.85, CELL * 0.45, t) 
		var hs = side * 0.5
		
		canvas.draw_rect(Rect2(vc.x - hs, vc.y - hs, side, side), seg_color)
		
		# 极简尖端探针标志
		if i == 0:
			var core_c = Color(1.0, 1.0, 1.0, 0.9)
			canvas.draw_rect(Rect2(vc.x - hs*0.4, vc.y - hs*0.4, side*0.4, side*0.4), core_c)
			
			var ring_c = Color.from_hsv(hue, 0.5, 1.0, 0.6)
			var hd = hs + 1.5
			var hl = 3.0
			# 左上
			canvas.draw_line(vc + Vector2(-hd, -hd), vc + Vector2(-hd+hl, -hd), ring_c, 1.0, true)
			canvas.draw_line(vc + Vector2(-hd, -hd), vc + Vector2(-hd, -hd+hl), ring_c, 1.0, true)
			# 右上
			canvas.draw_line(vc + Vector2(hd, -hd), vc + Vector2(hd-hl, -hd), ring_c, 1.0, true)
			canvas.draw_line(vc + Vector2(hd, -hd), vc + Vector2(hd, -hd+hl), ring_c, 1.0, true)
			# 左下
			canvas.draw_line(vc + Vector2(-hd, hd), vc + Vector2(-hd+hl, hd), ring_c, 1.0, true)
			canvas.draw_line(vc + Vector2(-hd, hd), vc + Vector2(-hd, hd-hl), ring_c, 1.0, true)
			# 右下
			canvas.draw_line(vc + Vector2(hd, hd), vc + Vector2(hd-hl, hd), ring_c, 1.0, true)
			canvas.draw_line(vc + Vector2(hd, hd), vc + Vector2(hd, hd-hl), ring_c, 1.0, true)

	# ── 寻轨失败阻断 ──
	if _death_time >= 0.0:
		var overlay_alpha = minf(_death_time * 1.5, 0.45)
		canvas.draw_rect(Rect2(0, 0, GRID_PX, GRID_PX), Color(0.05, 0.0, 0.0, overlay_alpha))
		if not _game_won and snake_len > 0:
			var head_c = _cell_center(_snake[0])
			var crash_pulse = sin(_death_time * TAU * 2.0) * 0.3 + 0.5
			var err_c = Color(1.0, 0.2, 0.1, crash_pulse * 0.8)
			var err_s = CELL * 0.6
			canvas.draw_line(head_c + Vector2(-err_s, -err_s), head_c + Vector2(err_s, err_s), err_c, 2.0, true)
			canvas.draw_line(head_c + Vector2(err_s, -err_s), head_c + Vector2(-err_s, err_s), err_c, 2.0, true)
			canvas.draw_rect(Rect2(head_c.x - err_s, head_c.y - err_s, err_s*2, err_s*2), Color(1.0, 0.2, 0.1, crash_pulse * 0.2), false, 1.5)

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
		var game_count = SettingsManager.get_int(_score_key("games"), 0)
		_record_label.text = (
			"[center][color=#" + dim + "]最长 [/color][color=#" + best_c + "]" + str(_best_length)
			+ "[/color]    [color=#" + dim + "]局数 [/color][color=#" + lose_c + "]" + str(game_count)
			+ "[/color][/center]"
		)

# ══════════════════════════════════════════════
# 自动操作 (AI 自玩)
# ══════════════════════════════════════════════

func get_auto_start_lines() -> Array:
	return [
		"路径规划自主训练启动。",
		"...导航演练。",
		"自主导航开始。...想接手就按方向键。",
		"训练中。...观摩可以。",
	]

func _on_auto_play_started() -> void:
	if not _started:
		_started = true
		if is_instance_valid(_tick_timer):
			_tick_timer.start()

func get_auto_play_interval() -> float:
	return 0.5

func _get_takeover_lines() -> Array:
	return ["...你来？好。", "操作权移交。", "接手确认。...小心尾巴。"]

func _auto_play_step() -> void:
	if not _auto_play:
		return
	# 仅检测游戏结束 (AI 决策已在 _tick 中处理)
	if _game_over:
		_auto_finish_and_close()

## AI 策略: 智能追食 + Hamiltonian Cycle 兜底
## 主策略: 选离食物最近且不会困死自己的方向 (看起来聪明)
## 兜底: 跟 Hamiltonian Cycle 走 (保证不死)
func _ai_pick_dir() -> Vector2i:
	var head = _snake[0]
	if _cycle_order.is_empty():
		return _dir
	var head_idx = _cycle_order[head.y][head.x]
	var N = GRID * GRID

	# 兜底: 沿 Hamiltonian Cycle 前进 (100% 安全)
	var next_idx = (head_idx + 1) % N
	var next_pos = _cycle_path[next_idx]
	var cycle_dir = next_pos - head

	# 按熟练度决定失误率
	if randf() < _get_mistake_rate():
		var options = [DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]
		options.shuffle()
		for d in options:
			if _is_safe(head + d):
				return d
		return cycle_dir

	# 智能追食: 选离食物最近 + 不会困死自己的方向
	var best_dir = Vector2i.ZERO
	var best_dist = 9999
	for d in [DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]:
		var np = head + d
		if not _is_safe(np):
			continue
		# 安全验证: 移动后可达空间 >= 蛇身长度 (不会困住自己)
		var reachable = _count_reachable_from(np)
		if reachable < _snake.size():
			continue
		var food_dist = absi(np.x - _food.x) + absi(np.y - _food.y)
		if food_dist < best_dist:
			best_dist = food_dist
			best_dir = d

	if best_dir != Vector2i.ZERO:
		return best_dir

	# 二级兜底: Hamiltonian Cycle (需验证安全)
	if _is_safe(head + cycle_dir):
		return cycle_dir

	# 三级兜底: 选可达空间最大的安全方向 (绝对不撞)
	var emer_dir = _dir
	var emer_reach = -1
	for d in [DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]:
		var np = head + d
		if _is_safe(np):
			var r = _count_reachable_from(np)
			if r > emer_reach:
				emer_reach = r
				emer_dir = d
	return emer_dir

func _is_safe(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= GRID or pos.y < 0 or pos.y >= GRID:
		return false
	for i in range(_snake.size() - 1):
		if _snake[i] == pos:
			return false
	return true

## Flood fill: 从某位置出发可到达的空间数量
## 提前截断: 够用了就不继续 (性能)
func _count_reachable_from(from: Vector2i) -> int:
	var visited: Dictionary = {}
	# 蛇身 (排除尾巴, 因为下一步尾巴会移走)
	for i in range(_snake.size() - 1):
		visited[_snake[i]] = true
	var queue: Array[Vector2i] = [from]
	visited[from] = true
	var count := 0
	var need = _snake.size() + 2  # 只要够用就行
	while queue.size() > 0:
		var cur = queue.pop_front()
		count += 1
		if count >= need:
			return count  # 提前截断
		for d in [DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]:
			var np = cur + d
			if np.x >= 0 and np.x < GRID and np.y >= 0 and np.y < GRID and not visited.has(np):
				visited[np] = true
				queue.append(np)
	return count

## 生成 Hamiltonian Cycle (蛇形扫描回路)
## 路径: 第0行全部向右 → 奇数行向左(1~11列) → 偶数行向右(1~11列)
##       → 最后一行全部向左 → 第0列向上回到起点
func _build_hamiltonian_cycle() -> void:
	_cycle_order.clear()
	_cycle_path.clear()
	for y in range(GRID):
		var row: Array = []
		row.resize(GRID)
		row.fill(0)
		_cycle_order.append(row)

	var index = 0
	var path: Array[Vector2i] = []

	# 第 0 行: 全部向右 (0..GRID-1)
	for x in range(GRID):
		_cycle_order[0][x] = index
		path.append(Vector2i(x, 0))
		index += 1

	# 中间行 (1..GRID-2): 在 1~GRID-1 列间蜂形扫描
	for y in range(1, GRID - 1):
		if y % 2 == 1:  # 奇数行: 右到左 (GRID-1 → 1)
			for x in range(GRID - 1, 0, -1):
				_cycle_order[y][x] = index
				path.append(Vector2i(x, y))
				index += 1
		else:  # 偶数行: 左到右 (1 → GRID-1)
			for x in range(1, GRID):
				_cycle_order[y][x] = index
				path.append(Vector2i(x, y))
				index += 1

	# 最后一行: 全部向左 (GRID-1 → 0)
	for x in range(GRID - 1, -1, -1):
		_cycle_order[GRID - 1][x] = index
		path.append(Vector2i(x, GRID - 1))
		index += 1

	# 第 0 列向上返回 (GRID-2 → 1)
	for y in range(GRID - 2, 0, -1):
		_cycle_order[y][0] = index
		path.append(Vector2i(0, y))
		index += 1

	_cycle_path = path

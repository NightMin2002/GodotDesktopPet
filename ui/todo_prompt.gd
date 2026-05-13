# todo_prompt.gd — 宠物主动待办提醒系统
# 启动后适时机提醒用户未完成的待办事项
# 在宠物上方显示常驻气泡 + 两侧操作按钮
extends CanvasLayer

var _pet: RigidBody2D
var _startup_elapsed: float = 0.0
var _startup_target: float = 0.0   # 随机启动缓冲 (8~15s)
var _poll_timer: float = 0.0
var _prompted_today: bool = false
var _startup_done: bool = false    # 启动缓冲已过

# ── UI 组件 ──
var _bubble: PanelContainer       # 常驻气泡
var _btn_accept: Button           # "查看待办"
var _btn_dismiss: Button          # "知道了"
var _showing: bool = false        # 是否正在显示
const BTN_FADE_TIME := 0.4

# ═══ 话术池 (冰山系 + 选词为人类优化) ═══

const MORNING_LINES := [
	"晨间扫描：检测到 {n} 项未处理事务。",
	"日间模式启动。待办队列 {n} 项挂起。",
	"早间报告。你有 {n} 件事没完成。...不是催你。",
]

const AFTERNOON_LINES := [
	"下午存档节点。待处理事务 {n} 项。",
	"午后提醒。{n} 项任务状态未更新。",
	"系统示意：{n} 项待办仍在队列中。",
]

const EVENING_LINES := [
	"日间任务尚未归档。剩余 {n} 项。",
	"傍晚了。{n} 项任务还挂着。...只是客观数据。",
	"今日待办完成率：{done}/{total}。仅供参考。",
]

func _ready() -> void:
	layer = 105
	_startup_target = randf_range(8.0, 15.0)
	# 检查今日是否已提醒过 (日期存为 YYYYMMDD 整数)
	var today_int = _get_today_int()
	var last_date = SettingsManager.get_int("todo_last_prompt_date", 0)
	_prompted_today = (last_date == today_int)
	# 调试: 直接触发信号
	EventBus.trigger_todo_prompt.connect(_on_force_trigger)

func link_pet(pet: Node2D) -> void:
	_pet = pet as RigidBody2D

## 获取今日日期的 YYYYMMDD 整数 (如 20260512)
func _get_today_int() -> int:
	var d = Time.get_date_dict_from_system()
	return d["year"] * 10000 + d["month"] * 100 + d["day"]

func _process(delta: float) -> void:
	# UI 跟随宠物位置
	if _showing:
		_update_positions()
		return
	
	# 已提醒过今天就不再检查
	if _prompted_today:
		return
	
	# 等宠物有效
	if not is_instance_valid(_pet):
		return
	
	# 启动缓冲
	_startup_elapsed += delta
	if not _startup_done:
		if _startup_elapsed < _startup_target:
			return
		_startup_done = true
		if _try_prompt():
			return
	
	# 轮询兜底 (每 60s 检查一次)
	_poll_timer += delta
	if _poll_timer >= 60.0:
		_poll_timer = 0.0
		_try_prompt()

# ═══════════════════════════════════════════════
#  触发逻辑
# ═══════════════════════════════════════════════

func _try_prompt() -> bool:
	if _prompted_today:
		return false
	if not is_instance_valid(_pet):
		return false
	
	# 条件 1: 有未完成的待办
	var todos = SettingsManager.get_todos()
	var remaining := 0
	var total := todos.size()
	for t in todos:
		if not t.get("done", false):
			remaining += 1
	if remaining <= 0:
		return false
	
	# 条件 2: 不在深夜模式
	if _pet.nighttime_mode:
		return false
	
	# 条件 3: 不在游戏中
	if _pet.gaming.active:
		return false
	
	# 条件 4: 宠物处于 idle 状态
	if _pet.current_state_name != "idle":
		return false
	
	# 条件 5: 气泡系统空闲
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node:
		for child in main_node.get_children():
			if child.has_method("is_busy") and child.is_busy():
				return false
	
	# 条件 6: 没有未确认的提醒/碎碎念
	if _pet.poke_system.pending_reminders.size() > 0:
		return false
	if _pet.poke_system.pending_chatter != "":
		return false
	
	# ── 全部条件满足，触发 ──
	_do_prompt(remaining, total)
	return true

func _do_prompt(remaining: int, total: int) -> void:
	_prompted_today = true
	SettingsManager.set_int("todo_last_prompt_date", _get_today_int())
	
	var line = _pick_line(remaining, total)
	
	# 宠物轻弹跳引起注意
	if _pet.behavior_mode == 0:
		_pet.apply_central_impulse(Vector2(randf_range(-30, 30), -300))
		_pet.apply_torque_impulse(randf_range(-600, 600))
	
	# 创建常驻气泡 + 双侧按钮
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(_pet):
		_create_prompt_ui(line)

# ═══════════════════════════════════════════════
#  话术选择
# ═══════════════════════════════════════════════

func _pick_line(remaining: int, total: int) -> String:
	var hour: int = Time.get_time_dict_from_system()["hour"]
	var pool: Array[String] = []
	if hour >= 6 and hour < 12:
		pool.assign(MORNING_LINES)
	elif hour >= 12 and hour < 18:
		pool.assign(AFTERNOON_LINES)
	else:
		pool.assign(EVENING_LINES)
	
	var line = pool[randi() % pool.size()]
	var done = total - remaining
	line = line.replace("{n}", str(remaining))
	line = line.replace("{done}", str(done))
	line = line.replace("{total}", str(total))
	return line

# ═══════════════════════════════════════════════
#  UI 创建
# ═══════════════════════════════════════════════

func _create_prompt_ui(message: String) -> void:
	_dismiss_all()
	
	# ── 常驻气泡 (宠物上方) ──
	_bubble = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.14, 0.24, 0.92)
	sb.border_color = Color(0.35, 0.50, 0.75, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_bubble.add_theme_stylebox_override("panel", sb)
	var label = Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_bubble.add_child(label)
	_bubble.modulate.a = 0.0
	add_child(_bubble)
	
	# ── 左侧按钮: "知道了" ──
	_btn_dismiss = _make_pill_btn("知道了", Color(0.55, 0.55, 0.55, 0.85), Color(0.65, 0.65, 0.65, 0.5))
	_btn_dismiss.pressed.connect(_on_dismiss)
	_btn_dismiss.modulate.a = 0.0
	add_child(_btn_dismiss)
	
	# ── 右侧按钮: "查看待办" ──
	_btn_accept = _make_pill_btn("查看待办", Color(0.30, 0.55, 0.42, 0.9), Color(0.38, 0.63, 0.50, 0.5))
	_btn_accept.pressed.connect(_on_accept)
	_btn_accept.modulate.a = 0.0
	add_child(_btn_accept)
	
	_showing = true
	_update_positions()
	
	# 淡入
	var tw = create_tween().set_parallel(true)
	tw.tween_property(_bubble, "modulate:a", 1.0, 0.3)
	tw.tween_property(_btn_dismiss, "modulate:a", 1.0, 0.3).set_delay(0.15)
	tw.tween_property(_btn_accept, "modulate:a", 1.0, 0.3).set_delay(0.15)

func _make_pill_btn(text: String, bg: Color, border: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	# 文字黑色描边 (任何背景都能看清)
	btn.add_theme_constant_override("outline_size", 3)
	btn.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	btn.flat = false
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Color(0.0, 0.0, 0.0, 0.7)  # 黑色外框
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(bg.r + 0.08, bg.g + 0.08, bg.b + 0.08, 1.0)
	h.border_color = Color(0.9, 0.9, 0.9, 0.6)  # hover 时白色边框反馈
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

# ═══════════════════════════════════════════════
#  位置跟随
# ═══════════════════════════════════════════════

func _update_positions() -> void:
	if not is_instance_valid(_pet):
		_dismiss_all()
		return
	
	var pet_pos = _pet.global_position
	var vp = get_viewport().get_visible_rect().size
	var pet_r: float = _pet.PET_RADIUS
	const MARGIN := 4.0  # 屏幕边距
	
	# ── 气泡: 宠物正上方居中 ──
	if is_instance_valid(_bubble):
		var bw = _bubble.size.x
		var bh = _bubble.size.y
		_bubble.position = Vector2(
			pet_pos.x - bw * 0.5,
			pet_pos.y - pet_r - bh - 16.0
		)
		# 上边界守卫: 上方放不下就翻到下方
		if _bubble.position.y < MARGIN:
			_bubble.position.y = pet_pos.y + pet_r + 16.0
		# 左右边界守卫: clamp 到屏幕内
		_bubble.position.x = clampf(_bubble.position.x, MARGIN, maxf(MARGIN, vp.x - bw - MARGIN))
	
	# ── 按钮垂直居中与宠物 ──
	var btn_y = pet_pos.y - 14.0  # 按钮中心对齐宠物中心
	var btn_gap = 12.0            # 按钮与宠物的间距
	
	# 检查左侧是否有足够空间 (需 ~90px)
	var left_space = pet_pos.x - pet_r - btn_gap
	var right_space = vp.x - (pet_pos.x + pet_r + btn_gap)
	
	if is_instance_valid(_btn_dismiss) and is_instance_valid(_btn_accept):
		var dw = _btn_dismiss.size.x
		var dh = _btn_dismiss.size.y
		var aw = _btn_accept.size.x
		var ah = _btn_accept.size.y
		
		if left_space >= dw + 10 and right_space >= aw + 10:
			# ── 标准布局: 左知道了 / 右查看待办 ──
			_btn_dismiss.position = Vector2(
				pet_pos.x - pet_r - btn_gap - dw,
				btn_y
			)
			_btn_accept.position = Vector2(
				pet_pos.x + pet_r + btn_gap,
				btn_y
			)
		elif right_space >= dw + aw + 20:
			# ── 左侧不够: 两个按钮都放右侧 ──
			_btn_dismiss.position = Vector2(
				pet_pos.x + pet_r + btn_gap,
				btn_y
			)
			_btn_accept.position = Vector2(
				pet_pos.x + pet_r + btn_gap + dw + 8.0,
				btn_y
			)
		else:
			# ── 右侧也不够: 都放左侧 ──
			_btn_accept.position = Vector2(
				pet_pos.x - pet_r - btn_gap - aw,
				btn_y
			)
			_btn_dismiss.position = Vector2(
				pet_pos.x - pet_r - btn_gap - aw - dw - 8.0,
				btn_y
			)
		
		# ── 最终边界 clamp: 确保按钮不超出屏幕 ──
		_btn_dismiss.position.x = clampf(_btn_dismiss.position.x, MARGIN, maxf(MARGIN, vp.x - dw - MARGIN))
		_btn_dismiss.position.y = clampf(_btn_dismiss.position.y, MARGIN, maxf(MARGIN, vp.y - dh - MARGIN))
		_btn_accept.position.x = clampf(_btn_accept.position.x, MARGIN, maxf(MARGIN, vp.x - aw - MARGIN))
		_btn_accept.position.y = clampf(_btn_accept.position.y, MARGIN, maxf(MARGIN, vp.y - ah - MARGIN))
	
	# 更新 hit_region
	_update_hit_rects()

func _update_hit_rects() -> void:
	if not is_instance_valid(_pet):
		return
	var rects: Array[Rect2] = []
	if is_instance_valid(_bubble):
		rects.append(Rect2(_bubble.position, _bubble.size))
	if is_instance_valid(_btn_dismiss):
		rects.append(Rect2(_btn_dismiss.position, _btn_dismiss.size))
	if is_instance_valid(_btn_accept):
		rects.append(Rect2(_btn_accept.position, _btn_accept.size))
	# 合并为一个大矩形存入 meta
	if rects.size() > 0:
		var min_pos = rects[0].position
		var max_end = rects[0].end
		for r in rects:
			min_pos.x = minf(min_pos.x, r.position.x)
			min_pos.y = minf(min_pos.y, r.position.y)
			max_end.x = maxf(max_end.x, r.end.x)
			max_end.y = maxf(max_end.y, r.end.y)
		_pet.set_meta("prompt_btn_rect", Rect2(min_pos, max_end - min_pos))

# ═══════════════════════════════════════════════
#  交互回调
# ═══════════════════════════════════════════════

func _on_accept() -> void:
	EventBus.show_todo_panel.emit()
	_dismiss_all()

func _on_dismiss() -> void:
	_dismiss_all()

func _dismiss_all() -> void:
	_showing = false
	if is_instance_valid(_pet):
		_pet.remove_meta("prompt_btn_rect")
	
	var nodes: Array[Control] = []
	if is_instance_valid(_bubble):
		nodes.append(_bubble)
	if is_instance_valid(_btn_dismiss):
		nodes.append(_btn_dismiss)
	if is_instance_valid(_btn_accept):
		nodes.append(_btn_accept)
	_bubble = null
	_btn_dismiss = null
	_btn_accept = null
	
	if nodes.size() == 0:
		return
	var tw = create_tween().set_parallel(true)
	for n in nodes:
		tw.tween_property(n, "modulate:a", 0.0, BTN_FADE_TIME)
	tw.finished.connect(func():
		for n2 in nodes:
			if is_instance_valid(n2):
				n2.queue_free()
	)

## 调试: 强制触发待办提醒 (绕过所有条件检查)
func _on_force_trigger() -> void:
	if not is_instance_valid(_pet):
		return
	_dismiss_all()
	_prompted_today = false
	var todos = SettingsManager.get_todos()
	var remaining := 0
	var total := todos.size()
	for t in todos:
		if not t.get("done", false):
			remaining += 1
	if remaining <= 0:
		# 没有待办时用专用话术
		_prompted_today = true
		SettingsManager.set_int("todo_last_prompt_date", _get_today_int())
		if _pet.behavior_mode == 0:
			_pet.apply_central_impulse(Vector2(randf_range(-30, 30), -300))
		await get_tree().create_timer(0.3).timeout
		if is_instance_valid(_pet):
			var empty_lines := [
				"待办队列为空。...要记点什么吗？",
				"当前无挂起事务。需要新建吗？",
				"今日无待办。...闲着也是闲着。",
			]
			_create_prompt_ui(empty_lines[randi() % empty_lines.size()])
		return
	_do_prompt(remaining, total)

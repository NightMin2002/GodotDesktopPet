# pet_holo_screen.gd — 宠物全息屏主控制器 (RefCounted)
# 管理全息迷你屏的渲染 (梯形透视)、屏幕矩形计算
# Phase 2: 支持多显示模式 (游戏 / 待机屏保)
class_name PetHoloScreen extends RefCounted

enum Mode { OFF, GAME, IDLE, LOADING, BATTERY, DONE, MAIL, ERROR }

var pet: RigidBody2D  # 由 pet.gd 注入

# ── 屏幕状态 ──
var visible: bool = false
var side: float = 1.0  # 全息屏方向: 1=右侧, -1=左侧
var mode: Mode = Mode.OFF

## 是否处于终端模式 (非 OFF / 非 GAME 的任何模式)
## 新增模式时无需修改，自动纳入
var is_terminal_mode: bool:
	get: return mode != Mode.OFF and mode != Mode.GAME

# ── 展开/收起动画 ──
var _deploy_progress: float = 0.0  # 0.0=完全收起, 1.0=完全展开
var _deploying: bool = false
var _retracting: bool = false
const DEPLOY_SPEED := 4.0  # 展开速度 (Hz)
const RETRACT_SPEED := 5.0  # 收起速度 (Hz)

# ── 动态间距 (全息屏 ↔ 宠物本体) ──
var _current_gap: float = 0.0  # 当前平滑插值后的实际间距
const GAP_GAME := 0.15       # 游戏模式: 内容自带内边距，可以贴近
const GAP_TERMINAL := 0.5    # 终端模式: 内容绘制到边缘，需要更大间距
const GAP_MIN := 0.1         # 绝对下限 (防止插入模型核心)
const GAP_MAX := 0.7         # 绝对上限 (防止漂移脱节)
const GAP_LERP_SPEED := 5.0  # 平滑过渡速度

# ── 纹理源 (游戏模式通过回调获取) ──
var _texture_provider: Callable = Callable()  # 返回 Texture2D 的回调

# ── 模块化渲染器 (懒加载) ──
var _mode_idle: HoloModeIdle
var _mode_loading: HoloModeLoading
var _mode_battery: HoloModeBattery
var _mode_done: HoloModeDone
var _mode_mail: HoloModeMail
var _mode_error: HoloModeError

# ── 待机/加载共享状态 ──
var _idle_duration: float = 0.0  # 屏保总时长 (0=不自动隐藏)
var _idle_elapsed: float = 0.0  # 屏保已运行时间

# ── 待机模式: 宠物锁定 + 踏板 ──
var _platform: StaticBody2D = null
var _lift_phase: int = 0  # 0=空闲, 1=上升中, 2=已到位
var _lift_target_y: float = 0.0

# ── 待机模式: 关闭按钮 ──
var _close_btn: Button = null

# ── 加载模式 ──
var _loading_label_text: String = ""

# ── 关闭互动话术 ──
const CLOSE_LINES := [
	"...连接中断。",
	"...数据流已暂停。",
	"终端已收起。",
	"会话结束。",
]

# ══════════════════════════════════════
# 公开接口
# ══════════════════════════════════════

## 显示全息屏 (游戏模式: 接收纹理回调)
func show_game(texture_provider: Callable, screen_side: float) -> void:
	# 如果当前在待机/加载/电池模式, 先清理干净
	if is_terminal_mode:
		_cleanup_active_mode()
	side = screen_side
	_texture_provider = texture_provider
	mode = Mode.GAME
	# 游戏模式直接显示 (无展开动画, 和 phase 1 行为一致)
	visible = true
	_deploy_progress = 1.0
	_deploying = false
	_retracting = false

## 显示全息屏 (待机屏保模式)
## duration: 屏保时长 (秒), 0=不自动隐藏
func show_idle(screen_side: float, duration: float = 0.0) -> void:
	side = screen_side
	mode = Mode.IDLE
	_idle_duration = duration
	_idle_elapsed = 0.0
	_get_mode_idle().init()
	# 展开动画
	visible = true
	_deploying = true
	_retracting = false
	# 锁定宠物 + 生成踏板
	_lock_pet()
	# 创建关闭按钮
	_create_close_btn()

## 隐藏全息屏 (带收起动画)
func hide() -> void:
	if mode == Mode.GAME:
		# 游戏模式直接隐藏 (和 phase 1 行为一致)
		visible = false
		mode = Mode.OFF
		_deploy_progress = 0.0
		_texture_provider = Callable()
		_deploying = false
		_retracting = false
		return
	# 非游戏模式: 收起动画
	_retracting = true
	_deploying = false
	_texture_provider = Callable()
	# 清理当前模式的资源
	_cleanup_active_mode()

## 显示全息屏 (加载模式: 旋转弧线 + 状态标签)
## label_text: 状态文字 (如 "LOADING", "SYS.CHECK")
func show_loading(label_text: String, screen_side: float, duration: float = 0.0) -> void:
	# 如果当前在其他模式, 先清理
	if is_terminal_mode:
		_cleanup_active_mode()
	side = screen_side
	mode = Mode.LOADING
	_get_mode_loading().init()
	_loading_label_text = label_text
	_idle_duration = duration
	_idle_elapsed = 0.0
	visible = true
	_deploying = true
	_retracting = false
	# 锁定宠物 + 踏板
	_lock_pet()
	# 创建关闭按钮 (双态: 默认显示状态文字, 悬停变断开连接)
	_create_close_btn(label_text)

## 显示全息屏 (电池状态模式)
func show_battery(screen_side: float, duration: float = 0.0) -> void:
	if is_terminal_mode:
		_cleanup_active_mode()
	side = screen_side
	mode = Mode.BATTERY
	_get_mode_battery().init()
	_idle_duration = duration
	_idle_elapsed = 0.0
	visible = true
	_deploying = true
	_retracting = false
	_lock_pet()
	_create_close_btn("电源监测")

## 显示终端操作完成 (打勾动画)
func show_done(screen_side: float, duration: float = 3.0) -> void:
	if is_terminal_mode:
		_cleanup_active_mode()
	side = screen_side
	mode = Mode.DONE
	_get_mode_done().init()
	_idle_duration = duration
	_idle_elapsed = 0.0
	visible = true
	_deploying = true
	_retracting = false
	_lock_pet()
	_create_close_btn("完成")

## 显示邮件通知
func show_mail(screen_side: float, duration: float = 0.0) -> void:
	if is_terminal_mode:
		_cleanup_active_mode()
	side = screen_side
	mode = Mode.MAIL
	_get_mode_mail().init()
	_idle_duration = duration
	_idle_elapsed = 0.0
	visible = true
	_deploying = true
	_retracting = false
	_lock_pet()
	_create_close_btn("新消息")

## 显示报错警示
func show_error(screen_side: float, duration: float = 0.0) -> void:
	if is_terminal_mode:
		_cleanup_active_mode()
	side = screen_side
	mode = Mode.ERROR
	_get_mode_error().init()
	_idle_duration = duration
	_idle_elapsed = 0.0
	visible = true
	_deploying = true
	_retracting = false
	_lock_pet()
	_create_close_btn("警告确认")

## 每帧更新 (由 pet._process 调用, 驱动动画)
func update(delta: float) -> void:
	# 展开动画
	if _deploying:
		_deploy_progress = minf(_deploy_progress + DEPLOY_SPEED * delta, 1.0)
		if _deploy_progress >= 1.0:
			_deploying = false
		pet.queue_redraw()
	# 收起动画
	elif _retracting:
		_deploy_progress = maxf(_deploy_progress - RETRACT_SPEED * delta, 0.0)
		if _deploy_progress <= 0.0:
			_retracting = false
			visible = false
			mode = Mode.OFF
		pet.queue_redraw()
	# 动态间距平滑过渡
	_update_dynamic_gap(delta)
	# 屏保动画 + 自动隐藏计时
	if mode == Mode.IDLE and visible:
		_get_mode_idle().time += delta
		_idle_elapsed += delta
		# 到时自动收起
		if _idle_duration > 0.0 and _idle_elapsed >= _idle_duration and not _retracting:
			hide()
		# 踏板上升驱动
		_update_platform(delta)
		# 锁定宠物位置
		if _lift_phase == 2 and is_instance_valid(_platform):
			pet.linear_velocity = Vector2.ZERO
			pet.global_position.y = _platform.position.y - pet.PET_RADIUS * pet.gravity_sign
		elif _lift_phase == 0:
			pet.linear_velocity = Vector2.ZERO
		# 关闭按钮: 悬停检测 + 位置同步
		_update_close_btn_hover()
		_update_close_btn_position()
		pet.queue_redraw()
	# 动画通用逻辑 (共用更新计时器)
	if is_terminal_mode and visible:
		var active_mode
		if mode == Mode.LOADING: active_mode = _get_mode_loading()
		elif mode == Mode.BATTERY: active_mode = _get_mode_battery()
		elif mode == Mode.DONE: active_mode = _get_mode_done()
		elif mode == Mode.MAIL: active_mode = _get_mode_mail()
		elif mode == Mode.ERROR: active_mode = _get_mode_error()
		else: active_mode = _get_mode_idle() # IDLE也有time但有些不一样，不过这样处理时间无妨，这里简化只看时间累加
		
		if "time" in active_mode:
			active_mode.time += delta
		_idle_elapsed += delta
		if _idle_duration > 0.0 and _idle_elapsed >= _idle_duration and not _retracting:
			hide()
		_update_platform(delta)
		if _lift_phase == 2 and is_instance_valid(_platform):
			pet.linear_velocity = Vector2.ZERO
			pet.global_position.y = _platform.position.y - pet.PET_RADIUS * pet.gravity_sign
		elif _lift_phase == 0:
			pet.linear_velocity = Vector2.ZERO
		_update_close_btn_hover()
		_update_close_btn_position()
		pet.queue_redraw()

# ══════════════════════════════════════
# 渲染
# ══════════════════════════════════════

## 全息迷你屏渲染 (由 pet.gd._draw() 调用)
func render() -> void:
	if not visible or _deploy_progress <= 0.0:
		return
	var hue = EventBus.ui_hue
	# 在世界坐标系中绘制 (反旋转刚体旋转)
	pet.draw_set_transform(Vector2.ZERO, -pet.rotation, Vector2.ONE)

	# 动态间距: 根据当前模式自适应平滑调整
	var gap = _current_gap if _current_gap > 0.01 else pet.PET_RADIUS * GAP_TERMINAL
	var holo_w: float = pet.PET_RADIUS * 2.0
	var holo_h: float = pet.PET_RADIUS * 2.5

	# 展开动画: 从宠物体表横向展开
	var anim_w = holo_w * _deploy_progress
	var anim_h = holo_h * _deploy_progress

	# 全息屏中心 (展开时从近端边缘向外推)
	var cx = side * (gap + anim_w * 0.5)
	var cy = 0.0  # 垂直居中于宠物中心

	# 投影支架线 (透明度随展开进度)
	var beam_alpha = _deploy_progress
	var near_edge_x = cx - side * anim_w * 0.5  # 靠近宠物的边
	var beam_start = Vector2(side * pet.PET_RADIUS * 0.6, 0)
	var beam_end = Vector2(near_edge_x, cy)
	pet.draw_line(beam_start, beam_end, Color.from_hsv(hue, 0.3, 0.8, 0.2 * beam_alpha), 0.8, true)
	pet.draw_circle(beam_start, 1.5, Color.from_hsv(hue, 0.4, 1.0, 0.4 * beam_alpha), true, -1.0, true)

	# 梯形透视: 靠近宠物的边上下收缩，远离的边保持原高
	var half_w = anim_w / 2.0
	var half_h = anim_h / 2.0
	var shrink = 0.15  # 近端收缩比例 (15%)
	var near_half_h = half_h * (1.0 - shrink)  # 近端半高 (较短)
	var far_half_h = half_h                     # 远端半高 (原高)

	# 微后仰: 顶部向远离宠物方向偏移，模拟屏幕微倾
	var tilt = side * anim_w * 0.16

	# 梯形 4 个顶点 (左上→右上→右下→左下)
	var pts: PackedVector2Array
	if side > 0:  # 全息屏在右侧: 左边(近端)窄，右边(远端)宽
		pts = PackedVector2Array([
			Vector2(cx - half_w + tilt, cy - near_half_h),  # 左上 (近, 后仰)
			Vector2(cx + half_w + tilt, cy - far_half_h),   # 右上 (远, 后仰)
			Vector2(cx + half_w, cy + far_half_h),           # 右下 (远)
			Vector2(cx - half_w, cy + near_half_h),          # 左下 (近)
		])
	else:  # 全息屏在左侧: 右边(近端)窄，左边(远端)宽
		pts = PackedVector2Array([
			Vector2(cx - half_w + tilt, cy - far_half_h),   # 左上 (远, 后仰)
			Vector2(cx + half_w + tilt, cy - near_half_h),  # 右上 (近, 后仰)
			Vector2(cx + half_w, cy + near_half_h),          # 右下 (近)
			Vector2(cx - half_w, cy + far_half_h),           # 左下 (远)
		])

	# 根据模式渲染内容
	match mode:
		Mode.GAME:
			_render_game_content(pts, hue)
		Mode.IDLE:
			_get_mode_idle().render(pts, hue, _deploy_progress)
		Mode.LOADING:
			_get_mode_loading().render(pts, hue, _deploy_progress)
		Mode.BATTERY:
			_get_mode_battery().render(pts, hue, _deploy_progress)
		Mode.DONE:
			_get_mode_done().render(pts, hue, _deploy_progress)
		Mode.MAIL:
			_get_mode_mail().render(pts, hue, _deploy_progress)
		Mode.ERROR:
			_get_mode_error().render(pts, hue, _deploy_progress)

	# 恢复变换
	pet.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## 返回全息迷你屏在屏幕上的包围矩形 (供游戏面板定位时避让)
func get_screen_rect() -> Rect2:
	if not visible:
		return Rect2()
	var gap_val = _current_gap if _current_gap > 0.01 else pet.PET_RADIUS * GAP_TERMINAL
	var holo_w: float = pet.PET_RADIUS * 2.0
	var holo_h: float = pet.PET_RADIUS * 2.5
	var cx = side * (gap_val + holo_w * 0.5)
	var cy = 0.0
	# 转到屏幕坐标
	var pet_screen = pet.get_global_transform_with_canvas().get_origin()
	var rect_x = pet_screen.x + cx - holo_w * 0.5 - 4.0
	var rect_y = pet_screen.y + cy - holo_h * 0.5 - 4.0
	return Rect2(rect_x, rect_y, holo_w + 8.0, holo_h + 8.0)

# ══════════════════════════════════════
# 宠物锁定 + 踏板 (待机模式)
# ══════════════════════════════════════

func _lock_pet() -> void:
	# 取消正在进行的空间跳跃
	if pet.free_roam_sys.active:
		pet.free_roam_sys.finish()
	# 高阻尼停下来
	pet.linear_damp = 20.0
	pet.linear_velocity = Vector2.ZERO
	# 切到 idle 状态
	if pet.current_state_name != "idle":
		pet.transition_to("idle")
	# 生成踏板
	_spawn_platform()

func _unlock_pet() -> void:
	_lift_phase = 0
	pet.gravity_scale = pet.gravity_sign  # 恢复重力
	# 移除踏板
	if is_instance_valid(_platform):
		for child in _platform.get_children():
			if child is CollisionShape2D:
				child.disabled = true
		var plat = _platform
		_platform = null
		var tween = plat.create_tween()
		tween.tween_property(plat, "modulate:a", 0.0, 0.3)
		tween.finished.connect(func():
			if is_instance_valid(plat):
				plat.queue_free()
		)
	# 切 fall 状态自然过渡
	pet.transition_to("fall")

func _spawn_platform() -> void:
	var parent = pet.get_parent()
	if not parent:
		return
	var plat_y = pet.global_position.y + pet.PET_RADIUS * pet.gravity_sign
	var body = StaticBody2D.new()
	body.position = Vector2(pet.global_position.x, plat_y)
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(pet.PET_RADIUS * 2.0, 8.0)
	col.shape = shape
	col.one_way_collision = true
	if pet.anti_gravity:
		col.rotation = PI
	body.add_child(col)
	var visual = FreeRoamSystem.PlatformVisual.new()
	visual.platform_width = pet.PET_RADIUS * 2.0
	visual.platform_color = pet.palette.shift_color(Color(0.2, 0.6, 1.0, 0.6))
	body.add_child(visual)
	parent.add_child(body)
	body.modulate.a = 0.0
	var tween = body.create_tween()
	tween.tween_property(body, "modulate:a", 1.0, 0.3)
	_platform = body
	_lift_target_y = plat_y - 15.0 * pet.gravity_sign
	_lift_phase = 1
	pet.gravity_scale = 0.0

func _update_platform(delta: float) -> void:
	if _lift_phase == 1 and is_instance_valid(_platform):
		var lift_speed = 80.0
		_platform.position.y -= lift_speed * delta * pet.gravity_sign
		pet.global_position.y = _platform.position.y - pet.PET_RADIUS * pet.gravity_sign
		var dist = (_platform.position.y - _lift_target_y) * pet.gravity_sign
		if dist <= 0.0:
			_platform.position.y = _lift_target_y
			pet.global_position.y = _lift_target_y - pet.PET_RADIUS * pet.gravity_sign
			_lift_phase = 2

## 动态间距: 根据当前模式计算目标 gap 并平滑过渡
func _update_dynamic_gap(delta: float) -> void:
	var target_ratio: float
	match mode:
		Mode.GAME:
			target_ratio = GAP_GAME
		_:
			target_ratio = GAP_TERMINAL
	var target = pet.PET_RADIUS * clampf(target_ratio, GAP_MIN, GAP_MAX)
	if _current_gap <= 0.01:
		_current_gap = target  # 首次初始化，直接跳到目标值
	else:
		_current_gap = lerpf(_current_gap, target, delta * GAP_LERP_SPEED)

# ══════════════════════════════════════
# 关闭按钮 (待机模式, 悬停显示)
# ══════════════════════════════════════

var _close_btn_visible: bool = false  # 关闭按钮当前是否可见
var _close_btn_default_text: String = ""  # 默认显示文字 (空=始终显示断开连接)

func _create_close_btn(default_text: String = "") -> void:
	_remove_close_btn()
	var parent = pet.get_parent()
	if not parent:
		return
	_close_btn_default_text = default_text
	var hue = EventBus.ui_hue
	_close_btn = Button.new()
	# 有默认文字时初始显示状态文字, 否则显示"断开连接"
	_close_btn.text = default_text if default_text != "" else "断开连接"
	_close_btn.custom_minimum_size = Vector2(80, 28)
	_close_btn.add_theme_font_size_override("font_size", 14)
	_close_btn.add_theme_color_override("font_color", Color.from_hsv(hue, 0.25, 0.7, 0.7))
	_close_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.35, 0.3, 1.0))
	_close_btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.2, 0.2, 1.0))
	# 背景样式
	var normal_bg = StyleBoxFlat.new()
	normal_bg.bg_color = Color(0.03, 0.05, 0.1, 0.75)
	normal_bg.border_color = Color.from_hsv(hue, 0.3, 0.6, 0.25)
	normal_bg.set_border_width_all(1)
	normal_bg.set_corner_radius_all(4)
	normal_bg.content_margin_left = 12
	normal_bg.content_margin_right = 12
	normal_bg.content_margin_top = 5
	normal_bg.content_margin_bottom = 5
	var hover_bg = StyleBoxFlat.new()
	hover_bg.bg_color = Color(0.12, 0.04, 0.04, 0.85)
	hover_bg.border_color = Color(0.8, 0.25, 0.25, 0.4)
	hover_bg.set_border_width_all(1)
	hover_bg.set_corner_radius_all(4)
	hover_bg.content_margin_left = 12
	hover_bg.content_margin_right = 12
	hover_bg.content_margin_top = 5
	hover_bg.content_margin_bottom = 5
	_close_btn.add_theme_stylebox_override("normal", normal_bg)
	_close_btn.add_theme_stylebox_override("hover", hover_bg)
	_close_btn.add_theme_stylebox_override("pressed", hover_bg)
	_close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_btn.pressed.connect(_on_close_pressed)
	parent.add_child(_close_btn)
	# 有默认文字时始终显示, 否则仅悬停显示
	if default_text != "":
		_close_btn.modulate.a = 0.0
		_close_btn_visible = false
		# 延迟淡入显示状态文字
		var tween = _close_btn.create_tween()
		tween.tween_property(_close_btn, "modulate:a", 1.0, 0.4).set_delay(0.3)
		_close_btn_visible = true
	else:
		_close_btn.modulate.a = 0.0
		_close_btn_visible = false
	_update_close_btn_position()

func _update_close_btn_hover() -> void:
	if not is_instance_valid(_close_btn):
		return
	var mouse_pos = pet.get_global_mouse_position()
	var dist = pet.global_position.distance_to(mouse_pos)
	var hover_range = pet.PET_RADIUS * 3.5
	var is_near = dist <= hover_range
	# 也检测鼠标是否在按钮上
	if is_instance_valid(_close_btn) and _close_btn.get_global_rect().has_point(Vector2(mouse_pos.x, mouse_pos.y)):
		is_near = true
	# 双态逻辑
	if _close_btn_default_text != "":
		# 有默认文字: 始终显示, 悬停时切换文字
		if is_near:
			if _close_btn.text != "断开连接":
				_close_btn.text = "断开连接"
		else:
			if _close_btn.text != _close_btn_default_text:
				_close_btn.text = _close_btn_default_text
	else:
		# 无默认文字: 悬停才显示
		if is_near and not _close_btn_visible:
			_close_btn_visible = true
			var tween = _close_btn.create_tween()
			tween.tween_property(_close_btn, "modulate:a", 1.0, 0.2)
		elif not is_near and _close_btn_visible:
			_close_btn_visible = false
			var tween = _close_btn.create_tween()
			tween.tween_property(_close_btn, "modulate:a", 0.0, 0.15)

func _update_close_btn_position() -> void:
	if not is_instance_valid(_close_btn):
		return
	# 位置: 宠物头顶上方
	var pet_screen = pet.get_global_transform_with_canvas().get_origin()
	var above_y = pet_screen.y - pet.PET_RADIUS * (1.0 if not pet.anti_gravity else -1.0) - 30.0
	# 水平居中于宠物
	var btn_size = _close_btn.size if _close_btn.size.x > 0 else Vector2(70, 22)
	var btn_x = pet_screen.x - btn_size.x * 0.5
	_close_btn.position = Vector2(btn_x, above_y)

func _remove_close_btn() -> void:
	if is_instance_valid(_close_btn):
		_close_btn.queue_free()
	_close_btn = null

## 返回关闭按钮的屏幕矩形 (供 hit_region_manager 注册可点击区域)
func get_close_btn_rect() -> Rect2:
	if not is_instance_valid(_close_btn) or _close_btn.modulate.a < 0.1:
		return Rect2()
	return _close_btn.get_global_rect()

func _on_close_pressed() -> void:
	# 互动反应: 给句话
	pet.show_local_bubble(CLOSE_LINES[randi() % CLOSE_LINES.size()])
	hide()

# ══════════════════════════════════════
# 内容渲染 (私有)
# ══════════════════════════════════════

## 游戏模式: 纹理映射到梯形
func _render_game_content(pts: PackedVector2Array, _hue: float) -> void:
	var viewport_tex: Texture2D = null
	if _texture_provider.is_valid():
		viewport_tex = _texture_provider.call()
	var uvs = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	])
	if viewport_tex:
		pet.draw_polygon(pts, [Color(1, 1, 1, 0.75)], uvs, viewport_tex)

# ══════════════════════════════════════
# 渲染器懒加载
# ══════════════════════════════════════

func _get_mode_idle() -> HoloModeIdle:
	if not _mode_idle:
		_mode_idle = HoloModeIdle.new()
		_mode_idle.screen = self
	return _mode_idle

func _get_mode_loading() -> HoloModeLoading:
	if not _mode_loading:
		_mode_loading = HoloModeLoading.new()
		_mode_loading.screen = self
	return _mode_loading

func _get_mode_battery() -> HoloModeBattery:
	if not _mode_battery:
		_mode_battery = HoloModeBattery.new()
		_mode_battery.screen = self
	return _mode_battery

func _get_mode_done() -> HoloModeDone:
	if not _mode_done:
		_mode_done = HoloModeDone.new()
		_mode_done.screen = self
	return _mode_done

func _get_mode_mail() -> HoloModeMail:
	if not _mode_mail:
		_mode_mail = HoloModeMail.new()
		_mode_mail.screen = self
	return _mode_mail

func _get_mode_error() -> HoloModeError:
	if not _mode_error:
		_mode_error = HoloModeError.new()
		_mode_error.screen = self
	return _mode_error
# ══════════════════════════════════════

## 将 UV 坐标 (0~1, 0~1) 映射到梯形 pts 的屏幕坐标
## pts 顺序: [左上, 右上, 右下, 左下]
func _map_uv(pts: PackedVector2Array, u: float, v: float) -> Vector2:
	var top = pts[0].lerp(pts[1], u)
	var bot = pts[3].lerp(pts[2], u)
	return top.lerp(bot, v)

# ══════════════════════════════════════
# 统一清理
# ══════════════════════════════════════

## 清理当前活跃模式的所有资源 (踏板/按钮/解锁)
func _cleanup_active_mode() -> void:
	_unlock_pet()
	_remove_close_btn()

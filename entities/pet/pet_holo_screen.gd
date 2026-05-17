# pet_holo_screen.gd — 宠物全息屏主控制器 (RefCounted)
# 管理全息迷你屏的渲染 (梯形透视)、屏幕矩形计算
# Phase 2: 支持多显示模式 (游戏 / 待机屏保)
class_name PetHoloScreen extends RefCounted

enum Mode { OFF, GAME, IDLE, LOADING, BATTERY, DONE, MAIL, ERROR, WARNING, QUERY, ALARM, CLEANUP, GLOBE, SYNC, LOCK }

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
var _game_locked: bool = false                # GAME 模式是否锁定宠物 (游戏终端使用)

# ── 中间缩放视口 (游戏模式用: GPU 预缩小以避免极端下采样模糊) ──
var _mini_vp: SubViewport = null
var _mini_rect: TextureRect = null

# ── 模块化渲染器 (字典注册 + 懒加载) ──
# 新增模式只需: 1) enum 加值  2) 注册表加一行  3) 写渲染器文件
const _MODE_REGISTRY := {
	Mode.IDLE:    {"class": "HoloModeIdle",    "label": "待机屏保"},
	Mode.LOADING: {"class": "HoloModeLoading", "label": "终端引导"},
	Mode.BATTERY: {"class": "HoloModeBattery", "label": "电源监测"},
	Mode.DONE:    {"class": "HoloModeDone",    "label": "完成"},
	Mode.MAIL:    {"class": "HoloModeMail",    "label": "新消息"},
	Mode.ERROR:   {"class": "HoloModeError",   "label": "警告确认"},
	Mode.WARNING: {"class": "HoloModeWarning", "label": "系统警告"},
	Mode.QUERY:   {"class": "HoloModeQuery",   "label": "未知检索"},
	Mode.ALARM:   {"class": "HoloModeAlarm",   "label": "日程触发"},
	Mode.CLEANUP: {"class": "HoloModeCleanup", "label": "垃圾清理"},
	Mode.GLOBE:   {"class": "HoloModeGlobe",   "label": "网络监控"},
	Mode.SYNC:    {"class": "HoloModeSync",    "label": "网络通信"},
	Mode.LOCK:    {"class": "HoloModeLock",    "label": "终端锁定"},
}
var _renderers: Dictionary = {}  # Mode -> RefCounted 实例缓存

# ── 待机/加载共享状态 ──
var _idle_duration: float = 0.0  # 屏保总时长 (0=不自动隐藏)
var _idle_elapsed: float = 0.0  # 屏保已运行时间

# ── 宠物锁定 + 踏板 (委托 PetPlatform) ──
var _plat := PetPlatform.new()

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
## lock: 是否锁定宠物+踏板 (游戏终端模式使用)
func show_game(texture_provider: Callable, screen_side: float, lock: bool = false) -> void:
	# 如果当前在待机/加载/电池模式, 先清理干净
	if is_terminal_mode:
		_cleanup_active_mode()
	side = screen_side
	_texture_provider = texture_provider
	mode = Mode.GAME
	_game_locked = lock
	visible = true
	if lock:
		# 锁定模式: 展开动画 + 锁定宠物 + 踏板
		_deploying = true
		_retracting = false
		_lock_pet()
		_create_close_btn("游戏终端")
	else:
		# 自由模式: 直接显示 (和 phase 1 行为一致)
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
	_get_renderer(Mode.IDLE).init()
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
		if _game_locked:
			# 锁定模式: 收起动画 + 解锁宠物
			_retracting = true
			_deploying = false
			_texture_provider = Callable()
			_game_locked = false
			_cleanup_mini_vp()
			_unlock_pet()
			_remove_close_btn()
		else:
			# 自由模式: 直接隐藏
			visible = false
			mode = Mode.OFF
			_deploy_progress = 0.0
			_texture_provider = Callable()
			_cleanup_mini_vp()
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
	_get_renderer(Mode.LOADING).init()
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
	_get_renderer(Mode.BATTERY).init()
	_idle_duration = duration
	_idle_elapsed = 0.0
	visible = true
	_deploying = true
	_retracting = false
	_lock_pet()
	_create_close_btn("电源监测")

## 显示终端操作完成 (打勾动画)
func show_done(screen_side: float, duration: float = 3.0) -> void:
	_show_terminal(Mode.DONE, screen_side, duration)

## 显示邮件通知
func show_mail(screen_side: float, duration: float = 0.0) -> void:
	_show_terminal(Mode.MAIL, screen_side, duration)

## 显示报错警示
func show_error(screen_side: float, duration: float = 0.0) -> void:
	_show_terminal(Mode.ERROR, screen_side, duration)

## 显示系统轻度警告
func show_warning(screen_side: float, duration: float = 0.0) -> void:
	_show_terminal(Mode.WARNING, screen_side, duration)

## 显示未知检索
func show_query(screen_side: float, duration: float = 0.0) -> void:
	_show_terminal(Mode.QUERY, screen_side, duration)

## 显示日程闹钟提醒
func show_alarm(screen_side: float, duration: float = 0.0) -> void:
	_show_terminal(Mode.ALARM, screen_side, duration)

## 显示垃圾清理与记忆回收
func show_cleanup(screen_side: float, duration: float = 0.0) -> void:
	_show_terminal(Mode.CLEANUP, screen_side, duration)

## 显示全球网络侦测彩蛋
func show_globe(screen_side: float, duration: float = 0.0) -> void:
	_show_terminal(Mode.GLOBE, screen_side, duration)

## 显示普通级别的通讯或离线状态断点连线扫描
func show_sync(screen_side: float, duration: float = 0.0) -> void:
	_show_terminal(Mode.SYNC, screen_side, duration)

## 显示隐私/终端锁定
func show_lock(screen_side: float, duration: float = 0.0) -> void:
	_show_terminal(Mode.LOCK, screen_side, duration)

## 通用终端模式启动 (注册表驱动)
func _show_terminal(m: Mode, screen_side: float, duration: float = 0.0) -> void:
	if is_terminal_mode:
		_cleanup_active_mode()
	side = screen_side
	mode = m
	_get_renderer(m).init()
	_idle_duration = duration
	_idle_elapsed = 0.0
	visible = true
	_deploying = true
	_retracting = false
	_lock_pet()
	var label: String = _MODE_REGISTRY[m]["label"] if m in _MODE_REGISTRY else "终端"
	_create_close_btn(label)

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
	# 终端模式通用逻辑 (含 IDLE, 注册表驱动)
	if is_terminal_mode and visible:
		var active_renderer = _get_renderer(mode)
		if active_renderer and "time" in active_renderer:
			active_renderer.time += delta
		_idle_elapsed += delta
		if _idle_duration > 0.0 and _idle_elapsed >= _idle_duration and not _retracting:
			hide()
		# 踏板升降驱动 + 位置锁定
		_plat.update(pet, delta)
		if not _plat.is_active:
			pet.linear_velocity = Vector2.ZERO
		_update_close_btn_hover()
		_update_close_btn_position()
		pet.queue_redraw()
	# GAME 锁定模式: 驱动踏板 + 关闭按钮
	elif mode == Mode.GAME and _game_locked and visible:
		_plat.update(pet, delta)
		if not _plat.is_active:
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
	# 在世界坐标系中绘制 (visual_rotation 已包含反重力翻转)
	pet.draw_set_transform(Vector2.ZERO, -pet.visual_rotation, Vector2.ONE)

	# 动态间距: 根据当前模式自适应平滑调整
	var gap = _current_gap if _current_gap > 0.01 else pet.PET_RADIUS * GAP_TERMINAL
	var holo_w: float
	var holo_h: float
	if mode == Mode.GAME:
		# 游戏模式: 匹配宠物体型 + 4:3 宽高比
		holo_w = pet.PET_RADIUS * 2.5
		holo_h = pet.PET_RADIUS * 1.9
	else:
		holo_w = pet.PET_RADIUS * 2.0
		holo_h = pet.PET_RADIUS * 2.5

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
	var shrink = 0 # 近端收缩比例 (15%)
	var near_half_h = half_h * (1.0 - shrink)  # 近端半高 (较短)
	var far_half_h = half_h                     # 远端半高 (原高)

	# 微后仰: 顶部向远离宠物方向偏移，模拟屏幕微倾
	var tilt = side * anim_w * 0

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
	if mode == Mode.GAME:
		_render_game_content(pts, hue)
	elif is_terminal_mode:
		var renderer = _get_renderer(mode)
		if renderer:
			renderer.render(pts, hue, _deploy_progress)

	# 恢复变换
	pet.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## 返回全息迷你屏在屏幕上的包围矩形 (供游戏面板定位时避让)
func get_screen_rect() -> Rect2:
	if not visible:
		return Rect2()
	var gap_val = _current_gap if _current_gap > 0.01 else pet.PET_RADIUS * GAP_TERMINAL
	var holo_w: float
	var holo_h: float
	if mode == Mode.GAME:
		holo_w = pet.PET_RADIUS * 2.5
		holo_h = pet.PET_RADIUS * 1.9
	else:
		holo_w = pet.PET_RADIUS * 2.0
		holo_h = pet.PET_RADIUS * 2.5
	var cx = side * (gap_val + holo_w * 0.5)
	var cy = 0.0
	# 转到屏幕坐标
	var pet_screen = pet.get_global_transform_with_canvas().get_origin()
	var rect_x = pet_screen.x + cx - holo_w * 0.5 - 4.0
	var rect_y = pet_screen.y + cy - holo_h * 0.5 - 4.0
	return Rect2(rect_x, rect_y, holo_w + 8.0, holo_h + 8.0)

# ══════════════════════════════════════
# 宠物锁定 + 踏板 (委托 PetPlatform)
# ══════════════════════════════════════

func _lock_pet() -> void:
	_plat.lock_pet(pet)

func _unlock_pet() -> void:
	_plat.unlock_pet(pet)
	pet.transition_to("fall")

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
	var anchor = pet.get_ui_anchor()
	var btn_size = _close_btn.size if _close_btn.size.x > 0 else Vector2(70, 22)
	var btn_x = anchor.center.x - btn_size.x * 0.5
	# 按钮放在宠物头顶方向 (正常=上方, 反重力=下方)
	var btn_y = anchor.head_y + anchor.head_dir * 10.0
	if anchor.head_dir < 0:
		btn_y -= btn_size.y  # 正常模式: 按钮底边对齐头顶
	_close_btn.position = Vector2(btn_x, btn_y)

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

## 游戏模式: 通过中间缩放视口映射到梯形
func _render_game_content(pts: PackedVector2Array, _hue: float) -> void:
	var viewport_tex: Texture2D = null
	if _texture_provider.is_valid():
		viewport_tex = _texture_provider.call()
	var display_tex = _get_mini_texture(viewport_tex)
	var uvs = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	])
	if display_tex:
		pet.draw_polygon(pts, [Color(1, 1, 1, 0.75)], uvs, display_tex)

## 中间缩放视口: GPU 线性过滤预缩小到接近显示尺寸, 避免 draw_polygon 的极端下采样模糊
func _get_mini_texture(source_tex: Texture2D) -> Texture2D:
	if not source_tex:
		return null
	var src_w = source_tex.get_width()
	var src_h = source_tex.get_height()
	if src_w <= 0:
		return null
	# 目标: 显示尺寸的 ~3x (质量/性能折中)
	var mini_w := 240
	var mini_h := int(float(mini_w) * float(src_h) / float(src_w))
	if not is_instance_valid(_mini_vp):
		_mini_vp = SubViewport.new()
		_mini_vp.transparent_bg = true
		_mini_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_mini_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_mini_vp.gui_disable_input = true
		_mini_rect = TextureRect.new()
		_mini_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_mini_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_mini_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mini_vp.add_child(_mini_rect)
		pet.add_child(_mini_vp)
	_mini_vp.size = Vector2i(mini_w, mini_h)
	_mini_rect.size = Vector2(mini_w, mini_h)
	_mini_rect.texture = source_tex
	return _mini_vp.get_texture()

## 清理中间缩放视口
func _cleanup_mini_vp() -> void:
	if is_instance_valid(_mini_vp):
		_mini_vp.queue_free()
	_mini_vp = null
	_mini_rect = null

# ══════════════════════════════════════
# 渲染器懒加载 (注册表驱动)
# ══════════════════════════════════════

## 通过注册表获取渲染器实例 (懒加载, 首次访问时创建)
func _get_renderer(m: Mode) -> RefCounted:
	if m in _renderers:
		return _renderers[m]
	if m not in _MODE_REGISTRY:
		return null
	var class_name_str: String = _MODE_REGISTRY[m]["class"]
	# 通过 class_name 全局注册表实例化
	var script = _resolve_mode_class(class_name_str)
	if not script:
		return null
	var instance = script.new()
	instance.screen = self
	_renderers[m] = instance
	return instance

## 查找全局 class_name 对应的 GDScript
func _resolve_mode_class(cls: String) -> GDScript:
	# Godot 4 的全局类名可以直接从 ClassDB 或 ProjectSettings 查找
	# 但 RefCounted 子类最可靠的方式是通过硬编码映射
	var map := {
		"HoloModeIdle": HoloModeIdle,
		"HoloModeLoading": HoloModeLoading,
		"HoloModeBattery": HoloModeBattery,
		"HoloModeDone": HoloModeDone,
		"HoloModeMail": HoloModeMail,
		"HoloModeError": HoloModeError,
		"HoloModeWarning": HoloModeWarning,
		"HoloModeQuery": HoloModeQuery,
		"HoloModeAlarm": HoloModeAlarm,
		"HoloModeCleanup": HoloModeCleanup,
		"HoloModeGlobe": HoloModeGlobe,
		"HoloModeSync": HoloModeSync,
		"HoloModeLock": HoloModeLock,
	}
	return map.get(cls, null)
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
	_cleanup_mini_vp()
	_unlock_pet()
	_remove_close_btn()

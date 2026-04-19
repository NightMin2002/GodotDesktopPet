# pet.gd — 宠物本体控制器
# 管理状态机、视觉渲染、输入检测
extends RigidBody2D

# ── 常量 ──
const PET_RADIUS := 30.0

# 占位符配色 (史莱姆风格)
const BODY_COLOR := Color(0.3, 0.85, 0.7, 1.0)       # 青绿色身体
const BODY_OUTLINE := Color(0.2, 0.6, 0.5, 1.0)       # 深色轮廓
const EYE_WHITE := Color(1.0, 1.0, 1.0, 1.0)
const EYE_PUPIL := Color(0.15, 0.15, 0.2, 1.0)
const CHEEK_COLOR := Color(1.0, 0.6, 0.7, 0.4)        # 腮红

# ── 状态机 ──
var states: Dictionary = {}
var current_state: PetState
var current_state_name: String = ""
var speed: float = 200.0            # 移动速度基数
var shockwave_enabled: bool = true   # 撞击冲击波特效开关
var trail_enabled: bool = true       # 粒子尾流特效开关
var hue_time: float = 0.0           # 供虹彩渐变使用的时间戳

# ── 克隆系统 ──
var is_clone: bool = false           # 是否为克隆分身
var clone_hue_shift: float = 0.0    # 克隆体色调偏移 (0~1 HSV hue offset)

# ── 全息时钟 HUD ──
var hud_clock_label: Label
var hud_clock_enabled: bool = false
var hud_bounce_time: float = 0.0
var _is_clock_hidden: bool = false

# ── 眼球行为控制器 ──
var eye_behavior: EyeBehavior

# ── 特效系统 ──
var trail_history: Array[Vector2] = [] # 全息拖影坐标缓存数组
var max_trail_length: int = 15         # 光晕段数
var shockwaves: Array[Dictionary] = [] # 冲击波队列

func get_shockwaves_count() -> int:
	return shockwaves.size()

func trigger_shockwave() -> void:
	# 双层高能震荡波，瞬间爆发
	shockwaves.append({"local_pos": Vector2.ZERO, "radius": PET_RADIUS, "alpha": 1.0})
	shockwaves.append({"local_pos": Vector2.ZERO, "radius": PET_RADIUS * 0.4, "alpha": 0.5})

# ── 屏幕信息 (由 main.gd 设置) ──
var screen_rect: Rect2i
var boundary_size: Vector2  # 视口坐标系的实际边界
var last_frame_speed: float = 0.0 # 用于捕获撞击前瞬时速度
var overlay_rect: Rect2 = Rect2() # 外部覆盖层的屏幕区域 (气泡通知等)

# ── 本地定向气泡 (戳一戳/吐槽等，每个宠物独立显示，支持向上堆叠) ──
const MAX_LOCAL_BUBBLES := 3
var _local_bubbles: Array[PanelContainer] = []

# ── 窗口交互模式 (由 main.gd 通过 EventBus 同步) ──
var window_mode: int = 0  # 0=FREE, 1=CONFINED, 2=REPELLED

# ── 行为指令 ──
var behavior_mode: int = 0  # 0=FREE(自由行动), 1=QUIET(安静待命)
var _was_dragged_in_quiet: bool = false  # 安静模式下被拖拽的标记 (用于吐槽)

func _ready() -> void:
	# 物理材质 (弹性)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.4     # 降低弹力，减少无逻辑的蹦蹦跳跳
	mat.friction = 0.8   # 保持高摩擦，利于滚动
	physics_material_override = mat
	
	# 质量与阻尼
	mass = 2.0
	linear_damp = 0.5    # 增加一点线性阻尼，让平移慢下来，主要表现为原地转
	angular_damp = 0.2   # 降低一点角阻尼，让滚动持续时间长些
	
	# 开启连续碰撞检测 (防止高速穿墙)
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	
	# 开启刚体接触监听，用于最真实的物理“瞬时撞击”特效
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	
	# 初始化状态机
	_init_states()
	
	# 初始化眼球行为控制器
	eye_behavior = EyeBehavior.new()
	eye_behavior.pet = self
	
	# 从持久化存储恢复设置 (不依赖信号时序)
	if not is_clone:
		hud_clock_enabled = SettingsManager.get_bool("hud_clock", false)
	else:
		hud_clock_enabled = false  # 克隆体不显示时钟
	_init_hud_clock()
	# 本地气泡系统: 按需动态创建，无需初始化
	eye_behavior.tracking_enabled = SettingsManager.get_bool("eye_track", true)
	shockwave_enabled = SettingsManager.get_bool("shockwave", true)
	trail_enabled = SettingsManager.get_bool("trail_fx", true)
	
	# 监听运行时设置变更
	EventBus.setting_toggled.connect(_on_setting_toggled)
	EventBus.behavior_mode_changed.connect(_on_behavior_mode_changed)

func _on_setting_toggled(setting_id: String, is_on: bool) -> void:
	if setting_id == "eye_track":
		eye_behavior.tracking_enabled = is_on
	elif setting_id == "shockwave":
		shockwave_enabled = is_on
	elif setting_id == "trail_fx":
		trail_enabled = is_on
	elif setting_id == "hud_clock":
		if is_clone:
			return  # 克隆体永远不显示时钟
		hud_clock_enabled = is_on
		hud_clock_label.visible = hud_clock_enabled

func _on_behavior_mode_changed(mode: int) -> void:
	behavior_mode = mode

func _init_states() -> void:
	states = {
		"idle": preload("res://entities/pet/states/idle.gd").new(),
		"walk": preload("res://entities/pet/states/walk.gd").new(),
		"drag": preload("res://entities/pet/states/drag.gd").new(),
		"fall": preload("res://entities/pet/states/fall.gd").new(),
		"jump": preload("res://entities/pet/states/jump.gd").new(),
		"retreat": preload("res://entities/pet/states/retreat.gd").new(),
	}
	for state in states.values():
		state.pet = self
	transition_to("fall")  # 初始从空中掉落

func transition_to(state_name: String) -> void:
	if state_name == current_state_name:
		return
	var old_name = current_state_name
	if current_state:
		current_state.exit()
	current_state = states.get(state_name)
	current_state_name = state_name
	if current_state:
		current_state.enter()
	EventBus.pet_state_changed.emit(old_name, state_name)

func _init_hud_clock() -> void:
	hud_clock_label = Label.new()
	hud_clock_label.top_level = true # 脱离刚体物理旋转限定，保持悬浮
	# 极简高对比机能风：纯黑字核 + 闪亮的白金光晕边框
	hud_clock_label.add_theme_font_size_override("font_size", 16)
	hud_clock_label.add_theme_color_override("font_color", Color(0.02, 0.02, 0.02, 0.9)) # 核心深邃黑
	hud_clock_label.add_theme_color_override("font_outline_color", Color(0.9, 0.95, 1.0, 0.9)) # 强力抗白光抗锯齿泛白边
	hud_clock_label.add_theme_constant_override("outline_size", 6)
	hud_clock_label.visible = hud_clock_enabled
	add_child(hud_clock_label)

## 创建一个本地气泡面板 (每次调用 show_local_bubble 动态创建)
func _create_local_bubble_panel(message: String) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.top_level = true  # 脱离刚体物理旋转
	panel.custom_minimum_size = Vector2(60, 30)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.1, 0.2, 0.92)
	var border_hue = fmod(0.13 + clone_hue_shift, 1.0)  # 金色基底 + 色偏
	style.border_color = Color.from_hsv(border_hue, 0.7, 1.0, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	
	var label = Label.new()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.85, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = message
	panel.add_child(label)
	return panel

func show_local_bubble(message: String) -> void:
	# 超出上限时移除最旧的气泡
	while _local_bubbles.size() >= MAX_LOCAL_BUBBLES:
		var oldest = _local_bubbles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	
	var panel = _create_local_bubble_panel(message)
	add_child(panel)
	_local_bubbles.append(panel)
	
	# 弹入动画
	var pet_pos = get_global_transform_with_canvas().get_origin()
	panel.position = pet_pos + Vector2(-80, -90)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.5, 0.5)
	panel.show()
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	
	# 独立协程管理消亡 (不影响其他气泡)
	_schedule_bubble_removal(panel)

## 气泡到期后淡出上飘并销毁
func _schedule_bubble_removal(panel: PanelContainer) -> void:
	await get_tree().create_timer(4.0).timeout
	if not is_instance_valid(panel): return
	
	var fade = create_tween().set_parallel(true)
	fade.tween_property(panel, "modulate:a", 0.0, 0.6)
	fade.tween_property(panel, "position:y", panel.position.y - 30, 0.6)
	await fade.finished
	if not is_instance_valid(panel): return
	_local_bubbles.erase(panel)
	panel.queue_free()

## 返回所有可见本地气泡的屏幕矩形 (供 main.gd 作为独立 DWM 小矩形注册)
func get_local_bubble_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for panel in _local_bubbles:
		if is_instance_valid(panel) and panel.visible:
			var r = Rect2(panel.position, panel.get_combined_minimum_size())
			r = r.grow(5)
			result.append(r)
	return result

# ── 辅助方法 ──

func is_mouse_on_pet() -> bool:
	var mouse_pos = get_global_mouse_position()
	return global_position.distance_to(mouse_pos) <= PET_RADIUS + 15.0

func is_settled() -> bool:
	return linear_velocity.length() < 20.0 and abs(linear_velocity.y) < 10.0

func get_render_rect() -> Rect2:
	# 初始框定宠物本体
	var rect := Rect2(global_position - Vector2(PET_RADIUS, PET_RADIUS), Vector2(PET_RADIUS * 2.0, PET_RADIUS * 2.0))
	
	# 囊括长长的拖影尾巴
	for pos in trail_history:
		rect = rect.expand(pos + Vector2(PET_RADIUS, PET_RADIUS))
		rect = rect.expand(pos - Vector2(PET_RADIUS, PET_RADIUS))
		
	# 囊括所有的爆炸冲击波（注意：冲击波位置目前位于 local_pos）
	for shock in shockwaves:
		var sr: float = shock["radius"] + 15.0
		var s_pos = global_position + shock["local_pos"]
		rect = rect.expand(s_pos + Vector2(sr, sr))
		rect = rect.expand(s_pos - Vector2(sr, sr))
		
	# 加入外扩安全边界像素，确保抗锯齿边缘光斑不会贴墙被裁剪
	rect.position -= Vector2(10, 10)
	rect.size += Vector2(20, 20)
	
	# 合并全息时钟 UI 区域
	if hud_clock_enabled and is_instance_valid(hud_clock_label) and hud_clock_label.visible:
		var clock_rect = Rect2(hud_clock_label.global_position, hud_clock_label.get_minimum_size())
		# 为时钟增加一点外边框余量
		clock_rect.position -= Vector2(5, 5)
		clock_rect.size += Vector2(10, 10)
		rect = rect.merge(clock_rect)
	
	# 注意: overlay_rect (全局气泡) 和 local_bubble_rects (本地气泡)
	# 均由 main.gd._update_passthrough_box() 作为独立小矩形注册到 DWM
	# 不合并进宠物本体 rect，避免产生巨大 AABB 挡桌面点击
	
	return rect

# ── 主循环 ──

func _process(delta: float) -> void:
	if current_state:
		current_state.process(delta)
	
	# 更新全息时钟
	if hud_clock_enabled and is_instance_valid(hud_clock_label):
		hud_bounce_time += delta * 2.0
		var time_dict = Time.get_time_dict_from_system()
		hud_clock_label.text = "%02d:%02d:%02d" % [time_dict.hour, time_dict.minute, time_dict.second]
		
		# 加入类似 AR 投影悬浮抖动的垂直缓动数学波
		var float_y = sin(hud_bounce_time) * 4.0
		var text_size = hud_clock_label.get_minimum_size()
		var center_p = global_position + Vector2(-text_size.x / 2.0, -PET_RADIUS - 28.0 + float_y)
		hud_clock_label.global_position = center_p
		
		# 当气泡出现（全局或本地）时自动避让隐藏时钟，防字体重叠
		var should_hide = (overlay_rect.size != Vector2.ZERO) or _local_bubbles.size() > 0
		if should_hide != _is_clock_hidden:
			_is_clock_hidden = should_hide
			var tw = create_tween()
			if should_hide:
				tw.tween_property(hud_clock_label, "modulate:a", 0.0, 0.2)
			else:
				tw.tween_property(hud_clock_label, "modulate:a", 1.0, 0.3)
	
	# 更新眼球行为（追踪/游走/眨眼）
	eye_behavior.update(delta)
	
	# 本地气泡堆叠跟随宠物位置 (最新的最靠近宠物，旧的依次向上推)
	if _local_bubbles.size() > 0:
		# 清理已释放的无效引用
		var valid_bubbles: Array[PanelContainer] = []
		for b in _local_bubbles:
			if is_instance_valid(b) and b.visible:
				valid_bubbles.append(b)
		_local_bubbles = valid_bubbles
		
		var pet_pos = get_global_transform_with_canvas().get_origin()
		var stack_y := 0.0
		var vp = get_viewport_rect().size
		# 从最新到最旧遍历 (最新的紧贴宠物头顶)
		for i in range(_local_bubbles.size() - 1, -1, -1):
			var panel = _local_bubbles[i]
			var min_size = panel.get_combined_minimum_size()
			var target_pos = pet_pos + Vector2(-min_size.x / 2.0, -90 - stack_y)
			target_pos.x = clampf(target_pos.x, 8, vp.x - min_size.x - 8)
			target_pos.y = clampf(target_pos.y, 8, vp.y - min_size.y - 8)
			panel.position = panel.position.lerp(target_pos, delta * 10.0)
			stack_y += min_size.y + 6  # 堆叠间距
	
	# 收集或消散残影以形成拖尾特效
	var has_visual_change := false
	if trail_enabled and linear_velocity.length() > 20.0:
		trail_history.push_front(global_position)
		if trail_history.size() > max_trail_length:
			trail_history.pop_back()
		has_visual_change = true
	else:
		if trail_history.size() > 0:
			trail_history.pop_back()
			has_visual_change = true
			
	hue_time += delta * 0.3
	
	# 计算冲击波爆炸圈扩散和消散
	var active_shocks: Array[Dictionary] = []
	for shock in shockwaves:
		shock["radius"] += 400.0 * delta
		shock["alpha"] -= 1.8 * delta
		if shock["alpha"] > 0:
			active_shocks.append(shock)
	if shockwaves.size() > 0:
		has_visual_change = true
	shockwaves = active_shocks
	
	# 按需重绘：特效活跃 / 物理运动中 / 眼球动画播放中
	if has_visual_change or linear_velocity.length() > 1.0 or eye_behavior.is_animating():
		queue_redraw()

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_process(delta)
	
	# 记录本帧物理速度，如果下帧发生撞击，就是参考依据
	last_frame_speed = linear_velocity.length()

func _on_body_entered(_body: Node) -> void:
	# 只有获得极高动量猛烈砸在底盘或者墙壁时，才激荡出强大的火花
	if shockwave_enabled and last_frame_speed > 350.0:
		trigger_shockwave()

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.input(event)
	
	if event is InputEventMouseButton:
		# 右键呼出全局追踪菜单 (HUD) — 仅原体响应
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not is_clone and is_mouse_on_pet():
				get_viewport().set_input_as_handled()
				EventBus.show_context_menu.emit(self)

# ── 视觉系统 ──

func _draw() -> void:
	# 由于不再拉伸，横纵比固定，我们可以直接使用 Godot 最安全最原生的 draw_circle
	
	# ── 绘制着陆虹彩冲击波特效 ──
	for shock in shockwaves:
		var effect_color = Color.from_hsv(fmod(hue_time + clone_hue_shift, 1.0), 0.6, 1.0, shock["alpha"])
		# 高科技空心雷达弧辐射
		draw_arc(shock["local_pos"], shock["radius"], 0, TAU, 32, effect_color, 4.0, true)

	# ── 绘制科幻全息光带拖影 (丝滑慧星彩带版) ──
	var trail_size = trail_history.size()
	if trail_size >= 2:
		var points = PackedVector2Array()
		var colors = PackedColorArray()
		for i in range(trail_size):
			var local_pos = to_local(trail_history[i])
			points.append(local_pos)
			var ratio = 1.0 - float(i) / trail_size
			
			# HSL 颜色空间：hue随时间加随粒子尾巴顺延发生偏转，产生五光十色的神圣尾迹！
			var trail_color = Color.from_hsv(fmod(hue_time + clone_hue_shift + ratio * 0.3, 1.0), 0.65, 1.0, ratio * 0.7)
			colors.append(trail_color)
			
			var fade_radius = PET_RADIUS * ratio * 0.85
			var core_color = trail_color
			core_color.a = ratio * 0.15
			draw_circle(local_pos, fade_radius, core_color)
			
		# 最后用高聚焦光束线描绘骨干
		draw_polyline_colors(points, colors, PET_RADIUS * 0.5, true)
	
	# ── 科幻单眼结构 (深度结合图2的高级优化版) ──
	# 外壳不受眨眼影响
	# 1. 边缘深色轮廓与偏深的湛蓝主外壳 (克隆体应用色调偏移)
	var shell_outline := _shift_color(Color(0.08, 0.12, 0.32, 1.0))
	var shell_main := _shift_color(Color(0.15, 0.30, 0.80, 1.0))
	draw_circle(Vector2.ZERO, PET_RADIUS + 1.2, shell_outline)
	draw_circle(Vector2.ZERO, PET_RADIUS, shell_main)
	
	# 2. 白色边框 (优化：极细、通透，更显高级科幻感)
	var border_radius = PET_RADIUS * 0.85
	draw_arc(Vector2.ZERO, border_radius, 0, TAU, 64, Color(1.0, 1.0, 1.0, 0.8), 1.2, true)
	
	# 3. 四个尖尖的角 (优化：正统的底座圆垫与独立四向锥形叶片重叠，完美还原形状)
	var dark_blue := _shift_color(Color(0.12, 0.18, 0.42, 1.0))
	var base_r = PET_RADIUS * 0.68
	var tip_dist = border_radius - 1.0  # 尖角刚刚触碰白边内侧
	
	# 绘制深蓝底盘核心
	draw_circle(Vector2.ZERO, base_r, dark_blue)
	# 绘制4个向外伸展的尖角（平滑与底盘融合的三角形）
	for i in range(4):
		var angle = i * PI / 2.0 + PI / 4.0  # 每个对角线：45, 135, 225, 315 度
		var tip_pos = Vector2(cos(angle), sin(angle)) * tip_dist
		var half_hw = PI / 10.0  # 控制尖刺的底部张角，避免过于瘦弱
		var left_base = Vector2(cos(angle - half_hw), sin(angle - half_hw)) * (base_r * 0.95)
		var right_base = Vector2(cos(angle + half_hw), sin(angle + half_hw)) * (base_r * 0.95)
		draw_polygon(PackedVector2Array([left_base, tip_pos, right_base]), PackedColorArray([dark_blue, dark_blue, dark_blue]))
	
	# 机械虹膌：眨眼时内部光圈收缩向中心
	var blink = eye_behavior.get_blink_amount()
	var iris_scale = 1.0 - blink * 0.95  # 闭眼峰值时虹膌缩至 5%
	if iris_scale > 0.05:
		# 第一层：占据主视觉的最外侧浅灰白层
		draw_circle(Vector2.ZERO, PET_RADIUS * 0.54 * iris_scale, _shift_color(Color(0.85, 0.88, 0.92, 1.0)))
		# 第二层：灰蓝色瞳环渐变层
		draw_circle(Vector2.ZERO, PET_RADIUS * 0.42 * iris_scale, _shift_color(Color(0.55, 0.65, 0.80, 1.0)))
		# 第三层：深蓝色次瞳孔
		draw_circle(Vector2.ZERO, PET_RADIUS * 0.28 * iris_scale, _shift_color(Color(0.15, 0.28, 0.68, 1.0)))
		# 第四层：极暗的黑底核心
		draw_circle(Vector2.ZERO, PET_RADIUS * 0.16 * iris_scale, _shift_color(Color(0.05, 0.08, 0.20, 1.0)))
		
		# 追踪光点 (随鼠标移动的小圆，形成有层次感的真实高光光斑)
		var pupil_pos = eye_behavior.get_pupil_offset() * iris_scale
		draw_circle(pupil_pos, PET_RADIUS * 0.11 * iris_scale, Color(1.0, 1.0, 1.0, iris_scale))
		draw_circle(pupil_pos, PET_RADIUS * 0.06 * iris_scale, Color(1.0, 1.0, 1.0, iris_scale))

## 克隆色偏工具函数: 将 RGB 颜色转到 HSV 空间偏移 hue 后转回
func _shift_color(c: Color) -> Color:
	if clone_hue_shift == 0.0:
		return c
	var h = c.h + clone_hue_shift
	if h > 1.0: h -= 1.0
	return Color.from_hsv(h, c.s, c.v, c.a)

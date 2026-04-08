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
var eye_track_mouse: bool = true

# ── 特效系统 ──
var trail_history: Array[Vector2] = [] # 全息拖影坐标缓存数组
var max_trail_length: int = 15         # 光晕段数
var shockwaves: Array[Dictionary] = [] # 冲击波队列

func trigger_shockwave() -> void:
	# 双层高能震荡波，瞬间爆发
	shockwaves.append({"local_pos": Vector2.ZERO, "radius": PET_RADIUS, "alpha": 1.0})
	shockwaves.append({"local_pos": Vector2.ZERO, "radius": PET_RADIUS * 0.4, "alpha": 0.5})

# ── 屏幕信息 (由 main.gd 设置) ──
var screen_rect: Rect2i
var boundary_size: Vector2  # 视口坐标系的实际边界
var last_frame_speed: float = 0.0 # 用于捕获撞击前瞬时速度

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
	
	# 监听设置变更
	EventBus.setting_toggled.connect(_on_setting_toggled)

func _on_setting_toggled(setting_id: String, is_on: bool) -> void:
	if setting_id == "eye_track":
		eye_track_mouse = is_on

func _init_states() -> void:
	states = {
		"idle": preload("res://entities/pet/states/idle.gd").new(),
		"walk": preload("res://entities/pet/states/walk.gd").new(),
		"drag": preload("res://entities/pet/states/drag.gd").new(),
		"fall": preload("res://entities/pet/states/fall.gd").new(),
		"jump": preload("res://entities/pet/states/jump.gd").new()
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

# ── 辅助方法 ──

func is_mouse_on_pet() -> bool:
	var mouse_pos = get_global_mouse_position()
	return global_position.distance_to(mouse_pos) <= PET_RADIUS + 15.0

func is_settled() -> bool:
	return linear_velocity.length() < 20.0 and abs(linear_velocity.y) < 10.0

func get_render_polygon() -> PackedVector2Array:
	var points := PackedVector2Array()
	
	# 囊括宠物本体四角
	var r := PET_RADIUS + 15.0
	var pos := global_position
	points.append(pos + Vector2(-r, -r))
	points.append(pos + Vector2(r, -r))
	points.append(pos + Vector2(r, r))
	points.append(pos + Vector2(-r, r))
	
	# 囊括拖影历史的所有点（大幅度削减无用空白区域）
	for t_pos in trail_history:
		points.append(t_pos + Vector2(-r, -r))
		points.append(t_pos + Vector2(r, -r))
		points.append(t_pos + Vector2(r, r))
		points.append(t_pos + Vector2(-r, r))
		
	# 囊括冲击波点
	for shock in shockwaves:
		var sr: float = shock["radius"] + 15.0
		var s_pos = pos + shock["local_pos"]
		points.append(s_pos + Vector2(-sr, -sr))
		points.append(s_pos + Vector2(sr, -sr))
		points.append(s_pos + Vector2(sr, sr))
		points.append(s_pos + Vector2(-sr, sr))
	
	# 用底层极速几何算法，抽出这些框框的外层包裹线（凸包多边形）
	return Geometry2D.convex_hull(points)

# ── 主循环 ──

func _process(delta: float) -> void:
	if current_state:
		current_state.process(delta)
	
	# 收集或消散残影以形成拖尾特效
	if linear_velocity.length() > 20.0:
		trail_history.push_front(global_position)
		if trail_history.size() > max_trail_length:
			trail_history.pop_back()
	else:
		if trail_history.size() > 0:
			trail_history.pop_back()
			
	# 计算冲击波爆炸圈扩散和消散
	var active_shocks: Array[Dictionary] = []
	for shock in shockwaves:
		shock["radius"] += 900.0 * delta # 冲击波迅速往外撕脱，速度极快
		shock["alpha"] -= 2.0 * delta    # 转瞬即逝
		if shock["alpha"] > 0:
			active_shocks.append(shock)
	shockwaves = active_shocks
	
	queue_redraw()

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_process(delta)
	
	# 记录本帧物理速度，如果下帧发生撞击，就是参考依据
	last_frame_speed = linear_velocity.length()

func _on_body_entered(_body: Node) -> void:
	# 只有获得极高动量猛烈砸在底盘或者墙壁时，才激荡出强大的火花
	if last_frame_speed > 350.0:
		trigger_shockwave()

func _input(event: InputEvent) -> void:
	if current_state:
		current_state.input(event)
	
	if event is InputEventMouseButton:
		# 右键呼出全局追踪菜单 (HUD)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_mouse_on_pet():
				get_viewport().set_input_as_handled()
				EventBus.show_context_menu.emit(self)

# ── 视觉系统 ──

func _draw() -> void:
	# 由于不再拉伸，横纵比固定，我们可以直接使用 Godot 最安全最原生的 draw_circle
	
	# ── 绘制着陆冲击波特效 ──
	for shock in shockwaves:
		# 高科技空心雷达弧辐射
		draw_arc(shock["local_pos"], shock["radius"], 0, TAU, 32, Color(0.1, 1.0, 0.9, shock["alpha"]), 4.0, true)

	# ── 绘制科幻全息光带拖影 (丝滑慧星彩带版) ──
	var trail_size = trail_history.size()
	if trail_size >= 2:
		var points = PackedVector2Array()
		var colors = PackedColorArray()
		for i in range(trail_size):
			var local_pos = to_local(trail_history[i])
			points.append(local_pos)
			var ratio = 1.0 - float(i) / trail_size
			colors.append(Color(0.2, 0.8, 1.0, ratio * 0.7))
			
			# 高级质感秘诀：在线性轨迹上垫底画一溜递减的半透明发光盘，能模拟出完美“头大尾细”的光绘粗细质感
			var fade_radius = PET_RADIUS * ratio * 0.85
			draw_circle(local_pos, fade_radius, Color(0.1, 0.6, 1.0, ratio * 0.15))
			
		# 最后用高聚焦光束线描绘骨干
		draw_polyline_colors(points, colors, PET_RADIUS * 0.5, true)
	
	# ── 科幻单眼结构 (带同轴旋转滚动的视觉效果依然保留) ──
	# 最外层深蓝包裹框
	draw_circle(Vector2.ZERO, PET_RADIUS + 2.0, Color(0.08, 0.15, 0.35, 1.0))
	# 外侧圈 (蓝色)
	draw_circle(Vector2.ZERO, PET_RADIUS, Color(0.15, 0.3, 0.65, 1.0))
	# 中间圈 (浅蓝/白)
	draw_circle(Vector2.ZERO, PET_RADIUS * 0.65, Color(0.7, 0.85, 1.0, 1.0))
	# 内侧深瞳核心
	draw_circle(Vector2.ZERO, PET_RADIUS * 0.4, Color(0.05, 0.1, 0.25, 1.0))
	
	# ── 瞳孔追踪白点 ──
	var pupil_pos := Vector2.ZERO
	if eye_track_mouse:
		# (使用局部坐标，保证滚动翻身时眼球追踪点依然正确看向鼠标)
		var to_mouse = get_local_mouse_position().normalized()
		pupil_pos = to_mouse * (PET_RADIUS * 0.2)
		
	# 亮白色机能光点
	draw_circle(pupil_pos, PET_RADIUS * 0.15, Color(0.9, 0.95, 1.0, 1.0))

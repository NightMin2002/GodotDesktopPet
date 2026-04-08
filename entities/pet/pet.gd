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

# ── 屏幕信息 (由 main.gd 设置) ──
var screen_rect: Rect2i
var boundary_size: Vector2  # 视口坐标系的实际边界

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
	
	# 初始化状态机
	_init_states()
	
	# 监听设置变更
	EventBus.setting_toggled.connect(_on_setting_toggled)

func _on_setting_toggled(setting_id: String, is_on: bool) -> void:
	if setting_id == "eye_track":
		eye_track_mouse = is_on

func _init_states() -> void:
	states = {
		"idle": StateIdle.new(),
		"walk": StateWalk.new(),
		"drag": StateDrag.new(),
		"fall": StateFall.new(),
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

# ── 主循环 ──

func _process(delta: float) -> void:
	if current_state:
		current_state.process(delta)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_process(delta)

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

func _update_visual_scale(delta: float) -> void:
	# 移除形变拉伸，因为现在球体会物理滚动，拉伸会导致视觉错位和长出“刺”来。
	# 圆形宠物就保持固定的圆比例。
	visual_scale = Vector2.ONE

func _draw() -> void:
	# 由于不再拉伸，横纵比固定，我们可以直接使用 Godot 最安全最原生的 draw_circle
	
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

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

# ── 视觉 ──
var facing_direction: float = 1.0   # 1=右, -1=左
var visual_scale := Vector2.ONE     # 压缩拉伸
var breath_time: float = 0.0        # 呼吸动画计时器

# ── 屏幕信息 (由 main.gd 设置) ──
var screen_rect: Rect2i
var boundary_size: Vector2  # 视口坐标系的实际边界

func _ready() -> void:
	# 物理材质 (弹性)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.4
	mat.friction = 0.6
	physics_material_override = mat
	
	# 质量与阻尼
	mass = 2.0
	linear_damp = 0.5
	angular_damp = 5.0
	
	# 锁定旋转 (宠物不应该旋转)
	lock_rotation = true
	
	# 开启连续碰撞检测 (防止高速穿墙)
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	
	# 初始化状态机
	_init_states()

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
	breath_time += delta
	if current_state:
		current_state.process(delta)
	_update_visual_scale(delta)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_process(delta)

func _input(event: InputEvent) -> void:
	if current_state:
		current_state.input(event)

# ── 视觉系统 ──

func _update_visual_scale(delta: float) -> void:
	var target := Vector2.ONE
	var speed = linear_velocity.length()
	
	if speed > 30.0:
		# 根据运动方向产生压缩拉伸
		var vel_norm = linear_velocity.normalized()
		var stretch = clamp(speed * 0.001, 0.0, 0.25)
		target.x = 1.0 + abs(vel_norm.x) * stretch - abs(vel_norm.y) * stretch * 0.5
		target.y = 1.0 + abs(vel_norm.y) * stretch - abs(vel_norm.x) * stretch * 0.5
	
	# 呼吸效果 (待机时)
	if current_state_name == "idle":
		target.x += sin(breath_time * 2.0) * 0.03
		target.y += sin(breath_time * 2.0 + PI) * 0.03
	
	# 保持体积守恒 (面积不变)
	target.x = clamp(target.x, 0.7, 1.3)
	target.y = clamp(target.y, 0.7, 1.3)
	
	visual_scale = visual_scale.lerp(target, delta * 10.0)

func _draw() -> void:
	var sx = visual_scale.x
	var sy = visual_scale.y
	var dir = facing_direction
	
	# ── 身体轮廓 ──
	_draw_ellipse(Vector2.ZERO, PET_RADIUS * sx + 2, PET_RADIUS * sy + 2, BODY_OUTLINE)
	
	# ── 身体 ──
	_draw_ellipse(Vector2.ZERO, PET_RADIUS * sx, PET_RADIUS * sy, BODY_COLOR)
	
	# ── 高光 ──
	var highlight_pos = Vector2(-8.0 * sx * dir, -10.0 * sy)
	_draw_ellipse(highlight_pos, 8.0 * sx, 6.0 * sy, Color(1, 1, 1, 0.25))
	
	# ── 眼睛 ──
	var eye_y = -4.0 * sy
	var eye_spacing = 10.0 * sx
	var eye_r = 7.0 * min(sx, sy)
	var pupil_r = 4.0 * min(sx, sy)
	
	# 瞳孔跟随鼠标
	var to_mouse = (get_global_mouse_position() - global_position).normalized()
	var pupil_offset = to_mouse * 2.5
	
	for side in [-1.0, 1.0]:
		var eye_pos = Vector2(side * eye_spacing, eye_y)
		# 眼白
		draw_circle(eye_pos, eye_r, EYE_WHITE)
		# 瞳孔
		draw_circle(eye_pos + pupil_offset, pupil_r, EYE_PUPIL)
		# 眼睛高光
		draw_circle(eye_pos + Vector2(-1.5, -2.5), 2.0, Color(1, 1, 1, 0.8))
	
	# ── 腮红 ──
	var cheek_y = 5.0 * sy
	_draw_ellipse(Vector2(-15.0 * sx, cheek_y), 6.0, 4.0, CHEEK_COLOR)
	_draw_ellipse(Vector2(15.0 * sx, cheek_y), 6.0, 4.0, CHEEK_COLOR)
	
	# ── 嘴巴 ──
	var mouth_y = 8.0 * sy
	if current_state_name == "drag":
		# 被拖拽时张嘴 >o<
		draw_circle(Vector2(0, mouth_y), 4.0 * min(sx, sy), Color(0.8, 0.3, 0.3, 0.8))
	else:
		# 微笑弧线
		var points := PackedVector2Array()
		for i in range(9):
			var t = float(i) / 8.0
			var angle = lerp(-0.4, 0.4, t) + PI * 0.5
			points.append(Vector2(cos(angle) * 8.0 * sx, sin(angle) * 4.0 * sy + mouth_y))
		for i in range(points.size() - 1):
			draw_line(points[i], points[i + 1], BODY_OUTLINE, 1.5, true)

## 辅助: 画椭圆
func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color, segments: int = 32) -> void:
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var angle = TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_colored_polygon(points, color)

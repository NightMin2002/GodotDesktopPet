# walk.gd — 行走状态
# 宠物沿地面水平移动，到达目标或超时后回到 Idle
class_name StateWalk
extends PetState

var walk_timer: float = 0.0
var walk_duration: float = 0.0
var walk_direction: float = 0.0  # -1.0 左, 1.0 右
var walk_force: float = 300.0

func enter() -> void:
	walk_duration = randf_range(1.5, 4.0)
	walk_timer = 0.0
	walk_direction = [-1.0, 1.0].pick_random()
	if pet:
		# 行走时保持较高的线性阻尼，让位移主要来自扭矩+摩擦力转化
		# 而不是纯平移惯性 (这是"看起来像滚动"而非"滑行"的关键)
		pet.linear_damp = 1.5
		pet.angular_damp = 0.2  # 保持低角阻尼让旋转持久

func exit() -> void:
	if pet:
		pet.linear_damp = 0.5

func process(delta: float) -> void:
	walk_timer += delta
	if walk_timer >= walk_duration:
		pet.transition_to("idle")

func physics_process(_delta: float) -> void:
	if not pet:
		return
	
	# 检查是否掉落了
	if not pet.is_settled():
		pet.transition_to("fall")
		return
	
	# ── 真正的滚动物理 ──
	# 主要驱动力: 大扭矩 → 通过摩擦力转化为地面位移 (真实滚动)
	# 辅助推力极低: 仅作为微弱补偿，不会产生可察觉的"滑行感"
	pet.apply_torque(walk_direction * 80000.0)
	pet.apply_central_force(Vector2(walk_direction * walk_force * 0.1, 0))
	
	# 碰到屏幕边缘就转向
	var screen_width = pet.boundary_size.x
	if pet.global_position.x < 50:
		walk_direction = 1.0
	elif pet.global_position.x > screen_width - 50:
		walk_direction = -1.0

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.transition_to("drag")

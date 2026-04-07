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
		pet.linear_damp = 0.5
		pet.facing_direction = walk_direction

func exit() -> void:
	pass

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
	
	# 施加水平行走力
	pet.apply_central_force(Vector2(walk_direction * walk_force, 0))
	
	# 碰到屏幕边缘就转向
	var screen_width = pet.boundary_size.x
	if pet.global_position.x < 50:
		walk_direction = 1.0
		pet.facing_direction = 1.0
	elif pet.global_position.x > screen_width - 50:
		walk_direction = -1.0
		pet.facing_direction = -1.0

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.transition_to("drag")

# walk.gd — 蹦跳 / 滚动漫步 移动状态
# 两种模式：单次蹦跳 (80%) 和滚动漫步 (20%)
# 蹦跳：一次性冲量 → 落地回 Idle
# 漫步：持续扭矩滚动到屏幕对面 → 到达边缘回 Idle
class_name StateWalk
extends PetState

var _has_landed: bool = false
var _land_pause: float = 0.0
var _is_stroll: bool = false       # 是否为滚动漫步模式
var _stroll_direction: float = 0.0 # 漫步滚动方向

func enter() -> void:
	if not pet: return
	_has_landed = false
	_land_pause = 0.0
	
	# 20% 概率进入滚动漫步 (从当前位置滚到对面边缘)
	if not _is_stroll and randf() < 0.2:
		_is_stroll = true
		_stroll_direction = [-1.0, 1.0].pick_random()
		# 边缘检测
		var x = pet.global_position.x
		var w = pet.boundary_size.x
		if x < 120.0: _stroll_direction = 1.0
		elif x > w - 120.0: _stroll_direction = -1.0
		pet.linear_damp = 0.8   # 适度阻尼控制速度
		pet.angular_damp = 0.3  # 低角阻尼让滚动持续
	else:
		# 普通蹦跳
		_is_stroll = false
		pet.linear_damp = 0.3
		pet.angular_damp = 0.5
		_do_hop()

func exit() -> void:
	_is_stroll = false

## 执行一次蹦跳
func _do_hop() -> void:
	_has_landed = false
	_land_pause = 0.0
	
	var hop_dir = [-1.0, 1.0].pick_random()
	# 边缘检测
	var x = pet.global_position.x
	var w = pet.boundary_size.x
	if x < 100.0: hop_dir = 1.0
	elif x > w - 100.0: hop_dir = -1.0
	
	# 适中高度的蹦跳
	var height = randf_range(300.0, 500.0)
	var horizontal = randf_range(130.0, 260.0) * hop_dir
	pet.apply_central_impulse(Vector2(horizontal, -height))
	pet.apply_torque_impulse(hop_dir * randf_range(1000.0, 3000.0))

func process(delta: float) -> void:
	if _is_stroll: return
	if not _has_landed: return
	_land_pause += delta
	if _land_pause >= 0.1:
		pet.transition_to("idle")

func physics_process(_delta: float) -> void:
	if not pet: return
	
	if _is_stroll:
		# 检查是否还在地面
		if not pet.is_settled() and pet.linear_velocity.y < -50.0:
			_is_stroll = false
			pet.transition_to("fall")
			return
		
		# 持续扭矩驱动滚动
		pet.apply_torque(_stroll_direction * 50000.0)
		pet.apply_central_force(Vector2(_stroll_direction * 30.0, 0))
		
		# 到达对面边缘 → 漫步结束
		var x = pet.global_position.x
		var w = pet.boundary_size.x
		if (_stroll_direction > 0.0 and x > w - 80.0) or (_stroll_direction < 0.0 and x < 80.0):
			_is_stroll = false
			pet.transition_to("idle")
	else:
		# 蹦跳落地检测
		if not _has_landed and pet.is_settled():
			_has_landed = true

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				_is_stroll = false
				pet.transition_to("drag")

# walk.gd — 蹦跳 / 悠闲散步 移动状态
# 两种模式：单次蹦跳 (92%) 和悠闲散步 (8%)
# 蹦跳：一次性冲量 → 落地回 Idle
# 散步：缓速扭矩滚动到屏幕对面 → 到达边缘回 Idle
class_name StateWalk
extends PetState

var _has_landed: bool = false
var _land_pause: float = 0.0
var _is_stroll: bool = false       # 是否为悠闲散步模式
var _stroll_direction: float = 0.0 # 散步滚动方向
var _stroll_last_x: float = 0.0   # 卡死检测：上次位置
var _stroll_stuck_timer: float = 0.0  # 卡死计时

func enter() -> void:
	if not pet: return
	_has_landed = false
	_land_pause = 0.0
	
	# 8% 概率进入悠闲散步 (受设置开关控制)
	if not _is_stroll and pet.stroll_enabled and randf() < 0.08:
		_is_stroll = true
		pet.is_strolling = true
		_stroll_direction = [-1.0, 1.0].pick_random()
		_stroll_stuck_timer = 0.0
		_stroll_last_x = pet.global_position.x
		# 边缘检测
		var x = pet.global_position.x
		var w = pet.boundary_size.x
		if x < 120.0: _stroll_direction = 1.0
		elif x > w - 120.0: _stroll_direction = -1.0
		pet.linear_damp = 1.5     # 较高阻尼：滚动更稳重，不会越滚越快
		pet.angular_damp = 0.5
	else:
		# 普通蹦跳
		_is_stroll = false
		pet.is_strolling = false
		pet.linear_damp = 0.3
		pet.angular_damp = 0.5
		_do_hop()

func exit() -> void:
	_is_stroll = false
	if pet:
		pet.is_strolling = false

## 执行一次蹦跳
func _do_hop() -> void:
	_has_landed = false
	_land_pause = 0.0
	
	var hop_dir = [-1.0, 1.0].pick_random()
	var x = pet.global_position.x
	var w = pet.boundary_size.x
	if x < 100.0: hop_dir = 1.0
	elif x > w - 100.0: hop_dir = -1.0
	
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

func physics_process(delta: float) -> void:
	if not pet: return
	
	if _is_stroll:
		# 卡死检测：0.8 秒内没移动超过 5px → 放弃散步
		if absf(pet.global_position.x - _stroll_last_x) < 5.0:
			_stroll_stuck_timer += delta
			if _stroll_stuck_timer > 0.8:
				_end_stroll()
				return
		else:
			_stroll_stuck_timer = 0.0
			_stroll_last_x = pet.global_position.x
		
		# 通知前方同伴跳开让路
		_nudge_pets_ahead()
		
		# 缓速扭矩驱动悠闲滚动
		pet.apply_torque(_stroll_direction * 25000.0)
		pet.apply_central_force(Vector2(_stroll_direction * 15.0, 0))
		
		# 到达对面边缘 → 散步结束
		var x = pet.global_position.x
		var w = pet.boundary_size.x
		if (_stroll_direction > 0.0 and x > w - 80.0) or (_stroll_direction < 0.0 and x < 80.0):
			_end_stroll()
	else:
		if not _has_landed and pet.is_settled():
			_has_landed = true

## 散步者通知前方的宠物跳开让路
var _nudged_pets: Dictionary = {}
func _nudge_pets_ahead() -> void:
	var parent = pet.get_parent()
	if not parent: return
	
	for child in parent.get_children():
		if child == pet or not (child is RigidBody2D): continue
		if not is_instance_valid(child): continue
		if not child.has_method("is_mouse_on_pet"): continue
		# 对方也在散步 → 不推，让卡死检测处理
		if "is_strolling" in child and child.is_strolling: continue
		
		# 只看前方 120px
		var dx = child.global_position.x - pet.global_position.x
		if _stroll_direction > 0 and dx < 0: continue
		if _stroll_direction < 0 and dx > 0: continue
		
		var dist = absf(dx)
		if dist > 140.0: continue
		
		# 已经通知过且还在空中 → 不重复
		var cid = child.get_instance_id()
		if _nudged_pets.has(cid) and absf(child.linear_velocity.y) > 30.0:
			continue
		
		# 1% 概率：轻推彩蛋 (温和版)
		if randf() < 0.01:
			var launch_dir = _stroll_direction
			child.apply_central_impulse(Vector2(launch_dir * 600.0, -200.0))
			child.apply_torque_impulse(launch_dir * 15000.0)
			if child.has_method("trigger_shockwave"):
				child.trigger_shockwave()
		else:
			# 轻轻跳开让路 (原地小跳，不飞走)
			child.apply_central_impulse(Vector2(0, -280.0))
			child.apply_torque_impulse(randf_range(-800.0, 800.0))
		_nudged_pets[cid] = true

func _end_stroll() -> void:
	_is_stroll = false
	_nudged_pets.clear()
	pet.is_strolling = false
	pet.transition_to("idle")

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				_is_stroll = false
				pet.is_strolling = false
				pet.transition_to("drag")

# walk.gd — 蹦跳 / 滚动 移动状态
# 步态风格: 蹦跳为主(纯冲量跳跃) / 滚动为主(短距扭矩滚动) / 混合平衡(50/50)
class_name StateWalk
extends PetState

var _has_landed: bool = false
var _land_pause: float = 0.0
var _is_stroll: bool = false       # 是否为滚动模式 (短距或长距)
var _is_long_stroll: bool = false  # true=长距散步(到边缘), false=短距滚动
var _stroll_direction: float = 0.0 # 滚动方向
var _stroll_last_x: float = 0.0   # 卡死检测：上次位置
var _stroll_stuck_timer: float = 0.0  # 卡死计时
var _roll_target_x: float = 0.0   # 短距滚动目标 X

func enter() -> void:
	if not pet: return
	_has_landed = false
	_land_pause = 0.0
	
	# 决定本次移动方式
	var do_roll := false
	var long := false
	match pet.move_style:
		0:  # 蹦跳为主: 纯蹦跳, 不滚动
			pass
		1:  # 滚动为主: 100% 短距滚动
			do_roll = true
			long = false
		2:  # 混合平衡: 50% 短距滚动
			if randf() < 0.50:
				do_roll = true
				long = false
	
	if not _is_stroll and do_roll:
		_is_stroll = true
		_is_long_stroll = long
		pet.is_strolling = true
		_stroll_direction = [-1.0, 1.0].pick_random()
		_stroll_stuck_timer = 0.0
		_stroll_last_x = pet.global_position.x
		# 边缘检测: 靠边时强制反向
		var x = pet.global_position.x
		var w = pet.boundary_size.x
		if x < 120.0: _stroll_direction = 1.0
		elif x > w - 120.0: _stroll_direction = -1.0
		# 短距滚动: 设定随机目标距离
		if not long:
			var roll_dist = randf_range(120.0, 300.0)
			_roll_target_x = x + _stroll_direction * roll_dist
			_roll_target_x = clampf(_roll_target_x, 80.0, w - 80.0)
		pet.linear_damp = 2.0 if not long else 1.5
		pet.angular_damp = 0.8 if not long else 0.5
	else:
		# 普通蹦跳
		_is_stroll = false
		_is_long_stroll = false
		pet.is_strolling = false
		pet.linear_damp = 0.3
		pet.angular_damp = 0.5
		_do_hop()

func exit() -> void:
	_is_stroll = false
	_is_long_stroll = false
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
	pet.apply_central_impulse(Vector2(horizontal, -height * pet.gravity_sign))
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
		# 卡死检测：0.8 秒内没移动超过 5px → 放弃
		if absf(pet.global_position.x - _stroll_last_x) < 5.0:
			_stroll_stuck_timer += delta
			if _stroll_stuck_timer > 0.8:
				_end_stroll()
				return
		else:
			_stroll_stuck_timer = 0.0
			_stroll_last_x = pet.global_position.x
		
		# 通知前方同伴跳开让路 (仅长距散步)
		if _is_long_stroll:
			_nudge_pets_ahead()
		
		# 缓速扭矩驱动滚动 (短距滚动更慢更从容)
		var torque_strength := 15000.0 if not _is_long_stroll else 25000.0
		var force_strength := 8.0 if not _is_long_stroll else 15.0
		pet.apply_torque(_stroll_direction * torque_strength * pet.gravity_sign)
		pet.apply_central_force(Vector2(_stroll_direction * force_strength, 0))
		
		# 到达目标 → 滚动结束
		var x = pet.global_position.x
		if _is_long_stroll:
			# 长距散步: 到达对面边缘
			var w = pet.boundary_size.x
			if (_stroll_direction > 0.0 and x > w - 80.0) or (_stroll_direction < 0.0 and x < 80.0):
				_end_stroll()
		else:
			# 短距滚动: 到达目标 X (20px 容差)
			if absf(x - _roll_target_x) < 20.0:
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
			child.apply_central_impulse(Vector2(launch_dir * 600.0, -200.0 * pet.gravity_sign))
			child.apply_torque_impulse(launch_dir * 15000.0)
			if child.has_method("trigger_shockwave"):
				child.trigger_shockwave()
		else:
			# 轻轻跳开让路 (原地小跳，不飞走)
			child.apply_central_impulse(Vector2(0, -280.0 * pet.gravity_sign))
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

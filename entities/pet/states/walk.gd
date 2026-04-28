# walk.gd — 蹦跳 / 滚动 移动状态
# 步态风格: 蹦跳为主(纯冲量跳跃) / 滚动为主(短距扭矩滚动) / 混合平衡(50/50)
# 自主巡航: 独立特殊事件, 8%概率长距滚动到对面边缘, 推开沿途同伴
class_name StateWalk
extends PetState

var _has_landed: bool = false
var _land_pause: float = 0.0
var _is_rolling: bool = false       # 是否处于滚动模式 (短距或巡航)
var _is_cruise: bool = false        # true=自主巡航(到边缘), false=短距滚动
var _roll_direction: float = 0.0    # 滚动方向
var _roll_last_x: float = 0.0      # 卡死检测：上次位置
var _roll_stuck_timer: float = 0.0  # 卡死计时
var _roll_target_x: float = 0.0    # 短距滚动目标 X

func enter() -> void:
	if not pet: return
	_has_landed = false
	_land_pause = 0.0
	
	# 1) 优先检查自主巡航事件 (独立于步态，8% 概率长距滚到对面)
	var do_roll := false
	var cruise := false
	if pet.stroll_enabled and randf() < 0.08:
		do_roll = true
		cruise = true
	else:
		# 2) 未触发巡航 → 按步态风格决定常规移动
		match pet.move_style:
			0:  # 蹦跳为主: 纯蹦跳, 不滚动
				pass
			1:  # 滚动为主: 100% 短距滚动
				do_roll = true
			2:  # 混合平衡: 50% 短距滚动
				if randf() < 0.50:
					do_roll = true
	
	if not _is_rolling and do_roll:
		_is_rolling = true
		_is_cruise = cruise
		pet.is_strolling = true
		_roll_direction = [-1.0, 1.0].pick_random()
		_roll_stuck_timer = 0.0
		_roll_last_x = pet.global_position.x
		# 边缘检测: 靠边时强制反向
		var x = pet.global_position.x
		var w = pet.boundary_size.x
		if x < 120.0: _roll_direction = 1.0
		elif x > w - 120.0: _roll_direction = -1.0
		# 短距滚动: 设定随机目标距离
		if not cruise:
			var roll_dist = randf_range(120.0, 300.0)
			_roll_target_x = x + _roll_direction * roll_dist
			_roll_target_x = clampf(_roll_target_x, 80.0, w - 80.0)
		pet.linear_damp = 2.0 if not cruise else 1.5
		pet.angular_damp = 0.8 if not cruise else 0.5
	else:
		# 普通蹦跳
		_is_rolling = false
		_is_cruise = false
		pet.is_strolling = false
		pet.linear_damp = 0.3
		pet.angular_damp = 0.5
		_do_hop()

func exit() -> void:
	_is_rolling = false
	_is_cruise = false
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
	if _is_rolling: return
	if not _has_landed: return
	_land_pause += delta
	if _land_pause >= 0.1:
		pet.transition_to("idle")

func physics_process(delta: float) -> void:
	if not pet: return
	
	if _is_rolling:
		# 卡死检测：0.8 秒内没移动超过 5px → 放弃
		if absf(pet.global_position.x - _roll_last_x) < 5.0:
			_roll_stuck_timer += delta
			if _roll_stuck_timer > 0.8:
				_end_roll()
				return
		else:
			_roll_stuck_timer = 0.0
			_roll_last_x = pet.global_position.x
		
		# 前方同伴处理
		var pets_ahead := _find_pets_ahead(140.0 if _is_cruise else 80.0)
		if _is_cruise:
			# 自主巡航: 推开前方同伴让路
			_nudge_pets(pets_ahead)
		elif not pets_ahead.is_empty():
			# 短距滚动: 发现前方同伴就提前结束，避免碰撞
			_end_roll()
			return
		
		# 缓速扭矩驱动滚动 (短距滚动更慢更从容)
		var torque_strength := 15000.0 if not _is_cruise else 25000.0
		var force_strength := 8.0 if not _is_cruise else 15.0
		pet.apply_torque(_roll_direction * torque_strength * pet.gravity_sign)
		pet.apply_central_force(Vector2(_roll_direction * force_strength, 0))
		
		# 到达目标 → 滚动结束
		var x = pet.global_position.x
		if _is_cruise:
			# 自主巡航: 到达对面边缘
			var w = pet.boundary_size.x
			if (_roll_direction > 0.0 and x > w - 80.0) or (_roll_direction < 0.0 and x < 80.0):
				_end_roll()
		else:
			# 短距滚动: 到达目标 X (20px 容差)
			if absf(x - _roll_target_x) < 20.0:
				_end_roll()
	else:
		if not _has_landed and pet.is_settled():
			_has_landed = true

# ── 前方同伴检测 (巡航推人和短距避让共用) ──

## 查找前方指定距离内的所有同伴
func _find_pets_ahead(dist: float) -> Array[RigidBody2D]:
	var result: Array[RigidBody2D] = []
	var parent = pet.get_parent()
	if not parent: return result
	for child in parent.get_children():
		if child == pet or not (child is RigidBody2D): continue
		if not is_instance_valid(child): continue
		if not child.has_method("is_mouse_on_pet"): continue
		var dx = child.global_position.x - pet.global_position.x
		if _roll_direction > 0 and dx < 0: continue
		if _roll_direction < 0 and dx > 0: continue
		if absf(dx) < dist:
			result.append(child)
	return result

## 自主巡航: 推开前方同伴让路
var _nudged_pets: Dictionary = {}
func _nudge_pets(pets: Array[RigidBody2D]) -> void:
	for child in pets:
		# 对方也在巡航 → 不推，让卡死检测处理
		if "is_strolling" in child and child.is_strolling: continue
		
		# 已经通知过且还在空中 → 不重复
		var cid = child.get_instance_id()
		if _nudged_pets.has(cid) and absf(child.linear_velocity.y) > 30.0:
			continue
		
		# 1% 概率：轻推彩蛋 (温和版)
		if randf() < 0.01:
			var launch_dir = _roll_direction
			child.apply_central_impulse(Vector2(launch_dir * 600.0, -200.0 * pet.gravity_sign))
			child.apply_torque_impulse(launch_dir * 15000.0)
			if child.has_method("trigger_shockwave"):
				child.trigger_shockwave()
		else:
			# 轻轻跳开让路 (原地小跳，不飞走)
			child.apply_central_impulse(Vector2(0, -280.0 * pet.gravity_sign))
			child.apply_torque_impulse(randf_range(-800.0, 800.0))
		_nudged_pets[cid] = true

func _end_roll() -> void:
	_is_rolling = false
	_nudged_pets.clear()
	pet.is_strolling = false
	pet.transition_to("idle")

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				_is_rolling = false
				pet.is_strolling = false
				pet.transition_to("drag")

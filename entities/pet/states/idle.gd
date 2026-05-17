# idle.gd — 待机状态
# 宠物立在原地，随机时间后转入 Walk 或 Jump
# 如果附近有漫步中的同伴滚来，跳起让路 (跳绳效果)
class_name StateIdle
extends PetState

var idle_timer: float = 0.0
var idle_duration: float = 0.0
var _dodge_cooldown: float = 0.0  # 让路跳跃冷却

func enter() -> void:
	idle_duration = randf_range(1.0, 4.0)
	idle_timer = 0.0
	_dodge_cooldown = 0.0
	if pet:
		pet.linear_damp = 0.8
		pet.angular_damp = 1.0
		# forced_look_dir 由 PetMovement HOLD 阶段管理，此处无需处理
		if pet.is_quiet_behavior():
			pet.linear_damp = 5.0
			pet.angular_damp = 8.0

func exit() -> void:
	if pet:
		pet.linear_damp = 0.5
		# 离开 idle 时取消活跃微行为 (被拖拽/状态切换等打断)
		# 但深夜休眠例外: 它是持续性的，只有退出深夜时段才中断
		if not (pet.nighttime_mode and pet.idle_behaviors.active_behavior == "hibernate"):
			pet.idle_behaviors.cancel()

func process(delta: float) -> void:
	# freeze 状态 (叠高高等): 跳过所有逻辑, 位置由外部控制
	if pet.freeze: return
	idle_timer += delta
	
	# ── 游戏态 / 全息屏活跃: 锁定 idle，不做任何转换/触发 ──
	if pet.gaming.active or pet.holo_screen.is_terminal_mode:
		return
	
	# ── 空间跳跃活跃时锁定 idle 状态，不做任何转换 ──
	if pet._roam_active:
		return
	
	# ── 安静模式位置锁定：持续微校正物理漂移 ──
	if pet.is_quiet_behavior() and pet.has_meta("retreat_target_x"):
		var target_x: float = pet.get_meta("retreat_target_x")
		var drift := pet.global_position.x - target_x
		if absf(drift) > 2.0:
			# 轻柔吸附回槽位 (速率8让对齐干脆又不失柔滑，约0.3秒归位)
			pet.global_position.x = lerpf(pet.global_position.x, target_x, 8.0 * delta)
			pet.linear_velocity.x *= 0.8  # 同步衰减水平速度
	
	if idle_timer >= idle_duration:
		if pet.is_quiet_behavior():
			if not _is_at_slot():
				pet.transition_to("retreat")
				return
			idle_timer = 0.0
			idle_duration = randf_range(1.0, 3.0)
			return
		# 微行为活跃时不转移状态 (等它自然结束)
		if pet.idle_behaviors.is_active():
			return
		# 尝试触发微行为 (休眠/自检)
		if pet.idle_behaviors.try_random(idle_timer):
			idle_timer = 0.0
			idle_duration = randf_range(2.0, 4.0)  # 微行为结束后重置计时
			return
		# 正在注视同伴时不跳动，安静地看着
		if pet.eye_behavior._look_at_pet != null:
			idle_timer = 0.0
			idle_duration = randf_range(1.5, 3.0)
			return
		# 根据步态风格调整 walk/jump 概率
		var jump_chance: float
		match pet.move_style:
			0: jump_chance = 0.15   # 蹦跳为主: 15% 大跳
			1: jump_chance = 0.0    # 滚动为主: 不跳
			2: jump_chance = 0.10   # 混合平衡: 10% 大跳
			_: jump_chance = 0.15
		if randf() > jump_chance:
			pet.transition_to("walk")
		else:
			pet.transition_to("jump")

func physics_process(delta: float) -> void:
	if not pet: return
	if pet.freeze: return
	
	# 空间跳跃活跃时由 roam 系统完全接管，跳过所有辅助行为
	if pet._roam_active:
		return
	
	# 检查是否还在空中 (休眠活跃时跳过: rotation lerp 可能产生微小扰动)
	if not pet.idle_behaviors.is_active() and not pet.is_settled():
		pet.transition_to("fall")
		return
	
	# ── 跳绳让路：近距离检测到滚动中的同伴 → 跳起让路 ──
	# 纯滚动模式不跳跃 (对方的 _has_pet_ahead 会让它主动停下)
	if not pet.is_quiet_behavior() and pet.move_style != 1:
		_dodge_cooldown -= delta
		if _dodge_cooldown <= 0.0:
			var stroller = _find_approaching_stroller()
			if stroller != null:
				pet.apply_central_impulse(Vector2(0, -350.0 * pet.gravity_sign))
				pet.apply_torque_impulse(randf_range(-800.0, 800.0))
				_dodge_cooldown = 0.5

## 检测是否有漫步中的宠物正在靠近 (120px 范围)
func _find_approaching_stroller() -> RigidBody2D:
	var parent = pet.get_parent()
	if not parent: return null
	
	for child in parent.get_children():
		if child == pet or not (child is RigidBody2D): continue
		if not is_instance_valid(child): continue
		if not ("is_strolling" in child): continue
		if not child.is_strolling: continue
		
		var dist = absf(child.global_position.x - pet.global_position.x)
		if dist > 140.0: continue
		
		# 确认对方正朝自己滚来
		var vx = child.linear_velocity.x
		var dx = pet.global_position.x - child.global_position.x
		if (vx > 10.0 and dx > 0.0) or (vx < -10.0 and dx < 0.0):
			return child
	return null

func input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if pet.is_mouse_on_pet():
				pet.get_viewport().set_input_as_handled()
				# 游戏中: 不进入拖拽，给个专属回应
				if pet.gaming.active:
					# 面板隐藏时: 点击宠物 → 展开面板 (不中断自玩)
					if pet.gaming.game and pet.gaming.game._panel_hidden:
						pet.gaming.game.set_panel_visible(true)
						return
					var lines := [
						"推演中。请勿干扰处理器。",
						"...对弈优先级高于触控响应。",
						"正在计算。稍后处理。",
						"触控信号已搁置。",
					]
					pet.show_local_bubble(lines[randi() % lines.size()])
					return
				# 看终端/加载中: 不进入拖拽，给个专属回应
				if pet.holo_screen.is_terminal_mode:
					var lines := [
						"...正在读取数据流。",
						"终端会话进行中。",
						"...稍后。",
					]
					pet.show_local_bubble(lines[randi() % lines.size()])
					return
				pet.transition_to("drag")

## 精确判定是否已停靠在分配的队列槽位上 (X + Y 双轴验证)
func _is_at_slot() -> bool:
	if not pet: return false
	if pet.has_meta("retreat_target_x"):
		var target_x: float = pet.get_meta("retreat_target_x")
		var x_ok := absf(pet.global_position.x - target_x) < 25.0
		# Y 轴验证: 确保宠物确实在目标表面 (地面/天花板) 附近
		if pet.has_meta("retreat_target_y"):
			var target_y: float = pet.get_meta("retreat_target_y")
			return x_ok and absf(pet.global_position.y - target_y) < 50.0
		return x_ok
	# 没有分配过槽位时回退到边缘检测
	var x = pet.global_position.x
	var w = pet.boundary_size.x
	return x < 100.0 or x > w - 100.0

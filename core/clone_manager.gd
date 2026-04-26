# clone_manager.gd — 克隆与行为管理器 (从 main.gd 拆分)
# 职责: 克隆体生命周期、安静排队、行为指令、告别退出
extends Node

var _main: Node2D

# ── 克隆常量 ──
const MAX_CLONES: int = 5
var CLONE_HUE_SHIFTS: Array[float] = [0.75, 0.45, 0.12, 0.35, 0.85]

# ── 告别退出锁 ──
var _is_quitting := false

func setup(main: Node2D) -> void:
	_main = main
	
	EventBus.clone_pet.connect(_on_clone_pet_requested)
	EventBus.dismiss_clones.connect(_on_dismiss_clones_requested)
	EventBus.behavior_mode_changed.connect(_on_behavior_mode_changed)

## 启动时从持久化恢复克隆体
func restore_clones() -> void:
	var saved_clones = SettingsManager.get_int("clone_count", 0)
	for i in range(mini(saved_clones, MAX_CLONES)):
		_clone_pet(null, false)

# ── 克隆系统 ──

func _on_clone_pet_requested(_source: Node2D) -> void:
	_clone_pet(_source, true)

func _clone_pet(source: Node2D, with_bubble: bool) -> void:
	var clone_count = _main.pet_instances.size() - 1
	if clone_count >= MAX_CLONES:
		if with_bubble:
			EventBus.show_reminder_bubble.emit("分身已达上限 (" + str(MAX_CLONES) + "/" + str(MAX_CLONES) + ")！")
		return
	
	var clone = _main.clone_scene.instantiate()
	clone.screen_rect = _main.screen_rect
	clone.boundary_size = _main.boundary_size
	clone.window_mode = _main.window_mode
	clone.clone_hue_shift = CLONE_HUE_SHIFTS[clone_count % CLONE_HUE_SHIFTS.size()]
	
	var spawn_x: float
	if is_instance_valid(source):
		spawn_x = source.global_position.x + randf_range(-80, 80)
	else:
		spawn_x = randf_range(_main.boundary_size.x * 0.2, _main.boundary_size.x * 0.8)
	spawn_x = clampf(spawn_x, 60.0, _main.boundary_size.x - 60.0)
	clone.position = Vector2(spawn_x, _main.boundary_size.y * 0.1)
	
	clone.behavior_mode = _main.behavior_mode
	
	_main.add_child(clone)
	_main.pet_instances.append(clone)
	
	SettingsManager.set_int("clone_count", _main.pet_instances.size() - 1)
	
	if with_bubble:
		var greetings = ["分身术！召唤成功", "又多了一个伙伴！", "一起热闹热闹~", "家族壮大啦！", "我给你叫了个帮手！"]
		EventBus.show_reminder_bubble.emit(greetings[clone_count % greetings.size()])
	
	print("[DesktopPet] 克隆体 #", clone_count + 1, " 已生成 (hue_shift=", clone.clone_hue_shift, ")")
	reorganize_quiet_queue()

func _on_dismiss_clones_requested() -> void:
	var clones_to_remove: Array[RigidBody2D] = []
	for p in _main.pet_instances:
		if p.is_clone:
			clones_to_remove.append(p)
	
	if clones_to_remove.is_empty():
		EventBus.show_reminder_bubble.emit("没有分身可以遣散哦~")
		return
	
	var farewells := ["拜拜~", "先撤啦!", "下次见!", "我先走一步~", "886!", "要想我哦~", "本体加油!"]
	
	# 依次告别滚出 (和退出告别同风格)
	for i in range(clones_to_remove.size()):
		var clone = clones_to_remove[i]
		if not is_instance_valid(clone):
			continue
		
		# 从 pet_instances 中移除 (不再参与命中检测)
		_main.pet_instances.erase(clone)
		
		# 告别语气泡
		clone.show_local_bubble(farewells[i % farewells.size()])
		await get_tree().create_timer(0.5).timeout
		
		# 冻结物理，清除碰撞
		clone.freeze = true
		clone.collision_layer = 0
		clone.collision_mask = 0
		
		# 滚向最近的屏幕边缘
		var slide_dir = -1.0 if clone.global_position.x < _main.boundary_size.x / 2.0 else 1.0
		var dist_to_edge = clone.global_position.x if slide_dir < 0 else _main.boundary_size.x - clone.global_position.x
		var total_dist = dist_to_edge + 150.0
		var exit_pos = clone.global_position + Vector2(slide_dir * total_dist, 0)
		var roll_angle = clone.rotation + slide_dir * total_dist / 30.0
		var slide_time = clampf(total_dist / 400.0, 0.6, 1.5)
		
		var tw = _main.create_tween().set_parallel(true)
		tw.tween_property(clone, "global_position", exit_pos, slide_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(clone, "rotation", roll_angle, slide_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(clone, "modulate:a", 0.0, slide_time * 0.8).set_delay(slide_time * 0.2)
		
		var c = clone
		tw.finished.connect(func(): c.queue_free())
		
		# 多个克隆体间隔退场
		if i < clones_to_remove.size() - 1:
			await get_tree().create_timer(0.35).timeout
	
	SettingsManager.set_int("clone_count", 0)
	EventBus.show_reminder_bubble.emit("分身们，辛苦了！下次再见~")
	reorganize_quiet_queue()

# ── 行为指令 ──

func _on_behavior_mode_changed(mode: int) -> void:
	_main.behavior_mode = mode
	SettingsManager.set_int("behavior_mode", mode)
	if mode == 1:
		reorganize_quiet_queue()

## 动态重新评估所有克隆体在屏幕上的水平位置，重新分配车位
func reorganize_quiet_queue() -> void:
	if _main.behavior_mode != 1: return
	
	var left_q: Array[RigidBody2D] = []
	var right_q: Array[RigidBody2D] = []
	
	for p in _main.pet_instances:
		if is_instance_valid(p):
			if p.global_position.x < _main.boundary_size.x / 2.0:
				left_q.append(p)
			else:
				right_q.append(p)
				
	left_q.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	right_q.sort_custom(func(a, b): return a.global_position.x > b.global_position.x)
	
	var pet_diameter := 60.0
	var gap := 10.0
	var spacing := pet_diameter + gap
	var edge_margin := 35.0
	_apply_queue_targets(left_q, edge_margin, spacing, 1.0)
	_apply_queue_targets(right_q, _main.boundary_size.x - edge_margin, spacing, -1.0)

func _apply_queue_targets(q: Array[RigidBody2D], base_x: float, spacing: float, dir: float) -> void:
	for i in range(q.size()):
		var p = q[i]
		var old_tgt = p.get_meta("retreat_target_x", -9999.0)
		var new_tgt = base_x + i * spacing * dir
		p.set_meta("retreat_target_x", new_tgt)
		
		if absf(old_tgt - new_tgt) > 5.0 and p.current_state_name == "idle":
			if absf(p.global_position.x - new_tgt) > 20.0:
				p.transition_to("retreat")

# ── 告别退出 ──

func quit_with_farewell() -> void:
	if _is_quitting:
		return
	_is_quitting = true
	
	for p in _main.pet_instances:
		if is_instance_valid(p):
			p.set_process_unhandled_input(false)
	
	for p in _main.pet_instances:
		if is_instance_valid(p):
			p.linear_damp = 5.0
			p.angular_damp = 8.0
	
	var clones: Array[RigidBody2D] = []
	for p in _main.pet_instances:
		if is_instance_valid(p) and p.is_clone:
			clones.append(p)
	
	if _main.pet_instance:
		if not _main.pet_instance.is_settled() or _main.pet_instance.current_state_name in ["fall", "jump", "drag"]:
			if _main.pet_instance.current_state_name == "drag":
				_main.pet_instance.transition_to("fall")
			var wait_time := 0.0
			while wait_time < 6.0:
				await get_tree().create_timer(0.2).timeout
				wait_time += 0.2
				if _main.pet_instance.is_settled() and _main.pet_instance.current_state_name not in ["fall", "jump", "drag"]:
					break
		
		await get_tree().create_timer(0.5).timeout
		
		_main.pet_instance.collision_layer = 0
		
		# 克隆体依次滚出屏幕
		if not clones.is_empty():
			var clone_farewells := ["拜拜~", "先撤啦!", "下次见!", "我先走一步~", "886!", "本体加油!", "要想我哦~"]
			var last_tween: Tween = null
			
			for i in range(clones.size()):
				var clone = clones[i]
				if not is_instance_valid(clone):
					continue
				
				clone.z_index = 100
				clone.show_local_bubble(clone_farewells[i % clone_farewells.size()])
				await get_tree().create_timer(0.6).timeout
				
				clone.freeze = true
				clone.collision_layer = 0
				clone.collision_mask = 0
				
				var slide_dir = -1.0 if clone.global_position.x < _main.boundary_size.x / 2.0 else 1.0
				var dist_to_edge = clone.global_position.x if slide_dir < 0 else _main.boundary_size.x - clone.global_position.x
				var total_dist = dist_to_edge + 150.0
				var exit_pos = clone.global_position + Vector2(slide_dir * total_dist, 0)
				var roll_angle = clone.rotation + slide_dir * total_dist / 30.0
				var slide_time = clampf(total_dist / 400.0, 0.6, 1.5)
				
				var tw = _main.create_tween().set_parallel(true)
				tw.tween_property(clone, "global_position", exit_pos, slide_time) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_property(clone, "rotation", roll_angle, slide_time) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_property(clone, "modulate:a", 0.0, slide_time * 0.8).set_delay(slide_time * 0.2)
				
				var c = clone
				tw.finished.connect(func():
					_main.pet_instances.erase(c)
					c.queue_free()
				)
				last_tween = tw
				
				if i < clones.size() - 1:
					await get_tree().create_timer(0.35).timeout
			
			if last_tween != null and last_tween.is_running():
				await last_tween.finished
		
		# 本体告别 + 退场
		var farewell_lines := [
			"好的，我去充电啦，下次我会好好监视你哦~",
			"要乖乖的，不然我会知道的哦~ 晚安！",
			"虽然要走了...但我无时无刻不在想你哦",
			"好好吃饭好好休息！不然下次我会碎碎念一整天！",
			"我先闪了~ 记得想我！不想也行，反正我会自己回来",
			"据我观测，你已经盯屏幕太久了！快去休息！",
			"放心走吧，你的桌面我替你守着呢~",
		]
		var farewell_line = farewell_lines[randi() % farewell_lines.size()]
		EventBus.force_show_bubble.emit(farewell_line)
		await get_tree().create_timer(2.0).timeout
		
		_main.pet_instance.freeze = true
		
		var slide_dir = -1.0 if _main.pet_instance.global_position.x < _main.boundary_size.x / 2.0 else 1.0
		var dist_to_edge = _main.pet_instance.global_position.x if slide_dir < 0 else _main.boundary_size.x - _main.pet_instance.global_position.x
		var total_dist = dist_to_edge + 150.0
		var exit_pos = _main.pet_instance.global_position + Vector2(slide_dir * total_dist, 0)
		var roll_angle = _main.pet_instance.rotation + slide_dir * total_dist / 30.0
		var slide_time = clampf(total_dist / 400.0, 0.8, 2.0)
		
		var tween = _main.create_tween().set_parallel(true)
		tween.tween_property(_main.pet_instance, "global_position", exit_pos, slide_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(_main.pet_instance, "rotation", roll_angle, slide_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(_main.pet_instance, "modulate:a", 0.0, slide_time)
		_main.pet_instance.overlay_rect = Rect2()
		# 气泡同步淡出
		for child in _main.get_children():
			if child.has_method("is_busy"):
				for sub in child.get_children():
					if sub is PanelContainer and sub.visible:
						tween.tween_property(sub, "modulate:a", 0.0, slide_time * 0.7)
		tween.chain().tween_callback(func(): get_tree().quit())
		return
	
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

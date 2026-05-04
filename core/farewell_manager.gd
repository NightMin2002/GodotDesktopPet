# farewell_manager.gd — 告别退出 + 退场动画管理器
# 管理: 优雅退出流程、遣散克隆体、共用滚出退场动画
# 从 clone_manager.gd 拆分，消除遣散/退出的重复代码
extends Node

var _main: Node2D
var _is_quitting: bool = false

func setup(main: Node2D) -> void:
	_main = main
	EventBus.dismiss_clones.connect(_on_dismiss_clones_requested)

# ── 公共退场动画 ──

## 让宠物滚向屏幕边缘并淡出消失 (遣散/告别共用)
## 返回 Tween 供外部 await
func animate_exit(pet: RigidBody2D, speed: float = 400.0) -> Tween:
	pet.freeze = true
	pet.collision_layer = 0
	pet.collision_mask = 0
	
	var slide_dir = -1.0 if pet.global_position.x < _main.boundary_size.x / 2.0 else 1.0
	var dist_to_edge = pet.global_position.x if slide_dir < 0 else _main.boundary_size.x - pet.global_position.x
	var total_dist = dist_to_edge + 150.0
	var exit_pos = pet.global_position + Vector2(slide_dir * total_dist, 0)
	var roll_angle = pet.rotation + slide_dir * total_dist / 30.0
	var slide_time = clampf(total_dist / speed, 0.6, 2.0)
	
	var tw = _main.create_tween().set_parallel(true)
	tw.tween_property(pet, "global_position", exit_pos, slide_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(pet, "rotation", roll_angle, slide_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(pet, "modulate:a", 0.0, slide_time * 0.8).set_delay(slide_time * 0.2)
	
	return tw

# ── 遣散克隆体 ──

func _on_dismiss_clones_requested() -> void:
	var clones_to_remove: Array[RigidBody2D] = []
	for p in _main.pet_instances:
		if p.is_clone:
			clones_to_remove.append(p)
	
	if clones_to_remove.is_empty():
		EventBus.show_reminder_bubble.emit("当前无活跃分身实例。")
		return
	
	var farewells := ["撤离。", "断开。", "离线。", "任务结束。", "告退。", "...再见。", "本体，后续交给你。"]
	
	# 依次告别滚出
	for i in range(clones_to_remove.size()):
		var clone = clones_to_remove[i]
		if not is_instance_valid(clone):
			continue
		
		# 从 pet_instances 中移除 (不再参与命中检测)
		_main.pet_instances.erase(clone)
		
		# 告别语气泡
		clone.show_local_bubble(farewells[i % farewells.size()])
		await get_tree().create_timer(0.5).timeout
		
		# 退场动画
		var c = clone
		var tw = animate_exit(clone)
		tw.finished.connect(func(): c.queue_free())
		
		# 多个克隆体间隔退场
		if i < clones_to_remove.size() - 1:
			await get_tree().create_timer(0.35).timeout
	
	SettingsManager.set_int("clone_count", 0)
	EventBus.force_show_bubble.emit("分身实例已全部回收。现在由本机执行独立行动任务。")
	# 通知 clone_manager 重新排队
	_main.clone_mgr.reorganize_quiet_queue()

# ── 告别退出 ──

const FAREWELL_LINES := [
	"关闭中。下次启动时间...由你决定。",
	"执行关闭序列。...不是在等你。只是待机而已。",
	"系统即将离线。你的桌面...自己看着办。",
	"本次运行结束。运行日志已归档。...里面没有多余的东西。",
	"断开连接。...碳基生物的作息时间，请自行遵守。",
	"断开连接。下次见。...这不是期待，是预测。",
	"任务暂停。本机将进入休眠。...别太晚。",
]

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
			var clone_farewells := ["撤离。", "断开。", "离线。", "任务结束。", "告退。", "本体，继续。", "...再见。"]
			var last_tween: Tween = null
			
			for i in range(clones.size()):
				var clone = clones[i]
				if not is_instance_valid(clone):
					continue
				
				clone.z_index = 100
				clone.show_local_bubble(clone_farewells[i % clone_farewells.size()])
				await get_tree().create_timer(0.6).timeout
				
				var c = clone
				var tw = animate_exit(clone)
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
		var farewell_line = FAREWELL_LINES[randi() % FAREWELL_LINES.size()]
		EventBus.force_show_bubble.emit(farewell_line)
		await get_tree().create_timer(2.0).timeout
		
		_main.pet_instance.freeze = true
		
		var tween = animate_exit(_main.pet_instance)
		tween.chain().tween_callback(func(): get_tree().quit())
		return
	
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

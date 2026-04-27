# clone_manager.gd — 克隆与行为管理器 (从 main.gd 拆分)
# 职责: 克隆体生命周期、安静排队、行为指令
extends Node

var _main: Node2D

# ── 克隆常量 ──
const MAX_CLONES: int = 5
var CLONE_HUE_SHIFTS: Array[float] = [0.75, 0.45, 0.12, 0.35, 0.85]


func setup(main: Node2D) -> void:
	_main = main
	
	EventBus.clone_pet.connect(_on_clone_pet_requested)
	EventBus.behavior_mode_changed.connect(_on_behavior_mode_changed)
	EventBus.setting_toggled.connect(_on_setting_toggled)

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
		EventBus.force_show_bubble.emit(greetings[clone_count % greetings.size()])
	
	print("[DesktopPet] 克隆体 #", clone_count + 1, " 已生成 (hue_shift=", clone.clone_hue_shift, ")")
	reorganize_quiet_queue()




func _on_behavior_mode_changed(mode: int) -> void:
	_main.behavior_mode = mode
	SettingsManager.set_int("behavior_mode", mode)
	if mode == 1:
		reorganize_quiet_queue()

func _on_setting_toggled(setting_id: String, _is_on: bool) -> void:
	# 反重力切换时，安静排队的 Y 轴目标需要重新计算
	if setting_id == "anti_gravity":
		reorganize_quiet_queue()

## 动态重新评估所有克隆体在屏幕上的水平位置，重新分配车位
func reorganize_quiet_queue() -> void:
	if _main.behavior_mode != 1: return
	
	# 反重力: 目标 Y 在天花板附近；正常: 目标 Y 在地面附近
	var ag = SettingsManager.get_bool("anti_gravity", false)
	var target_y: float = 35.0 if ag else _main.boundary_size.y - 35.0
	
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
	_apply_queue_targets(left_q, edge_margin, spacing, 1.0, target_y)
	_apply_queue_targets(right_q, _main.boundary_size.x - edge_margin, spacing, -1.0, target_y)

func _apply_queue_targets(q: Array[RigidBody2D], base_x: float, spacing: float, dir: float, target_y: float) -> void:
	for i in range(q.size()):
		var p = q[i]
		var old_tgt = p.get_meta("retreat_target_x", -9999.0)
		var new_tgt = base_x + i * spacing * dir
		p.set_meta("retreat_target_x", new_tgt)
		p.set_meta("retreat_target_y", target_y)
		
		if absf(old_tgt - new_tgt) > 5.0 and p.current_state_name == "idle":
			if absf(p.global_position.x - new_tgt) > 20.0:
				p.transition_to("retreat")



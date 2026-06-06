# clone_manager.gd — 克隆与行为管理器 (从 main.gd 拆分)
# 职责: 克隆体生命周期、安静排队、行为指令
extends Node

var _main: Node2D
const _PetColorPalette = preload("res://entities/pet/pet_color_palette.gd")

# ── 克隆常量 ──
const MAX_CLONES: int = 5


func setup(main: Node2D) -> void:
	_main = main
	
	EventBus.clone_pet.connect(_on_clone_pet_requested)
	EventBus.behavior_mode_changed.connect(_on_behavior_mode_changed)
	EventBus.setting_toggled.connect(_on_setting_toggled)
	EventBus.nighttime_mode_changed.connect(_on_nighttime_mode_changed)

## 启动时从持久化恢复克隆体
func restore_clones() -> void:
	var saved_clones = SettingsManager.get_int("clone_count", 0)
	for i in range(mini(saved_clones, MAX_CLONES)):
		_clone_pet(null, false)
		# 顺序入场: 等当前克隆体具象化完成后再生成下一个
		if i < mini(saved_clones, MAX_CLONES) - 1:
			await get_tree().create_timer(1.2).timeout

# ── 克隆系统 ──

func _on_clone_pet_requested(_source: Node2D) -> void:
	_clone_pet(_source, true)

func _clone_pet(source: Node2D, with_bubble: bool) -> void:
	var clone_count = _main.pet_instances.size() - 1
	if clone_count >= MAX_CLONES:
		if with_bubble:
			EventBus.show_reminder_bubble.emit("实例池已满 (" + str(MAX_CLONES) + "/" + str(MAX_CLONES) + ")。拒绝新建。")
		return
	
	var clone = _main.clone_scene.instantiate()
	clone.screen_rect = _main.screen_rect
	clone.boundary_size = _main.boundary_size
	clone.stand_ceiling_y = _main.stand_ceiling_y
	clone.stand_floor_y = _main.stand_floor_y
	clone.window_mode = _main.window_mode
	
	var pet_index = clone_count + 1
	clone.set_meta("pet_index", pet_index)
	
	# 尝试从持久化恢复颜色，否则随机分配
	var saved = SettingsManager.get_pet_color(pet_index)
	clone.palette = _PetColorPalette.new()
	if saved.hue >= 0:
		clone.palette.set_hue_degrees(saved.hue)
		clone.palette.set_sat_percent(saved.sat)
		clone.palette.set_val_percent(saved.val)
	else:
		var random_hue = _generate_distinct_hue()
		clone.palette.set_hue(random_hue)
		# 首次随机分配后立即保存
		SettingsManager.set_pet_color(pet_index, clone.palette.get_hue_degrees(), clone.palette.get_sat_percent(), clone.palette.get_val_percent())
	
	clone.behavior_mode = _main.behavior_mode
	
	var ag = SettingsManager.get_bool("anti_gravity", false)
	
	# ── 入场方式决策 ──
	# 70% 从侧方滚入/弹入 (和原体同风格)，30% 从空中掉落 (彩蛋)
	var side_entrance: bool = randf() < 0.7 and with_bubble  # 静默恢复时直接空降
	
	if side_entrance:
		# ── 侧方入场: 复用原体入场动画 ──
		clone.modulate = Color(1, 1, 1, 0)
		_main.add_child(clone)
		_main.pet_instances.append(clone)
		_main.perform_side_entrance(clone)
	else:
		# ── 次元传送: 悬空具象化 (彩蛋入场) ──
		var spawn_x: float
		if is_instance_valid(source):
			spawn_x = source.global_position.x + randf_range(-80, 80)
		else:
			spawn_x = randf_range(_main.boundary_size.x * 0.2, _main.boundary_size.x * 0.8)
		spawn_x = clampf(spawn_x, 60.0, _main.boundary_size.x - 60.0)
		var spawn_y: float
		if ag:
			spawn_y = _main.boundary_size.y * randf_range(0.6, 0.9)
		else:
			spawn_y = _main.boundary_size.y * randf_range(0.1, 0.4)
		clone.position = Vector2(spawn_x, spawn_y)
		
		# 物理冻结: 具象化期间悬停在原地
		clone.freeze = true
		clone.modulate = Color(1, 1, 1, 0)
		
		_main.add_child(clone)
		_main.pet_instances.append(clone)
		
		# 具象化特效
		var pet_hue = clone.palette.effective_hue() if clone.palette else 0.6
		var vfx = _MaterializeVFX.new(pet_hue, clone.PET_RADIUS)
		clone.add_child(vfx)
		
		# 淡入 + 完成后解冻掉落
		var fade_dur = 1.0
		vfx.duration = 1.5  # 特效比淡入多持续 0.5 秒收尾
		var tween = clone.create_tween()
		tween.tween_property(clone, "modulate:a", 1.0, fade_dur).set_ease(Tween.EASE_IN)
		tween.tween_callback(func():
			# 解冻: 开始掉落
			if is_instance_valid(clone):
				clone.freeze = false
		)
	
	SettingsManager.set_int("clone_count", _main.pet_instances.size() - 1)
	
	if with_bubble:
		var greetings = ["分身已部署。信号同步中。", "新单元上线。", "编队扩充。", "...又多了一个。", "部署完毕。"]
		EventBus.force_show_bubble.emit(greetings[clone_count % greetings.size()])
	
	print("[DesktopPet] 克隆体 #", pet_index, " 已生成 (hue=", clone.palette.get_hue_degrees(), "°)")
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

func _on_nighttime_mode_changed(active: bool) -> void:
	if active:
		reorganize_quiet_queue()

## 动态重新评估所有克隆体在屏幕上的水平位置，重新分配车位
func reorganize_quiet_queue() -> void:
	# 安静待命 OR 深夜模式 时才需要排队
	var any_quiet: bool = _main.behavior_mode == 1
	if not any_quiet:
		for p in _main.pet_instances:
			if is_instance_valid(p) and p.nighttime_mode:
				any_quiet = true
				break
	if not any_quiet:
		return
	
	# 反重力: 目标 Y 在天花板附近；正常: 目标 Y 在地面附近
	var ag = SettingsManager.get_bool("anti_gravity", false)
	var target_y: float = _main.get_stand_ceiling_y() + 35.0 if ag else _main.get_stand_floor_y() - 35.0
	
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

## 生成一个与现有宠物色调差异足够大的随机 hue (避免撞色)
func _generate_distinct_hue() -> float:
	var existing_hues: Array[float] = []
	for p in _main.pet_instances:
		if is_instance_valid(p) and p.palette:
			existing_hues.append(p.palette.hue)
	
	const MIN_HUE_DISTANCE := 0.08  # 色调最小间距 (约 29°)
	const MAX_ATTEMPTS := 20
	
	for attempt in range(MAX_ATTEMPTS):
		var candidate = randf()
		var too_close = false
		for h in existing_hues:
			var dist = absf(candidate - h)
			dist = minf(dist, 1.0 - dist)  # 环形距离
			if dist < MIN_HUE_DISTANCE:
				too_close = true
				break
		if not too_close:
			return candidate
	
	# 如果尝试次数耗尽 (宠物太多)，直接返回随机值
	return randf()

# ══════════════════════════════════════
# 次元具象化特效 (克隆体空降入场)
# ══════════════════════════════════════

class _MaterializeVFX extends Node2D:
	## 特效色调 (跟随克隆体配色)
	var _hue: float = 0.6
	## 宠物半径 (决定特效范围)
	var _radius: float = 30.0
	## 特效总时长
	var duration: float = 3.0
	## 内部计时
	var _time: float = 0.0
	## 数据碎片种子 (确定性随机, 每帧一致)
	var _frag_seeds: Array[float] = []
	
	func _init(hue: float = 0.6, radius: float = 30.0) -> void:
		_hue = hue
		_radius = radius
		# 预生成碎片种子 (黄金比例分布)
		for i in range(12):
			_frag_seeds.append(float(i) * 1.618033)
	
	func _process(delta: float) -> void:
		_time += delta
		if _time >= duration:
			queue_free()
			return
		queue_redraw()
	
	func _draw() -> void:
		var progress = clampf(_time / duration, 0.0, 1.0)
		# 特效整体强度: 前 70% 渐强, 后 30% 淡出
		var intensity: float
		if progress < 0.7:
			intensity = progress / 0.7
		else:
			intensity = (1.0 - progress) / 0.3
		intensity = clampf(intensity, 0.0, 1.0)
		
		# ── 1. 空间裂隙: 垂直亮线 → 逐渐扩展 ──
		var slit_h = _radius * 2.5 * (0.2 + progress * 0.8)
		var slit_w = 1.5 + progress * _radius * 0.3
		var slit_alpha = intensity * 0.25
		var slit_color = Color.from_hsv(_hue, 0.3, 1.0, slit_alpha)
		draw_rect(Rect2(-slit_w / 2.0, -slit_h / 2.0, slit_w, slit_h), slit_color)
		# 裂隙中心亮线
		var core_alpha = intensity * 0.5
		draw_line(Vector2(0, -slit_h / 2.0), Vector2(0, slit_h / 2.0),
			Color.from_hsv(_hue, 0.15, 1.0, core_alpha), 1.0, true)
		
		# ── 2. 脉冲环: 从中心向外扩散 ──
		for i in range(3):
			var ring_t = fmod(_time * 0.6 + float(i) * 0.33, 1.0)
			var ring_r = _radius * (0.3 + ring_t * 2.0)
			var ring_alpha = (1.0 - ring_t) * intensity * 0.35
			if ring_alpha > 0.01:
				draw_arc(Vector2.ZERO, ring_r, 0, TAU, 48,
					Color.from_hsv(_hue, 0.4, 0.9, ring_alpha), 1.2, true)
		
		# ── 3. 数据碎片: 从远处汇聚到中心 ──
		for i in range(_frag_seeds.size()):
			var seed_v = _frag_seeds[i]
			var angle = seed_v * TAU
			# 碎片从远处飞向中心, 随进度接近
			var dist_factor = 1.0 - clampf((_time - float(i) * 0.12) / (duration * 0.7), 0.0, 1.0)
			var dist = _radius * (1.5 + dist_factor * 3.5)
			var pos = Vector2(cos(angle), sin(angle)) * dist
			var frag_alpha = (1.0 - dist_factor * 0.6) * intensity * 0.5
			if frag_alpha > 0.01 and dist_factor > 0.02:
				var fw = 2.0 + fmod(seed_v * 7.3, 4.0)
				var fh = 1.0 + fmod(seed_v * 3.7, 2.0)
				draw_rect(Rect2(pos.x - fw / 2.0, pos.y - fh / 2.0, fw, fh),
					Color.from_hsv(_hue, 0.3, 1.0, frag_alpha))
		
		# ── 4. 水平扫描线: 上下扫过 ──
		var scan_y = sin(_time * 2.5) * _radius * 1.2
		var scan_alpha = intensity * 0.15
		if scan_alpha > 0.01:
			draw_line(Vector2(-_radius * 2.0, scan_y), Vector2(_radius * 2.0, scan_y),
				Color.from_hsv(_hue, 0.2, 1.0, scan_alpha), 0.8, true)

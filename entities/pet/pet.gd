# pet.gd — 宠物本体控制器
# 管理状态机、视觉渲染、输入检测
extends RigidBody2D

# ── 常量 ──
const PET_RADIUS := 30.0

# ── 状态机 ──
var states: Dictionary = {}
var current_state: PetState
var current_state_name: String = ""
var speed: float = 200.0            # 移动速度基数
var move_style: int = 0              # 步态风格: 0=蹦跳为主, 1=滚动为主, 2=混合平衡
var stroll_enabled: bool = true      # 自主巡航特殊事件开关 (独立于步态)
var free_roam_enabled: bool = false   # 空间跳跃开关 (透明踏板攀升)
var anti_gravity: bool = false       # 反重力模式
var gravity_sign: float = 1.0        # 重力方向符号 (1.0=正常, -1.0=反转)

# ── 克隆系统 ──
var is_clone: bool = false           # 是否为克隆分身

# ── 调色板 ──
var palette: PetColorPalette         # 每个宠物实例的独立调色板 (由 _ready 初始化)

# ── HUD + 气泡系统 (委托给 PetHUD) ──
var pet_hud: PetHUD
var hud_panel: HudPanel

# ── 眼球行为控制器 ──
var eye_behavior: EyeBehavior

# ── 特效系统 (委托给 PetEffects) ──
var pet_effects: PetEffects

# ── 屏幕信息 (由 main.gd 设置) ──
var screen_rect: Rect2i
var boundary_size: Vector2  # 视口坐标系的实际边界
var last_frame_speed: float = 0.0 # 用于捕获撞击前瞬时速度
var overlay_rect: Rect2 = Rect2() # 外部覆盖层的屏幕区域 (气泡通知等)



# ── 窗口交互模式 (由 main.gd 通过 EventBus 同步) ──
var window_mode: int = 0  # 0=FREE, 1=CONFINED, 2=REPELLED

# ── 行为指令 ──
var behavior_mode: int = 0  # 0=FREE(自由行动), 1=QUIET(安静待命)
@warning_ignore("unused_private_class_variable")
var _was_dragged_in_quiet: bool = false  # 安静模式下被拖拽的标记 (drag.gd写/fall.gd读)
var _quiet_drag_count: int = 0           # 安静模式下被拖拽的累计次数
var _last_quiet_drag_line: String = ""   # 上次显示的话术 (防连续重复)
var is_strolling: bool = false  # 是否正在滚动漫步 (供其他宠物检测让路)

# ── 戳一戳交互系统 (委托给 PokeSystem) ──
var poke_system: PokeSystem

# ── Idle 微行为系统 (委托给 IdleBehaviors) ──
var idle_behaviors: IdleBehaviors

func _ready() -> void:
	# 初始化调色板 (必须在所有子系统之前)
	if palette == null:
		palette = PetColorPalette.new()
	
	# 物理材质
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.35    # 适度弹性，落地有轻微回弹但不过度
	mat.friction = 0.6   # 中等摩擦，落地后自然减速
	physics_material_override = mat
	
	# 质量与阻尼
	mass = 2.0
	linear_damp = 0.5    # 基础线性阻尼 (各状态会动态覆盖)
	angular_damp = 0.5   # 基础角阻尼，落地后旋转较快停止
	
	# 开启连续碰撞检测 (防止高速穿墙)
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	
	# 开启刚体接触监听，用于最真实的物理“瞬时撞击”特效
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	
	# 初始化眼球行为控制器 (必须在状态机之前，fall.enter() 会访问 eye_behavior)
	eye_behavior = EyeBehavior.new()
	eye_behavior.pet = self
	
	# 初始化状态机
	_init_states()
	
	# 初始化戳一戳交互系统
	poke_system = PokeSystem.new()
	poke_system.pet = self
	
	# 初始化特效系统
	pet_effects = PetEffects.new()
	pet_effects.pet = self
	
	# 初始化 Idle 微行为系统
	idle_behaviors = IdleBehaviors.new()
	idle_behaviors.pet = self
	
	# 初始化 HUD + 气泡系统
	pet_hud = PetHUD.new()
	pet_hud.pet = self
	pet_hud.init_bubbles()
	
	# 初始化统一 HUD 面板 (时钟+WiFi+未来组件)
	hud_panel = HudPanel.new()
	hud_panel.init(self)
	
	# 从持久化存储恢复设置 (不依赖信号时序)
	eye_behavior.tracking_enabled = SettingsManager.get_bool("eye_track", true)
	pet_effects.shockwave_enabled = SettingsManager.get_bool("shockwave", true)
	pet_effects.trail_enabled = SettingsManager.get_bool("trail_fx", true)
	pet_effects.arc_enabled = SettingsManager.get_bool("arc_fx", true)
	pet_effects.effect_color_mode = SettingsManager.get_int("effect_color_mode", 0)
	move_style = SettingsManager.get_int("move_style", 0)
	stroll_enabled = SettingsManager.get_bool("stroll", true)
	free_roam_enabled = SettingsManager.get_bool("free_roam", false)
	var ag = SettingsManager.get_bool("anti_gravity", false)
	_set_anti_gravity(ag)
	# HUD 组件状态恢复 (仅原体)
	if not is_clone:
		var hud_clock = SettingsManager.get_bool("hud_clock", false)
		var hud_wifi = SettingsManager.get_bool("hud_wifi", false)
		var hud_pin_val = SettingsManager.get_bool("hud_pin", false)
		hud_panel.set_pin(hud_pin_val)
		if hud_clock:
			hud_panel.set_clock(true)
		if hud_wifi:
			hud_panel.set_wifi(true)
	
	# 监听运行时设置变更
	EventBus.setting_toggled.connect(_on_setting_toggled)
	EventBus.behavior_mode_changed.connect(_on_behavior_mode_changed)
	EventBus.pet_color_changed.connect(_on_pet_color_changed)
	EventBus.trigger_idle_behavior.connect(_on_trigger_idle_behavior)
	EventBus.trigger_free_roam.connect(_on_trigger_free_roam)
	EventBus.pet_scanning_changed.connect(_on_pet_scanning_changed)
	EventBus.pet_show_eye_icon.connect(_on_pet_show_eye_icon)

func _on_setting_toggled(setting_id: String, is_on: bool) -> void:
	if setting_id == "eye_track":
		eye_behavior.tracking_enabled = is_on
	elif setting_id == "shockwave":
		pet_effects.shockwave_enabled = is_on
	elif setting_id == "trail_fx":
		pet_effects.trail_enabled = is_on
	elif setting_id == "arc_fx":
		pet_effects.arc_enabled = is_on
	elif setting_id == "effect_color_mode":
		pet_effects.effect_color_mode = SettingsManager.get_int("effect_color_mode", 0)
	elif setting_id == "move_style":
		move_style = SettingsManager.get_int("move_style", 0)
	elif setting_id == "stroll":
		stroll_enabled = is_on
	elif setting_id == "free_roam":
		free_roam_enabled = is_on
	elif setting_id == "anti_gravity":
		_set_anti_gravity(is_on)
	elif setting_id == "hud_clock":
		if is_clone:
			return
		hud_panel.set_clock(is_on)
	elif setting_id == "hud_wifi":
		if is_clone:
			return
		hud_panel.set_wifi(is_on)
	elif setting_id == "hud_pin":
		if is_clone:
			return
		hud_panel.set_pin(is_on)

func _on_behavior_mode_changed(mode: int) -> void:
	behavior_mode = mode
	_was_dragged_in_quiet = false  # 清除残留标记

func _on_trigger_idle_behavior(behavior: String) -> void:
	if is_clone:
		return
	# 解析风格参数 (格式: "hibernate:1" → behavior="hibernate", style=1)
	var style := -1
	var base_behavior := behavior
	if ":" in behavior:
		var parts = behavior.split(":")
		base_behavior = parts[0]
		style = int(parts[1])
	# 强制切到 idle 状态 (微行为需要在 idle 中运行)
	if current_state_name != "idle":
		transition_to("idle")
	if style >= 0 and base_behavior == "hibernate":
		idle_behaviors.hibernate_style = style
	idle_behaviors.trigger(base_behavior)

func _on_pet_scanning_changed(state: String) -> void:
	if is_clone:
		return
	match state:
		"scanning":
			eye_behavior.start_scanning()
		"done":
			eye_behavior.finish_scanning()
		"idle":
			eye_behavior.stop_scanning()

func _on_pet_show_eye_icon(icon_type: String) -> void:
	if is_clone:
		return
	if icon_type == "":
		eye_behavior.hide_eye_icon()
	else:
		eye_behavior.show_eye_icon(icon_type)
func _on_pet_color_changed(pet_index: int, hue: float, sat: float, val: float) -> void:
	var my_index = get_meta("pet_index", 0)
	if pet_index != my_index:
		return
	palette.set_hue(hue)
	palette.sat_scale = sat
	palette.val_scale = val
	queue_redraw()

func _init_states() -> void:
	states = {
		"idle": preload("res://entities/pet/states/idle.gd").new(),
		"walk": preload("res://entities/pet/states/walk.gd").new(),
		"drag": preload("res://entities/pet/states/drag.gd").new(),
		"fall": preload("res://entities/pet/states/fall.gd").new(),
		"jump": preload("res://entities/pet/states/jump.gd").new(),
		"retreat": preload("res://entities/pet/states/retreat.gd").new(),
	}
	for state in states.values():
		state.pet = self
	transition_to("fall")  # 初始从空中掉落

func transition_to(state_name: String) -> void:
	if state_name == current_state_name:
		return
	var old_name = current_state_name
	if current_state:
		current_state.exit()
	current_state = states.get(state_name)
	current_state_name = state_name
	if current_state:
		current_state.enter()
	EventBus.pet_state_changed.emit(old_name, state_name)

# ── HUD + 气泡委托 ──

func show_local_bubble(message: String) -> void:
	pet_hud.show_bubble(message)

func get_local_bubble_rects() -> Array[Rect2]:
	return pet_hud.get_bubble_rects()

# ── 特效委托 ──

func trigger_shockwave() -> void:
	pet_effects.trigger_shockwave()

func get_shockwaves_count() -> int:
	return pet_effects.get_shockwave_count()


# ── 辅助方法 ──

func is_mouse_on_pet() -> bool:
	var mouse_pos = get_global_mouse_position()
	return global_position.distance_to(mouse_pos) <= PET_RADIUS + 15.0

func is_settled() -> bool:
	return linear_velocity.length() < 20.0 and abs(linear_velocity.y) < 10.0

## 切换反重力模式
func _set_anti_gravity(on: bool) -> void:
	anti_gravity = on
	gravity_sign = -1.0 if on else 1.0
	gravity_scale = -1.0 if on else 1.0
	# 给一个初始推力让宠物快速飞向目标 (开启→向天花板, 关闭→向地板)
	apply_central_impulse(Vector2(0, gravity_sign * 300.0))

# ── 自由移动 (透明踏板跳跃) ──
# 机制: 宠物先跳 → 顶点时踏板接住 → 落稳后继续跳 → 电梯式缓降归位

var _roam_platforms: Array[Node] = []  # 当前活跃的踏板
var _roam_active: bool = false         # 是否正在攀升/下降
var _roam_jumps_left: int = 0          # 剩余跳跃次数 (上升)
var _roam_phase: int = 0               # 0=空闲, 1=上升等顶点, 2=等落稳, 3=电梯下降中
var _roam_was_rising: bool = false     # 是否曾上升 (检测顶点用)
var _roam_airtime: float = 0.0        # 空中计时
var _roam_descending: bool = false     # 是否在下降阶段
var _roam_elevator: StaticBody2D = null  # 电梯踏板引用

const PLATFORM_WIDTH := 150.0          # 踏板宽度 (足够站稳)
const ELEVATOR_SPEED := 100.0          # 电梯下降速度 (px/s)

func _on_trigger_free_roam() -> void:
	if is_clone:
		return
	if _roam_active:
		return
	_start_free_roam()

func _start_free_roam() -> void:
	_roam_active = true
	_roam_jumps_left = randi_range(2, 4)
	_roam_phase = 0
	_roam_descending = false
	_roam_elevator = null
	
	# 锁定到 idle 状态 (中断 walk/jump 等行为，防止状态机冲突)
	if current_state != states.get("idle"):
		transition_to("idle")
	
	# 显示启动话术
	var lines := [
		"检测到垂直空间...启动攀升协议。",
		"切换至纵向移动模式。",
		"计算跳跃路径...执行。",
		"重力场分析完毕。开始移动。",
	]
	show_local_bubble(lines[randi() % lines.size()])
	
	# 第一跳
	_roam_do_jump()

func _roam_do_jump() -> void:
	if _roam_jumps_left <= 0:
		_roam_begin_descent()
		return
	
	_roam_jumps_left -= 1
	_roam_phase = 1  # 上升中，等待顶点
	_roam_was_rising = false
	_roam_airtime = 0.0
	
	# 随机跳跃方向
	var hop_dir = [-1.0, 1.0].pick_random()
	var x = global_position.x
	var w = boundary_size.x
	if x < 150.0: hop_dir = 1.0
	elif x > w - 150.0: hop_dir = -1.0
	
	# 较大的跳跃冲量 (比普通 jump 更高)
	var vy = randf_range(700.0, 1000.0) * -gravity_sign
	var vx = hop_dir * randf_range(100.0, 250.0)
	
	linear_damp = 0.2
	angular_damp = 0.6
	apply_central_impulse(Vector2(vx, vy))
	apply_torque_impulse(hop_dir * randf_range(3000.0, 8000.0))
	
	# 瞳孔看向跳跃方向
	eye_behavior.forced_look_dir = Vector2(hop_dir, -gravity_sign).normalized()

## 每帧检测攀升/下降状态
func _roam_update(_delta: float) -> void:
	if not _roam_active or _roam_phase == 0:
		return
	
	if _roam_phase == 1:
		# ── 阶段 1: 上升中，检测抛物线顶点 ──
		_roam_airtime += _delta
		var vy = linear_velocity.y * gravity_sign  # 标准化: 正=下落, 负=上升
		
		if vy < -30.0:
			_roam_was_rising = true
		
		if _roam_was_rising and vy > -20.0 and _roam_airtime > 0.15:
			# 到达顶点! 生成踏板 + 立即制动
			var platform_y = global_position.y + (PET_RADIUS) * gravity_sign
			_spawn_step_platform(Vector2(global_position.x, platform_y))
			_roam_brake()  # 制动防滚落
			_roam_phase = 2
	
	elif _roam_phase == 2:
		# ── 阶段 2: 上升踏板已生成，等宠物落稳 ──
		if is_settled():
			_roam_full_stop()  # 完全刹车
			_roam_phase = 0
			_roam_pause_then_jump()
	
	elif _roam_phase == 3:
		# ── 阶段 3: 电梯下降中 ──
		if not is_instance_valid(_roam_elevator):
			_roam_finish()
			return
		
		# 缓慢移动电梯踏板
		_roam_elevator.position.y += ELEVATOR_SPEED * _delta * gravity_sign
		
		# 直接锁定宠物到踏板正上方 (刚性跟随，无延迟)
		var target_y = _roam_elevator.position.y - PET_RADIUS * gravity_sign
		global_position.y = target_y
		linear_velocity.y = 0  # 清零垂直速度，防止物理漂移
		# 水平方向柔性居中
		var drift = global_position.x - _roam_elevator.position.x
		if absf(drift) > 3.0:
			global_position.x = lerpf(global_position.x, _roam_elevator.position.x, 6.0 * _delta)
		# 阻尼: 保持宠物稳定不晃动
		linear_velocity.x *= 0.8
		angular_velocity *= 0.85
		
		# 检查是否接近地面
		var ground_y = boundary_size.y if not anti_gravity else 0.0
		var dist = absf(_roam_elevator.position.y - ground_y)
		
		if dist < 20.0:
			# 接近地面: 踏板渐隐，宠物自然着地
			linear_damp = 0.5
			angular_damp = 0.8
			_roam_phase = 0
			# 渐隐电梯踏板
			var elevator = _roam_elevator
			_roam_elevator = null
			var tween = elevator.create_tween()
			tween.tween_property(elevator, "modulate:a", 0.0, 0.5)
			tween.finished.connect(func():
				if is_instance_valid(elevator):
					_roam_platforms.erase(elevator)
					elevator.queue_free()
			)
			_roam_finish()

## 着陆制动: 大幅衰减速度防止滚落
func _roam_brake() -> void:
	linear_velocity.x *= 0.15
	angular_velocity *= 0.1
	linear_damp = 4.0
	angular_damp = 6.0

## 完全刹车: 落稳后彻底停住
func _roam_full_stop() -> void:
	linear_velocity.x = 0
	angular_velocity = 0
	linear_damp = 5.0
	angular_damp = 8.0

func _roam_pause_then_jump() -> void:
	await get_tree().create_timer(0.8).timeout
	if not _roam_active:
		return
	if _roam_jumps_left > 0:
		_roam_do_jump()
	else:
		_roam_begin_descent()

# ── 电梯式下降 ──

func _roam_begin_descent() -> void:
	# 清除所有残留的上升踏板
	_roam_clear_platforms()
	
	# 计算距离地面还有多远
	var ground_y = boundary_size.y if not anti_gravity else 0.0
	var dist_to_ground = absf(global_position.y - ground_y)
	
	if dist_to_ground < 120.0:
		_roam_finish()
		return
	
	_roam_descending = true
	
	# 下降话术
	var lines := [
		"高度数据已记录。执行安全着陆程序。",
		"启动减速下降...逐级归位。",
		"重力辅助着陆协议启动。",
	]
	show_local_bubble(lines[randi() % lines.size()])
	
	# 等宠物稳定后生成电梯踏板
	await get_tree().create_timer(0.6).timeout
	if not _roam_active:
		return
	
	# 完全停住宠物
	_roam_full_stop()
	gravity_scale = 0.0  # 下降期间关闭重力 (由电梯踏板带动)
	
	# 在脚下生成电梯踏板 (不走定时销毁)
	var platform_y = global_position.y + PET_RADIUS * gravity_sign
	var elevator = _spawn_step_platform(Vector2(global_position.x, platform_y), true)
	_roam_elevator = elevator
	
	# 瞳孔朝下看
	eye_behavior.forced_look_dir = Vector2(0, gravity_sign)
	
	_roam_phase = 3  # 开始电梯下降

func _roam_finish() -> void:
	_roam_active = false
	_roam_phase = 0
	_roam_jumps_left = 0
	_roam_descending = false
	# 恢复重力
	gravity_scale = gravity_sign
	# 清理电梯引用
	_roam_elevator = null
	eye_behavior.forced_look_dir = Vector2.ZERO

## 快速清除所有残留踏板 (0.3秒渐隐)
func _roam_clear_platforms() -> void:
	for body in _roam_platforms:
		if is_instance_valid(body):
			var tween = body.create_tween()
			tween.tween_property(body, "modulate:a", 0.0, 0.3)
			tween.finished.connect(func():
				if is_instance_valid(body):
					body.queue_free()
			)
	_roam_platforms.clear()

func _spawn_step_platform(pos: Vector2, is_elevator: bool = false) -> StaticBody2D:
	var parent = get_parent()
	if not parent:
		return null
	
	var platform_thickness := 8.0
	
	# 物理碰撞体
	var body = StaticBody2D.new()
	body.position = pos
	
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(PLATFORM_WIDTH, platform_thickness)
	col.shape = shape
	col.one_way_collision = true  # 单向碰撞: 只能从下往上踩
	# 反重力时翻转单向碰撞方向
	if anti_gravity:
		col.rotation = PI
	body.add_child(col)
	
	# 视觉渲染节点
	var visual = _PlatformVisual.new()
	visual.platform_width = PLATFORM_WIDTH
	visual.platform_color = palette.shift_color(Color(0.2, 0.6, 1.0, 0.6))
	body.add_child(visual)
	
	parent.add_child(body)
	_roam_platforms.append(body)
	
	# 淡入动画
	body.modulate.a = 0.0
	var tween = body.create_tween()
	tween.tween_property(body, "modulate:a", 1.0, 0.15)
	
	# 电梯踏板不走定时销毁 (由电梯逻辑自行管理)
	if not is_elevator:
		_schedule_platform_removal(body, 3.5)
	
	return body

func _schedule_platform_removal(body: Node, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(body):
		var tween = body.create_tween()
		tween.tween_property(body, "modulate:a", 0.0, 0.8)
		tween.finished.connect(func():
			if is_instance_valid(body):
				_roam_platforms.erase(body)
				body.queue_free()
		)

## 踏板视觉渲染 (科技风能量平台)
## 特效: 从中心向两端展开 + 刻度线 + 能量流动 + 着陆闪光
class _PlatformVisual extends Node2D:
	var platform_width: float = 120.0
	var platform_color: Color = Color(0.2, 0.6, 1.0, 0.6)
	var _time: float = 0.0
	var _expand: float = 0.0          # 展开进度 0→1
	var _land_flash: float = 0.0      # 着陆闪光强度
	var _landed: bool = false         # 已检测到着陆
	
	func _process(delta: float) -> void:
		_time += delta
		# 展开动画: 0.3 秒从中心展开到全宽
		_expand = minf(_expand + delta / 0.3, 1.0)
		# 着陆闪光衰减
		if _land_flash > 0.0:
			_land_flash = maxf(_land_flash - delta * 3.0, 0.0)
		# 着陆检测: 踏板存在 0.4 秒后，如果父节点(body)被碰撞到会产生微振
		# 简化方案: 超过展开期后检测一次
		if not _landed and _time > 0.35:
			_landed = true
			_land_flash = 1.0  # 接住时闪一下
		queue_redraw()
	
	func _draw() -> void:
		var expand_ease = _ease_out_quad(_expand)
		var hw = platform_width / 2.0 * expand_ease  # 展开后的半宽
		if hw < 1.0:
			return
		
		var pulse = 0.85 + sin(_time * TAU / 2.5) * 0.15  # 呼吸脉冲
		var flash_boost = _land_flash * 0.4  # 着陆时整体提亮
		var c = Color(
			minf(platform_color.r + flash_boost, 1.0),
			minf(platform_color.g + flash_boost, 1.0),
			minf(platform_color.b + flash_boost * 0.5, 1.0),
			platform_color.a * pulse
		)
		
		# ── 外发光层 (最宽最透明) ──
		var glow_outer = Color(c.r, c.g, c.b, c.a * 0.15)
		draw_line(Vector2(-hw, 0), Vector2(hw, 0), glow_outer, 12.0, true)
		
		# ── 中发光层 ──
		var glow = Color(c.r, c.g, c.b, c.a * 0.3)
		draw_line(Vector2(-hw, 0), Vector2(hw, 0), glow, 6.0, true)
		
		# ── 主光线 (核心细线) ──
		draw_line(Vector2(-hw, 0), Vector2(hw, 0), c, 2.0, true)
		
		# ── 刻度线标记 (科技感细节) ──
		var tick_c = Color(c.r, c.g, c.b, c.a * 0.5)
		var tick_count = 5
		for i in range(tick_count):
			var t = float(i + 1) / float(tick_count + 1)
			var tx = lerpf(-hw, hw, t)
			draw_line(Vector2(tx, -3.0), Vector2(tx, 3.0), tick_c, 1.0, true)
		
		# ── 两端光点 (发散圆) ──
		var dot_c = Color(c.r, c.g, c.b, c.a * 0.9)
		draw_circle(Vector2(-hw, 0), 3.5, dot_c, true, -1.0, true)
		draw_circle(Vector2(hw, 0), 3.5, dot_c, true, -1.0, true)
		# 端点外圈光晕
		var halo_c = Color(c.r, c.g, c.b, c.a * 0.25)
		draw_circle(Vector2(-hw, 0), 6.0, halo_c, true, -1.0, true)
		draw_circle(Vector2(hw, 0), 6.0, halo_c, true, -1.0, true)
		
		# ── 中心能量核心 ──
		var core_c = Color(minf(c.r + 0.3, 1.0), minf(c.g + 0.3, 1.0), 1.0, c.a * 0.7)
		draw_circle(Vector2.ZERO, 2.5, core_c, true, -1.0, true)
		
		# ── 能量流动粒子 (两个光点沿线来回移动) ──
		if expand_ease > 0.8:
			var particle_a = c.a * 0.7
			var p1_t = fmod(_time * 0.6, 1.0)  # 从左到右
			var p2_t = fmod(_time * 0.6 + 0.5, 1.0)  # 半周期偏移
			var p1_x = lerpf(-hw * 0.9, hw * 0.9, p1_t)
			var p2_x = lerpf(-hw * 0.9, hw * 0.9, p2_t)
			var p_color = Color(minf(c.r + 0.2, 1.0), minf(c.g + 0.2, 1.0), 1.0, particle_a)
			draw_circle(Vector2(p1_x, 0), 2.0, p_color, true, -1.0, true)
			draw_circle(Vector2(p2_x, 0), 2.0, p_color, true, -1.0, true)
		
		# ── 着陆闪光环 (接住宠物时向外扩散) ──
		if _land_flash > 0.01:
			var ring_r = hw * (1.0 + (1.0 - _land_flash) * 0.3)
			var ring_c = Color(c.r, c.g, c.b, _land_flash * 0.6)
			draw_arc(Vector2.ZERO, ring_r, 0, TAU, 24, ring_c, 1.5, true)
	
	func _ease_out_quad(t: float) -> float:
		return 1.0 - (1.0 - t) * (1.0 - t)


# ── 戳一戳委托 ──

func handle_poke() -> void:
	poke_system.handle_poke()

# ── 主循环 ──

func _process(delta: float) -> void:
	if current_state:
		current_state.process(delta)
	
	# 更新子系统
	pet_hud.update(delta)
	# HUD 面板: 悬浮模式下转发鼠标状态
	if not is_clone:
		hud_panel.set_hover(is_mouse_on_pet())
	hud_panel.update(delta)
	eye_behavior.update(delta)
	var has_visual_change = pet_effects.update(delta)
	idle_behaviors.update(delta)
	_roam_update(delta)
	
	# 按需重绘：特效活跃 / 物理运动中 / 眼球动画播放中
	if has_visual_change or linear_velocity.length() > 1.0 or eye_behavior.is_animating():
		queue_redraw()

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_process(delta)
	
	# 记录本帧物理速度，如果下帧发生撞击，就是参考依据
	last_frame_speed = linear_velocity.length()

func _on_body_entered(_body: Node) -> void:
	# 只有获得极高动量猛烈砸在底盘或者墙壁时，才激荡出强大的火花
	if pet_effects.shockwave_enabled and last_frame_speed > 350.0:
		trigger_shockwave()

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.input(event)
	
	if event is InputEventMouseButton:
		# 右键呼出全局追踪菜单 (HUD) — 仅原体响应
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not is_clone and is_mouse_on_pet():
				get_viewport().set_input_as_handled()
				EventBus.show_context_menu.emit(self)

# ── 视觉系统 ──

func _draw() -> void:
	# ── 绘制特效 (冲击波 + 拖影，委托给 PetEffects) ──
	pet_effects.render(self)
	# ── 绘制能量共鸣弧 (近距离宠物间的静电放电) ──
	pet_effects.render_arcs(self)
	
	# ── 科幻单眼结构 ──
	# 外壳不受眨眼影响
	# 1. 边缘深色轮廓与偏深的湛蓝主外壳 (palette 统一变换)
	var shell_outline := palette.shift_color(Color(0.08, 0.12, 0.32, 1.0))
	var shell_main := palette.shift_color(Color(0.15, 0.30, 0.80, 1.0))
	draw_circle(Vector2.ZERO, PET_RADIUS + 1.2, shell_outline, true, -1.0, true)
	draw_circle(Vector2.ZERO, PET_RADIUS, shell_main, true, -1.0, true)
	
	# 2. 白色边框 (不受色调影响)
	var border_radius = PET_RADIUS * 0.85
	draw_arc(Vector2.ZERO, border_radius, 0, TAU, 64, Color(1.0, 1.0, 1.0, 0.8), 1.2, true)
	
	# 3. 四个尖尖的角 (底座圆垫与独立四向锥形叶片)
	var dark_blue := palette.shift_color(Color(0.12, 0.18, 0.42, 1.0))
	var base_r = PET_RADIUS * 0.68
	var tip_dist = border_radius - 1.0  # 尖角刚刚触碰白边内侧
	
	# 绘制深色底盘核心
	draw_circle(Vector2.ZERO, base_r, dark_blue, true, -1.0, true)
	# 绘制4个向外伸展的尖角（平滑与底盘融合的三角形）
	for i in range(4):
		var angle = i * PI / 2.0 + PI / 4.0  # 每个对角线：45, 135, 225, 315 度
		var tip_pos = Vector2(cos(angle), sin(angle)) * tip_dist
		var half_hw = PI / 10.0  # 控制尖刺的底部张角，避免过于瘦弱
		var left_base = Vector2(cos(angle - half_hw), sin(angle - half_hw)) * (base_r * 0.95)
		var right_base = Vector2(cos(angle + half_hw), sin(angle + half_hw)) * (base_r * 0.95)
		draw_polygon(PackedVector2Array([left_base, tip_pos, right_base]), PackedColorArray([dark_blue, dark_blue, dark_blue]))
	
	# 机械虹膜：眨眼时内部光圈收缩向中心
	# 眼球反向旋转补偿：抵消 RigidBody2D 的滚动角度，让眼球始终保持水平
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	var blink = eye_behavior.get_blink_amount()
	var iris_scale = 1.0 - blink * 0.95  # 闭眼峰值时虹膜缩至 5%
	if iris_scale > 0.05:
		# 虹膜内三层跟随鼠标偏移，眼白固定
		var iris_offset = eye_behavior.get_pupil_offset() * iris_scale
		# 第一层：眼白（巩膜）— 固定在圆心不动
		draw_circle(Vector2.ZERO, PET_RADIUS * 0.54 * iris_scale, palette.shift_color(Color(0.85, 0.88, 0.92, 1.0)), true, -1.0, true)
		# 第二层：灰蓝色虹膜外环 — 跟随鼠标
		draw_circle(iris_offset, PET_RADIUS * 0.42 * iris_scale, palette.shift_color(Color(0.55, 0.65, 0.80, 1.0)), true, -1.0, true)
		# 第三层：深蓝色虹膜内环 — 跟随鼠标
		draw_circle(iris_offset, PET_RADIUS * 0.28 * iris_scale, palette.shift_color(Color(0.15, 0.28, 0.68, 1.0)), true, -1.0, true)
		# 第四层：极暗的瞳孔核心 — 跟随鼠标
		draw_circle(iris_offset, PET_RADIUS * 0.16 * iris_scale, palette.shift_color(Color(0.05, 0.08, 0.20, 1.0)), true, -1.0, true)
		
		# 高光反射点 (固定在虹膜左上方，模拟环境光泽)
		var highlight_offset = iris_offset + Vector2(-PET_RADIUS * 0.08, -PET_RADIUS * 0.10) * iris_scale
		var highlight_fade = 1.0 - eye_behavior.get_drowsy_amount()  # 休眠时高光暗淡
		draw_circle(highlight_offset, PET_RADIUS * 0.11 * iris_scale, Color(1.0, 1.0, 1.0, iris_scale * 0.85 * highlight_fade), true, -1.0, true)
		draw_circle(highlight_offset, PET_RADIUS * 0.06 * iris_scale, Color(1.0, 1.0, 1.0, iris_scale * highlight_fade), true, -1.0, true)
		# ── 自定义休眠视觉 (覆盖整个内部区域到白边框) ──
	var h_blend = idle_behaviors.get_hibernate_visual_blend()
	if h_blend > 0.01:
		var screen_r = PET_RADIUS * 0.83  # 白边框内侧
		# 暗色屏幕覆盖层 (模拟设备关屏，覆盖虹膜+底座)
		draw_circle(Vector2.ZERO, screen_r, Color(0.03, 0.05, 0.12, h_blend * 0.95), true, -1.0, true)
		match idle_behaviors.hibernate_style:
			1: _draw_loading_spinner(screen_r, h_blend, idle_behaviors._hibernate_anim_time)
			2: _draw_battery_icon(screen_r, h_blend, idle_behaviors._hibernate_anim_time)
	
	# ── 检索动画覆盖层 (系统信息查询时瞳孔变加载指示器/对勾) ──
	# scanning_blend: 整体覆盖层 (scanning→done 期间保持1.0, stop时淡出)
	# done_blend: 内容交叉混合 (0=纯旋转器, 1=纯对勾)
	var scan_blend = eye_behavior.scanning_blend
	var done_blend = eye_behavior.scanning_done_blend
	if scan_blend > 0.01 or done_blend > 0.01:
		var scan_r = PET_RADIUS * 0.83  # 白边框内侧 (与休眠视觉同范围)
		# 暗色屏幕覆盖层 (由 scanning_blend 控制，过渡期间不会闪出眼瞳)
		var overlay_alpha = scan_blend * 0.95
		if done_blend > scan_blend:
			overlay_alpha = done_blend * 0.95  # stop_scanning 后 done_blend 独立淡出
		draw_circle(Vector2.ZERO, scan_r, Color(0.03, 0.05, 0.12, overlay_alpha), true, -1.0, true)
		# 加载旋转指示器 (随 done_blend 增大而淡出，实现交叉混合)
		var spinner_alpha = scan_blend * (1.0 - done_blend)
		if spinner_alpha > 0.01:
			_draw_loading_spinner(scan_r, spinner_alpha, eye_behavior.scanning_time)
		# 完成对勾图标 (随 done_blend 增大而淡入)
		if done_blend > 0.01:
			_draw_scanning_checkmark(scan_r, done_blend)
	
	# ── 通用图标覆盖层 (邮件/感叹号/问号等) ──
	var icon_blend = eye_behavior.eye_icon_blend
	if icon_blend > 0.01:
		var icon_r = PET_RADIUS * 0.83  # 白边框内侧
		# 暗色屏幕覆盖层
		draw_circle(Vector2.ZERO, icon_r, Color(0.03, 0.05, 0.12, icon_blend * 0.95), true, -1.0, true)
		# 按类型绘制对应图标
		match eye_behavior.eye_icon_type:
			"mail": _draw_eye_icon_mail(icon_r, icon_blend, eye_behavior.eye_icon_time)
			"alert": _draw_eye_icon_alert(icon_r, icon_blend, eye_behavior.eye_icon_time)
			"question": _draw_eye_icon_question(icon_r, icon_blend, eye_behavior.eye_icon_time)
			"error": _draw_eye_icon_error(icon_r, icon_blend, eye_behavior.eye_icon_time)
	
	# ── 休眠挡板 (仅风格0: 机械光圈半闭效果) ──
	var drowsy = eye_behavior.get_drowsy_amount()
	var is_shutter = idle_behaviors.active_behavior != "hibernate" or idle_behaviors.hibernate_style == 0
	if drowsy > 0.01 and iris_scale > 0.05 and is_shutter:
		var sclera_r = PET_RADIUS * 0.54 * iris_scale
		var plate_color = palette.shift_color(Color(0.10, 0.15, 0.38, 1.0))
		# 仅上挡板: 机械眼眸沉重下垂
		_draw_eye_shutter(sclera_r, sclera_r * drowsy * 1.5, true, plate_color)
	
	# 恢复默认变换，避免影响后续绘制
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## 绘制机械挡板 (圆弧段多边形，覆盖眼白的上方或下方)
func _draw_eye_shutter(radius: float, close_px: float, is_top: bool, color: Color) -> void:
	if close_px < 0.5:
		return
	# flat_y: 挡板平边的 Y 坐标
	var flat_y: float
	if is_top:
		flat_y = -radius + close_px    # 从顶部向下合拢
	else:
		flat_y = radius - close_px     # 从底部向上合拢
	flat_y = clampf(flat_y, -radius + 0.1, radius - 0.1)
	
	# 圆与平线的交点 X: x² + y² = r² → x = sqrt(r² - y²)
	var dx = sqrt(maxf(0.0, radius * radius - flat_y * flat_y))
	
	# 构建多边形: 平边两端点 + 沿圆弧的采样点
	var pts = PackedVector2Array()
	var arc_steps := 32
	var arc_r = radius + 1.0  # 弧线微超出巩膜圆, 消除内切弦间隙透出白色
	
	if is_top:
		# 从左交点出发，沿圆弧走上半圆到右交点，再沿平线封闭
		var angle_l = atan2(flat_y, -dx)  # 左交点角度
		var angle_r = atan2(flat_y, dx)   # 右交点角度
		var span = angle_r - angle_l
		if span < 0:
			span += TAU  # flat_y 越过圆心时 span 变负，修正为经过顶部的长弧
		for i in range(arc_steps + 1):
			var t = float(i) / float(arc_steps)
			var a = angle_l + span * t
			pts.append(Vector2(cos(a), sin(a)) * arc_r)
	else:
		# 从左交点出发，沿圆弧走下半圆到右交点
		var angle_l = atan2(flat_y, -dx)
		var angle_r = atan2(flat_y, dx)
		# 下半圆: 从 angle_l 经过 PI/2 (底部) 到 angle_r
		var span = angle_r - angle_l
		for i in range(arc_steps + 1):
			var t = float(i) / float(arc_steps)
			var a = angle_l + span * t
			pts.append(Vector2(cos(a), sin(a)) * arc_r)
	
	if pts.size() >= 3:
		draw_colored_polygon(pts, color)
		# 抗锯齿轮廓线 (消除多边形边缘锯齿)
		var outline_pts = pts.duplicate()
		outline_pts.append(pts[0])  # 闭合路径
		draw_polyline(outline_pts, color, 1.0, true)

## 绘制加载旋转指示器 (休眠风格1: 旋转弧线 + 光点)
func _draw_loading_spinner(radius: float, alpha: float, time: float) -> void:
	var spin_r = radius * 0.55
	var spin_angle = time * TAU * 0.4  # ~2.5 秒一圈
	var arc_len = PI * 0.8  # 144° 弧段
	var glow_color = palette.shift_color(Color(0.3, 0.6, 1.0, alpha * 0.85))
	# 主弧线
	draw_arc(Vector2.ZERO, spin_r, spin_angle, spin_angle + arc_len, 28, glow_color, 2.0, true)
	# 弧头光点
	var dot_pos = Vector2(cos(spin_angle + arc_len), sin(spin_angle + arc_len)) * spin_r
	draw_circle(dot_pos, 2.5, Color(glow_color.r, glow_color.g, glow_color.b, alpha), true, -1.0, true)
	# 弧尾渐隐尾迹 (更细、更透明)
	var trail_color = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.3)
	draw_arc(Vector2.ZERO, spin_r, spin_angle - PI * 0.3, spin_angle, 12, trail_color, 1.0, true)

## 绘制电池图标 (休眠风格2: 电池轮廓 + 脉冲充电条)
func _draw_battery_icon(radius: float, alpha: float, time: float) -> void:
	var bw = radius * 0.75  # 电池主体宽度
	var bh = radius * 0.45  # 电池主体高度
	var nub_w = radius * 0.08  # 正极凸起宽
	var nub_h = bh * 0.35  # 正极凸起高
	var outline_color = palette.shift_color(Color(0.35, 0.6, 1.0, alpha * 0.75))
	# 电池主体轮廓
	var x0 = -bw / 2.0
	var y0 = -bh / 2.0
	draw_rect(Rect2(x0, y0, bw, bh), outline_color, false, 1.5, true)
	# 正极凸起
	var nub_x = bw / 2.0
	var nub_y0 = -nub_h / 2.0
	draw_rect(Rect2(nub_x, nub_y0, nub_w, nub_h), outline_color, true, -1.0, true)
	# 充电条 (脉冲呼吸)
	var fill_pct = 0.25 + sin(time * TAU / 4.0) * 0.25  # 0% ~ 50%
	var pad = 2.5
	var fill_w = (bw - pad * 2) * fill_pct
	var fill_color = palette.shift_color(Color(0.25, 0.55, 1.0, alpha * 0.65))
	if fill_w > 1.0:
		draw_rect(Rect2(x0 + pad, y0 + pad, fill_w, bh - pad * 2), fill_color, true, -1.0, true)


## 绘制完成对勾图标 (检索完成: 机械风格SVG对勾)
func _draw_scanning_checkmark(radius: float, alpha: float) -> void:
	var s = radius * 0.06  # 缩放因子 (与其他图标统一)
	var glow_color = palette.shift_color(Color(0.2, 0.9, 0.5, alpha * 0.9))
	var lw = 2.2 * (radius / 16.0)
	# 对勾路径: 从左侧中部 → 底部中心 → 右上角
	var check_pts = PackedVector2Array([
		Vector2(-5.5, 0.0) * s,    # 起点: 左侧
		Vector2(-1.5, 5.0) * s,    # 拐点: 底部
		Vector2(6.0, -4.5) * s,    # 终点: 右上
	])
	draw_polyline(check_pts, glow_color, lw, true)
	# 外圈环 (完成状态标识)
	var ring_r = radius * 0.7
	var ring_color = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.5)
	draw_arc(Vector2.ZERO, ring_r, 0, TAU, 32, ring_color, 1.2, true)

## 绘制邮件图标 (信封轮廓 + V 型翻盖 + 呼吸脉冲)
func _draw_eye_icon_mail(radius: float, alpha: float, time: float) -> void:
	var s = radius * 0.06  # 缩放因子 (填满白边框区域)
	var glow_color = palette.shift_color(Color(0.3, 0.7, 1.0, alpha * 0.9))
	# 呼吸脉冲
	var pulse = 0.85 + sin(time * TAU / 3.0) * 0.15
	var c = Color(glow_color.r, glow_color.g, glow_color.b, alpha * pulse)
	var lw = 1.2 * (radius / 16.0)  # 线宽随半径缩放
	# 信封主体 (矩形轮廓)
	var hw = 7.0 * s  # 半宽
	var hh = 5.0 * s  # 半高
	var body_pts = PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh),
		Vector2(hw, hh), Vector2(-hw, hh),
		Vector2(-hw, -hh),  # 闭合
	])
	draw_polyline(body_pts, c, lw, true)
	# V 型翻盖 (从左上角 → 中下 → 右上角)
	var flap_pts = PackedVector2Array([
		Vector2(-hw, -hh),
		Vector2(0, hh * 0.35),
		Vector2(hw, -hh),
	])
	draw_polyline(flap_pts, c, lw, true)
	# 外环微光
	var ring_c = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.3)
	draw_arc(Vector2.ZERO, radius * 0.7, 0, TAU, 32, ring_c, 0.8, true)

## 绘制感叹号图标 (锥形竖条 + 醒目圆点 + 警示闪烁)
func _draw_eye_icon_alert(radius: float, alpha: float, time: float) -> void:
	var s = radius * 0.06
	var flash = 0.7 + sin(time * TAU / 1.5) * 0.3  # 1.5s 周期闪烁
	var glow_color = palette.shift_color(Color(1.0, 0.6, 0.15, alpha * flash))
	# 竖条主体 (上宽下窄的锥形多边形，而非均匀细线)
	var top_y = -8.5 * s
	var bot_y = 0.5 * s
	var top_hw = 1.8 * s   # 顶部半宽 (宽)
	var bot_hw = 0.7 * s   # 底部半宽 (窄)
	var bar_pts = PackedVector2Array([
		Vector2(-top_hw, top_y), Vector2(top_hw, top_y),  # 顶边
		Vector2(bot_hw, bot_y), Vector2(-bot_hw, bot_y),  # 底边
	])
	draw_colored_polygon(bar_pts, glow_color)
	# 抗锯齿轮廓
	var outline = bar_pts.duplicate()
	outline.append(bar_pts[0])
	draw_polyline(outline, glow_color, 0.8, true)
	# 底部圆点 (醒目，与竖条有明确间距)
	var dot_y = 4.0 * s
	draw_circle(Vector2(0, dot_y), 1.8 * (radius / 16.0), glow_color, true, -1.0, true)
	# 外环 (警示橙色)
	var ring_c = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.4)
	draw_arc(Vector2.ZERO, radius * 0.7, 0, TAU, 32, ring_c, 1.0, true)

## 绘制问号图标 (弧线 + 竖线 + 圆点 + 微摆动)
func _draw_eye_icon_question(radius: float, alpha: float, time: float) -> void:
	var s = radius * 0.06
	var glow_color = palette.shift_color(Color(0.5, 0.8, 1.0, alpha * 0.9))
	var lw = 1.6 * (radius / 16.0)
	# 微小浮动 (好奇的左右摆动)
	var sway = sin(time * TAU / 2.5) * 1.0 * s
	# 问号上半弧 (C 形曲线，采样绘制)
	var arc_pts = PackedVector2Array()
	var arc_cx = sway
	var arc_cy = -3.0 * s
	var arc_r = 3.5 * s
	for i in range(17):
		var t = float(i) / 16.0
		var a = PI * 1.1 + t * PI * 1.4  # 从左上绕到右下
		arc_pts.append(Vector2(arc_cx + cos(a) * arc_r, arc_cy + sin(a) * arc_r))
	draw_polyline(arc_pts, glow_color, lw, true)
	# 竖线段 (弧线底部到圆点上方)
	var stem_top = arc_cy + arc_r * sin(PI * 1.1 + PI * 1.4)
	var stem_bot = 2.0 * s
	draw_line(Vector2(sway, stem_top), Vector2(sway, stem_bot), glow_color, lw, true)
	# 底部圆点
	var dot_y = 4.5 * s
	draw_circle(Vector2(sway, dot_y), 1.0 * (radius / 16.0), glow_color, true, -1.0, true)
	# 外环微光
	var ring_c = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.35)
	draw_arc(Vector2.ZERO, radius * 0.7, 0, TAU, 32, ring_c, 0.8, true)

## 绘制错误标识 (红色交叉线 + 外环 + 闪烁)
func _draw_eye_icon_error(radius: float, alpha: float, time: float) -> void:
	var s = radius * 0.06
	var flash = 0.9 + sin(time * TAU / 3.0) * 0.1  # 3s 缓慢呼吸，微微明暗变化
	var glow_color = palette.shift_color(Color(1.0, 0.25, 0.2, alpha * flash))
	var lw = 2.2 * (radius / 16.0)
	# 交叉线 (左上→右下 + 右上→左下)
	var d = 5.5 * s  # 交叉半径
	draw_line(Vector2(-d, -d), Vector2(d, d), glow_color, lw, true)
	draw_line(Vector2(d, -d), Vector2(-d, d), glow_color, lw, true)
	# 外环 (警示红色)
	var ring_c = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.45)
	draw_arc(Vector2.ZERO, radius * 0.7, 0, TAU, 32, ring_c, 1.2, true)

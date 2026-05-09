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
var screen_wrap: bool = false        # 屏幕穿越模式 (左右边界环绕)
var _wrap_ghost_offset: Vector2 = Vector2.ZERO  # 穿越时幽灵副本的世界偏移

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
var last_frame_velocity: Vector2 = Vector2.ZERO # 用于捕获撞击前速度方向
var overlay_rect: Rect2 = Rect2() # 外部覆盖层的屏幕区域 (气泡通知等)



# ── 窗口交互模式 (由 main.gd 通过 EventBus 同步) ──
var window_mode: int = 0  # 0=FREE, 1=CONFINED, 2=REPELLED

# ── 行为指令 ──
var behavior_mode: int = 0  # 0=FREE(自由行动), 1=QUIET(安静待命)
var nighttime_mode: bool = false  # 深夜模式: 23:00~6:00 自动归位 + 半闭眼
@warning_ignore("unused_private_class_variable")
var _was_dragged_in_quiet: bool = false  # 安静模式下被拖拽的标记 (drag.gd写/fall.gd读)
var _quiet_drag_count: int = 0           # 安静模式下被拖拽的累计次数
var _last_quiet_drag_line: String = ""   # 上次显示的话术 (防连续重复)
var is_strolling: bool = false  # 是否正在滚动漫步 (供其他宠物检测让路)

## 统一判断: 宠物是否应处于安静排队行为 (手动安静待命 OR 深夜模式)
func is_quiet_behavior() -> bool:
	return behavior_mode == 1 or nighttime_mode

# ── 戳一戳交互系统 (委托给 PokeSystem) ──
var poke_system: PokeSystem

# ── Idle 微行为系统 (委托给 IdleBehaviors) ──
var idle_behaviors: IdleBehaviors

# ── 弹性形变系统 (委托给 PetSquash) ──
var squash: PetSquash

# ── 游戏状态 (全息迷你屏) ──
var _gaming: bool = false
var _gaming_game: RefCounted = null  # 当前游戏引用 (BaseGame)
var _gaming_holo_side: float = 1.0  # 全息屏方向: 1=右侧, -1=左侧
var _gaming_holo_aspect: float = 0.0  # 全息屏宽高比 (初始化后固定)
var _gaming_platform: StaticBody2D = null  # 游戏态悬浮踏板
var _gaming_lift_phase: int = 0     # 0=空闲, 1=上升中, 2=已到位
var _gaming_lift_target_y: float = 0.0  # 踏板目标高度

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
	
	# 初始化弹性形变系统
	squash = PetSquash.new()
	squash.pet = self
	
	# 初始化空间跳跃系统
	free_roam_sys = FreeRoamSystem.new()
	free_roam_sys.pet = self
	
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
	screen_wrap = SettingsManager.get_bool("screen_wrap", false)
	# 弹性形变恢复 (elastic_mode: 0=关闭, 1=轻弹, 2=果冻, 3=弹力球)
	var elastic_mode = SettingsManager.get_int("elastic_mode", 0)
	if elastic_mode > 0:
		squash.enabled = true
		squash.style = clampi(elastic_mode - 1, 0, 2)
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
	EventBus.trigger_squash_test.connect(_on_trigger_squash_test)
	EventBus.nighttime_mode_changed.connect(_on_nighttime_mode_changed)
	EventBus.pet_gaming_changed.connect(_on_pet_gaming_changed)

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
	elif setting_id == "screen_wrap":
		screen_wrap = is_on
		if not is_on:
			_wrap_ghost_offset = Vector2.ZERO
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

func _on_nighttime_mode_changed(active: bool) -> void:
	nighttime_mode = active
	_was_dragged_in_quiet = false

func _on_trigger_idle_behavior(behavior: String) -> void:
	if is_clone:
		return
	# 深夜模式: 拒绝执行指令 (宠物正在休眠，不接受命令)
	if nighttime_mode:
		show_local_bubble("休眠周期中。指令已搁置。")
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

func _on_pet_gaming_changed(active: bool, game: RefCounted) -> void:
	if is_clone:
		return
	_gaming = active
	_gaming_game = game
	if active:
		_gaming_holo_aspect = 0.0  # 重置，让新游戏初始化自己的比例
		# 决定全息屏在宠物哪边
		if global_position.x > boundary_size.x * 0.5:
			_gaming_holo_side = -1.0
		else:
			_gaming_holo_side = 1.0
		# 高阻尼停下来 (保留重力，在空中会自然落地)
		linear_damp = 20.0
		linear_velocity = Vector2.ZERO
		# 切到 idle 状态
		if current_state_name != "idle":
			transition_to("idle")
		# 生成踏板，缓缓升起
		_spawn_gaming_platform()
	else:
		eye_behavior.forced_look_dir = Vector2.ZERO
		# 清除踏板
		_remove_gaming_platform()
		# 切到 fall 状态自然过渡 (fall.enter 会恢复阻尼)
		transition_to("fall")
	queue_redraw()

## 游戏态踏板: 在宠物脚下生成踏板，缓缓升起把宠物托到空中
func _spawn_gaming_platform() -> void:
	var parent = get_parent()
	if not parent:
		return
	# 踏板位置 = 宠物脚下
	var plat_y = global_position.y + PET_RADIUS * gravity_sign
	var body = StaticBody2D.new()
	body.position = Vector2(global_position.x, plat_y)
	# 碰撞体 (单向踏板)
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(PET_RADIUS * 2.0, 8.0)
	col.shape = shape
	col.one_way_collision = true
	if anti_gravity:
		col.rotation = PI
	body.add_child(col)
	# 视觉效果 (复用 FreeRoamSystem 的 PlatformVisual)
	var visual = FreeRoamSystem.PlatformVisual.new()
	visual.platform_width = PET_RADIUS * 2.0
	visual.platform_color = palette.shift_color(Color(0.2, 0.6, 1.0, 0.6))
	body.add_child(visual)
	parent.add_child(body)
	# 淡入
	body.modulate.a = 0.0
	var tween = body.create_tween()
	tween.tween_property(body, "modulate:a", 1.0, 0.3)
	_gaming_platform = body
	# 目标高度: 上升约 15px
	_gaming_lift_target_y = plat_y - 15.0 * gravity_sign
	_gaming_lift_phase = 1
	# 关闭重力，让踏板完全控制宠物高度
	gravity_scale = 0.0

func _remove_gaming_platform() -> void:
	_gaming_lift_phase = 0
	gravity_scale = gravity_sign  # 恢复重力
	if is_instance_valid(_gaming_platform):
		# 立即禁用碰撞体，让宠物能马上下落
		for child in _gaming_platform.get_children():
			if child is CollisionShape2D:
				child.disabled = true
		# 淡出 + 移除
		var plat = _gaming_platform
		_gaming_platform = null
		var tween = plat.create_tween()
		tween.tween_property(plat, "modulate:a", 0.0, 0.3)
		tween.finished.connect(func():
			if is_instance_valid(plat):
				plat.queue_free()
		)

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
	# 游戏中: 只允许 idle 和 fall (落地), 阻止 walk/jump 等
	if _gaming and state_name not in ["idle", "fall"]:
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

## 屏幕穿越: 传送 + 幽灵偏移计算
func _update_screen_wrap() -> void:
	var w = boundary_size.x
	var margin = PET_RADIUS * 2.0
	var x = global_position.x
	
	# 传送: 完全超出后坐标翻转 + 同步拖影历史
	if x > w + PET_RADIUS:
		global_position.x -= w
		for i in range(pet_effects.trail_history.size()):
			pet_effects.trail_history[i].x -= w
	elif x < -PET_RADIUS:
		global_position.x += w
		for i in range(pet_effects.trail_history.size()):
			pet_effects.trail_history[i].x += w
	
	# 幽灵偏移: 靠近边界时在对侧渲染副本
	x = global_position.x  # 传送后的新位置
	_wrap_ghost_offset = Vector2.ZERO
	if x > w - margin:
		_wrap_ghost_offset = Vector2(-w, 0)
	elif x < margin:
		_wrap_ghost_offset = Vector2(w, 0)

# ── 自由移动 (委托 FreeRoamSystem) ──
var free_roam_sys: FreeRoamSystem

## 向后兼容: idle.gd / drag.gd 通过 _roam_active 访问状态
var _roam_active: bool:
	get: return free_roam_sys.active if free_roam_sys else false

func _on_trigger_free_roam() -> void:
	if is_clone or _roam_active:
		return
	_start_free_roam()

func _start_free_roam() -> void:
	free_roam_sys.start()

func _roam_update(delta: float) -> void:
	free_roam_sys.update(delta)

func _roam_finish() -> void:
	free_roam_sys.finish()



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

	# 游戏状态: 每帧强制瞳孔盯全息屏 + 锁定位置 + 驱动踏板上升
	if _gaming:
		eye_behavior.forced_look_dir = Vector2(_gaming_holo_side, 0.15)
		linear_velocity = Vector2.ZERO
		# 踏板上升驱动
		if _gaming_lift_phase == 1 and is_instance_valid(_gaming_platform):
			var lift_speed = 80.0
			_gaming_platform.position.y -= lift_speed * delta * gravity_sign
			# 宠物跟随踏板
			global_position.y = _gaming_platform.position.y - PET_RADIUS * gravity_sign
			# 检测抵达目标高度
			var dist = (_gaming_platform.position.y - _gaming_lift_target_y) * gravity_sign
			if dist <= 0.0:
				_gaming_platform.position.y = _gaming_lift_target_y
				global_position.y = _gaming_lift_target_y - PET_RADIUS * gravity_sign
				_gaming_lift_phase = 2
		elif _gaming_lift_phase == 2 and is_instance_valid(_gaming_platform):
			# 已到位: 持续锁定宠物在踏板上
			global_position.y = _gaming_platform.position.y - PET_RADIUS * gravity_sign
		# 落地后锁 idle
		if current_state_name != "idle" and is_settled():
			transition_to("idle")

	var has_visual_change = pet_effects.update(delta)
	idle_behaviors.update(delta)
	_roam_update(delta)
	var squash_changed = squash.update(delta)
	
	# 屏幕穿越: 传送 + 幽灵偏移计算
	if screen_wrap and not freeze:
		_update_screen_wrap()
	elif freeze and _wrap_ghost_offset != Vector2.ZERO:
		_wrap_ghost_offset = Vector2.ZERO
	
	# 按需重绘
	if has_visual_change or linear_velocity.length() > 1.0 or eye_behavior.is_animating() or squash_changed or _wrap_ghost_offset != Vector2.ZERO or _gaming:
		queue_redraw()

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_process(delta)
	
	# 记录本帧物理速度，如果下帧发生撞击，就是参考依据
	last_frame_speed = linear_velocity.length()
	last_frame_velocity = linear_velocity

func _on_body_entered(_body: Node) -> void:
	# 弹性形变: 拖拽中不触发 (沿地面拖拽会频繁接触/脱离地面)
	if squash.enabled and current_state_name != "drag":
		squash.apply_impact(last_frame_velocity, last_frame_speed)
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

# ── 游戏全息屏渲染 ──

func _draw_gaming_hologram() -> void:
	var hue = EventBus.ui_hue
	# 在世界坐标系中绘制 (反旋转刚体旋转)
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)

	var side = _gaming_holo_side
	var gap = PET_RADIUS + 5.0

	# 获取 SubViewport 纹理，按比例计算全息屏尺寸
	var viewport_tex: Texture2D = null
	if _gaming_game and _gaming_game.game_viewport:
		viewport_tex = _gaming_game.game_viewport.get_texture()
	var holo_w: float
	var holo_h: float
	if viewport_tex and viewport_tex.get_size().y > 0:
		var tex_size = viewport_tex.get_size()
		# 首次获取时记录宽高比，后续固定 (防止面板大小变化导致跳变)
		if _gaming_holo_aspect <= 0.0:
			_gaming_holo_aspect = tex_size.x / tex_size.y
		holo_h = PET_RADIUS * 2.5
		holo_w = holo_h * _gaming_holo_aspect
	else:
		holo_w = PET_RADIUS * 1.6
		holo_h = PET_RADIUS * 1.6

	# 全息屏中心
	var cx = side * (gap + holo_w * 0.5)
	var cy = 0.0  # 垂直居中于宠物中心

	# 投影支架线
	var near_edge_x = cx - side * holo_w * 0.5  # 靠近宠物的边
	var beam_start = Vector2(side * PET_RADIUS * 0.6, 0)
	var beam_end = Vector2(near_edge_x, cy)
	draw_line(beam_start, beam_end, Color.from_hsv(hue, 0.3, 0.8, 0.2), 0.8, true)
	draw_circle(beam_start, 1.5, Color.from_hsv(hue, 0.4, 1.0, 0.4), true, -1.0, true)

	# 梯形透视: 靠近宠物的边上下收缩，远离的边保持原高
	# 模拟"侧面看投影屏幕"的真实感
	var half_w = holo_w / 2.0
	var half_h = holo_h / 2.0
	var shrink = 0.15  # 近端收缩比例 (15%)
	var near_half_h = half_h * (1.0 - shrink)  # 近端半高 (较短)
	var far_half_h = half_h                     # 远端半高 (原高)

	# 梯形 4 个顶点 (左上→右上→右下→左下)
	var pts: PackedVector2Array
	if side > 0:  # 全息屏在右侧: 左边(近端)窄，右边(远端)宽
		pts = PackedVector2Array([
			Vector2(cx - half_w, cy - near_half_h),  # 左上 (近)
			Vector2(cx + half_w, cy - far_half_h),   # 右上 (远)
			Vector2(cx + half_w, cy + far_half_h),   # 右下 (远)
			Vector2(cx - half_w, cy + near_half_h),  # 左下 (近)
		])
	else:  # 全息屏在左侧: 右边(近端)窄，左边(远端)宽
		pts = PackedVector2Array([
			Vector2(cx - half_w, cy - far_half_h),   # 左上 (远)
			Vector2(cx + half_w, cy - near_half_h),  # 右上 (近)
			Vector2(cx + half_w, cy + near_half_h),  # 右下 (近)
			Vector2(cx - half_w, cy + far_half_h),   # 左下 (远)
		])
	var uvs = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	])

	# 外框光晕 (梯形轮廓)
	var glow_pts = pts.duplicate()
	glow_pts.append(pts[0])  # 闭合
	draw_polyline(glow_pts, Color.from_hsv(hue, 0.3, 0.8, 0.1), 2.0, true)
	draw_polyline(glow_pts, Color.from_hsv(hue, 0.4, 0.9, 0.35), 0.6, true)

	# SubViewport 纹理映射到梯形 (自动镜像任何游戏面板)
	if viewport_tex:
		draw_polygon(pts, [Color(1, 1, 1, 0.75)], uvs, viewport_tex)

	# 恢复变换
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# ── 视觉系统 ──

func _draw() -> void:
	# ── 绘制特效 (冲击波 + 拖影，委托给 PetEffects) ──
	pet_effects.render(self)
	if _wrap_ghost_offset != Vector2.ZERO:
		# 对侧幽灵特效: 偏移后再画一次
		draw_set_transform(_wrap_ghost_offset.rotated(-rotation), 0, Vector2.ONE)
		pet_effects.render(self)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# ── 绘制静电弧 (近距离宠物间的放电弧，需在世界空间绘制) ──
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	pet_effects.render_arcs(self)
	if _wrap_ghost_offset != Vector2.ZERO:
		# 幽灵位置的弧线: 补上被窗口裁剪的另一半
		draw_set_transform(_wrap_ghost_offset.rotated(-rotation), -rotation, Vector2.ONE)
		pet_effects.render_arcs(self)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	
	# ── 宠物本体 (可能画两次: 正常 + 屏幕穿越幽灵) ──
	_draw_body(Vector2.ZERO)
	if _wrap_ghost_offset != Vector2.ZERO:
		_draw_body(_wrap_ghost_offset)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# ── 游戏全息迷你屏 (SubViewport 纹理自动镜像) ──
	if _gaming and _gaming_game:
		_draw_gaming_hologram()
	
## 绘制宠物本体 (外壳+眼球+覆盖层), world_offset 用于屏幕穿越双重渲染
func _draw_body(world_offset: Vector2) -> void:
	var local_off = world_offset.rotated(-rotation)  # 世界偏移→绘图空间本地偏移
	var sq = squash.get_scale()
	
	# 身体 transform + offset
	var body_xform = Transform2D.IDENTITY
	body_xform = body_xform.rotated_local(rotation)
	body_xform = body_xform.scaled(sq)
	body_xform = body_xform.rotated(-rotation)
	body_xform.origin += local_off
	draw_set_transform_matrix(body_xform)
	
	# ── 科幻单眼结构 ──
	var shell_outline := palette.shift_color(Color(0.08, 0.12, 0.32, 1.0))
	var shell_main := palette.shift_color(Color(0.15, 0.30, 0.80, 1.0))
	draw_circle(Vector2.ZERO, PET_RADIUS + 1.2, shell_outline, true, -1.0, true)
	draw_circle(Vector2.ZERO, PET_RADIUS, shell_main, true, -1.0, true)
	var border_radius = PET_RADIUS * 0.85
	draw_arc(Vector2.ZERO, border_radius, 0, TAU, 64, Color(1.0, 1.0, 1.0, 0.8), 1.2, true)
	var dark_blue := palette.shift_color(Color(0.12, 0.18, 0.42, 1.0))
	var base_r = PET_RADIUS * 0.68
	var tip_dist = border_radius - 1.0
	draw_circle(Vector2.ZERO, base_r, dark_blue, true, -1.0, true)
	for i in range(4):
		var angle = i * PI / 2.0 + PI / 4.0
		var tip_pos = Vector2(cos(angle), sin(angle)) * tip_dist
		var half_hw = PI / 10.0
		var left_base = Vector2(cos(angle - half_hw), sin(angle - half_hw)) * (base_r * 0.95)
		var right_base = Vector2(cos(angle + half_hw), sin(angle + half_hw)) * (base_r * 0.95)
		draw_polygon(PackedVector2Array([left_base, tip_pos, right_base]), PackedColorArray([dark_blue, dark_blue, dark_blue]))
	
	# 眼球 transform + offset
	var eye_xform = Transform2D.IDENTITY
	eye_xform = eye_xform.scaled(sq)
	eye_xform = eye_xform.rotated(-rotation)
	eye_xform.origin += local_off
	draw_set_transform_matrix(eye_xform)
	var blink = eye_behavior.get_blink_amount()
	var iris_scale = 1.0 - blink * 0.95
	if iris_scale > 0.05:
		var iris_offset = eye_behavior.get_pupil_offset() * iris_scale
		draw_circle(Vector2.ZERO, PET_RADIUS * 0.54 * iris_scale, palette.shift_color(Color(0.85, 0.88, 0.92, 1.0)), true, -1.0, true)
		draw_circle(iris_offset, PET_RADIUS * 0.42 * iris_scale, palette.shift_color(Color(0.55, 0.65, 0.80, 1.0)), true, -1.0, true)
		draw_circle(iris_offset, PET_RADIUS * 0.28 * iris_scale, palette.shift_color(Color(0.15, 0.28, 0.68, 1.0)), true, -1.0, true)
		draw_circle(iris_offset, PET_RADIUS * 0.16 * iris_scale, palette.shift_color(Color(0.05, 0.08, 0.20, 1.0)), true, -1.0, true)
		var highlight_offset = iris_offset + Vector2(-PET_RADIUS * 0.08, -PET_RADIUS * 0.10) * iris_scale
		var highlight_fade = 1.0 - eye_behavior.get_drowsy_amount()
		draw_circle(highlight_offset, PET_RADIUS * 0.11 * iris_scale, Color(1.0, 1.0, 1.0, iris_scale * 0.85 * highlight_fade), true, -1.0, true)
		draw_circle(highlight_offset, PET_RADIUS * 0.06 * iris_scale, Color(1.0, 1.0, 1.0, iris_scale * highlight_fade), true, -1.0, true)
	var h_blend = idle_behaviors.get_hibernate_visual_blend()
	if h_blend > 0.01:
		var screen_r = PET_RADIUS * 0.83
		draw_circle(Vector2.ZERO, screen_r, Color(0.03, 0.05, 0.12, h_blend * 0.95), true, -1.0, true)
		match idle_behaviors.hibernate_style:
			1: _draw_loading_spinner(screen_r, h_blend, idle_behaviors._hibernate_anim_time)
			2: _draw_battery_icon(screen_r, h_blend, idle_behaviors._hibernate_anim_time)
	var scan_blend = eye_behavior.scanning_blend
	var done_blend = eye_behavior.scanning_done_blend
	if scan_blend > 0.01 or done_blend > 0.01:
		var scan_r = PET_RADIUS * 0.83
		var overlay_alpha = scan_blend * 0.95
		if done_blend > scan_blend:
			overlay_alpha = done_blend * 0.95
		draw_circle(Vector2.ZERO, scan_r, Color(0.03, 0.05, 0.12, overlay_alpha), true, -1.0, true)
		var spinner_alpha = scan_blend * (1.0 - done_blend)
		if spinner_alpha > 0.01:
			_draw_loading_spinner(scan_r, spinner_alpha, eye_behavior.scanning_time)
		if done_blend > 0.01:
			_draw_scanning_checkmark(scan_r, done_blend)
	var icon_blend = eye_behavior.eye_icon_blend
	if icon_blend > 0.01:
		var icon_r = PET_RADIUS * 0.83
		draw_circle(Vector2.ZERO, icon_r, Color(0.03, 0.05, 0.12, icon_blend * 0.95), true, -1.0, true)
		match eye_behavior.eye_icon_type:
			"mail": _draw_eye_icon_mail(icon_r, icon_blend, eye_behavior.eye_icon_time)
			"alert": _draw_eye_icon_alert(icon_r, icon_blend, eye_behavior.eye_icon_time)
			"question": _draw_eye_icon_question(icon_r, icon_blend, eye_behavior.eye_icon_time)
			"error": _draw_eye_icon_error(icon_r, icon_blend, eye_behavior.eye_icon_time)
	var drowsy = eye_behavior.get_drowsy_amount()
	var is_shutter = idle_behaviors.active_behavior != "hibernate" or idle_behaviors.hibernate_style == 0
	if drowsy > 0.01 and iris_scale > 0.05 and is_shutter:
		var sclera_r = PET_RADIUS * 0.54 * iris_scale
		var plate_color = palette.shift_color(Color(0.10, 0.15, 0.38, 1.0))
		# 正常: 挡板从屏幕顶部向下合拢 (自然闭眼)
		# 反重力: 挡板从屏幕底部向上合拢 (宠物"站在天花板上"闭眼, 而非悬挂耷拉)
		_draw_eye_shutter(sclera_r, sclera_r * drowsy * 1.5, not anti_gravity, plate_color)

func _on_trigger_squash_test(squash_style: int) -> void:
	if squash_style < 0:
		squash.enabled = false
	else:
		squash.style = squash_style
		squash.enabled = true

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
		# 下半圆: 从 angle_l 经过 PI/2 (Godot Y轴向下=下方) 到 angle_r
		# span 必须为负值: 递减方向经过 PI/2, 覆盖下半圆
		# (close_px > radius 时 flat_y 变负, span 会翻正, 需修正回负值)
		var span = angle_r - angle_l
		if span > 0:
			span -= TAU
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

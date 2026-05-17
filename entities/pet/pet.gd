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

## 视觉旋转角度 (物理旋转 + 反重力翻转)
## 渲染宠物/全息屏等需跟随翻转的内容时，用这个替代 rotation
var visual_rotation: float:
	get: return rotation + (PI if anti_gravity else 0.0)

## 反重力方向转换因子 (正常=1.0, 反重力=-1.0)
## 将世界空间方向转为视觉空间方向时，乘以此因子
var ag_flip: float:
	get: return -1.0 if anti_gravity else 1.0
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
var overlay_rects: Dictionary = {} # 外部覆盖层的屏幕区域 (多面板独立注册, key→Rect2)

## 注册/更新一个覆盖层命中区域 (面板 _process 中每帧调用)
func set_overlay_rect(key: String, rect: Rect2) -> void:
	overlay_rects[key] = rect

## 移除一个覆盖层命中区域 (面板关闭时调用)
func remove_overlay_rect(key: String) -> void:
	overlay_rects.erase(key)

## 获取所有活跃的覆盖层矩形
func get_all_overlay_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for r in overlay_rects.values():
		if r is Rect2 and r.size != Vector2.ZERO:
			result.append(r)
	return result



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

# ── 移动方向控制器 (委托给 PetMovement) ──
var movement: PetMovement

## 统一判断: 宠物是否应处于安静排队行为 (手动安静待命 OR 深夜模式)
func is_quiet_behavior() -> bool:
	return behavior_mode == 1 or nighttime_mode

# ── 戳一戳交互系统 (委托给 PokeSystem) ──
var poke_system: PokeSystem

# ── Idle 微行为系统 (委托给 IdleBehaviors) ──
var idle_behaviors: IdleBehaviors

# ── 自主活动调度器 (委托给 IdleActivities) ──
var idle_activities: IdleActivities

# ── 弹性形变系统 (委托给 PetSquash) ──
var squash: PetSquash

# ── 游戏态管理器 (委托给 PetGaming) ──
var gaming: PetGaming

# ── 全息屏控制器 (委托给 PetHoloScreen) ──
var holo_screen: PetHoloScreen

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
	
	# 初始化全息屏控制器 (必须在游戏态管理器之前)
	holo_screen = PetHoloScreen.new()
	holo_screen.pet = self
	
	# 初始化游戏态管理器 (必须在状态机之前，transition_to() 会访问 gaming.active)
	gaming = PetGaming.new()
	gaming.pet = self
	
	# 初始化移动方向控制器 (必须在状态机之前，enter() 会访问 movement)
	movement = PetMovement.new()
	movement.pet = self
	
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
	
	# 初始化自主活动调度器
	idle_activities = IdleActivities.new()
	idle_activities.pet = self
	
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
	idle_activities.mode = SettingsManager.get_int("auto_activity", 1)
	# 弹性形变恢复 (elastic_mode: 0=关闭, 1=轻弹, 2=果冻, 3=弹力球)
	var elastic_mode = SettingsManager.get_int("elastic_mode", 0)
	if elastic_mode > 0:
		squash.enabled = true
		squash.style = clampi(elastic_mode - 1, 0, 2)
	# HUD 组件状态恢复 (仅原体)
	if not is_clone:
		var hud_clock = SettingsManager.get_bool("hud_clock", false)
		var hud_wifi = SettingsManager.get_bool("hud_wifi", false)
		var hud_todo = SettingsManager.get_bool("hud_todo", false)
		var hud_pin_val = SettingsManager.get_bool("hud_pin", false)
		hud_panel.set_pin(hud_pin_val)
		if hud_clock:
			hud_panel.set_clock(true)
		if hud_wifi:
			hud_panel.set_wifi(true)
		if hud_todo:
			hud_panel.set_todo(true)
	
	# 监听运行时设置变更
	EventBus.setting_toggled.connect(_on_setting_toggled)
	EventBus.behavior_mode_changed.connect(_on_behavior_mode_changed)
	EventBus.pet_color_changed.connect(_on_pet_color_changed)
	EventBus.trigger_idle_behavior.connect(_on_trigger_idle_behavior)
	EventBus.trigger_free_roam.connect(_on_trigger_free_roam)
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
	elif setting_id == "auto_activity":
		idle_activities.mode = SettingsManager.get_int("auto_activity", 1)
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
	elif setting_id == "hud_todo":
		if is_clone:
			return
		hud_panel.set_todo(is_on)

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

func _on_pet_color_changed(pet_index: int, hue: float, sat: float, val: float) -> void:
	var my_index = get_meta("pet_index", 0)
	if pet_index != my_index:
		return
	palette.set_hue(hue)
	palette.sat_scale = sat
	palette.val_scale = val
	queue_redraw()

func _on_pet_gaming_changed(active: bool, game_ref: RefCounted) -> void:
	gaming.on_gaming_changed(active, game_ref)

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
	if gaming.active and state_name not in ["idle", "fall"]:
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


# ── UI 锚点 (反重力自适应) ──

## 获取宠物 UI 定位锚点 (统一处理反重力方向)
## 返回字典:
##   center: Vector2  — 宠物屏幕中心
##   head_dir: float   — 头顶方向 (-1=头朝上/正常, +1=头朝下/反重力)
##   head_y: float     — 头顶边缘 Y (放气泡/按钮的起点)
##   foot_y: float     — 脚底边缘 Y
func get_ui_anchor() -> Dictionary:
	var screen_pos = get_global_transform_with_canvas().get_origin()
	if anti_gravity:
		return {
			"center": screen_pos,
			"head_dir": 1.0,
			"head_y": screen_pos.y + PET_RADIUS,
			"foot_y": screen_pos.y - PET_RADIUS,
		}
	else:
		return {
			"center": screen_pos,
			"head_dir": -1.0,
			"head_y": screen_pos.y - PET_RADIUS,
			"foot_y": screen_pos.y + PET_RADIUS,
		}


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
	# HUD 面板: 悬浮模式下转发鼠标状态 (游戏态不响应 hover)
	if not is_clone:
		hud_panel.set_hover(false if gaming.active else is_mouse_on_pet())
	hud_panel.update(delta)
	eye_behavior.update(delta)

	# 游戏态: 瞳孔锁定 + 位置锁定 + 踏板升降 (委托给 PetGaming)
	gaming.update(delta)
	# 全息屏: 展开/收起动画 + 屏保动画 (委托给 PetHoloScreen)
	holo_screen.update(delta)
	# 移动方向控制器: 缓冲/保持计时 (在方向决议之前)
	movement.update(delta)
	
	# ── 瞳孔方向优先级决议 (唯一写入 forced_look_dir 的地方) ──
	# ag_flip 转换全息屏的逻辑位置为视觉位置
	var visual_side = holo_screen.side * ag_flip
	if gaming.active:
		eye_behavior.forced_look_dir = Vector2(visual_side, 0.15)
	elif holo_screen.visible and holo_screen.is_terminal_mode:
		eye_behavior.forced_look_dir = Vector2(visual_side, 0.15)
	elif holo_screen.visible and holo_screen._game_locked:
		eye_behavior.forced_look_dir = Vector2(visual_side, 0.15)
	elif movement.is_active:
		eye_behavior.forced_look_dir = movement.direction
	else:
		eye_behavior.forced_look_dir = Vector2.ZERO
	
	var has_visual_change = pet_effects.update(delta)
	idle_behaviors.update(delta)
	idle_activities.update(delta)
	_roam_update(delta)
	var squash_changed = squash.update(delta)
	
	# 屏幕穿越: 传送 + 幽灵偏移计算
	if screen_wrap and not freeze:
		_update_screen_wrap()
	elif freeze and _wrap_ghost_offset != Vector2.ZERO:
		_wrap_ghost_offset = Vector2.ZERO
	
	# 按需重绘
	if has_visual_change or linear_velocity.length() > 1.0 or eye_behavior.is_animating() or squash_changed or _wrap_ghost_offset != Vector2.ZERO or holo_screen.visible:
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
		# 右键呼出全局追踪菜单 (HUD) — 仅原体响应, 游戏态屏蔽
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not is_clone and is_mouse_on_pet() and not gaming.active:
				get_viewport().set_input_as_handled()
				EventBus.show_context_menu.emit(self)

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
	
	# ── 全息迷你屏 (先画, 让宠物本体覆盖近端, 营造 3D 前景效果) ──
	if holo_screen.visible:
		holo_screen.render()

	# ── 宠物本体 (可能画两次: 正常 + 屏幕穿越幽灵) ──
	_draw_body(Vector2.ZERO)
	if _wrap_ghost_offset != Vector2.ZERO:
		_draw_body(_wrap_ghost_offset)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	
## 绘制宠物本体 (外壳+眼球+覆盖层), world_offset 用于屏幕穿越双重渲染
func _draw_body(world_offset: Vector2) -> void:
	var local_off = world_offset.rotated(-rotation)  # 世界偏移→绘图空间本地偏移
	var squash_xform = squash.get_deformation_matrix()
	
	# 构建逆向与正向旋转，确保形变在世界坐标系方向生效，却在节点局部绘制空间进行
	# visual_rotation 已包含反重力翻转，无需额外处理
	var r_mat = Transform2D(visual_rotation, Vector2.ZERO)
	var r_inv = Transform2D(-visual_rotation, Vector2.ZERO)
	var base_xform = r_inv * squash_xform * r_mat
	
	base_xform.origin += local_off
	draw_set_transform_matrix(base_xform)
	
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
	var eye_xform = r_inv * squash_xform
	eye_xform.origin += local_off
	draw_set_transform_matrix(eye_xform)
	var blink = eye_behavior.get_blink_amount()
	var iris_scale = 1.0 - blink * 0.95
	if iris_scale > 0.05:
		var iris_offset = eye_behavior.get_pupil_offset() * iris_scale * ag_flip
		draw_circle(Vector2.ZERO, PET_RADIUS * 0.54 * iris_scale, palette.shift_color(Color(0.85, 0.88, 0.92, 1.0)), true, -1.0, true)
		draw_circle(iris_offset, PET_RADIUS * 0.42 * iris_scale, palette.shift_color(Color(0.55, 0.65, 0.80, 1.0)), true, -1.0, true)
		draw_circle(iris_offset, PET_RADIUS * 0.28 * iris_scale, palette.shift_color(Color(0.15, 0.28, 0.68, 1.0)), true, -1.0, true)
		draw_circle(iris_offset, PET_RADIUS * 0.16 * iris_scale, palette.shift_color(Color(0.05, 0.08, 0.20, 1.0)), true, -1.0, true)
		var highlight_offset = iris_offset + Vector2(-PET_RADIUS * 0.08, -PET_RADIUS * 0.10) * iris_scale * ag_flip
		var highlight_fade = 1.0 - eye_behavior.get_drowsy_amount()
		draw_circle(highlight_offset, PET_RADIUS * 0.11 * iris_scale, Color(1.0, 1.0, 1.0, iris_scale * 0.85 * highlight_fade), true, -1.0, true)
		draw_circle(highlight_offset, PET_RADIUS * 0.06 * iris_scale, Color(1.0, 1.0, 1.0, iris_scale * highlight_fade), true, -1.0, true)
	var h_blend = idle_behaviors.get_hibernate_visual_blend()
	if h_blend > 0.01:
		var screen_r = PET_RADIUS * 0.83
		draw_circle(Vector2.ZERO, screen_r, Color(0.03, 0.05, 0.12, h_blend * 0.95), true, -1.0, true)
		match idle_behaviors.hibernate_style:
			1: _draw_loading_spinner(screen_r, h_blend, idle_behaviors._hibernate_anim_time)
	var drowsy = eye_behavior.get_drowsy_amount()
	var is_shutter = idle_behaviors.active_behavior != "hibernate" or idle_behaviors.hibernate_style == 0
	if drowsy > 0.01 and iris_scale > 0.05 and is_shutter:
		var sclera_r = PET_RADIUS * 0.54 * iris_scale
		var plate_color = palette.shift_color(Color(0.10, 0.15, 0.38, 1.0))
		# 挡板从眼球顶部向下合拢 (反重力时整个眼球已翻转 180°，自动变为从底部向上)
		_draw_eye_shutter(sclera_r, sclera_r * drowsy * 1.5, true, plate_color)

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

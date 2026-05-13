# pet_gaming.gd — 宠物游戏态管理器 (RefCounted)
# 管理游戏态行为: 锁定宠物、踏板升降、瞳孔跟踪
# 全息屏渲染已委托给 PetHoloScreen
# 从 pet.gd 抽离，与 PetEffects / EyeBehavior / IdleBehaviors 等子系统同级
class_name PetGaming
extends RefCounted

var pet: RigidBody2D  # 由 pet.gd 注入

# ── 游戏态状态 ──
var active: bool = false
var game: RefCounted = null  # 当前游戏引用 (BaseGame)

# ── 悬浮踏板 ──
var _platform: StaticBody2D = null  # 游戏态悬浮踏板
var _lift_phase: int = 0     # 0=空闲, 1=上升中, 2=已到位
var _lift_target_y: float = 0.0  # 踏板目标高度

# ── 接口 ──

## 游戏启停信号处理
func on_gaming_changed(is_active: bool, game_ref: RefCounted) -> void:
	if pet.is_clone:
		return
	active = is_active
	game = game_ref
	if is_active:
		# 取消正在进行的空间跳跃 (清理踏板+状态)
		if pet.free_roam_sys.active:
			pet.free_roam_sys.finish()
		# 决定全息屏在宠物哪边并激活
		var screen_side: float
		if pet.global_position.x > pet.boundary_size.x * 0.5:
			screen_side = -1.0
		else:
			screen_side = 1.0
		pet.holo_screen.show_game(game.get_holo_texture, screen_side)
		# 高阻尼停下来 (保留重力，在空中会自然落地)
		pet.linear_damp = 20.0
		pet.linear_velocity = Vector2.ZERO
		# 切到 idle 状态
		if pet.current_state_name != "idle":
			pet.transition_to("idle")
		# 生成踏板，缓缓升起
		_spawn_platform()
	else:
		pet.movement.cancel()  # 清除移动方向 (瞳孔由决议层管理)
		# 隐藏全息屏
		pet.holo_screen.hide()
		# 清除踏板
		_remove_platform()
		# 设置空间跳跃冷却 (退出游戏后 60 秒内不触发 roam)
		pet.set_meta("_roam_cooldown", Time.get_ticks_msec())
		# 切到 fall 状态自然过渡 (fall.enter 会恢复阻尼)
		pet.transition_to("fall")
	pet.queue_redraw()

## 每帧更新: 瞳孔追踪 + 位置锁定 + 踏板升降驱动
func update(delta: float) -> void:
	if not active:
		return
	# 瞳孔方向由 pet.gd 决议层统一处理 (gaming.active 最高优先级)
	pet.linear_velocity = Vector2.ZERO
	# 踏板上升驱动
	if _lift_phase == 1 and is_instance_valid(_platform):
		var lift_speed = 80.0
		_platform.position.y -= lift_speed * delta * pet.gravity_sign
		# 宠物跟随踏板
		pet.global_position.y = _platform.position.y - pet.PET_RADIUS * pet.gravity_sign
		# 检测抵达目标高度
		var dist = (_platform.position.y - _lift_target_y) * pet.gravity_sign
		if dist <= 0.0:
			_platform.position.y = _lift_target_y
			pet.global_position.y = _lift_target_y - pet.PET_RADIUS * pet.gravity_sign
			_lift_phase = 2
	elif _lift_phase == 2 and is_instance_valid(_platform):
		# 已到位: 持续锁定宠物在踏板上
		pet.global_position.y = _platform.position.y - pet.PET_RADIUS * pet.gravity_sign
	# 落地后锁 idle
	if pet.current_state_name != "idle" and pet.is_settled():
		pet.transition_to("idle")

## 返回全息迷你屏在屏幕上的包围矩形 (供游戏面板定位时避让)
## 委托给 PetHoloScreen
func get_holo_screen_rect() -> Rect2:
	return pet.holo_screen.get_screen_rect()

# ── 踏板管理 (私有) ──

## 在宠物脚下生成踏板，缓缓升起把宠物托到空中
func _spawn_platform() -> void:
	var parent = pet.get_parent()
	if not parent:
		return
	# 踏板位置 = 宠物脚下
	var plat_y = pet.global_position.y + pet.PET_RADIUS * pet.gravity_sign
	var body = StaticBody2D.new()
	body.position = Vector2(pet.global_position.x, plat_y)
	# 碰撞体 (单向踏板)
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(pet.PET_RADIUS * 2.0, 8.0)
	col.shape = shape
	col.one_way_collision = true
	if pet.anti_gravity:
		col.rotation = PI
	body.add_child(col)
	# 视觉效果 (极简模式: 无闪光/粒子)
	var visual = FreeRoamSystem.PlatformVisual.new()
	visual.platform_width = pet.PET_RADIUS * 2.0
	visual.platform_color = pet.palette.shift_color(Color(0.2, 0.6, 1.0, 0.6))
	visual.quiet = true
	body.add_child(visual)
	parent.add_child(body)
	# 淡入
	body.modulate.a = 0.0
	var tween = body.create_tween()
	tween.tween_property(body, "modulate:a", 1.0, 0.3)
	_platform = body
	# 目标高度: 上升约 15px
	_lift_target_y = plat_y - 15.0 * pet.gravity_sign
	_lift_phase = 1
	# 关闭重力，让踏板完全控制宠物高度
	pet.gravity_scale = 0.0

func _remove_platform() -> void:
	_lift_phase = 0
	pet.gravity_scale = pet.gravity_sign  # 恢复重力
	if is_instance_valid(_platform):
		# 立即禁用碰撞体，让宠物能马上下落
		for child in _platform.get_children():
			if child is CollisionShape2D:
				child.disabled = true
		# 淡出 + 移除
		var plat = _platform
		_platform = null
		var tween = plat.create_tween()
		tween.tween_property(plat, "modulate:a", 0.0, 0.3)
		tween.finished.connect(func():
			if is_instance_valid(plat):
				plat.queue_free()
		)

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

# ── 悬浮踏板 (委托 PetPlatform) ──
var _plat := PetPlatform.new()

# ── 接口 ──

## 游戏启停信号处理
func on_gaming_changed(is_active: bool, game_ref: RefCounted) -> void:
	if pet.is_clone:
		return
	active = is_active
	game = game_ref
	if is_active:
		# 决定全息屏在宠物哪边并激活
		var screen_side: float
		if pet.global_position.x > pet.boundary_size.x * 0.5:
			screen_side = -1.0
		else:
			screen_side = 1.0
		pet.holo_screen.show_game(game.get_holo_texture, screen_side)
		# 锁定宠物 + 生成踏板 (取消 roam + 高阻尼 + idle + 踏板升起)
		_plat.lock_pet(pet)
	else:
		pet.movement.cancel()  # 清除移动方向 (瞳孔由决议层管理)
		# 隐藏全息屏
		pet.holo_screen.hide()
		# 清除踏板
		_plat.remove(pet)
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
	# 踏板升降驱动 + 位置锁定
	_plat.update(pet, delta)
	# 落地后锁 idle
	if pet.current_state_name != "idle" and pet.is_settled():
		pet.transition_to("idle")

## 返回全息迷你屏在屏幕上的包围矩形 (供游戏面板定位时避让)
## 委托给 PetHoloScreen
func get_holo_screen_rect() -> Rect2:
	return pet.holo_screen.get_screen_rect()

# pet_gaming.gd — 宠物游戏态管理器 (RefCounted)
# 管理游戏态行为: 锁定宠物、踏板升降、瞳孔跟踪、关闭按钮
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

# ── 关闭按钮 ──
var _close_btn: Button = null
var _close_btn_visible: bool = false
const _DEFAULT_TEXT := "自娱模式"
const _HOVER_TEXT := "中断游戏"

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
		# 创建头顶关闭按钮
		_create_close_btn()
	else:
		# 移除关闭按钮
		_remove_close_btn()
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

## 每帧更新: 瞳孔追踪 + 位置锁定 + 踏板升降驱动 + 关闭按钮
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
	# 关闭按钮: 悬停检测 + 位置跟随
	_update_close_btn_hover()
	_update_close_btn_position()

## 返回全息迷你屏在屏幕上的包围矩形 (供游戏面板定位时避让)
## 委托给 PetHoloScreen
func get_holo_screen_rect() -> Rect2:
	return pet.holo_screen.get_screen_rect()

## 返回关闭按钮的屏幕矩形 (供 hit_region_manager 注册可点击区域)
func get_close_btn_rect() -> Rect2:
	if not is_instance_valid(_close_btn) or _close_btn.modulate.a < 0.1:
		return Rect2()
	return _close_btn.get_global_rect()

# ══════════════════════════════════════
# 关闭按钮 (游戏态, 风格与终端模式一致)
# ══════════════════════════════════════

func _create_close_btn() -> void:
	_remove_close_btn()
	var parent = pet.get_parent()
	if not parent:
		return
	var hue = EventBus.ui_hue
	_close_btn = Button.new()
	_close_btn.text = _DEFAULT_TEXT
	_close_btn.custom_minimum_size = Vector2(80, 28)
	_close_btn.add_theme_font_size_override("font_size", 14)
	_close_btn.add_theme_color_override("font_color", Color.from_hsv(hue, 0.25, 0.7, 0.7))
	_close_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.35, 0.3, 1.0))
	_close_btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.2, 0.2, 1.0))
	# 背景样式 (同终端模式)
	var normal_bg = StyleBoxFlat.new()
	normal_bg.bg_color = Color(0.03, 0.05, 0.1, 0.75)
	normal_bg.border_color = Color.from_hsv(hue, 0.3, 0.6, 0.25)
	normal_bg.set_border_width_all(1)
	normal_bg.set_corner_radius_all(4)
	normal_bg.content_margin_left = 12
	normal_bg.content_margin_right = 12
	normal_bg.content_margin_top = 5
	normal_bg.content_margin_bottom = 5
	var hover_bg = StyleBoxFlat.new()
	hover_bg.bg_color = Color(0.12, 0.04, 0.04, 0.85)
	hover_bg.border_color = Color(0.8, 0.25, 0.25, 0.4)
	hover_bg.set_border_width_all(1)
	hover_bg.set_corner_radius_all(4)
	hover_bg.content_margin_left = 12
	hover_bg.content_margin_right = 12
	hover_bg.content_margin_top = 5
	hover_bg.content_margin_bottom = 5
	_close_btn.add_theme_stylebox_override("normal", normal_bg)
	_close_btn.add_theme_stylebox_override("hover", hover_bg)
	_close_btn.add_theme_stylebox_override("pressed", hover_bg)
	_close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_btn.pressed.connect(_on_close_pressed)
	parent.add_child(_close_btn)
	# 延迟淡入
	_close_btn.modulate.a = 0.0
	_close_btn_visible = false
	var tween = _close_btn.create_tween()
	tween.tween_property(_close_btn, "modulate:a", 1.0, 0.4).set_delay(0.3)
	_close_btn_visible = true
	_update_close_btn_position()

func _update_close_btn_hover() -> void:
	if not is_instance_valid(_close_btn):
		return
	var mouse_pos = pet.get_global_mouse_position()
	var dist = pet.global_position.distance_to(mouse_pos)
	var hover_range = pet.PET_RADIUS * 3.5
	var is_near = dist <= hover_range
	# 也检测鼠标是否在按钮上
	if is_instance_valid(_close_btn) and _close_btn.get_global_rect().has_point(Vector2(mouse_pos.x, mouse_pos.y)):
		is_near = true
	# 双态: 悬停时切换文字
	if is_near:
		if _close_btn.text != _HOVER_TEXT:
			_close_btn.text = _HOVER_TEXT
	else:
		if _close_btn.text != _DEFAULT_TEXT:
			_close_btn.text = _DEFAULT_TEXT

func _update_close_btn_position() -> void:
	if not is_instance_valid(_close_btn):
		return
	var anchor = pet.get_ui_anchor()
	var btn_size = _close_btn.size if _close_btn.size.x > 0 else Vector2(70, 22)
	var btn_x = anchor.center.x - btn_size.x * 0.5
	# 按钮放在宠物头顶方向 (正常=上方, 反重力=下方)
	var btn_y = anchor.head_y + anchor.head_dir * 10.0
	if anchor.head_dir < 0:
		btn_y -= btn_size.y  # 正常模式: 按钮底边对齐头顶
	_close_btn.position = Vector2(btn_x, btn_y)

func _remove_close_btn() -> void:
	if is_instance_valid(_close_btn):
		_close_btn.queue_free()
	_close_btn = null

func _on_close_pressed() -> void:
	# [待接入] 新游戏系统规划后在此处理关闭流程
	# 旧接口 (BaseGame._close_game / close_game_requested) 已随 games/ 目录删除
	pass

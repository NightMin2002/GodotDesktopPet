# reminder_bubble.gd — 全局通知气泡
# 在原体宠物头顶冒出提示气泡，自动消散
# 通过 pet.overlay_rect 将自身区域注册到穿透多边形
# 支持消息队列：多条消息依次播放，不会互相吞掉
# 注意: 定向气泡 (戳一戳/吐槽) 已迁移至 pet.gd.show_local_bubble()
extends CanvasLayer

var bubble_panel: PanelContainer
var bubble_label: Label
var pet_ref: RigidBody2D
var _is_showing := false
var _queue: Array[String] = []  # 待播放的消息队列
var _show_generation: int = 0   # 协程取消令牌 (每次强制显示时递增，旧协程自动终止)

func _ready() -> void:
	layer = 110
	_build_bubble()
	EventBus.show_reminder_bubble.connect(_on_bubble_requested)
	EventBus.force_show_bubble.connect(_on_force_bubble_requested)

func link_pet(pet: Node2D) -> void:
	pet_ref = pet as RigidBody2D

func _get_active_pet() -> RigidBody2D:
	if is_instance_valid(pet_ref):
		return pet_ref
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instance" in main_node and is_instance_valid(main_node.pet_instance):
		pet_ref = main_node.pet_instance
		return pet_ref
	return null

func _on_force_bubble_requested(message: String) -> void:
	# 强制中断: 清空队列 + 立即播放
	_queue.clear()
	_show_generation += 1  # 令旧的 _show_bubble 协程自动终止
	if _is_showing:
		bubble_panel.hide()
		var old_pet = _get_active_pet()
		if is_instance_valid(old_pet):
			old_pet.overlay_rect = Rect2()
		_is_showing = false
	_show_bubble(message)

func is_busy() -> bool:
	return _is_showing

func _process(_delta: float) -> void:
	if not bubble_panel.visible:
		return
	var active_pet = _get_active_pet()
	if not is_instance_valid(active_pet):
		return
	var pet_pos = active_pet.get_global_transform_with_canvas().get_origin()
	var bubble_offset_y: float
	if is_instance_valid(active_pet) and active_pet.anti_gravity:
		bubble_offset_y = 50.0  # 宠物下方
	else:
		bubble_offset_y = -90.0  # 宠物上方
	var target_pos = pet_pos + Vector2(-bubble_panel.size.x / 2.0, bubble_offset_y)
	var vp = get_viewport().get_visible_rect().size
	target_pos.x = clampf(target_pos.x, 8, vp.x - bubble_panel.size.x - 8)
	target_pos.y = clampf(target_pos.y, 8, vp.y - bubble_panel.size.y - 8)
	bubble_panel.position = bubble_panel.position.lerp(target_pos, _delta * 10.0)
	
	# 将气泡区域注册到宠物的穿透多边形计算中 (紧贴气泡尺寸+小余量)
	active_pet.overlay_rect = Rect2(bubble_panel.position, bubble_panel.size).grow(10)

func _build_bubble() -> void:
	bubble_panel = PanelContainer.new()
	bubble_panel.visible = false
	bubble_panel.custom_minimum_size = Vector2(60, 30)
	bubble_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 气泡不拦截鼠标
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.1, 0.2, 0.92)
	style.border_color = Color(1, 0.85, 0.3, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(18)
	bubble_panel.add_theme_stylebox_override("panel", style)
	add_child(bubble_panel)
	
	bubble_label = Label.new()
	bubble_label.add_theme_font_size_override("font_size", 20)
	bubble_label.add_theme_color_override("font_color", Color(1, 0.95, 0.85, 1))
	bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 标签不拦截鼠标
	bubble_panel.add_child(bubble_label)

func _on_bubble_requested(message: String) -> void:
	if _is_showing:
		# 🚨 防过度刷屏：完全一样的消息不复读
		if bubble_label.text == message or _queue.has(message):
			return
		# 其他不同消息则排队等候，最多缓存 3 条
		if _queue.size() < 3:
			_queue.append(message)
		return
	_show_bubble(message)

func _show_bubble(message: String) -> void:
	_is_showing = true
	var gen = _show_generation  # 捕获当前代数，用于协程取消检测
	
	bubble_label.text = message
	
	var active_pet = _get_active_pet()
	if is_instance_valid(active_pet):
		var pet_pos = active_pet.get_global_transform_with_canvas().get_origin()
		var init_y = 50.0 if active_pet.anti_gravity else -90.0
		bubble_panel.position = pet_pos + Vector2(-80, init_y)
	
	bubble_panel.modulate.a = 0.0
	bubble_panel.scale = Vector2(0.5, 0.5)
	bubble_panel.show()
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(bubble_panel, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(bubble_panel, "modulate:a", 1.0, 0.2)
	
	await get_tree().create_timer(6.0).timeout
	if gen != _show_generation:
		return  # 被 force_show_bubble 中断，安全退出旧协程
	if not is_instance_valid(bubble_panel):
		_is_showing = false
		return
	var fade = create_tween().set_parallel(true)
	fade.tween_property(bubble_panel, "modulate:a", 0.0, 0.6)
	var active_fade_pet = _get_active_pet()
	var fade_dir = 40.0 if (is_instance_valid(active_fade_pet) and active_fade_pet.anti_gravity) else -40.0
	fade.tween_property(bubble_panel, "position:y", bubble_panel.position.y + fade_dir, 0.6)
	await fade.finished
	if gen != _show_generation:
		return  # 被 force_show_bubble 中断，安全退出旧协程
	bubble_panel.hide()
	# 清除覆盖区域
	var active_pet2 = _get_active_pet()
	if is_instance_valid(active_pet2):
		active_pet2.overlay_rect = Rect2()
	_is_showing = false
	
	# 播放队列中下一条消息 (间隔 1 秒，避免连续弹出太急)
	if _queue.size() > 0:
		await get_tree().create_timer(1.0).timeout
		if gen != _show_generation:
			return  # 队列等待期间也可能被中断
		if _queue.size() > 0:
			var next_msg = _queue.pop_front()
			_show_bubble(next_msg)

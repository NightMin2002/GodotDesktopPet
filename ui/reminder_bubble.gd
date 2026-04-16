# reminder_bubble.gd — 提醒气泡通知
# 在宠物头顶冒出语音气泡式提示，自动消散
# 通过 pet.overlay_rect 将自身区域注册到穿透多边形
# 支持消息队列：多条消息依次播放，不会互相吞掉
extends CanvasLayer

var bubble_panel: PanelContainer
var bubble_label: Label
var pet_ref: RigidBody2D
var _is_showing := false
var _queue: Array[String] = []  # 待播放的消息队列

func _ready() -> void:
	layer = 110
	_build_bubble()
	EventBus.show_reminder_bubble.connect(_on_bubble_requested)

func link_pet(pet: Node2D) -> void:
	pet_ref = pet as RigidBody2D

func _get_active_pet() -> RigidBody2D:
	if is_instance_valid(pet_ref):
		return pet_ref
	# 尝试从 main 获取原体引用
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instance" in main_node and is_instance_valid(main_node.pet_instance):
		pet_ref = main_node.pet_instance
		return pet_ref
	return null

func is_busy() -> bool:
	return _is_showing

func _process(_delta: float) -> void:
	if not bubble_panel.visible:
		return
	var active_pet = _get_active_pet()
	if not is_instance_valid(active_pet):
		return
	var pet_pos = active_pet.get_global_transform_with_canvas().get_origin()
	var target_pos = pet_pos + Vector2(-bubble_panel.size.x / 2.0, -90)
	var vp = get_viewport().get_visible_rect().size
	target_pos.x = clampf(target_pos.x, 8, vp.x - bubble_panel.size.x - 8)
	target_pos.y = clampf(target_pos.y, 8, vp.y - bubble_panel.size.y - 8)
	bubble_panel.position = bubble_panel.position.lerp(target_pos, _delta * 10.0)
	
	# 将气泡区域注册到宠物的穿透多边形计算中 (grow(60) 覆盖淡出上飘动画)
	active_pet.overlay_rect = Rect2(bubble_panel.position, bubble_panel.size).grow(60)

func _build_bubble() -> void:
	bubble_panel = PanelContainer.new()
	bubble_panel.visible = false
	bubble_panel.custom_minimum_size = Vector2(60, 30)
	
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
	bubble_panel.add_child(bubble_label)

func _on_bubble_requested(message: String) -> void:
	if _is_showing:
		# 🚨 防过度点拽刷屏：如果当前屏幕正在显示的，或是队列里已经有完全一模一样的话，直接抛弃不复读！
		if bubble_label.text == message or _queue.has(message):
			return
			
		# 其他不同消息则排队等候，最多缓存 3 条
		if _queue.size() < 3:
			_queue.append(message)
		return
	_show_bubble(message)

func _show_bubble(message: String) -> void:
	_is_showing = true
	
	bubble_label.text = message
	
	var active_pet = _get_active_pet()
	if is_instance_valid(active_pet):
		var pet_pos = active_pet.get_global_transform_with_canvas().get_origin()
		bubble_panel.position = pet_pos + Vector2(-80, -90)
	
	bubble_panel.modulate.a = 0.0
	bubble_panel.scale = Vector2(0.5, 0.5)
	bubble_panel.show()
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(bubble_panel, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(bubble_panel, "modulate:a", 1.0, 0.2)
	
	await get_tree().create_timer(6.0).timeout
	if not is_instance_valid(bubble_panel):
		_is_showing = false
		return
	var fade = create_tween().set_parallel(true)
	fade.tween_property(bubble_panel, "modulate:a", 0.0, 0.6)
	fade.tween_property(bubble_panel, "position:y", bubble_panel.position.y - 40, 0.6)
	await fade.finished
	bubble_panel.hide()
	# 清除覆盖区域
	var active_pet2 = _get_active_pet()
	if is_instance_valid(active_pet2):
		active_pet2.overlay_rect = Rect2()
	_is_showing = false
	
	# 播放队列中下一条消息 (间隔 1 秒，避免连续弹出太急)
	if _queue.size() > 0:
		await get_tree().create_timer(1.0).timeout
		if _queue.size() > 0:
			var next_msg = _queue.pop_front()
			_show_bubble(next_msg)

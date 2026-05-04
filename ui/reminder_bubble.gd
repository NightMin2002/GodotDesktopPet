# reminder_bubble.gd — 全局通知路由
# 接收全局通知信号，委托给原体宠物的本地气泡系统 (pet_hud.gd) 显示
# 自身仅负责: 信号监听 → 防重复/队列管理 → 转发到 pet.show_local_bubble()
# 不再维护独立的 PanelContainer，消除与 pet_hud 的代码重复
extends CanvasLayer

var pet_ref: RigidBody2D
var _is_showing := false
var _queue: Array[String] = []  # 待播放的消息队列
var _show_generation: int = 0   # 协程取消令牌 (每次强制显示时递增，旧协程自动终止)
var _current_message := ""      # 当前正在显示的消息 (用于防重复)

func _ready() -> void:
	layer = 110
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

func is_busy() -> bool:
	return _is_showing

func _on_bubble_requested(message: String) -> void:
	if _is_showing:
		# 防过度刷屏：完全一样的消息不复读
		if _current_message == message or _queue.has(message):
			return
		# 其他不同消息则排队等候，最多缓存 3 条
		if _queue.size() < 3:
			_queue.append(message)
		return
	_show_bubble(message)

func _on_force_bubble_requested(message: String) -> void:
	# 强制中断: 清空队列 + 立即播放
	_queue.clear()
	_show_generation += 1  # 令旧的 _show_bubble 协程自动终止
	_is_showing = false
	_show_bubble(message)

func _show_bubble(message: String) -> void:
	_is_showing = true
	_current_message = message
	var gen = _show_generation  # 捕获当前代数，用于协程取消检测
	
	# 委托给原体宠物的本地气泡系统显示
	var active_pet = _get_active_pet()
	if is_instance_valid(active_pet):
		active_pet.show_local_bubble(message)
	
	# 等待气泡显示周期 (本地气泡自身管理 4 秒生命+0.6秒淡出)
	await get_tree().create_timer(5.0).timeout
	if gen != _show_generation:
		return  # 被 force_show_bubble 中断，安全退出旧协程
	
	_is_showing = false
	_current_message = ""
	
	# 播放队列中下一条消息 (间隔 1 秒，避免连续弹出太急)
	if _queue.size() > 0:
		await get_tree().create_timer(1.0).timeout
		if gen != _show_generation:
			return  # 队列等待期间也可能被中断
		if _queue.size() > 0:
			var next_msg = _queue.pop_front()
			_show_bubble(next_msg)

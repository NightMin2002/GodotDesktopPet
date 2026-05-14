# reminder_service.gd — 提醒后台服务 (常驻轻量 Node)
# 职责: 10 秒轮询检查提醒时间、触发气泡通知、管理待确认队列
# UI 展示由 profile/profile_tab_reminder.gd 负责
extends Node

var _check_timer := 0.0
var _fired_keys: Dictionary = {}
var _pet: Node2D

func _ready() -> void:
	_find_pet.call_deferred()

func _find_pet() -> void:
	var main = get_tree().root.get_node_or_null("Main")
	if main:
		for child in main.get_children():
			if child is RigidBody2D:
				_pet = child
				return

func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= 10.0:
		_check_timer = 0.0
		_check_reminders()

func _check_reminders() -> void:
	var now_dict = Time.get_time_dict_from_system()
	var now_str = "%02d:%02d" % [now_dict["hour"], now_dict["minute"]]
	
	var today = Time.get_date_string_from_system()
	if _fired_keys.get("_date", "") != today:
		_fired_keys = {"_date": today}
	
	var reminders = SettingsManager.get_reminders()
	var to_remove: Array[int] = []
	
	for i in range(reminders.size()):
		var r = reminders[i]
		if not r.get("on", true):
			continue
		var key = r.get("time", "") + "|" + r.get("msg", "")
		if r.get("time", "") == now_str and not _fired_keys.has(key):
			_fired_keys[key] = true
			EventBus.show_reminder_bubble.emit(r.get("msg", "时间节点已到达。"))
			# 记为待确认提醒 (用户戳宠物时再次传达)
			if is_instance_valid(_pet) and _pet.has_method("handle_poke"):
				_pet.poke_system.pending_reminders.append({"time": r.get("time", ""), "msg": r.get("msg", "时间节点已到达。")})
			# 一次性提醒：触发后标记删除
			if r.get("once", false):
				to_remove.append(i)
	
	# 从后往前删除，避免索引错位
	if to_remove.size() > 0:
		to_remove.reverse()
		for idx in to_remove:
			reminders.remove_at(idx)
		SettingsManager.save_reminders(reminders)

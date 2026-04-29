# pet_chatter.gd — 宠物碎碎念
# 对齐系统时钟的整点/半点触发，宠物主动冒泡说点什么
extends Node

# 模式: 0=关闭, 1=每30分钟, 2=每60分钟
var _mode := 1
var _pet: RigidBody2D
var _last_triggered_key := ""  # 防止同一时刻重复触发 (格式: "HH:MM")
var _check_timer := 0.0
var _recent_lines: Array[String] = []  # 最近说过的话，避免短期重复
const MAX_RECENT := 5
var _period_used: Dictionary = {}  # 今天已用过的时段 {"morning": true, ...}
var _today_date := ""  # 当前日期，跸日重置

# ── 话术池 ──

const GENERAL_LINES := [
	"连续操作已超半小时。建议活动。",
	"水分补给提醒。...不是在管你。",
	"屏幕注视时间过长。建议执行眨眼。",
	"已过半小时。...时间是自己走的。",
	"姿势数据异常概率上升。建议调整坐姿。",
	"本机运行正常。...顺便，你也检查一下自己。",
	"半小时节点已到。做什么由你决定。",
	"你的专注度数据不错。...但别忘了你是碳基生物。",
	"系统建议：起身活动。执行概率由你决定。",
	"检测到持续操作状态。提醒一下。不代表在意。",
	"呼吸频率稳定。继续保持。...顺便站起来。",
	"半小时。本机正常运转中。...你呢？",
]

const MORNING_LINES := [
	"早间环境光照良好。适合远眺。",
	"上午时段。效率峰值区间。...水分补给别忽略。",
	"日间模式启动。...你也是。",
]

const AFTERNOON_LINES := [
	"午后时段。碳基生物的困倦高发期。",
	"下午过半。运行状态...还行吗？",
	"检测到午后时段。如需饮品，自行决定。",
]

const EVENING_LINES := [
	"日间任务接近尾声。...这是客观评价。",
	"傍晚了。今天的数据量不小。",
	"晚间模式待切换。...能量补给完成了吗？",
]

const NIGHT_LINES := [
	"当前时间已进入夜间区段。",
	"夜间模式建议启用。...对你，不是对我。",
	"深夜了。你的运行时长已超出建议值。",
	"检测到深夜操作。...本机不评价。但建议停止。",
]

func _ready() -> void:
	_mode = SettingsManager.get_int("pet_chatter_mode", 1)
	EventBus.setting_toggled.connect(_on_setting_toggled)

func link_pet(pet: Node2D) -> void:
	_pet = pet as RigidBody2D

func _process(delta: float) -> void:
	if _mode == 0:
		return
	if not is_instance_valid(_pet):
		return
	
	# 每 5 秒检查一次系统时间 (不需要每帧)
	_check_timer += delta
	if _check_timer >= 5.0:
		_check_timer = 0.0
		_check_time()

func _check_time() -> void:
	var now = Time.get_time_dict_from_system()
	var hour: int = now["hour"]
	var minute: int = now["minute"]
	
	var should_trigger := false
	if _mode == 1:  # 每30分钟: 整点和半点触发
		should_trigger = (minute == 0 or minute == 30)
	elif _mode == 2:  # 每60分钟: 仅整点触发
		should_trigger = (minute == 0)
	
	if not should_trigger:
		return
	
	# 用 "HH:MM" 作为 key 防止同一时刻重复触发
	var key = "%02d:%02d" % [hour, minute]
	if key == _last_triggered_key:
		return
	
	_last_triggered_key = key
	_trigger_chatter()

func _trigger_chatter() -> void:
	var line = _pick_line()
	EventBus.show_reminder_bubble.emit(line)
	# 记为待确认 (覆盖旧的，只保留最新一条)
	if is_instance_valid(_pet):
		_pet.poke_system.pending_chatter = line
	# 轻弹跳引起注意 (仅自由行动模式下)
	if is_instance_valid(_pet) and _pet.behavior_mode == 0:
		_gentle_bounce()

func _gentle_bounce() -> void:
	_pet.apply_central_impulse(Vector2(randf_range(-30, 30), -350))
	_pet.apply_torque_impulse(randf_range(-800, 800))

func _pick_line() -> String:
	# 跸日重置时段记忆
	var today = Time.get_date_string_from_system()
	if today != _today_date:
		_today_date = today
		_period_used.clear()
	
	var pool: Array[String] = []
	pool.append_array(GENERAL_LINES)
	
	# 时段话术每天只追加一次，用过后当天不再混入
	var hour: int = Time.get_time_dict_from_system()["hour"]
	var period := ""
	if hour >= 6 and hour < 12:
		period = "morning"
	elif hour >= 12 and hour < 18:
		period = "afternoon"
	elif hour >= 18 and hour < 22:
		period = "evening"
	else:
		period = "night"
	
	if not _period_used.get(period, false):
		match period:
			"morning": pool.append_array(MORNING_LINES)
			"afternoon": pool.append_array(AFTERNOON_LINES)
			"evening": pool.append_array(EVENING_LINES)
			"night": pool.append_array(NIGHT_LINES)
		_period_used[period] = true
	
	# 排除最近说过的话
	var candidates: Array[String] = []
	for line in pool:
		if not _recent_lines.has(line):
			candidates.append(line)
	# 如果全说过了就重置记忆（话术池较小时的兜底）
	if candidates.is_empty():
		_recent_lines.clear()
		candidates.assign(pool)
	
	var picked = candidates[randi() % candidates.size()]
	_recent_lines.append(picked)
	if _recent_lines.size() > MAX_RECENT:
		_recent_lines.pop_front()
	return picked

func _on_setting_toggled(setting_id: String, _is_on: bool) -> void:
	if setting_id == "pet_chatter_mode":
		_mode = SettingsManager.get_int("pet_chatter_mode", 1)
		_last_triggered_key = ""  # 切换模式后重置

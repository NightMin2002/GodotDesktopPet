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
	"主人~ 已经半小时了哦，活动活动？🙆",
	"去倒杯水吧，我等你回来~ 💧",
	"看看窗外吧，眼睛会感谢你的 🌿",
	"时间过好快...你有没有觉得？⏳",
	"伸个懒腰吧！我也伸一个~ 🐾",
	"注意调整一下姿势哦，别太僵硬了",
	"半小时到！奖励自己休息一下吧 🎉",
	"你已经超厉害地专注了好一阵子！✨",
	"别忘了眨眨眼睛～盯太久屏幕不好哦",
	"深呼吸一下吧，放松放松肩膀~",
	"主人辛苦了，要不要休息一会儿？☕",
	"我替你看着，你先休息一下吧~",
]

const MORNING_LINES := [
	"早上的阳光最适合远眺了 ☀️",
	"上午效率最高！但也别忘了喝水哦~",
	"新的一天，主人加油！💪",
]

const AFTERNOON_LINES := [
	"下午犯困了吗？站起来走走吧~ 🚶",
	"午后时光，来杯茶怎么样？🍵",
	"下午过半了，主人还撑得住吗？😊",
]

const EVENING_LINES := [
	"晚上了呢，今天辛苦了～🌆",
	"忙了一天了，差不多可以收工啦~",
	"晚饭吃了吗？别饿着自己呀 🍚",
]

const NIGHT_LINES := [
	"主人...已经很晚了呢 🌙",
	"夜深了，注意身体，早点休息吧 💤",
	"这么晚了还在忙呀...辛苦了 🥺",
	"熬夜对身体不好的...虽然我也不睡 😅",
]

func _ready() -> void:
	_mode = SettingsManager.get_int("pet_chatter_mode", 1)
	EventBus.setting_toggled.connect(_on_setting_toggled)

func link_pet(pet: Node2D) -> void:
	_pet = pet as RigidBody2D

func _process(delta: float) -> void:
	if _mode == 0:
		return
	# 全屏锁定时不打扰
	if is_instance_valid(_pet) and _pet.fullscreen_locked:
		return
	
	# 每 5 秒检查一次系统时间 (不需要每帧)
	_check_timer += delta
	if _check_timer < 5.0:
		return
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

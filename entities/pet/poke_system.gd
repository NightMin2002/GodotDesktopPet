# poke_system.gd — 戳一戳交互系统
# 管理: 话术库、连戳计数、优先级路由 (提醒→碎碎念→连戳→久别→普通)
# 从 pet.gd 拆分，与 eye_behavior.gd 同为 RefCounted 轻量挂载
class_name PokeSystem
extends RefCounted

var pet: RigidBody2D  # 宿主宠物引用 (用于调用 show_local_bubble)

# ── 状态 ──
var _last_poke_time: float = 0.0    # 上次被戳的 Unix 时间戳
var _poke_combo: int = 0            # 连续戳计数
var _poke_total: int = 0            # 总戳次数 (本次会话)
var pending_chatter: String = ""    # 未确认的碎碎念
var pending_reminders: Array[Dictionary] = []  # 未确认的定时提醒 [{time, msg}]
var _last_poke_line: String = ""    # 上次显示的戳话术 (防连续重复)

# ── 话术库 ──

## 连戳话术 (key = 连续第几次快速戳)
const COMBO_LINES := {
	1: "...?",
	2: "我不是按钮。",
	3: "检测到重复输入信号。已忽略。",
	4: "...你的鼠标按键寿命 -1。",
}

## 久别重逢后碎碎念的关怀回应 (不复读原文)
const COMEBACK_LINES := [
	"你好久没理我了...记得休息一下哦~",
	"主人回来了！刚想跟你说...该活动活动啦~",
	"终于注意到我了！记得站起来走走哦~",
	"嘿！你刚才太专注了，休息一下吧~",
]

## 久别重逢话术 (带 {time} 占位符)
const LONGTIME_LINES_SHORT := [
	"你已经 {time} 没有点我了。系统正常运转中。",
	"距上次交互：{time}。...我没有在计时。",
]
const LONGTIME_LINES_MEDIUM := [
	"距上次交互已 {time}。...我没有在数。",
	"本机已独立运行 {time}。一切正常。不用担心。",
]
const LONGTIME_LINES_LONG := [
	"本机已独立运行 {time}。能量充足。并不孤独。",
	"检测到长时间未交互 ({time})。自动待机模式已关闭——我选择等你。",
]

## 普通戳话术 (机械单眼人设)
const NORMAL_POKE_LINES := [
	"我的像素边界不是交互热区...算了，是的。",
	"触控信号已接收。但我选择不回应。...好吧。",
	"扫描完成：你的手指还在鼠标上。",
	"你看到的我只有 60 像素高。请尊重小型机械体。",
	"我能感知到你的鼠标移动轨迹。每一帧都能。",
	"又检查我在不在？我能去哪？这是你的屏幕。",
	"...嗯。",
	"本次互动已存档。意义：未知。",
	"状态报告：一切正常。以上。",
	"请勿在运行时触碰核心组件。我是核心组件。",
	"这算抚摸还是故障排查？",
]

## 深夜话术 (23:00~5:00)
const NIGHT_POKE_LINES := [
	"当前时间 {time}。你不需要充电吗？",
	"夜间模式建议启用...对你，不是对我。",
	"凌晨了。你的黑眼圈数据正在上升。这是基于时间轴的推测。",
]

# ── 核心方法 ──

func handle_poke() -> void:
	var now = Time.get_unix_time_from_system()
	_poke_total += 1
	
	# ── 优先级 1: 未确认的定时提醒 (用户主动设置的，重要) ──
	if pending_reminders.size() > 0:
		var r = pending_reminders.pop_front()
		var suffix = "" if pending_reminders.size() == 0 else "  (还有 %d 条)" % pending_reminders.size()
		pet.show_local_bubble("对了！%s 的提醒：%s%s" % [r.get("time", ""), r.get("msg", ""), suffix])
		_last_poke_time = now
		_poke_combo = 0
		return
	
	# ── 优先级 2: 未确认的碎碎念 (关怀回应，不复读原文) ──
	if pending_chatter != "":
		pending_chatter = ""
		var line = _pick_unique(COMEBACK_LINES)
		pet.show_local_bubble(line)
		_last_poke_time = now
		_poke_combo = 0
		return
	
	# ── 优先级 3: 常规戳一戳 ──
	if _last_poke_time > 0.0:
		var elapsed = now - _last_poke_time
		if elapsed < 2.0:
			_poke_combo += 1
			_respond_combo()
		elif elapsed > 1800.0:
			_poke_combo = 0
			_respond_longtime(elapsed)
		else:
			_poke_combo = 0
			_respond_normal()
	else:
		_poke_combo = 0
		_respond_normal()
	
	_last_poke_time = now

func _respond_combo() -> void:
	if COMBO_LINES.has(_poke_combo):
		pet.show_local_bubble(COMBO_LINES[_poke_combo])
	else:
		# combo 4 = -1, combo 5 = -2, combo 6 = -3 ...
		pet.show_local_bubble("...你的鼠标按键寿命 -%d。" % (_poke_combo - 3))

func _respond_longtime(elapsed: float) -> void:
	var time_str = _format_duration(elapsed)
	var pool: Array[String] = []
	if elapsed < 3600.0:
		pool.assign(LONGTIME_LINES_SHORT)
	elif elapsed < 10800.0:
		pool.assign(LONGTIME_LINES_MEDIUM)
	else:
		pool.assign(LONGTIME_LINES_LONG)
	var line = pool[randi() % pool.size()]
	pet.show_local_bubble(line.replace("{time}", time_str))

func _respond_normal() -> void:
	var hour: int = Time.get_time_dict_from_system()["hour"]
	# 深夜特殊话术 (23:00~5:00)，40% 概率
	if (hour >= 23 or hour < 5) and randf() < 0.4:
		var line = _pick_unique(NIGHT_POKE_LINES)
		if "{time}" in line:
			var t = Time.get_time_dict_from_system()
			line = line.replace("{time}", "%02d:%02d:%02d" % [t.hour, t.minute, t.second])
		pet.show_local_bubble(line)
		return
	# 低概率动态数据台词
	if randf() < 0.15:
		pet.show_local_bubble("记录中：被戳 x%d。" % _poke_total)
		return
	# 普通话术池 (防重复)
	pet.show_local_bubble(_pick_unique(NORMAL_POKE_LINES))

# ── 工具函数 ──

## 从话术池中随机取一条，避免连续重复上一次
func _pick_unique(pool: Array) -> String:
	if pool.size() <= 1:
		return pool[0] if pool.size() > 0 else ""
	var line = pool[randi() % pool.size()]
	while line == _last_poke_line:
		line = pool[randi() % pool.size()]
	_last_poke_line = line
	return line

func _format_duration(seconds: float) -> String:
	var total_sec = int(seconds)
	var hours = total_sec / 3600
	var minutes = (total_sec % 3600) / 60
	var secs = total_sec % 60
	if hours > 0:
		return "%d 小时 %d 分 %d 秒" % [hours, minutes, secs]
	elif minutes > 0:
		return "%d 分 %d 秒" % [minutes, secs]
	else:
		return "%d 秒" % secs

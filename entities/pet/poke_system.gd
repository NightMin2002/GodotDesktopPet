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
var _recent_poke_lines: Array[String] = []  # 已触发话术记录 (洗牌模式: 全部说完才重置)

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
	"...终于响应了。活动协议待执行。建议现在。",
	"信号恢复。...刚才的提醒还生效。",
	"收到触控。顺便，你的连续在线时长需要关注一下。",
	"输入确认。...之前说的话，不重复了。你知道的。",
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

## 深夜话术 (23:00~5:00, 清醒时随机触发)
const NIGHT_POKE_LINES := [
	"当前时间 {time}。你不需要充电吗？",
	"夜间模式建议启用...对你，不是对我。",
	"凌晨了。你的黑眼圈数据正在上升。这是基于时间轴的推测。",
]

## 深夜休眠中被戳 (半梦半醒，催你去睡)
const NIGHTTIME_HIBERNATE_LINES := [
	"...休眠中。",
	"...嗯。",
	"系统待机。触控信号已搁置。",
	"...你也该进入休眠周期了。",
	"夜间模式。非必要交互已屏蔽。",
	"...检测到深夜触控。不处理。",
	"本机休眠中。...你为什么没有。",
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
	
	# ── 优先级 3: 深夜休眠中被戳 (半梦半醒应答，不走通用路由) ──
	if pet.nighttime_mode and pet.idle_behaviors.active_behavior == "hibernate":
		pet.show_local_bubble(_pick_unique(NIGHTTIME_HIBERNATE_LINES))
		_last_poke_time = now
		_poke_combo = 0
		return
	
	# ── 优先级 4: 常规戳一戳 ──
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

## 洗牌模式: 全池说完一轮才重置，重置时保留最后一条防首尾相连
func _pick_unique(pool: Array) -> String:
	if pool.size() <= 1:
		return pool[0] if pool.size() > 0 else ""
	# 排除已说过的
	var candidates: Array[String] = []
	for line in pool:
		if not _recent_poke_lines.has(line):
			candidates.append(line)
	# 全部说完了 → 重置记忆，保留最后一条防止首尾相连
	if candidates.is_empty():
		var last = _recent_poke_lines.back()
		_recent_poke_lines.clear()
		_recent_poke_lines.append(last)
		for line in pool:
			if line != last:
				candidates.append(line)
	var picked = candidates[randi() % candidates.size()]
	_recent_poke_lines.append(picked)
	return picked

func _format_duration(seconds: float) -> String:
	var total_sec = int(seconds)
	@warning_ignore("integer_division")
	var hours = total_sec / 3600
	@warning_ignore("integer_division")
	var minutes = (total_sec % 3600) / 60
	var secs = total_sec % 60
	if hours > 0:
		return "%d 小时 %d 分 %d 秒" % [hours, minutes, secs]
	elif minutes > 0:
		return "%d 分 %d 秒" % [minutes, secs]
	else:
		return "%d 秒" % secs

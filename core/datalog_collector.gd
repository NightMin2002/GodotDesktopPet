# datalog_collector.gd — 键鼠行为数据采集器 (Autoload)
# 桥接 C# InputMonitor 和数据日志系统
# 监控全局键鼠输入 → 生成 source:"pet" 日志条目
extends Node

# ── 配置 ──
const REPORT_INTERVAL := 7200.0  # 2 小时自动汇报一次 (秒)
const MIN_KEYSTROKES := 50       # 低于此值不生成报告 (避免空报告)

# ── 状态 ──
var _monitor: Node = null  # C# InputMonitor 引用
var _report_timer: Timer
var _session_start: String = ""
var _enabled: bool = false

func _ready() -> void:
	_session_start = Time.get_datetime_string_from_system(false, true)

	# 加载 C# InputMonitor
	call_deferred("_init_monitor")

	# 定时汇报
	_report_timer = Timer.new()
	_report_timer.one_shot = false
	_report_timer.wait_time = REPORT_INTERVAL
	_report_timer.timeout.connect(_on_report_timer)
	add_child(_report_timer)

	# 监听手动触发信号
	EventBus.trigger_input_report.connect(_on_manual_trigger)

func _init_monitor() -> void:
	# InputMonitor 是 C# 节点，需要用 CSharpScript 实例化
	var script = load("res://interop/InputMonitor.cs")
	if script == null:
		push_warning("[DataLogCollector] InputMonitor.cs 加载失败, 键鼠监控不可用")
		return

	_monitor = script.new()
	_monitor.name = "InputMonitor"
	add_child(_monitor)

	# 默认启动监控
	start()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# 退出时写入会话总结
		_generate_report("session_end")

# ═══════════════════════════════════════════════
#  公开 API
# ═══════════════════════════════════════════════

func start() -> void:
	if _monitor == null:
		return
	_monitor.StartMonitoring()
	_enabled = _monitor.IsActive()
	if _enabled:
		_report_timer.start()
		print("[DataLogCollector] 键鼠监控已启动")

func stop() -> void:
	if _monitor == null:
		return
	_monitor.StopMonitoring()
	_enabled = false
	_report_timer.stop()
	print("[DataLogCollector] 键鼠监控已停止")

func is_active() -> bool:
	return _enabled and _monitor != null and _monitor.IsActive()

## 手动触发生成报告 (调试用)
func force_report() -> void:
	_generate_report("manual")

# ═══════════════════════════════════════════════
#  定时 & 手动触发
# ═══════════════════════════════════════════════

func _on_report_timer() -> void:
	_generate_report("scheduled")

func _on_manual_trigger() -> void:
	force_report()

# ═══════════════════════════════════════════════
#  报告生成
# ═══════════════════════════════════════════════

func _generate_report(trigger: String) -> void:
	if _monitor == null:
		return

	var total_keys = _monitor.GetTotalKeystrokes()
	var key_stats = _monitor.GetKeyStats()
	var combo_stats = _monitor.GetComboStats()
	var mouse_stats = _monitor.GetMouseStats()

	# 低于阈值不生成 (手动触发除外)
	var left = mouse_stats.get("left_clicks", 0)
	var right = mouse_stats.get("right_clicks", 0)
	if trigger != "manual" and total_keys < MIN_KEYSTROKES and (left + right) < 20:
		return

	var now = Time.get_datetime_string_from_system(false, true)

	# 构建报告正文 (纯数据, 不加文案)
	var lines: PackedStringArray = []
	lines.append("=== 键鼠行为报告 ===")
	lines.append("触发: %s | 时间: %s" % [trigger, now])
	lines.append("会话起始: %s" % _session_start)
	lines.append("")

	# ── 键盘概览 ──
	lines.append("--- 键盘 ---")
	lines.append("总击键: %d" % total_keys)

	# Top 10 高频按键
	if key_stats.size() > 0:
		var sorted_keys = _sort_dict_by_value(key_stats)
		lines.append("高频按键 (Top 10):")
		var count = 0
		for pair in sorted_keys:
			if count >= 10:
				break
			lines.append("  %s: %d" % [pair[0], pair[1]])
			count += 1

	# 退格/删除统计
	var backspace = key_stats.get("Backspace", 0)
	var delete_key = key_stats.get("Delete", 0)
	if backspace + delete_key > 0:
		var delete_rate = 0.0
		if total_keys > 0:
			delete_rate = float(backspace + delete_key) / total_keys * 100.0
		lines.append("退格: %d | Delete: %d | 删除率: %.1f%%" % [backspace, delete_key, delete_rate])

	lines.append("")

	# ── 组合键 ──
	if combo_stats.size() > 0:
		lines.append("--- 组合键 ---")
		var sorted_combos = _sort_dict_by_value(combo_stats)
		for pair in sorted_combos:
			lines.append("  %s: %d" % [pair[0], pair[1]])
		lines.append("")

	# ── 鼠标 ──
	lines.append("--- 鼠标 ---")
	lines.append("左键: %d | 右键: %d | 中键: %d" % [
		mouse_stats.get("left_clicks", 0),
		mouse_stats.get("right_clicks", 0),
		mouse_stats.get("middle_clicks", 0),
	])
	var scroll = mouse_stats.get("scroll_delta", 0)
	if scroll > 0:
		lines.append("滚轮累计: %d" % scroll)

	# 写入数据日志
	var content = "\n".join(lines)
	var td = Time.get_datetime_dict_from_system()
	var title = "键鼠报告 %02d-%02d %02d:%02d" % [td.month, td.day, td.hour, td.minute]

	var id = "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	var entry = {
		"id": id,
		"title": title,
		"content": content,
		"tags": ["input", trigger],
		"source": "pet",
		"created": now,
		"updated": now,
	}

	var logs = SettingsManager.get_datalogs()
	logs.insert(0, entry)
	SettingsManager.save_datalogs(logs)
	print("[DataLogCollector] 报告已生成: %s (%s)" % [title, trigger])

	# 生成报告后重置计数 (下次报告是增量数据)
	_monitor.ResetStats()

# ═══════════════════════════════════════════════
#  工具函数
# ═══════════════════════════════════════════════

## 将字典按 value 降序排列, 返回 [[key, value], ...]
func _sort_dict_by_value(dict) -> Array:
	var pairs = []
	for key in dict:
		pairs.append([key, dict[key]])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	return pairs



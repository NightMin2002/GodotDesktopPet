# idle_behaviors.gd — Idle 微行为管理器
# 管理待机状态下的微行为子阶段: 低功耗休眠 / 系统自检
# 从 idle.gd 拆分，与 poke_system.gd 同为 RefCounted 轻量挂载
class_name IdleBehaviors
extends RefCounted

var pet: RigidBody2D  # 宿主宠物引用

# ── 状态 ──
var active_behavior: String = ""   # 当前活跃行为: "", "hibernate", "scan"
var _behavior_timer := 0.0         # 行为内部计时器

# ── 休眠参数 ──
var _hibernate_phase := 0          # 0=进入, 1=持续, 2=退出
var hibernate_style := 0           # 0=挡板, 1=加载指示, 2=电池图标
var _hibernate_anim_time := 0.0    # 累计动画时间 (跨阶段不重置, 用于平滑旋转)

var _hibernate_bubble_shown := false
var _hibernate_done := false        # 本轮离席已休眠过 (鼠标活动后重置)

# ── 自检调度 (真实时钟驱动) ──
var _scan_clock := 0.0             # 距上次自检的累计秒数
var _next_scan_interval := 0.0     # 下次自检的间隔 (秒)
var _scan_count_3h := 0            # 3小时窗口内已执行自检次数
var _window_clock := 0.0           # 3小时窗口计时器
const SCAN_MAX_PER_3H := 3         # 3小时内最多自检次数

# ── 休眠条件 ──
const MOUSE_IDLE_FOR_HIBERNATE := 300.0  # 鼠标静止 5 分钟后允许触发休眠

# ── 话术池 ──
const HIBERNATE_ENTER_LINES := [
	"低功耗模式...",
	"进入待机...",
	"节能模式启动...",
	"...休眠中。",
]

const HIBERNATE_WAKE_LINES := [
	"...系统恢复。",
	"低功耗模式结束。",
	"...嗯。重新上线。",
	"待机结束。一切正常。",
]

const SCAN_DONE_LINES := [
	"自检完毕。",
	"诊断完毕。一切正常。",
	"自检通过。",
	"组件状态：良好。",
]

func _init() -> void:
	# 首次自检间隔: 启动后 40~80 分钟
	_next_scan_interval = randf_range(2400.0, 4800.0)

# ── 主循环 ──

func update(delta: float) -> void:
	# 分身不运行微行为系统 (不需要自检/休眠)
	if pet.is_clone:
		return
	
	# 自检时钟始终运转 (无论是否在 idle)
	_scan_clock += delta
	_window_clock += delta
	# 鼠标活动后重置休眠标志 (用户回来了)
	if _hibernate_done and pet.eye_behavior._mouse_idle_time < 5.0:
		_hibernate_done = false
	# 3小时窗口重置
	if _window_clock >= 10800.0:  # 3 * 60 * 60
		_window_clock = 0.0
		_scan_count_3h = 0
	
	# ── 主动触发休眠: 持续监控，不依赖 idle.gd 的 try_random() ──
	if active_behavior == "" and not _hibernate_done:
		if pet.eye_behavior._mouse_idle_time >= MOUSE_IDLE_FOR_HIBERNATE:
			var state = pet.current_state_name
			if state == "idle":
				trigger("hibernate")
			elif state == "walk":
				# 正在散步 → 先回到 idle 再进入休眠
				pet.transition_to("idle")
				trigger("hibernate")
	
	if active_behavior == "":
		return
	_behavior_timer += delta
	if active_behavior == "hibernate":
		_hibernate_anim_time += delta
	match active_behavior:
		"hibernate": _update_hibernate(delta)
		"scan": _update_scan(delta)

## 当前是否有活跃的微行为
func is_active() -> bool:
	return active_behavior != ""

## 获取自定义休眠视觉的混合度 (0.0=不显示, 1.0=完全显示)
## 用于 pet.gd 渲染时平滑淡入/淡出加载指示器和电池图标
func get_hibernate_visual_blend() -> float:
	if active_behavior != "hibernate" or hibernate_style == 0:
		return 0.0
	match _hibernate_phase:
		0: return clampf(_behavior_timer / 1.5, 0.0, 1.0)
		1: return 1.0
		2: return clampf(1.0 - _behavior_timer / 0.8, 0.0, 1.0)
	return 0.0

## 尝试触发微行为 (由 idle.gd 在 idle 状态中调用)
## 返回 true 表示触发了行为 (idle 不应转移到 walk/jump)
func try_random(_idle_elapsed: float) -> bool:
	if active_behavior != "":
		return true  # 已有活跃行为
	
	# ── 自检: 真实时钟到达间隔 + 3小时窗口未满 ──
	if _scan_clock >= _next_scan_interval and _scan_count_3h < SCAN_MAX_PER_3H:
		trigger("scan")
		return true
	
	# ── 休眠: 鼠标长时间未移动 (用户离开了) ──
	# 本轮离席已休眠过则跳过，等用户回来再重置
	if not _hibernate_done:
		if pet.eye_behavior._mouse_idle_time >= MOUSE_IDLE_FOR_HIBERNATE:
			trigger("hibernate")
			return true
	
	return false

## 强制触发指定行为 (测试菜单用)
func trigger(behavior: String) -> void:
	_cancel_current()
	active_behavior = behavior
	_behavior_timer = 0.0
	match behavior:
		"hibernate": _enter_hibernate()
		"scan": _enter_scan()

## 取消当前微行为 (被交互打断)
func cancel() -> void:
	_cancel_current()

# ── 休眠 (低功耗模式) ──
# 触发条件: 鼠标静止 5 分钟以上 (用户离开电脑)

func _enter_hibernate() -> void:
	_hibernate_phase = 0  # 进入阶段
	_hibernate_bubble_shown = false
	_hibernate_anim_time = 0.0
	match hibernate_style:
		0:  # 挡板半闭
			pet.eye_behavior.start_drowsy(0.6)
			pet.eye_behavior.forced_look_dir = Vector2(0, 1)
		1, 2:  # 加载指示 / 电池图标: 抑制眨眼即可
			pet.eye_behavior._drowsy_target = 0.35
	# 增大阻尼，让它"沉下去"
	pet.linear_damp = 3.0
	pet.angular_damp = 5.0
	pet.angular_velocity = 0.0  # 立即停止旋转

func _update_hibernate(_delta: float) -> void:
	# 鼠标恢复活动 → 唤醒 (最低持续5秒，防止调试触发后因刚点菜单立即退出)
	if pet.eye_behavior._mouse_idle_time < 2.0 and _hibernate_phase == 1 and _behavior_timer > 5.0:
		_hibernate_phase = 2
		_behavior_timer = 0.0
		_hibernate_bubble_shown = false  # 重置标志，供退出阶段一次性守卫
		return
	
	match _hibernate_phase:
		0:  # 进入阶段: 等虹膜收缩完毕 (~1.5s) + 身体回正
			pet.rotation = lerpf(pet.rotation, 0.0, _delta * 3.0)
			if _behavior_timer > 1.5:
				_hibernate_phase = 1
				_behavior_timer = 0.0
				# 收缩到位后显示气泡
				if not _hibernate_bubble_shown:
					_hibernate_bubble_shown = true
					pet.show_local_bubble(_pick(HIBERNATE_ENTER_LINES))
		1:  # 持续阶段: 无限期等待，直到鼠标活动唤醒
			pet.rotation = lerpf(pet.rotation, 0.0, _delta * 3.0)
			if hibernate_style == 0:
				# 挡板呼吸
				pet.eye_behavior._drowsy_target = 0.6 + sin(_behavior_timer * TAU / 5.0) * 0.12
			# 风格 1-2 的动画由 pet.gd 渲染驱动，这里不需要额外逻辑
		2:  # 退出阶段: 恢复 (一次性初始化 + 等待动画)
			if not _hibernate_bubble_shown:
				_hibernate_bubble_shown = true
				pet.eye_behavior.stop_drowsy()
				pet.eye_behavior.forced_look_dir = Vector2.ZERO
				pet.show_local_bubble(_pick(HIBERNATE_WAKE_LINES))
			if _behavior_timer > 0.8:  # 等恢复动画完成
				_finish("hibernate")

# ── 系统自检 ──
# 触发条件: 每 60~90 分钟一次，3小时内最多 3 次

func _enter_scan() -> void:
	pet.show_local_bubble("自检中...")
	pet.eye_behavior.start_scan(func(): _on_scan_complete())

func _update_scan(_delta: float) -> void:
	# 扫描由 eye_behavior 内部驱动，这里只做超时保护
	if _behavior_timer > 4.0:
		pet.eye_behavior.stop_scan()
		_finish("scan")

func _on_scan_complete() -> void:
	# 50% 概率冒出诊断结果
	if randf() < 0.50:
		pet.show_local_bubble(_pick(SCAN_DONE_LINES))
	_finish("scan")

# ── 内部工具 ──

func _cancel_current() -> void:
	if active_behavior == "":
		return
	match active_behavior:
		"hibernate":
			pet.eye_behavior.stop_drowsy()
			pet.eye_behavior.drowsy_amount = 0.0
			pet.eye_behavior.forced_look_dir = Vector2.ZERO
			pet.linear_damp = 0.8
			pet.angular_damp = 1.0
		"scan":
			pet.eye_behavior.stop_scan()
	active_behavior = ""
	_behavior_timer = 0.0

func _finish(behavior: String) -> void:
	if active_behavior == behavior:
		active_behavior = ""
		_behavior_timer = 0.0
		match behavior:
			"scan":
				_scan_clock = 0.0
				_scan_count_3h += 1
				# 下次自检间隔: 60~90 分钟
				_next_scan_interval = randf_range(3600.0, 5400.0)
			"hibernate":
				# 标记本轮离席已休眠，等用户回来(鼠标活动)后才重置
				_hibernate_done = true
		# 恢复 idle 阻尼
		pet.linear_damp = 0.8
		pet.angular_damp = 1.0

func _pick(pool: Array) -> String:
	return pool[randi() % pool.size()]

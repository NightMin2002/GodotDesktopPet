# idle_behaviors.gd — Idle 微行为管理器
# 管理待机状态下的微行为子阶段: 低功耗休眠 / 系统自检 / 深夜模式
# 从 idle.gd 拆分，与 poke_system.gd 同为 RefCounted 轻量挂载
class_name IdleBehaviors
extends RefCounted

var pet: RigidBody2D  # 宿主宠物引用

# ── 状态 ──
var active_behavior: String = ""   # 当前活跃行为: "", "hibernate"
var _behavior_timer := 0.0         # 行为内部计时器

# ── 休眠参数 ──
var _hibernate_phase := 0          # 0=进入, 1=持续, 2=退出
var hibernate_style := 0           # 0=挡板, 1=加载指示, 2=电池图标
var _hibernate_anim_time := 0.0    # 累计动画时间 (跨阶段不重置, 用于平滑旋转)

var _hibernate_bubble_shown := false
var _hibernate_done := false        # 本轮离席已休眠过 (鼠标活动后重置)
var _idle_notice_shown := false     # 白天 5 分钟话术已显示 (鼠标活动后重置)

# ── 深夜模式 (23:00~6:00 强制归位 + 半闭眼) ──
var _nighttime_active := false      # 当前是否处于深夜模式
var _nighttime_check_timer := 0.0   # 系统时间检查节流 (每 30 秒检查一次)
const NIGHTTIME_START_HOUR := 23    # 深夜模式开始 (23:00)
const NIGHTTIME_END_HOUR :=6       # 深夜模式结束 (6:00)
const NIGHTTIME_CHECK_INTERVAL := 30.0  # 时间检查间隔 (秒)



# ── 白天待机分级条件 ──
const MOUSE_IDLE_FOR_NOTICE := 300.0     # 鼠标静止 5 分钟 → 说一句话
const MOUSE_IDLE_FOR_STANDBY := 1800.0   # 鼠标静止 30 分钟 → 进入待机动画

# ── 话术池 ──
const HIBERNATE_ENTER_LINES := [
	"低功耗模式...",
	"进入待机...",
	"节能模式启动...",
	"...休眠中。",
]

const IDLE_NOTICE_LINES := [
	"似乎未检测到活动现象。持续执行监控...",
	"操作员已离席。本机维持观测。",
	"外部输入信号中断。待机监控中。",
	"无活动检测。系统进入低负荷巡航。",
]

const HIBERNATE_WAKE_LINES := [
	"...系统恢复。",
	"低功耗模式结束。",
	"...嗯。重新上线。",
	"待机结束。一切正常。",
]

func _init() -> void:
	# 启动时立即触发首次深夜时段检测 (不等 30 秒)
	_nighttime_check_timer = NIGHTTIME_CHECK_INTERVAL

# ── 主循环 ──

func update(delta: float) -> void:
	# ── 游戏中: 跳过所有微行为 (深夜休眠/白天待机/自检) ──
	# 深夜时钟检测保留运转，游戏结束后能立即感知深夜模式
	if pet.gaming.active:
		if not pet.is_clone:
			_nighttime_check_timer += delta
			if _nighttime_check_timer >= NIGHTTIME_CHECK_INTERVAL:
				_nighttime_check_timer = 0.0
				_check_nighttime()
		return
	# ── 深夜模式自动休眠: 原体和克隆体都需要 (到位后进入半闭眼) ──
	if pet.nighttime_mode and active_behavior == "":
		if pet.current_state_name == "idle" and _is_pet_at_nighttime_slot():
			hibernate_style = 0  # 深夜专属: 机械挡板半闭眼
			trigger("hibernate")
	
	# ── 深夜休眠中: 持续更新 (原体和克隆体都需要) ──
	if pet.nighttime_mode and active_behavior == "hibernate":
		_behavior_timer += delta
		_hibernate_anim_time += delta
		_update_hibernate(delta)
		return
	
	# 分身不运行其余微行为系统 (不需要自检/白天休眠/深夜时钟检测)
	if pet.is_clone:
		return
	
	# 鼠标活动后重置标志 (用户回来了)
	if pet.eye_behavior._mouse_idle_time < 5.0:
		if _hibernate_done:
			_hibernate_done = false
		if _idle_notice_shown:
			_idle_notice_shown = false
	# ── 深夜时段检测 (每 30 秒检查一次系统时间, 仅原体负责发信号) ──
	_nighttime_check_timer += delta
	if _nighttime_check_timer >= NIGHTTIME_CHECK_INTERVAL:
		_nighttime_check_timer = 0.0
		_check_nighttime()
	
	# ── 白天待机分级: 5分钟说话 → 30分钟进入待机动画 ──
	if not _nighttime_active and active_behavior == "" and not _hibernate_done:
		var idle_time = pet.eye_behavior._mouse_idle_time
		# 第一级: 5 分钟 → 说一句话 (不改变视觉)
		if idle_time >= MOUSE_IDLE_FOR_NOTICE and not _idle_notice_shown:
			_idle_notice_shown = true
			pet.show_local_bubble(_pick(IDLE_NOTICE_LINES))
		# 第二级: 30 分钟 → 进入待机动画 (加载旋转器, 不是半闭眼)
		if idle_time >= MOUSE_IDLE_FOR_STANDBY:
			var state = pet.current_state_name
			if state == "idle":
				hibernate_style = 1  # 白天待机: 加载旋转器风格
				trigger("hibernate")
			elif state == "walk":
				pet.transition_to("idle")
				hibernate_style = 1
				trigger("hibernate")
	
	if active_behavior == "":
		return
	_behavior_timer += delta
	if active_behavior == "hibernate":
		_hibernate_anim_time += delta
	if active_behavior == "hibernate":
		_update_hibernate(delta)
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
	

	# 自主活动已迁移到 IdleActivities (定时器驱动, 不在此轮询)
	# 休眠触发已迁移至 update() 的白天分级逻辑 / 深夜模式自动触发
	
	return false

## 强制触发指定行为 (测试菜单用)
func trigger(behavior: String) -> void:
	_cancel_current()
	active_behavior = behavior
	_behavior_timer = 0.0
	match behavior:
		"hibernate": _enter_hibernate()
## 取消当前微行为 (被交互打断)
func cancel() -> void:
	_cancel_current()

# ── 深夜模式检测 ──

## 检查系统时间，判断是否进入/退出深夜模式
func _check_nighttime() -> void:
	var time_dict = Time.get_datetime_dict_from_system()
	var hour: int = time_dict.hour
	var is_night = hour >= NIGHTTIME_START_HOUR or hour < NIGHTTIME_END_HOUR
	
	if is_night and not _nighttime_active:
		_enter_nighttime()
	elif not is_night and _nighttime_active:
		_exit_nighttime()

## 进入深夜模式
func _enter_nighttime() -> void:
	_nighttime_active = true
	print("[DesktopPet] 深夜模式启动 (", NIGHTTIME_START_HOUR, ":00~", NIGHTTIME_END_HOUR, ":00)")
	# 通知所有系统: 深夜模式激活 → pet.nighttime_mode = true + 排队
	EventBus.nighttime_mode_changed.emit(true)
	# 如果当前在自由行动中的 idle/walk 状态，主动发起 retreat
	var state = pet.current_state_name
	if state == "idle" or state == "walk":
		pet.transition_to("retreat")

## 退出深夜模式
func _exit_nighttime() -> void:
	_nighttime_active = false
	print("[DesktopPet] 深夜模式结束，恢复正常行为")
	# 通知所有系统: 深夜模式关闭
	EventBus.nighttime_mode_changed.emit(false)
	# 取消正在进行的深夜休眠
	if active_behavior == "hibernate":
		_cancel_current()
	# 如果用户原本就是自由行动模式，恢复正常行为
	if pet.behavior_mode == 0:
		pet.transition_to("idle")

## 检查宠物是否已到达分配的排队槽位 (用于深夜模式自动休眠判定)
func _is_pet_at_nighttime_slot() -> bool:
	if not pet.has_meta("retreat_target_x"):
		return false
	var target_x: float = pet.get_meta("retreat_target_x")
	return absf(pet.global_position.x - target_x) < 25.0

# ── 休眠 (低功耗模式) ──
# 触发条件: 鼠标静止 5 分钟以上 (用户离开电脑) 或 深夜模式到位

func _enter_hibernate() -> void:
	_hibernate_phase = 0  # 进入阶段
	_hibernate_bubble_shown = false
	_hibernate_anim_time = 0.0
	match hibernate_style:
		0:  # 挡板半闭 (瞳孔保持自由追踪，眯着眼偶尔看你)
			pet.eye_behavior.start_drowsy(0.6)
		1, 2:  # 加载指示 / 电池图标: 抑制眨眼即可
			pet.eye_behavior._drowsy_target = 0.35
	# 增大阻尼，让它"沉下去"
	pet.linear_damp = 3.0
	pet.angular_damp = 5.0
	pet.angular_velocity = 0.0  # 立即停止旋转
	# 锁定旋转 + 设置目标角度, 避免 _process 中赋值 rotation 与物理引擎打架
	var rest_rot = PI if pet.anti_gravity else 0.0
	pet.rotation = rest_rot
	pet.lock_rotation = true

func _update_hibernate(_delta: float) -> void:
	# ── 唤醒条件 ──
	# 深夜模式: 只有退出深夜时段才唤醒 (由 _exit_nighttime 处理)
	# 白天模式: 鼠标恢复活动 → 唤醒 (最低持续5秒，防止调试触发后因刚点菜单立即退出)
	if not pet.nighttime_mode:
		if pet.eye_behavior._mouse_idle_time < 2.0 and _hibernate_phase == 1 and _behavior_timer > 5.0:
			_hibernate_phase = 2
			_behavior_timer = 0.0
			_hibernate_bubble_shown = false  # 重置标志，供退出阶段一次性守卫
			return
	
	match _hibernate_phase:
		0:  # 进入阶段: 等虹膜收缩完毕 (~1.5s)
			# rotation 已在 _enter_hibernate 中锁定, 无需每帧 lerp
			if _behavior_timer > 1.5:
				_hibernate_phase = 1
				_behavior_timer = 0.0
				# 收缩到位后显示气泡
				if not _hibernate_bubble_shown:
					_hibernate_bubble_shown = true
					pet.show_local_bubble(_pick(HIBERNATE_ENTER_LINES))
		1:  # 持续阶段: 无限期等待，直到唤醒条件满足
			# rotation 已锁定, 无需每帧 lerp
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
			pet.lock_rotation = false  # 解锁旋转

	active_behavior = ""
	_behavior_timer = 0.0

func _finish(behavior: String) -> void:
	if active_behavior == behavior:
		active_behavior = ""
		_behavior_timer = 0.0
		match behavior:
			"hibernate":
				# 标记本轮离席已休眠，等用户回来(鼠标活动)后才重置
				_hibernate_done = true
		# 恢复 idle 阻尼
		pet.linear_damp = 0.8
		pet.angular_damp = 1.0

func _pick(pool: Array) -> String:
	return pool[randi() % pool.size()]

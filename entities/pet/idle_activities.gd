# idle_activities.gd — 自主活动调度器 (菜单名: 运行功耗)
# 管理 idle 状态下的定时自主活动: 空间跳跃 / 浏览全息屏 / 自玩游戏
# 定时器驱动，到时间从池子里随机抽一个执行。三档: 待机(关闭) / 节能(偶尔) / 性能(频繁)
class_name IdleActivities
extends RefCounted

var pet: RigidBody2D  # 宿主宠物引用

# ── 活动池 ──
# 每个条目: {id: String, weight: float, action: Callable}
var _pool: Array[Dictionary] = []

# ── 调度参数 ──
# mode: 0=关闭, 1=偶尔(8~12分钟), 2=频繁(30~60秒 测试用)
var mode: int = 1:
	set(v):
		mode = v
		_elapsed = 0.0
		_roll_next_interval()

var _elapsed: float = 0.0         # 距上次活动的累计秒数
var _next_interval: float = 0.0   # 下次触发的随机间隔

# 各模式对应的间隔范围 (秒)  [min, max]
const INTERVAL_RANGE := {
	1: [480.0, 720.0],   # 偶尔: 8~12 分钟
	2: [60.0, 120.0],    # 频繁: 1~2 分钟
}

func _init() -> void:
	# 注册内置活动 (weight 决定抽中概率)
	register("free_roam", 3.0, _do_free_roam)     # 移动行为, 常见 (50%)
	register("holo_browse", 2.0, _do_holo_browse)  # 看屏幕, 较常见 (33%)
	register("auto_game", 1.0, _do_auto_game)      # 稀有事件 (17%)
	_roll_next_interval()

# ── 公开接口 ──

## 注册活动到池子
func register(id: String, weight: float, action: Callable) -> void:
	_pool.append({id = id, weight = weight, action = action})

## 每帧调用 (由 pet._process 驱动)
func update(delta: float) -> void:
	if mode == 0:
		return
	# 克隆体不触发
	if pet.is_clone:
		return
	# 只在 idle 状态下计时
	if pet.current_state_name != "idle":
		return
	# 前置条件: 自由行动 + 非深夜 + 非游戏中 + 非空间跳跃中
	if pet.behavior_mode != 0 or pet.nighttime_mode:
		return
	if pet.gaming.active or pet._roam_active:
		return
	# 微行为活跃时不触发 (休眠/自检中)
	if pet.idle_behaviors.is_active():
		return

	_elapsed += delta
	if _elapsed >= _next_interval:
		_elapsed = 0.0
		_roll_next_interval()
		_execute_random()

## 设置模式并持久化 (菜单用)
func set_mode_and_save(new_mode: int) -> void:
	mode = clampi(new_mode, 0, 2)  # setter 会自动重置计时器
	SettingsManager.set_int("auto_activity", mode)

# ── 内部 ──

## 随机下次间隔
func _roll_next_interval() -> void:
	var r = INTERVAL_RANGE.get(mode, [9999.0, 9999.0])
	_next_interval = randf_range(r[0], r[1])

## 从池子抽一个可执行的活动并执行
func _execute_random() -> void:
	var picked = _weighted_pick()
	if not picked.is_empty():
		print("[IdleActivities] 触发: ", picked.id, " (间隔 %.0fs)" % _next_interval)
		picked.action.call()

## 检查特定活动的前置条件
func _can_run(id: String) -> bool:
	match id:
		"free_roam":
			return pet.free_roam_enabled and not pet._roam_active
		"auto_game":
			return not pet.gaming.active
		"holo_browse":
			return not pet.gaming.active and not pet.holo_screen.visible
	return true

## 按权重随机抽取 (只从满足前置条件的活动中选)
func _weighted_pick() -> Dictionary:
	var available: Array[Dictionary] = []
	var total := 0.0
	for entry in _pool:
		if _can_run(entry.id):
			available.append(entry)
			total += entry.weight
	if available.is_empty():
		return {}
	var roll = randf() * total
	var cumulative := 0.0
	for entry in available:
		cumulative += entry.weight
		if roll <= cumulative:
			return entry
	return available.back()

# ── 活动实现 ──

func _do_free_roam() -> void:
	pet._start_free_roam()

func _do_auto_game() -> void:
	var games = ["2048", "minesweeper", "snake", "tetris"]
	EventBus.launch_game_auto.emit(games[randi() % games.size()])

func _do_holo_browse() -> void:
	# 决定屏幕方向 (和游戏态一样的逻辑)
	var screen_side: float
	if pet.global_position.x > pet.boundary_size.x * 0.5:
		screen_side = -1.0
	else:
		screen_side = 1.0
	# 显示 15~25 秒
	var duration = randf_range(15.0, 25.0)
	# 从适合自发触发的终端模式中随机抽一个
	# 排除: DONE(需配合操作) / ERROR(无故报错不合理) / WARNING(同上) / ALARM(有特定触发场景)
	var mode_pool: Array[Callable] = [
		func(): pet.holo_screen.show_idle(screen_side, duration),
		func(): pet.holo_screen.show_loading("SYS.CHECK", screen_side, duration),
		func(): pet.holo_screen.show_battery(screen_side, duration),
		func(): pet.holo_screen.show_mail(screen_side, duration),
		func(): pet.holo_screen.show_query(screen_side, duration),
		func(): pet.holo_screen.show_cleanup(screen_side, duration),
		func(): pet.holo_screen.show_globe(screen_side, duration),
		func(): pet.holo_screen.show_sync(screen_side, duration),
		func(): pet.holo_screen.show_lock(screen_side, duration),
	]
	mode_pool[randi() % mode_pool.size()].call()

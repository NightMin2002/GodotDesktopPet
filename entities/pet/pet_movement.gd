# pet_movement.gd — 移动方向控制器 (RefCounted)
# 统一管理移动相关的瞳孔方向生命周期:
#   IDLE → LOOK_AHEAD (先看方向) → ACTIVE (运动中) → HOLD (落地保持) → IDLE
#
# 本控制器不直接写 forced_look_dir，只维护 direction 和 phase。
# 最终方向由 pet.gd 的优先级决议统一写入 eye_behavior.forced_look_dir。
class_name PetMovement
extends RefCounted

enum Phase { IDLE, LOOK_AHEAD, ACTIVE, HOLD }

var pet: RigidBody2D  # 由 pet.gd 注入

var phase: Phase = Phase.IDLE
var direction: Vector2 = Vector2.ZERO   # 当前移动方向 (归一化)
var _timer: float = 0.0
var _on_ready: Callable                 # LOOK_AHEAD 到期后的回调

const LOOK_AHEAD_TIME := 0.3   # 先看方向再行动的缓冲时长
const LOOK_HOLD_TIME := 0.3    # 落地后保持看方向的时长

## 是否有活跃的方向 (LOOK_AHEAD / ACTIVE / HOLD 任一阶段)
var is_active: bool:
	get: return phase != Phase.IDLE

## 是否在缓冲期 (状态应跳过物理)
var in_look_ahead: bool:
	get: return phase == Phase.LOOK_AHEAD

## 开始移动: 设方向 + 进入缓冲期
## on_ready_callback: 缓冲到期后自动调用 (用于施加冲量等)
func start(dir: Vector2, on_ready_callback: Callable = Callable()) -> void:
	direction = dir.normalized() if dir.length() > 0 else dir
	phase = Phase.LOOK_AHEAD
	_timer = LOOK_AHEAD_TIME
	_on_ready = on_ready_callback

## 直接激活 (跳过缓冲)
## 用于已有自己节奏的场景 (free_roam 的 await 蓄力, 持续滚动中切换方向等)
func activate(dir: Vector2) -> void:
	direction = dir.normalized() if dir.length() > 0 else dir
	phase = Phase.ACTIVE
	_timer = 0.0
	_on_ready = Callable()

## 运动结束: 进入 HOLD 阶段 (保持看方向 0.3s 后自动 IDLE)
func finish() -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.HOLD
	_timer = LOOK_HOLD_TIME
	_on_ready = Callable()

## 强制取消: 立刻清方向回 IDLE (被拖拽 / 休眠唤醒 / 游戏启动等打断)
func cancel() -> void:
	phase = Phase.IDLE
	direction = Vector2.ZERO
	_timer = 0.0
	_on_ready = Callable()

## 每帧更新 (由 pet.gd _process 调用, 在方向决议之前)
func update(delta: float) -> void:
	match phase:
		Phase.LOOK_AHEAD:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.ACTIVE
				if _on_ready.is_valid():
					var cb = _on_ready
					_on_ready = Callable()
					cb.call()
		Phase.HOLD:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.IDLE
				direction = Vector2.ZERO

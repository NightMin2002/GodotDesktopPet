# base_game.gd — 小游戏接口基类
# 所有游戏包中的游戏脚本必须继承此类，实现标准接口
# 生命周期: start() → [游戏进行中] → game_finished 信号 → cleanup()
class_name BaseGame extends RefCounted

enum Result { WIN, LOSE, DRAW }

## 游戏结束信号 (GameManager 监听)
signal game_finished(result: Result)

# ── 元数据 (子类覆写) ──

func get_game_id() -> String:
	return ""

func get_game_name() -> String:
	return ""

func get_game_desc() -> String:
	return ""

# ── 生命周期 (子类覆写) ──

## 启动游戏: host 是 GameManager 的 CanvasLayer, pet 是宠物原体引用
func start(host: CanvasLayer, pet: Node2D) -> void:
	pass

## 清理资源: 移除所有 UI 节点、断开信号
func cleanup() -> void:
	pass

## 在宠物身旁绘制全息迷你屏 (子类覆写)
## pet 是宠物 CanvasItem (用其 draw_* 方法), rect 是绘制区域
func draw_hologram(pet_ci: CanvasItem, rect: Rect2) -> void:
	pass

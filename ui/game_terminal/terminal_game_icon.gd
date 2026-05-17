# terminal_game_icon.gd — 终端游戏大厅图标基类
# 每个游戏在自己的文件夹下提供 icon.gd extends TerminalGameIcon
# 骨架在构建大厅卡片时自动加载并实例化
class_name TerminalGameIcon extends Control

## 由骨架设置 (可选读取)
var game_id: String = ""

## 是否被悬停 (由骨架卡片 hover 事件驱动)
var _hovered: bool = false

## 内部时钟
var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

# ══════════════════════════════════════════════
#  便利方法 (子类可用)
# ══════════════════════════════════════════════

## 当前 UI 主题色
func hue() -> float:
	return EventBus.ui_hue

## 基于 hover 状态的透明度 [base, highlight]
func alphas() -> Array:
	return [0.55 if _hovered else 0.35, 0.9 if _hovered else 0.6]

## 主题色线条颜色
func line_color() -> Color:
	return Color.from_hsv(hue(), 0.4, 0.75, alphas()[0])

## 主题色强调颜色
func accent_color() -> Color:
	return Color.from_hsv(hue(), 0.55, 0.9, alphas()[1])

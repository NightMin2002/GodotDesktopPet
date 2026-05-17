# terminal_game_base.gd — 终端游戏基类
# 所有终端原生游戏的公共接口定义
# 子类放在 ui/game_terminal/games/<game_id>/game.gd
class_name TerminalGameBase extends Control

signal game_started
signal game_over(result: int)  # 0=胜, 1=负, 2=平

# ══════════════════════════════════════════════
#  元数据 (子类必须覆写)
# ══════════════════════════════════════════════

## 唯一标识 (用于战绩持久化 key、文件夹名等)
func get_game_id() -> String: return ""

## 显示名称 (大厅卡片标题、终端标题栏)
func get_game_name() -> String: return ""

## 简短描述 (大厅卡片副标题)
func get_game_desc() -> String: return ""

## 是否支持 AI 自玩 (大厅卡片是否显示"委托推演"按钮)
func supports_auto_play() -> bool: return false

# ══════════════════════════════════════════════
#  生命周期 (子类覆写)
# ══════════════════════════════════════════════

## 骨架调用: 构建 UI 并启动首局
func build() -> void: pass

## 重开一局 (结算覆盖层"再来一局"按钮回调)
func start_game() -> void: pass

# ══════════════════════════════════════════════
#  HUD 协议 (可选覆写)
# ══════════════════════════════════════════════

## 返回 HUD 数据槽位
## 格式: { "slot_id": { "label": "显示名", "value": "值", "color": Color } }
func get_hud_data() -> Dictionary: return {}

## 最佳分数 (供骨架持久化最高分)
func get_best_score() -> int: return 0

# ══════════════════════════════════════════════
#  AI 自玩 (可选覆写, supports_auto_play()=true 时需实现)
# ══════════════════════════════════════════════

## 骨架 Timer 每 0.4s 调用一次
func auto_play_step() -> void: pass

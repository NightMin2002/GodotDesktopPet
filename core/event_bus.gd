# event_bus.gd — 全局事件总线 (Autoload 单例)
# 所有模块间通信都通过这里中转，避免强耦合
extends Node

# ── 拖拽相关 ──
signal drag_started
signal drag_ended

# ── 状态变化 ──
signal pet_state_changed(old_state: String, new_state: String)


# ── UI 相关 ──
signal show_context_menu(target_node: Node2D)
signal context_menu_toggled(is_open: bool)
signal setting_toggled(setting_id: String, is_on: bool)

# ── 系统功能 ──
signal show_reminder_bubble(message: String)
signal force_show_bubble(message: String)  # 强制显示: 中断当前气泡+清空队列+立即播放
signal show_todo_panel                                # 打开/关闭待办事项面板
signal show_pet_profile                               # 打开/关闭装置终端面板
signal show_pet_profile_reminder                      # 打开装置终端 + 切到定时提醒 Tab
signal todo_count_changed(pending: int, total: int)   # 待办数量变化 (供宠物主动行为用)
signal trigger_todo_prompt                            # 调试: 强制触发待办主动提醒
signal trigger_input_report                           # 调试: 强制生成键鼠输入报告 (写入机体记录)
signal panel_focus_requested(panel_id: String)          # 面板置顶请求 (点击面板→置顶, 其他面板降级)
signal trigger_window_report                          # 调试: 强制生成窗口活动报告 (写入机体记录)

# ── 窗口交互模式 ──
signal window_mode_changed(mode: int)  # 0=FREE, 1=CONFINED, 2=REPELLED

# ── 行为指令 ──
signal behavior_mode_changed(mode: int)  # 0=FREE(自由行动), 1=QUIET(安静待命)
signal trigger_idle_behavior(behavior: String)  # 调试: 强制触发 idle 微行为
signal trigger_free_roam  # 调试: 触发自由移动 (透明踏板跳跃)
signal nighttime_mode_changed(active: bool)  # 深夜模式: 23:00~6:00 自动归位+半闭眼

signal trigger_squash_test(style: int)  # 弹性形变测试: -1=关闭, 0=果冻, 1=弹力球, 2=水滴

# ── 克隆系统 ──
signal clone_pet(source: Node2D)  # 请求从原体克隆一个分身
signal dismiss_clones  # 一键遣散所有分身

# ── 颜色系统 ──
signal pet_color_changed(pet_index: int, hue: float, sat: float, val: float)
signal ui_theme_changed(hue: float)
signal appearance_changed(style: int)
signal show_platform_style_panel

# ── 游戏系统 ──
signal show_game_terminal  # 打开/关闭游戏终端面板
signal pet_gaming_changed(active: bool, game: RefCounted)  # 游戏启停时通知宠物
signal show_memo_popup  # 全局热键: 弹出快速备忘录弹窗
signal show_file_search  # 打开/关闭文件检索终端面板

## UI 主题色 Hue (全局可读，默认 0.537 ≈ 当前青色)
var ui_hue: float = 0.537

## 已打开面板的矩形追踪 (面板层级管理用, panel_id -> { "rect": Rect2, "layer": int })
var _active_panel_rects: Dictionary = {}

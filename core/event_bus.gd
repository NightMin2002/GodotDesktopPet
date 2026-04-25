# event_bus.gd — 全局事件总线 (Autoload 单例)
# 所有模块间通信都通过这里中转，避免强耦合
extends Node

# ── 拖拽相关 ──
signal drag_started
signal drag_ended

# ── 状态变化 ──
signal pet_state_changed(old_state: String, new_state: String)

# ── IPC 相关 (预留) ──
signal ipc_message_received(data: Dictionary)
signal task_completed(task_name: String)

# ── UI 相关 ──
signal show_context_menu(target_node: Node2D)
signal context_menu_toggled(is_open: bool)
signal setting_toggled(setting_id: String, is_on: bool)

# ── 系统功能 ──
signal autostart_toggled(is_on: bool)
signal show_reminder_bubble(message: String)
signal force_show_bubble(message: String)  # 强制显示: 中断当前气泡+清空队列+立即播放
signal show_reminder_panel

# ── 窗口交互模式 ──
signal window_mode_changed(mode: int)  # 0=FREE, 1=CONFINED, 2=REPELLED

# ── 行为指令 ──
signal behavior_mode_changed(mode: int)  # 0=FREE(自由行动), 1=QUIET(安静待命)

# ── 克隆系统 ──
signal clone_pet(source: Node2D)  # 请求从原体克隆一个分身
signal dismiss_clones  # 一键遣散所有分身

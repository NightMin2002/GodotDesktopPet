# Desktop Pet — AI 开发上下文

> 将此文件发送给 AI 助手，即可让它快速理解项目全貌。

---

## 项目概述

基于 **Godot 4.x + GDScript** 的桌面透明物理宠物。宠物以 RigidBody2D 运行在全屏透明窗口中，通过弹簧力物理实现拖拽交互，使用有限状态机 (FSM) 管理行为。通过 C# 层调用 Win32 API 实现桌面窗口感知与进程级优化。

## 技术栈

- **引擎**: Godot 4.6+ (Compatibility 渲染器 / OpenGL)
- **语言**: GDScript (主逻辑) + C# (Win32 系统底层桥接)
- **物理**: Godot 内置 2D 物理引擎 (120 ticks/s)
- **渲染**: 120fps 目标帧率，按需 queue_redraw
- **持久化**: ConfigFile (user://settings.cfg)
- **架构**: 双进程松耦合 (宠物端 Godot + 笔记端 Vue 3，目前仅宠物端)

## 目录结构

```
project.godot              # 项目配置 (透明窗口 + Compatibility 渲染器)
main.tscn / main.gd        # 启动场景: 窗口设置 + 边界墙 + 宠物生成 + 鼠标穿透 + 幽灵墙系统 + 窗口交互三模式
core/
  event_bus.gd              # Autoload 全局事件总线
  settings_manager.gd       # Autoload 持久化设置管理器 (ConfigFile)
ui/
  context_menu.tscn/gd      # 右键全息追踪面板 (开关 + 窗口模式切换含说明 + 提醒入口)
  reminder_panel.gd         # 提醒管理面板 (增删提醒 + 定时检查 + 测试触发)
  reminder_bubble.gd        # 气泡通知 (宠物头顶弹出 + overlay_rect 穿透扩展)
  floating_text/            # 浮动文字特效 (预留)
entities/pet/
  pet.tscn                  # RigidBody2D + CircleShape2D (r=30)
  pet.gd                    # 宠物控制器: FSM + 输入 + 视觉渲染 (科幻单眼 + 虹膜眨眼)
  eye_behavior.gd           # 瞳孔行为控制器: 鼠标追踪 → 闲置游走 + 机械虹膜眨眼
  states/
    state.gd                # PetState 基类 (RefCounted)
    idle.gd                 # StateIdle: 短暂待机, 60%→Walk / 40%→Jump
    walk.gd                 # StateWalk: 水平力行走, 碰边转向
    drag.gd                 # StateDrag: 弹簧力跟随鼠标
    fall.gd                 # StateFall: 自由落体
    jump.gd                 # StateJump: 高能弹跳
interop/
  WindowsManager.cs         # Win32 API 桥接: 窗口枚举 + 任务栏隐藏 + 进程提权 + 开机自启动
docs/                       # 项目文档
```

## 核心架构

### 1. 状态机 (FSM)
- 状态继承 `PetState` (RefCounted)，不是 Node
- pet.gd 持有 `states: Dictionary`，通过 `transition_to("state_name")` 切换
- 每个状态实现 5 个接口: `enter()`, `exit()`, `process()`, `physics_process()`, `input()`

### 2. 物理系统
- 宠物是 `RigidBody2D`，**禁止直接修改 position**，只能用力/冲量
- 拖拽用弹簧力公式: `F = stiffness * displacement - damping * velocity`
- 边界墙是 4 个 StaticBody2D (400px 厚)
- 引擎 120 ticks/s 物理 + 120fps 渲染

### 3. 透明窗口 + 鼠标穿透
- 全屏无边框透明窗口覆盖可用屏幕区域
- `DisplayServer.window_set_mouse_passthrough()` = DWM 可见区域 (不只是鼠标)
- **DWM 限流优化**: 穿透区域刷新 ~60hz (8px 空间量化 + 16ms 时间节流)
- 菜单/面板打开时全屏穿透，关闭动画结束后才恢复 (防淡出裁剪)
- 气泡通知通过 `pet.overlay_rect` 将自身区域注册到穿透多边形

### 4. 幽灵墙系统 (Win32 窗口感知)
- C# 层 `EnumWindows` 按 Z-Order 获取桌面窗口矩形
- GDScript 每 0.1s 同步生成 `StaticBody2D` 幽灵碰撞墙
- **分段裁剪算法**: 踏板从完整宽度扣除被更高层窗口覆盖的区间
- **最大化窗口过滤**: 宽≥屏幕90%且高≥屏幕85% 的窗口自动跳过 (避免全屏干扰)

### 4.5 窗口交互三模式
- **自由漫游 (FREE)**: 单向踏板 (顶/底)，宠物自由行走
- **窗口封闭 (CONFINED)**: 宠物被困在当前窗口内
  - 重叠窗口迭代合并 → bounding box 四面封闭墙
  - **Sweep-Line 虚空填充**: 沿 X 轴切片，对每个切片找未被窗口覆盖的 Y 区间 → 生成物理屏障
  - `confined_anchor_rect` 保存原始目标窗口用于跨帧匹配
  - 拖拽状态 clamp 到 confined_rect
- **窗口排斥 (REPELLED)**: 宠物无法进入窗口，但可以出来
  - `CollisionShape2D.rotation` 旋转法线方向 → 单向碰撞
  - 顶(0°) 底(π) 左(-π/2) 右(+π/2)
  - 旋转后 RectangleShape2D 宽高互换以保持墙体形状
- 设置持久化至 `settings.cfg` 的 `window_mode`
- 右键菜单三态循环切换，含模式说明文字

### 5. 眼球行为系统 (EyeBehavior)
- RefCounted 管理瞳孔追踪/游走/眨眼三种行为
- 鼠标活跃: 12x 速率锁定 → 鼠标静止 2.5s: 2x 好奇游走
- 关闭追踪: 始终游走（不会冻结）
- 快门式眨眼: 每 2.5~7s，20% 概率连眨

### 6. 设置持久化
- `SettingsManager` (Autoload) 基于 ConfigFile
- pet.gd 启动时直接读取 SettingsManager（不依赖信号时序）
- 右键菜单按钮只更新显示 + 发信号给正在运行的宠物

### 7. 提醒系统
- 提醒存储在 ConfigFile 中，格式: `{time: "09:00", msg: "...", on: true}`
- 每 10 秒检查当前时间匹配，跨天自动重置已触发记录
- 气泡通知在宠物头顶弹出，弹簧动画 + 6s 淡出上飘 + overlay_rect 穿透扩展

### 8. 系统级集成
- `WS_EX_TOOLWINDOW` 隐藏任务栏图标 (窗口隐藏 → 设置 → HideFromTaskbar → 显示)
- `StatusIndicator` 驻留系统托盘
- `SetPriorityClass(ABOVE_NORMAL)` 进程优先级提升
- 注册表 `HKCU\Run` 开机自启动 (可在右键菜单开关)

### 9. 通信
- 模块间通过 `EventBus` (Autoload) 信号解耦
- 信号: `drag_started/ended`, `pet_state_changed`, `show_context_menu`, `context_menu_toggled`, `setting_toggled`, `show_reminder_panel`, `show_reminder_bubble`, `autostart_toggled`, `window_mode_changed`

## 当前状态
- ✅ 透明窗口 + 鼠标穿透 (DWM 限流 + 穿透 = 渲染区域)
- ✅ 物理掉落 + 弹跳 + 滚轴驱动 + 边界反弹
- ✅ 弹簧力拖拽
- ✅ 5 状态 FSM (Idle/Walk/Drag/Fall/Jump)
- ✅ 右键全息面板 (眼球追踪 + 冲击波 + 自启动 + 提醒入口)
- ✅ 科幻单眼 (追踪 → 游走 + 机械虹膜眨眼)
- ✅ Win32 幽灵墙 (分段裁剪 + Z-Order 遮挡)
- ✅ 窗口交互三模式 (自由漫游 / 窗口封闭+虚空填充 / 窗口排斥+单向碰撞)
- ✅ 最大化窗口自动过滤
- ✅ 隐秘常驻 (任务栏隐藏 + 系统托盘 + 进程提权)
- ✅ 120fps 性能优化 (DWM 限流 + 按需重绘 + 进程提权)
- ✅ 设置持久化 (ConfigFile + 跨重启恢复)
- ✅ 开机自启动 (注册表 + 右键菜单开关)
- ✅ 定时提醒系统 (自定义时间 + 气泡通知)
- ❌ IPC 联动 (WebSocket 预留)
- ❌ 音效系统 / 存档系统
- ❌ 睡眠/情绪等高级行为

## 开发规则
1. 单文件不超过 200 行，超过就拆分
2. 新行为 = 新状态文件
3. 模块间用 EventBus 通信，禁止跨模块直接 get_node
4. 物理体只用 apply_force / apply_impulse，不改 position
5. 边界定位用 `get_viewport_rect().size`
6. 淡出动画结束后才发 `context_menu_toggled(false)`，防 DWM 裁剪
7. 气泡等覆盖层通过 `pet.overlay_rect` 注册到穿透多边形

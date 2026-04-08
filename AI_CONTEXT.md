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
- **架构**: 双进程松耦合 (宠物端 Godot + 笔记端 Vue 3，目前仅宠物端)

## 目录结构

```
project.godot              # 项目配置 (透明窗口 + Compatibility 渲染器)
main.tscn / main.gd        # 启动场景: 窗口设置 + 边界墙 + 宠物生成 + 鼠标穿透 + 幽灵墙系统
core/
  event_bus.gd              # Autoload 全局事件总线
ui/
  context_menu.tscn/gd      # 右键全息追踪面板 (眼球追踪开关 + 撞击特效开关)
entities/pet/
  pet.tscn                  # RigidBody2D + CircleShape2D (r=30)
  pet.gd                    # 宠物控制器: FSM + 输入 + 视觉渲染 (科幻单眼 + 虹膜眨眼)
  eye_behavior.gd           # 瞳孔行为控制器: 鼠标追踪 → 闲置游走过渡 + 机械虹膜眨眼
  states/
    state.gd                # PetState 基类 (RefCounted): enter/exit/process/physics_process/input
    idle.gd                 # StateIdle: 短暂(0.3~1.5s)待机, 60%→Walk / 40%→Jump
    walk.gd                 # StateWalk: 水平力行走, 碰边转向, 1.5~4s后→Idle
    drag.gd                 # StateDrag: 弹簧力 F=kx-cv 跟随鼠标, 降低重力
    fall.gd                 # StateFall: 自由落体, 速度<15持续0.3s→Idle
    jump.gd                 # StateJump: 暴走弹射, 巨大上冲量+万级扭矩
interop/
  WindowsManager.cs         # Win32 API 桥接: 窗口枚举 + 任务栏隐藏 + 进程优先级提升
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
- 启用了 CCD (CCD_MODE_CAST_RAY) 防穿墙
- 边界墙是 4 个 StaticBody2D (400px 厚)，用视口坐标定位
- 引擎物理帧率 120 ticks/s，与渲染帧率 120fps 对齐

### 3. 透明窗口 + 鼠标穿透
- 全屏无边框透明窗口覆盖可用屏幕区域
- `DisplayServer.window_set_mouse_passthrough()` 管理点击穿透多边形
- 正常时穿透多边形只覆盖宠物周围 50px，拖拽/菜单时扩展到全屏
- **DWM 限流优化**: 穿透区域刷新限制在 ~60hz (8px 空间量化 + 16ms 时间节流)

### 4. 幽灵墙系统 (Win32 窗口感知)
- C# 层 `EnumWindows` 按 Z-Order 从高到低获取桌面窗口矩形
- GDScript 侧每 0.1s 同步生成 `StaticBody2D` 幽灵碰撞墙
- **分段裁剪算法**: 每条踏板 (顶部/底部) 从完整宽度出发，扣除被更高层窗口覆盖的区间
- 每条踏板最多拆为 3 个独立碰撞分段 (一个窗口上方/下方各 3 个)
- 宽度 < 30px 的碎片分段自动丢弃

### 5. 眼球行为系统 (EyeBehavior)
- `EyeBehavior` (RefCounted) 管理瞳孔追踪/游走/眨眼三种行为
- 鼠标活跃: 12x 速率紧锁追踪 → 鼠标静止 2.5s: 2x 慢速好奇游走
- 关闭追踪开关: 始终保持好奇游走模式 (不会冻结)
- 机械虹膜快门式眨眼: 每 2.5~7s，内圈光环收缩至 5%，20% 概率连眨

### 6. 通信
- 模块间通过 `EventBus` (Autoload 单例) 的信号解耦
- 已定义信号: `drag_started`, `drag_ended`, `pet_state_changed`
- UI 信号: `show_context_menu`, `context_menu_toggled`, `setting_toggled`
- 预留信号: `ipc_message_received`, `task_completed`

### 7. 系统级集成
- `WS_EX_TOOLWINDOW` 隐藏任务栏图标
- `StatusIndicator` 驻留系统托盘
- `SetPriorityClass(ABOVE_NORMAL)` 进程优先级提升，对抗游戏资源抢占

## 当前状态
- ✅ 透明窗口 + 鼠标穿透 (DWM 限流 + 8px 空间量化)
- ✅ 物理掉落 + 弹跳 + 滚轴驱动 + 边界反弹
- ✅ 弹簧力拖拽
- ✅ 5 状态 FSM (Idle/Walk/Drag/Fall/Jump)
- ✅ 实时定位全息 HUD 设置面板 (眼球追踪开关 + 撞击特效开关)
- ✅ 科幻单眼视觉层 (鼠标追踪 → 闲置游走 + 机械虹膜眨眼)
- ✅ Win32 幽灵墙系统 (分段裁剪碰撞 + Z-Order 遮挡检测)
- ✅ 隐秘常驻系统 (任务栏隐藏 + 系统托盘 + 进程提权)
- ✅ 120fps 性能优化 (DWM 限流 + 按需重绘 + 进程提权)
- ❌ IPC 联动 (WebSocket 预留)
- ❌ 音效系统
- ❌ 存档系统
- ❌ 睡眠/情绪等高级行为

## 开发规则
1. 单文件不超过 200 行，超过就拆分
2. 新行为 = 新状态文件，不要塞进已有状态
3. 模块间用 EventBus 通信，禁止跨模块直接 get_node()
4. 物理体只用 apply_force / apply_impulse，不改 position
5. 边界定位用 `get_viewport_rect().size`，不用屏幕像素坐标 (防 Windows 缩放问题)
6. 眼球行为逻辑放在 `EyeBehavior` (RefCounted)，_draw() 渲染留在 pet.gd

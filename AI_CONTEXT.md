# Desktop Pet — AI 开发上下文

> 将此文件发送给 AI 助手，即可让它快速理解项目全貌。

---

## 项目概述

基于 **Godot 4.x + GDScript** 的桌面透明物理宠物。宠物以 RigidBody2D 运行在全屏透明窗口中，通过弹簧力物理实现拖拽交互，使用有限状态机 (FSM) 管理行为。

## 技术栈

- **引擎**: Godot 4.6+ (Compatibility 渲染器 / OpenGL)
- **语言**: GDScript (类 Python，Godot 原生)
- **物理**: Godot 内置 2D 物理引擎
- **架构**: 双进程松耦合 (宠物端 Godot + 笔记端 Vue 3，目前仅宠物端)

## 目录结构

```
project.godot              # 项目配置 (透明窗口 + Compatibility 渲染器)
main.tscn / main.gd        # 启动场景: 窗口设置 + 边界墙 + 宠物生成 + 鼠标穿透
core/
  event_bus.gd              # Autoload 全局事件总线
ui/
  context_menu.tscn/gd      # 右键控制全息追踪面板
entities/pet/
  pet.tscn                  # RigidBody2D + CircleShape2D (r=30)
  pet.gd                    # 宠物控制器: FSM + 输入 + _draw() 科幻单眼渲染
  states/
    state.gd                # PetState 基类 (RefCounted): enter/exit/process/physics_process/input
    idle.gd                 # StateIdle: 呼吸动画, 2~5s后→Walk
    walk.gd                 # StateWalk: 水平力行走, 碰边转向, 1.5~4s后→Idle
    drag.gd                 # StateDrag: 弹簧力 F=kx-cv 跟随鼠标, 降低重力
    fall.gd                 # StateFall: 自由落体, 速度<15持续0.3s→Idle
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

### 3. 透明窗口
- 全屏无边框透明窗口覆盖可用屏幕区域
- `DisplayServer.window_set_mouse_passthrough()` 管理点击穿透多边形
- 正常时穿透多边形只覆盖宠物周围 50px，拖拽时扩展到全屏

### 4. 通信
- 模块间通过 `EventBus` (Autoload 单例) 的信号解耦
- 已定义信号: `drag_started`, `drag_ended`, `pet_state_changed`
- 预留信号: `ipc_message_received`, `task_completed`

## 当前状态
- ✅ 透明窗口 + 鼠标穿透 (包含边缘区域收缩防锁死逻辑)
- ✅ 物理掉落 + 弹跳 + 滚轴驱动 + 边界反弹
- ✅ 弹簧力拖拽
- ✅ 4 状态 FSM (Idle/Walk/Drag/Fall)
- ✅ 实时定位全息 HUD 设置面板 (极客像素风)
- ✅ 科幻单眼视觉层 (鼠标瞳孔追踪体系)
- ❌ IPC 联动 (WebSocket 预留)
- ❌ 音效系统
- ❌ 存档系统

## 开发规则
1. 单文件不超过 200 行，超过就拆分
2. 新行为 = 新状态文件，不要塞进已有状态
3. 模块间用 EventBus 通信，禁止跨模块直接 get_node()
4. 物理体只用 apply_force / apply_impulse，不改 position
5. 边界定位用 `get_viewport_rect().size`，不用屏幕像素坐标 (防 Windows 缩放问题)

# 🐾 Desktop Pet — 桌面物理宠物

基于 Godot 4.x 的桌面透明宠物，拥有"肉弹"物理手感。

## 快速开始

### 1. 下载 Godot

前往官网下载 **Godot 4.6.2** (Standard 版即可，不需要 .NET 版)：
- https://godotengine.org/download/windows/
- 选择 **Standard** 下载，解压即用，无需安装

### 2. 打开项目

1. 启动 Godot
2. 在项目管理器中点击 **Import**
3. 浏览到本目录，选择 `project.godot`
4. 点击 **Import & Edit**

### 3. 验证设置

首次打开项目后，请在编辑器中确认以下设置 (Project → Project Settings)：

| 设置路径 | 值 |
|---------|---|
| 显示 → 窗口 → 大小 → 无边框 (Borderless) | ✅ 开 |
| 显示 → 窗口 → 大小 → 透明 (Transparent) | ✅ 开 |
| 显示 → 窗口 → 大小 → 始终在最前面 (Always On Top) | ✅ 开 |
| 显示 → 窗口 → 逐像素透明度 → 允许 (Allowed) | ✅ 开 |
| 显示 → 窗口 → 子窗口 → 嵌入子窗口 (Embed Subwindows) | ❌ 关 |
| 渲染 → 视口 → 透明背景 (Transparent Background) | ✅ 开 |

> ⚠️ 渲染器应为 **Compatibility (GL)**，如不是，在编辑器右上角切换。

### 4. 运行

按 **F5** 或点击右上角 ▶ 按钮运行项目。

## 操作方式

| 操作 | 效果 |
|------|------|
| 鼠标左键按住宠物 | 弹簧拖拽 (松开后会被甩飞) |
| 什么都不做 | 宠物会自动走动、发呆 |

## 项目结构

```
├── project.godot          # 项目配置
├── main.tscn / main.gd    # 启动场景 (窗口+边界+宠物)
├── core/
│   └── event_bus.gd       # 全局事件总线
└── entities/pet/
    ├── pet.tscn / pet.gd  # 宠物本体 (RigidBody2D)
    └── states/
        ├── state.gd       # 状态基类
        ├── idle.gd        # 待机: 呼吸动画 → 随机走动
        ├── walk.gd        # 行走: 水平移动 → 回到待机
        ├── drag.gd        # 拖拽: 弹簧力跟随鼠标
        └── fall.gd        # 掉落: 自由落体 → 落稳回待机
```

## 技术要点

- **物理拖拽**: 使用弹簧力公式 `F = k·x - c·v` 而非直接修改坐标
- **鼠标穿透**: `DisplayServer.window_set_mouse_passthrough()` 实现点击穿透
- **状态机**: RefCounted 轻量 FSM，4 个状态互相切换
- **占位符视觉**: `_draw()` 绘制的史莱姆 (眼睛追踪鼠标、呼吸动画、压缩拉伸)

# file_drop.gd — 文件投喂系统骨架 (RefCounted)
# 职责: 接收拖入文件 → 查找 C# 桥接 → 分发给操作菜单
# 具体功能由 action_*.gd 独立模块实现, 通过 register_action() 注册

var pet: Node2D  # 由 pet.gd 注入

# ── C# 桥接引用 (懒加载) ──
var _file_ops: Node = null
var _wm: Node = null  # WindowsManager (全局鼠标状态检测)

# ── 已注册的操作 ──
# 格式: [{id, label, handler}]
# - id: 唯一标识 (如 "scan", "shred")
# - label: 菜单显示文本 (如 "[扫描] 属性检索")
# - handler: RefCounted 实例, 必须实现 execute(file_drop, paths) 方法
var _actions: Array = []

# ── 状态 ──
var _pending_paths: PackedStringArray = []  # 当前待处理的文件路径
var _is_active: bool = false

# ── 拖放悬停视觉反馈 ──
var hover_amount: float = 0.0   # 悬停动画进度 (0=隐藏, 1=完全显示), pet.gd 读取
var _hover_time: float = 0.0    # 脉冲动画计时器
var _was_hovering: bool = false  # 上一帧是否在悬停 (用于检测"拖了个寂寞")
var _miss_timer: float = 0.0    # 松手后确认定时器 (等待 files_dropped 信号)

# ── 菜单 UI (委托给 DropMenu) ──
var _menu  # DropMenu 实例

# ── 话术 ──
const LINES := {
	"receive_single": "检测到外部数据载体。",
	"receive_multi": "批量数据输入。计 %d 项。",
	"cancel": "指令撤销。",
	"no_bridge": "系统桥接离线。无法执行。",
	"not_found": "目标不存在。可能已被移除。",
}

# ── 彩蛋: 拖入非文件内容的吐槽话术 ──
const MISS_LINES := [
	"数据格式解析失败。投入的是什么？",
	"检测到未知载荷。已丢弃。",
	"…这不是文件。",
	"输入流无法解码。请检查载体类型。",
	"投喂失败。我不吃这个。",
]

# ══════════════════════════════════════
#  初始化
# ══════════════════════════════════════

func init() -> void:
	# 加载菜单 UI 模块
	var DropMenu = preload("res://entities/pet/file_drop/drop_menu.gd")
	_menu = DropMenu.new()
	_menu.file_drop = self
	
	# 注册内置操作 (每个 action 文件都是独立的)
	_register_builtin_actions()

func _register_builtin_actions() -> void:
	_register_action_file("res://entities/pet/file_drop/action_scan.gd")
	_register_action_file("res://entities/pet/file_drop/action_shred.gd")

## 从脚本路径加载并注册一个操作模块
func _register_action_file(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var script = load(path)
	if script == null:
		return
	var instance = script.new()
	if instance.has_method("get_action_id") and instance.has_method("get_action_label") and instance.has_method("execute"):
		register_action(instance.get_action_id(), instance.get_action_label(), instance)
	else:
		push_warning("[FileDrop] 操作模块缺少必要接口: %s" % path)

## 手动注册一个操作 (供外部或测试用)
func register_action(id: String, label: String, handler) -> void:
	# 去重
	for a in _actions:
		if a.id == id:
			return
	_actions.append({id = id, label = label, handler = handler})

## 获取已注册的操作列表 (供菜单读取)
func get_actions() -> Array:
	return _actions

# ══════════════════════════════════════
#  C# 桥接
# ══════════════════════════════════════

## 懒加载 FileOperations C# 节点
func get_file_ops() -> Node:
	if _file_ops != null and is_instance_valid(_file_ops):
		return _file_ops
	var node = _find_csharp_node("GetFileInfo")
	if node:
		_file_ops = node
	return _file_ops

## 懒加载 WindowsManager C# 节点
func _get_wm() -> Node:
	if _wm != null and is_instance_valid(_wm):
		return _wm
	var node = _find_csharp_node("GetGlobalMouseState")
	if node:
		_wm = node
	return _wm

## 通用: 在 Main 节点下查找拥有指定方法的 C# 子节点
func _find_csharp_node(method_name: String) -> Node:
	var tree = pet.get_tree()
	if tree == null:
		return null
	var main_node = tree.root.get_node_or_null("Main")
	if main_node:
		for child in main_node.get_children():
			if child.has_method(method_name):
				return child
	return null

# ══════════════════════════════════════
#  接收入口
# ══════════════════════════════════════

## 由 main.gd 调用, 传入拖放的文件路径列表
func receive(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	
	# 关闭上一次未完成的交互
	if _is_active:
		dismiss()
	
	_pending_paths = paths
	_is_active = true
	_miss_timer = 0.0  # 清除吐槽定时器 (文件成功投入, 不是 "拖了个寂寞")
	
	# 话术反馈
	if paths.size() == 1:
		pet.show_local_bubble(LINES.receive_single)
	else:
		pet.show_local_bubble(LINES.receive_multi % paths.size())
	
	# 弹出操作菜单
	if _menu:
		_menu.show(_actions, pet)

## 获取当前待处理的文件路径列表
func get_pending_paths() -> PackedStringArray:
	return _pending_paths

# ══════════════════════════════════════
#  操作分发
# ══════════════════════════════════════

## 菜单选中某个操作后回调
func execute_action(action_id: String) -> void:
	dismiss()
	
	if action_id == "_cancel":
		pet.show_local_bubble(LINES.cancel)
		_pending_paths = []
		return
	
	for a in _actions:
		if a.id == action_id:
			a.handler.execute(self, _pending_paths)
			return
	
	push_warning("[FileDrop] 未找到操作: %s" % action_id)

## 关闭菜单 & 清理状态
func dismiss() -> void:
	if _menu:
		_menu.dismiss()
	_is_active = false

# ══════════════════════════════════════
#  每帧更新 (由 pet.gd _process 驱动)
# ══════════════════════════════════════

func update(delta: float) -> void:
	if _menu and _is_active:
		_menu.update(delta)
	# 拖放悬停检测 (原体专属)
	if not pet.is_clone:
		_update_hover(delta)

# ══════════════════════════════════════
#  工具方法 (供 action 模块共用)
# ══════════════════════════════════════

func format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	elif bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
	else:
		return "%.2f GB" % (bytes / (1024.0 * 1024.0 * 1024.0))

# ══════════════════════════════════════
#  拖放悬停检测 + 吸引光圈
# ══════════════════════════════════════

## 每帧检测: 外部拖放是否悬停在宠物上方
func _update_hover(delta: float) -> void:
	var is_hovering := false
	
	# 排除: 操作菜单正在展示 (文件已投递, 不是悬停阶段)
	# 排除: 宠物自身拖拽状态 (drag 状态下左键也按住)
	if not _is_active and pet.current_state_name != "drag":
		var wm = _get_wm()
		if wm:
			var state = wm.GetGlobalMouseState()  # [held, screenX, screenY, isDragCursor]
			# 左键按住 + 光标是非标准光标 (OLE 拖拽时光标变成带文件图标的特殊形态)
			# 普通左键按住时光标仍是标准箭头 → isDragCursor=0 → 不触发
			if state[0] == 1 and state[3] == 1:
				# 将屏幕坐标转为视口坐标 (减去窗口位置)
				var win_pos = pet.get_window().position
				var mouse_local = Vector2(state[1] - win_pos.x, state[2] - win_pos.y)
				var dist = pet.global_position.distance_to(mouse_local)
				if dist <= pet.PET_RADIUS + 20.0:
					is_hovering = true
	
	# 平滑过渡动画
	var target = 1.0 if is_hovering else 0.0
	hover_amount = move_toward(hover_amount, target, delta * 5.0)
	if hover_amount > 0.01:
		_hover_time += delta
	else:
		_hover_time = 0.0
	
	# ── 彩蛋: 检测"拖了个寂寞" (光圈亮了但没收到文件) ──
	if _was_hovering and not is_hovering:
		# 悬停结束, 启动确认定时器 (等 files_dropped 信号抵达)
		_miss_timer = 0.3
	_was_hovering = is_hovering
	
	# 定时器倒计时
	if _miss_timer > 0.0:
		_miss_timer -= delta
		if _miss_timer <= 0.0:
			_miss_timer = 0.0
			# 定时器到期且 receive 没被调用 (没有文件投入)
			if not _is_active:
				pet.show_local_bubble(MISS_LINES.pick_random())

## 绘制拖放悬停吸引光圈 (由 pet.gd _draw 调用)
func render_hover(canvas: Node2D) -> void:
	if hover_amount <= 0.01:
		return
	var alpha = hover_amount
	var t = _hover_time
	var base_hue = EventBus.ui_hue
	var r = pet.PET_RADIUS
	
	# 呼吸脉冲半径
	var pulse = sin(t * 3.5) * 0.12 + 1.0
	var ring_r = (r + 12.0) * pulse
	
	# 外圈发光 (柔和的宽弧)
	var glow_color = Color.from_hsv(base_hue, 0.6, 0.9, alpha * 0.25)
	canvas.draw_arc(Vector2.ZERO, ring_r + 4.0, 0, TAU, 64, glow_color, 6.0, true)
	
	# 主圈 (旋转的断续弧线)
	var ring_color = Color.from_hsv(base_hue, 0.5, 1.0, alpha * 0.7)
	var seg_count := 3
	var seg_len = TAU / seg_count * 0.6  # 每段弧占 60%
	var gap = TAU / seg_count
	var spin = t * 2.0  # 旋转速度
	for i in range(seg_count):
		var start_a = spin + gap * i
		canvas.draw_arc(Vector2.ZERO, ring_r, start_a, start_a + seg_len, 16, ring_color, 2.0, true)
	
	# 内圈呼吸光晕
	var inner_r = r + 4.0
	var inner_color = Color.from_hsv(base_hue, 0.4, 1.0, alpha * 0.15 * pulse)
	canvas.draw_circle(Vector2.ZERO, inner_r, inner_color, true, -1.0, true)

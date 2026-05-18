# file_drop.gd — 文件投喂系统骨架 (RefCounted)
# 职责: 接收拖入文件 → 查找 C# 桥接 → 分发给操作菜单
# 具体功能由 action_*.gd 独立模块实现, 通过 register_action() 注册

var pet: Node2D  # 由 pet.gd 注入

# ── C# 桥接引用 (懒加载) ──
var _file_ops: Node = null

# ── 已注册的操作 ──
# 格式: [{id, label, handler}]
# - id: 唯一标识 (如 "scan", "shred")
# - label: 菜单显示文本 (如 "[扫描] 属性检索")
# - handler: RefCounted 实例, 必须实现 execute(file_drop, paths) 方法
var _actions: Array = []

# ── 状态 ──
var _pending_paths: PackedStringArray = []  # 当前待处理的文件路径
var _is_active: bool = false

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
	var tree = pet.get_tree()
	if tree == null:
		return null
	# FileOperations 挂在 Main 节点下 (由 main.gd add_child)
	var main_node = tree.root.get_node_or_null("Main")
	if main_node:
		for child in main_node.get_children():
			if child.has_method("GetFileInfo"):
				_file_ops = child
				return _file_ops
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

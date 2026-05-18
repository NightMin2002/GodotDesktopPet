# sec_play.gd — 玩法分区 (玩具注册表)
# 玩具通过 _TOY_REGISTRY 注册, 新增只需: 1) 写模块文件 2) 注册表加一行
extends RefCounted

var ctx  # ContextMenu 引用

# ── 玩具注册表 ──
# 新增玩具: 在这里加一行 preload 即可
const _TOY_REGISTRY := [
	preload("res://ui/context_menu/toys/toy_stacking.gd"),
]

# ── 运行时 ──
var _toys: Array = []  # ToyBase 实例列表

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# 动态注册所有玩具
	for ToyScript in _TOY_REGISTRY:
		var toy = ToyScript.new(ctx)
		_toys.append(toy)
		_build_toy_entry(vbox, toy)

	panel.mouse_entered.connect(func(): ctx._submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.panels["sec_play"] = panel

## 为单个玩具构建菜单入口 (自动判断有无子菜单)
func _build_toy_entry(vbox: VBoxContainer, toy) -> void:
	if toy.has_submenu():
		# 有子菜单: 创建 L3 触发按钮 + L3 面板
		var toy_id = "toy_" + toy.get_label()
		var btn = ctx._make_menu_btn(toy.get_label() + " [+]", Color(0.3, 1.0, 0.7, 1))
		vbox.add_child(btn)
		ctx._bind_l3_trigger(btn, toy_id, "sec_play")

		# 构建 L3 面板
		var l3_panel = ctx._submenu._make_panel()
		var l3_vbox = VBoxContainer.new()
		l3_vbox.add_theme_constant_override("separation", 4)
		l3_panel.add_child(l3_vbox)
		toy.build_submenu(l3_vbox)
		ctx._submenu.register_l3_panel(toy_id, l3_panel, "sec_play")
	else:
		# 无子菜单: 直接按钮
		var btn = ctx._make_menu_btn(toy.get_label(), Color(0.3, 1.0, 0.7, 1))
		btn.pressed.connect(toy.on_activate)
		vbox.add_child(btn)
		if toy.get_desc() != "":
			var b = btn
			var desc = toy.get_desc()
			btn.mouse_entered.connect(func(): ctx._tooltip.show_for(b, desc, true))
			btn.mouse_exited.connect(func(): ctx._tooltip.show_for(b, desc, false))

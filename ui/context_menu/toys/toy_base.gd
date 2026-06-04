# toy_base.gd — 娱乐玩具基类
# 所有玩具模块继承此类, 提供统一接口供 sec_play.gd 注册和分发
# 新增玩具只需: 1) 继承 ToyBase  2) 实现接口  3) 在 sec_play.gd 注册表加一行
class_name ToyBase extends RefCounted

var ctx  # ContextMenu 引用

func _init(context_menu) -> void:
	ctx = context_menu

# ── 必须实现 ──

## 玩具显示名称 (菜单按钮文字)
func get_label() -> String:
	return ""

## 玩具描述 (tooltip)
func get_desc() -> String:
	return ""

# ── 可选实现 ──

## 是否有子菜单 (true → 按钮显示 [+], 展开 L3 面板)
func has_submenu() -> bool:
	return false

## 构建子菜单内容 (has_submenu=true 时调用)
## vbox: 子菜单的 VBoxContainer, 往里面添加按钮即可
func build_submenu(vbox: VBoxContainer) -> void:
	pass

## 直接执行 (has_submenu=false 时, 点击按钮触发)
func on_activate() -> void:
	pass

## 外部生命周期清理 (例如回收分身、关闭程序前)
func cleanup() -> void:
	pass

# ── 工具方法 (子类直接用) ──

## 关闭菜单
func close_menu() -> void:
	ctx.close_menu_instant()

## 获取所有宠物实例 (原体 + 克隆体)
func get_all_pets() -> Array:
	var main = ctx.get_tree().root.get_node_or_null("Main")
	if not main:
		return []
	var result := []
	for p in main.pet_instances:
		if is_instance_valid(p):
			result.append(p)
	return result

## 获取克隆体列表
func get_clones() -> Array:
	var result := []
	for p in get_all_pets():
		if p.is_clone:
			result.append(p)
	return result

## 创建标准子菜单按钮
func make_btn(label: String, callback: Callable, desc: String = "") -> Button:
	var btn = CyberMenuButton.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 19)
	btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.3, 1.0, 0.7, 1))
	btn.text = label
	btn.pressed.connect(callback)
	if desc != "":
		var b = btn
		var d = desc
		btn.mouse_entered.connect(func(): ctx._tooltip.show_for(b, d, true))
		btn.mouse_exited.connect(func(): ctx._tooltip.show_for(b, d, false))
	return btn

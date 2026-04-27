# section_styler.gd — 分区标题样式化子系统 (RefCounted)
# 负责: 将 ▌ 标题 Label 替换为彩色左边框徽章 + 子菜单边框色自动继承
# 从 context_menu.gd 拆分
extends RefCounted

var _menu  # context_menu 引用
var _btn_section_colors: Dictionary = {}  # Button -> Color

func _init(menu_ref) -> void:
	_menu = menu_ref

## 将 ▌ 标题 Label 替换为徽章(彩色左边框面板) + 延伸细线
func style_headers(hud: PanelContainer, submenus: Dictionary) -> void:
	var vbox = hud.get_node("Margin/VBox")
	var is_first_section := true
	var children_snapshot = vbox.get_children().duplicate()
	var current_section_color := Color.WHITE
	
	for child in children_snapshot:
		if child is Label and child.text.begins_with("\u258c"):
			var label: Label = child
			current_section_color = label.get_theme_color("font_color")
			var section_text: String = label.text.replace("\u258c", "")
			var idx = label.get_index()
			
			# 上方间距
			if not is_first_section:
				var spacer = Control.new()
				spacer.custom_minimum_size.y = 4
				spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
				vbox.add_child(spacer)
				vbox.move_child(spacer, idx)
				idx += 1
			is_first_section = false
			
			# 全宽徽章: 彩色左边框 + 深背景横幅
			var badge = PanelContainer.new()
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var style = StyleBoxFlat.new()
			style.bg_color = Color(current_section_color.r * 0.2, current_section_color.g * 0.2, current_section_color.b * 0.2, 0.7)
			style.border_color = current_section_color
			style.border_width_left = 3
			style.border_width_top = 0
			style.border_width_right = 0
			style.border_width_bottom = 0
			style.corner_radius_top_right = 4
			style.corner_radius_bottom_right = 4
			style.corner_radius_top_left = 0
			style.corner_radius_bottom_left = 0
			style.content_margin_left = 8
			style.content_margin_right = 10
			style.content_margin_top = 2
			style.content_margin_bottom = 2
			badge.add_theme_stylebox_override("panel", style)
			
			var badge_label = Label.new()
			badge_label.text = section_text
			badge_label.add_theme_font_size_override("font_size", 13)
			badge_label.add_theme_color_override("font_color", Color(current_section_color.r, current_section_color.g, current_section_color.b, 0.9))
			badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_child(badge_label)
			
			# 替换原 Label
			vbox.add_child(badge)
			vbox.move_child(badge, idx)
			label.queue_free()
		elif child is Button:
			# 记录每个按钮所属区块的颜色
			_btn_section_colors[child] = current_section_color
	
	# 自动给子菜单上色
	color_submenus(submenus)

## 根据触发按钮所属区块色自动设置子菜单边框色
func color_submenus(submenus: Dictionary) -> void:
	for menu_id in submenus:
		var trigger = _menu._get_submenu_trigger(menu_id)
		if trigger and trigger in _btn_section_colors:
			var color: Color = _btn_section_colors[trigger]
			var panel: PanelContainer = submenus[menu_id]
			var style = panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			style.border_color = Color(color.r, color.g, color.b, 0.8)
			panel.add_theme_stylebox_override("panel", style)

## 获取按钮所属区块颜色
func get_section_color(btn: Button) -> Color:
	return _btn_section_colors.get(btn, Color.WHITE)

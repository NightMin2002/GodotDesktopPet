# datalog_category_view.gd — 机体记录分类入口卡片
# 静态工厂: 渲染分类首页, 不持有状态
extends RefCounted

# 分类定义
const PET_CATEGORIES = [
	{"tag": "sys:input", "title": "键鼠行为", "desc": "击键统计 / 组合键 / 点击 / 移动距离", "icon": "//"},
	{"tag": "sys:window", "title": "窗口程序", "desc": "前台应用使用时长分布", "icon": "[]"},
	#{"tag": "sys:session", "title": "会话概要", "desc": "在线时长 / 启动关机 / 深夜检测", "icon": "<>"},
]

## 渲染分类卡片到 container, 点击时回调 on_select(tag: String)
static func render(container: VBoxContainer, logs: Array, on_select: Callable) -> void:
	for child in container.get_children():
		child.queue_free()

	# 标题
	var header = Label.new()
	header.text = "SYSTEM // 机体数据分类"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.35, 0.6, 0.5))
	container.add_child(header)

	for cat in PET_CATEGORIES:
		var count = _count_by_tag(logs, cat.tag)
		var card = _make_card(cat, count, on_select)
		container.add_child(card)

	# 底部提示
	var hint = Label.new()
	hint.text = "更多数据源开发中..."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.3))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(hint)

static func _count_by_tag(logs: Array, tag: String) -> int:
	var count = 0
	for entry in logs:
		if entry.get("source", "") == "pet":
			var tags = entry.get("tags", [])
			if tag in tags:
				count += 1
	return count

static func _make_card(cat: Dictionary, count: int, on_select: Callable) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var cs = StyleBoxFlat.new()
	cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.25, 0.12, 0.55)
	cs.set_corner_radius_all(3)
	cs.set_border_width_all(1)
	cs.border_width_left = 3
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.45, 0.65, 0.5)
	cs.content_margin_left = 14; cs.content_margin_right = 12
	cs.content_margin_top = 12; cs.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", cs)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# 第一行: 图标 + 标题 + 记录数 + 箭头
	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row1)

	var icon_lbl = Label.new()
	icon_lbl.text = cat.icon
	icon_lbl.add_theme_font_size_override("font_size", 14)
	icon_lbl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.7))
	row1.add_child(icon_lbl)

	var title_lbl = Label.new()
	title_lbl.text = cat.title
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.92, 0.96, 0.95))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(title_lbl)

	var count_lbl = Label.new()
	count_lbl.text = "%d 条" % count if count > 0 else "暂无数据"
	count_lbl.add_theme_font_size_override("font_size", 11)
	count_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.6) if count == 0 else Color.from_hsv(EventBus.ui_hue, 0.35, 0.75, 0.7))
	row1.add_child(count_lbl)

	var arrow = Label.new()
	arrow.text = ">"
	arrow.add_theme_font_size_override("font_size", 13)
	arrow.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.4))
	row1.add_child(arrow)

	# 第二行: 描述
	var desc_lbl = Label.new()
	desc_lbl.text = cat.desc
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.5))
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)

	# 点击进入子列表
	var tag_id = cat.tag
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			on_select.call(tag_id)
	)

	# hover 效果
	card.mouse_entered.connect(func():
		var hs = cs.duplicate()
		hs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.30, 0.18, 0.65)
		hs.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.75, 0.65)
		card.add_theme_stylebox_override("panel", hs)
	)
	card.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel", cs)
	)

	return card

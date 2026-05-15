# profile_tab_datalog.gd — 数据日志 Tab (装置终端 Tab 3)
# 双分区轻量笔记: 机体记录 (宠物) + 操作员备忘 (用户)
# 复用 ProfileStyles 样式工厂
extends HBoxContainer

# ── 状态 ──
var _source_filter: String = "user"  # "user" | "pet"
var _pet_category: String = ""       # "" = 分类首页, "sys:input" = 键鼠列表...
var _logs: Array = []
var _filtered: Array = []
var _selected_idx: int = -1  # 在 _filtered 中的索引

# ── 机体记录分类定义 ──
const PET_CATEGORIES = [
	{"tag": "sys:input", "title": "键鼠行为", "desc": "击键统计 / 组合键 / 点击 / 移动距离", "icon": "//"},
	#{"tag": "sys:window", "title": "窗口程序", "desc": "前台应用使用时长分布", "icon": "[]"},
	#{"tag": "sys:session", "title": "会话概要", "desc": "在线时长 / 启动关机 / 深夜检测", "icon": "<>"},
]

# ── UI 引用 ──
var _list_vbox: VBoxContainer
var _detail_panel: VBoxContainer
var _title_edit: LineEdit
var _content_edit: TextEdit
var _tags_flow: HBoxContainer
var _tag_input: LineEdit
var _info_label: Label
var _empty_hint: VBoxContainer
var _save_badge: Label
var _new_btn: Button
var _report_btn: Button  # 机体记录分区的"生成报告"按钮
var _del_btn: Button
var _search_edit: LineEdit
var _filter_btns: Array[Button] = []
var _scroll: ScrollContainer
var _detail_header: Label
var _detail_empty: VBoxContainer  # 右栏未选中时的引导
var _search_row: HBoxContainer     # 搜索+按钮行 (分类首页时隐藏)
var _back_btn: Button              # 子列表返回按钮
var _category_container: VBoxContainer  # 分类卡片容器

# ── 防抖 ──
var _save_timer: Timer
var _search_timer: Timer

# ── 删除确认 ──
var _del_pending: bool = false
var _del_reset_tween: Tween

# ── 动画标记 ──
var _animate_new_card: bool = false

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	_logs = SettingsManager.get_datalogs()

	# ── 左栏: 列表 ──
	var left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(280, 0)
	left.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(left)

	# 分区切换按钮
	var filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 0)
	left.add_child(filter_row)

	_filter_btns.clear()
	var filters = [["操作员备忘", "user"], ["机体记录", "pet"]]
	for f in filters:
		var btn = Button.new()
		btn.text = f[0]
		btn.add_theme_font_size_override("font_size", 13)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var src = f[1]
		btn.pressed.connect(func(): _switch_source(src))
		_style_filter_btn(btn, src == _source_filter)
		_filter_btns.append(btn)
		filter_row.add_child(btn)

	# 搜索框 + 新建按钮 (+返回按钮)
	_search_row = HBoxContainer.new()
	_search_row.add_theme_constant_override("separation", 6)
	left.add_child(_search_row)

	# 返回按钮 (机体记录子列表时显示)
	_back_btn = Button.new()
	_back_btn.text = "<"
	_back_btn.add_theme_font_size_override("font_size", 13)
	_back_btn.custom_minimum_size = Vector2(28, 0)
	var bk_s = StyleBoxFlat.new()
	bk_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.15, 0.5)
	bk_s.set_corner_radius_all(2)
	bk_s.content_margin_left = 4; bk_s.content_margin_right = 4
	bk_s.content_margin_top = 4; bk_s.content_margin_bottom = 4
	_back_btn.add_theme_stylebox_override("normal", bk_s)
	var bk_h = bk_s.duplicate()
	bk_h.bg_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.25, 0.7)
	_back_btn.add_theme_stylebox_override("hover", bk_h)
	_back_btn.add_theme_stylebox_override("pressed", bk_h)
	_back_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.8, 0.7))
	_back_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 0.9))
	_back_btn.pressed.connect(_on_back_to_categories)
	_back_btn.visible = false
	_search_row.add_child(_back_btn)

	_search_edit = _make_line_edit("搜索关键词...", 0)
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(func(_t): _on_search_changed())
	_search_row.add_child(_search_edit)

	_new_btn = Button.new()
	_new_btn.text = "+ 新建"
	_new_btn.add_theme_font_size_override("font_size", 12)
	_new_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.95, 0.9))
	_new_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	var nb_s = StyleBoxFlat.new()
	nb_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.20, 0.6)
	nb_s.set_border_width_all(1)
	nb_s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.55, 0.4)
	nb_s.set_corner_radius_all(2)
	nb_s.content_margin_left = 10; nb_s.content_margin_right = 10
	nb_s.content_margin_top = 4; nb_s.content_margin_bottom = 4
	_new_btn.add_theme_stylebox_override("normal", nb_s)
	var nb_h = nb_s.duplicate()
	nb_h.bg_color = Color.from_hsv(EventBus.ui_hue, 0.45, 0.30, 0.8)
	nb_h.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.7)
	_new_btn.add_theme_stylebox_override("hover", nb_h)
	_new_btn.add_theme_stylebox_override("pressed", nb_h)
	_new_btn.pressed.connect(_on_new_pressed)
	_new_btn.visible = (_source_filter == "user")
	_search_row.add_child(_new_btn)

	# 机体记录分区: 手动触发报告按钮
	_report_btn = Button.new()
	_report_btn.text = "生成报告"
	_report_btn.add_theme_font_size_override("font_size", 12)
	_report_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.85))
	_report_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	var rb_s = StyleBoxFlat.new()
	rb_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.45, 0.18, 0.6)
	rb_s.set_border_width_all(1)
	rb_s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.55, 0.4)
	rb_s.set_corner_radius_all(2)
	rb_s.content_margin_left = 10; rb_s.content_margin_right = 10
	rb_s.content_margin_top = 4; rb_s.content_margin_bottom = 4
	_report_btn.add_theme_stylebox_override("normal", rb_s)
	var rb_h = rb_s.duplicate()
	rb_h.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.28, 0.8)
	rb_h.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.7)
	_report_btn.add_theme_stylebox_override("hover", rb_h)
	_report_btn.add_theme_stylebox_override("pressed", rb_h)
	_report_btn.pressed.connect(func():
		EventBus.trigger_input_report.emit()
		# 稍后刷新列表
		var tw = create_tween()
		tw.tween_interval(0.1)
		tw.tween_callback(func():
			if _source_filter == "pet" and _pet_category != "":
				_apply_filter()
		)
	)
	_report_btn.visible = false  # 只在子列表时显示
	_search_row.add_child(_report_btn)

	# ── 分类卡片容器 (机体记录分类首页) ──
	_category_container = VBoxContainer.new()
	_category_container.add_theme_constant_override("separation", 6)
	_category_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_container.visible = false
	left.add_child(_category_container)

	# 计数指示
	_info_label = ProfileStyles.label_dim("", 10)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	left.add_child(_info_label)

	# 列表区
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	left.add_child(_scroll)

	var scroll_margin = MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_right", 4)
	_scroll.add_child(scroll_margin)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 4)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(_list_vbox)

	# 空状态提示
	_empty_hint = VBoxContainer.new()
	_empty_hint.add_theme_constant_override("separation", 8)
	_empty_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_hint.visible = false
	_empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_vbox.add_child(_empty_hint)

	var empty_spacer = Control.new()
	empty_spacer.custom_minimum_size = Vector2(0, 30)
	_empty_hint.add_child(empty_spacer)

	var empty_icon = Label.new()
	empty_icon.text = "[ ]"
	empty_icon.add_theme_font_size_override("font_size", 28)
	empty_icon.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.25))
	empty_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_hint.add_child(empty_icon)

	var empty_text = Label.new()
	empty_text.add_theme_font_size_override("font_size", 12)
	empty_text.add_theme_color_override("font_color", Color(0.35, 0.4, 0.45, 0.45))
	empty_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_hint.add_child(empty_text)
	# 文案根据分区区分
	if _source_filter == "user":
		empty_text.text = "暂无备忘记录\n点击 [+ 新建] 开始记录"
	else:
		empty_text.text = "机体日志为空\n系统尚未采集到可报告的行为数据"

	# 独立科幻滚动指示器
	var indicator = preload("res://ui/profile/cyber_scroll_indicator.gd").new()
	indicator.bind_scroll(_scroll)
	add_child(indicator)

	# ── 竖分隔线 ──
	var vsep = VSeparator.new()
	var vs_s = StyleBoxFlat.new()
	vs_s.border_width_left = 1
	vs_s.border_color = Color(1.0, 1.0, 1.0, 0.04)
	vs_s.content_margin_top = 8; vs_s.content_margin_bottom = 8
	vsep.add_theme_stylebox_override("separator", vs_s)
	add_child(vsep)

	# ── 右栏: 详情编辑 ──
	var right_wrapper = Control.new()
	right_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(right_wrapper)

	# 未选中引导
	_detail_empty = VBoxContainer.new()
	_detail_empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_detail_empty.add_theme_constant_override("separation", 10)
	_detail_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_wrapper.add_child(_detail_empty)

	var de_icon = Label.new()
	de_icon.text = "<>"
	de_icon.add_theme_font_size_override("font_size", 32)
	de_icon.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.35, 0.2))
	de_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_empty.add_child(de_icon)

	var de_text = Label.new()
	de_text.text = "选择一条记录查看详情"
	de_text.add_theme_font_size_override("font_size", 13)
	de_text.add_theme_color_override("font_color", Color(0.35, 0.4, 0.45, 0.35))
	de_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_empty.add_child(de_text)

	# 详情面板
	_detail_panel = VBoxContainer.new()
	_detail_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_panel.add_theme_constant_override("separation", 8)
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_panel.visible = false
	right_wrapper.add_child(_detail_panel)

	# 前缀标记
	_detail_header = Label.new()
	_detail_header.text = "ENTRY // 操作员备忘"
	_detail_header.add_theme_font_size_override("font_size", 11)
	_detail_header.add_theme_color_override("font_color", Color(0.35, 0.40, 0.48, 0.45))
	_detail_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(_detail_header)

	# 标题编辑
	_title_edit = _make_line_edit("标题", 0)
	_title_edit.add_theme_font_size_override("font_size", 18)
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_edit.text_changed.connect(func(_t): _on_content_changed())
	_detail_panel.add_child(_title_edit)

	# 标签区
	var tags_row = HBoxContainer.new()
	tags_row.add_theme_constant_override("separation", 6)
	_detail_panel.add_child(tags_row)

	var tag_icon = ProfileStyles.label_dim("TAGS //", 10)
	tags_row.add_child(tag_icon)

	_tags_flow = HBoxContainer.new()
	_tags_flow.add_theme_constant_override("separation", 4)
	_tags_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tags_row.add_child(_tags_flow)

	_tag_input = _make_line_edit("新标签 回车确认", 90)
	_tag_input.add_theme_font_size_override("font_size", 11)
	_tag_input.custom_minimum_size = Vector2(90, 0)
	_tag_input.text_submitted.connect(_on_tag_submitted)
	tags_row.add_child(_tag_input)

	# 分隔线
	var hsep = HSeparator.new()
	hsep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	hsep.add_theme_constant_override("separation", 1)
	_detail_panel.add_child(hsep)

	# 正文编辑
	_content_edit = TextEdit.new()
	_content_edit.placeholder_text = "写点什么..."
	_content_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_content_edit.add_theme_font_size_override("font_size", 14)
	_content_edit.add_theme_color_override("font_color", Color(0.80, 0.85, 0.90, 0.95))
	_content_edit.add_theme_color_override("font_placeholder_color", Color(0.35, 0.40, 0.48, 0.4))
	_content_edit.add_theme_color_override("caret_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.9))
	var te_bg = StyleBoxFlat.new()
	te_bg.bg_color = Color(0.03, 0.04, 0.08, 0.4)
	te_bg.set_corner_radius_all(2)
	te_bg.set_content_margin_all(12)
	_content_edit.add_theme_stylebox_override("normal", te_bg)
	var te_focus = te_bg.duplicate()
	te_focus.border_width_bottom = 1
	te_focus.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.4)
	_content_edit.add_theme_stylebox_override("focus", te_focus)
	_content_edit.text_changed.connect(_on_content_changed)
	_detail_panel.add_child(_content_edit)

	# 底部信息栏
	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	_detail_panel.add_child(bottom)

	_save_badge = Label.new()
	_save_badge.text = ""
	_save_badge.add_theme_font_size_override("font_size", 11)
	_save_badge.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.7, 0.6))
	bottom.add_child(_save_badge)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)

	_del_btn = Button.new()
	_del_btn.text = "删除记录"
	_del_btn.add_theme_font_size_override("font_size", 12)
	_del_btn.add_theme_color_override("font_color", Color(0.65, 0.4, 0.4, 0.6))
	_del_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.4, 0.35, 1.0))
	var ds = StyleBoxFlat.new()
	ds.bg_color = Color(0.10, 0.04, 0.04, 0.4)
	ds.set_corner_radius_all(2)
	ds.set_border_width_all(1)
	ds.border_color = Color(0.4, 0.18, 0.18, 0.25)
	ds.content_margin_left = 10; ds.content_margin_right = 10
	ds.content_margin_top = 3; ds.content_margin_bottom = 3
	_del_btn.add_theme_stylebox_override("normal", ds)
	var dh = ds.duplicate()
	dh.bg_color = Color(0.25, 0.08, 0.08, 0.7)
	dh.border_color = Color(0.8, 0.3, 0.3, 0.5)
	_del_btn.add_theme_stylebox_override("hover", dh)
	_del_btn.add_theme_stylebox_override("pressed", dh)
	_del_btn.pressed.connect(_on_delete_pressed)
	bottom.add_child(_del_btn)

	# ── 防抖 Timer ──
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.6
	_save_timer.timeout.connect(_do_save)
	add_child(_save_timer)

	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.3
	_search_timer.timeout.connect(_apply_filter)
	add_child(_search_timer)

	# ── 初始刷新 ──
	_update_pet_view()
	_update_detail_panel()

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_filter_btns.clear()
	_selected_idx = -1
	_del_pending = false
	build()

# ═══════════════════════════════════════════════
#  分区 & 搜索
# ═══════════════════════════════════════════════

func _switch_source(src: String) -> void:
	if src == _source_filter:
		return
	_source_filter = src
	_pet_category = ""  # 重置分类状态
	_selected_idx = -1
	# 用户分区: 平铺列表; 宠物分区: 分类首页
	_new_btn.visible = (_source_filter == "user")
	_report_btn.visible = false
	_back_btn.visible = false
	# 更新按钮样式
	for i in range(_filter_btns.size()):
		var is_active = (["user", "pet"][i] == _source_filter)
		_style_filter_btn(_filter_btns[i], is_active)
	# 更新空状态文案
	_update_empty_hint_text()
	_update_pet_view()
	_update_detail_panel()

## 机体记录: 分类首页 / 子列表 切换
func _update_pet_view() -> void:
	if _source_filter == "user":
		# 用户分区: 直接平铺列表
		_category_container.visible = false
		_scroll.visible = true
		_search_row.visible = true
		_apply_filter()
		return

	# 宠物分区
	if _pet_category == "":
		# 分类首页: 显示分类卡片, 隐藏日志列表
		_category_container.visible = true
		_scroll.visible = false
		_info_label.text = ""
		_search_row.visible = false
		_render_pet_categories()
	else:
		# 子列表: 显示日志列表, 隐藏分类卡片
		_category_container.visible = false
		_scroll.visible = true
		_search_row.visible = true
		_back_btn.visible = true
		_report_btn.visible = (_pet_category == "sys:input")
		_apply_filter()

func _render_pet_categories() -> void:
	for child in _category_container.get_children():
		child.queue_free()

	# 标题
	var header = Label.new()
	header.text = "SYSTEM // 机体数据分类"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.35, 0.6, 0.5))
	_category_container.add_child(header)

	_logs = SettingsManager.get_datalogs()

	for cat in PET_CATEGORIES:
		# 统计该分类的日志数
		var count = 0
		for entry in _logs:
			if entry.get("source", "") == "pet":
				var tags = entry.get("tags", [])
				if cat.tag in tags:
					count += 1

		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var cs = StyleBoxFlat.new()
		cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.25, 0.12, 0.55)
		cs.set_corner_radius_all(3)
		cs.set_border_width_all(1)
		cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.25)
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
				_enter_pet_category(tag_id)
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

		_category_container.add_child(card)

	# 底部提示
	var hint = Label.new()
	hint.text = "更多数据源开发中..."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.3))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_category_container.add_child(hint)

func _enter_pet_category(tag: String) -> void:
	_pet_category = tag
	_selected_idx = -1
	_search_edit.text = ""
	_update_pet_view()
	_update_detail_panel()

func _on_back_to_categories() -> void:
	_pet_category = ""
	_selected_idx = -1
	_search_edit.text = ""
	_back_btn.visible = false
	_report_btn.visible = false
	_new_btn.visible = false
	_update_pet_view()
	_update_detail_panel()

func _update_empty_hint_text() -> void:
	if not _empty_hint: return
	for child in _empty_hint.get_children():
		if child is Label and child.get_theme_font_size("font_size") == 12:
			if _source_filter == "user":
				child.text = "暂无备忘记录\n点击 [+ 新建] 开始记录"
			else:
				child.text = "机体日志为空\n系统尚未采集到可报告的行为数据"

func _on_search_changed() -> void:
	_search_timer.start()

func _apply_filter() -> void:
	_logs = SettingsManager.get_datalogs()
	var keyword = _search_edit.text.strip_edges().to_lower() if _search_edit else ""

	_filtered.clear()
	for entry in _logs:
		if entry.get("source", "user") != _source_filter:
			continue
		# 机体记录子列表: 只显示当前分类的日志
		if _source_filter == "pet" and _pet_category != "":
			var tags = entry.get("tags", [])
			if _pet_category not in tags:
				continue
		if keyword != "":
			var title_match = entry.get("title", "").to_lower().find(keyword) >= 0
			var content_match = entry.get("content", "").to_lower().find(keyword) >= 0
			var tag_match = false
			for tag in entry.get("tags", []):
				if str(tag).to_lower().find(keyword) >= 0:
					tag_match = true
					break
			if not title_match and not content_match and not tag_match:
				continue
		_filtered.append(entry)

	# 按更新时间倒序
	_filtered.sort_custom(func(a, b): return a.get("updated", "") > b.get("updated", ""))

	_render_list()

func _render_list() -> void:
	if not _list_vbox:
		return
	# 清理旧卡片 (保留 empty_hint)
	for child in _list_vbox.get_children():
		if child != _empty_hint:
			child.queue_free()

	_empty_hint.visible = _filtered.is_empty()
	if _info_label:
		_info_label.text = "%d 条记录" % _filtered.size() if _filtered.size() > 0 else ""

	for i in range(_filtered.size()):
		var entry = _filtered[i]
		var card = _make_log_card(entry, i)
		_list_vbox.add_child(card)
		# 新建条目入场动画
		if _animate_new_card and i == 0:
			_animate_new_card = false
			card.modulate.a = 0.0
			var tw = create_tween().set_parallel(true)
			tw.tween_property(card, "modulate:a", 1.0, 0.25)

	# 把 empty_hint 移到末尾
	if _empty_hint.get_parent() == _list_vbox:
		_list_vbox.move_child(_empty_hint, _list_vbox.get_child_count() - 1)

# ═══════════════════════════════════════════════
#  日志卡片
# ═══════════════════════════════════════════════

func _make_log_card(entry: Dictionary, idx: int) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var is_sel = (idx == _selected_idx)
	var cs = StyleBoxFlat.new()
	if is_sel:
		cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.20, 0.7)
		cs.border_width_left = 3
		cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.85, 0.8)
	else:
		cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.20, 0.10, 0.3)
		cs.border_width_left = 2
		cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.2)
	cs.set_corner_radius_all(2)
	cs.content_margin_left = 12; cs.content_margin_right = 10
	cs.content_margin_top = 8; cs.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", cs)

	# hover 效果
	var hover_bg = Color.from_hsv(EventBus.ui_hue, 0.28, 0.16, 0.55)
	var normal_bg = cs.bg_color
	card.mouse_entered.connect(func():
		if idx != _selected_idx:
			cs.bg_color = hover_bg
			cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.4)
	)
	card.mouse_exited.connect(func():
		if idx != _selected_idx:
			cs.bg_color = normal_bg
			cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.2)
	)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# 顶行: 标签 + 时间
	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	var tags = entry.get("tags", [])
	var tag_count = 0
	for tag in tags:
		if tag_count >= 3:
			break
		top_row.add_child(_make_tag_badge(str(tag), false))
		tag_count += 1

	var time_spacer = Control.new()
	time_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(time_spacer)

	var time_str = entry.get("updated", entry.get("created", ""))
	# 显示完整时间戳: "2026-05-15 09:00"
	if time_str.length() >= 16:
		time_str = time_str.substr(0, 16)  # "YYYY-MM-DD HH:MM"
	var time_l = Label.new()
	time_l.text = time_str
	time_l.add_theme_font_size_override("font_size", 10)
	time_l.add_theme_color_override("font_color", Color(0.35, 0.40, 0.45, 0.4))
	time_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(time_l)

	# 标题
	var title_text = entry.get("title", "").strip_edges()
	var title_l = Label.new()
	if title_text == "":
		title_l.text = "无标题"
		title_l.add_theme_color_override("font_color", Color(0.40, 0.44, 0.50, 0.4))
	else:
		title_l.text = title_text
		title_l.add_theme_color_override("font_color", Color(0.82, 0.87, 0.92, 0.95) if is_sel else Color(0.68, 0.74, 0.80, 0.85))
	title_l.add_theme_font_size_override("font_size", 14)
	title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_l)

	# 内容预览
	var preview_text = entry.get("content", "").strip_edges()
	if preview_text.length() > 60:
		preview_text = preview_text.substr(0, 60) + "..."
	if preview_text != "":
		var preview_l = Label.new()
		preview_l.text = preview_text
		preview_l.add_theme_font_size_override("font_size", 11)
		preview_l.add_theme_color_override("font_color", Color(0.38, 0.42, 0.48, 0.4))
		preview_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		preview_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(preview_l)

	# 点击选中
	var i_copy = idx
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_log(i_copy)
	)

	return card

# ═══════════════════════════════════════════════
#  标签徽章 (胶囊样式)
# ═══════════════════════════════════════════════

func _make_tag_badge(tag_text: String, with_close: bool) -> Control:
	var badge = PanelContainer.new()
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.40, 0.25, 0.65)
	bs.set_corner_radius_all(8)
	bs.set_border_width_all(1)
	bs.border_color = Color.from_hsv(EventBus.ui_hue, 0.45, 0.6, 0.45)
	bs.content_margin_left = 7; bs.content_margin_right = 7
	bs.content_margin_top = 2; bs.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", bs)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE if not with_close else Control.MOUSE_FILTER_PASS

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 3)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(hbox)

	var lbl = Label.new()
	lbl.text = tag_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.45, 0.8, 0.75))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	if with_close:
		var x_btn = Button.new()
		x_btn.text = "x"
		x_btn.add_theme_font_size_override("font_size", 9)
		x_btn.add_theme_color_override("font_color", Color(0.5, 0.35, 0.35, 0.4))
		x_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.4, 0.4, 0.9))
		var x_s = StyleBoxEmpty.new()
		x_btn.add_theme_stylebox_override("normal", x_s)
		x_btn.add_theme_stylebox_override("hover", x_s)
		x_btn.add_theme_stylebox_override("pressed", x_s)
		x_btn.custom_minimum_size = Vector2(12, 12)
		var tag_ref = tag_text
		x_btn.pressed.connect(func(): _remove_tag(tag_ref))
		hbox.add_child(x_btn)

	return badge

# ═══════════════════════════════════════════════
#  选中 & 详情面板
# ═══════════════════════════════════════════════

func _select_log(idx: int) -> void:
	_selected_idx = idx
	_reset_delete_state()
	_render_list()
	_update_detail_panel()

func _update_detail_panel() -> void:
	if _selected_idx < 0 or _selected_idx >= _filtered.size():
		_detail_panel.visible = false
		_detail_empty.visible = true
		return

	_detail_panel.visible = true
	_detail_empty.visible = false
	_reset_delete_state()

	var entry = _filtered[_selected_idx]
	var is_pet = (entry.get("source", "user") == "pet")

	# 更新头部标记
	if is_pet:
		_detail_header.text = "ENTRY // 机体记录"
	else:
		_detail_header.text = "ENTRY // 操作员备忘"

	_title_edit.text = entry.get("title", "")
	_title_edit.editable = true

	_content_edit.text = entry.get("content", "")
	_content_edit.editable = not is_pet

	_del_btn.visible = true
	_tag_input.visible = true

	var created = entry.get("created", "")
	_save_badge.text = "创建于 %s" % created if created != "" else ""

	_refresh_tags_display(entry.get("tags", []))

func _refresh_tags_display(tags: Array) -> void:
	for child in _tags_flow.get_children():
		child.queue_free()

	for tag in tags:
		_tags_flow.add_child(_make_tag_badge(str(tag), true))

# ═══════════════════════════════════════════════
#  CRUD 操作
# ═══════════════════════════════════════════════

func _on_new_pressed() -> void:
	var now = Time.get_datetime_string_from_system(false, true)
	var id = "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	# 用当前时间生成默认标题, 格式: "备忘 05-15 09:00"
	var td = Time.get_datetime_dict_from_system()
	var default_title = "备忘 %02d-%02d %02d:%02d" % [td.month, td.day, td.hour, td.minute]
	var entry = {
		"id": id,
		"title": default_title,
		"content": "",
		"tags": [],
		"source": "user",
		"created": now,
		"updated": now,
	}
	_logs.insert(0, entry)
	SettingsManager.save_datalogs(_logs)

	_selected_idx = 0
	_animate_new_card = true
	_apply_filter()
	_update_detail_panel()

	# 聚焦标题并全选, 方便直接覆盖输入
	if _title_edit:
		_title_edit.grab_focus()
		_title_edit.select_all()

func _on_delete_pressed() -> void:
	if _selected_idx < 0 or _selected_idx >= _filtered.size():
		return

	if not _del_pending:
		# 第一次点击: 进入确认态
		_del_pending = true
		_del_btn.text = "确认删除?"
		_del_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5, 1.0))
		var crit_s = StyleBoxFlat.new()
		crit_s.bg_color = Color(0.5, 0.12, 0.12, 0.8)
		crit_s.set_corner_radius_all(2)
		crit_s.set_border_width_all(1)
		crit_s.border_color = Color(0.9, 0.3, 0.3, 0.8)
		crit_s.content_margin_left = 10; crit_s.content_margin_right = 10
		crit_s.content_margin_top = 3; crit_s.content_margin_bottom = 3
		_del_btn.add_theme_stylebox_override("normal", crit_s)
		_del_btn.add_theme_stylebox_override("hover", crit_s)
		# 3 秒后自动取消确认态
		if _del_reset_tween and _del_reset_tween.is_valid():
			_del_reset_tween.kill()
		_del_reset_tween = create_tween()
		_del_reset_tween.tween_interval(3.0)
		_del_reset_tween.tween_callback(_reset_delete_state)
		return

	# 第二次点击: 真正删除
	var entry = _filtered[_selected_idx]
	var target_id = entry.get("id", "")

	for i in range(_logs.size() - 1, -1, -1):
		if _logs[i].get("id", "") == target_id:
			_logs.remove_at(i)
			break

	SettingsManager.save_datalogs(_logs)
	_selected_idx = -1
	_del_pending = false
	_apply_filter()
	_update_detail_panel()

func _reset_delete_state() -> void:
	_del_pending = false
	if not is_instance_valid(_del_btn):
		return
	_del_btn.text = "删除记录"
	_del_btn.add_theme_color_override("font_color", Color(0.65, 0.4, 0.4, 0.6))
	var ds = StyleBoxFlat.new()
	ds.bg_color = Color(0.10, 0.04, 0.04, 0.4)
	ds.set_corner_radius_all(2)
	ds.set_border_width_all(1)
	ds.border_color = Color(0.4, 0.18, 0.18, 0.25)
	ds.content_margin_left = 10; ds.content_margin_right = 10
	ds.content_margin_top = 3; ds.content_margin_bottom = 3
	_del_btn.add_theme_stylebox_override("normal", ds)
	var dh = ds.duplicate()
	dh.bg_color = Color(0.25, 0.08, 0.08, 0.7)
	dh.border_color = Color(0.8, 0.3, 0.3, 0.5)
	_del_btn.add_theme_stylebox_override("hover", dh)
	_del_btn.add_theme_stylebox_override("pressed", dh)

func _on_content_changed() -> void:
	_save_timer.start()

func _do_save() -> void:
	if _selected_idx < 0 or _selected_idx >= _filtered.size():
		return
	var entry = _filtered[_selected_idx]
	var target_id = entry.get("id", "")

	# 更新数据
	entry["title"] = _title_edit.text
	entry["content"] = _content_edit.text
	entry["updated"] = Time.get_datetime_string_from_system(false, true)

	# 回写到主列表
	for i in range(_logs.size()):
		if _logs[i].get("id", "") == target_id:
			_logs[i] = entry
			break

	SettingsManager.save_datalogs(_logs)

	# 刷新卡片列表 (标题/预览可能变了)
	_render_list()

	# 显示保存徽章
	if _save_badge:
		_save_badge.text = "已保存"
		_save_badge.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.9))
		var tw = create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(func():
			if is_instance_valid(_save_badge):
				var created = entry.get("created", "")
				_save_badge.text = "创建于 %s" % created if created != "" else ""
				_save_badge.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.7, 0.6))
		)

func _on_tag_submitted(text: String) -> void:
	var tag = text.strip_edges()
	if tag == "" or _selected_idx < 0 or _selected_idx >= _filtered.size():
		return
	var entry = _filtered[_selected_idx]
	var tags = entry.get("tags", [])
	if tag in tags:
		_tag_input.text = ""
		return
	tags.append(tag)
	entry["tags"] = tags
	entry["updated"] = Time.get_datetime_string_from_system(false, true)
	_save_log_to_main(entry)
	_tag_input.text = ""
	_refresh_tags_display(tags)
	_render_list()

func _remove_tag(tag: String) -> void:
	if _selected_idx < 0 or _selected_idx >= _filtered.size():
		return
	var entry = _filtered[_selected_idx]
	var tags = entry.get("tags", [])
	tags.erase(tag)
	entry["tags"] = tags
	entry["updated"] = Time.get_datetime_string_from_system(false, true)
	_save_log_to_main(entry)
	_refresh_tags_display(tags)
	_render_list()

func _save_log_to_main(entry: Dictionary) -> void:
	var target_id = entry.get("id", "")
	for i in range(_logs.size()):
		if _logs[i].get("id", "") == target_id:
			_logs[i] = entry
			break
	SettingsManager.save_datalogs(_logs)

# ═══════════════════════════════════════════════
#  样式工具
# ═══════════════════════════════════════════════

func _style_filter_btn(btn: Button, active: bool) -> void:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(0)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 5; s.content_margin_bottom = 5
	if active:
		s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.30, 0.18, 0.7)
		s.border_width_bottom = 2
		s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.7)
		btn.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.85, 0.92, 1.0, 1.0))
	else:
		s.bg_color = Color(0.05, 0.07, 0.12, 0.25)
		s.border_width_bottom = 1
		s.border_color = Color(0.3, 0.35, 0.4, 0.15)
		btn.add_theme_color_override("font_color", Color(0.45, 0.55, 0.65, 0.6))
		btn.add_theme_color_override("font_hover_color", Color(0.60, 0.70, 0.80, 0.8))
	btn.add_theme_stylebox_override("normal", s)
	var sh = s.duplicate()
	sh.bg_color = Color.from_hsv(EventBus.ui_hue, 0.25, 0.15, 0.55)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sh)

func _make_line_edit(placeholder: String, min_width: int) -> LineEdit:
	var input = LineEdit.new()
	input.placeholder_text = placeholder
	if min_width > 0:
		input.custom_minimum_size = Vector2(min_width, 0)
	input.add_theme_font_size_override("font_size", 13)
	input.add_theme_color_override("font_color", Color(0.80, 0.85, 0.90, 0.9))
	input.add_theme_color_override("font_placeholder_color", Color(0.35, 0.40, 0.48, 0.35))
	input.add_theme_color_override("caret_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.9))
	var ls = StyleBoxFlat.new()
	ls.bg_color = Color(0.04, 0.05, 0.09, 0.5)
	ls.set_corner_radius_all(2)
	ls.set_content_margin_all(6)
	ls.border_width_bottom = 1
	ls.border_color = Color.from_hsv(EventBus.ui_hue, 0.25, 0.35, 0.15)
	input.add_theme_stylebox_override("normal", ls)
	var lf = ls.duplicate()
	lf.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.7, 0.5)
	input.add_theme_stylebox_override("focus", lf)
	return input

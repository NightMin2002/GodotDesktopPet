# datalog_tab.gd — 数据日志 Tab (装置终端 Tab 3)
# 双分区轻量笔记: 机体记录 (宠物) + 操作员备忘 (用户)
# 复用 ProfileStyles 样式工厂
extends HBoxContainer

# ── 状态 ──
var _source_filter: String = "user"  # "user" | "pet"
var _pet_category: String = ""       # "" = 分类首页, "sys:input" = 键鼠列表...
var _logs: Array = []
var _filtered: Array = []
var _selected_idx: int = -1  # 在 _filtered 中的索引

# ── 子模块 ──
const DatalogCategoryView = preload("res://ui/profile/datalog/datalog_category_view.gd")
const DatalogDetailView = preload("res://ui/profile/datalog/datalog_detail_view.gd")
const DatalogListView = preload("res://ui/profile/datalog/datalog_list_view.gd")
const DatalogWindowCards = preload("res://ui/profile/datalog/datalog_window_cards.gd")
var _ctx: Dictionary = {}  # 共享上下文, 传递给子模块

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
var _content_wrapper: HBoxContainer # 正文包裹 (CyberScrollIndicator.wrap 生成)
var _pet_content_rtl: RichTextLabel  # 机体记录只读展示 (支持 BBCode 绿字增量)
var _pet_content_wrapper: HBoxContainer  # 机体记录包裹
var _window_cards_wrapper: HBoxContainer  # 窗口包裹 (CyberScrollIndicator.wrap 生成)
var _window_cards_inner: VBoxContainer    # 卡片挂载点
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
		if _pet_category == "sys:input":
			EventBus.trigger_input_report.emit()
		elif _pet_category == "sys:window":
			EventBus.trigger_window_report.emit()
		# 刷新列表并自动选中更新的报告
		var tw = create_tween()
		tw.tween_interval(0.15)
		tw.tween_callback(func():
			if _source_filter == "pet" and _pet_category != "":
				_apply_filter()
				if not _filtered.is_empty():
					_select_log(0)
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

	# 科幻滚动指示器 (左栏列表, 与 left 同级)
	var list_indicator = CyberScrollIndicator.new()
	list_indicator.bind_scroll(_scroll)
	add_child(list_indicator)

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
	_content_wrapper = CyberScrollIndicator.wrap(_content_edit)

	# 机体记录只读展示 (RichTextLabel, 支持 BBCode 绿字)
	var pet_scroll = ScrollContainer.new()
	pet_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(pet_scroll)

	_pet_content_rtl = RichTextLabel.new()
	_pet_content_rtl.bbcode_enabled = true
	_pet_content_rtl.fit_content = true
	_pet_content_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pet_content_rtl.add_theme_font_size_override("normal_font_size", 14)
	_pet_content_rtl.add_theme_color_override("default_color", Color(0.80, 0.85, 0.90, 0.95))
	var rtl_bg = StyleBoxFlat.new()
	rtl_bg.bg_color = Color(0.03, 0.04, 0.08, 0.4)
	rtl_bg.set_corner_radius_all(2)
	rtl_bg.set_content_margin_all(12)
	_pet_content_rtl.add_theme_stylebox_override("normal", rtl_bg)
	pet_scroll.add_child(_pet_content_rtl)

	_pet_content_wrapper = CyberScrollIndicator.wrap(pet_scroll)
	_pet_content_wrapper.visible = false

	# 窗口卡片容器 (替代 TextEdit, 当显示 sys:window 条目时)
	var win_scroll = ScrollContainer.new()
	win_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	win_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(win_scroll)

	_window_cards_inner = VBoxContainer.new()
	_window_cards_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_window_cards_inner.add_theme_constant_override("separation", 0)
	win_scroll.add_child(_window_cards_inner)

	_window_cards_wrapper = CyberScrollIndicator.wrap(win_scroll)
	_window_cards_wrapper.visible = false

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

	# ── 初始化 ──
	_build_ctx()
	_update_pet_view()
	_update_detail_panel()

func _build_ctx() -> void:
	_ctx = {
		"owner": self,
		"logs": _logs,
		"filtered": _filtered,
		"selected_idx": _selected_idx,
		"del_pending": _del_pending,
		"del_reset_tween": _del_reset_tween,
		"animate_new_card": _animate_new_card,
		"ui": {
			"detail_panel": _detail_panel,
			"detail_empty": _detail_empty,
			"detail_header": _detail_header,
			"title_edit": _title_edit,
			"content_edit": _content_edit,
			"content_wrapper": _content_wrapper,
			"pet_content_rtl": _pet_content_rtl,
			"pet_content_wrapper": _pet_content_wrapper,
			"tags_flow": _tags_flow,
			"tag_input": _tag_input,
			"del_btn": _del_btn,
			"save_badge": _save_badge,
			"save_timer": _save_timer,
			"window_cards_wrapper": _window_cards_wrapper,
			"window_cards_inner": _window_cards_inner,
		},
		"render_list": _render_list,
		"apply_filter": _apply_filter,
		"make_tag_badge": _make_tag_badge,
		"render_window_cards": DatalogWindowCards.render,
	}

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_filter_btns.clear()
	_selected_idx = -1
	_del_pending = false
	_ctx = {}
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
		_report_btn.visible = (_pet_category in ["sys:input", "sys:window"])
		_apply_filter()

func _render_pet_categories() -> void:
	_logs = SettingsManager.get_datalogs()
	DatalogCategoryView.render(_category_container, _logs, _enter_pet_category)

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
#  日志卡片 + 标签徽章 (委托给 DatalogListView)
# ═══════════════════════════════════════════════

func _make_log_card(entry: Dictionary, idx: int) -> PanelContainer:
	return DatalogListView.make_log_card(entry, idx, _selected_idx, _select_log, _make_tag_badge)

func _make_tag_badge(tag_text: String, with_close: bool) -> Control:
	return DatalogListView.make_tag_badge(tag_text, with_close, _remove_tag)

# ═══════════════════════════════════════════════
#  选中 & 详情面板 (委托给 DatalogDetailView)
# ═══════════════════════════════════════════════

func _sync_ctx() -> void:
	_ctx.logs = _logs
	_ctx.filtered = _filtered
	_ctx.selected_idx = _selected_idx
	_ctx.del_pending = _del_pending
	_ctx.del_reset_tween = _del_reset_tween
	_ctx.animate_new_card = _animate_new_card

func _sync_from_ctx() -> void:
	_selected_idx = _ctx.selected_idx
	_del_pending = _ctx.del_pending
	_del_reset_tween = _ctx.del_reset_tween
	_animate_new_card = _ctx.animate_new_card

func _select_log(idx: int) -> void:
	_selected_idx = idx
	_sync_ctx()
	DatalogDetailView.select_log(_ctx, idx)
	_sync_from_ctx()

func _update_detail_panel() -> void:
	_sync_ctx()
	DatalogDetailView.update_detail_panel(_ctx)
	_sync_from_ctx()

func _on_new_pressed() -> void:
	_sync_ctx()
	DatalogDetailView.on_new_pressed(_ctx)
	_sync_from_ctx()

func _on_delete_pressed() -> void:
	_sync_ctx()
	DatalogDetailView.on_delete_pressed(_ctx)
	_sync_from_ctx()

func _reset_delete_state() -> void:
	_sync_ctx()
	DatalogDetailView.reset_delete_state(_ctx)
	_sync_from_ctx()

func _on_content_changed() -> void:
	_sync_ctx()
	DatalogDetailView.on_content_changed(_ctx)

func _do_save() -> void:
	_sync_ctx()
	DatalogDetailView.do_save(_ctx)
	_sync_from_ctx()

func _on_tag_submitted(text: String) -> void:
	_sync_ctx()
	DatalogDetailView.on_tag_submitted(_ctx, text)
	_sync_from_ctx()

func _remove_tag(tag: String) -> void:
	_sync_ctx()
	DatalogDetailView.remove_tag(_ctx, tag)
	_sync_from_ctx()

func _save_log_to_main(entry: Dictionary) -> void:
	_sync_ctx()
	DatalogDetailView._save_log_to_main(_ctx, entry)
	_sync_from_ctx()

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

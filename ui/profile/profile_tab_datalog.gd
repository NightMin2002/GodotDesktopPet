# profile_tab_datalog.gd — 数据日志 Tab (装置终端 Tab 4)
# 双分区轻量笔记: 机体记录 (宠物) + 操作员备忘 (用户)
# 复用 ProfileStyles 样式工厂
extends HBoxContainer

# ── 状态 ──
var _source_filter: String = "user"  # "user" | "pet"
var _logs: Array = []
var _filtered: Array = []
var _selected_idx: int = -1  # 在 _filtered 中的索引

# ── UI 引用 ──
var _list_vbox: VBoxContainer
var _detail_panel: VBoxContainer
var _title_edit: LineEdit
var _content_edit: TextEdit
var _tags_flow: HBoxContainer
var _tag_input: LineEdit
var _info_label: Label
var _empty_label: Label
var _save_badge: Label
var _new_btn: Button
var _del_btn: Button
var _search_edit: LineEdit
var _filter_btns: Array[Button] = []
var _scroll: ScrollContainer

# ── 防抖 ──
var _save_timer: Timer
var _search_timer: Timer

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
	left.custom_minimum_size = Vector2(260, 0)
	left.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(left)

	# 分区切换按钮
	var filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	left.add_child(filter_row)

	_filter_btns.clear()
	var filters = [["操作员备忘", "user"], ["机体记录", "pet"]]
	for f in filters:
		var btn = Button.new()
		btn.text = f[0]
		btn.add_theme_font_size_override("font_size", 13)
		var src = f[1]
		btn.pressed.connect(func(): _switch_source(src))
		_style_filter_btn(btn, src == _source_filter)
		_filter_btns.append(btn)
		filter_row.add_child(btn)

	# 搜索框
	_search_edit = _make_line_edit("搜索...", 0)
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(func(_t): _on_search_changed())
	left.add_child(_search_edit)

	# 工具栏
	var tool_row = HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 4)
	left.add_child(tool_row)

	var count_label = ProfileStyles.label_dim("", 11)
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label = count_label
	tool_row.add_child(count_label)

	_new_btn = Button.new()
	_new_btn.text = "+ 新建"
	_new_btn.add_theme_font_size_override("font_size", 13)
	_new_btn.add_theme_color_override("font_color", Color(0.7, 0.9, 0.8, 0.9))
	var nb_s = ProfileStyles.small_btn_normal()
	nb_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.22, 0.6)
	nb_s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.6, 0.5)
	_new_btn.add_theme_stylebox_override("normal", nb_s)
	var nb_h = nb_s.duplicate()
	nb_h.bg_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.3, 0.8)
	nb_h.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.7)
	_new_btn.add_theme_stylebox_override("hover", nb_h)
	_new_btn.add_theme_stylebox_override("pressed", nb_h)
	_new_btn.pressed.connect(_on_new_pressed)
	tool_row.add_child(_new_btn)

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
	_list_vbox.add_theme_constant_override("separation", 6)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(_list_vbox)

	# 空状态提示
	_empty_label = Label.new()
	_empty_label.text = "暂无记录"
	_empty_label.add_theme_font_size_override("font_size", 13)
	_empty_label.add_theme_color_override("font_color", Color(0.35, 0.4, 0.45, 0.6))
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label.visible = false
	_list_vbox.add_child(_empty_label)

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
	_detail_panel = VBoxContainer.new()
	_detail_panel.add_theme_constant_override("separation", 8)
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_detail_panel)

	# 标题编辑
	_title_edit = _make_line_edit("标题", 0)
	_title_edit.add_theme_font_size_override("font_size", 18)
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_edit.text_changed.connect(func(_t): _on_content_changed())
	_detail_panel.add_child(_title_edit)

	# 标签区
	var tags_row = HBoxContainer.new()
	tags_row.add_theme_constant_override("separation", 4)
	_detail_panel.add_child(tags_row)

	var tag_icon = ProfileStyles.label_dim("TAGS //", 11)
	tags_row.add_child(tag_icon)

	_tags_flow = HBoxContainer.new()
	_tags_flow.add_theme_constant_override("separation", 4)
	_tags_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tags_row.add_child(_tags_flow)

	_tag_input = _make_line_edit("+ 新标签", 80)
	_tag_input.add_theme_font_size_override("font_size", 11)
	_tag_input.custom_minimum_size = Vector2(80, 0)
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
	_content_edit.add_theme_color_override("font_placeholder_color", Color(0.35, 0.40, 0.48, 0.5))
	_content_edit.add_theme_color_override("caret_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.9))
	var te_bg = StyleBoxFlat.new()
	te_bg.bg_color = Color(0.03, 0.04, 0.08, 0.4)
	te_bg.set_corner_radius_all(2)
	te_bg.set_content_margin_all(10)
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
	_del_btn.text = "删除"
	_del_btn.add_theme_font_size_override("font_size", 12)
	_del_btn.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4, 0.7))
	_del_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.4, 0.35, 1.0))
	var ds = StyleBoxFlat.new()
	ds.bg_color = Color(0.12, 0.05, 0.05, 0.5)
	ds.set_corner_radius_all(3)
	ds.set_border_width_all(1)
	ds.border_color = Color(0.5, 0.2, 0.2, 0.3)
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
	_apply_filter()
	_update_detail_panel()

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_filter_btns.clear()
	_selected_idx = -1
	build()

# ═══════════════════════════════════════════════
#  分区 & 搜索
# ═══════════════════════════════════════════════

func _switch_source(src: String) -> void:
	if src == _source_filter:
		return
	_source_filter = src
	_selected_idx = -1
	# 用户分区可新建, 宠物分区不可新建
	_new_btn.visible = (_source_filter == "user")
	# 更新按钮样式
	for i in range(_filter_btns.size()):
		var is_active = (["user", "pet"][i] == _source_filter)
		_style_filter_btn(_filter_btns[i], is_active)
	_apply_filter()
	_update_detail_panel()

func _on_search_changed() -> void:
	_search_timer.start()

func _apply_filter() -> void:
	_logs = SettingsManager.get_datalogs()
	var keyword = _search_edit.text.strip_edges().to_lower() if _search_edit else ""

	_filtered.clear()
	for log in _logs:
		if log.get("source", "user") != _source_filter:
			continue
		if keyword != "":
			var title_match = log.get("title", "").to_lower().find(keyword) >= 0
			var content_match = log.get("content", "").to_lower().find(keyword) >= 0
			var tag_match = false
			for tag in log.get("tags", []):
				if str(tag).to_lower().find(keyword) >= 0:
					tag_match = true
					break
			if not title_match and not content_match and not tag_match:
				continue
		_filtered.append(log)

	# 按更新时间倒序
	_filtered.sort_custom(func(a, b): return a.get("updated", "") > b.get("updated", ""))

	_render_list()

func _render_list() -> void:
	if not _list_vbox:
		return
	# 清理旧卡片 (保留 empty_label)
	for child in _list_vbox.get_children():
		if child != _empty_label:
			child.queue_free()

	_empty_label.visible = _filtered.is_empty()
	if _info_label:
		_info_label.text = "%d 条记录" % _filtered.size()

	for i in range(_filtered.size()):
		var log = _filtered[i]
		var card = _make_log_card(log, i)
		_list_vbox.add_child(card)

	# 把 empty_label 移到末尾
	if _empty_label.get_parent() == _list_vbox:
		_list_vbox.move_child(_empty_label, _list_vbox.get_child_count() - 1)

# ═══════════════════════════════════════════════
#  日志卡片
# ═══════════════════════════════════════════════

func _make_log_card(log: Dictionary, idx: int) -> PanelContainer:
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
		cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.25, 0.12, 0.35)
		cs.border_width_left = 2
		cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.5, 0.3)
	cs.set_corner_radius_all(2)
	cs.content_margin_left = 12; cs.content_margin_right = 10
	cs.content_margin_top = 8; cs.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", cs)

	# hover 效果
	var hover_bg = Color.from_hsv(EventBus.ui_hue, 0.3, 0.18, 0.6)
	var normal_bg = cs.bg_color
	card.mouse_entered.connect(func():
		if idx != _selected_idx:
			cs.bg_color = hover_bg
	)
	card.mouse_exited.connect(func():
		if idx != _selected_idx:
			cs.bg_color = normal_bg
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

	var tags = log.get("tags", [])
	for tag in tags:
		if tags.find(tag) >= 3:
			break  # 最多显示 3 个
		var tl = Label.new()
		tl.text = str(tag)
		tl.add_theme_font_size_override("font_size", 10)
		tl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.75, 0.7))
		top_row.add_child(tl)

	var time_spacer = Control.new()
	time_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(time_spacer)

	var time_str = log.get("updated", log.get("created", ""))
	# 显示完整时间戳: "2026-05-15 09:00"
	if time_str.length() >= 16:
		time_str = time_str.substr(0, 16)  # "YYYY-MM-DD HH:MM"
	var time_l = Label.new()
	time_l.text = time_str
	time_l.add_theme_font_size_override("font_size", 10)
	time_l.add_theme_color_override("font_color", Color(0.35, 0.40, 0.45, 0.5))
	time_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(time_l)

	# 标题
	var title_l = Label.new()
	title_l.text = log.get("title", "无标题")
	title_l.add_theme_font_size_override("font_size", 14)
	title_l.add_theme_color_override("font_color", Color(0.82, 0.87, 0.92, 0.95) if is_sel else Color(0.70, 0.76, 0.82, 0.85))
	title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_l)

	# 内容预览
	var preview_text = log.get("content", "").strip_edges()
	if preview_text.length() > 60:
		preview_text = preview_text.substr(0, 60) + "..."
	if preview_text != "":
		var preview_l = Label.new()
		preview_l.text = preview_text
		preview_l.add_theme_font_size_override("font_size", 11)
		preview_l.add_theme_color_override("font_color", Color(0.40, 0.45, 0.50, 0.5))
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
#  选中 & 详情面板
# ═══════════════════════════════════════════════

func _select_log(idx: int) -> void:
	_selected_idx = idx
	_render_list()
	_update_detail_panel()

func _update_detail_panel() -> void:
	if _selected_idx < 0 or _selected_idx >= _filtered.size():
		_title_edit.text = ""
		_title_edit.editable = false
		_content_edit.text = ""
		_content_edit.editable = false
		_del_btn.visible = false
		_save_badge.text = ""
		_tag_input.visible = false
		_refresh_tags_display([])
		return

	var log = _filtered[_selected_idx]
	var is_pet = (log.get("source", "user") == "pet")

	_title_edit.text = log.get("title", "")
	_title_edit.editable = true  # 标题始终可编辑

	_content_edit.text = log.get("content", "")
	_content_edit.editable = not is_pet  # 宠物日志正文不可编辑

	_del_btn.visible = true
	_tag_input.visible = true

	var created = log.get("created", "")
	var updated = log.get("updated", "")
	_save_badge.text = "创建于 %s" % created if created != "" else ""

	_refresh_tags_display(log.get("tags", []))

func _refresh_tags_display(tags: Array) -> void:
	for child in _tags_flow.get_children():
		child.queue_free()

	for tag in tags:
		var tag_panel = HBoxContainer.new()
		tag_panel.add_theme_constant_override("separation", 2)

		var tl = Label.new()
		tl.text = str(tag)
		tl.add_theme_font_size_override("font_size", 11)
		tl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.8))
		tag_panel.add_child(tl)

		# x 删除按钮
		var x_btn = Button.new()
		x_btn.text = "x"
		x_btn.add_theme_font_size_override("font_size", 9)
		x_btn.add_theme_color_override("font_color", Color(0.5, 0.35, 0.35, 0.5))
		x_btn.add_theme_color_override("font_hover_color", Color(0.9, 0.4, 0.4, 0.9))
		var x_s = StyleBoxEmpty.new()
		x_btn.add_theme_stylebox_override("normal", x_s)
		x_btn.add_theme_stylebox_override("hover", x_s)
		x_btn.add_theme_stylebox_override("pressed", x_s)
		x_btn.custom_minimum_size = Vector2(14, 14)
		var tag_ref = str(tag)
		x_btn.pressed.connect(func(): _remove_tag(tag_ref))
		tag_panel.add_child(x_btn)

		_tags_flow.add_child(tag_panel)

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
	_apply_filter()
	_update_detail_panel()

	# 聚焦标题并全选, 方便直接覆盖输入
	if _title_edit:
		_title_edit.grab_focus()
		_title_edit.select_all()

func _on_delete_pressed() -> void:
	if _selected_idx < 0 or _selected_idx >= _filtered.size():
		return
	var log = _filtered[_selected_idx]
	var target_id = log.get("id", "")

	# 从主列表删除
	for i in range(_logs.size() - 1, -1, -1):
		if _logs[i].get("id", "") == target_id:
			_logs.remove_at(i)
			break

	SettingsManager.save_datalogs(_logs)
	_selected_idx = -1
	_apply_filter()
	_update_detail_panel()

func _on_content_changed() -> void:
	_save_timer.start()

func _do_save() -> void:
	if _selected_idx < 0 or _selected_idx >= _filtered.size():
		return
	var log = _filtered[_selected_idx]
	var target_id = log.get("id", "")

	# 更新数据
	log["title"] = _title_edit.text
	log["content"] = _content_edit.text
	log["updated"] = Time.get_datetime_string_from_system(false, true)

	# 回写到主列表
	for i in range(_logs.size()):
		if _logs[i].get("id", "") == target_id:
			_logs[i] = log
			break

	SettingsManager.save_datalogs(_logs)

	# 刷新卡片列表 (标题/预览可能变了)
	_render_list()

	# 显示保存徽章
	if _save_badge:
		_save_badge.text = "已保存"
		_save_badge.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.8))
		var tw = create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(func():
			if is_instance_valid(_save_badge):
				var created = log.get("created", "")
				_save_badge.text = "创建于 %s" % created if created != "" else ""
				_save_badge.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.7, 0.6))
		)

func _on_tag_submitted(text: String) -> void:
	var tag = text.strip_edges()
	if tag == "" or _selected_idx < 0 or _selected_idx >= _filtered.size():
		return
	var log = _filtered[_selected_idx]
	var tags = log.get("tags", [])
	if tag in tags:
		_tag_input.text = ""
		return
	tags.append(tag)
	log["tags"] = tags
	log["updated"] = Time.get_datetime_string_from_system(false, true)
	_save_log_to_main(log)
	_tag_input.text = ""
	_refresh_tags_display(tags)
	_render_list()

func _remove_tag(tag: String) -> void:
	if _selected_idx < 0 or _selected_idx >= _filtered.size():
		return
	var log = _filtered[_selected_idx]
	var tags = log.get("tags", [])
	tags.erase(tag)
	log["tags"] = tags
	log["updated"] = Time.get_datetime_string_from_system(false, true)
	_save_log_to_main(log)
	_refresh_tags_display(tags)
	_render_list()

func _save_log_to_main(log: Dictionary) -> void:
	var target_id = log.get("id", "")
	for i in range(_logs.size()):
		if _logs[i].get("id", "") == target_id:
			_logs[i] = log
			break
	SettingsManager.save_datalogs(_logs)

# ═══════════════════════════════════════════════
#  样式工具
# ═══════════════════════════════════════════════

func _style_filter_btn(btn: Button, active: bool) -> void:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(2)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 4; s.content_margin_bottom = 4
	if active:
		s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.22, 0.7)
		s.border_width_bottom = 2
		s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.7)
		btn.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
	else:
		s.bg_color = Color(0.06, 0.08, 0.14, 0.3)
		s.border_width_bottom = 1
		s.border_color = Color(0, 0, 0, 0)
		btn.add_theme_color_override("font_color", Color(0.50, 0.60, 0.70, 0.7))
	btn.add_theme_stylebox_override("normal", s)
	var sh = s.duplicate()
	sh.bg_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.18, 0.6)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sh)

func _make_line_edit(placeholder: String, min_width: int) -> LineEdit:
	var input = LineEdit.new()
	input.placeholder_text = placeholder
	if min_width > 0:
		input.custom_minimum_size = Vector2(min_width, 0)
	input.add_theme_font_size_override("font_size", 13)
	input.add_theme_color_override("font_color", Color(0.80, 0.85, 0.90, 0.9))
	input.add_theme_color_override("font_placeholder_color", Color(0.35, 0.40, 0.48, 0.4))
	input.add_theme_color_override("caret_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.9))
	var ls = StyleBoxFlat.new()
	ls.bg_color = Color(0.04, 0.06, 0.10, 0.5)
	ls.set_corner_radius_all(2)
	ls.set_content_margin_all(6)
	ls.border_width_bottom = 1
	ls.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.2)
	input.add_theme_stylebox_override("normal", ls)
	var lf = ls.duplicate()
	lf.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.7, 0.5)
	input.add_theme_stylebox_override("focus", lf)
	return input

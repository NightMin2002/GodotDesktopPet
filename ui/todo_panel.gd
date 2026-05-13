# todo_panel.gd — 待办清单面板 (主从双栏)
# 左栏: 待办列表 | 右栏: 选中项目的备注
# 视觉样式由 todo_themes/ 下的主题模块提供
extends CanvasLayer

# ═══════════════════════════════════════════════
#  主题注册表
# ═══════════════════════════════════════════════

const _THEME_IDS   := ["retro_gray", "dark_terminal", "holo_glass", "blueprint_draft", "neon_cyber", "paper_note", "blackboard_chalk"]
const _THEME_NAMES := ["\u7070\u767d", "\u7ec8\u7aef", "\u5168\u606f", "\u84dd\u56fe", "\u8367\u5149", "\u4fbf\u7b3a", "\u9ed1\u677f"]

var theme: TodoThemeBase
var _current_theme_idx: int = 0

var panel: PanelContainer
var list_box: VBoxContainer
var scroll: ScrollContainer
var note_edit: TextEdit
var note_title: LineEdit
var note_empty: VBoxContainer
var save_badge: PanelContainer
var save_badge_label: Label
var scroll_hint_top: Panel
var scroll_hint_btm: Panel

var _selected_idx: int = -1
var _guard_frames := 0
var _save_timer: Timer
var _save_fade_tween: Tween

# ── 引用 ──
var _title_label: Label
var _progress_label: Label
var _progress_blocks: Array[Panel] = []
var _theme_btn: Button

var _new_btn: Button
var _vsep_style: StyleBoxFlat
var _note_title_sep: HSeparator

# ── 拖拽 ──
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _title_bar: Control

# ── 面板尺寸 ──
var _panel_w: float = 900
var _panel_h: float = 600

func _ready() -> void:
	_current_theme_idx = SettingsManager.get_int("todo_theme", 0)
	if _current_theme_idx < 0 or _current_theme_idx >= _THEME_IDS.size():
		_current_theme_idx = 0
	theme = _create_theme(_current_theme_idx)
	_calc_panel_size()
	_build_ui()
	EventBus.show_todo_panel.connect(_toggle_panel)
	EventBus.ui_theme_changed.connect(_apply_ui_theme)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.6
	_save_timer.timeout.connect(_do_save_note)
	add_child(_save_timer)

func _create_theme(idx: int) -> TodoThemeBase:
	match idx:
		1: return TodoThemeDarkTerminal.new()
		2: return TodoThemeHoloGlass.new()
		3: return TodoThemeBlueprintDraft.new()
		4: return TodoThemeNeonCyber.new()
		5: return TodoThemePaperNote.new()
		6: return TodoThemeBlackboardChalk.new()
		_: return TodoThemeRetroGray.new()

func _calc_panel_size() -> void:
	var vp = get_viewport().get_visible_rect().size
	_panel_w = clampf(vp.x * 0.7, 700, 1600)
	_panel_h = clampf(vp.y * 0.7, 450, 1000)

func _clamp_pos(pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - _panel_w - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - _panel_h - 4.0))
	return pos

# ═══════════════════════════════════════════════
#  主题切换
# ═══════════════════════════════════════════════

func _cycle_theme() -> void:
	var next_idx = (_current_theme_idx + 1) % _THEME_IDS.size()
	_switch_theme_to(next_idx)

func _switch_theme_to(idx: int) -> void:
	var was_visible = panel.visible
	var old_pos = panel.position if was_visible else Vector2.ZERO
	var old_selected = _selected_idx

	# 保存选择
	_current_theme_idx = idx
	SettingsManager.set_int("todo_theme", idx)

	# 创建新主题
	theme = _create_theme(idx)

	# 移除旧面板
	if panel and is_instance_valid(panel):
		panel.queue_free()
	_progress_blocks.clear()

	# 等旧面板释放
	await get_tree().process_frame

	# 重建 UI
	_build_ui()
	_selected_idx = old_selected
	_refresh_list()
	_refresh_right_panel()
	_update_theme_btn_text()

	if was_visible:
		_calc_panel_size()
		panel.custom_minimum_size = Vector2(_panel_w, _panel_h)
		panel.position = _clamp_pos(old_pos)
		panel.modulate.a = 1.0
		panel.scale = Vector2.ONE
		panel.show()
		panel.pivot_offset = panel.size / 2.0

func _update_theme_btn_text() -> void:
	if _theme_btn:
		_theme_btn.text = _THEME_NAMES[_current_theme_idx]

# ═══════════════════════════════════════════════
#  UI 构建
# ═══════════════════════════════════════════════

func _build_ui() -> void:
	layer = 101

	panel = theme.create_panel()
	panel.visible = false
	panel.custom_minimum_size = Vector2(_panel_w, _panel_h)
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", theme.panel_margins[0])
	margin.add_theme_constant_override("margin_top", theme.panel_margins[1])
	margin.add_theme_constant_override("margin_right", theme.panel_margins[2])
	margin.add_theme_constant_override("margin_bottom", theme.panel_margins[3])
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(margin)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", theme.outer_spacing)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(outer)

	# ── 标题栏 ──
	_title_bar = _build_title_bar()
	outer.add_child(_title_bar)
	outer.add_child(theme.make_separator())

	# ═══ 双栏 ═══
	var split = HBoxContainer.new()
	split.add_theme_constant_override("separation", 0)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(split)

	# ── 左栏 ──
	var left_col = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", theme.left_spacing)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = theme.col_ratio[0]
	split.add_child(left_col)

	_new_btn = theme.make_add_button("+ \u65b0\u5efa\u5f85\u529e")
	_new_btn.pressed.connect(_on_add_pressed)
	left_col.add_child(_new_btn)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", theme.list_spacing)
	scroll.add_child(list_box)

	scroll_hint_top = _make_scroll_hint(true)
	scroll_hint_btm = _make_scroll_hint(false)
	scroll.get_v_scroll_bar().value_changed.connect(func(_v): _update_scroll_hints())

	var bottom_spacer = Control.new()
	bottom_spacer.custom_minimum_size.y = theme.bottom_pad
	left_col.add_child(bottom_spacer)

	# ── 竖分割线 ──
	var vsep = VSeparator.new()
	_vsep_style = theme.apply_vsep_style(vsep)
	split.add_child(vsep)

	# ── 右栏 ──
	var right_col = VBoxContainer.new()
	right_col.add_theme_constant_override("separation", theme.right_spacing)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = theme.col_ratio[1]
	split.add_child(right_col)

	var title_row = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right_col.add_child(title_row)

	note_title = LineEdit.new()
	note_title.placeholder_text = "\u5f85\u529e\u540d\u79f0"
	note_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme.apply_note_title_style(note_title)
	note_title.text_submitted.connect(_on_title_edited)
	note_title.focus_exited.connect(_on_title_focus_lost)
	title_row.add_child(note_title)

	save_badge = PanelContainer.new()
	save_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_badge.modulate.a = 0.0
	save_badge_label = Label.new()
	save_badge_label.text = "\u5df2\u4fdd\u5b58"
	save_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme.apply_save_badge_style(save_badge, save_badge_label)
	save_badge.add_child(save_badge_label)
	title_row.add_child(save_badge)

	_note_title_sep = theme.make_separator()
	right_col.add_child(_note_title_sep)

	note_edit = TextEdit.new()
	note_edit.placeholder_text = "\u5728\u6b64\u7f16\u8f91\u5907\u6ce8\u5185\u5bb9..."
	note_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	theme.apply_note_edit_style(note_edit)
	note_edit.text_changed.connect(_on_note_text_changed)
	note_edit.visible = false
	right_col.add_child(note_edit)

	note_empty = VBoxContainer.new()
	note_empty.add_theme_constant_override("separation", 12)
	note_empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	note_empty.alignment = BoxContainer.ALIGNMENT_CENTER

	var ei = Label.new()
	ei.text = ":"
	ei.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ei.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme.apply_empty_icon_style(ei)
	note_empty.add_child(ei)

	var eh = Label.new()
	eh.text = "\u70b9\u51fb\u5de6\u4fa7\u5f85\u529e\u67e5\u770b\u8be6\u60c5"
	eh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme.apply_empty_hint_style(eh)
	note_empty.add_child(eh)
	right_col.add_child(note_empty)

	_refresh_list()
	_refresh_right_panel()

# ── 标题栏 ──

func _build_title_bar() -> Control:
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_title_bar_input)
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE

	_title_label = Label.new()
	_title_label.text = "\u5f85\u529e\u6e05\u5355"
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme.apply_title_label_style(_title_label)
	bar.add_child(_title_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	_progress_label = Label.new()
	_progress_label.text = "0/0"
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme.apply_progress_label_style(_progress_label)
	bar.add_child(_progress_label)

	var blocks_box = HBoxContainer.new()
	blocks_box.add_theme_constant_override("separation", theme.progress_block_sp)
	blocks_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(blocks_box)
	for i in range(10):
		var block = Panel.new()
		theme.apply_progress_block_style(block)
		block.visible = false
		blocks_box.add_child(block)
		_progress_blocks.append(block)

	# 主题切换按钮
	_theme_btn = theme.make_theme_button(_THEME_NAMES[_current_theme_idx])
	_theme_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_theme_btn.pressed.connect(_cycle_theme)
	bar.add_child(_theme_btn)

	var close_btn = theme.make_close_button("\u5173\u95ed")
	close_btn.pressed.connect(_close_panel)
	bar.add_child(close_btn)

	return bar

# ═══════════════════════════════════════════════
#  滚动提示条
# ═══════════════════════════════════════════════

func _make_scroll_hint(is_top: bool) -> Panel:
	var hint = Panel.new()
	hint.custom_minimum_size = Vector2(0, 3)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_stylebox_override("panel", theme.make_scroll_hint_style())
	hint.visible = false
	_add_hint_deferred.call_deferred(hint, is_top)
	return hint

func _add_hint_deferred(hint: Panel, is_top: bool) -> void:
	var left_col = scroll.get_parent()
	if not left_col:
		return
	if is_top:
		left_col.add_child(hint)
		left_col.move_child(hint, left_col.get_children().find(scroll))
	else:
		var scroll_idx = left_col.get_children().find(scroll)
		left_col.add_child(hint)
		left_col.move_child(hint, scroll_idx + 1)

func _update_scroll_hints() -> void:
	var vbar = scroll.get_v_scroll_bar()
	if not vbar:
		return
	var can_scroll = vbar.max_value > vbar.page
	scroll_hint_top.visible = can_scroll and vbar.value > 2
	scroll_hint_btm.visible = can_scroll and vbar.value < vbar.max_value - vbar.page - 2

# ═══════════════════════════════════════════════
#  左栏列表
# ═══════════════════════════════════════════════

func _refresh_list() -> void:
	for child in list_box.get_children():
		child.queue_free()

	var todos = SettingsManager.get_todos()

	if todos.is_empty():
		var empty_box = CenterContainer.new()
		empty_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_box.custom_minimum_size.y = 100
		var lbl = Label.new()
		lbl.text = "\u8fd8\u6ca1\u6709\u5f85\u529e\u54e6\n\u70b9\u51fb\u4e0a\u65b9\u6309\u94ae\u521b\u5efa\u4e00\u4e2a\u5427"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		theme.apply_empty_hint_style(lbl)
		empty_box.add_child(lbl)
		list_box.add_child(empty_box)
		_update_progress(todos)
		_update_scroll_hints_deferred()
		return

	for i in range(todos.size()):
		var t = todos[i]
		var is_done: bool = t.get("done", false)
		var is_selected: bool = (i == _selected_idx)
		var has_note: bool = not t.get("notes", "").is_empty()

		var card = PanelContainer.new()
		var card_style = theme.make_card_style(is_done, is_selected)
		card.add_theme_stylebox_override("panel", card_style)

		var cs_ref = card_style
		var sel_ref = is_selected
		var idx_sel = i
		card.mouse_entered.connect(func():
			if not sel_ref:
				card.add_theme_stylebox_override("panel", theme.make_card_hover_style(cs_ref))
		)
		card.mouse_exited.connect(func():
			if not sel_ref:
				card.add_theme_stylebox_override("panel", cs_ref)
		)
		card.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_selected_idx = idx_sel
				_refresh_list()
				_refresh_right_panel()
		)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(row)

		var check_btn = theme.make_checkbox(is_done)
		var idx_c = i
		check_btn.pressed.connect(func(): _toggle_todo(idx_c))
		row.add_child(check_btn)

		var title_lbl = Label.new()
		title_lbl.text = t.get("text", "(\u672a\u547d\u540d)")
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		theme.apply_card_title_style(title_lbl, is_done, is_selected)
		row.add_child(title_lbl)

		if has_note:
			var ni = Label.new()
			ni.text = ":"
			ni.mouse_filter = Control.MOUSE_FILTER_IGNORE
			theme.apply_note_indicator_style(ni)
			row.add_child(ni)

		var del_btn = theme.make_delete_button("\u5220\u9664")
		var idx_d = i
		var card_ref = card
		del_btn.pressed.connect(func(): _delete_todo_animated(idx_d, card_ref))
		row.add_child(del_btn)

		list_box.add_child(card)

	_update_progress(todos)
	_update_scroll_hints_deferred()

func _update_scroll_hints_deferred() -> void:
	(func(): _update_scroll_hints()).call_deferred()

# ═══════════════════════════════════════════════
#  右栏备注
# ═══════════════════════════════════════════════

func _refresh_right_panel() -> void:
	var todos = SettingsManager.get_todos()
	if _selected_idx < 0 or _selected_idx >= todos.size():
		note_edit.visible = false
		note_title.text = ""
		note_title.editable = false
		_note_title_sep.visible = false
		note_empty.visible = true
		save_badge.modulate.a = 0.0
		return

	var t = todos[_selected_idx]
	note_title.editable = true
	note_title.text = t.get("text", "")
	_note_title_sep.visible = true
	note_edit.visible = true
	note_empty.visible = false
	save_badge.modulate.a = 0.0

	note_edit.text_changed.disconnect(_on_note_text_changed)
	note_edit.text = t.get("notes", "")
	note_edit.text_changed.connect(_on_note_text_changed)

func _on_title_edited(_new: String) -> void:
	_save_title()
	note_title.release_focus()

func _on_title_focus_lost() -> void:
	_save_title()

func _save_title() -> void:
	if _selected_idx < 0:
		return
	var todos = SettingsManager.get_todos()
	if _selected_idx < todos.size():
		var t = note_title.text.strip_edges()
		if t.is_empty():
			t = "(\u672a\u547d\u540d)"
			note_title.text = t
		todos[_selected_idx]["text"] = t
		SettingsManager.save_todos(todos)
		_refresh_list()
		_show_saved()

func _on_note_text_changed() -> void:
	_save_timer.start()

func _do_save_note() -> void:
	if _selected_idx < 0:
		return
	var todos = SettingsManager.get_todos()
	if _selected_idx < todos.size():
		todos[_selected_idx]["notes"] = note_edit.text
		SettingsManager.save_todos(todos)
		_refresh_list()
		_show_saved()

func _show_saved() -> void:
	save_badge.modulate.a = 1.0
	if _save_fade_tween and _save_fade_tween.is_valid():
		_save_fade_tween.kill()
	_save_fade_tween = create_tween()
	_save_fade_tween.tween_interval(1.8)
	_save_fade_tween.tween_property(save_badge, "modulate:a", 0.0, 0.4)

# ═══════════════════════════════════════════════
#  进度
# ═══════════════════════════════════════════════

func _update_progress(todos: Array) -> void:
	var total = todos.size()
	var done = 0
	for t in todos:
		if t.get("done", false):
			done += 1

	_progress_label.text = "%d/%d" % [done, total]

	for i in range(_progress_blocks.size()):
		if i < total:
			_progress_blocks[i].visible = true
			theme.update_progress_block(_progress_blocks[i], i < done)
		else:
			_progress_blocks[i].visible = false

	if total > 0 and done >= total:
		theme.apply_progress_complete(_progress_label, true)
		_title_label.text = "\u5168\u90e8\u5b8c\u6210\u4e86"
	else:
		theme.apply_progress_complete(_progress_label, false)
		_title_label.text = "\u5f85\u529e\u6e05\u5355"

	EventBus.todo_count_changed.emit(total - done, total)

# ═══════════════════════════════════════════════
#  操作
# ═══════════════════════════════════════════════

func _on_add_pressed() -> void:
	var todos = SettingsManager.get_todos()
	todos.append({
		"id": _gen_id(),
		"text": "(\u672a\u547d\u540d)",
		"notes": "",
		"done": false,
		"created": Time.get_date_string_from_system(),
	})
	SettingsManager.save_todos(todos)
	_selected_idx = todos.size() - 1
	_refresh_list()
	_refresh_right_panel()
	note_title.grab_focus()
	note_title.select_all()

func _toggle_todo(idx: int) -> void:
	var todos = SettingsManager.get_todos()
	if idx < todos.size():
		todos[idx]["done"] = not todos[idx].get("done", false)
		SettingsManager.save_todos(todos)
		_refresh_list()
		_refresh_right_panel()

func _delete_todo(idx: int) -> void:
	var todos = SettingsManager.get_todos()
	if idx < todos.size():
		todos.remove_at(idx)
		if _selected_idx == idx:
			_selected_idx = -1
		elif _selected_idx > idx:
			_selected_idx -= 1
		SettingsManager.save_todos(todos)
		_refresh_list()
		_refresh_right_panel()

func _delete_todo_animated(idx: int, card: Control) -> void:
	card.pivot_offset = card.size / 2.0
	var tw = create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 0.0, 0.12)
	tw.tween_property(card, "scale", Vector2(0.9, 0.9), 0.12)
	tw.finished.connect(func(): _delete_todo(idx))

func _gen_id() -> String:
	return "%d_%d" % [Time.get_unix_time_from_system(), randi()]

# ═══════════════════════════════════════════════
#  面板显隐
# ═══════════════════════════════════════════════

func _toggle_panel() -> void:
	if panel.visible:
		_close_panel()
	else:
		_open_panel()

func _open_panel() -> void:
	_calc_panel_size()
	panel.custom_minimum_size = Vector2(_panel_w, _panel_h)
	_selected_idx = -1
	_refresh_list()
	_refresh_right_panel()
	EventBus.context_menu_toggled.emit(true)
	get_window().grab_focus()

	var vp = get_viewport().get_visible_rect().size
	panel.position = _clamp_pos(Vector2((vp.x - _panel_w) * 0.5, (vp.y - _panel_h) * 0.5))
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.8, 0.8)
	panel.show()
	await get_tree().process_frame
	panel.pivot_offset = panel.size / 2.0
	_guard_frames = 5

	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _close_panel() -> void:
	_dragging = false
	panel.pivot_offset = panel.size / 2.0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.1)
	tween.tween_property(panel, "scale", Vector2(0.7, 0.7), 0.1)
	tween.finished.connect(func():
		panel.hide()
		EventBus.context_menu_toggled.emit(false)
	)

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible or _guard_frames > 0:
		return
	if event is InputEventMouseButton and event.pressed:
		if _dragging:
			return
		var local = panel.get_local_mouse_position()
		if not Rect2(Vector2.ZERO, panel.size).has_point(local):
			_close_panel()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _guard_frames > 0:
		_guard_frames -= 1

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_viewport().get_mouse_position() - panel.position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		panel.position = get_viewport().get_mouse_position() - _drag_offset
		panel.position = _clamp_pos(panel.position)

# ═══════════════════════════════════════════════
#  主题色
# ═══════════════════════════════════════════════

func _apply_ui_theme(_hue: float) -> void:
	theme.update_panel_hue(panel, _hue)
	if panel.visible:
		_refresh_list()

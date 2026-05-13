# todo_panel.gd — 待办清单面板 (主从双栏)
# 左栏: 待办列表 | 右栏: 选中项目的备注
# 视觉样式由 TodoThemeBase 及其子类提供
extends CanvasLayer

# ═══════════════════════════════════════════════
#  主题注册表 — 新增主题只需往这两个数组加一条
# ═══════════════════════════════════════════════

const _THEME_NAMES := ["默认", "黑板", "赛博终端", "蓝图", "手账", "掌机", "小票", "老黄历"]

var theme: TodoThemeBase
var _current_theme_idx: int = 0

var panel: PanelContainer
var scroll: ScrollContainer
var note_edit: TextEdit
var note_title: LineEdit
var note_empty: VBoxContainer
var save_badge: PanelContainer
var save_badge_label: Label
var _fade_top: Control
var _fade_btm: Control

var _selected_idx: int = -1
var _guard_frames := 0
var _save_timer: Timer
var _save_fade_tween: Tween

# ── 引用 ──
var _title_label: Label
var _theme_btn: Button
var _progress_indicator: Control

var _new_btn: Button
var _vsep_style: StyleBoxFlat
var _note_title_sep: HSeparator

# ── 虚拟滚动列表 ──
const _POOL_BUFFER := 3
var _spacer: Control
var _pool: Array[Dictionary] = []
var _row_h: float = 48.0
var _empty_hint: CenterContainer
var _scrollbar: Control
var _scroll_area: HBoxContainer

# ── 拖拽 ──
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _title_bar: Control

# ── 面板尺寸 ──
var _panel_w: float = 900
var _panel_h: float = 600

func _ready() -> void:
	_current_theme_idx = SettingsManager.get_int("todo_theme", 0)
	if _current_theme_idx < 0 or _current_theme_idx >= _THEME_NAMES.size():
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
		1: return TodoThemeBlackboardChalk.new()
		2: return TodoThemeCyberTerminal.new()
		3: return TodoThemeBlueprintDraft.new()
		4: return TodoThemeNotebookPostit.new()
		5: return TodoThemeRetroHandheld.new()
		6: return TodoThemeReceiptPaper.new()
		7: return TodoThemeVintageCalendar.new()
		_:
			var t = TodoThemeBase.new()
			t._from_seeds(
				Color(0.12, 0.14, 0.20),
				Color(0.88, 0.90, 0.96),
				Color(0.35, 0.70, 0.90),
				Color(0.90, 0.30, 0.25),
				0.95
			)
			return t

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
	var next_idx = (_current_theme_idx + 1) % _THEME_NAMES.size()
	_switch_theme_to(next_idx)

func _switch_theme_to(idx: int) -> void:
	var was_visible = panel.visible
	var old_pos = panel.position if was_visible else Vector2.ZERO
	var old_selected = _selected_idx

	_current_theme_idx = idx
	SettingsManager.set_int("todo_theme", idx)
	theme = _create_theme(idx)

	if panel and is_instance_valid(panel):
		panel.queue_free()


	await get_tree().process_frame

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
	# 延迟一帧等布局算完再刷新卡片宽度
	(func(): _refresh_list(); _update_fades()).call_deferred()

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

	# ── 进度指示器 (独占一行) ──
	_progress_indicator = theme.make_progress_indicator()
	if _progress_indicator:
		_progress_indicator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		outer.add_child(_progress_indicator)

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

	# 包裹层：普通 Control 让 fade 遮罩能用锚点叠加
	var _scroll_wrapper = Control.new()
	_scroll_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_wrapper.clip_contents = true
	left_col.add_child(_scroll_wrapper)

	_scroll_area = HBoxContainer.new()
	_scroll_area.add_theme_constant_override("separation", 0)
	_scroll_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll_wrapper.add_child(_scroll_area)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_area.add_child(scroll)

	_scrollbar = theme.make_scrollbar()
	_scrollbar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_area.add_child(_scrollbar)

	_spacer = Control.new()
	_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_spacer)
	_row_h = _calc_row_h()
	_pool.clear()

	scroll.get_v_scroll_bar().value_changed.connect(func(_v): _refresh_list(); _update_fades())
	_scrollbar.bind(scroll)

	# 滚动指示条 — 叠加在 wrapper 上，锚点定位生效
	_fade_top = _ScrollFade.new(theme, true)
	_fade_btm = _ScrollFade.new(theme, false)
	_fade_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_btm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_wrapper.add_child(_fade_top)
	_scroll_wrapper.add_child(_fade_btm)

	_empty_hint = CenterContainer.new()
	_empty_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_hint.custom_minimum_size.y = 100
	var _eh_lbl = Label.new()
	_eh_lbl.text = "\u8fd8\u6ca1\u6709\u5f85\u529e\u54e6\n\u70b9\u51fb\u4e0a\u65b9\u6309\u94ae\u521b\u5efa\u4e00\u4e2a\u5427"
	_eh_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	theme.apply_empty_hint_style(_eh_lbl)
	_empty_hint.add_child(_eh_lbl)
	_empty_hint.visible = false
	left_col.add_child(_empty_hint)

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
	_title_label.text = "待办清单"
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme.apply_title_label_style(_title_label)
	bar.add_child(_title_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	# 主题切换按钮
	_theme_btn = theme.make_theme_button(_THEME_NAMES[_current_theme_idx])
	_theme_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_theme_btn.pressed.connect(_cycle_theme)
	bar.add_child(_theme_btn)

	var close_btn = theme.make_close_button("关闭")
	close_btn.pressed.connect(_close_panel)
	bar.add_child(close_btn)

	return bar

# ═══════════════════════════════════════════════
#  滚动指示器 — 隐藏条目计数徽章
# ═══════════════════════════════════════════════

class _ScrollFade extends Control:
	var _t: TodoThemeBase
	var _is_top: bool
	var _alpha := 0.0
	var _count := 0
	const BADGE_H := 22.0

	func _init(t: TodoThemeBase, is_top: bool) -> void:
		_t = t; _is_top = is_top
		anchor_left = 0; anchor_right = 1
		if is_top:
			anchor_top = 0; anchor_bottom = 0
			offset_bottom = BADGE_H
		else:
			anchor_top = 1; anchor_bottom = 1
			offset_top = -BADGE_H

	func update_state(alpha: float, count: int) -> void:
		var new_a = clampf(alpha, 0.0, 1.0)
		if absf(new_a - _alpha) > 0.01 or count != _count:
			_alpha = new_a
			_count = count
			queue_redraw()

	func _draw() -> void:
		if _alpha < 0.01 or _count <= 0: return
		var font = ThemeDB.fallback_font
		var fs := 11
		var arrow = "\u25b2 " if _is_top else "\u25bc "
		var text = arrow + str(_count)
		var ts = font.get_string_size(text, 0, -1, fs)
		var pill_w = ts.x + 16
		var pill_h = BADGE_H - 4
		var px = (size.x - pill_w) * 0.5
		var py := 1.0 if _is_top else 3.0
		# 药丸背景
		draw_rect(Rect2(px, py, pill_w, pill_h), Color(_t.bg_main, _alpha * 0.8))
		# 边框
		draw_rect(Rect2(px, py, pill_w, pill_h), Color(_t.accent, _alpha * 0.6), false, 1.0)
		# 文字
		var tx = px + 8
		var ty = py + pill_h * 0.5 + ts.y * 0.3
		draw_string(font, Vector2(tx, ty), text, 0, -1, fs, Color(_t.accent, _alpha))

func _update_fades() -> void:
	var vbar = scroll.get_v_scroll_bar()
	if not vbar or vbar.max_value <= vbar.page:
		_fade_top.update_state(0.0, 0)
		_fade_btm.update_state(0.0, 0)
		return
	var range_val = vbar.max_value - vbar.page
	if range_val <= 0:
		_fade_top.update_state(0.0, 0)
		_fade_btm.update_state(0.0, 0)
		return
	var todos = SettingsManager.get_todos()
	var total = todos.size()
	var first_visible = maxi(0, int(vbar.value / _row_h))
	var vp_h = scroll.size.y
	if vp_h <= 0: vp_h = 400
	var last_visible = mini(total - 1, int((vbar.value + vp_h) / _row_h))
	var hidden_above = first_visible
	var hidden_below = maxi(0, total - 1 - last_visible)
	var top_ratio = clampf(vbar.value / minf(range_val, 80.0), 0.0, 1.0)
	var btm_ratio = clampf((range_val - vbar.value) / minf(range_val, 80.0), 0.0, 1.0)
	_fade_top.update_state(top_ratio, hidden_above)
	_fade_btm.update_state(btm_ratio, hidden_below)

func _calc_row_h() -> float:
	return theme.checkbox_size_px.y + theme.card_padding[2] + theme.card_padding[3] + theme.list_spacing + 6

func _ensure_pool(needed: int) -> void:
	while _pool.size() < needed:
		var card = PanelContainer.new()
		card.clip_contents = false
		var slot := {
			"card": card,
			"bound_idx": -1,
			"bound_hash": -1,
			"style_normal": null,
		}
		card.gui_input.connect(_on_pool_card_input.bind(slot))
		card.mouse_entered.connect(_on_pool_hover.bind(slot, true))
		card.mouse_exited.connect(_on_pool_hover.bind(slot, false))
		_spacer.add_child(card)
		_pool.append(slot)

func _on_pool_card_input(ev: InputEvent, sl: Dictionary) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if sl.bound_idx >= 0:
			_selected_idx = sl.bound_idx
			_refresh_list()
			_refresh_right_panel()

func _on_pool_hover(sl: Dictionary, entering: bool) -> void:
	if sl.bound_idx < 0 or sl.bound_idx == _selected_idx: return
	if entering and sl.style_normal:
		sl.card.add_theme_stylebox_override("panel", theme.make_card_hover_style(sl.style_normal))
	elif sl.style_normal:
		sl.card.add_theme_stylebox_override("panel", sl.style_normal)

func _on_pool_check(sl: Dictionary) -> void:
	if sl.bound_idx >= 0: _toggle_todo(sl.bound_idx)

func _on_pool_del(sl: Dictionary) -> void:
	if sl.bound_idx >= 0: _delete_todo_animated(sl.bound_idx, sl.card)

func _bind_slot(slot_i: int, todo_idx: int, todos: Array, width: float) -> void:
	var sl = _pool[slot_i]
	var t = todos[todo_idx]
	var is_done: bool = t.get("done", false)
	var is_sel: bool = (todo_idx == _selected_idx)
	var has_note: bool = not t.get("notes", "").is_empty()
	var text: String = t.get("text", "(\u672a\u547d\u540d)")

	# 快速状态指纹 — 任何视觉要素变了才重绘
	var h := todo_idx
	h = h * 31 + (1 if is_done else 0)
	h = h * 31 + (1 if is_sel else 0)
	h = h * 31 + (1 if has_note else 0)
	h = h * 31 + text.hash()

	var card_h = _row_h - theme.list_spacing
	sl.card.position = Vector2(0, todo_idx * _row_h)
	sl.card.size = Vector2(width, card_h)
	sl.card.visible = true
	sl.bound_idx = todo_idx

	if sl.bound_hash == h:
		return

	# 清空旧内容
	while sl.card.get_child_count() > 0:
		var child = sl.card.get_child(0)
		sl.card.remove_child(child)
		child.queue_free()

	var card_style = theme.make_card_style(is_done, is_sel)
	sl.card.add_theme_stylebox_override("panel", card_style)
	sl.style_normal = card_style

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	sl.card.add_child(row)

	var check = theme.make_checkbox(is_done)
	check.pressed.connect(_on_pool_check.bind(sl))
	row.add_child(check)

	var title_lbl = Label.new()
	title_lbl.text = text
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme.apply_card_title_style(title_lbl, is_done, is_sel)
	row.add_child(title_lbl)

	if has_note:
		var ni = Label.new()
		ni.text = ":"
		ni.mouse_filter = Control.MOUSE_FILTER_IGNORE
		theme.apply_note_indicator_style(ni)
		row.add_child(ni)

	var del_btn = theme.make_delete_button("\u5220\u9664")
	del_btn.pressed.connect(_on_pool_del.bind(sl))
	row.add_child(del_btn)

	sl.bound_hash = h

func _refresh_list() -> void:
	var todos = SettingsManager.get_todos()

	if todos.is_empty():
		_spacer.custom_minimum_size = Vector2(0, 100)
		for sl in _pool: sl.card.visible = false
		scroll.visible = false
		_empty_hint.visible = true
		_update_progress(todos)
		(func(): _update_fades()).call_deferred()
		return

	scroll.visible = true
	_empty_hint.visible = false
	_spacer.custom_minimum_size.y = todos.size() * _row_h

	var spacer_w = _spacer.size.x
	if spacer_w <= 0: spacer_w = scroll.size.x
	if spacer_w <= 0: spacer_w = 400

	var scroll_y = scroll.get_v_scroll_bar().value
	var vp_h = scroll.size.y
	if vp_h <= 0: vp_h = 400

	var first = maxi(0, int(scroll_y / _row_h) - _POOL_BUFFER)
	var last = mini(todos.size() - 1, int((scroll_y + vp_h) / _row_h) + _POOL_BUFFER)

	var needed = last - first + 1
	_ensure_pool(needed)

	var slot_i = 0
	for idx in range(first, last + 1):
		_bind_slot(slot_i, idx, todos, spacer_w)
		slot_i += 1

	for i in range(slot_i, _pool.size()):
		_pool[i].card.visible = false

	_update_progress(todos)
	(func(): _update_fades()).call_deferred()

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

	if total > 0 and done >= total:
		_title_label.text = "全部完成了"
	else:
		_title_label.text = "待办清单"

	theme.update_progress_indicator(_progress_indicator, done, total)

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
	# 滚动到底部显示新项
	(func(): scroll.get_v_scroll_bar().value = scroll.get_v_scroll_bar().max_value).call_deferred()
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
	if theme.has_method("play_delete_animation"):
		var handled = theme.play_delete_animation(card, func(): _delete_todo(idx))
		if handled: return
	_delete_todo(idx)

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
	# 延迟一帧等布局算完真实尺寸后再刷新卡片宽度
	(func(): _refresh_list(); _update_fades()).call_deferred()

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

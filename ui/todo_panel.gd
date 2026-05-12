# todo_panel.gd — 待办清单面板 (主从双栏 · 灰白复古风)
# 左栏: 待办列表 | 右栏: 选中项目的备注
# 屏幕 70%，像素风九宫格边框
extends CanvasLayer

var panel: PanelContainer
var list_box: VBoxContainer
var scroll: ScrollContainer
var note_edit: TextEdit
var note_title: LineEdit
var note_empty: VBoxContainer
var save_badge: PanelContainer     # 保存成功徽章
var save_badge_label: Label
var scroll_hint_top: Panel         # 滚动提示 (上)
var scroll_hint_btm: Panel         # 滚动提示 (下)

var _selected_idx: int = -1
var _guard_frames := 0
var _save_timer: Timer
var _save_fade_tween: Tween

# ── 引用 ──
var _title_label: Label
var _progress_label: Label
var _progress_blocks: Array[Panel] = []

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

# ═══ 配色 (灰白复古) ═══
const BG_MAIN    := Color(0.78, 0.80, 0.84, 0.97)
const BG_TITLE   := Color(0.65, 0.68, 0.73, 0.85)
const BG_CARD    := Color(0.85, 0.87, 0.90, 0.65)
const BG_CARD_S  := Color(0.88, 0.90, 0.94, 0.85)
const BG_CARD_D  := Color(0.80, 0.82, 0.85, 0.40)
const BG_INPUT   := Color(0.92, 0.93, 0.95, 0.9)
const TX_PRIMARY := Color(0.10, 0.12, 0.18, 1.0)
const TX_SECOND  := Color(0.35, 0.38, 0.45, 0.8)
const TX_DIM     := Color(0.50, 0.52, 0.58, 0.55)
const TX_DONE    := Color(0.45, 0.48, 0.52, 0.5)
const BD_LIGHT   := Color(0.60, 0.63, 0.68, 0.3)
const BD_SELECT  := Color(0.30, 0.65, 0.45, 0.6)
const GREEN_DONE := Color(0.25, 0.72, 0.40, 1.0)
const GREEN_SOFT := Color(0.30, 0.65, 0.42, 0.7)
const RED_DEL_H  := Color(0.85, 0.25, 0.20, 1.0)

func _ready() -> void:
	_calc_panel_size()
	_build_ui()
	EventBus.show_todo_panel.connect(_toggle_panel)
	EventBus.ui_theme_changed.connect(_apply_ui_theme)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.6
	_save_timer.timeout.connect(_do_save_note)
	add_child(_save_timer)



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
#  UI 构建
# ═══════════════════════════════════════════════

func _build_ui() -> void:
	layer = 101

	panel = _PixelPanel.new()
	panel.visible = false
	panel.custom_minimum_size = Vector2(_panel_w, _panel_h)
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 26)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(margin)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(outer)

	# ── 标题栏 ──
	_title_bar = _build_title_bar()
	outer.add_child(_title_bar)
	outer.add_child(_make_sep())

	# ═══ 双栏 ═══
	var split = HBoxContainer.new()
	split.add_theme_constant_override("separation", 0)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(split)

	# ── 左栏 ──
	var left_col = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 1.0
	split.add_child(left_col)

	# 新建按钮
	_new_btn = _make_pill_btn("+ 新建待办", Color(0.35, 0.55, 0.45, 0.85), Color(0.30, 0.62, 0.45, 1.0))
	_new_btn.pressed.connect(_on_add_pressed)
	left_col.add_child(_new_btn)

	# 滚动区域 (隐藏原生滚动条，用提示条指示)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)

	# 滚动提示 (覆盖在 scroll 上方)
	scroll_hint_top = _make_scroll_hint(true)
	scroll_hint_btm = _make_scroll_hint(false)
	# 通过 scroll 信号更新
	scroll.get_v_scroll_bar().value_changed.connect(func(_v): _update_scroll_hints())

	# 底部呼吸间距
	var bottom_pad = Control.new()
	bottom_pad.custom_minimum_size.y = 6
	left_col.add_child(bottom_pad)

	# ── 竖分割线 ──
	var vsep = VSeparator.new()
	vsep.add_theme_constant_override("separation", 18)
	_vsep_style = StyleBoxFlat.new()
	_vsep_style.bg_color = Color(0.55, 0.58, 0.65, 0.18)
	_vsep_style.set_content_margin_all(0)
	vsep.add_theme_stylebox_override("separator", _vsep_style)
	split.add_child(vsep)

	# ── 右栏 ──
	var right_col = VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 10)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.3
	split.add_child(right_col)

	# 标题行
	var title_row = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right_col.add_child(title_row)

	note_title = LineEdit.new()
	note_title.placeholder_text = "待办名称"
	note_title.add_theme_font_size_override("font_size", 20)
	note_title.add_theme_color_override("font_color", TX_PRIMARY)
	note_title.add_theme_color_override("font_placeholder_color", TX_DIM)
	note_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nt_style = StyleBoxFlat.new()
	nt_style.bg_color = Color.TRANSPARENT
	nt_style.set_border_width_all(0)
	nt_style.content_margin_left = 2
	nt_style.content_margin_bottom = 4
	note_title.add_theme_stylebox_override("normal", nt_style)
	var nt_focus = nt_style.duplicate()
	nt_focus.border_width_bottom = 2
	nt_focus.border_color = GREEN_SOFT
	note_title.add_theme_stylebox_override("focus", nt_focus)
	note_title.text_submitted.connect(_on_title_edited)
	note_title.focus_exited.connect(_on_title_focus_lost)
	title_row.add_child(note_title)

	# 保存徽章 (绿底白字小胶囊)
	save_badge = PanelContainer.new()
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = GREEN_DONE
	badge_style.set_corner_radius_all(8)
	badge_style.content_margin_left = 8
	badge_style.content_margin_right = 8
	badge_style.content_margin_top = 2
	badge_style.content_margin_bottom = 2
	save_badge.add_theme_stylebox_override("panel", badge_style)
	save_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_badge.modulate.a = 0.0
	save_badge_label = Label.new()
	save_badge_label.text = "已保存"
	save_badge_label.add_theme_font_size_override("font_size", 11)
	save_badge_label.add_theme_color_override("font_color", Color.WHITE)
	save_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_badge.add_child(save_badge_label)
	title_row.add_child(save_badge)

	_note_title_sep = _make_sep()
	right_col.add_child(_note_title_sep)

	# 备注编辑器
	note_edit = TextEdit.new()
	note_edit.placeholder_text = "在此编辑备注内容..."
	note_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	note_edit.add_theme_font_size_override("font_size", 16)
	note_edit.add_theme_color_override("font_color", Color(0.15, 0.18, 0.22, 0.95))
	note_edit.add_theme_color_override("font_placeholder_color", TX_DIM)
	note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var ne_style = StyleBoxFlat.new()
	ne_style.bg_color = BG_INPUT
	ne_style.border_color = BD_LIGHT
	ne_style.set_border_width_all(1)
	ne_style.set_corner_radius_all(4)
	ne_style.content_margin_left = 14
	ne_style.content_margin_right = 14
	ne_style.content_margin_top = 12
	ne_style.content_margin_bottom = 12
	note_edit.add_theme_stylebox_override("normal", ne_style)
	var ne_focus = ne_style.duplicate()
	ne_focus.border_color = GREEN_SOFT
	note_edit.add_theme_stylebox_override("focus", ne_focus)
	note_edit.text_changed.connect(_on_note_text_changed)
	note_edit.visible = false
	right_col.add_child(note_edit)

	# 空状态
	note_empty = VBoxContainer.new()
	note_empty.add_theme_constant_override("separation", 12)
	note_empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	note_empty.alignment = BoxContainer.ALIGNMENT_CENTER

	var ei = Label.new()
	ei.text = ":"
	ei.add_theme_font_size_override("font_size", 36)
	ei.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62, 0.25))
	ei.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ei.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_empty.add_child(ei)

	var eh = Label.new()
	eh.text = "点击左侧待办查看详情"
	eh.add_theme_font_size_override("font_size", 14)
	eh.add_theme_color_override("font_color", TX_DIM)
	eh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eh.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_title_label.add_theme_color_override("font_color", TX_PRIMARY)
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_title_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	_progress_label = Label.new()
	_progress_label.text = "0/0"
	_progress_label.add_theme_font_size_override("font_size", 14)
	_progress_label.add_theme_color_override("font_color", TX_SECOND)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_progress_label)

	var blocks_box = HBoxContainer.new()
	blocks_box.add_theme_constant_override("separation", 3)
	blocks_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(blocks_box)
	for i in range(10):
		var block = Panel.new()
		block.custom_minimum_size = Vector2(8, 8)
		var bs = StyleBoxFlat.new()
		bs.bg_color = Color(0.65, 0.68, 0.72, 0.35)
		bs.border_color = Color(0.25, 0.28, 0.32, 0.5)
		bs.set_border_width_all(1)
		bs.set_corner_radius_all(0)
		block.add_theme_stylebox_override("panel", bs)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.visible = false
		blocks_box.add_child(block)
		_progress_blocks.append(block)

	# 关闭按钮 (胶囊风格)
	var close_btn = _make_pill_btn("关闭", Color(0.55, 0.48, 0.48, 0.55), Color(0.72, 0.30, 0.28, 0.85), 13)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	close_btn.custom_minimum_size.y = 28
	close_btn.pressed.connect(_close_panel)
	bar.add_child(close_btn)

	return bar

# ═══════════════════════════════════════════════
#  像素边框
# ═══════════════════════════════════════════════

class _PixelPanel extends PanelContainer:
	var _hue: float = EventBus.ui_hue

	func _ready() -> void:
		var empty = StyleBoxFlat.new()
		empty.bg_color = Color.TRANSPARENT
		add_theme_stylebox_override("panel", empty)

	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		var bw := 2.0
		var cs := 6.0

		draw_rect(r, Color(0.78, 0.80, 0.84, 0.97))

		var bc = Color(0.35, 0.38, 0.45, 0.5)
		draw_rect(Rect2(cs, 0, r.size.x - cs * 2, bw), bc)
		draw_rect(Rect2(cs, r.size.y - bw, r.size.x - cs * 2, bw), bc)
		draw_rect(Rect2(0, cs, bw, r.size.y - cs * 2), bc)
		draw_rect(Rect2(r.size.x - bw, cs, bw, r.size.y - cs * 2), bc)

		var cc = Color(0.25, 0.28, 0.35, 0.65)
		for c in [
			[Vector2(0, 0), Vector2(cs, bw)], [Vector2(0, 0), Vector2(bw, cs)],
			[Vector2(r.size.x - cs, 0), Vector2(cs, bw)], [Vector2(r.size.x - bw, 0), Vector2(bw, cs)],
			[Vector2(0, r.size.y - bw), Vector2(cs, bw)], [Vector2(0, r.size.y - cs), Vector2(bw, cs)],
			[Vector2(r.size.x - cs, r.size.y - bw), Vector2(cs, bw)], [Vector2(r.size.x - bw, r.size.y - cs), Vector2(bw, cs)],
		]:
			draw_rect(Rect2(c[0], c[1]), cc)

		var th := 56.0
		draw_rect(Rect2(bw, bw, r.size.x - bw * 2, th), Color(0.65, 0.68, 0.73, 0.85))
		draw_rect(Rect2(bw, bw + th, r.size.x - bw * 2, 1), Color(0.55, 0.58, 0.62, 0.2))

	func update_hue(_hue_val: float) -> void:
		queue_redraw()

# ═══════════════════════════════════════════════
#  滚动提示条
# ═══════════════════════════════════════════════

func _make_scroll_hint(is_top: bool) -> Panel:
	var hint = Panel.new()
	hint.custom_minimum_size = Vector2(0, 3)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.45, 0.48, 0.55, 0.25)
	s.set_corner_radius_all(1)
	hint.add_theme_stylebox_override("panel", s)
	hint.visible = false
	# 放在 left_col 的 scroll 上下
	# 延迟添加到 left_col (scroll 的父节点)
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
		lbl.text = "还没有待办哦\n点击上方按钮创建一个吧"
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", TX_DIM)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		var card_style = _make_card_style(is_done, is_selected)
		card.add_theme_stylebox_override("panel", card_style)

		var cs_ref = card_style
		var sel_ref = is_selected
		var idx_sel = i
		card.mouse_entered.connect(func():
			if not sel_ref:
				var hs = cs_ref.duplicate()
				hs.bg_color.a = minf(hs.bg_color.a + 0.15, 1.0)
				hs.border_color = Color(0.40, 0.55, 0.50, 0.35)
				card.add_theme_stylebox_override("panel", hs)
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

		# checkbox
		var check_btn = _make_checkbox(is_done)
		var idx_c = i
		check_btn.pressed.connect(func(): _toggle_todo(idx_c))
		row.add_child(check_btn)

		# 标题
		var title_lbl = Label.new()
		title_lbl.text = t.get("text", "(未命名)")
		title_lbl.add_theme_font_size_override("font_size", 17)
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_done:
			title_lbl.add_theme_color_override("font_color", TX_DONE)
		elif is_selected:
			title_lbl.add_theme_color_override("font_color", TX_PRIMARY)
		else:
			title_lbl.add_theme_color_override("font_color", Color(0.18, 0.20, 0.28, 0.9))
		row.add_child(title_lbl)

		# 备注指示
		if has_note:
			var ni = Label.new()
			ni.text = ":"
			ni.add_theme_font_size_override("font_size", 12)
			ni.add_theme_color_override("font_color", GREEN_SOFT)
			ni.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(ni)

		# 删除按钮 (文字型)
		var del_btn = _make_text_btn("删除", Color(0.55, 0.42, 0.42, 0.35), RED_DEL_H)
		var idx_d = i
		var card_ref = card
		del_btn.pressed.connect(func(): _delete_todo_animated(idx_d, card_ref))
		row.add_child(del_btn)

		list_box.add_child(card)

	_update_progress(todos)
	_update_scroll_hints_deferred()

func _update_scroll_hints_deferred() -> void:
	# 延迟一帧让 scroll 计算完布局
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
			t = "(未命名)"
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
			var bs = _progress_blocks[i].get_theme_stylebox("panel") as StyleBoxFlat
			if bs:
				bs.bg_color = GREEN_DONE if i < done else Color(0.65, 0.68, 0.72, 0.35)
		else:
			_progress_blocks[i].visible = false

	if total > 0 and done >= total:
		_progress_label.add_theme_color_override("font_color", GREEN_DONE)
		_title_label.text = "全部完成了"
	else:
		_progress_label.add_theme_color_override("font_color", TX_SECOND)
		_title_label.text = "待办清单"

	EventBus.todo_count_changed.emit(total - done, total)

# ═══════════════════════════════════════════════
#  操作
# ═══════════════════════════════════════════════

func _on_add_pressed() -> void:
	var todos = SettingsManager.get_todos()
	todos.append({
		"id": _gen_id(),
		"text": "(未命名)",
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
#  UI 工具
# ═══════════════════════════════════════════════

## 胶囊按钮 (绿底/灰底，有边框层级感)
func _make_pill_btn(text: String, bg: Color, hover_bg: Color, font_size: int = 15) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Color(bg.r + 0.08, bg.g + 0.08, bg.b + 0.08, 0.4)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = hover_bg
	h.border_color = Color(hover_bg.r + 0.1, hover_bg.g + 0.1, hover_bg.b + 0.1, 0.6)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

## 文字按钮 (无背景，hover 变色)
func _make_text_btn(text: String, normal_color: Color, hover_color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", normal_color)
	btn.add_theme_color_override("font_hover_color", hover_color)
	btn.flat = false
	btn.custom_minimum_size = Vector2(0, 24)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.75, 0.72, 0.72, 0.2)
	s.border_color = Color(0.58, 0.48, 0.48, 0.25)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(0.85, 0.30, 0.25, 0.15)
	h.border_color = Color(0.75, 0.35, 0.30, 0.4)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func _make_sep() -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.55, 0.58, 0.65, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

func _make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	if is_selected:
		s.bg_color = BG_CARD_S
		s.border_color = BD_SELECT
		s.set_border_width_all(1)
		s.border_width_left = 3
	elif is_done:
		s.bg_color = BG_CARD_D
		s.border_color = Color(0.65, 0.68, 0.72, 0.15)
		s.set_border_width_all(1)
	else:
		s.bg_color = BG_CARD
		s.border_color = BD_LIGHT
		s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 12
	s.content_margin_right = 10
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

func _make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(26, 26)
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(3)
	s.set_border_width_all(2)
	if is_done:
		btn.text = "✓"
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color.WHITE)
		s.bg_color = GREEN_DONE
		s.border_color = Color(0.20, 0.60, 0.35, 0.7)
	else:
		btn.text = ""
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", TX_DIM)
		s.bg_color = Color(0.88, 0.90, 0.92, 0.7)
		s.border_color = Color(0.55, 0.58, 0.65, 0.35)
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	if is_done:
		h.bg_color = Color(0.20, 0.65, 0.35, 1.0)
	else:
		h.bg_color = Color(0.82, 0.85, 0.88, 0.9)
		h.border_color = GREEN_SOFT
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

# ═══════════════════════════════════════════════
#  主题色
# ═══════════════════════════════════════════════

func _apply_ui_theme(_hue: float) -> void:
	if panel is _PixelPanel:
		(panel as _PixelPanel).update_hue(_hue)
	if panel.visible:
		_refresh_list()

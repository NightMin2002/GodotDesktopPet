# file_search_panel.gd — 文件检索终端面板
# 职责: 面板骨架、输入框、结果列表、状态栏、DWM 穿透、宠物优先拦截
# 依赖: interop/FileSearchEngine.cs (C# 独立搜索引擎)
extends CanvasLayer

# ── 面板尺寸 ──
var _panel_w: float = 680
var _panel_h: float = 520

# ── 引用 ──
var panel: PanelContainer
var _is_open: bool = false
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

# ── C# 桥接 ──
var _search_engine: Node = null
var _engine_available: bool = false
var _engine_version: String = ""
var _engine_error: String = ""

# ── 搜索状态 ──
var _query: String = ""
var _results: Array = []
var _total_results: int = 0
var _is_searching: bool = false
var _debounce_timer: float = 0.0
var _pending_query: String = ""

# ── UI 组件 ──
var _input_field: LineEdit
var _result_container: VBoxContainer
var _scroll: ScrollContainer
var _status_label: Label
var _count_label: Label
var _clear_btn: Button
var _frame_drawer: Control
var _time_passed: float = 0.0
var _detail_view: bool = false  # false=正常视图, true=详细视图(单行)

# ── 结果卡片引用 ──
var _result_cards: Array[Control] = []
const MAX_VISIBLE_RESULTS := 200

# ── 引导卡片 ──
var _guide_card: Control = null
const EVERYTHING_URL := "https://www.voidtools.com/zh-cn/"

# ── 面板层级 ──
const _PANEL_ID := "file_search"

# ── 话术 ──
const LINES := {
	"open": "检索终端启动。",
	"searching": "文件索引扫描中...",
	"found": "命中 %d 个目标。",
	"not_found": "未检测到匹配项。",
	"offline": "检索引擎未就绪。",
	"not_found_everything": "未检测到 Everything。安装后可获得极速检索。",
	"not_running": "Everything 未运行。启动后自动接入。",
	"close": "检索终端关闭。",
	"locate": "目标已标记。",
	"copy_path": "路径数据已写入剪贴板。",
}

func _ready() -> void:
	_calc_panel_size()
	_find_search_engine()
	_build_ui()
	EventBus.show_file_search.connect(_on_toggle)
	EventBus.panel_focus_requested.connect(_on_panel_focus)

func _calc_panel_size() -> void:
	var vp = get_viewport().get_visible_rect().size
	_panel_w = vp.x * 0.70
	_panel_h = vp.y * 0.70

func _clamp_pos(pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - _panel_w - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - _panel_h - 4.0))
	return pos

# ═══════════════════════════════════════════════
#  主循环
# ═══════════════════════════════════════════════

func _process(delta: float) -> void:
	if not _is_open:
		return
	_time_passed += delta
	if is_instance_valid(_frame_drawer):
		_frame_drawer.queue_redraw()
	# DWM 穿透: 精确区域
	var pet = _get_pet()
	if pet:
		pet.set_overlay_rect("file_search", Rect2(panel.position, Vector2(_panel_w, _panel_h)))
	EventBus._active_panel_rects[_PANEL_ID] = { "rect": Rect2(panel.position, Vector2(_panel_w, _panel_h)), "layer": layer }
	# 搜索防抖
	if _debounce_timer > 0.0:
		_debounce_timer -= delta
		if _debounce_timer <= 0.0:
			_execute_search(_pending_query)
	# 轮询搜索结果 (C# 后台线程边搜边返回)
	if _is_searching and _search_engine != null:
		_poll_search_results()

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	# 宠物优先输入拦截
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var mouse_pos: Vector2 = event.position
		if Rect2(panel.position, Vector2(_panel_w, _panel_h)).has_point(mouse_pos):
			var pet_hit = _find_pet_at_mouse()
			if pet_hit:
				pet_hit._unhandled_input(event)
				get_viewport().set_input_as_handled()
				return
	# 点击置顶
	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = event.position
		if Rect2(panel.position, Vector2(_panel_w, _panel_h)).has_point(pos):
			if layer < -1:
				for pid in EventBus._active_panel_rects:
					if pid != _PANEL_ID:
						var info = EventBus._active_panel_rects[pid]
						if info.layer > layer and info.rect.has_point(pos):
							return
			_bring_to_front()
	# ESC 关闭
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _is_open:
			_close_panel()
			get_viewport().set_input_as_handled()

# ═══════════════════════════════════════════════
#  UI 构建
# ═══════════════════════════════════════════════

func _build_ui() -> void:
	layer = -1

	panel = PanelContainer.new()
	panel.visible = false
	panel.custom_minimum_size = Vector2(_panel_w, _panel_h)
	var ps = StyleBoxEmpty.new()
	panel.add_theme_stylebox_override("panel", ps)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)

	# 边框绘制器
	_frame_drawer = Control.new()
	_frame_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_drawer.draw.connect(_on_frame_draw)
	panel.add_child(_frame_drawer)

	# 内边距
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(margin)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(outer)

	# ── 标题栏 ──
	outer.add_child(_build_title_bar())

	# ── 搜索栏 ──
	outer.add_child(_build_search_bar())

	# ── 结果统计 + 视图切换 ──
	var count_row = HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 8)
	count_row.mouse_filter = Control.MOUSE_FILTER_PASS

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", Color(0.50, 0.58, 0.65, 0.6))
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_row.add_child(_count_label)

	# 视图切换按钮
	var view_btn = Button.new()
	view_btn.text = "详细"
	view_btn.add_theme_font_size_override("font_size", 12)
	view_btn.add_theme_color_override("font_color", Color(0.55, 0.62, 0.70, 0.7))
	view_btn.add_theme_color_override("font_hover_color", Color(0.80, 0.88, 0.95, 1.0))
	var vb_s = StyleBoxFlat.new()
	vb_s.bg_color = Color(0.08, 0.10, 0.16, 0.5)
	vb_s.set_corner_radius_all(3)
	vb_s.set_border_width_all(1)
	vb_s.border_color = Color(0.35, 0.40, 0.50, 0.3)
	vb_s.content_margin_left = 8; vb_s.content_margin_right = 8
	vb_s.content_margin_top = 2; vb_s.content_margin_bottom = 2
	view_btn.add_theme_stylebox_override("normal", vb_s)
	var vb_h = vb_s.duplicate()
	vb_h.bg_color = Color(0.12, 0.14, 0.22, 0.7)
	vb_h.border_color = Color(0.45, 0.50, 0.60, 0.5)
	view_btn.add_theme_stylebox_override("hover", vb_h)
	view_btn.add_theme_stylebox_override("pressed", vb_h)
	view_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	view_btn.pressed.connect(func():
		_detail_view = not _detail_view
		view_btn.text = "正常" if _detail_view else "详细"
		_rebuild_result_cards()
	)
	count_row.add_child(view_btn)

	outer.add_child(count_row)

	# ── 结果列表区域 ──
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	# 自定义滚动条 (复用装置终端样式)
	ProfileStyles.setup_custom_scrollbar(_scroll)
	outer.add_child(_scroll)

	_result_container = VBoxContainer.new()
	_result_container.add_theme_constant_override("separation", 4)
	_result_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_result_container)

	# ── 底部状态栏 ──
	outer.add_child(_build_status_bar())

func _build_title_bar() -> Control:
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.gui_input.connect(_on_title_bar_input)

	var title = Label.new()
	title.text = "文件检索终端"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.70, 0.80, 0.92, 0.9))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4, 0.7))
	close_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.4, 0.35, 1.0))
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.08, 0.08, 0.5)
	cs.set_corner_radius_all(4)
	cs.set_border_width_all(1)
	cs.border_color = Color(0.5, 0.2, 0.2, 0.3)
	cs.content_margin_left = 10; cs.content_margin_right = 10
	cs.content_margin_top = 3; cs.content_margin_bottom = 3
	close_btn.add_theme_stylebox_override("normal", cs)
	var ch = cs.duplicate()
	ch.bg_color = Color(0.25, 0.1, 0.1, 0.7)
	ch.border_color = Color(0.8, 0.3, 0.3, 0.5)
	close_btn.add_theme_stylebox_override("hover", ch)
	close_btn.add_theme_stylebox_override("pressed", ch)
	close_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	close_btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			_close_panel()
	)
	bar.add_child(close_btn)

	return bar

func _build_search_bar() -> Control:
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)

	# 输入框
	_input_field = LineEdit.new()
	_input_field.placeholder_text = "输入检索指令..."
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.add_theme_font_size_override("font_size", 16)
	_input_field.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.95))
	_input_field.add_theme_color_override("font_placeholder_color", Color(0.45, 0.52, 0.60, 0.5))
	_input_field.add_theme_color_override("caret_color", Color.from_hsv(EventBus.ui_hue, 0.5, 1.0))
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.06, 0.08, 0.14, 0.7)
	input_style.set_corner_radius_all(4)
	input_style.set_border_width_all(1)
	input_style.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.4)
	input_style.content_margin_left = 12; input_style.content_margin_right = 12
	input_style.content_margin_top = 8; input_style.content_margin_bottom = 8
	_input_field.add_theme_stylebox_override("normal", input_style)
	var input_focus = input_style.duplicate()
	input_focus.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.7)
	_input_field.add_theme_stylebox_override("focus", input_focus)
	_input_field.text_changed.connect(_on_text_changed)
	_input_field.text_submitted.connect(func(_t): _execute_search(_input_field.text))
	bar.add_child(_input_field)

	# 清空按钮
	_clear_btn = Button.new()
	_clear_btn.text = "X"
	_clear_btn.visible = false
	_clear_btn.add_theme_font_size_override("font_size", 14)
	var clear_s = StyleBoxFlat.new()
	clear_s.bg_color = Color(0.12, 0.10, 0.10, 0.5)
	clear_s.set_corner_radius_all(4)
	clear_s.content_margin_left = 6; clear_s.content_margin_right = 6
	clear_s.content_margin_top = 4; clear_s.content_margin_bottom = 4
	_clear_btn.add_theme_stylebox_override("normal", clear_s)
	_clear_btn.add_theme_stylebox_override("hover", clear_s)
	_clear_btn.add_theme_color_override("font_color", Color(0.6, 0.5, 0.5, 0.7))
	_clear_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.4, 0.35, 1.0))
	_clear_btn.pressed.connect(func():
		_input_field.text = ""
		_clear_results()
		_input_field.grab_focus()
	)
	bar.add_child(_clear_btn)

	return bar

func _build_status_bar() -> Control:
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	# 分隔线
	var sep = HSeparator.new()
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sep_s = StyleBoxFlat.new()
	sep_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.2, 0.4, 0.2)
	sep_s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", sep_s)
	sep.add_theme_constant_override("separation", 1)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.45, 0.52, 0.60, 0.55))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_status_label()
	bar.add_child(_status_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(sep)
	vbox.add_child(bar)
	return vbox

# ═══════════════════════════════════════════════
#  标题栏拖拽
# ═══════════════════════════════════════════════

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			_dragging = true
			_drag_offset = panel.get_global_mouse_position() - panel.position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_dragging = false
			return
		panel.position = _clamp_pos(panel.get_global_mouse_position() - _drag_offset)

# ═══════════════════════════════════════════════
#  面板开关
# ═══════════════════════════════════════════════

func _on_toggle() -> void:
	if _is_open:
		_close_panel()
	else:
		_open_panel()

func _open_panel() -> void:
	_is_open = true
	_find_search_engine()
	_check_engine_status()
	EventBus.panel_focus_requested.emit(_PANEL_ID)
	var vp = get_viewport().get_visible_rect().size
	panel.position = _clamp_pos(Vector2(
		(vp.x - _panel_w) * 0.5,
		(vp.y - _panel_h) * 0.5
	))
	panel.pivot_offset = Vector2(_panel_w * 0.5, _panel_h * 0.5)
	panel.scale = Vector2(0.85, 0.85)
	panel.modulate.a = 0.0
	panel.show()
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 聚焦输入框
	tween.finished.connect(func():
		if is_instance_valid(_input_field):
			_input_field.grab_focus()
	)
	# 话术 + 引导
	var pet = _get_pet()
	if pet:
		if not _engine_available:
			if _engine_error == "not_found" or _engine_error == "dll_not_found":
				pet.show_local_bubble(LINES.not_found_everything)
			elif _engine_error == "not_running":
				pet.show_local_bubble(LINES.not_running)
			else:
				pet.show_local_bubble(LINES.offline)
		else:
			pet.show_local_bubble(LINES.open)
	# 引导卡片
	if not _engine_available:
		_show_guide_card()
	else:
		_hide_guide_card()

func _close_panel() -> void:
	_is_open = false
	_dragging = false
	_hide_guide_card()
	# 取消正在进行的搜索
	if _is_searching and _search_engine != null:
		_search_engine.call("CancelSearch")
		_is_searching = false
	EventBus._active_panel_rects.erase(_PANEL_ID)
	var pet = _get_pet()
	if pet:
		pet.remove_overlay_rect("file_search")
	panel.pivot_offset = panel.size / 2.0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.1)
	tween.tween_property(panel, "scale", Vector2(0.85, 0.85), 0.1)
	tween.finished.connect(func():
		panel.hide()
	)

# ═══════════════════════════════════════════════
#  面板层级
# ═══════════════════════════════════════════════

func _bring_to_front() -> void:
	if layer != -1:
		EventBus.panel_focus_requested.emit(_PANEL_ID)

func _on_panel_focus(panel_id: String) -> void:
	if not _is_open:
		return
	if panel_id == _PANEL_ID:
		layer = -1
	else:
		layer = -2

# ═══════════════════════════════════════════════
#  C# 桥接
# ═══════════════════════════════════════════════

func _find_search_engine() -> void:
	if _search_engine != null and is_instance_valid(_search_engine):
		return
	var tree = get_tree()
	if tree == null:
		return
	var main_node = tree.root.get_node_or_null("Main")
	if main_node:
		for child in main_node.get_children():
			if child.has_method("StartSearch") and child.has_method("PollResults"):
				_search_engine = child
				return

func _check_engine_status() -> void:
	if _search_engine == null:
		_engine_available = false
		_engine_error = "not_found"
		_engine_version = ""
		_update_status_label()
		return
	var status: Dictionary = _search_engine.call("GetStatus")
	_engine_available = status.get("available", false)
	_engine_error = status.get("error", "")
	_engine_version = status.get("version", "")
	_update_status_label()

func _update_status_label() -> void:
	if not is_instance_valid(_status_label):
		return
	if _is_searching:
		var found = _search_engine.call("GetTotalFound") if _search_engine else 0
		_status_label.text = "扫描中... 已命中 %d 个目标" % found
		_status_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.8, 0.7))
	elif _engine_available:
		_status_label.text = "检索引擎: Everything v%s [在线]" % _engine_version
		_status_label.add_theme_color_override("font_color", Color(0.35, 0.65, 0.50, 0.6))
	elif _engine_error == "downloading":
		_status_label.text = "检索引擎: 正在下载 SDK..."
		_status_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.7, 0.6))
	elif _engine_error == "not_running":
		_status_label.text = "检索引擎: Everything 未运行 [离线]"
		_status_label.add_theme_color_override("font_color", Color(0.65, 0.55, 0.35, 0.6))
	elif _engine_error == "dll_not_found" or _engine_error == "not_found":
		_status_label.text = "检索引擎: SDK 加载中... [离线]"
		_status_label.add_theme_color_override("font_color", Color(0.65, 0.55, 0.35, 0.6))
	elif _engine_error == "download_failed":
		_status_label.text = "检索引擎: SDK 下载失败 [离线]"
		_status_label.add_theme_color_override("font_color", Color(0.65, 0.40, 0.35, 0.6))
	else:
		_status_label.text = "检索引擎: 未就绪 [离线]"
		_status_label.add_theme_color_override("font_color", Color(0.65, 0.45, 0.40, 0.6))

# ═══════════════════════════════════════════════
#  引导卡片 (Everything 未就绪时显示)
# ═══════════════════════════════════════════════

func _show_guide_card() -> void:
	_hide_guide_card()
	if not is_instance_valid(_result_container):
		return

	_guide_card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.7)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = Color.from_hsv(EventBus.ui_hue, 0.25, 0.5, 0.3)
	style.content_margin_left = 20; style.content_margin_right = 20
	style.content_margin_top = 20; style.content_margin_bottom = 20
	_guide_card.add_theme_stylebox_override("panel", style)
	_result_container.add_child(_guide_card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	_guide_card.add_child(vbox)

	# 状态图标
	var icon_label = Label.new()
	icon_label.text = "[OFFLINE]"
	icon_label.add_theme_font_size_override("font_size", 14)
	icon_label.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.7, 0.6))
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_label)

	# 标题
	var title = Label.new()
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	# 说明文字
	var desc = Label.new()
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.55, 0.62, 0.70, 0.7))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc)

	# 根据错误类型显示不同内容
	var _everything_installed = false
	if _search_engine and _search_engine.has_method("FindEverythingExe"):
		var exe_path: String = _search_engine.call("FindEverythingExe")
		_everything_installed = exe_path.length() > 0

	match _engine_error:
		"not_running":
			title.text = "Everything 未运行"
			if _everything_installed:
				desc.text = "检测到 Everything 已安装但未运行。\n点击下方按钮，由本机代为启动。"
			else:
				desc.text = "检索终端依赖 Everything 提供毫秒级全盘索引。\n请启动 Everything 后再试，终端会自动接入。"
			icon_label.text = "[STANDBY]"
		"downloading":
			title.text = "SDK 下载中"
			desc.text = "首次使用，正在从 voidtools.com 下载 Everything SDK...\n下载完成后自动就绪。"
			icon_label.text = "[SYNC]"
		"download_failed":
			title.text = "SDK 下载失败"
			desc.text = "无法从 voidtools.com 获取 SDK。\n请检查网络连接后重试，或手动下载 Everything64.dll 放入程序目录。"
			icon_label.text = "[ERROR]"
		_:
			if _everything_installed:
				title.text = "Everything 未运行"
				desc.text = "检测到 Everything 已安装。\n点击下方按钮，由本机代为启动。"
				icon_label.text = "[STANDBY]"
			else:
				title.text = "需要安装 Everything"
				desc.text = "检索终端依赖 Everything 提供毫秒级全盘文件索引。\n安装后在后台运行，终端将自动接入。轻量无广告，推荐安装。"

	# 分隔线
	var sep = HSeparator.new()
	var sep_s = StyleBoxFlat.new()
	sep_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.15, 0.35, 0.2)
	sep_s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", sep_s)
	sep.add_theme_constant_override("separation", 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# 操作按钮区
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(btn_row)

	# 按钮样式工厂
	var _make_primary_btn = func(text: String) -> Button:
		var btn = Button.new()
		btn.text = text
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.95, 0.95))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		var s = StyleBoxFlat.new()
		s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.3, 0.6)
		s.set_corner_radius_all(5)
		s.set_border_width_all(1)
		s.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.5)
		s.content_margin_left = 16; s.content_margin_right = 16
		s.content_margin_top = 6; s.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", s)
		var h = s.duplicate()
		h.bg_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.45, 0.75)
		h.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.7)
		btn.add_theme_stylebox_override("hover", h)
		btn.add_theme_stylebox_override("pressed", h)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		return btn

	# 启动按钮 (已安装 Everything 时显示)
	if _everything_installed and _engine_error != "downloading":
		var launch_btn = _make_primary_btn.call("启动 Everything")
		launch_btn.pressed.connect(func():
			if _search_engine:
				var ok: bool = _search_engine.call("TryLaunchEverything")
				var pet = _get_pet()
				if ok:
					if pet:
						pet.show_local_bubble("正在唤醒 Everything。稍候。")
					# 2 秒后自动重新检测
					await get_tree().create_timer(2.5).timeout
					_check_engine_status()
					if _engine_available:
						_hide_guide_card()
						if is_instance_valid(_input_field):
							_input_field.grab_focus()
						if pet:
							pet.show_local_bubble("检索引擎已接入。")
				else:
					if pet:
						pet.show_local_bubble("唤醒失败。请手动启动 Everything。")
		)
		btn_row.add_child(launch_btn)
	# 下载按钮 (未安装时显示)
	elif _engine_error != "downloading":
		var dl_btn = _make_primary_btn.call("前往下载 Everything")
		dl_btn.pressed.connect(func():
			OS.shell_open(EVERYTHING_URL)
			var pet = _get_pet()
			if pet:
				pet.show_local_bubble("已打开下载页面。安装后启动即可。")
		)
		btn_row.add_child(dl_btn)

	# 重试按钮 (安装/启动 Everything 后点击)
	if _engine_error != "downloading":
		var retry_btn = Button.new()
		retry_btn.text = "重新检测"
		retry_btn.add_theme_font_size_override("font_size", 13)
		retry_btn.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75, 0.8))
		retry_btn.add_theme_color_override("font_hover_color", Color(0.85, 0.92, 1.0, 1.0))
		var rt_s = StyleBoxFlat.new()
		rt_s.bg_color = Color(0.10, 0.12, 0.18, 0.5)
		rt_s.set_corner_radius_all(4)
		rt_s.set_border_width_all(1)
		rt_s.border_color = Color(0.4, 0.45, 0.5, 0.3)
		rt_s.content_margin_left = 12; rt_s.content_margin_right = 12
		rt_s.content_margin_top = 5; rt_s.content_margin_bottom = 5
		retry_btn.add_theme_stylebox_override("normal", rt_s)
		var rt_h = rt_s.duplicate()
		rt_h.bg_color = Color(0.15, 0.18, 0.25, 0.7)
		rt_h.border_color = Color(0.5, 0.55, 0.6, 0.5)
		retry_btn.add_theme_stylebox_override("hover", rt_h)
		retry_btn.add_theme_stylebox_override("pressed", rt_h)
		retry_btn.mouse_filter = Control.MOUSE_FILTER_PASS
		retry_btn.pressed.connect(func():
			_check_engine_status()
			if _engine_available:
				_hide_guide_card()
				var pet = _get_pet()
				if pet:
					pet.show_local_bubble(LINES.open)
			else:
				var pet = _get_pet()
				if pet:
					if _engine_error == "not_running":
						pet.show_local_bubble(LINES.not_running)
					else:
						pet.show_local_bubble(LINES.offline)
		)
		btn_row.add_child(retry_btn)

func _hide_guide_card() -> void:
	if _guide_card != null and is_instance_valid(_guide_card):
		_guide_card.queue_free()
		_guide_card = null

# ═══════════════════════════════════════════════
#  搜索逻辑
# ═══════════════════════════════════════════════

func _on_text_changed(text: String) -> void:
	_clear_btn.visible = text.length() > 0
	if text.strip_edges().is_empty():
		_cancel_and_clear()
		return
	# 防抖: 250ms (Everything 是毫秒级, 不用等太久)
	_pending_query = text
	_debounce_timer = 0.25

func _execute_search(query: String) -> void:
	query = query.strip_edges()
	if query.is_empty():
		_cancel_and_clear()
		return
	if _search_engine == null:
		_find_search_engine()
		if _search_engine == null:
			return
	# 搜索前重新检测 (用户可能刚启动 Everything)
	if not _engine_available:
		_check_engine_status()
		if not _engine_available:
			return
	# 引擎上线了, 清掉引导卡片
	_hide_guide_card()

	# 清空旧结果
	_clear_results()
	_is_searching = true
	_query = query
	_update_status_label()

	# 发起异步搜索 (C# 后台线程)
	_search_engine.call("StartSearch", query, MAX_VISIBLE_RESULTS, "all")

func _poll_search_results() -> void:
	if _search_engine == null:
		return
	# 获取新增结果
	var new_results: Array = _search_engine.call("PollResults")
	if new_results.size() > 0:
		var base_index = _result_cards.size()
		for i in new_results.size():
			var item = new_results[i]
			_results.append(item)
			var card: Control
			if _detail_view:
				card = _make_detail_card(item, base_index + i)
			else:
				card = _make_result_card(item, base_index + i)
			_result_container.add_child(card)
			_result_cards.append(card)
			# 入场动画: 淡入
			card.modulate.a = 0.0
			var tw = create_tween()
			var delay = i * 0.03
			tw.tween_property(card, "modulate:a", 1.0, 0.2).set_delay(delay).set_ease(Tween.EASE_OUT)
		_total_results = _results.size()
		_count_label.text = "命中 %d 个目标" % _total_results
	# 检查搜索是否完成
	if _search_engine.call("IsSearchDone"):
		_is_searching = false
		# 重新获取引擎状态 (可能中途断连)
		_check_engine_status()
		if _results.is_empty() and not _query.is_empty():
			if not _engine_available:
				# Everything 掉线了
				_count_label.text = ""
				_show_guide_card()
				var pet = _get_pet()
				if pet:
					pet.show_local_bubble(LINES.not_running)
			else:
				_count_label.text = "未检测到匹配项"
	else:
		_update_status_label()

func _cancel_and_clear() -> void:
	if _is_searching and _search_engine != null:
		_search_engine.call("CancelSearch")
	_is_searching = false
	_clear_results()
	_update_status_label()

func _clear_results() -> void:
	_results = []
	_total_results = 0
	_count_label.text = ""
	for card in _result_cards:
		if is_instance_valid(card):
			card.queue_free()
	_result_cards.clear()

# ═══════════════════════════════════════════════
#  结果渲染
# ═══════════════════════════════════════════════

func _make_result_card(item: Dictionary, index: int) -> Control:
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.5) if index % 2 == 0 else Color(0.07, 0.09, 0.16, 0.5)
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color.from_hsv(EventBus.ui_hue, 0.2, 0.4, 0.15)
	style.content_margin_left = 12; style.content_margin_right = 12
	style.content_margin_top = 8; style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	# hover 效果
	var hover_style = style.duplicate()
	hover_style.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.7, 0.4)
	hover_style.bg_color = Color(0.08, 0.10, 0.18, 0.7)
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", hover_style))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", style))

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(vbox)

	# 第一行: 图标 + 文件名 + 大小
	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 文件类型图标 (用字符表示)
	var icon_label = Label.new()
	var is_folder: bool = item.get("is_folder", false)
	var ext: String = str(item.get("extension", "")).to_lower()
	icon_label.text = _get_type_icon(is_folder, ext)
	icon_label.add_theme_font_size_override("font_size", 14)
	icon_label.add_theme_color_override("font_color", _get_type_color(is_folder, ext))
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(icon_label)

	# 文件名
	var name_label = Label.new()
	name_label.text = str(item.get("name", ""))
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.95))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(name_label)

	# 大小
	var size_label = Label.new()
	var size_val: int = int(item.get("size", 0))
	size_label.text = _format_size(size_val) if not is_folder else ""
	size_label.add_theme_font_size_override("font_size", 13)
	size_label.add_theme_color_override("font_color", Color(0.50, 0.58, 0.65, 0.6))
	size_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(size_label)

	vbox.add_child(row1)

	# 第二行: 路径 + 修改时间
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var path_label = Label.new()
	path_label.text = str(item.get("path", ""))
	path_label.add_theme_font_size_override("font_size", 12)
	path_label.add_theme_color_override("font_color", Color(0.45, 0.52, 0.60, 0.55))
	path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row2.add_child(path_label)

	var date_label = Label.new()
	date_label.text = str(item.get("date_modified", ""))
	date_label.add_theme_font_size_override("font_size", 12)
	date_label.add_theme_color_override("font_color", Color(0.45, 0.52, 0.60, 0.5))
	date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row2.add_child(date_label)

	vbox.add_child(row2)

	# 第三行: 操作按钮
	var row3 = HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	row3.mouse_filter = Control.MOUSE_FILTER_PASS
	row3.alignment = BoxContainer.ALIGNMENT_END

	var full_path: String = str(item.get("full_path", ""))

	var locate_btn = _make_action_btn("定位", Color(0.3, 0.7, 0.5, 0.8))
	locate_btn.pressed.connect(func(): _on_locate(full_path))
	row3.add_child(locate_btn)

	var copy_btn = _make_action_btn("复制路径", Color(0.3, 0.6, 0.8, 0.8))
	copy_btn.pressed.connect(func(): _on_copy_path(full_path))
	row3.add_child(copy_btn)

	vbox.add_child(row3)

	return card

func _make_detail_card(item: Dictionary, index: int) -> Control:
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.35) if index % 2 == 0 else Color(0.07, 0.09, 0.16, 0.35)
	style.set_corner_radius_all(2)
	style.set_border_width_all(0)
	style.content_margin_left = 8; style.content_margin_right = 8
	style.content_margin_top = 3; style.content_margin_bottom = 3
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	# hover
	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.08, 0.10, 0.18, 0.6)
	hover_style.set_border_width_all(1)
	hover_style.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.6, 0.3)
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", hover_style))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", style))

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(row)

	var is_folder: bool = item.get("is_folder", false)
	var ext: String = str(item.get("extension", "")).to_lower()

	# 图标
	var icon_l = Label.new()
	icon_l.text = _get_type_icon(is_folder, ext)
	icon_l.add_theme_font_size_override("font_size", 12)
	icon_l.add_theme_color_override("font_color", _get_type_color(is_folder, ext))
	icon_l.custom_minimum_size.x = 28
	icon_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_l)

	# 文件名
	var name_l = Label.new()
	name_l.text = str(item.get("name", ""))
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96, 0.9))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_l)

	# 日期
	var date_l = Label.new()
	date_l.text = str(item.get("date_modified", ""))
	date_l.add_theme_font_size_override("font_size", 11)
	date_l.add_theme_color_override("font_color", Color(0.42, 0.48, 0.55, 0.5))
	date_l.custom_minimum_size.x = 110
	date_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(date_l)

	# 大小
	var size_l = Label.new()
	var size_val: int = int(item.get("size", 0))
	size_l.text = _format_size(size_val) if not is_folder else ""
	size_l.add_theme_font_size_override("font_size", 11)
	size_l.add_theme_color_override("font_color", Color(0.42, 0.48, 0.55, 0.5))
	size_l.custom_minimum_size.x = 60
	size_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	size_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(size_l)

	# 双击打开 / 右键复制路径
	var full_path: String = str(item.get("full_path", ""))
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
				_on_locate(full_path)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_on_copy_path(full_path)
	)

	return card

func _rebuild_result_cards() -> void:
	for card in _result_cards:
		if is_instance_valid(card):
			card.queue_free()
	_result_cards.clear()
	for i in _results.size():
		var card: Control
		if _detail_view:
			card = _make_detail_card(_results[i], i)
		else:
			card = _make_result_card(_results[i], i)
		_result_container.add_child(card)
		_result_cards.append(card)

func _make_action_btn(text: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", Color(color.r + 0.2, color.g + 0.2, color.b + 0.2, 1.0))
	var s = StyleBoxFlat.new()
	s.bg_color = Color(color.r * 0.15, color.g * 0.15, color.b * 0.15, 0.4)
	s.set_corner_radius_all(3)
	s.set_border_width_all(1)
	s.border_color = Color(color.r, color.g, color.b, 0.3)
	s.content_margin_left = 8; s.content_margin_right = 8
	s.content_margin_top = 2; s.content_margin_bottom = 2
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.6)
	h.border_color = Color(color.r, color.g, color.b, 0.6)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
	)
	return btn

# ═══════════════════════════════════════════════
#  操作回调
# ═══════════════════════════════════════════════

func _on_locate(path: String) -> void:
	# 复用 FileOperations.OpenInExplorer
	var file_ops = _find_csharp_node("OpenInExplorer")
	if file_ops:
		file_ops.call("OpenInExplorer", path)
	var pet = _get_pet()
	if pet:
		pet.show_local_bubble(LINES.locate)

func _on_copy_path(path: String) -> void:
	DisplayServer.clipboard_set(path)
	var pet = _get_pet()
	if pet:
		pet.show_local_bubble(LINES.copy_path)

# ═══════════════════════════════════════════════
#  文件类型识别
# ═══════════════════════════════════════════════

func _get_type_icon(is_folder: bool, ext: String) -> String:
	if is_folder:
		return "[DIR]"
	match ext:
		"pdf", "doc", "docx", "txt", "md", "rtf", "odt":
			return "[DOC]"
		"jpg", "jpeg", "png", "gif", "bmp", "webp", "svg", "ico", "tiff":
			return "[IMG]"
		"mp4", "avi", "mkv", "mov", "wmv", "flv", "webm":
			return "[VID]"
		"mp3", "wav", "flac", "aac", "ogg", "wma", "m4a":
			return "[AUD]"
		"zip", "rar", "7z", "tar", "gz", "bz2", "xz":
			return "[ARC]"
		"exe", "msi", "bat", "cmd", "ps1", "sh":
			return "[EXE]"
		"py", "js", "ts", "cs", "gd", "cpp", "c", "h", "java", "rs", "go":
			return "[COD]"
		"xls", "xlsx", "csv":
			return "[XLS]"
		"ppt", "pptx":
			return "[PPT]"
		"html", "htm", "css", "xml", "json", "yaml", "yml":
			return "[WEB]"
		_:
			return "[---]"

func _get_type_color(is_folder: bool, ext: String) -> Color:
	if is_folder:
		return Color(0.9, 0.75, 0.3, 0.8)
	match ext:
		"pdf", "doc", "docx", "txt", "md", "rtf", "odt":
			return Color(0.4, 0.7, 0.9, 0.7)
		"jpg", "jpeg", "png", "gif", "bmp", "webp", "svg", "ico", "tiff":
			return Color(0.7, 0.5, 0.9, 0.7)
		"mp4", "avi", "mkv", "mov", "wmv", "flv", "webm":
			return Color(0.9, 0.5, 0.5, 0.7)
		"mp3", "wav", "flac", "aac", "ogg", "wma", "m4a":
			return Color(0.5, 0.8, 0.5, 0.7)
		"zip", "rar", "7z", "tar", "gz", "bz2", "xz":
			return Color(0.8, 0.6, 0.3, 0.7)
		"exe", "msi", "bat", "cmd", "ps1", "sh":
			return Color(0.9, 0.4, 0.4, 0.7)
		"py", "js", "ts", "cs", "gd", "cpp", "c", "h", "java", "rs", "go":
			return Color(0.3, 0.8, 0.7, 0.7)
		_:
			return Color(0.5, 0.55, 0.6, 0.6)

func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	elif bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
	else:
		return "%.2f GB" % (bytes / (1024.0 * 1024.0 * 1024.0))

# ═══════════════════════════════════════════════
#  边框渲染
# ═══════════════════════════════════════════════

func _on_frame_draw() -> void:
	if not _frame_drawer: return
	var hue = EventBus.ui_hue
	var w = _frame_drawer.size.x
	var h = _frame_drawer.size.y

	# 1. 六边形切角多边形
	var c_l = 24.0
	var pts = PackedVector2Array()
	pts.append(Vector2(c_l, 0))
	pts.append(Vector2(w, 0))
	pts.append(Vector2(w, h - c_l))
	pts.append(Vector2(w - c_l, h))
	pts.append(Vector2(0, h))
	pts.append(Vector2(0, c_l))
	pts.append(Vector2(c_l, 0))

	# 2. 深色磨砂背景
	var bg_c = Color(0.03, 0.05, 0.09, 0.95)
	_frame_drawer.draw_polygon(pts, PackedColorArray([bg_c]))

	# 3. 主边界线
	var border_c = Color.from_hsv(hue, 0.4, 0.7, 0.35)
	_frame_drawer.draw_polyline(pts, border_c, 1.2, true)

	# 4. 角刻度
	var tick_c = Color.from_hsv(hue, 0.5, 0.8, 0.25)
	var cx = w * 0.5
	for i in range(-20, 21):
		var tx = cx + i * 8.0
		var ty_len = 3.0 if i % 5 != 0 else 6.0
		if tx > c_l and tx < w - c_l:
			_frame_drawer.draw_line(Vector2(tx, 0), Vector2(tx, ty_len), tick_c, 1.0)

	# 5. 呼吸切角
	var breathe = (sin(_time_passed * 4.0) * 0.5 + 0.5) * 0.6 + 0.4
	var br_c = Color.from_hsv(hue, 0.6, 0.9, 0.7 * breathe)
	_frame_drawer.draw_line(pts[5], pts[6], br_c, 2.5, true)
	_frame_drawer.draw_line(pts[2], pts[3], br_c, 2.5, true)

	# 6. 直角 L 型托座
	var L_len = 14.0
	_frame_drawer.draw_polyline(PackedVector2Array([
		pts[1] + Vector2(-L_len, 0), pts[1], pts[1] + Vector2(0, L_len)
	]), br_c, 2.5, true)
	_frame_drawer.draw_polyline(PackedVector2Array([
		pts[4] + Vector2(L_len, 0), pts[4], pts[4] + Vector2(0, -L_len)
	]), br_c, 2.5, true)

	# 7. 电流游走
	var total_len = 0.0
	var segs = []
	for i in range(6):
		var p1 = pts[i]
		var p2 = pts[i+1]
		var d = p1.distance_to(p2)
		segs.append({ "p1": p1, "p2": p2, "dist": d, "offset": total_len })
		total_len += d

	var runner_len = 120.0
	var speed = 600.0
	var current_head = fmod(_time_passed * speed, total_len)
	var highlight_c = Color.from_hsv(hue, 0.4, 0.95, 0.8)
	var glow_c = Color.from_hsv(hue, 0.6, 0.95, 0.25)

	for wrap in range(-1, 2):
		var head = current_head + wrap * total_len
		var tail = head - runner_len
		if tail >= total_len or head <= 0:
			continue
		var start_d = maxf(0.0, tail)
		var end_d = minf(total_len, head)
		for seg in segs:
			var s_offset = seg.offset
			var e_offset = seg.offset + seg.dist
			if end_d <= s_offset or start_d >= e_offset:
				continue
			var t_start = maxf(0.0, start_d - s_offset) / seg.dist
			var t_end = minf(seg.dist, end_d - s_offset) / seg.dist
			var p_s = seg.p1.lerp(seg.p2, t_start)
			var p_e = seg.p1.lerp(seg.p2, t_end)
			_frame_drawer.draw_line(p_s, p_e, glow_c, 5.0, true)
			_frame_drawer.draw_line(p_s, p_e, highlight_c, 1.5, true)



# ═══════════════════════════════════════════════
#  工具方法
# ═══════════════════════════════════════════════

func _get_pet() -> Node:
	var tree = get_tree()
	if tree == null:
		return null
	var main_node = tree.root.get_node_or_null("Main")
	if main_node and "pet_instance" in main_node:
		return main_node.pet_instance
	return null

func _find_pet_at_mouse() -> Node:
	var main_node = get_tree().root.get_node_or_null("Main")
	if not main_node or not "pet_instances" in main_node:
		return null
	for p in main_node.pet_instances:
		if is_instance_valid(p) and p.is_mouse_on_pet():
			return p
	return null

func _find_csharp_node(method_name: String) -> Node:
	var tree = get_tree()
	if tree == null:
		return null
	var main_node = tree.root.get_node_or_null("Main")
	if main_node:
		for child in main_node.get_children():
			if child.has_method(method_name):
				return child
	return null

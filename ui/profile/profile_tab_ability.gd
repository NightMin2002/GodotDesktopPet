# profile_tab_ability.gd — 能力数据 Tab
# [占位符状态] 能力成长系统待规划，当前展示结构骨架
extends HBoxContainer

var _level_label: Label
var _xp_label: Label
var _rate_label: Label
var _level_bar_fill: Panel
var _level_bar_bg: Panel

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER # 彻底隐形原生滚动条
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)

	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", ProfileStyles.card_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.add_child(card)
	scroll.add_child(margin)

	var vbox = ProfileStyles.make_tab_vbox(16)
	card.add_child(vbox)

	var accent = ProfileStyles.accent()
	var dim = ProfileStyles.dim()
	var val_col = ProfileStyles.val_color()

	# ── 1. 模块标题 ──
	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim("分析模块 //", 11))
	title_row.add_child(ProfileStyles.title_label("核心架构熟练度 [CORE_ARCH]", 16))
	vbox.add_child(title_row)

	# ── 2. 核心大盘视图 (Level + 数据槽) ──
	var top_display = HBoxContainer.new()
	top_display.add_theme_constant_override("separation", 16)
	vbox.add_child(top_display)

	# 左侧：巨型 Level 专属面板
	var lv_panel = PanelContainer.new()
	var lv_ps = StyleBoxFlat.new()
	lv_ps.bg_color = Color(0.01, 0.02, 0.05, 0.4)
	lv_ps.border_width_left = 4
	lv_ps.border_color = accent
	lv_ps.content_margin_left = 16; lv_ps.content_margin_right = 24
	lv_ps.content_margin_top = 8; lv_ps.content_margin_bottom = 8
	lv_panel.add_theme_stylebox_override("panel", lv_ps)

	var lv_vbox = VBoxContainer.new()
	lv_vbox.add_theme_constant_override("separation", -8)
	var lv_tag = ProfileStyles.label_dim("SYS_OVERALL_LEVEL", 10)
	lv_tag.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.6))
	lv_vbox.add_child(lv_tag)
	_level_label = ProfileStyles.make_label("—", 46, Color(accent.r, accent.g, accent.b, 0.4))
	lv_vbox.add_child(_level_label)
	lv_panel.add_child(lv_vbox)
	top_display.add_child(lv_panel)

	# 右侧：数据块列 (占位)
	var stats_grid = HBoxContainer.new()
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override("separation", 10)
	top_display.add_child(stats_grid)

	_xp_label = _add_stat_cell(stats_grid, "积累承载量", "—", Color(val_col.r, val_col.g, val_col.b, 0.4))
	_rate_label = _add_stat_cell(stats_grid, "推算偏差概率", "—", Color(dim.r, dim.g, dim.b, 0.4))

	# ── 3. 护甲包裹式的进度条 (空进度) ──
	var bar_shell = PanelContainer.new()
	var bc_s = StyleBoxFlat.new()
	bc_s.bg_color = Color(0, 0, 0, 0)
	bc_s.border_width_top = 1; bc_s.border_width_bottom = 1
	bc_s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.15)
	bc_s.content_margin_left = 2; bc_s.content_margin_right = 2
	bc_s.content_margin_top = 6; bc_s.content_margin_bottom = 6
	bar_shell.add_theme_stylebox_override("panel", bc_s)
	vbox.add_child(bar_shell)
	
	_level_bar_bg = Panel.new()
	_level_bar_bg.custom_minimum_size = Vector2(0, 4)
	_level_bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar_bg_s = StyleBoxFlat.new()
	bar_bg_s.bg_color = Color(0.08, 0.10, 0.18, 0.8)
	_level_bar_bg.add_theme_stylebox_override("panel", bar_bg_s)
	bar_shell.add_child(_level_bar_bg)

	# 进度条填充为空 (anchor_right = 0)
	_level_bar_fill = Panel.new()
	var bar_fill_s = StyleBoxFlat.new()
	bar_fill_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.3)
	_level_bar_fill.add_theme_stylebox_override("panel", bar_fill_s)
	_level_bar_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_bar_fill.anchor_right = 0.0 # 占位：无进度
	_level_bar_bg.add_child(_level_bar_fill)

	# ── 4. 终端返回式日志说明 ──
	var note_pnl = PanelContainer.new()
	var n_s = StyleBoxFlat.new()
	n_s.bg_color = Color(0, 0, 0, 0)
	n_s.border_width_left = 2
	n_s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.6, 0.3)
	n_s.content_margin_left = 8
	note_pnl.add_theme_stylebox_override("panel", n_s)
	
	var note = ProfileStyles.label_dim("> SYS_REPORT: 能力成长系统待规划。当前模块为结构占位符，数据接入后自动激活。", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_pnl.add_child(note)
	vbox.add_child(note_pnl)

	# 分隔线
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	vbox.add_child(sep)

	# ── 5. 底层干预终端 (Control Row) [占位，按钮不执行操作] ──
	var ctrl_row = HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 24)
	ctrl_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_child(ctrl_row)

	var override_box = HBoxContainer.new()
	override_box.add_theme_constant_override("separation", 10)
	ctrl_row.add_child(override_box)
	
	override_box.add_child(ProfileStyles.label_dim("底层覆写协议 [权限: 操作员] [未激活]", 12))

	var btn_n = ProfileStyles.small_btn_normal()
	# 复用样式但降低透明度表示不可用
	var btn_disabled = btn_n.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color(btn_disabled.bg_color.r, btn_disabled.bg_color.g, btn_disabled.bg_color.b, 0.2)
	btn_disabled.border_color = Color(btn_disabled.border_color.r, btn_disabled.border_color.g, btn_disabled.border_color.b, 0.2)

	for item in [{"label": "-"}, {"label": "∝"}, {"label": "+"}]:
		var btn = Button.new()
		btn.text = item.label
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.25))
		btn.add_theme_stylebox_override("normal", btn_disabled)
		btn.add_theme_stylebox_override("hover", btn_disabled)
		btn.add_theme_stylebox_override("pressed", btn_disabled)
		btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		# [占位] 系统未激活，按钮不绑定任何操作
		override_box.add_child(btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl_row.add_child(spacer)

	# ── 独立科幻滚动指示器 ──
	var indicator = preload("res://ui/profile/cyber_scroll_indicator.gd").new()
	indicator.bind_scroll(scroll)
	add_child(indicator)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_level_label = null
	_xp_label = null
	_rate_label = null
	_level_bar_fill = null
	_level_bar_bg = null
	build()

# ── 专用的内部槽位制造工厂 ──

func _add_stat_cell(parent: Control, lbl: String, val: String, val_color: Color) -> Label:
	var pnl = PanelContainer.new()
	pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.01, 0.02, 0.05, 0.3)
	s.border_width_left = 2
	s.border_width_bottom = 1
	s.border_color = Color(val_color.r, val_color.g, val_color.b, maxf(val_color.a, 0.3))
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 6; s.content_margin_bottom = 6
	pnl.add_theme_stylebox_override("panel", s)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(ProfileStyles.label_dim(lbl, 11))
	
	var val_label = ProfileStyles.make_label(val, 16, val_color)
	vb.add_child(val_label)
	pnl.add_child(vb)
	parent.add_child(pnl)
	
	return val_label

func _get_pet() -> Node:
	return ProfileStyles.get_pet(get_tree())

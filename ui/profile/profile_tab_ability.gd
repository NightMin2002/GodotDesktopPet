# profile_tab_ability.gd — 能力数据 Tab (等级/经验/控制/互动)
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

	var lv_info = SettingsManager.get_gaming_level_progress()
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
	_level_label = ProfileStyles.make_label(str(lv_info.level), 46, accent)
	lv_vbox.add_child(_level_label)
	lv_panel.add_child(lv_vbox)
	top_display.add_child(lv_panel)

	# 右侧：数据块列 (EXP / ERR_RATE)
	var stats_grid = HBoxContainer.new()
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override("separation", 10)
	top_display.add_child(stats_grid)

	var xp_txt = "%d / %d" % [lv_info.xp, lv_info.xp_next] if lv_info.level < SettingsManager.MAX_LEVEL else "数据已满 (MAX)"
	_xp_label = _add_stat_cell(stats_grid, "积累承载量", xp_txt, val_col)
	_rate_label = _add_stat_cell(stats_grid, "推算偏差概率", "%.1f%%" % (lv_info.rate * 100.0), dim)

	# ── 3. 护甲包裹式的进度条 ──
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

	_level_bar_fill = Panel.new()
	var bar_fill_s = StyleBoxFlat.new()
	bar_fill_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.9)
	_level_bar_fill.add_theme_stylebox_override("panel", bar_fill_s)
	_level_bar_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_bar_fill.anchor_right = clampf(lv_info.progress, 0, 1)
	_level_bar_bg.add_child(_level_bar_fill)

	# ── 4. 终端返回式日志说明 ──
	var note_pnl = PanelContainer.new()
	var n_s = StyleBoxFlat.new()
	n_s.bg_color = Color(0, 0, 0, 0)
	n_s.border_width_left = 2
	n_s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.6, 0.3)
	n_s.content_margin_left = 8
	note_pnl.add_theme_stylebox_override("panel", n_s)
	
	var note = ProfileStyles.label_dim("> SYS_REPORT: 熟练度参数将随全局策略推演自动积累更新。执行模型阈值突破后，系统自主操控的容错率与精准度自动同步提升。", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_pnl.add_child(note)
	vbox.add_child(note_pnl)

	# 分隔线
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	vbox.add_child(sep)

	# ── 5. 底层人工干预终端 (Control Row) ──
	var ctrl_row = HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 24)
	ctrl_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_child(ctrl_row)

	# 干预面板左侧 (等级覆写)
	var override_box = HBoxContainer.new()
	override_box.add_theme_constant_override("separation", 10)
	ctrl_row.add_child(override_box)
	
	override_box.add_child(ProfileStyles.label_dim("底层覆写协议 [权限: 操作员]", 12))

	var btn_n = ProfileStyles.small_btn_normal()
	var btn_h = ProfileStyles.small_btn_hover()

	for item in [{"label": "-", "action": "down"}, {"label": "∝", "action": "reset"}, {"label": "+", "action": "up"}]:
		var btn = Button.new()
		btn.text = item.label
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
		btn.add_theme_stylebox_override("normal", btn_n)
		btn.add_theme_stylebox_override("hover", btn_h)
		btn.add_theme_stylebox_override("pressed", btn_h)
		var action = item.action
		btn.pressed.connect(func(): _on_level_action(action))
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
	s.border_color = Color(val_color.r, val_color.g, val_color.b, maxf(val_color.a, 0.5))
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

# ── 等级控制 ──

func _on_level_action(action: String) -> void:
	var pet = _get_pet()
	var level = SettingsManager.get_gaming_level()
	if action == "up":
		if level >= SettingsManager.MAX_LEVEL:
			if pet: pet.show_local_bubble("...已是最高等级。")
			return
		var target_xp = SettingsManager.LEVEL_XP[mini(level, SettingsManager.MAX_LEVEL - 1)]
		SettingsManager.set_int("gaming_xp", target_xp)
		if pet: pet.show_local_bubble("...后台训练模块的数据已同步。Lv.%d。" % SettingsManager.get_gaming_level())
	elif action == "down":
		if level <= 1:
			if pet: pet.show_local_bubble("...已经 Lv.1。没有可回退的数据。")
			return
		var target_xp = SettingsManager.LEVEL_XP[level - 2]
		SettingsManager.set_int("gaming_xp", target_xp)
		if pet: pet.show_local_bubble("训练数据回退。Lv.%d。...不太理解目的。" % SettingsManager.get_gaming_level())
	elif action == "reset":
		SettingsManager.set_int("gaming_xp", 0)
		if pet: pet.show_local_bubble("检测到用户越权清除训练数据。...已批准。")
	refresh()

func _on_level_change(diff: int) -> void:
	var lv_info = SettingsManager.get_gaming_level_progress()
	lv_info.level += diff
	SettingsManager.set_gaming_level(lv_info.level)
	refresh()

func _get_pet() -> Node:
	var main_n = get_tree().root.get_node_or_null("Main")
	if main_n and "pet_instances" in main_n and main_n.pet_instances.size() > 0:
		return main_n.pet_instances[0]
	return null

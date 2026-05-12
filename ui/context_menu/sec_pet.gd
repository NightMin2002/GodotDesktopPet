# sec_pet.gd — 宠物分区 (构建 + 回调 + 分身 + profile + records)
extends RefCounted

var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _chatter_btn: Button
var _clone_btn: Button
var _reminder_btn: Button
var _profile_btn: Button
var _deploy_clone_btn: Button
var _dismiss_btn: Button
var _profile_labels: Dictionary = {}
var _records_container: VBoxContainer = null

# ── 碎碎念 ──
const CHATTER_MODE_LABELS := ["碎碎念 · 已关闭 [+]", "碎碎念 · 每30分钟 [+]", "碎碎念 · 每60分钟 [+]"]

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_chatter_btn = ctx._make_menu_btn("碎碎念 · 每30分钟 [+]", Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_chatter_btn)
	ctx._bind_l3_trigger(_chatter_btn, "chatter", "sec_pet")

	_clone_btn = ctx._make_menu_btn("分身 (0/5) [+]", Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_clone_btn)
	ctx._bind_l3_trigger(_clone_btn, "clone", "sec_pet")

	_reminder_btn = ctx._make_menu_btn("提醒管理", Color(0.2, 0.85, 1.0, 1))
	ctx._apply_capsule_style(_reminder_btn, Color(0.12, 0.22, 0.42, 0.7), Color(0.4, 0.6, 0.9, 0.5))
	_reminder_btn.pressed.connect(func():
		ctx._close_and_emit(EventBus.show_reminder_panel)
	)
	vbox.add_child(_reminder_btn)

	_profile_btn = ctx._make_menu_btn("训练数据 [+]", Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_profile_btn)
	ctx._bind_l3_trigger(_profile_btn, "pet_profile", "sec_pet")

	var records_btn = ctx._make_menu_btn("对局记录 [+]", Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(records_btn)
	ctx._bind_l3_trigger(records_btn, "game_records", "sec_pet")

	var terminal_btn = ctx._make_menu_btn("个人终端 [+]", Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(terminal_btn)
	ctx._bind_l3_trigger(terminal_btn, "holo_terminal", "sec_pet")

	panel.mouse_entered.connect(func(): ctx._submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.panels["sec_pet"] = panel

	# L3: 碎碎念单选
	ctx._submenu.create_radio("chatter", [
		{"value": 0, "label": "关闭", "desc": "宠物不会主动说话"},
		{"value": 1, "label": "每30分钟", "desc": "每到整点和半点，冒泡说点什么"},
		{"value": 2, "label": "每60分钟", "desc": "每到整点，冒泡说点什么"},
	], _on_radio_chatter_mode, 3)
	ctx._submenu._l3_parent_map["chatter"] = "sec_pet"

	# L3: 分身操作面板
	_build_clone_l3_panel()
	# L3: 经验等级
	_build_profile_panel()
	# L3: 游戏战绩
	_build_records_l3_panel()
	# L3: 个人终端
	_build_terminal_l3_panel()

# ── 碎碎念回调 ──

func _on_radio_chatter_mode(value: int) -> void:
	update_chatter_label(value)
	SettingsManager.set_int("pet_chatter_mode", value)
	EventBus.setting_toggled.emit("pet_chatter_mode", value > 0)
	ctx._submenu.refresh_radio("chatter", value)

func update_chatter_label(mode: int) -> void:
	_chatter_btn.text = CHATTER_MODE_LABELS[mode]

# ── 分身 ──

func _build_clone_l3_panel() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var deploy_btn = ctx._make_menu_btn("部署分身 (0/5)", Color(0.2, 0.85, 1.0, 1))
	deploy_btn.pressed.connect(_on_deploy_clone_pressed)
	vbox.add_child(deploy_btn)
	_deploy_clone_btn = deploy_btn

	_dismiss_btn = ctx._make_menu_btn("回收全部分身", Color(0.2, 0.85, 1.0, 1))
	_dismiss_btn.add_theme_color_override("font_color", Color(0.55, 0.7, 0.75, 0.7))
	_dismiss_btn.pressed.connect(_on_dismiss_btn_pressed)
	vbox.add_child(_dismiss_btn)

	panel.mouse_entered.connect(func(): ctx._submenu.on_l3_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_l3_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.l3_panels["clone"] = panel
	ctx._submenu._l3_parent_map["clone"] = "sec_pet"

func _on_deploy_clone_pressed() -> void:
	if is_instance_valid(ctx.target):
		EventBus.clone_pet.emit(ctx.target)
	await ctx.get_tree().process_frame
	update_clone_label()

func _on_dismiss_btn_pressed() -> void:
	EventBus.dismiss_clones.emit()
	ctx._close_hud()

func update_clone_label() -> void:
	var main_node = ctx.get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instances" in main_node:
		var count: int = (main_node.pet_instances as Array).size() - 1
		var max_c: int = main_node.clone_mgr.MAX_CLONES if main_node.clone_mgr else 5
		_clone_btn.text = "分身 (" + str(count) + "/" + str(max_c) + ") [+]"
		if _deploy_clone_btn:
			_deploy_clone_btn.text = "部署分身 (" + str(count) + "/" + str(max_c) + ")"

# ── 训练数据 (Profile) ──

func _build_profile_panel() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "- 游戏熟练度 -"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 0.8))
	vbox.add_child(title)

	# 等级
	var lv_label = Label.new()
	lv_label.add_theme_font_size_override("font_size", 22)
	lv_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1))
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lv_label)
	_profile_labels["level"] = lv_label

	# XP 进度
	var xp_label = Label.new()
	xp_label.add_theme_font_size_override("font_size", 13)
	xp_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.7))
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(xp_label)
	_profile_labels["xp"] = xp_label

	# XP 进度条
	var bar_bg = Panel.new()
	bar_bg.custom_minimum_size = Vector2(160, 6)
	var bar_bg_style = StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(0.1, 0.12, 0.2, 0.6)
	bar_bg_style.set_corner_radius_all(3)
	bar_bg.add_theme_stylebox_override("panel", bar_bg_style)
	var bar_wrapper = CenterContainer.new()
	bar_wrapper.add_child(bar_bg)
	vbox.add_child(bar_wrapper)

	var bar_fill = Panel.new()
	bar_fill.position = Vector2.ZERO
	bar_fill.size = Vector2(0, 6)
	var bar_fill_style = StyleBoxFlat.new()
	bar_fill_style.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.8)
	bar_fill_style.set_corner_radius_all(3)
	bar_fill.add_theme_stylebox_override("panel", bar_fill_style)
	bar_bg.add_child(bar_fill)
	_profile_labels["bar_fill"] = bar_fill
	_profile_labels["bar_bg"] = bar_bg

	# 失误率
	var rate_label = Label.new()
	rate_label.add_theme_font_size_override("font_size", 13)
	rate_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.7))
	rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rate_label)
	_profile_labels["rate"] = rate_label

	# 操作按钮行
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var btn_style_normal = StyleBoxFlat.new()
	btn_style_normal.bg_color = Color(0.15, 0.18, 0.28, 0.7)
	btn_style_normal.set_corner_radius_all(4)
	btn_style_normal.content_margin_left = 8
	btn_style_normal.content_margin_right = 8
	btn_style_normal.content_margin_top = 3
	btn_style_normal.content_margin_bottom = 3
	var btn_style_hover = StyleBoxFlat.new()
	btn_style_hover.bg_color = Color(0.25, 0.3, 0.45, 0.8)
	btn_style_hover.set_corner_radius_all(4)
	btn_style_hover.content_margin_left = 8
	btn_style_hover.content_margin_right = 8
	btn_style_hover.content_margin_top = 3
	btn_style_hover.content_margin_bottom = 3

	for item in [{"label": "-", "action": "down"}, {"label": "∝", "action": "reset"}, {"label": "+", "action": "up"}]:
		var btn = Button.new()
		btn.text = item.label
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
		btn.add_theme_stylebox_override("normal", btn_style_normal)
		btn.add_theme_stylebox_override("hover", btn_style_hover)
		btn.add_theme_stylebox_override("pressed", btn_style_hover)
		var action = item.action
		btn.pressed.connect(func(): _on_profile_action(action))
		btn_row.add_child(btn)

	panel.mouse_entered.connect(func(): ctx._submenu.on_l3_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_l3_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.l3_panels["pet_profile"] = panel
	ctx._submenu._l3_parent_map["pet_profile"] = "sec_pet"

func refresh_profile() -> void:
	var info = SettingsManager.get_gaming_level_progress()
	if _profile_labels.has("level"):
		_profile_labels["level"].text = "Lv.%d" % info.level
	if _profile_labels.has("xp"):
		if info.level >= SettingsManager.MAX_LEVEL:
			_profile_labels["xp"].text = "XP: %d (MAX)" % info.xp
		else:
			_profile_labels["xp"].text = "XP: %d / %d" % [info.xp, info.xp_next]
	if _profile_labels.has("bar_fill") and _profile_labels.has("bar_bg"):
		var bar_w = _profile_labels["bar_bg"].custom_minimum_size.x
		_profile_labels["bar_fill"].size = Vector2(bar_w * clampf(info.progress, 0, 1), 6)
		var fill_style = _profile_labels["bar_fill"].get_theme_stylebox("panel") as StyleBoxFlat
		if fill_style:
			fill_style.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.8)
	if _profile_labels.has("rate"):
		_profile_labels["rate"].text = "失误率: %.1f%%" % (info.rate * 100.0)

func _on_profile_action(action: String) -> void:
	var pet_node = _get_pet()
	var level = SettingsManager.get_gaming_level()
	if action == "up":
		if level >= SettingsManager.MAX_LEVEL:
			if pet_node: pet_node.show_local_bubble("...已是最高等级。")
			return
		var target_xp = SettingsManager.LEVEL_XP[mini(level, SettingsManager.MAX_LEVEL - 1)]
		SettingsManager.set_int("gaming_xp", target_xp)
		if pet_node: pet_node.show_local_bubble("...后台训练模块的数据已同步。Lv.%d。" % SettingsManager.get_gaming_level())
	elif action == "down":
		if level <= 1:
			if pet_node: pet_node.show_local_bubble("...已经 Lv.1。没有可回退的数据。")
			return
		var target_xp = SettingsManager.LEVEL_XP[level - 2]
		SettingsManager.set_int("gaming_xp", target_xp)
		if pet_node: pet_node.show_local_bubble("训练数据回退。Lv.%d。...不太理解目的。" % SettingsManager.get_gaming_level())
	elif action == "reset":
		SettingsManager.set_int("gaming_xp", 0)
		if pet_node: pet_node.show_local_bubble("检测到用户越权清除训练数据。...已批准。")
	refresh_profile()

func _get_pet() -> Node:
	var main_n = ctx.get_tree().root.get_node_or_null("Main")
	if main_n and "pet_instances" in main_n and main_n.pet_instances.size() > 0:
		return main_n.pet_instances[0]
	return null

# ── 游戏战绩 (Records) ──

func _build_records_l3_panel() -> void:
	var panel = ctx._submenu._make_panel()
	panel.custom_minimum_size = Vector2(200, 0)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	_records_container = vbox

	# 初始化按钮
	var reset_btn = Button.new()
	reset_btn.text = "初始化对局数据"
	reset_btn.add_theme_font_size_override("font_size", 11)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.12, 0.12, 0.6)
	btn_style.set_corner_radius_all(4)
	btn_style.content_margin_left = 6
	btn_style.content_margin_right = 6
	btn_style.content_margin_top = 2
	btn_style.content_margin_bottom = 2
	reset_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.35, 0.15, 0.15, 0.8)
	reset_btn.add_theme_stylebox_override("hover", btn_hover)
	reset_btn.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4, 0.8))
	reset_btn.pressed.connect(_on_reset_records)
	vbox.add_child(reset_btn)

	panel.mouse_entered.connect(func(): ctx._submenu.on_l3_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_l3_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.l3_panels["game_records"] = panel
	ctx._submenu._l3_parent_map["game_records"] = "sec_pet"

func refresh_records() -> void:
	if not _records_container:
		return
	var children = _records_container.get_children()
	for i in range(children.size() - 1):
		children[i].queue_free()

	var dim_color = Color(0.4, 0.5, 0.6, 0.6)
	var val_color = Color(0.6, 0.75, 0.9, 0.85)
	var insert_idx = 0

	for g_id in ["2048", "snake", "minesweeper", "tic_tac_toe"]:
		var g_name = {"2048": "2048", "snake": "贪吃蛇", "minesweeper": "扫雷", "tic_tac_toe": "井字棋"}[g_id]
		var title = Label.new()
		title.text = g_name
		title.add_theme_font_size_override("font_size", 12)
		title.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.9, 0.9))
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_records_container.add_child(title)
		_records_container.move_child(title, insert_idx)
		insert_idx += 1

		if g_id == "tic_tac_toe":
			var w = SettingsManager.get_int("game_tic_tac_toe_wins", 0)
			var l = SettingsManager.get_int("game_tic_tac_toe_losses", 0)
			var d = SettingsManager.get_int("game_tic_tac_toe_draws", 0)
			insert_idx = _add_record_row("  胜 %d  负 %d  平 %d" % [w, l, d], dim_color, insert_idx)
		else:
			for side in ["我", "宠"]:
				var prefix = "game_%s_" % g_id if side == "我" else "game_%s_auto_" % g_id
				var txt = "  %s: " % side
				match g_id:
					"2048":
						var best = SettingsManager.get_int(prefix + "best", 0)
						var tile = SettingsManager.get_int(prefix + "best_tile", 0)
						txt += "最高 %d" % best
						if tile > 0:
							txt += "  最大块 %d" % tile
					"snake":
						var bl = SettingsManager.get_int(prefix + "best_len", 3)
						var gm = SettingsManager.get_int(prefix + "games", 0)
						txt += "最长 %d  局数 %d" % [bl, gm]
					"minesweeper":
						var w = SettingsManager.get_int(prefix + "wins", 0)
						var l = SettingsManager.get_int(prefix + "losses", 0)
						txt += "通关 %d  触雷 %d" % [w, l]
				insert_idx = _add_record_row(txt, val_color if side == "我" else dim_color, insert_idx)

func _add_record_row(text: String, color: Color, idx: int) -> int:
	var row = Label.new()
	row.text = text
	row.add_theme_font_size_override("font_size", 11)
	row.add_theme_color_override("font_color", color)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_records_container.add_child(row)
	_records_container.move_child(row, idx)
	return idx + 1

func _on_reset_records() -> void:
	var keys_to_clear = []
	for gid in ["2048", "minesweeper", "snake", "tic_tac_toe"]:
		for suffix in ["wins", "losses", "best", "best_len", "best_tile", "games", "draws"]:
			keys_to_clear.append("game_%s_%s" % [gid, suffix])
			keys_to_clear.append("game_%s_auto_%s" % [gid, suffix])
	for key in keys_to_clear:
		SettingsManager.set_int(key, 0)
	refresh_records()
	var pet_node = _get_pet()
	if pet_node: pet_node.show_local_bubble("对局数据已清除。...确认归零。")

# ── 个人终端 ──

func _build_terminal_l3_panel() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var items := [
		{"label": "电源状态", "behavior": "_holo_battery", "desc": "全息屏显示系统电源状态与监控"},
		{"label": "状态确认", "behavior": "_holo_done", "desc": "系统信息检索完成核准画面"},
		{"label": "终端报错", "behavior": "_holo_error", "desc": "模拟系统致命错误故障画面"},
		{"label": "新消息", "behavior": "_holo_mail", "desc": "全息屏显示系统级通知与新邮件待办"},
		{"label": "终端引导", "behavior": "_holo_loading", "desc": "全息屏显示系统初始化引导序列"},
		{"label": "待机屏保", "behavior": "_holo_browse", "desc": "弹出全息屏待机屏保 (25秒)"}
	]

	for item in items:
		var btn = Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.2, 0.85, 1.0, 1))
		btn.text = item.label
		var behavior = item.behavior
		btn.pressed.connect(func(): _on_terminal_action(behavior))
		if item.has("desc"):
			var desc_text = item.desc
			var b = btn
			btn.mouse_entered.connect(func(): ctx._tooltip.show_for(b, desc_text, true))
			btn.mouse_exited.connect(func(): ctx._tooltip.show_for(b, desc_text, false))
		vbox.add_child(btn)

	panel.mouse_entered.connect(func(): ctx._submenu.on_l3_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_l3_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.l3_panels["holo_terminal"] = panel
	ctx._submenu._l3_parent_map["holo_terminal"] = "sec_pet"

func _on_terminal_action(behavior: String) -> void:
	ctx._tooltip.panel.hide()
	ctx._submenu.hide_all_instant()
	ctx.hud.hide()
	ctx._sidebar.panel.hide()
	ctx.target = null
	EventBus.context_menu_toggled.emit(false)

	# 深夜模式拒绝执行
	var pet = _get_pet()
	if pet and "nighttime_mode" in pet and pet.nighttime_mode:
		pet.show_local_bubble("休眠周期中。指令已搁置。")
		return

	if pet and not pet.gaming.active and not pet.holo_screen.visible:
		var s: float = -1.0 if pet.global_position.x > pet.boundary_size.x * 0.5 else 1.0
		if behavior == "_holo_browse":
			pet.holo_screen.show_idle(s, 25.0)
		elif behavior == "_holo_loading":
			pet.holo_screen.show_loading("初始化", s, 10.0)
		elif behavior == "_holo_battery":
			pet.holo_screen.show_battery(s, 10.0)
		elif behavior == "_holo_done":
			pet.holo_screen.show_done(s, 4.0)
		elif behavior == "_holo_error":
			pet.holo_screen.show_error(s, 5.0)
		elif behavior == "_holo_mail":
			pet.holo_screen.show_mail(s, 6.0)

# sec_pet.gd — 宠物分区 (构建 + 回调 + 分身 + profile + terminal)
extends RefCounted

var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _chatter_btn: Button
var _clone_btn: Button
var _reminder_btn: Button
var _todo_btn: Button
var _deploy_clone_btn: Button
var _dismiss_btn: Button

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

	_todo_btn = ctx._make_menu_btn("待办清单", Color(0.2, 0.85, 1.0, 1))
	ctx._apply_capsule_style(_todo_btn, Color(0.12, 0.22, 0.42, 0.7), Color(0.4, 0.6, 0.9, 0.5))
	_todo_btn.pressed.connect(func():
		ctx._close_and_emit(EventBus.show_todo_panel)
	)
	vbox.add_child(_todo_btn)

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

# ── 训练数据 (已迁移至装置档案面板 能力数据 Tab) ──

func refresh_profile() -> void:
	pass  # 等级控制已迁移至 pet_profile_panel.gd


func _get_pet() -> Node:
	var main_n = ctx.get_tree().root.get_node_or_null("Main")
	if main_n and "pet_instances" in main_n and main_n.pet_instances.size() > 0:
		return main_n.pet_instances[0]
	return null

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
		{"label": "系统警告", "behavior": "_holo_warning", "desc": "全息屏显示系统轻度警告与提示"},
		{"label": "未知检索", "behavior": "_holo_query", "desc": "全息屏显示查无此项或异常检索状态"},
		{"label": "日程提醒", "behavior": "_holo_alarm", "desc": "全息屏显示模拟铃铛闹钟与时钟点阵"},
		{"label": "碎片清理", "behavior": "_holo_cleanup", "desc": "全息屏显示文件落入垃圾桶粉碎表现"},
		{"label": "网络巡航", "behavior": "_holo_globe", "desc": "全息屏显示3D全球数据网络模拟监控(彩蛋)"},
		{"label": "网络连接", "behavior": "_holo_sync", "desc": "全息屏显示超大机能版扇形通信测算信号"},
		{"label": "系统锁定", "behavior": "_holo_lock", "desc": "全息屏显示防卫锁闭的隐私状态"},
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
		_dispatch_terminal(pet, behavior, s)

# ── 终端行为分发表 (数据驱动, 新增模式只加一行) ──
const _TERMINAL_ACTIONS := {
	"_holo_browse":  {"method": "show_idle",    "duration": 25.0},
	"_holo_loading": {"method": "show_loading", "duration": 10.0, "arg": "初始化"},
	"_holo_battery": {"method": "show_battery", "duration": 10.0},
	"_holo_done":    {"method": "show_done",    "duration": 4.0},
	"_holo_error":   {"method": "show_error",   "duration": 5.0},
	"_holo_warning": {"method": "show_warning", "duration": 5.0},
	"_holo_query":   {"method": "show_query",   "duration": 5.0},
	"_holo_alarm":   {"method": "show_alarm",   "duration": 8.0},
	"_holo_cleanup": {"method": "show_cleanup", "duration": 6.0},
	"_holo_globe":   {"method": "show_globe",   "duration": 10.0},
	"_holo_sync":    {"method": "show_sync",    "duration": 6.0},
	"_holo_lock":    {"method": "show_lock",    "duration": 5.0},
	"_holo_mail":    {"method": "show_mail",    "duration": 6.0},
}

func _dispatch_terminal(pet, behavior: String, s: float) -> void:
	if behavior not in _TERMINAL_ACTIONS:
		return
	var cfg = _TERMINAL_ACTIONS[behavior]
	var method: String = cfg["method"]
	var dur: float = cfg.get("duration", 0.0)
	if cfg.has("arg"):
		pet.holo_screen.call(method, cfg["arg"], s, dur)
	else:
		pet.holo_screen.call(method, s, dur)

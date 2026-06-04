# sec_pet.gd — 宠物分区 (构建 + 回调 + 分身 + profile + terminal)
extends RefCounted



var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _chatter_btn: Button
var _activity_btn: Button
var _appearance_btn: Button
var _size_btn: Button
var _clone_btn: Button
var _deploy_clone_btn: Button
var _dismiss_btn: Button
var _debug_behavior_btn: Button
var _nighttime_btn: Button

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx.make_submenu_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_chatter_btn = ctx._make_menu_btn(ctx.get_radio_title("chatter"), Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_chatter_btn)
	ctx.register_radio_title("chatter", _chatter_btn)
	ctx._bind_l3_trigger(_chatter_btn, "chatter", "sec_pet")

	_clone_btn = ctx._make_menu_btn("分身 (0/5) [+]", Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_clone_btn)
	ctx._bind_l3_trigger(_clone_btn, "clone", "sec_pet")

	_activity_btn = ctx._make_menu_btn(ctx.get_radio_title("auto_activity"), Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_activity_btn)
	ctx.register_radio_title("auto_activity", _activity_btn)
	ctx._bind_l3_trigger(_activity_btn, "auto_activity", "sec_pet")

	_appearance_btn = ctx._make_menu_btn(ctx.get_radio_title("appearance"), Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_appearance_btn)
	ctx.register_radio_title("appearance", _appearance_btn)
	ctx._bind_l3_trigger(_appearance_btn, "appearance", "sec_pet")

	_size_btn = ctx._make_menu_btn(ctx.get_radio_title("pet_size"), Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_size_btn)
	ctx.register_radio_title("pet_size", _size_btn)
	ctx._bind_l3_trigger(_size_btn, "pet_size", "sec_pet")

	var terminal_btn = ctx._make_menu_btn("个人终端 [+]", Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(terminal_btn)
	ctx._bind_l3_trigger(terminal_btn, "holo_terminal", "sec_pet")

	var search_btn = ctx._make_menu_btn("文件检索", Color(0.2, 0.85, 1.0, 1))
	search_btn.pressed.connect(_on_file_search_pressed)
	vbox.add_child(search_btn)

	_debug_behavior_btn = ctx._make_menu_btn("指令序列 [+]", Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_debug_behavior_btn)
	ctx._bind_l3_trigger(_debug_behavior_btn, "debug_behavior", "sec_pet")

	ctx.register_l2_panel("sec_pet", panel)

	# L3: 碎碎念单选
	ctx.create_radio_group("chatter", 3, "sec_pet")

	# L3: 运行功耗单选
	ctx.create_radio_group("auto_activity", 3, "sec_pet")

	# L3: 机体外观单选
	ctx.create_radio_group("appearance", 3, "sec_pet")

	# L3: 机体大小单选
	ctx.create_radio_group("pet_size", 5, "sec_pet")

	# L3: 分身操作面板
	_build_clone_l3_panel()
	# L3: 个人终端
	_build_terminal_l3_panel()
	# L3: 指令序列
	_build_debug_behavior_submenu()

# ── 分身 ──

func _build_clone_l3_panel() -> void:
	var panel = ctx.make_submenu_panel()
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

	ctx._submenu.register_l3_panel("clone", panel, "sec_pet")

func _on_deploy_clone_pressed() -> void:
	if is_instance_valid(ctx.target):
		EventBus.clone_pet.emit(ctx.target)
	await ctx.get_tree().process_frame
	update_clone_label()

func _on_dismiss_btn_pressed() -> void:
	ctx.cleanup_toys()
	EventBus.dismiss_clones.emit()
	# 遣散是异步退场动画, 先刷新标签再关菜单
	await ctx.get_tree().process_frame
	update_clone_label()
	ctx._close_hud()

func update_clone_label() -> void:
	var main_node = ctx.get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instances" in main_node:
		var count: int = (main_node.pet_instances as Array).size() - 1
		var max_c: int = main_node.clone_mgr.MAX_CLONES if main_node.clone_mgr else 5
		_clone_btn.text = "分身 (" + str(count) + "/" + str(max_c) + ") [+]"
		if _deploy_clone_btn:
			_deploy_clone_btn.text = "部署分身 (" + str(count) + "/" + str(max_c) + ")"

# ── 训练数据 (已迁移至装置终端面板 能力数据 Tab) ──

func refresh_profile() -> void:
	pass  # 等级控制已迁移至 pet_profile_panel.gd

# ── 文件检索 ──

func _on_file_search_pressed() -> void:
	ctx.close_menu_instant()
	EventBus.show_file_search.emit()


func _get_pet() -> Node:
	return ProfileStyles.get_pet(ctx.get_tree())

# ── 个人终端 ──

func _build_terminal_l3_panel() -> void:
	var panel = ctx.make_submenu_panel()
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
		{"label": "回收归档", "behavior": "_holo_recycle", "desc": "全息屏显示文件吸入传送涡旋归档存储"},
		{"label": "网络巡航", "behavior": "_holo_globe", "desc": "全息屏显示3D全球数据网络模拟监控(彩蛋)"},
		{"label": "网络连接", "behavior": "_holo_sync", "desc": "全息屏显示超大机能版扇形通信测算信号"},
		{"label": "系统锁定", "behavior": "_holo_lock", "desc": "全息屏显示防卫锁闭的隐私状态"},
		{"label": "新消息", "behavior": "_holo_mail", "desc": "全息屏显示系统级通知与新邮件待办"},
		{"label": "桌面监控", "behavior": "_holo_desktop", "desc": "实时捕捉桌面画面投射到全息屏"},
		{"label": "终端引导", "behavior": "_holo_loading", "desc": "全息屏显示系统初始化引导序列"},
		{"label": "待机屏保", "behavior": "_holo_browse", "desc": "弹出全息屏待机屏保"}
	]

	for item in items:
		var btn = CyberMenuButton.new()

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

	ctx._submenu.register_l3_panel("holo_terminal", panel, "sec_pet")

func _on_terminal_action(behavior: String) -> void:
	ctx.close_menu_instant()

	# 深夜模式拒绝执行
	var pet = _get_pet()
	if pet and "nighttime_mode" in pet and pet.nighttime_mode:
		pet.show_local_bubble("休眠周期中。指令已搁置。")
		return

	if pet and not pet.gaming.active:
		var s: float = -1.0 if pet.global_position.x > pet.boundary_size.x * 0.5 else 1.0
		_dispatch_terminal(pet, behavior, s)

# ── 终端行为分发表 (数据驱动, 新增模式只加一行) ──
const _TERMINAL_ACTIONS := {
	"_holo_browse":  {"method": "show_idle",    "duration": 10.0},
	"_holo_loading": {"method": "show_loading", "duration": 10.0, "arg": "初始化"},
	"_holo_battery": {"method": "show_battery", "duration": 10.0},
	"_holo_done":    {"method": "show_done",    "duration": 10.0},
	"_holo_error":   {"method": "show_error",   "duration": 10.0},
	"_holo_warning": {"method": "show_warning", "duration": 10.0},
	"_holo_query":   {"method": "show_query",   "duration": 10.0},
	"_holo_alarm":   {"method": "show_alarm",   "duration": 10.0},
	"_holo_cleanup": {"method": "show_cleanup", "duration": 10.0},
	"_holo_recycle": {"method": "show_recycle", "duration": 10.0},
	"_holo_globe":   {"method": "show_globe",   "duration": 10.0},
	"_holo_sync":    {"method": "show_sync",    "duration": 10.0},
	"_holo_lock":    {"method": "show_lock",    "duration": 10.0},
	"_holo_mail":    {"method": "show_mail",    "duration": 10.0},
	"_holo_desktop": {"method": "show_desktop", "duration": 0.0},
}

func _dispatch_terminal(pet, behavior: String, s: float) -> void:
	if behavior not in _TERMINAL_ACTIONS:
		return
	var cfg = _TERMINAL_ACTIONS[behavior]
	var method: String = cfg["method"]
	var dur: float = cfg.get("duration", 0.0)
	if pet.has_method("show_holo_action"):
		pet.show_holo_action(method, s, dur, cfg.get("arg", null))

# ── 指令序列 ──

func _build_debug_behavior_submenu() -> void:
	var panel = ctx.make_submenu_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var debug_items := [
		{"label": "眼睑下垂", "behavior": "drowsy", "desc": "模拟困倦半闭眼效果"},
		{"label": "待机休眠 · 挡板", "behavior": "hibernate:0", "desc": "手动触发待机休眠 (机械挡板半闭眼)"},
		{"label": "待机休眠 · 旋转器", "behavior": "hibernate:1", "desc": "手动触发待机休眠 (加载旋转器风格)"},
		{"label": "碎碎念", "behavior": "_chatter", "desc": "立即触发一次碎碎念气泡"},
		{"label": "待办提醒", "behavior": "_todo_prompt", "desc": "强制触发一次待办主动提醒"},
		{"label": "空间跳跃", "behavior": "_free_roam", "desc": "触发一次空间跳跃踏板序列"},
	]

	for item in debug_items:
		var btn = CyberMenuButton.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.2, 0.85, 1.0, 1))
		btn.text = item.label
		var behavior = item.behavior
		btn.pressed.connect(func(): _on_debug_behavior_pressed(behavior))
		if item.has("desc"):
			var desc_text = item.desc
			var b = btn
			btn.mouse_entered.connect(func(): ctx._tooltip.show_for(b, desc_text, true))
			btn.mouse_exited.connect(func(): ctx._tooltip.show_for(b, desc_text, false))
		vbox.add_child(btn)

	# ── 分隔线 ──
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.8, 1.0, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# ── 深夜模式开关 ──
	_nighttime_btn = CyberMenuButton.new()
	_nighttime_btn.flat = true
	_nighttime_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_nighttime_btn.add_theme_font_size_override("font_size", 19)
	_nighttime_btn.add_theme_color_override("font_color", Color(0.7, 0.75, 1.0, 1))
	_nighttime_btn.add_theme_color_override("font_hover_color", Color(0.5, 0.55, 1.0, 1))
	var pet = _get_pet()
	var is_night = pet and pet.nighttime_mode
	_nighttime_btn.text = "深夜模式 [●]" if is_night else "深夜模式 [○]"
	_nighttime_btn.pressed.connect(func(): _on_nighttime_toggle(_nighttime_btn))
	var night_desc = "手动开关深夜模式 (归位+半闭眼休眠)"
	_nighttime_btn.mouse_entered.connect(func(): ctx._tooltip.show_for(_nighttime_btn, night_desc, true))
	_nighttime_btn.mouse_exited.connect(func(): ctx._tooltip.show_for(_nighttime_btn, night_desc, false))
	vbox.add_child(_nighttime_btn)

	# ── 解除当前行为 ──
	var cancel_btn = CyberMenuButton.new()
	cancel_btn.flat = true
	cancel_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cancel_btn.add_theme_font_size_override("font_size", 19)
	cancel_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5, 0.8))
	cancel_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.4, 0.3, 1))
	cancel_btn.text = "解除当前行为"
	cancel_btn.pressed.connect(func(): _on_cancel_behavior())
	var cancel_desc = "取消休眠/深夜模式等活跃行为，恢复正常"
	cancel_btn.mouse_entered.connect(func(): ctx._tooltip.show_for(cancel_btn, cancel_desc, true))
	cancel_btn.mouse_exited.connect(func(): ctx._tooltip.show_for(cancel_btn, cancel_desc, false))
	vbox.add_child(cancel_btn)

	ctx._submenu.register_l3_panel("debug_behavior", panel, "sec_pet")

func _on_debug_behavior_pressed(behavior: String) -> void:
	ctx.close_menu_instant()

	var main_node = ctx.get_tree().root.get_node_or_null("Main")

	if behavior == "_chatter":
		if main_node:
			for child in main_node.get_children():
				if child.has_method("_trigger_chatter"):
					child._trigger_chatter()
					return
		EventBus.show_reminder_bubble.emit("碎碎念系统未就绪。")
	elif behavior == "_free_roam":
		EventBus.trigger_free_roam.emit()
	elif behavior == "_todo_prompt":
		EventBus.trigger_todo_prompt.emit()
	else:
		EventBus.trigger_idle_behavior.emit(behavior)

# ── 深夜模式手动开关 ──

func _on_nighttime_toggle(btn: Button) -> void:
	ctx.close_menu_instant()

	var pet = _get_pet()
	if not pet:
		return
	var new_state = not pet.nighttime_mode
	if pet.has_method("set_manual_nighttime_mode"):
		pet.set_manual_nighttime_mode(new_state)
	btn.text = "深夜模式 [●]" if new_state else "深夜模式 [○]"

# ── 解除当前行为 (一键恢复正常) ──

func _on_cancel_behavior() -> void:
	ctx.close_menu_instant()

	var pet = _get_pet()
	if not pet:
		return
	if pet.has_method("cancel_active_behavior"):
		pet.cancel_active_behavior()
	if _nighttime_btn:
		_nighttime_btn.text = "深夜模式 [○]"
	pet.show_local_bubble("...系统重置。恢复常规运行。")

func refresh_debug_submenu() -> void:
	if _nighttime_btn:
		var pet = _get_pet()
		var is_night = pet and pet.nighttime_mode
		_nighttime_btn.text = "深夜模式 [●]" if is_night else "深夜模式 [○]"

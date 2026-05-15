# sec_behavior.gd — 行为分区 (构建 + 回调 + debug 子菜单)
extends RefCounted

const _CyberMenuBtn = preload("res://ui/context_menu/cyber_menu_button.gd")

var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _window_mode_btn: Button
var _behavior_mode_btn: Button
var _gait_btn: Button
var _mode_btn: Button

# ── 常量 ──
const WINDOW_MODE_LABELS := ["窗口 · 自由漫游 [+]", "窗口 · 窗口封闭 [+]", "窗口 · 窗口排斥 [+]"]
const BEHAVIOR_MODE_LABELS := ["指令 · 自由行动 [+]", "指令 · 安静待命 [+]"]
const GAIT_LABELS := ["步态 · 蹦跳为主 [+]", "步态 · 滚动为主 [+]", "步态 · 混合平衡 [+]"]

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_window_mode_btn = ctx._make_menu_btn("窗口 · 自由漫游 [+]", Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_window_mode_btn)
	ctx._bind_l3_trigger(_window_mode_btn, "window_mode", "sec_behavior")

	_behavior_mode_btn = ctx._make_menu_btn("指令 · 自由行动 [+]", Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_behavior_mode_btn)
	ctx._bind_l3_trigger(_behavior_mode_btn, "behavior_mode", "sec_behavior")

	_gait_btn = ctx._make_menu_btn("步态 · 蹦跳为主 [+]", Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_gait_btn)
	ctx._bind_l3_trigger(_gait_btn, "gait", "sec_behavior")

	_mode_btn = ctx._make_menu_btn("模式 [+]", Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_mode_btn)
	ctx._bind_l3_trigger(_mode_btn, "mode", "sec_behavior")

	panel.mouse_entered.connect(func(): ctx._submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.panels["sec_behavior"] = panel

	# L3 子菜单
	ctx._submenu.create_radio("window_mode", [
		{"value": 0, "label": "自由漫游"},
		{"value": 1, "label": "窗口封闭"},
		{"value": 2, "label": "窗口排斥"},
	], _on_radio_window_mode, 3)
	ctx._submenu._l3_parent_map["window_mode"] = "sec_behavior"

	ctx._submenu.create_radio("behavior_mode", [
		{"value": 0, "label": "自由行动"},
		{"value": 1, "label": "安静待命"},
	], _on_radio_behavior_mode, 3)
	ctx._submenu._l3_parent_map["behavior_mode"] = "sec_behavior"

	ctx._submenu.create_radio("gait", [
		{"value": 0, "label": "蹦跳为主"},
		{"value": 1, "label": "滚动为主"},
		{"value": 2, "label": "混合平衡"},
	], _on_radio_gait, 3)
	ctx._submenu._l3_parent_map["gait"] = "sec_behavior"

	ctx._submenu.create_toggle("mode", [
		{"id": "eye_track", "on": "指针跟踪 [●]", "off": "指针跟踪 [○]", "key": "eye_track", "default": true},
		{"id": "anti_gravity", "on": "反重力 [●]", "off": "反重力 [○]", "key": "anti_gravity", "default": false},
		{"id": "free_roam", "on": "空间跳跃 [●]", "off": "空间跳跃 [○]", "key": "free_roam", "default": false},
		{"id": "screen_wrap", "on": "屏幕穿越 [●]", "off": "屏幕穿越 [○]", "key": "screen_wrap", "default": false},
	], 3)
	ctx._submenu._l3_parent_map["mode"] = "sec_behavior"
	# 模式子菜单追加踏板外观胶囊
	_append_platform_style_capsule()

	# L3: 指令序列
	_build_debug_behavior_submenu()

# ── 窗口模式 ──

func _on_radio_window_mode(value: int) -> void:
	update_window_mode_label(value)
	EventBus.window_mode_changed.emit(value)
	ctx._submenu.refresh_radio("window_mode", value)

func update_window_mode_label(mode: int) -> void:
	_window_mode_btn.text = WINDOW_MODE_LABELS[mode]

# ── 行为指令 ──

func _on_radio_behavior_mode(value: int) -> void:
	update_behavior_mode_label(value)
	EventBus.behavior_mode_changed.emit(value)
	ctx._submenu.refresh_radio("behavior_mode", value)

func update_behavior_mode_label(mode: int) -> void:
	_behavior_mode_btn.text = BEHAVIOR_MODE_LABELS[mode]

func on_behavior_mode_synced(mode: int) -> void:
	update_behavior_mode_label(mode)
	ctx._submenu.refresh_radio("behavior_mode", mode)

# ── 步态 ──

func _on_radio_gait(value: int) -> void:
	update_gait_label(value)
	SettingsManager.set_int("move_style", value)
	EventBus.setting_toggled.emit("move_style", value > 0)
	ctx._submenu.refresh_radio("gait", value)

func update_gait_label(mode: int) -> void:
	_gait_btn.text = GAIT_LABELS[mode]

# ── 踏板外观胶囊 ──

func _append_platform_style_capsule() -> void:
	var mode_panel = ctx._submenu.l3_panels.get("mode")
	if not mode_panel: return
	var vbox = mode_panel.get_child(0) as VBoxContainer
	if not vbox: return

	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.8, 1.0, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	var btn = _CyberMenuBtn.new()
	btn.text = "踏板外观"
	btn.add_theme_font_size_override("font_size", 17)
	ctx._apply_capsule_style(btn,
		Color(0.08, 0.15, 0.3, 0.5),
		Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.35))
	btn.pressed.connect(func():
		ctx._close_and_emit(EventBus.show_platform_style_panel)
	)
	vbox.add_child(btn)

# ── 指令序列 (行为子菜单) ──

func _build_debug_behavior_submenu() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var debug_items := [
		{"label": "眼睑下垂", "behavior": "drowsy", "desc": "模拟困倦半闭眼效果"},
		{"label": "碎碎念", "behavior": "_chatter", "desc": "立即触发一次碎碎念气泡"},
		{"label": "待办提醒", "behavior": "_todo_prompt", "desc": "强制触发一次待办主动提醒"},
		{"label": "空间跳跃", "behavior": "_free_roam", "desc": "触发一次空间跳跃踏板序列"},
		{"label": "自动对弈", "behavior": "_auto_game_2048", "desc": "宠物自己玩一局 2048"},
		{"label": "自动扫雷", "behavior": "_auto_game_mine", "desc": "宠物自己玩一局扫雷"},
		{"label": "自动导航", "behavior": "_auto_game_snake", "desc": "宠物自己玩一局贪吃蛇"},
		{"label": "自动堆叠", "behavior": "_auto_game_tetris", "desc": "宠物自己玩一局俄罗斯方块"},
	]

	for item in debug_items:
		var btn = _CyberMenuBtn.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.2, 1))
		btn.text = item.label
		var behavior = item.behavior
		btn.pressed.connect(func(): _on_debug_behavior_pressed(behavior))
		if item.has("desc"):
			var desc_text = item.desc
			var b = btn
			btn.mouse_entered.connect(func(): ctx._tooltip.show_for(b, desc_text, true))
			btn.mouse_exited.connect(func(): ctx._tooltip.show_for(b, desc_text, false))
		vbox.add_child(btn)

	panel.mouse_entered.connect(func(): ctx._submenu.on_l3_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_l3_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.l3_panels["debug_behavior"] = panel
	ctx._submenu._l3_parent_map["debug_behavior"] = "sec_system"

func _on_debug_behavior_pressed(behavior: String) -> void:
	ctx._tooltip.panel.hide()
	ctx._submenu.hide_all_instant()
	ctx.hud.hide()
	ctx._sidebar.panel.hide()
	ctx.target = null
	EventBus.context_menu_toggled.emit(false)

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
	elif behavior == "_auto_game_2048":
		EventBus.launch_game_auto.emit("2048")
	elif behavior == "_auto_game_mine":
		EventBus.launch_game_auto.emit("minesweeper")
	elif behavior == "_auto_game_snake":
		EventBus.launch_game_auto.emit("snake")
	elif behavior == "_auto_game_tetris":
		EventBus.launch_game_auto.emit("tetris")
	else:
		EventBus.trigger_idle_behavior.emit(behavior)

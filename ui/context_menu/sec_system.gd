# sec_system.gd — 系统分区 (构建 + 回调)
extends RefCounted

var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _sysinfo_btn: Button
var _autostart_btn: Button
var _debug_behavior_btn: Button

# ── 自启动延迟检查 ──
var _autostart_check_pending := false
var _autostart_check_delay := 0.0

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_sysinfo_btn = ctx._make_menu_btn("系统信息", Color(0.8, 0.55, 0.55, 1))
	_sysinfo_btn.pressed.connect(_on_sysinfo_btn_pressed)
	vbox.add_child(_sysinfo_btn)

	_autostart_btn = ctx._make_menu_btn("开机自启动 [○]", Color(0.8, 0.55, 0.55, 1))
	_autostart_btn.pressed.connect(_on_autostart_btn_pressed)
	vbox.add_child(_autostart_btn)

	_debug_behavior_btn = ctx._make_menu_btn("指令序列 [+]", Color(1.0, 0.7, 0.2, 1))
	vbox.add_child(_debug_behavior_btn)
	ctx._bind_l3_trigger(_debug_behavior_btn, "debug_behavior", "sec_system")

	panel.mouse_entered.connect(func(): ctx._submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.panels["sec_system"] = panel

# ── 系统信息 ──

func _on_sysinfo_btn_pressed() -> void:
	ctx._close_hud()
	ctx._sysinfo_bubble.trigger()

# ── 自启动 ──

func _on_autostart_btn_pressed() -> void:
	var win_mgr = ctx._get_win_manager()
	if not win_mgr or not win_mgr.has_method("SetAutoStart"):
		return
	var current: bool = win_mgr.call("IsAutoStartEnabled")
	var new_val = not current
	win_mgr.call("SetAutoStart", new_val)
	ctx._set_toggle(_autostart_btn, new_val, "开机自启动 [●]", "开机自启动 [○]")

func schedule_autostart_check() -> void:
	_autostart_check_pending = true
	_autostart_check_delay = 0.0

func check_autostart_deferred(delta: float) -> void:
	if not _autostart_check_pending:
		return
	_autostart_check_delay += delta
	if _autostart_check_delay < 0.5:
		return
	_autostart_check_pending = false
	var win_mgr = ctx._get_win_manager()
	if win_mgr and win_mgr.has_method("IsAutoStartEnabled"):
		var on: bool = win_mgr.call("IsAutoStartEnabled")
		ctx._set_toggle(_autostart_btn, on, "开机自启动 [●]", "开机自启动 [○]")
	else:
		_autostart_btn.text = "开机自启动 [○]"

# ── 退出 ──

func on_quit_pressed() -> void:
	ctx._tooltip.panel.hide()
	if is_instance_valid(ctx.target):
		ctx.hud.pivot_offset = ctx.target.get_global_transform_with_canvas().get_origin() - ctx.hud.position

	var tween = ctx.create_tween().set_parallel(true)
	tween.tween_property(ctx.hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(ctx.hud, "modulate:a", 0.0, 0.15)
	if ctx._menu_side == 1:
		ctx._sidebar.panel.pivot_offset = Vector2(ctx._sidebar.panel.size.x, ctx._sidebar.panel.size.y * 0.5)
	else:
		ctx._sidebar.panel.pivot_offset = Vector2(0, ctx._sidebar.panel.size.y * 0.5)
	tween.tween_property(ctx._sidebar.panel, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(ctx._sidebar.panel, "modulate:a", 0.0, 0.15)

	tween.finished.connect(func():
		ctx.hud.hide()
		ctx._sidebar.panel.hide()
		EventBus.context_menu_toggled.emit(false)
	)
	ctx.target = null

	var main_node = ctx.get_tree().root.get_node_or_null("Main")
	if main_node and main_node.has_method("quit_with_farewell"):
		main_node.quit_with_farewell()
	else:
		ctx.get_tree().quit()

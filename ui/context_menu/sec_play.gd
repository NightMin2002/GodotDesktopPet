# sec_play.gd — 玩法分区 (构建 + 回调 + 游戏列表 + 自娱指令)
extends RefCounted

const _CyberMenuBtn = preload("res://ui/context_menu/cyber_menu_button.gd")

var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _entertain_btn: Button
var _auto_play_btn: Button
var _game_container: VBoxContainer

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# 游戏终端入口
	var terminal_btn = ctx._make_menu_btn("游戏终端", Color(0.3, 1.0, 0.7, 1))
	vbox.add_child(terminal_btn)
	terminal_btn.pressed.connect(func():
		ctx._close_hud()
		EventBus.show_game_terminal.emit()
	)
	var tb = terminal_btn
	terminal_btn.mouse_entered.connect(func(): ctx._tooltip.show_for(tb, "独立游戏运行终端", true))
	terminal_btn.mouse_exited.connect(func(): ctx._tooltip.show_for(tb, "独立游戏运行终端", false))

	_entertain_btn = ctx._make_menu_btn("娱乐 [+]", Color(0.3, 1.0, 0.7, 1))
	vbox.add_child(_entertain_btn)
	ctx._bind_l3_trigger(_entertain_btn, "entertain", "sec_play")

	_auto_play_btn = ctx._make_menu_btn("自娱指令 [+]", Color(0.3, 1.0, 0.7, 1))
	vbox.add_child(_auto_play_btn)
	ctx._bind_l3_trigger(_auto_play_btn, "auto_play", "sec_play")

	# 小游戏入口容器 (菜单打开时动态填充)
	_game_container = VBoxContainer.new()
	_game_container.add_theme_constant_override("separation", 6)
	vbox.add_child(_game_container)

	panel.mouse_entered.connect(func(): ctx._submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.panels["sec_play"] = panel

	# L3: 娱乐
	ctx._submenu.create_toggle("entertain", [
		{"id": "stroll", "on": "自主巡航 [●]", "off": "自主巡航 [○]", "key": "stroll", "default": true},
	], 3)
	ctx._submenu._l3_parent_map["entertain"] = "sec_play"

	# L3: 自娱指令
	_build_auto_play_submenu()

# ── 自娱指令 ──

func _build_auto_play_submenu() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var auto_items := [
		{"label": "自动对弈", "game_id": "2048", "desc": "让宠物自己玩一局 2048"},
		{"label": "自动扫雷", "game_id": "minesweeper", "desc": "让宠物自己玩一局扫雷"},
		{"label": "自动导航", "game_id": "snake", "desc": "让宠物自己玩一局贪吃蛇"},
		{"label": "自动堆叠", "game_id": "tetris", "desc": "让宠物自己玩一局俄罗斯方块"},
	]

	for item in auto_items:
		var btn = _CyberMenuBtn.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.3, 1.0, 0.7, 1))
		btn.text = item.label
		var gid = item.game_id
		btn.pressed.connect(func(): _on_auto_play_pressed(gid))
		if item.has("desc"):
			var desc_text = item.desc
			var b = btn
			btn.mouse_entered.connect(func(): ctx._tooltip.show_for(b, desc_text, true))
			btn.mouse_exited.connect(func(): ctx._tooltip.show_for(b, desc_text, false))
		vbox.add_child(btn)

	panel.mouse_entered.connect(func(): ctx._submenu.on_l3_panel_enter())
	panel.mouse_exited.connect(func(): ctx._submenu.on_l3_panel_exit())
	ctx.add_child(panel)
	ctx._submenu.l3_panels["auto_play"] = panel
	ctx._submenu._l3_parent_map["auto_play"] = "sec_play"

func _on_auto_play_pressed(game_id: String) -> void:
	ctx._tooltip.panel.hide()
	ctx._submenu.hide_all_instant()
	ctx.hud.hide()
	ctx._sidebar.panel.hide()
	ctx.target = null
	EventBus.context_menu_toggled.emit(false)
	EventBus.launch_game_auto.emit(game_id)

# ── 游戏列表 ──

func update_game_list() -> void:
	if not _game_container:
		return
	# 清空旧内容
	for child in _game_container.get_children():
		child.queue_free()

	var main_node = ctx.get_tree().root.get_node_or_null("Main")
	if not main_node or not ("game_mgr" in main_node) or not main_node.game_mgr:
		return
	var games: Array = main_node.game_mgr.get_installed_games()
	if games.size() == 0:
		return

	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 3)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.3, 0.85, 0.55, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_container.add_child(sep)

	var label = Label.new()
	label.text = "小游戏"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.4, 0.65, 0.5, 0.5))
	_game_container.add_child(label)

	for game_meta in games:
		var gid: String = game_meta.get("id", "")
		var gname: String = game_meta.get("name", gid)
		var gdesc: String = game_meta.get("desc", "")
		var btn = ctx._make_menu_btn(gname, Color(0.3, 1.0, 0.7, 1))
		btn.pressed.connect(func():
			ctx._close_hud()
			EventBus.launch_game.emit(gid)
		)
		if gdesc != "":
			var b = btn
			var desc_text = gdesc
			btn.mouse_entered.connect(func(): ctx._tooltip.show_for(b, desc_text, true))
			btn.mouse_exited.connect(func(): ctx._tooltip.show_for(b, desc_text, false))
		_game_container.add_child(btn)


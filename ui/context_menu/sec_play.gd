# sec_play.gd — 玩法分区 (构建 + 回调 + 游戏列表)
extends RefCounted

var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _entertain_btn: Button
var _activity_btn: Button
var _game_container: VBoxContainer

# ── 常量 ──
const ACTIVITY_LABELS := ["自主活动 · 已关闭 [+]", "自主活动 · 偶尔 [+]", "自主活动 · 频繁 [+]"]

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_entertain_btn = ctx._make_menu_btn("娱乐 [+]", Color(0.3, 1.0, 0.7, 1))
	vbox.add_child(_entertain_btn)
	ctx._bind_l3_trigger(_entertain_btn, "entertain", "sec_play")

	_activity_btn = ctx._make_menu_btn("自主活动 · 偶尔 [+]", Color(0.3, 1.0, 0.7, 1))
	vbox.add_child(_activity_btn)
	ctx._bind_l3_trigger(_activity_btn, "auto_activity", "sec_play")

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

	# L3: 自主活动单选
	ctx._submenu.create_radio("auto_activity", [
		{"value": 0, "label": "关闭", "desc": "不会自己玩游戏或跳跃"},
		{"value": 1, "label": "偶尔", "desc": "隔很久才自己动一下"},
		{"value": 2, "label": "频繁", "desc": "经常自己找事做"},
	], _on_radio_auto_activity, 3)
	ctx._submenu._l3_parent_map["auto_activity"] = "sec_play"

# ── 自主活动 ──

func _on_radio_auto_activity(value: int) -> void:
	update_activity_label(value)
	SettingsManager.set_int("auto_activity", value)
	EventBus.setting_toggled.emit("auto_activity", value > 0)
	ctx._submenu.refresh_radio("auto_activity", value)

func update_activity_label(mode: int) -> void:
	_activity_btn.text = ACTIVITY_LABELS[mode]

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
		btn.tooltip_text = gdesc
		_game_container.add_child(btn)

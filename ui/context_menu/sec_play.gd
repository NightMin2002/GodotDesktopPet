# sec_play.gd — 玩法分区 (构建 + 回调 + 游戏列表 + 自娱指令)
extends RefCounted



var ctx  # ContextMenu 引用

# ── 按钮引用 ──
var _stack_btn: Button
var _auto_play_btn: Button
var _game_container: VBoxContainer

# ── 叠高高状态 ──
var _stacking: bool = false

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_stack_btn = ctx._make_menu_btn("叠高高", Color(0.3, 1.0, 0.7, 1))
	_stack_btn.pressed.connect(_on_stack_pressed)
	vbox.add_child(_stack_btn)

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

	# L3: 自娱指令
	_build_auto_play_submenu()

# ── 叠高高 ──

const _STACK_REJECT := [
	"...就我一个，叠什么。",
	"编队为零。物理学拒绝了你的请求。",
	"操作对象不足。需要至少一个分身。",
	"没有可用单元。先部署分身。",
]

func _on_stack_pressed() -> void:
	ctx._tooltip.panel.hide()
	ctx._submenu.hide_all_instant()
	ctx.hud.hide()
	ctx._sidebar.panel.hide()
	ctx.target = null
	EventBus.context_menu_toggled.emit(false)

	var main = ctx.get_tree().root.get_node_or_null("Main")
	if not main:
		return
	var pets: Array = main.pet_instances
	var clones := []
	for p in pets:
		if is_instance_valid(p) and p.is_clone:
			clones.append(p)

	if clones.is_empty():
		EventBus.force_show_bubble.emit(_STACK_REJECT[randi() % _STACK_REJECT.size()])
		return

	if _stacking:
		_unstack(main, clones)
	else:
		_do_stack(main, clones)

func _do_stack(main: Node, clones: Array) -> void:
	_stacking = true
	var origin_pet = main.pet_instances[0]

	# 按克隆体索引排序保证一致性
	clones.sort_custom(func(a, b): return a.get_meta("pet_index", 0) < b.get_meta("pet_index", 0))

	var diameter = origin_pet.PET_RADIUS * 2.0
	for i in range(clones.size()):
		var clone = clones[i]
		# 把克隆体挪到原体头上
		var stack_height = (i + 1) * diameter * origin_pet.ag_flip * -1.0
		clone.set_meta("stack_offset_y", stack_height)
		clone.set_meta("stack_origin", origin_pet)
		# 保存原始碰撞配置, 然后关闭碰撞 (避免压住原体)
		clone.set_meta("stack_col_layer", clone.collision_layer)
		clone.set_meta("stack_col_mask", clone.collision_mask)
		clone.collision_layer = 0
		clone.collision_mask = 0
		clone.freeze = true
		clone.global_position = Vector2(origin_pet.global_position.x, origin_pet.global_position.y + stack_height)
		# 连接 process 跟随
		if not clone.has_meta("stack_callable"):
			var c = clone
			var callable = func():
				if not is_instance_valid(c) or not c.freeze:
					return
				var base = c.get_meta("stack_origin", null)
				if not is_instance_valid(base):
					return
				var off_y: float = c.get_meta("stack_offset_y", 0.0)
				c.global_position = Vector2(base.global_position.x, base.global_position.y + off_y)
			c.set_meta("stack_callable", callable)
			origin_pet.get_tree().process_frame.connect(callable)

	var lines := [
		"...稳住。别乱动。",
		"编队堆叠完毕。重心需自行维持。",
		"塔基是我。动一下试试。",
	]
	EventBus.force_show_bubble.emit(lines[randi() % lines.size()])

func _unstack(main: Node, clones: Array) -> void:
	_stacking = false
	var origin_pet = main.pet_instances[0]

	for clone in clones:
		# 恢复碰撞
		clone.collision_layer = clone.get_meta("stack_col_layer", 1)
		clone.collision_mask = clone.get_meta("stack_col_mask", 1)
		clone.remove_meta("stack_col_layer")
		clone.remove_meta("stack_col_mask")
		clone.freeze = false
		# 断开跟随
		if clone.has_meta("stack_callable"):
			var callable = clone.get_meta("stack_callable")
			if origin_pet.get_tree().process_frame.is_connected(callable):
				origin_pet.get_tree().process_frame.disconnect(callable)
			clone.remove_meta("stack_callable")
		clone.remove_meta("stack_offset_y")
		clone.remove_meta("stack_origin")
		# 给个小推力让它们散开
		clone.apply_central_impulse(Vector2(randf_range(-100, 100), -150))

	EventBus.force_show_bubble.emit("解散。各回各位。")

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
		var btn = CyberMenuButton.new()
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

	ctx._submenu.register_l3_panel("auto_play", panel, "sec_play")

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


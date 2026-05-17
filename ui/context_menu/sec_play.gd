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

	_stack_btn = ctx._make_menu_btn("叠高高 [+]", Color(0.3, 1.0, 0.7, 1))
	vbox.add_child(_stack_btn)
	ctx._bind_l3_trigger(_stack_btn, "stacking", "sec_play")

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

	# L3: 叠高高
	_build_stacking_submenu()

	# L3: 自娱指令
	_build_auto_play_submenu()

# ── 叠高高 ──

const _STACK_REJECT := [
	"...就我一个，叠什么。",
	"编队为零。物理学拒绝了你的请求。",
	"操作对象不足。需要至少一个分身。",
	"没有可用单元。先部署分身。",
]

const _STACK_LINES := [
	"...稳住。别乱动。",
	"编队堆叠完毕。重心需自行维持。",
	"塔基是我。动一下试试。",
	"结构锁定。数据塔已上线。",
]

func _build_stacking_submenu() -> void:
	var panel = ctx._submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var items := [
		{"label": "单塔", "towers": 1, "desc": "全部叠成一塔 (至少 1 个分身)"},
		{"label": "双塔", "towers": 2, "desc": "分成两组各叠一塔 (至少 3 个分身)"},
		{"label": "三塔", "towers": 3, "desc": "分成三组各叠一塔 (至少 5 个分身)"},
		{"label": "解散", "towers": 0, "desc": "解除叠高高"},
	]

	for item in items:
		var btn = CyberMenuButton.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.3, 1.0, 0.7, 1))
		btn.text = item.label
		var n = item.towers
		btn.pressed.connect(func(): _on_stack_mode(n))
		if item.has("desc"):
			var desc_text = item.desc
			var b = btn
			btn.mouse_entered.connect(func(): ctx._tooltip.show_for(b, desc_text, true))
			btn.mouse_exited.connect(func(): ctx._tooltip.show_for(b, desc_text, false))
		vbox.add_child(btn)

	ctx._submenu.register_l3_panel("stacking", panel, "sec_play")

func _close_menu() -> void:
	ctx._tooltip.panel.hide()
	ctx._submenu.hide_all_instant()
	ctx.hud.hide()
	ctx._sidebar.panel.hide()
	ctx.target = null
	EventBus.context_menu_toggled.emit(false)

func _get_all_pets() -> Array:
	var main = ctx.get_tree().root.get_node_or_null("Main")
	if not main:
		return []
	var result := []
	for p in main.pet_instances:
		if is_instance_valid(p):
			result.append(p)
	return result

func _on_stack_mode(tower_count: int) -> void:
	_close_menu()

	var all_pets = _get_all_pets()
	if all_pets.size() < 2:
		EventBus.force_show_bubble.emit(_STACK_REJECT[randi() % _STACK_REJECT.size()])
		return

	# 解散
	if tower_count == 0:
		_unstack_all(all_pets, false)
		return

	# 检查人数: N 塔至少需要 N*2 个宠物
	if all_pets.size() < tower_count * 2:
		EventBus.force_show_bubble.emit("编队不足。" + str(tower_count) + " 塔至少需要 " + str(tower_count * 2) + " 个单元。")
		return

	# 先解散已有的叠加
	_unstack_all(all_pets, true)

	# 按塔数均分宠物 (轮询分配)
	var towers: Array = []
	for i in range(tower_count):
		towers.append([])
	for i in range(all_pets.size()):
		towers[i % tower_count].append(all_pets[i])

	# 叠起来: 每组第一个是塔基(自由活动), 其余冻结跟随
	# 按组交错, 同组按层级递增延迟, 视觉上一个个飞上去
	var anim_idx := 0
	for group in towers:
		if group.size() < 2:
			continue
		var base = group[0]
		for j in range(1, group.size()):
			_freeze_on_base(base, group[j], j, anim_idx * 0.3)
			anim_idx += 1

	_stacking = true
	EventBus.force_show_bubble.emit(_STACK_LINES[randi() % _STACK_LINES.size()])

## 把一个宠物冻结到塔基头上 (弹跳动画)
func _freeze_on_base(base, pet, layer_index: int, delay: float = 0.0) -> void:
	var diameter = base.PET_RADIUS * 2.0
	var offset_y = layer_index * diameter * base.ag_flip * -1.0

	pet.set_meta("stack_offset_y", offset_y)
	pet.set_meta("stack_origin", base)
	pet.set_meta("stack_col_layer", pet.collision_layer)
	pet.set_meta("stack_col_mask", pet.collision_mask)
	pet.collision_layer = 0
	pet.collision_mask = 0
	pet.freeze = true

	var start_pos = pet.global_position
	var c = pet
	var b = base
	# 弧线最高点: 比目标位置更高, 模拟跳跃抛物线的顶点
	var overshoot = (60.0 + layer_index * 30.0) * base.ag_flip * -1.0

	var tween = base.get_tree().create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	if delay > 0.0:
		tween.tween_interval(delay)

	# 第一段: 弹射到目标上方 (起跳 + 飞行)
	tween.tween_method(func(t: float):
		if not is_instance_valid(c) or not is_instance_valid(b): return
		var target = Vector2(b.global_position.x, b.global_position.y + offset_y + overshoot)
		c.global_position = start_pos.lerp(target, t)
	, 0.0, 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 第二段: 从上方下落到精确位置 (落地弹跳感)
	tween.tween_method(func(t: float):
		if not is_instance_valid(c) or not is_instance_valid(b): return
		var above = Vector2(b.global_position.x, b.global_position.y + offset_y + overshoot)
		var target = Vector2(b.global_position.x, b.global_position.y + offset_y)
		c.global_position = above.lerp(target, t)
	, 0.0, 1.0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	# 落位后挂载跟随
	tween.tween_callback(func():
		if not is_instance_valid(c): return
		_attach_follow(c, b)
	)

## 挂载 process_frame 跟随 (动画完成后调用)
func _attach_follow(pet, base) -> void:
	if pet.has_meta("stack_callable"):
		return
	var c = pet
	var callable = func():
		if not is_instance_valid(c) or not c.freeze:
			return
		var b = c.get_meta("stack_origin", null)
		if not is_instance_valid(b):
			return
		var off: float = c.get_meta("stack_offset_y", 0.0)
		c.global_position = Vector2(b.global_position.x, b.global_position.y + off)
	c.set_meta("stack_callable", callable)
	base.get_tree().process_frame.connect(callable)

## 解散所有叠加
func _unstack_all(all_pets: Array, silent: bool = false) -> void:
	var tree = ctx.get_tree()
	for pet in all_pets:
		if not pet.has_meta("stack_origin"):
			continue
		# 恢复碰撞
		pet.collision_layer = pet.get_meta("stack_col_layer", 1)
		pet.collision_mask = pet.get_meta("stack_col_mask", 1)
		pet.remove_meta("stack_col_layer")
		pet.remove_meta("stack_col_mask")
		pet.freeze = false
		# 断开跟随
		if pet.has_meta("stack_callable"):
			var callable = pet.get_meta("stack_callable")
			if tree.process_frame.is_connected(callable):
				tree.process_frame.disconnect(callable)
			pet.remove_meta("stack_callable")
		pet.remove_meta("stack_offset_y")
		pet.remove_meta("stack_origin")
		# 散开推力
		pet.apply_central_impulse(Vector2(randf_range(-100, 100), -150))

	if _stacking:
		_stacking = false
		if not silent:
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

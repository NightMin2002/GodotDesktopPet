# toy_stacking.gd — 叠高高玩具模块
# 把克隆体叠到塔基头上, 支持单塔/双塔/三塔模式
extends "res://ui/context_menu/toys/toy_base.gd"

var _stacking: bool = false

# ── 接口实现 ──

func get_label() -> String:
	return "叠高高"

func get_desc() -> String:
	return "把分身叠起来"

func has_submenu() -> bool:
	return true

func build_submenu(vbox: VBoxContainer) -> void:
	var items := [
		{"label": "单塔", "towers": 1, "desc": "全部叠成一塔 (至少 1 个分身)"},
		{"label": "双塔", "towers": 2, "desc": "分成两组各叠一塔 (至少 3 个分身)"},
		{"label": "三塔", "towers": 3, "desc": "分成三组各叠一塔 (至少 5 个分身)"},
		{"label": "解散", "towers": 0, "desc": "解除叠高高"},
	]
	for item in items:
		var n = item.towers
		vbox.add_child(make_btn(item.label, func(): _on_stack_mode(n), item.desc))

func cleanup() -> void:
	_unstack_all(get_all_pets(), true, false)

# ── 话术 ──

const _REJECT := [
	"...就我一个，叠什么。",
	"编队为零。物理学拒绝了你的请求。",
	"操作对象不足。需要至少一个分身。",
	"没有可用单元。先部署分身。",
]

const _STACK := [
	"...稳住。别乱动。",
	"编队堆叠完毕。重心需自行维持。",
	"塔基是我。动一下试试。",
	"结构锁定。数据塔已上线。",
]

# ── 核心逻辑 ──

func _on_stack_mode(tower_count: int) -> void:
	close_menu()

	var all_pets = get_all_pets()
	if all_pets.size() < 2:
		EventBus.force_show_bubble.emit(_REJECT[randi() % _REJECT.size()])
		return

	# 解散
	if tower_count == 0:
		_unstack_all(all_pets, false)
		return

	# 检查人数: N 塔至少需要 N*2 个宠物
	if all_pets.size() < tower_count * 2:
		EventBus.force_show_bubble.emit("编队不足。" + str(tower_count) + " 塔至少需要 " + str(tower_count * 2) + " 个单元。")
		return

	# 先静默解散已有的叠加
	_unstack_all(all_pets, true)

	# 按塔数均分宠物 (轮询分配)
	var towers: Array = []
	for i in range(tower_count):
		towers.append([])
	for i in range(all_pets.size()):
		towers[i % tower_count].append(all_pets[i])

	# 叠起来: 每组第一个是塔基, 其余弹跳上去
	var anim_idx := 0
	for group in towers:
		if group.size() < 2:
			continue
		var base = group[0]
		for j in range(1, group.size()):
			_freeze_on_base(base, group[j], j, anim_idx * 0.3)
			anim_idx += 1

	_stacking = true
	EventBus.force_show_bubble.emit(_STACK[randi() % _STACK.size()])

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
	# 深夜模式: 还没休眠的宠物强制进入半闭眼
	if pet.nighttime_mode and pet.idle_behaviors and pet.idle_behaviors.active_behavior != "hibernate":
		pet.idle_behaviors.hibernate_style = 0
		pet.idle_behaviors.trigger("hibernate")

	var start_pos = pet.global_position
	var c = pet
	var b = base
	var overshoot = (60.0 + layer_index * 30.0) * base.ag_flip * -1.0

	var tween = base.get_tree().create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	if delay > 0.0:
		tween.tween_interval(delay)

	# 第一段: 弹射到目标上方
	tween.tween_method(func(t: float):
		if not is_instance_valid(c) or not is_instance_valid(b): return
		var target = Vector2(b.global_position.x, b.global_position.y + offset_y + overshoot)
		c.global_position = start_pos.lerp(target, t)
	, 0.0, 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 第二段: 落地弹跳
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

## 挂载 process_frame 跟随
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
func _unstack_all(all_pets: Array, silent: bool = false, apply_impulse: bool = true) -> void:
	var tree = ctx.get_tree()
	for pet in all_pets:
		if not pet.has_meta("stack_origin"):
			continue
		pet.collision_layer = pet.get_meta("stack_col_layer", 1)
		pet.collision_mask = pet.get_meta("stack_col_mask", 1)
		pet.remove_meta("stack_col_layer")
		pet.remove_meta("stack_col_mask")
		pet.freeze = false
		if pet.has_meta("stack_callable"):
			var callable = pet.get_meta("stack_callable")
			if tree.process_frame.is_connected(callable):
				tree.process_frame.disconnect(callable)
			pet.remove_meta("stack_callable")
		pet.remove_meta("stack_offset_y")
		pet.remove_meta("stack_origin")
		if apply_impulse:
			pet.apply_central_impulse(Vector2(randf_range(-100, 100), -150))

	if _stacking:
		_stacking = false
		if not silent:
			EventBus.force_show_bubble.emit("解散。各回各位。")

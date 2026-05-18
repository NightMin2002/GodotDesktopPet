# action_shred.gd — [粉碎] 数据销毁操作
# 二次确认提供两种强度: 回收站 (可恢复) / 彻底粉碎 (不可恢复)
# 确认按钮跟随宠物移动, 和 todo_prompt 同风格

# ── 操作接口 ──

func get_action_id() -> String:
	return "shred"

func get_action_label() -> String:
	return "[粉碎] 数据销毁"

func execute(file_drop, paths: PackedStringArray) -> void:
	var pet = file_drop.pet
	if not pet or not is_instance_valid(pet):
		return
	
	# 先显示文件名让用户确认目标
	var name = paths[0].get_file()
	var suffix = " (及另外 %d 项)" % (paths.size() - 1) if paths.size() > 1 else ""
	pet.show_local_bubble("粉碎目标: %s%s" % [name, suffix])
	
	# 等一拍再弹确认
	var tree = pet.get_tree()
	if tree:
		await tree.create_timer(0.5).timeout
	
	pet.show_local_bubble("选择销毁方式。")
	
	_show_confirm(file_drop, paths)

# ══════════════════════════════════════
#  确认面板 (三按钮, 跟随宠物)
# ══════════════════════════════════════

var _confirm_canvas: CanvasLayer = null
var _confirm_btn_cancel: Button = null
var _confirm_btn_recycle: Button = null
var _confirm_btn_shred: Button = null
var _confirm_pet: Node2D = null
var _confirm_file_drop = null

func _show_confirm(file_drop, paths: PackedStringArray) -> void:
	_dismiss_confirm()
	
	var pet = file_drop.pet
	_confirm_pet = pet
	_confirm_file_drop = file_drop
	
	_confirm_canvas = CanvasLayer.new()
	_confirm_canvas.layer = 121
	pet.get_tree().root.add_child(_confirm_canvas)
	
	# [取消] 左侧
	_confirm_btn_cancel = _make_btn("取消", Color(0.55, 0.55, 0.55, 0.85))
	_confirm_btn_cancel.modulate.a = 0.0
	_confirm_btn_cancel.pressed.connect(func():
		pet.show_local_bubble("指令撤销。")
		_dismiss_confirm()
	)
	_confirm_canvas.add_child(_confirm_btn_cancel)
	
	# [回收站] 中间偏右 (安全选项, 绿色)
	_confirm_btn_recycle = _make_btn("回收站", Color(0.2, 0.45, 0.3, 0.9))
	_confirm_btn_recycle.modulate.a = 0.0
	_confirm_btn_recycle.pressed.connect(func():
		_dismiss_confirm()
		_do_recycle(file_drop, paths)
	)
	_confirm_canvas.add_child(_confirm_btn_recycle)
	
	# [彻底粉碎] 右侧 (危险选项, 红色)
	_confirm_btn_shred = _make_btn("彻底粉碎", Color(0.45, 0.12, 0.12, 0.9))
	_confirm_btn_shred.add_theme_color_override("font_color", Color(1.0, 0.65, 0.65))
	_confirm_btn_shred.modulate.a = 0.0
	_confirm_btn_shred.pressed.connect(func():
		_dismiss_confirm()
		_do_shred(file_drop, paths)
	)
	_confirm_canvas.add_child(_confirm_btn_shred)
	
	_update_confirm_positions()
	
	# 淡入
	var tw = _confirm_canvas.create_tween().set_parallel(true)
	tw.tween_property(_confirm_btn_cancel, "modulate:a", 1.0, 0.25)
	tw.tween_property(_confirm_btn_recycle, "modulate:a", 1.0, 0.25).set_delay(0.08)
	tw.tween_property(_confirm_btn_shred, "modulate:a", 1.0, 0.25).set_delay(0.15)
	
	# 注册每帧跟随
	pet.get_tree().process_frame.connect(_update_confirm_positions)

func _update_confirm_positions() -> void:
	if not _confirm_pet or not is_instance_valid(_confirm_pet):
		_dismiss_confirm()
		return
	
	var anchor = _confirm_pet.get_ui_anchor()
	var vp = _confirm_pet.get_viewport().get_visible_rect().size
	var pet_r: float = _confirm_pet.PET_RADIUS
	const BTN_GAP := 10.0
	const MARGIN := 4.0
	
	var btn_y = anchor.center.y - 14.0
	
	# [取消] 左侧
	if _confirm_btn_cancel and is_instance_valid(_confirm_btn_cancel):
		var w = _confirm_btn_cancel.size.x
		var h = _confirm_btn_cancel.size.y
		_confirm_btn_cancel.position = Vector2(
			anchor.center.x - pet_r - BTN_GAP - w,
			btn_y
		)
		_confirm_btn_cancel.position.x = clampf(_confirm_btn_cancel.position.x, MARGIN, maxf(MARGIN, vp.x - w - MARGIN))
		_confirm_btn_cancel.position.y = clampf(_confirm_btn_cancel.position.y, MARGIN, maxf(MARGIN, vp.y - h - MARGIN))
	
	# [回收站] 和 [彻底粉碎] 右侧并排
	var right_x = anchor.center.x + pet_r + BTN_GAP
	
	if _confirm_btn_recycle and is_instance_valid(_confirm_btn_recycle):
		var w = _confirm_btn_recycle.size.x
		var h = _confirm_btn_recycle.size.y
		_confirm_btn_recycle.position = Vector2(right_x, btn_y)
		_confirm_btn_recycle.position.x = clampf(_confirm_btn_recycle.position.x, MARGIN, maxf(MARGIN, vp.x - w - MARGIN))
		_confirm_btn_recycle.position.y = clampf(_confirm_btn_recycle.position.y, MARGIN, maxf(MARGIN, vp.y - h - MARGIN))
		right_x = _confirm_btn_recycle.position.x + w + 6.0
	
	if _confirm_btn_shred and is_instance_valid(_confirm_btn_shred):
		var w = _confirm_btn_shred.size.x
		var h = _confirm_btn_shred.size.y
		_confirm_btn_shred.position = Vector2(right_x, btn_y)
		_confirm_btn_shred.position.x = clampf(_confirm_btn_shred.position.x, MARGIN, maxf(MARGIN, vp.x - w - MARGIN))
		_confirm_btn_shred.position.y = clampf(_confirm_btn_shred.position.y, MARGIN, maxf(MARGIN, vp.y - h - MARGIN))
	
	# DWM 穿透区域
	_update_confirm_hit_rects()

func _update_confirm_hit_rects() -> void:
	if not _confirm_pet or not is_instance_valid(_confirm_pet):
		return
	var rects: Array[Rect2] = []
	for btn in [_confirm_btn_cancel, _confirm_btn_recycle, _confirm_btn_shred]:
		if btn and is_instance_valid(btn):
			rects.append(Rect2(btn.position, btn.size))
	if rects.size() > 0:
		var min_pos = rects[0].position
		var max_end = rects[0].end
		for r in rects:
			min_pos.x = minf(min_pos.x, r.position.x)
			min_pos.y = minf(min_pos.y, r.position.y)
			max_end.x = maxf(max_end.x, r.end.x)
			max_end.y = maxf(max_end.y, r.end.y)
		_confirm_pet.set_overlay_rect("file_drop_confirm", Rect2(min_pos, max_end - min_pos))

func _dismiss_confirm() -> void:
	# 断开帧信号
	if _confirm_pet and is_instance_valid(_confirm_pet):
		if _confirm_pet.get_tree() and _confirm_pet.get_tree().process_frame.is_connected(_update_confirm_positions):
			_confirm_pet.get_tree().process_frame.disconnect(_update_confirm_positions)
		_confirm_pet.remove_overlay_rect("file_drop_confirm")
	
	if _confirm_canvas and is_instance_valid(_confirm_canvas):
		_confirm_canvas.queue_free()
	_confirm_canvas = null
	_confirm_btn_cancel = null
	_confirm_btn_recycle = null
	_confirm_btn_shred = null
	_confirm_pet = null

# ══════════════════════════════════════
#  执行操作
# ══════════════════════════════════════

## 移入回收站
func _do_recycle(file_drop, paths: PackedStringArray) -> void:
	var pet = file_drop.pet
	var ops = file_drop.get_file_ops()
	if ops == null:
		pet.show_local_bubble(file_drop.LINES.no_bridge)
		return
	
	var ok := 0
	var fail := 0
	var err := ""
	for path in paths:
		var r: Dictionary = ops.call("RecycleFile", path)
		if r.get("success", false):
			ok += 1
		else:
			fail += 1
			if err == "": err = r.get("error", "")
	
	if fail == 0:
		pet.show_local_bubble("已移入回收站。可从回收站恢复。")
		_show_holo(pet, "RECYCLE", 2.5)
	else:
		pet.show_local_bubble("回收失败。%s" % err)
		_show_holo(pet, "ERROR", 2.0)

## 彻底粉碎
func _do_shred(file_drop, paths: PackedStringArray) -> void:
	var pet = file_drop.pet
	var ops = file_drop.get_file_ops()
	if ops == null:
		pet.show_local_bubble(file_drop.LINES.no_bridge)
		return
	
	var ok := 0
	var fail := 0
	var err := ""
	for path in paths:
		var r: Dictionary = ops.call("DeleteFilePermanently", path)
		if r.get("success", false):
			ok += 1
		else:
			fail += 1
			if err == "": err = r.get("error", "")
	
	if fail == 0:
		pet.show_local_bubble("数据销毁完毕。本机不保留记录。")
		_show_holo(pet, "CLEANUP", 3.0)
	elif ok > 0:
		pet.show_local_bubble("部分完成。%d 项销毁, %d 项失败。" % [ok, fail])
		_show_holo(pet, "WARNING", 2.5)
	else:
		pet.show_local_bubble("粉碎失败。%s" % err)
		_show_holo(pet, "ERROR", 2.0)

## 全息屏动画 (通用分发)
func _show_holo(pet: Node2D, mode_name: String, duration: float) -> void:
	var hs = pet.holo_screen
	if not hs:
		return
	var side = hs.side  # 复用当前方向，默认 1.0 (右侧)
	match mode_name:
		"CLEANUP": hs.show_cleanup(side, duration)
		"RECYCLE": hs.show_recycle(side, duration)
		"ERROR": hs.show_error(side, duration)
		"DONE": hs.show_done(side, duration)
		"QUERY": hs.show_query(side, duration)
		"WARNING": hs.show_warning(side, duration)

# ══════════════════════════════════════
#  按钮工厂
# ══════════════════════════════════════

func _make_btn(text: String, bg: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_constant_override("outline_size", 3)
	btn.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Color(0.0, 0.0, 0.0, 0.7)
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	s.content_margin_left = 14; s.content_margin_right = 14
	s.content_margin_top = 6; s.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color(bg.r + 0.08, bg.g + 0.08, bg.b + 0.08, 1.0)
	h.border_color = Color(0.9, 0.9, 0.9, 0.6)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	
	return btn

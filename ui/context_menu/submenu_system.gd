# submenu_system.gd — 级联子菜单子系统 (RefCounted)
# 负责: 开关子菜单 + 单选子菜单的创建/显隐/动画/hover 延时/位置追踪
# 支持 L2 (分区面板) + L3 (选项面板) 两层级联
# 从 context_menu.gd 拆分
extends RefCounted

const _CyberMenuBtn = preload("res://ui/context_menu/cyber_menu_button.gd")

var _menu  # context_menu 引用

# ── L2: 分区子菜单 (主菜单按钮 → 分区面板) ──
var panels: Dictionary = {}       # id -> PanelContainer
var items: Dictionary = {}        # "item_id" -> Button (toggle 子项)
var active: String = ""
var _hover_timer: float = -1.0
var _pending_id: String = ""
var _close_timer: float = -1.0
var _radio_buttons: Dictionary = {}   # menu_id -> [{btn, value, label}]
var _radio_callbacks: Dictionary = {}  # menu_id -> Callable
var _trigger_map: Dictionary = {}     # menu_id -> Button

# ── L3: 选项子菜单 (分区面板内的按钮 → 选项面板) ──
var l3_panels: Dictionary = {}        # id -> PanelContainer
var l3_items: Dictionary = {}         # "item_id" -> Button
var l3_active: String = ""
var _l3_hover_timer: float = -1.0
var _l3_pending_id: String = ""
var _l3_close_timer: float = -1.0
var _l3_radio_buttons: Dictionary = {}
var _l3_radio_callbacks: Dictionary = {}
var _l3_trigger_map: Dictionary = {}  # menu_id -> Button (L2 面板中的按钮)
var _l3_parent_map: Dictionary = {}   # l3_id -> l2_id (归属关系)

func _init(menu_ref) -> void:
	_menu = menu_ref

# ═══════════════════════════════════════════
# L2 API (与原有接口完全一致)
# ═══════════════════════════════════════════

## 注册菜单ID与触发按钮的映射
func register_trigger(menu_id: String, btn: Button) -> void:
	_trigger_map[menu_id] = btn

## 获取子菜单对应的触发按钮
func get_trigger(menu_id: String) -> Button:
	return _trigger_map.get(menu_id, null)

# ── 开关子菜单 ──

func create_toggle(menu_id: String, toggle_items: Array, level: int = 2) -> void:
	var panel = _make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var target_items = items if level == 2 else l3_items
	for item in toggle_items:
		var btn = _CyberMenuBtn.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.1, 1, 0.9, 1))
		var item_data = item
		btn.pressed.connect(func(): _on_toggle_pressed(item_data, target_items))
		vbox.add_child(btn)
		target_items[item.id] = btn
	if level == 2:
		panel.mouse_entered.connect(func(): on_panel_enter())
		panel.mouse_exited.connect(func(): on_panel_exit())
		_menu.add_child(panel)
		panels[menu_id] = panel
	else:
		panel.mouse_entered.connect(func(): on_l3_panel_enter())
		panel.mouse_exited.connect(func(): on_l3_panel_exit())
		_menu.add_child(panel)
		l3_panels[menu_id] = panel

# ── 单选子菜单 ──

func create_radio(menu_id: String, radio_items: Array, callback: Callable, level: int = 2) -> void:
	var panel = _make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	var group_items: Array = []
	var target_radio = _radio_buttons if level == 2 else _l3_radio_buttons
	var target_callbacks = _radio_callbacks if level == 2 else _l3_radio_callbacks
	for item in radio_items:
		var btn = _CyberMenuBtn.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.1, 1, 0.9, 1))
		btn.text = item.label + " [○]"
		var v = item.value
		var mid = menu_id
		var lv = level
		btn.pressed.connect(func(): _on_radio_pressed(mid, v, lv))
		if item.has("desc"):
			var desc_text = item.desc
			var b = btn
			btn.mouse_entered.connect(func(): _menu._tooltip.show_for(b, desc_text, true))
			btn.mouse_exited.connect(func(): _menu._tooltip.show_for(b, desc_text, false))
		vbox.add_child(btn)
		group_items.append({"btn": btn, "value": item.value, "label": item.label})
	if level == 2:
		panel.mouse_entered.connect(func(): on_panel_enter())
		panel.mouse_exited.connect(func(): on_panel_exit())
		_menu.add_child(panel)
		panels[menu_id] = panel
	else:
		panel.mouse_entered.connect(func(): on_l3_panel_enter())
		panel.mouse_exited.connect(func(): on_l3_panel_exit())
		_menu.add_child(panel)
		l3_panels[menu_id] = panel
	target_radio[menu_id] = group_items
	target_callbacks[menu_id] = callback

# ── 刷新状态 ──

func refresh_toggle(item_id: String, is_on: bool, on_text: String, off_text: String) -> void:
	if item_id in items:
		items[item_id].text = on_text if is_on else off_text
	if item_id in l3_items:
		l3_items[item_id].text = on_text if is_on else off_text

func refresh_radio(menu_id: String, current_value: int) -> void:
	var target = _radio_buttons if _radio_buttons.has(menu_id) else _l3_radio_buttons
	if not target.has(menu_id): return
	for item in target[menu_id]:
		var btn: Button = item.btn
		if item.value == current_value:
			btn.text = item.label + " [●]"
		else:
			btn.text = item.label + " [○]"

# ═══════════════════════════════════════════
# L2 显示/隐藏
# ═══════════════════════════════════════════

func show(menu_id: String) -> void:
	_close_timer = -1.0
	# 切换 L2 时先关掉 L3
	hide_l3_all_instant()
	for id in panels:
		if id != menu_id and panels[id].visible:
			panels[id].hide()
	var panel: PanelContainer = panels[menu_id]
	active = menu_id
	update_position(menu_id)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.5, 0.8)
	panel.show()
	await _menu.get_tree().process_frame
	update_position(menu_id)
	# pivot: 从靠近主菜单的边缘展开
	if _menu._menu_side == 1:
		panel.pivot_offset = Vector2(0, panel.size.y / 2.0)
	else:
		panel.pivot_offset = Vector2(panel.size.x, panel.size.y / 2.0)
	var tween = _menu.create_tween().set_parallel(true)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)

func hide_all() -> void:
	hide_l3_all_instant()
	for panel in panels.values():
		if panel.visible:
			var tween = _menu.create_tween().set_parallel(true)
			tween.tween_property(panel, "modulate:a", 0.0, 0.1)
			tween.tween_property(panel, "scale", Vector2(0.5, 0.8), 0.1)
			tween.finished.connect(panel.hide)
	active = ""

func hide_all_instant() -> void:
	hide_l3_all_instant()
	for panel in panels.values():
		panel.hide()
	active = ""
	_hover_timer = -1.0
	_close_timer = -1.0



# ── L2 位置 ──

func update_position(menu_id: String) -> void:
	var trigger_btn: Button = get_trigger(menu_id)
	if not trigger_btn:
		return
	var panel: PanelContainer = panels[menu_id]
	var btn_pos = trigger_btn.global_position
	var btn_size = trigger_btn.size
	var vp_size = _menu.get_viewport().get_visible_rect().size
	var panel_w = panel.size.x if panel.size.x > 0 else 160.0
	# 寻找外层的 PanelContainer 以正确计算面板边缘（包含 padding）
	var bounds = _menu.get_panel_bounds_for_button(trigger_btn)
	var ref_pos = bounds.pos
	var ref_w = bounds.w

	var gap := 6.0
	var x: float
	if _menu._menu_side == 1:
		# 菜单在宠物右侧 → 子菜单向右级联
		var right_x = ref_pos.x + ref_w + gap
		if right_x + panel_w > vp_size.x - 10:
			x = ref_pos.x - panel_w - gap
		else:
			x = right_x
	else:
		# 菜单在宠物左侧 → 子菜单向左级联
		var left_x = ref_pos.x - panel_w - gap
		if left_x < 10:
			x = ref_pos.x + ref_w + gap
		else:
			x = left_x
	var y = btn_pos.y + btn_size.y / 2.0 - panel.size.y / 2.0
	y = clampf(y, 8.0, vp_size.y - panel.size.y - 8.0)
	panel.position = Vector2(x, y)
	panel.set_meta("trigger_global_x", trigger_btn.global_position.x + trigger_btn.size.x / 2.0)
	panel.set_meta("trigger_global_y", trigger_btn.global_position.y + trigger_btn.size.y / 2.0)
	panel.queue_redraw()

# ── L2 hover 逻辑 ──

func on_trigger_hover(menu_id: String) -> void:
	_close_timer = -1.0
	if active == menu_id:
		return
	_pending_id = menu_id
	_hover_timer = 0.15

func on_trigger_exit() -> void:
	_hover_timer = -1.0
	_close_timer = 0.3

func on_panel_enter() -> void:
	_close_timer = -1.0

func on_panel_exit() -> void:
	_close_timer = 0.3

# ═══════════════════════════════════════════
# L3 API (选项子菜单)
# ═══════════════════════════════════════════

## 注册 L3 触发按钮 + 归属关系
func register_l3_trigger(l3_id: String, btn: Button, parent_l2_id: String) -> void:
	_l3_trigger_map[l3_id] = btn
	_l3_parent_map[l3_id] = parent_l2_id

func get_l3_trigger(l3_id: String) -> Button:
	return _l3_trigger_map.get(l3_id, null)

# ── L3 显示/隐藏 ──

func show_l3(menu_id: String) -> void:
	_l3_close_timer = -1.0
	for id in l3_panels:
		if id != menu_id and l3_panels[id].visible:
			l3_panels[id].hide()
	var panel: PanelContainer = l3_panels[menu_id]
	l3_active = menu_id
	update_l3_position(menu_id)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.5, 0.8)
	panel.show()
	await _menu.get_tree().process_frame
	update_l3_position(menu_id)
	if _menu._menu_side == 1:
		panel.pivot_offset = Vector2(0, panel.size.y / 2.0)
	else:
		panel.pivot_offset = Vector2(panel.size.x, panel.size.y / 2.0)
	var tween = _menu.create_tween().set_parallel(true)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)

func hide_l3_all() -> void:
	for panel in l3_panels.values():
		if panel.visible:
			var tween = _menu.create_tween().set_parallel(true)
			tween.tween_property(panel, "modulate:a", 0.0, 0.1)
			tween.tween_property(panel, "scale", Vector2(0.5, 0.8), 0.1)
			tween.finished.connect(panel.hide)
	l3_active = ""

func hide_l3_all_instant() -> void:
	for panel in l3_panels.values():
		panel.hide()
	l3_active = ""
	_l3_hover_timer = -1.0
	_l3_close_timer = -1.0



# ── L3 位置: 基于 L2 面板边缘继续级联 ──

func update_l3_position(menu_id: String) -> void:
	var trigger_btn: Button = get_l3_trigger(menu_id)
	if not trigger_btn:
		return
	var panel: PanelContainer = l3_panels[menu_id]
	# 找到 L2 父面板作为定位参考
	var parent_id = _l3_parent_map.get(menu_id, "")
	var l2_panel = panels.get(parent_id)
	var vp_size = _menu.get_viewport().get_visible_rect().size
	var panel_w = panel.size.x if panel.size.x > 0 else 160.0
	var gap := 6.0
	var x: float
	if l2_panel:
		if _menu._menu_side == 1:
			var right_x = l2_panel.position.x + l2_panel.size.x + gap
			if right_x + panel_w > vp_size.x - 10:
				x = l2_panel.position.x - panel_w - gap
			else:
				x = right_x
		else:
			var left_x = l2_panel.position.x - panel_w - gap
			if left_x < 10:
				x = l2_panel.position.x + l2_panel.size.x + gap
			else:
				x = left_x
	else:
		# 回退: 基于外层 Panel 边界
		var bounds = _menu.get_panel_bounds_for_button(trigger_btn)
		var ref_pos = bounds.pos
		var ref_w = bounds.w
		x = ref_pos.x + ref_w + gap if _menu._menu_side == 1 else ref_pos.x - panel_w - gap
	var btn_pos = trigger_btn.global_position
	var btn_size = trigger_btn.size
	var y = btn_pos.y + btn_size.y / 2.0 - panel.size.y / 2.0
	y = clampf(y, 8.0, vp_size.y - panel.size.y - 8.0)
	panel.position = Vector2(x, y)
	panel.set_meta("trigger_global_x", trigger_btn.global_position.x + trigger_btn.size.x / 2.0)
	panel.set_meta("trigger_global_y", trigger_btn.global_position.y + trigger_btn.size.y / 2.0)
	panel.queue_redraw()

# ── L3 hover 逻辑 ──

func on_l3_trigger_hover(menu_id: String) -> void:
	_l3_close_timer = -1.0
	# 同时也阻止 L2 关闭
	_close_timer = -1.0
	if l3_active == menu_id:
		return
	_l3_pending_id = menu_id
	_l3_hover_timer = 0.15

func on_l3_trigger_exit() -> void:
	_l3_hover_timer = -1.0
	_l3_close_timer = 0.3

func on_l3_panel_enter() -> void:
	_l3_close_timer = -1.0
	# L3 面板进入时也阻止 L2 关闭
	_close_timer = -1.0

func on_l3_panel_exit() -> void:
	_l3_close_timer = 0.3

# ═══════════════════════════════════════════
# 统一定时器处理
# ═══════════════════════════════════════════

## 每帧处理 hover/close 定时器 (由主控调用)
func process_timers(delta: float) -> void:
	# L2 定时器
	if _hover_timer >= 0:
		_hover_timer -= delta
		if _hover_timer < 0:
			show(_pending_id)
	if _close_timer >= 0:
		_close_timer -= delta
		if _close_timer < 0:
			if is_mouse_in_area():
				_close_timer = -1.0
			else:
				hide_all()
	# L3 定时器
	if _l3_hover_timer >= 0:
		_l3_hover_timer -= delta
		if _l3_hover_timer < 0:
			show_l3(_l3_pending_id)
	if _l3_close_timer >= 0:
		_l3_close_timer -= delta
		if _l3_close_timer < 0:
			if is_mouse_in_l3_area():
				_l3_close_timer = -1.0
			else:
				hide_l3_all()

func is_mouse_in_area() -> bool:
	# 检查 L2 触发按钮
	for btn in _trigger_map.values():
		var local = btn.get_local_mouse_position()
		if Rect2(Vector2.ZERO, btn.size).has_point(local):
			return true
	# 检查 L2 面板
	for panel in panels.values():
		if panel.visible:
			var local = panel.get_local_mouse_position()
			if Rect2(Vector2.ZERO, panel.size).has_point(local):
				return true
	# 检查 L3 面板 (L3 打开时不应关闭 L2)
	for panel in l3_panels.values():
		if panel.visible:
			var local = panel.get_local_mouse_position()
			if Rect2(Vector2.ZERO, panel.size).has_point(local):
				return true
	return false

func is_mouse_in_l3_area() -> bool:
	if l3_active != "":
		var btn = _l3_trigger_map.get(l3_active)
		if is_instance_valid(btn):
			var local = btn.get_local_mouse_position()
			if Rect2(Vector2.ZERO, btn.size).has_point(local):
				return true
	# 检查 L3 面板
	for panel in l3_panels.values():
		if panel.visible:
			var local = panel.get_local_mouse_position()
			if Rect2(Vector2.ZERO, panel.size).has_point(local):
				return true
	return false

# ═══════════════════════════════════════════
# 内部工具
# ═══════════════════════════════════════════

func _make_panel() -> PanelContainer:
	var panel = PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.16, 0.92)
	style.border_color = Color.from_hsv(EventBus.ui_hue, 0.8, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.draw.connect(_menu.draw_panel_tail.bind(panel))
	return panel

func _on_toggle_pressed(item: Dictionary, target_items: Dictionary) -> void:
	var btn: Button = target_items[item.id]
	var is_on = btn.text.ends_with("[●]")
	var new_val = not is_on
	btn.text = item.on if new_val else item.off
	SettingsManager.set_bool(item.key, new_val)
	EventBus.setting_toggled.emit(item.key, new_val)

func _on_radio_pressed(menu_id: String, value: int, level: int = 2) -> void:
	refresh_radio(menu_id, value)
	var target_callbacks = _radio_callbacks if level == 2 else _l3_radio_callbacks
	if target_callbacks.has(menu_id):
		target_callbacks[menu_id].call(value)

## UI 主题色运行时更新: 刷新所有子菜单面板边框
func apply_ui_theme(hue: float) -> void:
	for panel in panels.values():
		var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style = style.duplicate()
			style.border_color = Color.from_hsv(hue, 0.8, 1.0, 0.8)
			panel.add_theme_stylebox_override("panel", style)
	for panel in l3_panels.values():
		var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style = style.duplicate()
			style.border_color = Color.from_hsv(hue, 0.8, 1.0, 0.8)
			panel.add_theme_stylebox_override("panel", style)

## 获取所有可见面板 (供外部点击检测用)
func get_all_visible_panels() -> Array:
	var result: Array = []
	for panel in panels.values():
		if panel.visible:
			result.append(panel)
	for panel in l3_panels.values():
		if panel.visible:
			result.append(panel)
	return result



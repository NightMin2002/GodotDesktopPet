# drop_menu.gd — 文件投喂操作菜单 (RefCounted)
# 布局: 宠物左侧 [取消] + 右侧 [指令] → hover 展开子菜单
# 每帧跟随宠物移动, 淡入/淡出动画, 屏幕边界自适应

var file_drop  # FileDrop 骨架引用

# ── 内部节点 ──
var _canvas: CanvasLayer = null
var _btn_cancel: Button = null
var _btn_action: Button = null
var _submenu: VBoxContainer = null    # 指令下拉子菜单
var _submenu_bg: PanelContainer = null  # 子菜单背景面板
var _showing: bool = false
var _submenu_open: bool = false

const FADE_TIME := 0.3

# ══════════════════════════════════════
#  显示
# ══════════════════════════════════════

func show(actions: Array, pet: Node2D) -> void:
	dismiss()
	
	_canvas = CanvasLayer.new()
	_canvas.layer = 120
	pet.get_tree().root.add_child(_canvas)
	
	# ── 左侧: [取消] ──
	_btn_cancel = _make_pill_btn("取消", Color(0.55, 0.55, 0.55, 0.85), Color(0.0, 0.0, 0.0, 0.7))
	_btn_cancel.pressed.connect(func(): file_drop.execute_action("_cancel"))
	_btn_cancel.modulate.a = 0.0
	_canvas.add_child(_btn_cancel)
	
	# ── 右侧: [指令] ──
	var hue = EventBus.ui_hue if EventBus.ui_hue is float else 0.55
	var accent_bg = Color.from_hsv(hue, 0.45, 0.35, 0.9)
	var accent_border = Color.from_hsv(hue, 0.5, 0.6, 0.5)
	_btn_action = _make_pill_btn("指令", accent_bg, Color(0.0, 0.0, 0.0, 0.7))
	_btn_action.modulate.a = 0.0
	_btn_action.mouse_entered.connect(_open_submenu.bind(actions))
	_canvas.add_child(_btn_action)
	
	# ── 子菜单容器 (初始隐藏) ──
	_submenu_bg = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.18, 0.92)
	sb.set_border_width_all(1)
	sb.border_color = Color.from_hsv(hue, 0.4, 0.5, 0.4)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4; sb.content_margin_right = 4
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	_submenu_bg.add_theme_stylebox_override("panel", sb)
	_submenu_bg.visible = false
	_canvas.add_child(_submenu_bg)
	
	_submenu = VBoxContainer.new()
	_submenu.add_theme_constant_override("separation", 2)
	_submenu_bg.add_child(_submenu)
	
	# 填充子菜单项
	for action in actions:
		var item = _make_submenu_item(action.label)
		var action_id = action.id
		item.pressed.connect(func(): file_drop.execute_action(action_id))
		_submenu.add_child(item)
	
	_showing = true
	_update_positions()
	
	# 淡入
	var tw = _canvas.create_tween().set_parallel(true)
	tw.tween_property(_btn_cancel, "modulate:a", 1.0, FADE_TIME)
	tw.tween_property(_btn_action, "modulate:a", 1.0, FADE_TIME).set_delay(0.1)

# ══════════════════════════════════════
#  子菜单展开/收起
# ══════════════════════════════════════

func _open_submenu(actions: Array) -> void:
	if _submenu_open:
		return
	_submenu_open = true
	_submenu_bg.visible = true
	_submenu_bg.modulate.a = 0.0
	_update_positions()
	
	if _canvas and is_instance_valid(_canvas):
		var tw = _canvas.create_tween()
		tw.tween_property(_submenu_bg, "modulate:a", 1.0, 0.2)

func _close_submenu() -> void:
	if not _submenu_open:
		return
	_submenu_open = false
	
	if _submenu_bg and is_instance_valid(_submenu_bg) and _canvas and is_instance_valid(_canvas):
		var tw = _canvas.create_tween()
		tw.tween_property(_submenu_bg, "modulate:a", 0.0, 0.15)
		tw.finished.connect(func():
			if _submenu_bg and is_instance_valid(_submenu_bg):
				_submenu_bg.visible = false
		)

## 每帧检查鼠标是否离开了按钮 + 子菜单区域
func _check_mouse_leave() -> void:
	if not _submenu_open:
		return
	if not file_drop or not file_drop.pet:
		return
	var mouse = file_drop.pet.get_viewport().get_mouse_position()
	var on_btn = _btn_action and is_instance_valid(_btn_action) and Rect2(_btn_action.position, _btn_action.size).grow(6).has_point(mouse)
	var on_menu = _submenu_bg and is_instance_valid(_submenu_bg) and _submenu_bg.visible and Rect2(_submenu_bg.position, _submenu_bg.size).grow(8).has_point(mouse)
	if not on_btn and not on_menu:
		_close_submenu()

# ══════════════════════════════════════
#  位置跟随 (每帧由 file_drop 驱动)
# ══════════════════════════════════════

func update(delta: float) -> void:
	if _showing:
		_update_positions()
		_check_mouse_leave()

func _update_positions() -> void:
	if not file_drop or not file_drop.pet:
		return
	var pet = file_drop.pet
	if not is_instance_valid(pet):
		dismiss()
		return
	
	var anchor = pet.get_ui_anchor()
	var vp = pet.get_viewport().get_visible_rect().size
	var pet_r: float = pet.PET_RADIUS
	const BTN_GAP := 12.0
	const MARGIN := 4.0
	
	var btn_y = anchor.center.y - 14.0
	
	# 计算按钮尺寸
	var cw = _btn_cancel.size.x if is_instance_valid(_btn_cancel) else 60.0
	var ch = _btn_cancel.size.y if is_instance_valid(_btn_cancel) else 28.0
	var aw = _btn_action.size.x if is_instance_valid(_btn_action) else 60.0
	var ah = _btn_action.size.y if is_instance_valid(_btn_action) else 28.0
	const BTN_SPACE := 8.0
	
	# 计算左右可用空间
	var left_space = anchor.center.x - pet_r - BTN_GAP
	var right_space = vp.x - (anchor.center.x + pet_r + BTN_GAP)
	
	if left_space >= cw + 10 and right_space >= aw + 10:
		# ── 标准布局: 取消在左, 指令在右 ──
		if is_instance_valid(_btn_cancel):
			_btn_cancel.position = Vector2(
				anchor.center.x - pet_r - BTN_GAP - cw, btn_y)
		if is_instance_valid(_btn_action):
			_btn_action.position = Vector2(
				anchor.center.x + pet_r + BTN_GAP, btn_y)
	elif right_space >= cw + BTN_SPACE + aw + 10:
		# ── 左侧不够: 两个按钮都放右侧 ──
		var rx = anchor.center.x + pet_r + BTN_GAP
		if is_instance_valid(_btn_cancel):
			_btn_cancel.position = Vector2(rx, btn_y)
			rx += cw + BTN_SPACE
		if is_instance_valid(_btn_action):
			_btn_action.position = Vector2(rx, btn_y)
	else:
		# ── 右侧也不够: 两个按钮都放左侧 ──
		var lx = anchor.center.x - pet_r - BTN_GAP
		if is_instance_valid(_btn_action):
			_btn_action.position = Vector2(lx - aw, btn_y)
			lx -= aw + BTN_SPACE
		if is_instance_valid(_btn_cancel):
			_btn_cancel.position = Vector2(lx - cw, btn_y)
	
	# ── 最终边界 clamp ──
	for btn in [_btn_cancel, _btn_action]:
		if btn and is_instance_valid(btn):
			var w = btn.size.x
			var h = btn.size.y
			btn.position.x = clampf(btn.position.x, MARGIN, maxf(MARGIN, vp.x - w - MARGIN))
			btn.position.y = clampf(btn.position.y, MARGIN, maxf(MARGIN, vp.y - h - MARGIN))
	
	# ── 子菜单: 贴在 [指令] 按钮下方 ──
	if _submenu_bg and is_instance_valid(_submenu_bg) and _submenu_bg.visible and _btn_action and is_instance_valid(_btn_action):
		var ax = _btn_action.position.x
		var ay = _btn_action.position.y + _btn_action.size.y + 4.0
		var sw = _submenu_bg.size.x
		var sh = _submenu_bg.size.y
		# 如果菜单超出屏幕底部, 向上弹出
		if ay + sh > vp.y - MARGIN:
			ay = _btn_action.position.y - sh - 4.0
		# 水平不超出屏幕
		ax = clampf(ax, MARGIN, maxf(MARGIN, vp.x - sw - MARGIN))
		_submenu_bg.position = Vector2(ax, ay)
	
	# ── 更新 DWM 穿透区域 ──
	_update_hit_rects()

func _update_hit_rects() -> void:
	if not file_drop or not file_drop.pet:
		return
	var rects: Array[Rect2] = []
	if _btn_cancel and is_instance_valid(_btn_cancel):
		rects.append(Rect2(_btn_cancel.position, _btn_cancel.size))
	if _btn_action and is_instance_valid(_btn_action):
		rects.append(Rect2(_btn_action.position, _btn_action.size))
	if _submenu_bg and is_instance_valid(_submenu_bg) and _submenu_bg.visible:
		rects.append(Rect2(_submenu_bg.position, _submenu_bg.size))
	
	if rects.size() > 0:
		var min_pos = rects[0].position
		var max_end = rects[0].end
		for r in rects:
			min_pos.x = minf(min_pos.x, r.position.x)
			min_pos.y = minf(min_pos.y, r.position.y)
			max_end.x = maxf(max_end.x, r.end.x)
			max_end.y = maxf(max_end.y, r.end.y)
		file_drop.pet.set_overlay_rect("file_drop_menu", Rect2(min_pos, max_end - min_pos))

# ══════════════════════════════════════
#  关闭
# ══════════════════════════════════════

func dismiss() -> void:
	_submenu_open = false
	_showing = false
	if file_drop and file_drop.pet and is_instance_valid(file_drop.pet):
		file_drop.pet.remove_overlay_rect("file_drop_menu")
	
	if _canvas and is_instance_valid(_canvas):
		# 淡出然后销毁
		var nodes_to_fade: Array = []
		if _btn_cancel and is_instance_valid(_btn_cancel): nodes_to_fade.append(_btn_cancel)
		if _btn_action and is_instance_valid(_btn_action): nodes_to_fade.append(_btn_action)
		if _submenu_bg and is_instance_valid(_submenu_bg): nodes_to_fade.append(_submenu_bg)
		
		if nodes_to_fade.size() > 0:
			var tw = _canvas.create_tween().set_parallel(true)
			for n in nodes_to_fade:
				tw.tween_property(n, "modulate:a", 0.0, 0.2)
			var canvas_ref = _canvas
			tw.finished.connect(func():
				if is_instance_valid(canvas_ref):
					canvas_ref.queue_free()
			)
		else:
			_canvas.queue_free()
	
	_canvas = null
	_btn_cancel = null
	_btn_action = null
	_submenu = null
	_submenu_bg = null

# ══════════════════════════════════════
#  按钮样式
# ══════════════════════════════════════

## 药丸形主按钮 (和 todo_prompt 同风格)
func _make_pill_btn(text: String, bg: Color, border: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_constant_override("outline_size", 3)
	btn.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	btn.flat = false
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
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

## 子菜单条目 (窄高, 无圆角, 宽度撑满)
func _make_submenu_item(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 0)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(0.82, 0.86, 0.95))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var hue = EventBus.ui_hue if EventBus.ui_hue is float else 0.55
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.set_corner_radius_all(3)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 5; s.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color.from_hsv(hue, 0.4, 0.3, 0.6)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	
	return btn

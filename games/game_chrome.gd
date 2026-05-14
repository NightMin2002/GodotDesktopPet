# game_chrome.gd — 游戏悬浮组件系统 (RefCounted)
# 从 BaseGame 提取的悬浮 UI 管理: 标题气泡、侧边按钮、发言气泡、
# 连接线、重开按钮、全息合成器委托
# 所有组件挂载在 game_container 的 parent (CanvasLayer) 上
class_name GameChrome extends RefCounted

# ── 宿主引用 (由 BaseGame 注入) ──
var game  # BaseGame (不标注类型, 避免循环引用)

# ── 节点引用 ──
var title_bubble: PanelContainer = null
var side_container: VBoxContainer = null
var connector: ColorRect = null
var restart_bubble: Button = null
var speech_bubble: Control = null
var speech_label: Label = null
var close_btn: Button = null
var help_btn: Button = null

# ── 状态 ──
var chrome_side: int = 1         # 按钮朝向 (1=右侧, -1=左侧)
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var pending_speech: String = ""  # _say() 在气泡创建前调用时暂存

# ── 全息合成器 ──
var _holo: HoloCompositor = null

# ══════════════════════════════════════════════
# 初始化
# ══════════════════════════════════════════════

## 创建悬浮组件 (游戏在面板构建完成、定位之后调用)
func setup(game_name: String, on_close: Callable, on_restart: Callable = Callable()) -> void:
	var gc = game.game_container
	var parent = gc.get_parent()
	if not parent:
		return
	var hue = EventBus.ui_hue

	# ── 标题气泡 ──
	title_bubble = PanelContainer.new()
	var tb_bg = StyleBoxFlat.new()
	tb_bg.bg_color = Color(0.04, 0.06, 0.12, 0.92)
	tb_bg.border_color = Color.from_hsv(hue, 0.45, 0.85, 0.35)
	tb_bg.set_border_width_all(1)
	tb_bg.set_corner_radius_all(14)
	tb_bg.content_margin_left = 18
	tb_bg.content_margin_right = 18
	tb_bg.content_margin_top = 5
	tb_bg.content_margin_bottom = 5
	title_bubble.add_theme_stylebox_override("panel", tb_bg)
	title_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bubble.mouse_default_cursor_shape = Control.CURSOR_MOVE

	var title_label = Label.new()
	title_label.text = game_name
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color.from_hsv(hue, 0.4, 1.0, 0.9))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bubble.add_child(title_label)

	title_bubble.gui_input.connect(_on_drag_input)
	parent.add_child(title_bubble)

	# ── 连接线 ──
	connector = ColorRect.new()
	connector.color = Color.from_hsv(hue, 0.4, 0.8, 0.2)
	connector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(connector)

	# ── 侧边按钮组 ──
	side_container = VBoxContainer.new()
	side_container.add_theme_constant_override("separation", 6)
	side_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# i 按钮 (有教程内容时才创建)
	var steps = game.get_tutorial_steps()
	if not steps.is_empty():
		var info_btn = _create_button("i", false)
		info_btn.pressed.connect(game._toggle_tutorial)
		help_btn = info_btn
		side_container.add_child(info_btn)
	# 隐藏按钮 (收起面板, 只留全息屏)
	var hide_btn = _create_button("▽", false)
	hide_btn.pressed.connect(func(): game.set_panel_visible(false))
	side_container.add_child(hide_btn)
	# 关闭按钮
	close_btn = _create_button("✕", true)
	close_btn.pressed.connect(on_close)
	side_container.add_child(close_btn)
	parent.add_child(side_container)

	# ── 重开按钮 (初始隐藏, game over 后显示) ──
	if on_restart.is_valid():
		restart_bubble = _create_restart_button(on_restart)
		parent.add_child(restart_bubble)
		restart_bubble.hide()

	# 确定按钮朝向
	chrome_side = _determine_side()

	# ── 发言气泡 (在侧边按钮对面, 靠近宠物的一侧) ──
	speech_bubble = _create_speech_bubble()
	parent.add_child(speech_bubble)

	if game._auto_play:
		# 自玩时隐藏发言气泡 (不自言自语)
		speech_bubble.visible = false
		pending_speech = ""
	elif pending_speech != "":
		# 如果 start() 中的 _say() 先于气泡创建，立即显示暂存文本
		speech_label.text = pending_speech
		pending_speech = ""

	# 等布局完成后定位
	await parent.get_tree().process_frame
	update_positions()
	# 先创建全息合成器 (此时各组件位置正确, 包围盒精确)
	_holo = HoloCompositor.new()
	_holo.setup(_get_holo_refs())
	if game._panel_hidden:
		# 面板已隐藏: chrome 直接隐藏, 跳过入场动画
		for node in [title_bubble, side_container, connector, speech_bubble]:
			if is_instance_valid(node):
				node.visible = false
	else:
		# 再启动入场动画 (动画会临时修改位置/透明度, 不影响全息布局)
		animate_in()

# ══════════════════════════════════════════════
# 发言
# ══════════════════════════════════════════════

## 更新发言气泡文字 (带高亮闪烁动画)
func say(text: String) -> void:
	if game._auto_play:
		return  # 自玩时不在面板气泡发言 (不自言自语)
	if not speech_label:
		# 气泡尚未创建，暂存文本
		pending_speech = text
		return
	speech_label.text = text
	# 同步全息克隆体的文字
	if _holo:
		_holo.sync_speech_text(text)
	if is_instance_valid(speech_bubble):
		speech_bubble.modulate = Color(1.4, 1.4, 1.4, 1.0)
		var owner_node: Node = null
		if is_instance_valid(game.game_container): owner_node = game.game_container
		elif game.game_viewport: owner_node = game.game_viewport
		if owner_node:
			var tween = owner_node.create_tween()
			tween.tween_property(speech_bubble, "modulate", Color.WHITE, 0.5)

# ══════════════════════════════════════════════
# 重开按钮
# ══════════════════════════════════════════════

## 显示悬浮重开按钮 (game over 后调用)
func show_restart() -> void:
	if game._panel_hidden:
		return
	if not is_instance_valid(restart_bubble) or not is_instance_valid(game.game_container):
		return
	restart_bubble.show()
	# 同步全息克隆体可见性
	if _holo:
		_holo.sync_restart_visible(true)
	# 检查面板下方是否有足够空间
	var gc_pos = game.game_container.position
	var gc_size = game.game_container.size
	var needed_bottom = gc_pos.y + gc_size.y + game._RESTART_GAP + game._RESTART_RESERVE.y + game._RESTART_GAP
	if needed_bottom > game.screen_size.y:
		var shift = needed_bottom - game.screen_size.y
		game.game_container.position.y = maxf(gc_pos.y - shift, 8.0)
	update_positions()
	# 弹入动画
	restart_bubble.modulate.a = 0.0
	restart_bubble.scale = Vector2(0.5, 0.5)
	restart_bubble.pivot_offset = restart_bubble.size / 2.0 if restart_bubble.size.x > 1 else Vector2(50, 16)
	var tw = restart_bubble.create_tween().set_parallel(true)
	tw.tween_property(restart_bubble, "modulate:a", 1.0, 0.2)
	tw.tween_property(restart_bubble, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 隐藏悬浮重开按钮 (重新开始时调用)
func hide_restart() -> void:
	game._takeover = false  # 重开新局，清除接管标记
	if is_instance_valid(restart_bubble):
		restart_bubble.hide()
	if _holo:
		_holo.sync_restart_visible(false)
		_holo.update_layout(_get_holo_refs())

# ══════════════════════════════════════════════
# 位置同步
# ══════════════════════════════════════════════

## 同步悬浮组件位置 (面板移动时调用)
func update_positions() -> void:
	var gc = game.game_container
	if not is_instance_valid(gc):
		return
	var gc_pos = gc.position
	var gc_size = gc.size
	var gap := 8.0
	var vp = game.screen_size

	# 标题气泡: 优先居中在面板上方, 空间不足时翻转到下方
	if is_instance_valid(title_bubble):
		var tb_size = title_bubble.size
		var x = gc_pos.x + (gc_size.x - tb_size.x) / 2.0
		x = clampf(x, 8.0, vp.x - tb_size.x - 8.0)
		var above_y = gc_pos.y - tb_size.y - gap
		if above_y >= 8.0:
			title_bubble.position = Vector2(x, above_y)
		else:
			var below_y = gc_pos.y + gc_size.y + gap
			below_y = clampf(below_y, 8.0, vp.y - tb_size.y - 8.0)
			title_bubble.position = Vector2(x, below_y)

	# 连接线: 在标题和面板之间 (自动判断方向)
	if is_instance_valid(connector) and is_instance_valid(title_bubble):
		var tb_pos_y = title_bubble.position.y
		var tb_end_y = tb_pos_y + title_bubble.size.y
		var title_above = (tb_pos_y + title_bubble.size.y <= gc_pos.y)
		if title_above:
			var line_height = gc_pos.y - tb_end_y
			if line_height > 1:
				connector.size = Vector2(1, line_height)
				connector.position = Vector2(gc_pos.x + gc_size.x / 2.0, tb_end_y)
				connector.show()
			else:
				connector.hide()
		else:
			var line_height = tb_pos_y - (gc_pos.y + gc_size.y)
			if line_height > 1:
				connector.size = Vector2(1, line_height)
				connector.position = Vector2(gc_pos.x + gc_size.x / 2.0, gc_pos.y + gc_size.y)
				connector.show()
			else:
				connector.hide()

	# 侧边按钮: 面板外侧顶部对齐
	if is_instance_valid(side_container):
		var sc_size = side_container.size
		var x: float
		if chrome_side > 0:
			x = gc_pos.x + gc_size.x + gap
		else:
			x = gc_pos.x - sc_size.x - gap
		var y = gc_pos.y
		x = clampf(x, 8.0, vp.x - sc_size.x - 8.0)
		y = clampf(y, 8.0, vp.y - sc_size.y - 8.0)
		side_container.position = Vector2(x, y)

	# 发言气泡: 面板侧面 (侧边按钮对面, 即靠近宠物的一侧)
	if is_instance_valid(speech_bubble):
		var bubble: PanelContainer = speech_bubble.get_meta("_bubble") as PanelContainer
		var arrow: Control = speech_bubble.get_meta("_arrow") as Control
		if bubble:
			var speech_side = -chrome_side  # 和侧边按钮相反的一侧
			var b_size = bubble.size
			var arrow_w := 8.0
			var sx: float
			if speech_side > 0:
				sx = gc_pos.x + gc_size.x + gap + arrow_w
			else:
				sx = gc_pos.x - b_size.x - gap - arrow_w
			var sy = gc_pos.y + 8.0
			sx = clampf(sx, 8.0, vp.x - b_size.x - 8.0)
			sy = clampf(sy, 8.0, vp.y - b_size.y - 8.0)
			bubble.position = Vector2(sx, sy)
			# 箭头定位
			if arrow:
				var arrow_h := 12.0
				var ax: float
				if speech_side > 0:
					ax = sx - arrow_w
					(arrow as _SpeechArrow).pointing_right = false
				else:
					ax = sx + b_size.x
					(arrow as _SpeechArrow).pointing_right = true
				var ay = sy + b_size.y / 2.0 - arrow_h / 2.0
				arrow.position = Vector2(ax, ay)
				arrow.size = Vector2(arrow_w, arrow_h)
				arrow.queue_redraw()

	# 重开按钮: 居中在面板下方
	if is_instance_valid(restart_bubble) and restart_bubble.visible:
		var rb_size = restart_bubble.size
		var rx = gc_pos.x + (gc_size.x - rb_size.x) / 2.0
		var ry = gc_pos.y + gc_size.y + gap
		rx = clampf(rx, 8.0, vp.x - rb_size.x - 8.0)
		ry = clampf(ry, 8.0, vp.y - rb_size.y - 8.0)
		restart_bubble.position = Vector2(rx, ry)

	# 教程面板
	game._position_tutorial()
	# 全息合成视口布局同步
	if _holo:
		_holo.update_layout(_get_holo_refs())

# ══════════════════════════════════════════════
# 拖拽
# ══════════════════════════════════════════════

## 标题气泡拖拽 → 带动整个面板移动
func _on_drag_input(event: InputEvent) -> void:
	var gc = game.game_container
	if not is_instance_valid(gc):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = gc.get_viewport().get_mouse_position() - gc.position
			EventBus.drag_started.emit()
		else:
			if _dragging:
				EventBus.drag_ended.emit()
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var vp = game.screen_size
		var new_pos = gc.get_viewport().get_mouse_position() - _drag_offset
		new_pos.x = clampf(new_pos.x, 8.0, vp.x - gc.size.x - 8.0)
		new_pos.y = clampf(new_pos.y, 8.0, vp.y - gc.size.y - 8.0)
		gc.position = new_pos
		update_positions()

# ══════════════════════════════════════════════
# 动画
# ══════════════════════════════════════════════

## 悬浮组件分层入场动画
func animate_in() -> void:
	# 标题气泡: 从下方浮上 + 淡入
	if is_instance_valid(title_bubble):
		var target_y = title_bubble.position.y
		title_bubble.position.y += 12
		title_bubble.modulate.a = 0.0
		var tw = title_bubble.create_tween().set_parallel(true)
		tw.tween_property(title_bubble, "position:y", target_y, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.set_delay(0.12)
		tw.tween_property(title_bubble, "modulate:a", 1.0, 0.2).set_delay(0.12)

	# 连接线: 淡入
	if is_instance_valid(connector):
		connector.modulate.a = 0.0
		var tw = connector.create_tween()
		tw.tween_property(connector, "modulate:a", 1.0, 0.2).set_delay(0.18)

	# 侧边按钮: 逐个弹出
	if is_instance_valid(side_container):
		for i in range(side_container.get_child_count()):
			var child = side_container.get_child(i) as Control
			if not child:
				continue
			child.modulate.a = 0.0
			child.scale = Vector2(0.3, 0.3)
			child.pivot_offset = child.size / 2.0
			var delay = 0.2 + i * 0.08
			var tw = child.create_tween().set_parallel(true)
			tw.tween_property(child, "modulate:a", 1.0, 0.15).set_delay(delay)
			tw.tween_property(child, "scale", Vector2.ONE, 0.22) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
				.set_delay(delay)

	# 发言气泡: 淡入
	if is_instance_valid(speech_bubble):
		speech_bubble.modulate.a = 0.0
		var tw = speech_bubble.create_tween()
		tw.tween_property(speech_bubble, "modulate:a", 1.0, 0.25).set_delay(0.15)

## 悬浮组件退场动画
func animate_out() -> void:
	for node in [title_bubble, side_container, connector, restart_bubble, speech_bubble]:
		if is_instance_valid(node):
			var tw = node.create_tween()
			tw.tween_property(node, "modulate:a", 0.0, 0.12)

# ══════════════════════════════════════════════
# 全息合成 (委托给 HoloCompositor)
# ══════════════════════════════════════════════

## 构建传递给 HoloCompositor 的组件引用字典
func _get_holo_refs() -> Dictionary:
	return {
		"game_viewport": game.game_viewport,
		"game_container": game.game_container,
		"parent": game.game_container.get_parent() if is_instance_valid(game.game_container) else null,
		"title": title_bubble,
		"connector": connector,
		"side": side_container,
		"restart": restart_bubble,
		"speech": speech_bubble,
		"chrome_side": chrome_side,
	}

## 获取全息合成纹理 (供 PetHoloScreen 渲染)
func get_holo_texture() -> Texture2D:
	if _holo:
		var tex = _holo.get_texture()
		if tex:
			return tex
	if game.game_viewport:
		return game.game_viewport.get_texture()
	return null

# ══════════════════════════════════════════════
# 清理
# ══════════════════════════════════════════════

func cleanup() -> void:
	for node in [title_bubble, side_container, connector, restart_bubble, speech_bubble]:
		if is_instance_valid(node):
			node.queue_free()
	title_bubble = null
	side_container = null
	connector = null
	restart_bubble = null
	speech_bubble = null
	speech_label = null
	close_btn = null
	help_btn = null
	if _holo:
		_holo.cleanup()
		_holo = null

## 返回悬浮组件的屏幕矩形 (供 hit_region_manager 注册)
func get_rects() -> Array[Rect2]:
	if game._panel_hidden:
		return []
	var rects: Array[Rect2] = []
	if is_instance_valid(title_bubble):
		rects.append(Rect2(title_bubble.position, title_bubble.size))
	if is_instance_valid(side_container):
		rects.append(Rect2(side_container.position, side_container.size))
	if is_instance_valid(restart_bubble) and restart_bubble.visible:
		rects.append(Rect2(restart_bubble.position, restart_bubble.size))
	if is_instance_valid(speech_bubble):
		var bubble: PanelContainer = speech_bubble.get_meta("_bubble") as PanelContainer
		if bubble:
			rects.append(Rect2(bubble.position, bubble.size))
	return rects

# ══════════════════════════════════════════════
# 私有: UI 工厂
# ══════════════════════════════════════════════

## 判断按钮应该在面板哪一侧 (远离宠物)
func _determine_side() -> int:
	var pet_x = game.screen_size.x / 2.0
	if is_instance_valid(game._pet):
		pet_x = game._pet.get_global_transform_with_canvas().get_origin().x
	var panel_center_x = game.game_container.position.x + game.game_container.size.x / 2.0
	if panel_center_x > pet_x:
		return 1
	else:
		return -1

## 创建圆形悬浮按钮
func _create_button(text: String, is_close: bool) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(30, 30)
	btn.add_theme_font_size_override("font_size", 13)
	var hue = EventBus.ui_hue
	if is_close:
		btn.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65, 0.7))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.35, 0.35, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.2, 0.2, 1.0))
	else:
		btn.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65, 0.7))
		btn.add_theme_color_override("font_hover_color", Color.from_hsv(hue, 0.5, 1.0, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color.from_hsv(hue, 0.6, 1.0, 1.0))
	# normal 背景
	var normal_bg = StyleBoxFlat.new()
	normal_bg.bg_color = Color(0.05, 0.08, 0.15, 0.88)
	normal_bg.border_color = Color.from_hsv(hue, 0.35, 0.65, 0.3)
	normal_bg.set_border_width_all(1)
	normal_bg.set_corner_radius_all(15)
	normal_bg.set_content_margin_all(0)
	# hover 背景
	var hover_bg = StyleBoxFlat.new()
	if is_close:
		hover_bg.bg_color = Color(0.18, 0.06, 0.06, 0.9)
		hover_bg.border_color = Color(0.8, 0.25, 0.25, 0.5)
	else:
		hover_bg.bg_color = Color(0.08, 0.12, 0.22, 0.9)
		hover_bg.border_color = Color.from_hsv(hue, 0.5, 0.9, 0.5)
	hover_bg.set_border_width_all(1)
	hover_bg.set_corner_radius_all(15)
	hover_bg.set_content_margin_all(0)

	btn.add_theme_stylebox_override("normal", normal_bg)
	btn.add_theme_stylebox_override("hover", hover_bg)
	btn.add_theme_stylebox_override("pressed", hover_bg)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn

## 创建悬浮发言气泡 (在面板侧面, 带小三角指向面板)
func _create_speech_bubble() -> Control:
	var hue = EventBus.ui_hue
	var wrapper = Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 主气泡面板
	var bubble = PanelContainer.new()
	bubble.custom_minimum_size = Vector2(140, 0)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.12, 0.92)
	bg.border_color = Color.from_hsv(hue, 0.45, 0.85, 0.35)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	bubble.add_theme_stylebox_override("panel", bg)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE

	speech_label = Label.new()
	speech_label.text = ""
	speech_label.add_theme_font_size_override("font_size", 13)
	speech_label.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95, 0.9))
	speech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_label.custom_minimum_size = Vector2(120, 0)
	speech_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(speech_label)

	# 小三角箭头 (用 _draw 绘制, 方向在定位时更新)
	var arrow = _SpeechArrow.new()
	arrow.hue = hue
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(arrow)
	wrapper.add_child(bubble)
	wrapper.set_meta("_bubble", bubble)
	wrapper.set_meta("_arrow", arrow)
	return wrapper

## 创建悬浮重开按钮 (pill 形状, 居中在面板下方)
func _create_restart_button(on_restart: Callable) -> Button:
	var btn = Button.new()
	btn.text = "再来一局"
	btn.custom_minimum_size = Vector2(100, 32)
	btn.add_theme_font_size_override("font_size", 14)
	var hue = EventBus.ui_hue
	btn.add_theme_color_override("font_color", Color.from_hsv(hue, 0.35, 0.85, 0.8))
	btn.add_theme_color_override("font_hover_color", Color.from_hsv(hue, 0.5, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color.from_hsv(hue, 0.6, 1.0, 1.0))
	var normal_bg = StyleBoxFlat.new()
	normal_bg.bg_color = Color(0.05, 0.08, 0.15, 0.88)
	normal_bg.border_color = Color.from_hsv(hue, 0.35, 0.65, 0.3)
	normal_bg.set_border_width_all(1)
	normal_bg.set_corner_radius_all(16)
	normal_bg.content_margin_left = 18
	normal_bg.content_margin_right = 18
	normal_bg.content_margin_top = 4
	normal_bg.content_margin_bottom = 4
	var hover_bg = StyleBoxFlat.new()
	hover_bg.bg_color = Color(0.08, 0.12, 0.22, 0.9)
	hover_bg.border_color = Color.from_hsv(hue, 0.5, 0.9, 0.5)
	hover_bg.set_border_width_all(1)
	hover_bg.set_corner_radius_all(16)
	hover_bg.content_margin_left = 18
	hover_bg.content_margin_right = 18
	hover_bg.content_margin_top = 4
	hover_bg.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal_bg)
	btn.add_theme_stylebox_override("hover", hover_bg)
	btn.add_theme_stylebox_override("pressed", hover_bg)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(on_restart)
	return btn

# ══════════════════════════════════════════════
# 内嵌类: 发言气泡小三角箭头
# ══════════════════════════════════════════════

class _SpeechArrow extends Control:
	var hue: float = 0.55
	var pointing_right: bool = false  # true = 箭头尖端朝右 (面板在右侧)

	func _draw() -> void:
		var w = size.x
		var h = size.y
		if w < 1 or h < 1:
			return
		var points: PackedVector2Array
		if pointing_right:
			# 尖端在右
			points = PackedVector2Array([
				Vector2(0, 0),
				Vector2(w, h / 2.0),
				Vector2(0, h),
			])
		else:
			# 尖端在左
			points = PackedVector2Array([
				Vector2(w, 0),
				Vector2(0, h / 2.0),
				Vector2(w, h),
			])
		var fill_color = Color(0.04, 0.06, 0.12, 0.92)
		draw_colored_polygon(points, fill_color)
		# 边框线 (只画两条斜边，不画底边)
		var border_color = Color.from_hsv(hue, 0.45, 0.85, 0.35)
		draw_line(points[0], points[1], border_color, 1.0, true)
		draw_line(points[1], points[2], border_color, 1.0, true)

# base_game.gd — 小游戏接口基类
# 所有游戏包中的游戏脚本必须继承此类，实现标准接口
# 生命周期: GameManager 注入属性 → start() → [游戏进行中] → game_finished 信号 → cleanup()
class_name BaseGame extends RefCounted

enum Result { WIN, LOSE, DRAW }

## 游戏结束信号 (GameManager 监听)
signal game_finished(result: Result)

# ── GameManager 注入的运行时引用 (start 前自动设置) ──
var game_viewport: SubViewport            # 游戏 UI 渲染到的 SubViewport
var game_container: SubViewportContainer   # 屏幕上的容器 (定位/拖拽用)
var screen_size: Vector2                   # 屏幕实际大小
var _pet: Node2D = null                    # 宠物原体引用

# ── 教程面板 ──
var _tutorial_panel: PanelContainer = null
var _tutorial_visible: bool = false
var _help_btn: Button = null

# ── 悬浮组件 (解构式 UI) ──
var _title_bubble: PanelContainer = null   # 悬浮标题气泡
var _side_container: VBoxContainer = null  # 侧边按钮组
var _connector: ColorRect = null           # 标题-面板连接线
var _restart_bubble: Button = null         # 悬浮重开按钮 (game over 后显示)
var _chrome_close_btn: Button = null       # 悬浮关闭按钮
var _chrome_side: int = 1                  # 按钮朝向 (1=右侧, -1=左侧)
var _chrome_dragging: bool = false
var _chrome_drag_offset: Vector2 = Vector2.ZERO

# ── 元数据 (子类覆写) ──

func get_game_id() -> String:
	return ""

func get_game_name() -> String:
	return ""

func get_game_desc() -> String:
	return ""

# ── 生命周期 (子类覆写) ──

## 启动游戏: 构建 UI (add_child 到 game_viewport)、初始化逻辑
func start() -> void:
	pass

## 清理资源: 移除所有 UI 节点、断开信号
func cleanup() -> void:
	_cleanup_chrome()
	_destroy_tutorial()

# ── 教程系统 (子类按需覆写) ──

## 覆写: 返回简报步骤。空数组 = 不显示简报按钮
## 格式: [{text: String}]
func get_tutorial_steps() -> Array[Dictionary]:
	return []

## 覆写: 返回预览动画 Control 节点 (可选, 显示在教程面板顶部)
func get_tutorial_preview() -> Control:
	return null

# ── 辅助方法 ──

## 同步 SubViewport 大小到面板内容 (面板 resized 时调用)
func sync_viewport_size() -> void:
	if not game_viewport or not game_container:
		return
	if game_viewport.get_child_count() > 0:
		var panel = game_viewport.get_child(0)
		if panel is Control:
			var s = panel.size
			game_viewport.size = Vector2i(s)
			game_container.custom_minimum_size = s
			game_container.size = s

# ══════════════════════════════════════════════
# 悬浮组件系统 (标题气泡 + 侧边按钮 + 连接线)
# ══════════════════════════════════════════════

## 创建悬浮组件 (游戏在面板构建完成、定位之后调用)
func _setup_floating_chrome(game_name: String, on_close: Callable, on_restart: Callable = Callable()) -> void:
	var parent = game_container.get_parent()
	if not parent:
		return
	var hue = EventBus.ui_hue

	# ── 标题气泡 ──
	_title_bubble = PanelContainer.new()
	var tb_bg = StyleBoxFlat.new()
	tb_bg.bg_color = Color(0.04, 0.06, 0.12, 0.92)
	tb_bg.border_color = Color.from_hsv(hue, 0.45, 0.85, 0.35)
	tb_bg.set_border_width_all(1)
	tb_bg.set_corner_radius_all(14)
	tb_bg.content_margin_left = 18
	tb_bg.content_margin_right = 18
	tb_bg.content_margin_top = 5
	tb_bg.content_margin_bottom = 5
	_title_bubble.add_theme_stylebox_override("panel", tb_bg)
	_title_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bubble.mouse_default_cursor_shape = Control.CURSOR_MOVE

	var title_label = Label.new()
	title_label.text = game_name
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color.from_hsv(hue, 0.4, 1.0, 0.9))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bubble.add_child(title_label)

	_title_bubble.gui_input.connect(_on_chrome_drag_input)
	parent.add_child(_title_bubble)

	# ── 连接线 ──
	_connector = ColorRect.new()
	_connector.color = Color.from_hsv(hue, 0.4, 0.8, 0.2)
	_connector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_connector)

	# ── 侧边按钮组 ──
	_side_container = VBoxContainer.new()
	_side_container.add_theme_constant_override("separation", 6)
	_side_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# i 按钮 (有教程内容时才创建)
	var steps = get_tutorial_steps()
	if not steps.is_empty():
		var info_btn = _create_chrome_button("i", false)
		info_btn.pressed.connect(_toggle_tutorial)
		_help_btn = info_btn
		_side_container.add_child(info_btn)
	# 关闭按钮
	_chrome_close_btn = _create_chrome_button("✕", true)
	_chrome_close_btn.pressed.connect(on_close)
	_side_container.add_child(_chrome_close_btn)
	parent.add_child(_side_container)

	# ── 重开按钮 (初始隐藏, game over 后显示) ──
	if on_restart.is_valid():
		_restart_bubble = _create_restart_bubble(on_restart)
		parent.add_child(_restart_bubble)
		_restart_bubble.hide()

	# 确定按钮朝向
	_chrome_side = _determine_chrome_side()

	# 等布局完成后定位 + 入场动画
	await parent.get_tree().process_frame
	_update_chrome_positions()
	_animate_chrome_in()

## 创建圆形悬浮按钮
func _create_chrome_button(text: String, is_close: bool) -> Button:
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
	normal_bg.set_corner_radius_all(15)  # 圆形
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

## 创建悬浮重开按钮 (pill 形状, 居中在面板下方)
func _create_restart_bubble(on_restart: Callable) -> Button:
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

## 显示悬浮重开按钮 (game over 后调用, 自动处理屏幕空间不足)
func _show_restart_bubble() -> void:
	if not is_instance_valid(_restart_bubble) or not is_instance_valid(game_container):
		return
	_restart_bubble.show()
	# 检查面板下方是否有足够空间放置按钮
	var gc_pos = game_container.position
	var gc_size = game_container.size
	var gap := 8.0
	var rb_h = maxf(_restart_bubble.size.y, _restart_bubble.custom_minimum_size.y)
	var needed_bottom = gc_pos.y + gc_size.y + gap + rb_h + gap
	if needed_bottom > screen_size.y:
		# 空间不足: 将面板整体上移腐出空间
		var shift = needed_bottom - screen_size.y
		game_container.position.y = maxf(gc_pos.y - shift, 8.0)
	_update_chrome_positions()
	# 弹入动画
	_restart_bubble.modulate.a = 0.0
	_restart_bubble.scale = Vector2(0.5, 0.5)
	_restart_bubble.pivot_offset = _restart_bubble.size / 2.0 if _restart_bubble.size.x > 1 else Vector2(50, 16)
	var tw = _restart_bubble.create_tween().set_parallel(true)
	tw.tween_property(_restart_bubble, "modulate:a", 1.0, 0.2)
	tw.tween_property(_restart_bubble, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 隐藏悬浮重开按钮 (重新开始时调用)
func _hide_restart_bubble() -> void:
	if is_instance_valid(_restart_bubble):
		_restart_bubble.hide()

## 判断按钮应该在面板哪一侧 (远离宠物)
func _determine_chrome_side() -> int:
	var pet_x = screen_size.x / 2.0
	if is_instance_valid(_pet):
		pet_x = _pet.get_global_transform_with_canvas().get_origin().x
	var panel_center_x = game_container.position.x + game_container.size.x / 2.0
	if panel_center_x > pet_x:
		return 1  # 面板在宠物右边 → 按钮在面板右侧 (更远离宠物)
	else:
		return -1  # 面板在宠物左边 → 按钮在面板左侧

## 同步悬浮组件位置 (面板移动时调用)
func _update_chrome_positions() -> void:
	if not is_instance_valid(game_container):
		return
	var gc_pos = game_container.position
	var gc_size = game_container.size
	var gap := 8.0

	# 标题气泡: 居中在面板上方
	if is_instance_valid(_title_bubble):
		var tb_size = _title_bubble.size
		var x = gc_pos.x + (gc_size.x - tb_size.x) / 2.0
		var y = gc_pos.y - tb_size.y - gap
		x = clampf(x, 8.0, screen_size.x - tb_size.x - 8.0)
		y = maxf(y, 8.0)
		_title_bubble.position = Vector2(x, y)

	# 连接线: 从标题底部到面板顶部
	if is_instance_valid(_connector) and is_instance_valid(_title_bubble):
		var tb_bottom = _title_bubble.position.y + _title_bubble.size.y
		var line_height = gc_pos.y - tb_bottom
		if line_height > 1:
			_connector.size = Vector2(1, line_height)
			_connector.position = Vector2(
				gc_pos.x + gc_size.x / 2.0,
				tb_bottom
			)
			_connector.show()
		else:
			_connector.hide()

	# 侧边按钮: 面板外侧顶部对齐
	if is_instance_valid(_side_container):
		var sc_size = _side_container.size
		var x: float
		if _chrome_side > 0:
			x = gc_pos.x + gc_size.x + gap
		else:
			x = gc_pos.x - sc_size.x - gap
		var y = gc_pos.y
		x = clampf(x, 8.0, screen_size.x - sc_size.x - 8.0)
		y = clampf(y, 8.0, screen_size.y - sc_size.y - 8.0)
		_side_container.position = Vector2(x, y)

	# 重开按钮: 居中在面板下方
	if is_instance_valid(_restart_bubble) and _restart_bubble.visible:
		var rb_size = _restart_bubble.size
		var rx = gc_pos.x + (gc_size.x - rb_size.x) / 2.0
		var ry = gc_pos.y + gc_size.y + gap
		rx = clampf(rx, 8.0, screen_size.x - rb_size.x - 8.0)
		ry = clampf(ry, 8.0, screen_size.y - rb_size.y - 8.0)
		_restart_bubble.position = Vector2(rx, ry)

	# 教程面板
	_position_tutorial()

## 标题气泡拖拽 → 带动整个面板移动
func _on_chrome_drag_input(event: InputEvent) -> void:
	if not is_instance_valid(game_container):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_chrome_dragging = true
			_chrome_drag_offset = game_container.get_viewport().get_mouse_position() - game_container.position
			EventBus.drag_started.emit()
		else:
			if _chrome_dragging:
				EventBus.drag_ended.emit()
			_chrome_dragging = false
	elif event is InputEventMouseMotion and _chrome_dragging:
		var vp = screen_size
		var new_pos = game_container.get_viewport().get_mouse_position() - _chrome_drag_offset
		new_pos.x = clampf(new_pos.x, 8.0, vp.x - game_container.size.x - 8.0)
		new_pos.y = clampf(new_pos.y, 8.0, vp.y - game_container.size.y - 8.0)
		game_container.position = new_pos
		_update_chrome_positions()

## 悬浮组件分层入场动画
func _animate_chrome_in() -> void:
	# 标题气泡: 从下方浮上 + 淡入
	if is_instance_valid(_title_bubble):
		var target_y = _title_bubble.position.y
		_title_bubble.position.y += 12
		_title_bubble.modulate.a = 0.0
		var tw = _title_bubble.create_tween().set_parallel(true)
		tw.tween_property(_title_bubble, "position:y", target_y, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.set_delay(0.12)
		tw.tween_property(_title_bubble, "modulate:a", 1.0, 0.2).set_delay(0.12)

	# 连接线: 淡入
	if is_instance_valid(_connector):
		_connector.modulate.a = 0.0
		var tw = _connector.create_tween()
		tw.tween_property(_connector, "modulate:a", 1.0, 0.2).set_delay(0.18)

	# 侧边按钮: 逐个弹出
	if is_instance_valid(_side_container):
		for i in range(_side_container.get_child_count()):
			var child = _side_container.get_child(i) as Control
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

## 悬浮组件退场动画
func _animate_chrome_out() -> void:
	for node in [_title_bubble, _side_container, _connector, _restart_bubble]:
		if is_instance_valid(node):
			var tw = node.create_tween()
			tw.tween_property(node, "modulate:a", 0.0, 0.12)

## 清理悬浮组件
func _cleanup_chrome() -> void:
	for node in [_title_bubble, _side_container, _connector, _restart_bubble]:
		if is_instance_valid(node):
			node.queue_free()
	_title_bubble = null
	_side_container = null
	_connector = null
	_restart_bubble = null
	_chrome_close_btn = null
	_help_btn = null

## 返回悬浮组件的屏幕矩形 (供 hit_region_manager 注册)
func get_chrome_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if is_instance_valid(_title_bubble):
		rects.append(Rect2(_title_bubble.position, _title_bubble.size))
	if is_instance_valid(_side_container):
		rects.append(Rect2(_side_container.position, _side_container.size))
	if is_instance_valid(_restart_bubble) and _restart_bubble.visible:
		rects.append(Rect2(_restart_bubble.position, _restart_bubble.size))
	return rects

# ══════════════════════════════════════════════
# 教程面板 (内部)
# ══════════════════════════════════════════════

func _toggle_tutorial() -> void:
	if _tutorial_visible:
		_hide_tutorial()
	else:
		_show_tutorial()

func _show_tutorial() -> void:
	if _tutorial_visible:
		return
	var steps = get_tutorial_steps()
	if steps.is_empty():
		return
	_tutorial_visible = true
	_build_tutorial_panel(steps)

	# 按钮高亮 (表示教程已展开)
	if _help_btn:
		_help_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 1.0, 0.9))

func _hide_tutorial() -> void:
	_tutorial_visible = false
	if _help_btn:
		_help_btn.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65, 0.7))
	if is_instance_valid(_tutorial_panel):
		var panel = _tutorial_panel
		_tutorial_panel = null
		var tween = panel.create_tween().set_parallel(true)
		tween.tween_property(panel, "modulate:a", 0.0, 0.15)
		tween.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.15)
		tween.finished.connect(func():
			if is_instance_valid(panel):
				panel.queue_free()
		)

func _destroy_tutorial() -> void:
	_tutorial_visible = false
	if is_instance_valid(_tutorial_panel):
		_tutorial_panel.queue_free()
		_tutorial_panel = null

func _build_tutorial_panel(steps: Array[Dictionary]) -> void:
	var hue = EventBus.ui_hue
	_tutorial_panel = PanelContainer.new()
	_tutorial_panel.custom_minimum_size = Vector2(200, 0)

	# 面板背景 (同游戏面板风格，略透明)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.12, 0.92)
	bg.border_color = Color.from_hsv(hue, 0.4, 0.7, 0.3)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 12
	bg.content_margin_right = 12
	bg.content_margin_top = 10
	bg.content_margin_bottom = 10
	_tutorial_panel.add_theme_stylebox_override("panel", bg)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_panel.add_child(vbox)

	# 标题
	var title_label = Label.new()
	title_label.text = "任务简报"
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color.from_hsv(hue, 0.4, 1.0, 0.85))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_label)

	# 分割线
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = Color.from_hsv(hue, 0.5, 0.7, 0.15)
	sep_style.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", sep_style)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# 可选: 预览动画区
	var preview = get_tutorial_preview()
	if preview:
		var preview_wrapper = PanelContainer.new()
		var preview_bg = StyleBoxFlat.new()
		preview_bg.bg_color = Color(0.03, 0.05, 0.10, 0.7)
		preview_bg.set_corner_radius_all(6)
		preview_bg.set_content_margin_all(4)
		preview_wrapper.add_theme_stylebox_override("panel", preview_bg)
		preview_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_wrapper.add_child(preview)
		vbox.add_child(preview_wrapper)

	# 教程步骤
	for i in range(steps.size()):
		var step = steps[i]
		var step_hbox = HBoxContainer.new()
		step_hbox.add_theme_constant_override("separation", 6)
		step_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# 序号圆点
		var num_label = Label.new()
		num_label.text = str(i + 1)
		num_label.add_theme_font_size_override("font_size", 11)
		num_label.add_theme_color_override("font_color", Color.from_hsv(hue, 0.4, 0.9, 0.6))
		num_label.custom_minimum_size = Vector2(14, 0)
		num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		step_hbox.add_child(num_label)

		# 步骤文字
		var text_label = Label.new()
		text_label.text = step.get("text", "")
		text_label.add_theme_font_size_override("font_size", 12)
		text_label.add_theme_color_override("font_color", Color(0.6, 0.72, 0.85, 0.9))
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		step_hbox.add_child(text_label)

		vbox.add_child(step_hbox)

	# 添加到屏幕层 (不进 SubViewport, 不会显示在全息屏上)
	var parent = game_container.get_parent()
	if parent:
		parent.add_child(_tutorial_panel)

	# 定位 (游戏面板的外侧)
	await _tutorial_panel.get_tree().process_frame
	_position_tutorial()

	# 弹入动画
	_tutorial_panel.modulate.a = 0.0
	_tutorial_panel.scale = Vector2(0.85, 0.85)
	_tutorial_panel.pivot_offset = _tutorial_panel.size / 2.0
	var tween = _tutorial_panel.create_tween().set_parallel(true)
	tween.tween_property(_tutorial_panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(_tutorial_panel, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _position_tutorial() -> void:
	if not is_instance_valid(_tutorial_panel) or not is_instance_valid(game_container):
		return
	var gc_pos = game_container.position
	var gc_size = game_container.size
	var tp_size = _tutorial_panel.size
	var vp = screen_size
	var gap := 8.0

	# 优先放在游戏面板远离宠物的一侧
	var pet_x: float = vp.x / 2.0
	if is_instance_valid(_pet):
		pet_x = _pet.get_global_transform_with_canvas().get_origin().x

	var x: float
	if gc_pos.x + gc_size.x / 2.0 > pet_x:
		# 游戏面板在宠物右边 → 教程放游戏面板右边
		x = gc_pos.x + gc_size.x + gap
		# 如果有侧边按钮在右边，教程再往外推
		if _chrome_side > 0 and is_instance_valid(_side_container):
			x += _side_container.size.x + gap
	else:
		# 游戏面板在宠物左边 → 教程放游戏面板左边
		x = gc_pos.x - tp_size.x - gap
		if _chrome_side < 0 and is_instance_valid(_side_container):
			x -= _side_container.size.x + gap

	# Y: 顶部对齐游戏面板
	var y = gc_pos.y

	# 边界保护
	x = clampf(x, 8.0, vp.x - tp_size.x - 8.0)
	y = clampf(y, 8.0, vp.y - tp_size.y - 8.0)

	# 如果放不下 (被挤出屏幕), 叠在游戏面板上方
	if x < 8.0 or x + tp_size.x > vp.x - 8.0:
		x = gc_pos.x
		y = gc_pos.y - tp_size.y - gap
		y = clampf(y, 8.0, vp.y - tp_size.y - 8.0)

	_tutorial_panel.position = Vector2(x, y)

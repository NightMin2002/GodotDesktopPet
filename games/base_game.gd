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
	_destroy_tutorial()

# ── 教程系统 (子类按需覆写) ──

## 覆写: 返回教程步骤。空数组 = 不显示教程按钮
## 格式: [{text: String}]
func get_tutorial_steps() -> Array[Dictionary]:
	return []

## 覆写: 返回预览动画 Control 节点 (可选, 显示在教程面板顶部)
func get_tutorial_preview() -> Control:
	return null

## 创建 "?" 帮助按钮 (游戏在 _build_ui 时添加到标题栏)
## 如果没有教程内容则返回 null
func create_help_button() -> Button:
	var steps = get_tutorial_steps()
	if steps.is_empty():
		return null
	_help_btn = Button.new()
	_help_btn.text = "?"
	_help_btn.custom_minimum_size = Vector2(26, 26)
	_help_btn.add_theme_font_size_override("font_size", 13)
	_help_btn.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65, 0.7))
	_help_btn.add_theme_color_override("font_hover_color", Color.from_hsv(EventBus.ui_hue, 0.5, 1.0, 1.0))
	_help_btn.add_theme_color_override("font_pressed_color", Color.from_hsv(EventBus.ui_hue, 0.6, 1.0, 1.0))
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.08, 0.10, 0.18, 0.6)
	btn_normal.set_corner_radius_all(6)
	btn_normal.set_content_margin_all(0)
	var btn_hover = StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.10, 0.14, 0.25, 0.8)
	btn_hover.set_corner_radius_all(6)
	btn_hover.set_content_margin_all(0)
	_help_btn.add_theme_stylebox_override("normal", btn_normal)
	_help_btn.add_theme_stylebox_override("hover", btn_hover)
	_help_btn.add_theme_stylebox_override("pressed", btn_hover)
	_help_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_help_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_help_btn.pressed.connect(_toggle_tutorial)
	return _help_btn

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
	title_label.text = "操作指南"
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
	var gap := 8.0  # 面板间距

	# 优先放在游戏面板远离宠物的一侧
	var pet_x: float = vp.x / 2.0
	if is_instance_valid(_pet):
		pet_x = _pet.get_global_transform_with_canvas().get_origin().x

	var x: float
	if gc_pos.x + gc_size.x / 2.0 > pet_x:
		# 游戏面板在宠物右边 → 教程放游戏面板右边
		x = gc_pos.x + gc_size.x + gap
	else:
		# 游戏面板在宠物左边 → 教程放游戏面板左边
		x = gc_pos.x - tp_size.x - gap

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

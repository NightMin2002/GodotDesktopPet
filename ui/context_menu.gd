# context_menu.gd — 右键全息追踪面板

# 管理: 设置开关 (持久化) + 开机自启动 + 提醒管理入口

extends CanvasLayer

const InfoSidebar = preload("res://ui/context_menu/info_sidebar.gd")

const SysinfoBubble = preload("res://ui/context_menu/sysinfo_bubble.gd")

const MenuTooltip = preload("res://ui/context_menu/menu_tooltip.gd")

const SectionStyler = preload("res://ui/context_menu/section_styler.gd")

const SubmenuSystem = preload("res://ui/context_menu/submenu_system.gd")

@onready var hud: PanelContainer = $HUDPanel

@onready var track_btn: Button = $HUDPanel/Margin/VBox/EyeTrackBtn

@onready var hud_btn: Button = $HUDPanel/Margin/VBox/HudBtn

@onready var autostart_btn: Button = $HUDPanel/Margin/VBox/AutoStartBtn

@onready var window_mode_btn: Button = $HUDPanel/Margin/VBox/WindowModeBtn

@onready var behavior_mode_btn: Button = $HUDPanel/Margin/VBox/BehaviorModeBtn

@onready var gait_btn: Button = $HUDPanel/Margin/VBox/GaitBtn

@onready var effects_btn: Button = $HUDPanel/Margin/VBox/EffectsBtn

@onready var theme_btn: Button = $HUDPanel/Margin/VBox/ThemeBtn

@onready var entertain_btn: Button = $HUDPanel/Margin/VBox/EntertainBtn

@onready var mode_btn: Button = $HUDPanel/Margin/VBox/ModeBtn

@onready var chatter_btn: Button = $HUDPanel/Margin/VBox/ChatterBtn

@onready var reminder_btn: Button = $HUDPanel/Margin/VBox/ReminderBtn

@onready var clone_btn: Button = $HUDPanel/Margin/VBox/CloneBtn

@onready var dismiss_btn: Button = $HUDPanel/Margin/VBox/DismissBtn

@onready var sysinfo_btn: Button = $HUDPanel/Margin/VBox/SysInfoBtn

@onready var debug_behavior_btn: Button = $HUDPanel/Margin/VBox/DebugBehaviorBtn

@onready var quit_btn: Button = $HUDPanel/Margin/VBox/QuitBtn

var _submenu: SubmenuSystem

# 信息侧栏

var _sidebar: InfoSidebar

var _sysinfo_bubble: SysinfoBubble

var _tooltip: MenuTooltip

var _styler: SectionStyler

var target: Node2D = null

func _ready() -> void:

	hud.hide()

	_sidebar = InfoSidebar.new(self)

	_sidebar.build()

	_sysinfo_bubble = SysinfoBubble.new(self)

	_tooltip = MenuTooltip.new(self)

	_tooltip.build()

	_submenu = SubmenuSystem.new(self)

	_build_submenus()

	_styler = SectionStyler.new(self)

	_styler.style_headers(hud, _submenu.panels)

	# 胶囊按钮样式: 面板入口 + 危险操作
	_apply_capsule_style(theme_btn, Color(0.12, 0.22, 0.42, 0.7), Color(0.4, 0.6, 0.9, 0.5))
	_apply_capsule_style(reminder_btn, Color(0.12, 0.22, 0.42, 0.7), Color(0.4, 0.6, 0.9, 0.5))
	_apply_capsule_style(quit_btn, Color(0.35, 0.1, 0.1, 0.65), Color(0.8, 0.3, 0.3, 0.5))

	# 从持久化存储恢复上次的设置状态

	_load_saved_settings()

	# UI 主题色: 启动时应用 + 运行时监听
	_apply_ui_theme(EventBus.ui_hue)
	EventBus.ui_theme_changed.connect(_apply_ui_theme)

	EventBus.show_context_menu.connect(_on_show_context_menu)

	track_btn.pressed.connect(_on_track_btn_pressed)

	hud_btn.mouse_entered.connect(func(): _submenu.on_trigger_hover("hud"))

	hud_btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())

	hud_btn.pressed.connect(func(): _submenu.toggle("hud"))

	chatter_btn.mouse_entered.connect(func(): _submenu.on_trigger_hover("chatter"))

	chatter_btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())

	chatter_btn.pressed.connect(func(): _submenu.toggle("chatter"))

	# 模式子菜单触发器

	window_mode_btn.mouse_entered.connect(func(): _submenu.on_trigger_hover("window_mode"))

	window_mode_btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())

	window_mode_btn.pressed.connect(func(): _submenu.toggle("window_mode"))

	behavior_mode_btn.mouse_entered.connect(func(): _submenu.on_trigger_hover("behavior_mode"))

	behavior_mode_btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())

	behavior_mode_btn.pressed.connect(func(): _submenu.toggle("behavior_mode"))

	gait_btn.mouse_entered.connect(func(): _submenu.on_trigger_hover("gait"))

	gait_btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())

	gait_btn.pressed.connect(func(): _submenu.toggle("gait"))

	# 功能子菜单触发器

	effects_btn.mouse_entered.connect(func(): _submenu.on_trigger_hover("effects"))

	effects_btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())

	effects_btn.pressed.connect(func(): _submenu.toggle("effects"))
	
	theme_btn.pressed.connect(func():
		# 立即隐藏菜单 + 补发 false 平衡引用计数
		_tooltip.panel.hide()
		_submenu.hide_all_instant()
		hud.hide()
		_sidebar.panel.hide()
		target = null
		EventBus.context_menu_toggled.emit(false)
		EventBus.show_theme_panel.emit()
	)

	entertain_btn.mouse_entered.connect(func(): _submenu.on_trigger_hover("entertain"))

	entertain_btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())

	entertain_btn.pressed.connect(func(): _submenu.toggle("entertain"))

	# 模式子菜单触发器

	mode_btn.mouse_entered.connect(func(): _submenu.on_trigger_hover("mode"))

	mode_btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())

	mode_btn.pressed.connect(func(): _submenu.toggle("mode"))

	reminder_btn.pressed.connect(_on_reminder_btn_pressed)

	clone_btn.pressed.connect(_on_clone_btn_pressed)

	dismiss_btn.pressed.connect(_on_dismiss_btn_pressed)

	sysinfo_btn.pressed.connect(_on_sysinfo_btn_pressed)

	autostart_btn.pressed.connect(_on_autostart_btn_pressed)

	# 调试子菜单触发器

	debug_behavior_btn.mouse_entered.connect(func(): _submenu.on_trigger_hover("debug_behavior"))

	debug_behavior_btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())

	debug_behavior_btn.pressed.connect(func(): _submenu.toggle("debug_behavior"))

	quit_btn.pressed.connect(_on_quit_btn_pressed)

	# 监听外部行为模式变化同步按钮状态

	EventBus.behavior_mode_changed.connect(_on_behavior_mode_synced)

# ── 持久化加载 ──

func _load_saved_settings() -> void:

	var eye = SettingsManager.get_bool("eye_track", true)

	# 应用到本地按钮显示 (pet 自己从 SettingsManager 读取，不依赖信号)

	_set_toggle(track_btn, eye, "眼球追踪 [●]", "眼球追踪 [○]")

	# 子菜单按钮状态初始化

	_refresh_submenu_states()

	# 窗口交互模式状态 (按钮文字 + 子菜单选中)

	var wm = SettingsManager.get_int("window_mode", 0)

	_update_window_mode_label(wm)

	_submenu.refresh_radio("window_mode", wm)

	# 行为指令状态 (按钮文字 + 子菜单选中)

	var bm = SettingsManager.get_int("behavior_mode", 0)

	_update_behavior_mode_label(bm)

	_submenu.refresh_radio("behavior_mode", bm)

	# 步态状态

	var gm = SettingsManager.get_int("move_style", 0)

	_update_gait_label(gm)

	_submenu.refresh_radio("gait", gm)

	# 宠物碎碎念模式

	var chatter_mode = SettingsManager.get_int("pet_chatter_mode", 1)

	_update_chatter_label(chatter_mode)

	_submenu.refresh_radio("chatter", chatter_mode)

	# 自启动状态延迟检测 (等 C# 节点就绪)

	_autostart_check_pending = true

var _autostart_check_pending := false

var _autostart_check_delay := 0.0

func _check_autostart_deferred(delta: float) -> void:

	if not _autostart_check_pending:

		return

	_autostart_check_delay += delta

	if _autostart_check_delay < 0.5:  # 等 0.5 秒让 C# 节点就绪

		return

	_autostart_check_pending = false

	var win_mgr = _get_win_manager()

	if win_mgr and win_mgr.has_method("IsAutoStartEnabled"):

		var on: bool = win_mgr.call("IsAutoStartEnabled")

		_set_toggle(autostart_btn, on, "开机自启动 [●]", "开机自启动 [○]")

	else:

		autostart_btn.text = "开机自启动 [○]"

# ── 弹性追踪 (含边界钳制) ──

func _process(delta: float) -> void:

	_check_autostart_deferred(delta)

	if hud.visible and is_instance_valid(target):

		var target_pos = _calc_menu_pos(target.get_global_transform_with_canvas().get_origin())

		hud.position = hud.position.lerp(target_pos, delta * 15.0)

		# 信息栏跟随主菜单 + 实时时钟

		_sidebar.update_position(hud)

		_sidebar.update_time()

		_sidebar.update_uptime()

		# 侧栏异步结果

		if _sidebar.has_pending():

			_sidebar.apply_pending()

		# 子菜单跟随主菜单

		if _submenu.active != "":

			_submenu.update_position(_submenu.active)

		# 子菜单跟随主菜单

		if _submenu.active != "":

			_submenu.update_position(_submenu.active)

	_sysinfo_bubble.process_tick()

	# tooltip 跟随按钮位置

	if _tooltip.panel.visible:

		_tooltip.update_position()

	_submenu.process_timers(delta)

func _clamp_to_viewport(pos: Vector2) -> Vector2:

	var vp = get_viewport().get_visible_rect().size

	var hs = hud.size

	pos.x = clampf(pos.x, 4.0, vp.x - hs.x - 4.0)

	pos.y = clampf(pos.y, 4.0, vp.y - hs.y - 4.0)

	return pos

## 智能菜单定位: 根据宠物屏幕位置选择弹出方向

func _calc_menu_pos(pet_pos: Vector2) -> Vector2:

	var vp = get_viewport().get_visible_rect().size

	var hs = hud.size if hud.size.x > 0 else Vector2(200, 400)

	var gap := 45.0  # 宠物与面板间距

	# 水平: 宠物在右半屏 → 面板弹到左边

	var x: float

	if pet_pos.x > vp.x * 0.5:

		x = pet_pos.x - hs.x - gap

	else:

		x = pet_pos.x + gap

	# 垂直: 宠物在下半屏 → 面板弹到上方，否则下方

	var y: float

	if pet_pos.y > vp.y * 0.5:

		y = pet_pos.y - hs.y + 20.0  # 上方，底部对齐宠物附近

	else:

		y = pet_pos.y - 20.0  # 下方，顶部对齐宠物附近

	# 边界钳制

	x = clampf(x, 4.0, vp.x - hs.x - 4.0)

	y = clampf(y, 4.0, vp.y - hs.y - 4.0)

	return Vector2(x, y)

# ── 菜单开关 ──

func _on_show_context_menu(target_node: Node2D) -> void:

	target = target_node

	if hud.visible:

		_close_hud()

		return

	EventBus.context_menu_toggled.emit(true)

	_update_clone_label()

	var pet_pos = target.get_global_transform_with_canvas().get_origin()

	var panel_pos = _calc_menu_pos(pet_pos)

	hud.position = panel_pos

	hud.modulate.a = 0.0

	hud.show()

	# 信息栏同步展开

	_sidebar.refresh()

	_sidebar.panel.modulate.a = 0.0

	_sidebar.panel.show()

	_sidebar.update_position(hud)

	# 异步查询 WiFi

	_sidebar.query()

	# 等待一帧让布局计算出 size，再设缩放锚点
	await get_tree().process_frame
	# 二次 clamp: 布局计算出真实 size 后修正位置
	hud.position = _clamp_to_viewport(hud.position)
	_sidebar.update_position(hud)
	# 缩放锚点设在宠物相对于面板的位置 → 面板从宠物处绽放展开
	hud.pivot_offset = pet_pos - hud.position

	hud.scale = Vector2(0.3, 0.3)

	_sidebar.panel.pivot_offset = Vector2(_sidebar.panel.size.x, _sidebar.panel.size.y * 0.5)

	_sidebar.panel.scale = Vector2(0.3, 0.3)

	var tween = create_tween().set_parallel(true)

	tween.tween_property(hud, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

	tween.tween_property(hud, "modulate:a", 1.0, 0.2)

	tween.tween_property(_sidebar.panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

	tween.tween_property(_sidebar.panel, "modulate:a", 1.0, 0.25)

func _close_hud() -> void:

	_tooltip.panel.hide()

	_submenu.hide_all_instant()

	if is_instance_valid(target):

		hud.pivot_offset = target.get_global_transform_with_canvas().get_origin() - hud.position

	var tween = create_tween().set_parallel(true)

	tween.tween_property(hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	tween.tween_property(hud, "modulate:a", 0.0, 0.15)

	tween.tween_property(_sidebar.panel, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	tween.tween_property(_sidebar.panel, "modulate:a", 0.0, 0.15)

	tween.finished.connect(func():

		hud.hide()

		_sidebar.panel.hide()

		EventBus.context_menu_toggled.emit(false)

	)

	target = null

# ── 按钮回调 ──

func _on_track_btn_pressed() -> void:

	var on = _flip_toggle(track_btn, "眼球追踪 [●]", "眼球追踪 [○]")

	SettingsManager.set_bool("eye_track", on)

	EventBus.setting_toggled.emit("eye_track", on)

func _on_autostart_btn_pressed() -> void:

	var win_mgr = _get_win_manager()

	if not win_mgr or not win_mgr.has_method("SetAutoStart"):

		return

	var current: bool = win_mgr.call("IsAutoStartEnabled")

	var new_val = not current

	win_mgr.call("SetAutoStart", new_val)

	_set_toggle(autostart_btn, new_val, "开机自启动 [●]", "开机自启动 [○]")

const CHATTER_MODE_LABELS := ["碎碎念 · 已关闭 [+]", "碎碎念 · 每30分钟 [+]", "碎碎念 · 每60分钟 [+]"]

func _on_radio_chatter_mode(value: int) -> void:

	_update_chatter_label(value)

	SettingsManager.set_int("pet_chatter_mode", value)

	EventBus.setting_toggled.emit("pet_chatter_mode", value > 0)

	_submenu.refresh_radio("chatter", value)

func _update_chatter_label(mode: int) -> void:

	chatter_btn.text = CHATTER_MODE_LABELS[mode]

func _on_reminder_btn_pressed() -> void:

	# 立即隐藏菜单 + 补发 false 平衡引用计数
	_tooltip.panel.hide()
	_submenu.hide_all_instant()
	hud.hide()
	_sidebar.panel.hide()
	target = null
	EventBus.context_menu_toggled.emit(false)

	EventBus.show_reminder_panel.emit()

# ── 克隆系统 ──

func _on_clone_btn_pressed() -> void:

	if is_instance_valid(target):

		EventBus.clone_pet.emit(target)

	# 延迟一帧更新计数

	await get_tree().process_frame

	_update_clone_label()

func _on_dismiss_btn_pressed() -> void:

	EventBus.dismiss_clones.emit()

	_close_hud()

func _update_clone_label() -> void:

	var main_node = get_tree().root.get_node_or_null("Main")

	if main_node and "pet_instances" in main_node:

		var count: int = (main_node.pet_instances as Array).size() - 1

		var max_c: int = main_node.clone_mgr.MAX_CLONES if main_node.clone_mgr else 5

		clone_btn.text = "召唤分身 (" + str(count) + "/" + str(max_c) + ")"

# ── 退出按钮 ──

func _on_quit_btn_pressed() -> void:

	_tooltip.panel.hide()

	if is_instance_valid(target):

		hud.pivot_offset = target.get_global_transform_with_canvas().get_origin() - hud.position

	var tween = create_tween().set_parallel(true)

	tween.tween_property(hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	tween.tween_property(hud, "modulate:a", 0.0, 0.15)

	tween.tween_property(_sidebar.panel, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	tween.tween_property(_sidebar.panel, "modulate:a", 0.0, 0.15)

	tween.finished.connect(func():

		hud.hide()

		_sidebar.panel.hide()

		EventBus.context_menu_toggled.emit(false)

	)

	target = null

	# 调用 main.gd 的告别退出

	var main_node = get_tree().root.get_node_or_null("Main")

	if main_node and main_node.has_method("quit_with_farewell"):

		main_node.quit_with_farewell()

	else:

		get_tree().quit()

# ── 窗口模式 (子菜单单选回调) ──

const WINDOW_MODE_LABELS := ["窗口 · 自由漫游 [+]", "窗口 · 窗口封闭 [+]", "窗口 · 窗口排斥 [+]"]

func _on_radio_window_mode(value: int) -> void:

	_update_window_mode_label(value)

	EventBus.window_mode_changed.emit(value)

	_submenu.refresh_radio("window_mode", value)

func _update_window_mode_label(mode: int) -> void:

	window_mode_btn.text = WINDOW_MODE_LABELS[mode]

# ── 行为指令 (子菜单单选回调) ──

const BEHAVIOR_MODE_LABELS := ["指令 · 自由行动 [+]", "指令 · 安静待命 [+]"]

func _on_radio_behavior_mode(value: int) -> void:

	_update_behavior_mode_label(value)

	EventBus.behavior_mode_changed.emit(value)

	_submenu.refresh_radio("behavior_mode", value)

func _update_behavior_mode_label(mode: int) -> void:

	behavior_mode_btn.text = BEHAVIOR_MODE_LABELS[mode]

func _on_behavior_mode_synced(mode: int) -> void:

	_update_behavior_mode_label(mode)

	_submenu.refresh_radio("behavior_mode", mode)

# ── 步态 (子菜单单选回调) ──

const GAIT_LABELS := ["步态 · 蹦跳为主 [+]", "步态 · 滚动为主 [+]", "步态 · 混合平衡 [+]"]

func _on_radio_gait(value: int) -> void:

	_update_gait_label(value)

	SettingsManager.set_int("move_style", value)

	EventBus.setting_toggled.emit("move_style", value > 0)

	_submenu.refresh_radio("gait", value)

func _update_gait_label(mode: int) -> void:

	gait_btn.text = GAIT_LABELS[mode]

# ── 特效配色 ──

var _effect_color_btns: Array[Button] = []

## 在 effects 面板的 VBox 中追加配色单选按钮
func _append_effect_color_radio() -> void:
	var effects_panel = _submenu.panels.get("effects")
	if not effects_panel:
		return
	var vbox = effects_panel.get_child(0)  # VBoxContainer
	
	# 分割线
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 3)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)
	
	# 配色标题
	var label = Label.new()
	label.text = "特效配色"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75, 0.5))
	vbox.add_child(label)
	
	# 单选按钮
	var saved = SettingsManager.get_int("effect_color_mode", 0)
	var labels = ["虹彩模式", "跟随体色"]
	_effect_color_btns.clear()
	for i in range(2):
		var btn = Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.1, 1, 0.9, 1))
		btn.text = labels[i] + (" [●]" if i == saved else " [○]")
		var val = i
		btn.pressed.connect(func(): _on_radio_effect_color(val))
		vbox.add_child(btn)
		_effect_color_btns.append(btn)

func _on_radio_effect_color(value: int) -> void:
	SettingsManager.set_int("effect_color_mode", value)
	EventBus.setting_toggled.emit("effect_color_mode", value > 0)
	# 刷新单选按钮显示
	var labels = ["虹彩模式", "跟随体色"]
	for i in range(_effect_color_btns.size()):
		_effect_color_btns[i].text = labels[i] + (" [●]" if i == value else " [○]")

# ── 工具函数 ──

## 胶囊按钮样式: 半透明背景 + 细边框 + 圆角, 用于面板入口和危险操作
func _apply_capsule_style(btn: Button, bg_color: Color, border_color: Color) -> void:
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.border_color = border_color
	style_normal.set_border_width_all(1)
	style_normal.set_corner_radius_all(8)
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12
	style_normal.content_margin_top = 4
	style_normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", style_normal)
	# hover 态: 略微提亮
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(bg_color.r + 0.06, bg_color.g + 0.06, bg_color.b + 0.06, bg_color.a + 0.15)
	style_hover.border_color = Color(border_color.r, border_color.g, border_color.b, border_color.a + 0.3)
	btn.add_theme_stylebox_override("hover", style_hover)
	# pressed 态
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(bg_color.r + 0.03, bg_color.g + 0.03, bg_color.b + 0.03, bg_color.a + 0.1)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	# 文字居中
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 必须关闭 flat, 否则 Godot 不绘制 normal 态 StyleBox 背景
	btn.flat = false

func _set_toggle(btn: Button, is_on: bool, on_text: String, off_text: String) -> void:

	btn.text = on_text if is_on else off_text

func _flip_toggle(btn: Button, on_text: String, off_text: String) -> bool:
	var is_on = btn.text.ends_with("[●]")
	var new_val = not is_on
	_set_toggle(btn, new_val, on_text, off_text)
	return new_val

func _get_win_manager() -> Node:

	var main_node = get_tree().root.get_node_or_null("Main")

	if main_node:

		for child in main_node.get_children():

			if child.get_class() == "WindowsManager" or child.has_method("IsAutoStartEnabled"):

				return child

	return null

# ── 外部点击关闭 ──

func _unhandled_input(event: InputEvent) -> void:

	if hud.visible and event is InputEventMouseButton and event.pressed:

		var local_mouse = hud.get_local_mouse_position()

		var rect = Rect2(Vector2.ZERO, hud.size)

		var in_hud = rect.has_point(local_mouse)

		# 检测是否点击在子菜单内

		var in_submenu = false

		for panel in _submenu.panels.values():

			if panel.visible:

				var sm_local = panel.get_local_mouse_position()

				if Rect2(Vector2.ZERO, panel.size).has_point(sm_local):

					in_submenu = true

					break

		if not in_hud and not in_submenu:

			_close_hud()

			get_viewport().set_input_as_handled()

# ── 级联子菜单系统 ──

## 创建所有子菜单面板 (委托到 SubmenuSystem)
func _build_submenus() -> void:
	# 注册触发按钮映射
	_submenu.register_trigger("window_mode", window_mode_btn)
	_submenu.register_trigger("behavior_mode", behavior_mode_btn)
	_submenu.register_trigger("effects", effects_btn)
	_submenu.register_trigger("entertain", entertain_btn)
	_submenu.register_trigger("mode", mode_btn)
	_submenu.register_trigger("gait", gait_btn)
	_submenu.register_trigger("hud", hud_btn)
	_submenu.register_trigger("chatter", chatter_btn)
	_submenu.register_trigger("debug_behavior", debug_behavior_btn)
	# 单选子菜单
	_submenu.create_radio("window_mode", [
		{"value": 0, "label": "自由漫游", "desc": "在窗口间自由行走"},
		{"value": 1, "label": "窗口封闭", "desc": "被困在当前窗口内"},
		{"value": 2, "label": "窗口排斥", "desc": "无法进入任何窗口"},
	], _on_radio_window_mode)
	_submenu.create_radio("behavior_mode", [
		{"value": 0, "label": "自由行动", "desc": "活力满满，随意滚动跳跃"},
		{"value": 1, "label": "安静待命", "desc": "安安静静，乖乖不动"},
	], _on_radio_behavior_mode)
	_submenu.create_radio("gait", [
		{"value": 0, "label": "蹦跳为主", "desc": "纯蹦跳移动，不会滚动"},
		{"value": 1, "label": "滚动为主", "desc": "纯滚动移动，不会跳跃"},
		{"value": 2, "label": "混合平衡", "desc": "蹦跳和滚动各半，动静结合"},
	], _on_radio_gait)
	_submenu.create_radio("chatter", [
		{"value": 0, "label": "关闭", "desc": "宠物不会主动说话"},
		{"value": 1, "label": "每30分钟", "desc": "每到整点和半点，冒泡说点什么"},
		{"value": 2, "label": "每60分钟", "desc": "每到整点，冒泡说点什么"},
	], _on_radio_chatter_mode)
	# 开关子菜单
	_submenu.create_toggle("effects", [
		{"id": "shockwave", "on": "撞击冲击波 [●]", "off": "撞击冲击波 [○]", "key": "shockwave", "default": true},
		{"id": "trail_fx", "on": "粒子尾流 [●]", "off": "粒子尾流 [○]", "key": "trail_fx", "default": true},
		{"id": "arc_fx", "on": "能量共鸣弧 [●]", "off": "能量共鸣弧 [○]", "key": "arc_fx", "default": true},
	])
	# 在 effects 面板中追加特效配色单选 (共用同一面板)
	_append_effect_color_radio()
	_submenu.create_toggle("entertain", [
		{"id": "stroll", "on": "自主巡航 [●]", "off": "自主巡航 [○]", "key": "stroll", "default": true},
	])
	_submenu.create_toggle("mode", [
		{"id": "anti_gravity", "on": "反重力 [●]", "off": "反重力 [○]", "key": "anti_gravity", "default": false},
	])
	_submenu.create_toggle("hud", [
		{"id": "hud_pin", "on": "常驻显示 [●]", "off": "常驻显示 [○]", "key": "hud_pin", "default": false},
		{"id": "hud_clock", "on": "系统时钟 [●]", "off": "系统时钟 [○]", "key": "hud_clock", "default": false},
		{"id": "hud_wifi", "on": "WiFi 信息 [●]", "off": "WiFi 信息 [○]", "key": "hud_wifi", "default": false},
	])
	# 调试子菜单: 行为测试 (直接触发 idle 微行为)
	_build_debug_behavior_submenu()

## 从 SettingsManager 刷新子菜单状态
func _refresh_submenu_states() -> void:
	_submenu.refresh_toggle("shockwave", SettingsManager.get_bool("shockwave", true), "撞击冲击波 [●]", "撞击冲击波 [○]")
	_submenu.refresh_toggle("trail_fx", SettingsManager.get_bool("trail_fx", true), "粒子尾流 [●]", "粒子尾流 [○]")
	_submenu.refresh_toggle("arc_fx", SettingsManager.get_bool("arc_fx", true), "能量共鸣弧 [●]", "能量共鸣弧 [○]")
	_submenu.refresh_toggle("stroll", SettingsManager.get_bool("stroll", true), "自主巡航 [●]", "自主巡航 [○]")
	_submenu.refresh_toggle("anti_gravity", SettingsManager.get_bool("anti_gravity", false), "反重力 [●]", "反重力 [○]")
	_submenu.refresh_toggle("hud_pin", SettingsManager.get_bool("hud_pin", false), "常驻显示 [●]", "常驻显示 [○]")
	_submenu.refresh_toggle("hud_clock", SettingsManager.get_bool("hud_clock", false), "系统时钟 [●]", "系统时钟 [○]")
	_submenu.refresh_toggle("hud_wifi", SettingsManager.get_bool("hud_wifi", false), "WiFi 信息 [●]", "WiFi 信息 [○]")

func _on_sysinfo_btn_pressed() -> void:

	_close_hud()

	_sysinfo_bubble.trigger()

## UI 主题色应用: 更新 HUD 面板边框 + 传递给子系统
func _apply_ui_theme(hue: float) -> void:
	var style = hud.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style = style.duplicate()
		style.border_color = Color.from_hsv(hue, 0.8, 1.0, 1.0)
		hud.add_theme_stylebox_override("panel", style)
	# 通知子菜单系统
	if _submenu and _submenu.has_method("apply_ui_theme"):
		_submenu.apply_ui_theme(hue)
	# 通知侧栏
	if _sidebar and _sidebar.has_method("apply_ui_theme"):
		_sidebar.apply_ui_theme(hue)

# ── 调试: 行为测试子菜单 ──

func _build_debug_behavior_submenu() -> void:
	var panel = _submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	
	var debug_items := [
		{"label": "休眠: 挡板半闭", "behavior": "hibernate:0", "desc": "机械眼睑半闭 + 瞳孔下垂"},
		{"label": "休眠: 加载指示", "behavior": "hibernate:1", "desc": "旋转弧线指示器，像设备待机"},
		{"label": "休眠: 电池图标", "behavior": "hibernate:2", "desc": "电池轮廓 + 脉冲充电条"},
		{"label": "系统自检", "behavior": "scan", "desc": "瞳孔快速左右扫描"},
	]
	
	for item in debug_items:
		var btn = Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.2, 1))
		btn.text = item.label
		var behavior_id = item.behavior
		btn.pressed.connect(func(): _on_debug_behavior_pressed(behavior_id))
		if item.has("desc"):
			var desc_text = item.desc
			var b = btn
			btn.mouse_entered.connect(func(): _tooltip.show_for(b, desc_text, true))
			btn.mouse_exited.connect(func(): _tooltip.show_for(b, desc_text, false))
		vbox.add_child(btn)
	
	panel.mouse_entered.connect(func(): _submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): _submenu.on_panel_exit())
	add_child(panel)
	_submenu.panels["debug_behavior"] = panel

func _on_debug_behavior_pressed(behavior: String) -> void:
	# 关闭菜单后触发行为
	_tooltip.panel.hide()
	_submenu.hide_all_instant()
	hud.hide()
	_sidebar.panel.hide()
	target = null
	EventBus.context_menu_toggled.emit(false)
	# 延迟一帧让菜单关闭完毕
	await get_tree().process_frame
	EventBus.trigger_idle_behavior.emit(behavior)

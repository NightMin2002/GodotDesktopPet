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

@onready var effects_btn: Button = $HUDPanel/Margin/VBox/EffectsBtn

@onready var entertain_btn: Button = $HUDPanel/Margin/VBox/EntertainBtn

@onready var mode_btn: Button = $HUDPanel/Margin/VBox/ModeBtn

@onready var chatter_btn: Button = $HUDPanel/Margin/VBox/ChatterBtn

@onready var reminder_btn: Button = $HUDPanel/Margin/VBox/ReminderBtn

@onready var clone_btn: Button = $HUDPanel/Margin/VBox/CloneBtn

@onready var dismiss_btn: Button = $HUDPanel/Margin/VBox/DismissBtn

@onready var sysinfo_btn: Button = $HUDPanel/Margin/VBox/SysInfoBtn

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

	# 从持久化存储恢复上次的设置状态

	_load_saved_settings()

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

	# 功能子菜单触发器

	effects_btn.mouse_entered.connect(func(): _submenu.on_trigger_hover("effects"))

	effects_btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())

	effects_btn.pressed.connect(func(): _submenu.toggle("effects"))

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

	quit_btn.pressed.connect(_on_quit_btn_pressed)

	# 监听外部行为模式变化同步按钮状态

	EventBus.behavior_mode_changed.connect(_on_behavior_mode_synced)

# ── 持久化加载 ──

func _load_saved_settings() -> void:

	var eye = SettingsManager.get_bool("eye_track", true)

	var clock = SettingsManager.get_bool("hud_clock", false)

	# 应用到本地按钮显示 (pet 自己从 SettingsManager 读取，不依赖信号)

	_set_toggle(track_btn, eye, "◉ 眼球追踪", "○ 眼球追踪")

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

		_set_toggle(autostart_btn, on, "◉ 开机自启动", "○ 开机自启动")

	else:

		autostart_btn.text = "○ 开机自启动"

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

	var on = _flip_toggle(track_btn, "◉ 眼球追踪", "○ 眼球追踪")

	SettingsManager.set_bool("eye_track", on)

	EventBus.setting_toggled.emit("eye_track", on)

func _on_autostart_btn_pressed() -> void:

	var win_mgr = _get_win_manager()

	if not win_mgr or not win_mgr.has_method("SetAutoStart"):

		return

	var current: bool = win_mgr.call("IsAutoStartEnabled")

	var new_val = not current

	win_mgr.call("SetAutoStart", new_val)

	_set_toggle(autostart_btn, new_val, "◉ 开机自启动", "○ 开机自启动")

const CHATTER_MODE_LABELS := ["碎碎念 · 已关闭 ▸", "碎碎念 · 每30分钟 ▸", "碎碎念 · 每60分钟 ▸"]

func _on_radio_chatter_mode(value: int) -> void:

	_update_chatter_label(value)

	SettingsManager.set_int("pet_chatter_mode", value)

	EventBus.setting_toggled.emit("pet_chatter_mode", value > 0)

	_submenu.refresh_radio("chatter", value)

func _update_chatter_label(mode: int) -> void:

	chatter_btn.text = CHATTER_MODE_LABELS[mode]

func _on_reminder_btn_pressed() -> void:

	_tooltip.panel.hide()

	if is_instance_valid(target):

		hud.pivot_offset = target.get_global_transform_with_canvas().get_origin() - hud.position

	var tween = create_tween().set_parallel(true)

	tween.tween_property(hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	tween.tween_property(hud, "modulate:a", 0.0, 0.15)

	tween.finished.connect(func(): hud.hide())

	target = null

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

const WINDOW_MODE_LABELS := ["窗口 · 自由漫游 ▸", "窗口 · 窗口封闭 ▸", "窗口 · 窗口排斥 ▸"]

func _on_radio_window_mode(value: int) -> void:

	_update_window_mode_label(value)

	EventBus.window_mode_changed.emit(value)

	_submenu.refresh_radio("window_mode", value)

func _update_window_mode_label(mode: int) -> void:

	window_mode_btn.text = WINDOW_MODE_LABELS[mode]

# ── 行为指令 (子菜单单选回调) ──

const BEHAVIOR_MODE_LABELS := ["指令 · 自由行动 ▸", "指令 · 安静待命 ▸"]

func _on_radio_behavior_mode(value: int) -> void:

	_update_behavior_mode_label(value)

	EventBus.behavior_mode_changed.emit(value)

	_submenu.refresh_radio("behavior_mode", value)

func _update_behavior_mode_label(mode: int) -> void:

	behavior_mode_btn.text = BEHAVIOR_MODE_LABELS[mode]

func _on_behavior_mode_synced(mode: int) -> void:

	_update_behavior_mode_label(mode)

	_submenu.refresh_radio("behavior_mode", mode)

# ── 工具函数 ──

func _set_toggle(btn: Button, is_on: bool, on_text: String, off_text: String) -> void:

	btn.text = on_text if is_on else off_text

func _flip_toggle(btn: Button, on_text: String, off_text: String) -> bool:

	var is_on = btn.text.begins_with("◉")

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
	_submenu.register_trigger("hud", hud_btn)
	_submenu.register_trigger("chatter", chatter_btn)
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
	_submenu.create_radio("chatter", [
		{"value": 0, "label": "关闭", "desc": "宠物不会主动说话"},
		{"value": 1, "label": "每30分钟", "desc": "每到整点和半点，冒泡说点什么"},
		{"value": 2, "label": "每60分钟", "desc": "每到整点，冒泡说点什么"},
	], _on_radio_chatter_mode)
	# 开关子菜单
	_submenu.create_toggle("effects", [
		{"id": "shockwave", "on": "◉ 撞击冲击波", "off": "○ 撞击冲击波", "key": "shockwave", "default": true},
		{"id": "trail_fx", "on": "◉ 粒子尾流", "off": "○ 粒子尾流", "key": "trail_fx", "default": true},
	])
	_submenu.create_toggle("entertain", [
		{"id": "stroll", "on": "◉ 滚动散步", "off": "○ 滚动散步", "key": "stroll", "default": true},
	])
	_submenu.create_toggle("mode", [
		{"id": "anti_gravity", "on": "◉ 反重力", "off": "○ 反重力", "key": "anti_gravity", "default": false},
	])
	_submenu.create_toggle("hud", [
		{"id": "hud_clock", "on": "◉ 系统时钟", "off": "○ 系统时钟", "key": "hud_clock", "default": false},
		{"id": "hud_wifi", "on": "◉ WiFi 信息", "off": "○ WiFi 信息", "key": "hud_wifi", "default": false},
	])

## 从 SettingsManager 刷新子菜单状态
func _refresh_submenu_states() -> void:
	_submenu.refresh_toggle("shockwave", SettingsManager.get_bool("shockwave", true), "◉ 撞击冲击波", "○ 撞击冲击波")
	_submenu.refresh_toggle("trail_fx", SettingsManager.get_bool("trail_fx", true), "◉ 粒子尾流", "○ 粒子尾流")
	_submenu.refresh_toggle("stroll", SettingsManager.get_bool("stroll", true), "◉ 滚动散步", "○ 滚动散步")
	_submenu.refresh_toggle("anti_gravity", SettingsManager.get_bool("anti_gravity", false), "◉ 反重力", "○ 反重力")
	_submenu.refresh_toggle("hud_clock", SettingsManager.get_bool("hud_clock", false), "◉ 系统时钟", "○ 系统时钟")
	_submenu.refresh_toggle("hud_wifi", SettingsManager.get_bool("hud_wifi", false), "◉ WiFi 信息", "○ WiFi 信息")

func _on_sysinfo_btn_pressed() -> void:

	_close_hud()

	_sysinfo_bubble.trigger()

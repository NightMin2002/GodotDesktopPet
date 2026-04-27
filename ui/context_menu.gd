# context_menu.gd — 右键全息追踪面板
# 管理: 设置开关 (持久化) + 开机自启动 + 提醒管理入口
extends CanvasLayer

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
@onready var quit_btn: Button = $HUDPanel/Margin/VBox/QuitBtn

# ── 级联子菜单系统 ──
var _submenus: Dictionary = {}         # id -> PanelContainer
var _submenu_items: Dictionary = {}    # "id/key" -> Button
var _active_submenu: String = ""
var _submenu_hover_timer: float = -1.0
var _submenu_pending_id: String = ""
var _submenu_close_timer: float = -1.0
var _btn_section_colors: Dictionary = {}  # Button -> Color (按钮所属区块颜色)

# 信息侧栏
var _info_panel: PanelContainer
var _info_date_label: Label
var _info_time_label: Label
var _info_wifi_label: Label
var _info_wifi_dot: Label
var _info_wifi_pending: String = ""
var _info_wifi_has_pending: bool = false

var _tooltip_panel: PanelContainer
var _tooltip_label: Label
var _tooltip_tween: Tween

var target: Node2D = null

func _ready() -> void:
	hud.hide()
	_build_info_panel()
	_build_mode_tooltip()
	_build_submenus()
	_style_section_headers()
	
	# 从持久化存储恢复上次的设置状态
	_load_saved_settings()
	
	EventBus.show_context_menu.connect(_on_show_context_menu)
	track_btn.pressed.connect(_on_track_btn_pressed)
	hud_btn.mouse_entered.connect(func(): _on_submenu_trigger_hover("hud"))
	hud_btn.mouse_exited.connect(func(): _on_submenu_trigger_exit())
	hud_btn.pressed.connect(func(): _toggle_submenu("hud"))
	chatter_btn.mouse_entered.connect(func(): _on_submenu_trigger_hover("chatter"))
	chatter_btn.mouse_exited.connect(func(): _on_submenu_trigger_exit())
	chatter_btn.pressed.connect(func(): _toggle_submenu("chatter"))
	# 模式子菜单触发器
	window_mode_btn.mouse_entered.connect(func(): _on_submenu_trigger_hover("window_mode"))
	window_mode_btn.mouse_exited.connect(func(): _on_submenu_trigger_exit())
	window_mode_btn.pressed.connect(func(): _toggle_submenu("window_mode"))
	behavior_mode_btn.mouse_entered.connect(func(): _on_submenu_trigger_hover("behavior_mode"))
	behavior_mode_btn.mouse_exited.connect(func(): _on_submenu_trigger_exit())
	behavior_mode_btn.pressed.connect(func(): _toggle_submenu("behavior_mode"))
	# 功能子菜单触发器
	effects_btn.mouse_entered.connect(func(): _on_submenu_trigger_hover("effects"))
	effects_btn.mouse_exited.connect(func(): _on_submenu_trigger_exit())
	effects_btn.pressed.connect(func(): _toggle_submenu("effects"))
	entertain_btn.mouse_entered.connect(func(): _on_submenu_trigger_hover("entertain"))
	entertain_btn.mouse_exited.connect(func(): _on_submenu_trigger_exit())
	entertain_btn.pressed.connect(func(): _toggle_submenu("entertain"))
	# 模式子菜单触发器
	mode_btn.mouse_entered.connect(func(): _on_submenu_trigger_hover("mode"))
	mode_btn.mouse_exited.connect(func(): _on_submenu_trigger_exit())
	mode_btn.pressed.connect(func(): _toggle_submenu("mode"))
	reminder_btn.pressed.connect(_on_reminder_btn_pressed)
	clone_btn.pressed.connect(_on_clone_btn_pressed)
	dismiss_btn.pressed.connect(_on_dismiss_btn_pressed)
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
	_refresh_radio_submenu("window_mode", wm)
	
	# 行为指令状态 (按钮文字 + 子菜单选中)
	var bm = SettingsManager.get_int("behavior_mode", 0)
	_update_behavior_mode_label(bm)
	_refresh_radio_submenu("behavior_mode", bm)
	
	# 宠物碎碎念模式
	var chatter_mode = SettingsManager.get_int("pet_chatter_mode", 1)
	_update_chatter_label(chatter_mode)
	_refresh_radio_submenu("chatter", chatter_mode)
	
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
		_update_info_panel_position()
		_update_info_time()
		# WiFi 异步结果
		if _info_wifi_has_pending:
			_info_wifi_has_pending = false
			_info_wifi_label.text = _info_wifi_pending
			var connected = _info_wifi_pending != "未连接"
			_info_wifi_dot.add_theme_color_override("font_color",
				Color(0.3, 0.8, 0.4, 0.9) if connected else Color(0.7, 0.4, 0.3, 0.7))
		# 子菜单跟随主菜单
		if _active_submenu != "":
			_update_submenu_position(_active_submenu)
	# tooltip 跟随按钮位置
	if _tooltip_panel.visible:
		_update_tooltip_position()
	# 子菜单 hover 延时弹出
	if _submenu_hover_timer >= 0:
		_submenu_hover_timer -= delta
		if _submenu_hover_timer < 0:
			_show_submenu(_submenu_pending_id)
	# 子菜单延时关闭 (关闭前二次验证鼠标位置)
	if _submenu_close_timer >= 0:
		_submenu_close_timer -= delta
		if _submenu_close_timer < 0:
			if _is_mouse_in_submenu_area():
				_submenu_close_timer = -1.0  # 鼠标回来了，取消关闭
			else:
				_hide_all_submenus()

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
	_refresh_info_panel()
	_info_panel.modulate.a = 0.0
	_info_panel.show()
	_update_info_panel_position()
	# 异步查询 WiFi
	_query_wifi_for_info()
	# 等待一帧让布局计算出 size，再设缩放锚点
	await get_tree().process_frame
	# 缩放锚点设在宠物相对于面板的位置 → 面板从宠物处绽放展开
	hud.pivot_offset = pet_pos - hud.position
	hud.scale = Vector2(0.3, 0.3)
	_info_panel.pivot_offset = Vector2(_info_panel.size.x, _info_panel.size.y * 0.5)
	_info_panel.scale = Vector2(0.3, 0.3)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(hud, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(hud, "modulate:a", 1.0, 0.2)
	tween.tween_property(_info_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(_info_panel, "modulate:a", 1.0, 0.25)

func _close_hud() -> void:
	_tooltip_panel.hide()
	_hide_all_submenus_instant()
	if is_instance_valid(target):
		hud.pivot_offset = target.get_global_transform_with_canvas().get_origin() - hud.position
	var tween = create_tween().set_parallel(true)
	tween.tween_property(hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(hud, "modulate:a", 0.0, 0.15)
	tween.tween_property(_info_panel, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_info_panel, "modulate:a", 0.0, 0.15)
	tween.finished.connect(func():
		hud.hide()
		_info_panel.hide()
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
	_refresh_radio_submenu("chatter", value)

func _update_chatter_label(mode: int) -> void:
	chatter_btn.text = CHATTER_MODE_LABELS[mode]

func _on_reminder_btn_pressed() -> void:
	_tooltip_panel.hide()
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
	_tooltip_panel.hide()
	if is_instance_valid(target):
		hud.pivot_offset = target.get_global_transform_with_canvas().get_origin() - hud.position
	var tween = create_tween().set_parallel(true)
	tween.tween_property(hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(hud, "modulate:a", 0.0, 0.15)
	tween.tween_property(_info_panel, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_info_panel, "modulate:a", 0.0, 0.15)
	tween.finished.connect(func():
		hud.hide()
		_info_panel.hide()
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
	_refresh_radio_submenu("window_mode", value)

func _update_window_mode_label(mode: int) -> void:
	window_mode_btn.text = WINDOW_MODE_LABELS[mode]

# ── 行为指令 (子菜单单选回调) ──

const BEHAVIOR_MODE_LABELS := ["指令 · 自由行动 ▸", "指令 · 安静待命 ▸"]

func _on_radio_behavior_mode(value: int) -> void:
	_update_behavior_mode_label(value)
	EventBus.behavior_mode_changed.emit(value)
	_refresh_radio_submenu("behavior_mode", value)

func _update_behavior_mode_label(mode: int) -> void:
	behavior_mode_btn.text = BEHAVIOR_MODE_LABELS[mode]

func _on_behavior_mode_synced(mode: int) -> void:
	_update_behavior_mode_label(mode)
	_refresh_radio_submenu("behavior_mode", mode)

# ── 自定义浮动 Tooltip ──

var _active_tooltip_btn: Button  # 当前 tooltip 关联的按钮

func _build_mode_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.16, 0.92)
	style.border_color = Color(0.1, 0.8, 1.0, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_tooltip_panel.add_theme_stylebox_override("panel", style)
	
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 15)
	_tooltip_label.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95, 0.95))
	_tooltip_panel.add_child(_tooltip_label)
	
	add_child(_tooltip_panel)

func _update_tooltip_position() -> void:
	if not is_instance_valid(_active_tooltip_btn):
		return
	var btn_pos = _active_tooltip_btn.global_position
	var btn_size = _active_tooltip_btn.size
	var vp_size = get_viewport().get_visible_rect().size
	var tip_w = _tooltip_panel.size.x
	var tip_h = _tooltip_panel.size.y
	var y_pos = btn_pos.y + btn_size.y / 2.0 - tip_h / 2.0
	
	# 优先右侧，空间不足时改左侧
	var gap := 16.0
	var right_x = btn_pos.x + btn_size.x + gap
	if right_x + tip_w > vp_size.x - 10:
		# 左侧弹出
		_tooltip_panel.position = Vector2(btn_pos.x - tip_w - gap, y_pos)
		_tooltip_panel.pivot_offset = Vector2(tip_w, tip_h / 2.0)
	else:
		# 右侧弹出
		_tooltip_panel.position = Vector2(right_x, y_pos)
		_tooltip_panel.pivot_offset = Vector2(0, tip_h / 2.0)

func _show_tooltip_for(btn: Button, text: String, show: bool) -> void:
	if _tooltip_tween and _tooltip_tween.is_running():
		_tooltip_tween.kill()
	if show:
		_active_tooltip_btn = btn
		_tooltip_label.text = text
		_tooltip_panel.modulate.a = 0.0
		_tooltip_panel.scale = Vector2(0.7, 0.7)
		_tooltip_panel.show()
		# 等一帧计算 size 后定位
		await get_tree().process_frame
		_tooltip_panel.pivot_offset = Vector2(0, _tooltip_panel.size.y / 2.0)
		_update_tooltip_position()
		_tooltip_tween = create_tween().set_parallel(true)
		_tooltip_tween.tween_property(_tooltip_panel, "modulate:a", 1.0, 0.15)
		_tooltip_tween.tween_property(_tooltip_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tooltip_tween = create_tween().set_parallel(true)
		_tooltip_tween.tween_property(_tooltip_panel, "modulate:a", 0.0, 0.1)
		_tooltip_tween.tween_property(_tooltip_panel, "scale", Vector2(0.7, 0.7), 0.1)
		_tooltip_tween.finished.connect(func(): _tooltip_panel.hide())

func _show_mode_desc(_show: bool) -> void:
	pass  # 已迁移至子菜单

func _show_behavior_desc(_show: bool) -> void:
	pass  # 已迁移至子菜单

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
		for panel in _submenus.values():
			if panel.visible:
				var sm_local = panel.get_local_mouse_position()
				if Rect2(Vector2.ZERO, panel.size).has_point(sm_local):
					in_submenu = true
					break
		if not in_hud and not in_submenu:
			_close_hud()
			get_viewport().set_input_as_handled()

# ── 级联子菜单系统 ──

## 创建所有子菜单面板 (一次性构建，按需显隐)
func _build_submenus() -> void:
	# 窗口模式子菜单 (单选)
	_create_radio_submenu("window_mode", [
		{"value": 0, "label": "自由漫游", "desc": "在窗口间自由行走"},
		{"value": 1, "label": "窗口封闭", "desc": "被困在当前窗口内"},
		{"value": 2, "label": "窗口排斥", "desc": "无法进入任何窗口"},
	], func(v): _on_radio_window_mode(v))
	# 行为指令子菜单 (单选)
	_create_radio_submenu("behavior_mode", [
		{"value": 0, "label": "自由行动", "desc": "活力满满，随意滚动跳跃"},
		{"value": 1, "label": "安静待命", "desc": "安安静静，乖乖不动"},
	], func(v): _on_radio_behavior_mode(v))
	# 碎碎念子菜单 (单选)
	_create_radio_submenu("chatter", [
		{"value": 0, "label": "关闭", "desc": "宠物不会主动说话"},
		{"value": 1, "label": "每30分钟", "desc": "每到整点和半点，冒泡说点什么"},
		{"value": 2, "label": "每60分钟", "desc": "每到整点，冒泡说点什么"},
	], func(v): _on_radio_chatter_mode(v))
	# 视觉特效子菜单 (开关)
	_create_submenu("effects", [
		{"id": "shockwave", "on": "◉ 撞击冲击波", "off": "○ 撞击冲击波",
		 "key": "shockwave", "default": true},
		{"id": "trail_fx", "on": "◉ 粒子尾流", "off": "○ 粒子尾流",
		 "key": "trail_fx", "default": true},
	])
	# 娱乐玩法子菜单 (开关)
	_create_submenu("entertain", [
		{"id": "stroll", "on": "◉ 滚动散步", "off": "○ 滚动散步",
		 "key": "stroll", "default": true},
	])
	# 模式子菜单 (开关，未来可继续扩展更多全局模式)
	_create_submenu("mode", [
		{"id": "anti_gravity", "on": "◉ 反重力", "off": "○ 反重力",
		 "key": "anti_gravity", "default": false},
	])
	# HUD 子菜单 (开关，控制悬浮面板中的各组件)
	_create_submenu("hud", [
		{"id": "hud_clock", "on": "◉ 系统时钟", "off": "○ 系统时钟",
		 "key": "hud_clock", "default": false},
		{"id": "hud_wifi", "on": "◉ WiFi 信息", "off": "○ WiFi 信息",
		 "key": "hud_wifi", "default": false},
	])

## 创建单个子菜单面板
func _create_submenu(menu_id: String, items: Array) -> void:
	var panel = PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.16, 0.92)
	style.border_color = Color(0.1, 0.8, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	
	for item in items:
		var btn = Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.1, 1, 0.9, 1))
		var item_data = item  # 捕获闭包变量
		btn.pressed.connect(func(): _on_submenu_item_pressed(item_data))
		vbox.add_child(btn)
		_submenu_items[item.id] = btn
	
	# hover 进出检测
	panel.mouse_entered.connect(func(): _on_submenu_panel_enter())
	panel.mouse_exited.connect(func(): _on_submenu_panel_exit())
	
	add_child(panel)
	_submenus[menu_id] = panel

## 从 SettingsManager 刷新所有子菜单按钮的显示状态
func _refresh_submenu_states() -> void:
	# 视觉特效
	var shock = SettingsManager.get_bool("shockwave", true)
	_set_toggle(_submenu_items["shockwave"], shock, "◉ 撞击冲击波", "○ 撞击冲击波")
	var trail = SettingsManager.get_bool("trail_fx", true)
	_set_toggle(_submenu_items["trail_fx"], trail, "◉ 粒子尾流", "○ 粒子尾流")
	# 娱乐玩法
	var stroll = SettingsManager.get_bool("stroll", true)
	_set_toggle(_submenu_items["stroll"], stroll, "◉ 滚动散步", "○ 滚动散步")
	# 模式
	var ag = SettingsManager.get_bool("anti_gravity", false)
	_set_toggle(_submenu_items["anti_gravity"], ag, "◉ 反重力", "○ 反重力")
	# HUD
	var hc = SettingsManager.get_bool("hud_clock", false)
	_set_toggle(_submenu_items["hud_clock"], hc, "◉ 系统时钟", "○ 系统时钟")
	var hw = SettingsManager.get_bool("hud_wifi", false)
	_set_toggle(_submenu_items["hud_wifi"], hw, "◉ WiFi 信息", "○ WiFi 信息")

## 子菜单项被按下
func _on_submenu_item_pressed(item: Dictionary) -> void:
	var btn: Button = _submenu_items[item.id]
	var on = _flip_toggle(btn, item.on, item.off)
	SettingsManager.set_bool(item.key, on)
	EventBus.setting_toggled.emit(item.key, on)

## hover 触发按钮 → 延时弹出子菜单
func _on_submenu_trigger_hover(menu_id: String) -> void:
	_submenu_close_timer = -1.0  # 取消关闭倒计时
	if _active_submenu == menu_id:
		return  # 已经打开了
	_submenu_pending_id = menu_id
	_submenu_hover_timer = 0.15  # 150ms 延时

## hover 离开触发按钮
func _on_submenu_trigger_exit() -> void:
	_submenu_hover_timer = -1.0  # 取消弹出倒计时
	_submenu_close_timer = 0.3   # 300ms 后关闭 (给鼠标移入子菜单的时间)

## 点击直接切换子菜单
func _toggle_submenu(menu_id: String) -> void:
	_submenu_hover_timer = -1.0
	_submenu_close_timer = -1.0
	if _active_submenu == menu_id:
		_hide_all_submenus()
	else:
		_show_submenu(menu_id)

## 鼠标进入子菜单面板
func _on_submenu_panel_enter() -> void:
	_submenu_close_timer = -1.0  # 取消关闭

## 鼠标离开子菜单面板
func _on_submenu_panel_exit() -> void:
	_submenu_close_timer = 0.3   # 延时关闭

## 显示指定子菜单 (带动画)
func _show_submenu(menu_id: String) -> void:
	_submenu_close_timer = -1.0  # 取消待关闭倒计时
	# 先关闭其他子菜单
	for id in _submenus:
		if id != menu_id and _submenus[id].visible:
			_submenus[id].hide()
	
	var panel: PanelContainer = _submenus[menu_id]
	_active_submenu = menu_id
	
	# 定位到触发按钮右侧
	_update_submenu_position(menu_id)
	
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.5, 0.8)
	panel.show()
	
	# 等一帧算 size
	await get_tree().process_frame
	_update_submenu_position(menu_id)
	panel.pivot_offset = Vector2(0, panel.size.y / 2.0)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)

## 更新子菜单位置 (锚定到触发按钮右侧)
func _update_submenu_position(menu_id: String) -> void:
	var trigger_btn: Button = _get_submenu_trigger(menu_id)
	if not trigger_btn:
		return
	
	var panel: PanelContainer = _submenus[menu_id]
	var btn_pos = trigger_btn.global_position
	var btn_size = trigger_btn.size
	var vp_size = get_viewport().get_visible_rect().size
	var panel_w = panel.size.x if panel.size.x > 0 else 160.0
	
	# 优先右侧弹出，空间不足时左侧
	var x: float
	var right_x = btn_pos.x + btn_size.x + 6
	if right_x + panel_w > vp_size.x - 10:
		x = btn_pos.x - panel_w - 6
	else:
		x = right_x
	var y = btn_pos.y + btn_size.y / 2.0 - panel.size.y / 2.0
	y = clampf(y, 8.0, vp_size.y - panel.size.y - 8.0)
	panel.position = Vector2(x, y)

## 带动画关闭所有子菜单
func _hide_all_submenus() -> void:
	for panel in _submenus.values():
		if panel.visible:
			var tween = create_tween().set_parallel(true)
			tween.tween_property(panel, "modulate:a", 0.0, 0.1)
			tween.tween_property(panel, "scale", Vector2(0.5, 0.8), 0.1)
			tween.finished.connect(panel.hide)
	_active_submenu = ""

## 无动画立即关闭所有子菜单
func _hide_all_submenus_instant() -> void:
	for panel in _submenus.values():
		panel.hide()
	_active_submenu = ""
	_submenu_hover_timer = -1.0
	_submenu_close_timer = -1.0

## 检测鼠标是否在子菜单区域内 (含触发按钮)
func _is_mouse_in_submenu_area() -> bool:
	# 检查触发按钮
	for btn in [window_mode_btn, behavior_mode_btn, effects_btn, entertain_btn, mode_btn, hud_btn]:
		var local = btn.get_local_mouse_position()
		if Rect2(Vector2.ZERO, btn.size).has_point(local):
			return true
	# 检查子菜单面板
	for panel in _submenus.values():
		if panel.visible:
			var local = panel.get_local_mouse_position()
			if Rect2(Vector2.ZERO, panel.size).has_point(local):
				return true
	return false

## 获取子菜单对应的触发按钮
func _get_submenu_trigger(menu_id: String) -> Button:
	match menu_id:
		"window_mode": return window_mode_btn
		"behavior_mode": return behavior_mode_btn
		"effects": return effects_btn
		"entertain": return entertain_btn
		"mode": return mode_btn
		"hud": return hud_btn
		"chatter": return chatter_btn
	return null

## 创建单选子菜单 (窗口模式/行为指令)
var _radio_buttons: Dictionary = {}  # menu_id -> [{btn, value, label}]
var _radio_callbacks: Dictionary = {}  # menu_id -> Callable

func _create_radio_submenu(menu_id: String, items: Array, callback: Callable) -> void:
	var panel = PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.16, 0.92)
	style.border_color = Color(0.1, 0.8, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	
	var group_items: Array = []
	for item in items:
		var btn = Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.1, 1, 0.9, 1))
		btn.text = "○ " + item.label
		var v = item.value
		var mid = menu_id
		btn.pressed.connect(func(): _on_radio_item_pressed(mid, v))
		# 如果有描述，悬停显示 tooltip
		if item.has("desc"):
			var desc_text = item.desc
			var b = btn
			btn.mouse_entered.connect(func(): _show_tooltip_for(b, desc_text, true))
			btn.mouse_exited.connect(func(): _show_tooltip_for(b, desc_text, false))
		vbox.add_child(btn)
		group_items.append({"btn": btn, "value": item.value, "label": item.label})
	
	panel.mouse_entered.connect(func(): _on_submenu_panel_enter())
	panel.mouse_exited.connect(func(): _on_submenu_panel_exit())
	
	add_child(panel)
	_submenus[menu_id] = panel
	_radio_buttons[menu_id] = group_items
	_radio_callbacks[menu_id] = callback

## 单选项被点击
func _on_radio_item_pressed(menu_id: String, value: int) -> void:
	if _radio_callbacks.has(menu_id):
		_radio_callbacks[menu_id].call(value)

## 刷新单选子菜单的选中状态
func _refresh_radio_submenu(menu_id: String, current_value: int) -> void:
	if not _radio_buttons.has(menu_id): return
	for item in _radio_buttons[menu_id]:
		var btn: Button = item.btn
		if item.value == current_value:
			btn.text = "● " + item.label
		else:
			btn.text = "○ " + item.label

# ── 分区标题样式化 ──

## 将 ▌ 标题 Label 替换为徽章(彩色左边框面板) + 延伸细线
func _style_section_headers() -> void:
	var vbox = hud.get_node("Margin/VBox")
	var is_first_section := true
	var children_snapshot = vbox.get_children().duplicate()
	var current_section_color := Color.WHITE
	
	for child in children_snapshot:
		if child is Label and child.text.begins_with("\u258c"):
			var label: Label = child
			current_section_color = label.get_theme_color("font_color")
			var section_text: String = label.text.replace("\u258c", "")
			var idx = label.get_index()
			
			# 上方间距
			if not is_first_section:
				var spacer = Control.new()
				spacer.custom_minimum_size.y = 4
				spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
				vbox.add_child(spacer)
				vbox.move_child(spacer, idx)
				idx += 1
			is_first_section = false
			
			# 全宽徽章: 彩色左边框 + 深背景横幅
			var badge = PanelContainer.new()
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var style = StyleBoxFlat.new()
			style.bg_color = Color(current_section_color.r * 0.2, current_section_color.g * 0.2, current_section_color.b * 0.2, 0.7)
			style.border_color = current_section_color
			style.border_width_left = 3
			style.border_width_top = 0
			style.border_width_right = 0
			style.border_width_bottom = 0
			style.corner_radius_top_right = 4
			style.corner_radius_bottom_right = 4
			style.corner_radius_top_left = 0
			style.corner_radius_bottom_left = 0
			style.content_margin_left = 8
			style.content_margin_right = 10
			style.content_margin_top = 2
			style.content_margin_bottom = 2
			badge.add_theme_stylebox_override("panel", style)
			
			var badge_label = Label.new()
			badge_label.text = section_text
			badge_label.add_theme_font_size_override("font_size", 13)
			badge_label.add_theme_color_override("font_color", Color(current_section_color.r, current_section_color.g, current_section_color.b, 0.9))
			badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_child(badge_label)
			
			# 替换原 Label
			vbox.add_child(badge)
			vbox.move_child(badge, idx)
			label.queue_free()
		elif child is Button:
			# 记录每个按钮所属区块的颜色
			_btn_section_colors[child] = current_section_color
	
	# 自动给子菜单上色
	_color_submenus()

## 根据触发按钮所属区块色自动设置子菜单边框色
func _color_submenus() -> void:
	for menu_id in _submenus:
		var trigger = _get_submenu_trigger(menu_id)
		if trigger and trigger in _btn_section_colors:
			var color: Color = _btn_section_colors[trigger]
			var panel: PanelContainer = _submenus[menu_id]
			var style = panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			style.border_color = Color(color.r, color.g, color.b, 0.8)
			panel.add_theme_stylebox_override("panel", style)

# ── 信息侧栏 ──

func _build_info_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.visible = false
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.1, 0.92)
	style.border_color = Color(0.1, 0.8, 1.0, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	_info_panel.add_theme_stylebox_override("panel", style)
	add_child(_info_panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_info_panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	
	# ── 日期 ──
	_info_date_label = Label.new()
	_info_date_label.add_theme_font_size_override("font_size", 14)
	_info_date_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.95, 0.7))
	_info_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_info_date_label)
	
	# ── 时钟 (大号) ──
	_info_time_label = Label.new()
	_info_time_label.add_theme_font_size_override("font_size", 28)
	_info_time_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.95))
	_info_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_info_time_label)
	
	# ── 分隔线 ──
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	sep.add_theme_stylebox_override("separator", _make_info_sep_style())
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)
	
	# ── WiFi 行 ──
	var wifi_row = HBoxContainer.new()
	wifi_row.add_theme_constant_override("separation", 6)
	wifi_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(wifi_row)
	
	_info_wifi_dot = Label.new()
	_info_wifi_dot.text = "\u25cf"
	_info_wifi_dot.add_theme_font_size_override("font_size", 10)
	_info_wifi_dot.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4, 0.9))
	_info_wifi_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wifi_row.add_child(_info_wifi_dot)
	
	var wifi_tag = Label.new()
	wifi_tag.text = "WiFi"
	wifi_tag.add_theme_font_size_override("font_size", 11)
	wifi_tag.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.6))
	wifi_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wifi_row.add_child(wifi_tag)
	
	_info_wifi_label = Label.new()
	_info_wifi_label.text = "..."
	_info_wifi_label.add_theme_font_size_override("font_size", 13)
	_info_wifi_label.add_theme_color_override("font_color", Color(0.7, 0.82, 0.95, 0.85))
	_info_wifi_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wifi_row.add_child(_info_wifi_label)

func _make_info_sep_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.8, 1.0, 0.15)
	s.set_content_margin_all(0)
	return s

## 刷新信息栏内容 (日期+时钟)
func _refresh_info_panel() -> void:
	var d = Time.get_date_dict_from_system()
	var weekdays = ["日", "一", "二", "三", "四", "五", "六"]
	var wd = weekdays[d.weekday % 7]
	_info_date_label.text = "%d年%02d月%02d日 周%s" % [d.year, d.month, d.day, wd]
	_update_info_time()

## 更新实时时钟
func _update_info_time() -> void:
	var t = Time.get_time_dict_from_system()
	_info_time_label.text = "%02d:%02d:%02d" % [t.hour, t.minute, t.second]

## 信息栏定位: 紧贴主菜单左侧
func _update_info_panel_position() -> void:
	if not _info_panel.visible:
		return
	var info_w = _info_panel.size.x if _info_panel.size.x > 0 else 120.0
	var gap := 4.0
	# 默认在主菜单左侧
	var x = hud.position.x - info_w - gap
	# 如果左侧空间不足，放到右侧
	if x < 4.0:
		x = hud.position.x + hud.size.x + gap
	_info_panel.position = Vector2(x, hud.position.y)

## WiFi 异步查询
func _query_wifi_for_info() -> void:
	_info_wifi_label.text = "..."
	_info_wifi_dot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.4, 0.7))
	WorkerThreadPool.add_task(_wifi_info_task)

func _wifi_info_task() -> void:
	var output: Array = []
	var exit = OS.execute("powershell", ["-NoProfile", "-Command",
		"(Get-NetConnectionProfile | Where-Object {$_.InterfaceAlias -match 'Wi-Fi|WLAN|Wireless'} | Select-Object -First 1).Name"], output, true, false)
	var ssid = ""
	if exit == 0 and output.size() > 0:
		# 取第一行 (可能有多个 WiFi 适配器)
		var lines = output[0].strip_edges().split("\n")
		if lines.size() > 0:
			ssid = lines[0].strip_edges()
	if ssid == "":
		ssid = "未连接"
	_info_wifi_pending = ssid
	_info_wifi_has_pending = true


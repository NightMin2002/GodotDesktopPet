# context_menu.gd — 右键全息追踪面板 (分区委托重构版)
# 管理: 6 个分区入口 → L2 分区面板 → L3 选项面板
# 各分区构建 + 回调委托给 sec_*.gd, 本文件只负责协调

extends CanvasLayer

const InfoSidebar = preload("res://ui/context_menu/info_sidebar.gd")
const MenuTooltip = preload("res://ui/context_menu/menu_tooltip.gd")
const SubmenuSystem = preload("res://ui/context_menu/submenu_system.gd")
const MenuSettings = preload("res://ui/context_menu/menu_setting_registry.gd")

const EffectPreview = preload("res://ui/context_menu/effect_preview.gd")
const SecPet = preload("res://ui/context_menu/sec_pet.gd")
const SecBehavior = preload("res://ui/context_menu/sec_behavior.gd")
const SecVisual = preload("res://ui/context_menu/sec_visual.gd")
const SecPlay = preload("res://ui/context_menu/sec_play.gd")
const SecSystem = preload("res://ui/context_menu/sec_system.gd")

# ── 主菜单分区入口按钮 ──
@onready var hud: PanelContainer = $HUDPanel
@onready var sec_pet_btn: Button = $HUDPanel/Margin/VBox/SecPetBtn
@onready var sec_display_btn: Button = $HUDPanel/Margin/VBox/SecDisplayBtn
@onready var sec_behavior_btn: Button = $HUDPanel/Margin/VBox/SecBehaviorBtn
@onready var sec_visual_btn: Button = $HUDPanel/Margin/VBox/SecVisualBtn
@onready var sec_play_btn: Button = $HUDPanel/Margin/VBox/SecPlayBtn
@onready var sec_system_btn: Button = $HUDPanel/Margin/VBox/SecSystemBtn
@onready var todo_btn: Button = $HUDPanel/Margin/VBox/TodoBtn
@onready var game_terminal_btn: Button = $HUDPanel/Margin/VBox/GameTerminalBtn
@onready var profile_btn: Button = $HUDPanel/Margin/VBox/ProfileBtn
@onready var quit_btn: Button = $HUDPanel/Margin/VBox/QuitBtn

# ── 子系统 ──
var _submenu: SubmenuSystem
var _sidebar: InfoSidebar
var _tooltip: MenuTooltip
var _fx_preview: EffectPreview
var _radio_title_buttons: Dictionary = {}

# ── 分区 builder ──
var _sec_pet: SecPet
var _sec_behavior: SecBehavior
var _sec_visual: SecVisual
var _sec_play: SecPlay
var _sec_system: SecSystem

var target: Node2D = null
## 菜单展开方向: 1=菜单在宠物右侧, -1=菜单在宠物左侧
var _menu_side: int = 1

func _ready() -> void:
	hud.hide()

	_sidebar = InfoSidebar.new(self)
	_sidebar.build()
	_tooltip = MenuTooltip.new(self)
	_tooltip.build()
	_submenu = SubmenuSystem.new(self)
	_fx_preview = EffectPreview.new(self)

	# 初始化分区 builder
	_sec_pet = SecPet.new(self)
	_sec_behavior = SecBehavior.new(self)
	_sec_visual = SecVisual.new(self)
	_sec_play = SecPlay.new(self)
	_sec_system = SecSystem.new(self)

	# 构建所有分区面板 (L2 + L3)
	_build_all_sections()

	# 胶囊按钮样式
	_apply_capsule_style(todo_btn, Color(0.12, 0.22, 0.42, 0.65), Color(0.4, 0.6, 0.9, 0.5))
	todo_btn.pressed.connect(func(): _close_and_emit(EventBus.show_todo_panel))

	_apply_capsule_style(game_terminal_btn, Color(0.08, 0.20, 0.15, 0.65), Color(0.3, 0.85, 0.55, 0.5))
	game_terminal_btn.pressed.connect(func(): _close_and_emit(EventBus.show_game_terminal))

	_apply_capsule_style(profile_btn, Color(0.08, 0.15, 0.28, 0.65), Color(0.2, 0.6, 0.85, 0.5))
	profile_btn.pressed.connect(func(): _close_and_emit(EventBus.show_pet_profile))
	_apply_capsule_style(quit_btn, Color(0.35, 0.1, 0.1, 0.65), Color(0.8, 0.3, 0.3, 0.5))

	# 分区色 — 给每个主菜单按钮左侧加彩色条纹
	_style_section_buttons()

	_load_saved_settings()

	# UI 主题色
	_apply_ui_theme(EventBus.ui_hue)
	EventBus.ui_theme_changed.connect(_apply_ui_theme)
	EventBus.show_context_menu.connect(_on_show_context_menu)

	# 主菜单 6 个分区入口的 hover/click
	_bind_section_trigger(sec_pet_btn, "sec_pet")
	_bind_section_trigger(sec_display_btn, "sec_display")
	_bind_section_trigger(sec_behavior_btn, "sec_behavior")
	_bind_section_trigger(sec_visual_btn, "sec_visual")
	_bind_section_trigger(sec_play_btn, "sec_play")
	_bind_section_trigger(sec_system_btn, "sec_system")

	quit_btn.pressed.connect(_sec_system.on_quit_pressed)
	EventBus.behavior_mode_changed.connect(_sec_behavior.on_behavior_mode_synced)

# ═══════════════════════════════════════════
# 分区入口绑定
# ═══════════════════════════════════════════

## 绑定分区入口按钮的 hover/exit/click 到 L2 子菜单
func _bind_section_trigger(btn: Button, menu_id: String) -> void:
	_submenu.register_trigger(menu_id, btn)
	btn.mouse_entered.connect(func(): _submenu.on_trigger_hover(menu_id))
	btn.mouse_exited.connect(func(): _submenu.on_trigger_exit())
	_make_hover_only(btn)

## 绑定 L2 面板中的按钮到 L3 子菜单
func _bind_l3_trigger(btn: Button, l3_id: String, parent_l2_id: String) -> void:
	_submenu.register_l3_trigger(l3_id, btn, parent_l2_id)
	btn.mouse_entered.connect(func(): _submenu.on_l3_trigger_hover(l3_id))
	btn.mouse_exited.connect(func(): _submenu.on_l3_trigger_exit())
	_make_hover_only(btn)

## 子菜单触发按钮: 只响应 hover，不响应点击
func _make_hover_only(btn: Button) -> void:
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	btn.add_theme_color_override("font_pressed_color", btn.get_theme_color("font_hover_color"))
	var hover_bg = btn.get_theme_stylebox("hover")
	if hover_bg:
		btn.add_theme_stylebox_override("pressed", hover_bg)

# ═══════════════════════════════════════════
# 分区面板构建
# ═══════════════════════════════════════════

## 构建显示分区 (太小不值得拆文件)
func _build_sec_display() -> void:
	create_toggle_group("sec_display")

## 统一入口
func _build_all_sections() -> void:
	_sec_pet.build()
	_build_sec_display()
	_sec_behavior.build()
	_sec_visual.build()
	_sec_play.build()
	_sec_system.build()
	# 全部分区面板就绪后，统一构建预览
	_fx_preview.build()

# ═══════════════════════════════════════════
# 分区入口按钮样式
# ═══════════════════════════════════════════

## 给每个分区入口按钮添加彩色左边框徽章风格
func _style_section_buttons() -> void:
	var section_defs := [
		[sec_pet_btn, Color(0.2, 0.75, 0.9)],
		[sec_display_btn, Color(0.2, 0.75, 0.9)],
		[sec_behavior_btn, Color(0.4, 0.6, 1.0)],
		[sec_visual_btn, Color(0.85, 0.7, 0.25)],
		[sec_play_btn, Color(0.3, 0.85, 0.55)],
		[sec_system_btn, Color(0.6, 0.45, 0.45)],
	]
	for def in section_defs:
		var btn: Button = def[0]
		btn.set_script(CyberMenuButton)
		btn._ready()
		var color: Color = def[1]
		var style = StyleBoxFlat.new()
		style.bg_color = Color(color.r * 0.15, color.g * 0.15, color.b * 0.15, 0.4)
		style.border_color = color
		style.border_width_left = 3
		style.border_width_top = 0
		style.border_width_right = 0
		style.border_width_bottom = 0
		style.corner_radius_top_right = 0
		style.corner_radius_bottom_right = 0
		style.corner_radius_top_left = 0
		style.corner_radius_bottom_left = 0
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", style)
		var hover_style = style.duplicate()
		hover_style.bg_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.6)
		btn.add_theme_stylebox_override("hover", hover_style)
		var pressed_style = style.duplicate()
		pressed_style.bg_color = Color(color.r * 0.2, color.g * 0.2, color.b * 0.2, 0.5)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.flat = false

# ═══════════════════════════════════════════
# 工具函数: 创建按钮
# ═══════════════════════════════════════════

func _make_menu_btn(text: String, hover_color: Color) -> Button:
	var btn = CyberMenuButton.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
	btn.add_theme_color_override("font_hover_color", hover_color)
	btn.text = text
	return btn

func make_submenu_panel() -> PanelContainer:
	return _submenu._make_panel()

func register_l2_panel(menu_id: String, panel: PanelContainer) -> void:
	panel.mouse_entered.connect(func(): _submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): _submenu.on_panel_exit())
	add_child(panel)
	_submenu.panels[menu_id] = panel

func show_menu_tooltip(btn: Button, text: String, show: bool) -> void:
	_tooltip.show_for(btn, text, show)

func create_toggle_group(menu_id: String, group_id: String = "", level: int = 2, parent_l2_id: String = "") -> void:
	var source_id = group_id if group_id != "" else menu_id
	_submenu.create_toggle(menu_id, MenuSettings.get_toggle_group(source_id), level, parent_l2_id)

func create_radio_group(menu_id: String, level: int = 2, parent_l2_id: String = "") -> void:
	var mid := menu_id
	_submenu.create_radio(menu_id, MenuSettings.get_radio_items(menu_id), func(value: int): _on_registered_radio_changed(mid, value), level, parent_l2_id)

func register_radio_title(menu_id: String, btn: Button) -> void:
	_radio_title_buttons[menu_id] = btn
	refresh_registered_radio(menu_id)

func get_radio_title(menu_id: String, value = null) -> String:
	var resolved_value: int = MenuSettings.get_radio_value(menu_id) if value == null else int(value)
	return MenuSettings.get_radio_title(menu_id, resolved_value)

func get_radio_value(menu_id: String) -> int:
	return MenuSettings.get_radio_value(menu_id)

func get_radio_items(menu_id: String) -> Array:
	return MenuSettings.get_radio_items(menu_id)

func refresh_registered_radio(menu_id: String, value = null) -> void:
	var resolved_value: int = MenuSettings.get_radio_value(menu_id) if value == null else int(value)
	_submenu.refresh_radio(menu_id, resolved_value)
	if _radio_title_buttons.has(menu_id):
		var btn = _radio_title_buttons[menu_id] as Button
		if is_instance_valid(btn):
			btn.text = MenuSettings.get_radio_title(menu_id, resolved_value)

func refresh_registered_settings() -> void:
	for item_id in MenuSettings.get_toggle_ids():
		var item := MenuSettings.get_toggle_def(item_id)
		if item.is_empty():
			continue
		_submenu.refresh_toggle(item.id, SettingsManager.get_bool(item.key, item.default), item.on, item.off)
	for menu_id in MenuSettings.get_radio_ids():
		refresh_registered_radio(menu_id)

func close_menu_instant() -> void:
	_tooltip.panel.hide()
	_submenu.hide_all_instant()
	hud.hide()
	_sidebar.panel.hide()
	target = null
	EventBus.context_menu_toggled.emit(false)

func cleanup_toys() -> void:
	if _sec_play and _sec_play.has_method("cleanup_toys"):
		_sec_play.cleanup_toys()

## 关闭菜单并发射信号 (用于面板入口按钮)
func _close_and_emit(sig: Signal) -> void:
	close_menu_instant()
	sig.emit()

# ═══════════════════════════════════════════
# 持久化加载
# ═══════════════════════════════════════════

func _load_saved_settings() -> void:
	refresh_registered_settings()
	_sec_pet.refresh_debug_submenu()

func apply_registered_radio(menu_id: String, value: int) -> void:
	var group := MenuSettings.get_radio_group(menu_id)
	if group.is_empty():
		return
	var setting_key: String = group.get("setting_key", "")
	if setting_key != "":
		SettingsManager.set_int(setting_key, value)
	refresh_registered_radio(menu_id, value)
	match group.get("event", ""):
		"window_mode_changed":
			EventBus.window_mode_changed.emit(value)
		"behavior_mode_changed":
			EventBus.behavior_mode_changed.emit(value)
		"setting_toggled":
			if setting_key != "":
				EventBus.setting_toggled.emit(setting_key, value > 0)
		"appearance_changed":
			EventBus.appearance_changed.emit(value)
		"pet_size_changed":
			EventBus.pet_size_changed.emit(value)
		"squash_test":
			EventBus.trigger_squash_test.emit(-1 if value == 0 else value - 1)

func _on_registered_radio_changed(menu_id: String, value: int) -> void:
	apply_registered_radio(menu_id, value)

# ═══════════════════════════════════════════
# 弹性追踪 / _process
# ═══════════════════════════════════════════

func _process(delta: float) -> void:
	if hud.visible and is_instance_valid(target):
		var target_pos = _calc_menu_pos(target.get_global_transform_with_canvas().get_origin())
		hud.position = hud.position.lerp(target_pos, delta * 15.0)
		_sidebar.update_position(hud)
		_sidebar.update_time()
		_sidebar.update_uptime()
		if _sidebar.has_pending():
			_sidebar.apply_pending()
		# L2 子菜单跟随
		if _submenu.active != "":
			_submenu.update_position(_submenu.active)
		# L3 子菜单跟随
		if _submenu.l3_active != "":
			_submenu.update_l3_position(_submenu.l3_active)
	if _tooltip.panel.visible:
		_tooltip.update_position()
	_fx_preview.update_positions()
	_submenu.process_timers(delta)

func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	var hs = hud.size
	pos.x = clampf(pos.x, 4.0, vp.x - hs.x - 4.0)
	pos.y = clampf(pos.y, 4.0, vp.y - hs.y - 4.0)
	return pos

func _calc_menu_pos(pet_pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	var hs = hud.size if hud.size.x > 0 else Vector2(200, 400)
	var gap := 45.0
	var x: float
	if _menu_side == -1:
		x = pet_pos.x - hs.x - gap
	else:
		x = pet_pos.x + gap
	var y: float
	if pet_pos.y > vp.y * 0.5:
		y = pet_pos.y - hs.y + 20.0
	else:
		y = pet_pos.y - 20.0
	x = clampf(x, 4.0, vp.x - hs.x - 4.0)
	y = clampf(y, 4.0, vp.y - hs.y - 4.0)
	return Vector2(x, y)

# ═══════════════════════════════════════════
# 菜单开关
# ═══════════════════════════════════════════

func _on_show_context_menu(target_node: Node2D) -> void:
	target = target_node
	if hud.visible:
		_close_hud()
		return

	EventBus.context_menu_toggled.emit(true)
	_sec_pet.update_clone_label()

	var pet_pos = target.get_global_transform_with_canvas().get_origin()
	var vp = get_viewport().get_visible_rect().size
	_menu_side = -1 if pet_pos.x > vp.x * 0.5 else 1

	var panel_pos = _calc_menu_pos(pet_pos)
	hud.position = panel_pos
	hud.modulate.a = 0.0
	_sec_pet.refresh_profile()
	hud.show()

	_sidebar.refresh()
	_sidebar.panel.modulate.a = 0.0
	_sidebar.panel.show()
	_sidebar.update_position(hud)
	_sidebar.query()

	await get_tree().process_frame
	hud.position = _clamp_to_viewport(hud.position)
	_sidebar.update_position(hud)
	hud.pivot_offset = pet_pos - hud.position
	hud.scale = Vector2(0.3, 0.3)

	if _menu_side == 1:
		_sidebar.panel.pivot_offset = Vector2(_sidebar.panel.size.x, _sidebar.panel.size.y * 0.5)
	else:
		_sidebar.panel.pivot_offset = Vector2(0, _sidebar.panel.size.y * 0.5)
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

	if _menu_side == 1:
		_sidebar.panel.pivot_offset = Vector2(_sidebar.panel.size.x, _sidebar.panel.size.y * 0.5)
	else:
		_sidebar.panel.pivot_offset = Vector2(0, _sidebar.panel.size.y * 0.5)
	tween.tween_property(_sidebar.panel, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_sidebar.panel, "modulate:a", 0.0, 0.15)

	tween.finished.connect(func():
		hud.hide()
		_sidebar.panel.hide()
		EventBus.context_menu_toggled.emit(false)
	)
	target = null

# ═══════════════════════════════════════════
# UI 主题色
# ═══════════════════════════════════════════

func _apply_ui_theme(hue: float) -> void:
	var style = hud.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style = style.duplicate()
		style.border_color = Color.from_hsv(hue, 0.8, 1.0, 0.8)
		style.set_corner_radius_all(0)
		hud.add_theme_stylebox_override("panel", style)
	if _submenu and _submenu.has_method("apply_ui_theme"):
		_submenu.apply_ui_theme(hue)
	if _sidebar and _sidebar.has_method("apply_ui_theme"):
		_sidebar.apply_ui_theme(hue)

# ═══════════════════════════════════════════
# 工具函数
# ═══════════════════════════════════════════

func _apply_capsule_style(btn: Button, bg_color: Color, border_color: Color) -> void:
	btn.set_script(CyberMenuButton)
	btn._ready()
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.border_color = border_color
	style_normal.set_border_width_all(1)
	style_normal.set_corner_radius_all(0)
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12
	style_normal.content_margin_top = 4
	style_normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", style_normal)
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(bg_color.r + 0.06, bg_color.g + 0.06, bg_color.b + 0.06, bg_color.a + 0.15)
	style_hover.border_color = Color(border_color.r, border_color.g, border_color.b, border_color.a + 0.3)
	btn.add_theme_stylebox_override("hover", style_hover)
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(bg_color.r + 0.03, bg_color.g + 0.03, bg_color.b + 0.03, bg_color.a + 0.1)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.flat = false

func _set_toggle(btn: Button, is_on: bool, on_text: String, off_text: String) -> void:
	btn.text = on_text if is_on else off_text

func _flip_toggle(btn: Button, on_text: String, off_text: String) -> bool:
	var is_on = btn.text.ends_with("[●]")
	var new_val = not is_on
	_set_toggle(btn, new_val, on_text, off_text)
	return new_val

func _get_win_manager() -> Node:
	return ProfileStyles.get_win_manager(get_tree())

# ── 外部点击关闭 ──

func _unhandled_input(event: InputEvent) -> void:
	if hud.visible and event is InputEventMouseButton and event.pressed:
		var local_mouse = hud.get_local_mouse_position()
		var rect = Rect2(Vector2.ZERO, hud.size)
		var in_hud = rect.has_point(local_mouse)

		var in_submenu = false
		# 检查 L2 + L3 所有可见面板
		for panel in _submenu.get_all_visible_panels():
			var sm_local = panel.get_local_mouse_position()
			if Rect2(Vector2.ZERO, panel.size).has_point(sm_local):
				in_submenu = true
				break

		if not in_hud and not in_submenu:
			_close_hud()
			get_viewport().set_input_as_handled()

# ═══════════════════════════════════════════
# UI 共通工具函数 (提供给子系统调用)
# ═══════════════════════════════════════════

## 寻找外层的 PanelContainer 以正确计算面板边缘（包含 padding）
func get_panel_bounds_for_button(btn: Button) -> Dictionary:
	var ref_pos = btn.global_position
	var ref_w = btn.size.x
	var p = btn.get_parent()
	while p != null and p != self:
		if p is PanelContainer:
			ref_pos = p.global_position
			ref_w = p.size.x
			break
		p = p.get_parent()
	return {"pos": ref_pos, "w": ref_w}

## 为弹出的浮窗面板绘制一个指向触发按钮的小尾巴（三角形）
func draw_panel_tail(panel: PanelContainer) -> void:
	if not panel.has_meta("trigger_global_y"): return
	var trigger_global_y: float = panel.get_meta("trigger_global_y")
	var trigger_global_x: float = panel.get_meta("trigger_global_x", 0.0)
	var local_y = trigger_global_y - panel.global_position.y

	var arr_w = 6.0
	var arr_h = 16.0
	var bg_c = Color(0.04, 0.08, 0.16, 0.92)
	var border_c = Color.from_hsv(EventBus.ui_hue, 0.8, 1.0, 0.8)
	if panel.has_meta("override_border_c"): border_c = panel.get_meta("override_border_c")

	var pts = PackedVector2Array()
	var border_pts = PackedVector2Array()
	# 动态判断面板相对于触发按钮的方位: 中心X对比
	var is_right_side = (panel.global_position.x + panel.size.x/2.0 > trigger_global_x)

	if is_right_side:
		pts.append(Vector2(2.0, local_y - arr_h/2.0))
		pts.append(Vector2(-arr_w, local_y))
		pts.append(Vector2(2.0, local_y + arr_h/2.0))

		border_pts.append(Vector2(0, local_y - arr_h/2.0 + 1.0))
		border_pts.append(Vector2(-arr_w, local_y))
		border_pts.append(Vector2(0, local_y + arr_h/2.0 - 1.0))
	else:
		var w = panel.size.x
		pts.append(Vector2(w - 2.0, local_y - arr_h/2.0))
		pts.append(Vector2(w + arr_w, local_y))
		pts.append(Vector2(w - 2.0, local_y + arr_h/2.0))

		border_pts.append(Vector2(w, local_y - arr_h/2.0 + 1.0))
		border_pts.append(Vector2(w + arr_w, local_y))
		border_pts.append(Vector2(w, local_y + arr_h/2.0 - 1.0))

	panel.draw_colored_polygon(pts, bg_c)
	panel.draw_polyline(border_pts, border_c, panel.get_meta("border_thickness", 2.0), true)

# context_menu.gd — 右键全息追踪面板 (分区级联重构版)
# 管理: 6 个分区入口 → L2 分区面板 → L3 选项面板
# 设置开关 (持久化) + 开机自启动 + 提醒管理入口

extends CanvasLayer

const InfoSidebar = preload("res://ui/context_menu/info_sidebar.gd")
const SysinfoBubble = preload("res://ui/context_menu/sysinfo_bubble.gd")
const MenuTooltip = preload("res://ui/context_menu/menu_tooltip.gd")
const SubmenuSystem = preload("res://ui/context_menu/submenu_system.gd")
const EffectPreview = preload("res://ui/context_menu/effect_preview.gd")

# ── 主菜单分区入口按钮 ──
@onready var hud: PanelContainer = $HUDPanel
@onready var sec_pet_btn: Button = $HUDPanel/Margin/VBox/SecPetBtn
@onready var sec_display_btn: Button = $HUDPanel/Margin/VBox/SecDisplayBtn
@onready var sec_behavior_btn: Button = $HUDPanel/Margin/VBox/SecBehaviorBtn
@onready var sec_visual_btn: Button = $HUDPanel/Margin/VBox/SecVisualBtn
@onready var sec_play_btn: Button = $HUDPanel/Margin/VBox/SecPlayBtn
@onready var sec_system_btn: Button = $HUDPanel/Margin/VBox/SecSystemBtn
@onready var quit_btn: Button = $HUDPanel/Margin/VBox/QuitBtn

var _submenu: SubmenuSystem
var _sidebar: InfoSidebar
var _sysinfo_bubble: SysinfoBubble
var _tooltip: MenuTooltip
var _fx_preview: EffectPreview
var target: Node2D = null

## 菜单展开方向: 1=菜单在宠物右侧, -1=菜单在宠物左侧
var _menu_side: int = 1

# ── L2 分区面板中动态创建的按钮引用 (供回调/状态刷新用) ──
var _chatter_btn: Button
var _window_mode_btn: Button
var _behavior_mode_btn: Button
var _gait_btn: Button
var _mode_btn: Button
var _effects_btn: Button
var _elastic_btn: Button
var _entertain_btn: Button
var _activity_btn: Button
var _clone_btn: Button
var _dismiss_btn: Button
var _sysinfo_btn: Button
var _autostart_btn: Button
var _debug_behavior_btn: Button
var _theme_btn: Button
var _reminder_btn: Button

# ── 小游戏容器 ──
var _game_container: VBoxContainer

# ── 特效配色内嵌按钮 ──
var _effect_color_btns: Array[Button] = []



func _ready() -> void:
	hud.hide()

	_sidebar = InfoSidebar.new(self)
	_sidebar.build()
	_sysinfo_bubble = SysinfoBubble.new(self)
	_tooltip = MenuTooltip.new(self)
	_tooltip.build()
	_submenu = SubmenuSystem.new(self)
	_fx_preview = EffectPreview.new(self)

	# 构建所有分区面板 (L2) + 选项面板 (L3)
	_build_all_sections()

	# 胶囊按钮样式
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

	quit_btn.pressed.connect(_on_quit_btn_pressed)
	EventBus.behavior_mode_changed.connect(_on_behavior_mode_synced)

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

## 子菜单触发按钮: 只响应 hover，不响应点击 (去掉手型光标 + pressed 视觉与 hover 一致)
func _make_hover_only(btn: Button) -> void:
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	btn.add_theme_color_override("font_pressed_color", btn.get_theme_color("font_hover_color"))
	var hover_bg = btn.get_theme_stylebox("hover")
	if hover_bg:
		btn.add_theme_stylebox_override("pressed", hover_bg)
# ═══════════════════════════════════════════
# 分区面板构建 (L2 + L3)
# ═══════════════════════════════════════════

## 构建宠物分区
func _build_sec_pet() -> void:
	var panel = _submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_chatter_btn = _make_menu_btn("碎碎念 · 每30分钟 [+]", Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_chatter_btn)
	_bind_l3_trigger(_chatter_btn, "chatter", "sec_pet")

	_clone_btn = _make_menu_btn("分身 (0/5) [+]", Color(0.2, 0.85, 1.0, 1))
	vbox.add_child(_clone_btn)
	_bind_l3_trigger(_clone_btn, "clone", "sec_pet")

	_reminder_btn = _make_menu_btn("提醒管理", Color(0.2, 0.85, 1.0, 1))
	_apply_capsule_style(_reminder_btn, Color(0.12, 0.22, 0.42, 0.7), Color(0.4, 0.6, 0.9, 0.5))
	_reminder_btn.pressed.connect(func():
		_close_and_emit(EventBus.show_reminder_panel)
	)
	vbox.add_child(_reminder_btn)

	panel.mouse_entered.connect(func(): _submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): _submenu.on_panel_exit())
	add_child(panel)
	_submenu.panels["sec_pet"] = panel

	# L3: 碎碎念单选
	_submenu.create_radio("chatter", [
		{"value": 0, "label": "关闭", "desc": "宠物不会主动说话"},
		{"value": 1, "label": "每30分钟", "desc": "每到整点和半点，冒泡说点什么"},
		{"value": 2, "label": "每60分钟", "desc": "每到整点，冒泡说点什么"},
	], _on_radio_chatter_mode, 3)
	_submenu._l3_parent_map["chatter"] = "sec_pet"

	# L3: 分身操作面板 (手动构建，因为是操作按钮而非开关/单选)
	_build_clone_l3_panel()

## 构建显示分区
func _build_sec_display() -> void:
	# 直接用 L2 面板放开关项 (无需 L3)
	_submenu.create_toggle("sec_display", [
		{"id": "hud_pin", "on": "常驻显示 [●]", "off": "常驻显示 [○]", "key": "hud_pin", "default": false},
		{"id": "hud_clock", "on": "系统时钟 [●]", "off": "系统时钟 [○]", "key": "hud_clock", "default": false},
		{"id": "hud_wifi", "on": "WiFi 信息 [●]", "off": "WiFi 信息 [○]", "key": "hud_wifi", "default": false},
	])

## 构建行为分区
func _build_sec_behavior() -> void:
	var panel = _submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_window_mode_btn = _make_menu_btn("窗口 · 自由漫游 [+]", Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_window_mode_btn)
	_bind_l3_trigger(_window_mode_btn, "window_mode", "sec_behavior")

	_behavior_mode_btn = _make_menu_btn("指令 · 自由行动 [+]", Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_behavior_mode_btn)
	_bind_l3_trigger(_behavior_mode_btn, "behavior_mode", "sec_behavior")

	_gait_btn = _make_menu_btn("步态 · 蹦跳为主 [+]", Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_gait_btn)
	_bind_l3_trigger(_gait_btn, "gait", "sec_behavior")

	_mode_btn = _make_menu_btn("模式 [+]", Color(0.4, 0.7, 1.0, 1))
	vbox.add_child(_mode_btn)
	_bind_l3_trigger(_mode_btn, "mode", "sec_behavior")

	panel.mouse_entered.connect(func(): _submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): _submenu.on_panel_exit())
	add_child(panel)
	_submenu.panels["sec_behavior"] = panel

	# L3 子菜单
	_submenu.create_radio("window_mode", [
		{"value": 0, "label": "自由漫游", "desc": "在窗口间自由行走"},
		{"value": 1, "label": "窗口封闭", "desc": "被困在当前窗口内"},
		{"value": 2, "label": "窗口排斥", "desc": "无法进入任何窗口"},
	], _on_radio_window_mode, 3)
	_submenu._l3_parent_map["window_mode"] = "sec_behavior"

	_submenu.create_radio("behavior_mode", [
		{"value": 0, "label": "自由行动", "desc": "活力满满，随意滚动跳跃"},
		{"value": 1, "label": "安静待命", "desc": "安安静静，乖乖不动"},
	], _on_radio_behavior_mode, 3)
	_submenu._l3_parent_map["behavior_mode"] = "sec_behavior"

	_submenu.create_radio("gait", [
		{"value": 0, "label": "蹦跳为主", "desc": "纯蹦跳移动，不会滚动"},
		{"value": 1, "label": "滚动为主", "desc": "纯滚动移动，不会跳跃"},
		{"value": 2, "label": "混合平衡", "desc": "蹦跳和滚动各半，动静结合"},
	], _on_radio_gait, 3)
	_submenu._l3_parent_map["gait"] = "sec_behavior"

	_submenu.create_toggle("mode", [
		{"id": "eye_track", "on": "指针跟踪 [●]", "off": "指针跟踪 [○]", "key": "eye_track", "default": true},
		{"id": "anti_gravity", "on": "反重力 [●]", "off": "反重力 [○]", "key": "anti_gravity", "default": false},
		{"id": "free_roam", "on": "空间跳跃 [●]", "off": "空间跳跃 [○]", "key": "free_roam", "default": false},
		{"id": "screen_wrap", "on": "屏幕穿越 [●]", "off": "屏幕穿越 [○]", "key": "screen_wrap", "default": false},
	], 3)
	_submenu._l3_parent_map["mode"] = "sec_behavior"
	# 模式子菜单追加踏板外观胶囊
	_append_platform_style_capsule()

## 构建视觉分区
func _build_sec_visual() -> void:
	var panel = _submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_effects_btn = _make_menu_btn("特效 [+]", Color(1.0, 0.85, 0.3, 1))
	vbox.add_child(_effects_btn)
	_bind_l3_trigger(_effects_btn, "effects", "sec_visual")

	_elastic_btn = _make_menu_btn("弹性 · 关闭 [+]", Color(1.0, 0.85, 0.3, 1))
	vbox.add_child(_elastic_btn)
	_bind_l3_trigger(_elastic_btn, "elastic", "sec_visual")

	_theme_btn = _make_menu_btn("外观主题", Color(1.0, 0.85, 0.3, 1))
	_apply_capsule_style(_theme_btn, Color(0.12, 0.22, 0.42, 0.7), Color(0.4, 0.6, 0.9, 0.5))
	_theme_btn.pressed.connect(func():
		_close_and_emit(EventBus.show_theme_panel)
	)
	vbox.add_child(_theme_btn)

	panel.mouse_entered.connect(func(): _submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): _submenu.on_panel_exit())
	add_child(panel)
	_submenu.panels["sec_visual"] = panel

	# L3: 特效开关子菜单
	_submenu.create_toggle("effects", [
		{"id": "shockwave", "on": "撞击冲击波 [●]", "off": "撞击冲击波 [○]", "key": "shockwave", "default": true},
		{"id": "trail_fx", "on": "粒子尾流 [●]", "off": "粒子尾流 [○]", "key": "trail_fx", "default": true},
		{"id": "arc_fx", "on": "静电弧 [●]", "off": "静电弧 [○]", "key": "arc_fx", "default": true},
	], 3)
	_submenu._l3_parent_map["effects"] = "sec_visual"
	_append_effect_color_radio()

	# L3: 弹性形变单选
	_submenu.create_radio("elastic", [
		{"value": 0, "label": "关闭", "desc": "标准球体，无弹性效果"},
		{"value": 1, "label": "轻弹", "desc": "自然柔弹，快速恢复"},
		{"value": 2, "label": "果冻", "desc": "QQ弹弹，慢速晃动恢复"},
		{"value": 3, "label": "弹力球", "desc": "弹性十足，强力回弹"},
	], _on_radio_elastic, 3)
	_submenu._l3_parent_map["elastic"] = "sec_visual"

## 构建玩法分区
func _build_sec_play() -> void:
	var panel = _submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_entertain_btn = _make_menu_btn("娱乐 [+]", Color(0.3, 1.0, 0.7, 1))
	vbox.add_child(_entertain_btn)
	_bind_l3_trigger(_entertain_btn, "entertain", "sec_play")

	_activity_btn = _make_menu_btn("自主活动 · 偶尔 [+]", Color(0.3, 1.0, 0.7, 1))
	vbox.add_child(_activity_btn)
	_bind_l3_trigger(_activity_btn, "auto_activity", "sec_play")

	# 小游戏入口容器 (菜单打开时动态填充，因为 game_mgr 初始化晚于菜单构建)
	_game_container = VBoxContainer.new()
	_game_container.add_theme_constant_override("separation", 6)
	vbox.add_child(_game_container)

	panel.mouse_entered.connect(func(): _submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): _submenu.on_panel_exit())
	add_child(panel)
	_submenu.panels["sec_play"] = panel

	# L3: 娱乐
	_submenu.create_toggle("entertain", [
		{"id": "stroll", "on": "自主巡航 [●]", "off": "自主巡航 [○]", "key": "stroll", "default": true},
	], 3)
	_submenu._l3_parent_map["entertain"] = "sec_play"

	# L3: 自主活动单选
	_submenu.create_radio("auto_activity", [
		{"value": 0, "label": "关闭", "desc": "不会自己玩游戏或跳跃"},
		{"value": 1, "label": "偶尔", "desc": "隔很久才自己动一下"},
		{"value": 2, "label": "频繁", "desc": "经常自己找事做"},
	], _on_radio_auto_activity, 3)
	_submenu._l3_parent_map["auto_activity"] = "sec_play"

## 动态更新小游戏列表 (每次菜单打开时调用)
func _update_game_list() -> void:
	if not _game_container:
		return
	# 清空旧内容
	for child in _game_container.get_children():
		child.queue_free()

	var main_node = get_tree().root.get_node_or_null("Main")
	if not main_node or not ("game_mgr" in main_node) or not main_node.game_mgr:
		return
	var games: Array = main_node.game_mgr.get_installed_games()
	if games.size() == 0:
		return

	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 3)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.3, 0.85, 0.55, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_container.add_child(sep)

	var label = Label.new()
	label.text = "小游戏"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.4, 0.65, 0.5, 0.5))
	_game_container.add_child(label)

	for game_meta in games:
		var gid: String = game_meta.get("id", "")
		var gname: String = game_meta.get("name", gid)
		var gdesc: String = game_meta.get("desc", "")
		var btn = _make_menu_btn(gname, Color(0.3, 1.0, 0.7, 1))
		btn.pressed.connect(func():
			_close_hud()
			EventBus.launch_game.emit(gid)
		)
		btn.tooltip_text = gdesc
		_game_container.add_child(btn)

## 构建系统分区
func _build_sec_system() -> void:
	var panel = _submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_sysinfo_btn = _make_menu_btn("系统信息", Color(0.8, 0.55, 0.55, 1))
	_sysinfo_btn.pressed.connect(_on_sysinfo_btn_pressed)
	vbox.add_child(_sysinfo_btn)

	_autostart_btn = _make_menu_btn("开机自启动 [○]", Color(0.8, 0.55, 0.55, 1))
	_autostart_btn.pressed.connect(_on_autostart_btn_pressed)
	vbox.add_child(_autostart_btn)

	_debug_behavior_btn = _make_menu_btn("指令序列 [+]", Color(1.0, 0.7, 0.2, 1))
	vbox.add_child(_debug_behavior_btn)
	_bind_l3_trigger(_debug_behavior_btn, "debug_behavior", "sec_system")

	panel.mouse_entered.connect(func(): _submenu.on_panel_enter())
	panel.mouse_exited.connect(func(): _submenu.on_panel_exit())
	add_child(panel)
	_submenu.panels["sec_system"] = panel

	# L3: 指令序列
	_build_debug_behavior_submenu()

## 统一入口
func _build_all_sections() -> void:
	_build_sec_pet()
	_build_sec_display()
	_build_sec_behavior()
	_build_sec_visual()
	_build_sec_play()
	_build_sec_system()
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
		var color: Color = def[1]
		var style = StyleBoxFlat.new()
		style.bg_color = Color(color.r * 0.15, color.g * 0.15, color.b * 0.15, 0.4)
		style.border_color = color
		style.border_width_left = 3
		style.border_width_top = 0
		style.border_width_right = 0
		style.border_width_bottom = 0
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
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
	var btn = Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
	btn.add_theme_color_override("font_hover_color", hover_color)
	btn.text = text
	return btn

## 关闭菜单并发射信号 (用于面板入口按钮)
func _close_and_emit(sig: Signal) -> void:
	_tooltip.panel.hide()
	_submenu.hide_all_instant()
	hud.hide()
	_sidebar.panel.hide()
	target = null
	EventBus.context_menu_toggled.emit(false)
	sig.emit()

# ═══════════════════════════════════════════
# 持久化加载
# ═══════════════════════════════════════════

func _load_saved_settings() -> void:
	var eye = SettingsManager.get_bool("eye_track", true)
	# 指针跟踪已迁移到行为分区的模式 L3 toggle

	_refresh_submenu_states()

	var wm = SettingsManager.get_int("window_mode", 0)
	_update_window_mode_label(wm)
	_submenu.refresh_radio("window_mode", wm)

	var bm = SettingsManager.get_int("behavior_mode", 0)
	_update_behavior_mode_label(bm)
	_submenu.refresh_radio("behavior_mode", bm)

	var gm = SettingsManager.get_int("move_style", 0)
	_update_gait_label(gm)
	_submenu.refresh_radio("gait", gm)

	var am = SettingsManager.get_int("auto_activity", 1)
	_update_activity_label(am)
	_submenu.refresh_radio("auto_activity", am)

	var chatter_mode = SettingsManager.get_int("pet_chatter_mode", 1)
	_update_chatter_label(chatter_mode)
	_submenu.refresh_radio("chatter", chatter_mode)

	_autostart_check_pending = true

var _autostart_check_pending := false
var _autostart_check_delay := 0.0

func _check_autostart_deferred(delta: float) -> void:
	if not _autostart_check_pending:
		return
	_autostart_check_delay += delta
	if _autostart_check_delay < 0.5:
		return
	_autostart_check_pending = false
	var win_mgr = _get_win_manager()
	if win_mgr and win_mgr.has_method("IsAutoStartEnabled"):
		var on: bool = win_mgr.call("IsAutoStartEnabled")
		_set_toggle(_autostart_btn, on, "开机自启动 [●]", "开机自启动 [○]")
	else:
		_autostart_btn.text = "开机自启动 [○]"

func _refresh_submenu_states() -> void:
	_submenu.refresh_toggle("shockwave", SettingsManager.get_bool("shockwave", true), "撞击冲击波 [●]", "撞击冲击波 [○]")
	_submenu.refresh_toggle("trail_fx", SettingsManager.get_bool("trail_fx", true), "粒子尾流 [●]", "粒子尾流 [○]")
	_submenu.refresh_toggle("arc_fx", SettingsManager.get_bool("arc_fx", true), "静电弧 [●]", "静电弧 [○]")
	_submenu.refresh_toggle("stroll", SettingsManager.get_bool("stroll", true), "自主巡航 [●]", "自主巡航 [○]")
	_submenu.refresh_toggle("eye_track", SettingsManager.get_bool("eye_track", true), "指针跟踪 [●]", "指针跟踪 [○]")
	_submenu.refresh_toggle("anti_gravity", SettingsManager.get_bool("anti_gravity", false), "反重力 [●]", "反重力 [○]")
	_submenu.refresh_toggle("free_roam", SettingsManager.get_bool("free_roam", false), "空间跳跃 [●]", "空间跳跃 [○]")
	_submenu.refresh_toggle("screen_wrap", SettingsManager.get_bool("screen_wrap", false), "屏幕穿越 [●]", "屏幕穿越 [○]")
	_submenu.refresh_toggle("hud_pin", SettingsManager.get_bool("hud_pin", false), "常驻显示 [●]", "常驻显示 [○]")
	_submenu.refresh_toggle("hud_clock", SettingsManager.get_bool("hud_clock", false), "系统时钟 [●]", "系统时钟 [○]")
	_submenu.refresh_toggle("hud_wifi", SettingsManager.get_bool("hud_wifi", false), "WiFi 信息 [●]", "WiFi 信息 [○]")
	# 弹性形变
	var elastic_mode = SettingsManager.get_int("elastic_mode", 0)
	_apply_elastic_mode(elastic_mode, false)
	# 刷新所有单选菜单
	_submenu.refresh_radio("window_mode", SettingsManager.get_int("window_mode", 0))
	_submenu.refresh_radio("behavior_mode", SettingsManager.get_int("behavior_mode", 0))
	_submenu.refresh_radio("gait", SettingsManager.get_int("move_style", 0))
	_submenu.refresh_radio("chatter", SettingsManager.get_int("chatter_mode", 0))
	_submenu.refresh_radio("elastic", elastic_mode)
	_submenu.refresh_radio("auto_activity", SettingsManager.get_int("auto_activity", 1))

# ═══════════════════════════════════════════
# 弹性追踪 / _process
# ═══════════════════════════════════════════

func _process(delta: float) -> void:
	_check_autostart_deferred(delta)
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
	_sysinfo_bubble.process_tick()
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
	_update_clone_label()
	_update_game_list()

	var pet_pos = target.get_global_transform_with_canvas().get_origin()
	var vp = get_viewport().get_visible_rect().size
	_menu_side = -1 if pet_pos.x > vp.x * 0.5 else 1

	var panel_pos = _calc_menu_pos(pet_pos)
	hud.position = panel_pos
	hud.modulate.a = 0.0
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
# 按钮回调
# ═══════════════════════════════════════════

func _on_autostart_btn_pressed() -> void:
	var win_mgr = _get_win_manager()
	if not win_mgr or not win_mgr.has_method("SetAutoStart"):
		return
	var current: bool = win_mgr.call("IsAutoStartEnabled")
	var new_val = not current
	win_mgr.call("SetAutoStart", new_val)
	_set_toggle(_autostart_btn, new_val, "开机自启动 [●]", "开机自启动 [○]")

# ── 碎碎念 ──

const CHATTER_MODE_LABELS := ["碎碎念 · 已关闭 [+]", "碎碎念 · 每30分钟 [+]", "碎碎念 · 每60分钟 [+]"]

func _on_radio_chatter_mode(value: int) -> void:
	_update_chatter_label(value)
	SettingsManager.set_int("pet_chatter_mode", value)
	EventBus.setting_toggled.emit("pet_chatter_mode", value > 0)
	_submenu.refresh_radio("chatter", value)

func _update_chatter_label(mode: int) -> void:
	_chatter_btn.text = CHATTER_MODE_LABELS[mode]

# ── 窗口模式 ──

const WINDOW_MODE_LABELS := ["窗口 · 自由漫游 [+]", "窗口 · 窗口封闭 [+]", "窗口 · 窗口排斥 [+]"]

func _on_radio_window_mode(value: int) -> void:
	_update_window_mode_label(value)
	EventBus.window_mode_changed.emit(value)
	_submenu.refresh_radio("window_mode", value)

func _update_window_mode_label(mode: int) -> void:
	_window_mode_btn.text = WINDOW_MODE_LABELS[mode]

# ── 行为指令 ──

const BEHAVIOR_MODE_LABELS := ["指令 · 自由行动 [+]", "指令 · 安静待命 [+]"]

func _on_radio_behavior_mode(value: int) -> void:
	_update_behavior_mode_label(value)
	EventBus.behavior_mode_changed.emit(value)
	_submenu.refresh_radio("behavior_mode", value)

func _update_behavior_mode_label(mode: int) -> void:
	_behavior_mode_btn.text = BEHAVIOR_MODE_LABELS[mode]

func _on_behavior_mode_synced(mode: int) -> void:
	_update_behavior_mode_label(mode)
	_submenu.refresh_radio("behavior_mode", mode)

# ── 自主活动 ──

const ACTIVITY_LABELS := ["自主活动 · 已关闭 [+]", "自主活动 · 偶尔 [+]", "自主活动 · 频繁 [+]"]

func _on_radio_auto_activity(value: int) -> void:
	_update_activity_label(value)
	# 直接通知所有宠物实例 (通过 setting_toggled 信号)
	SettingsManager.set_int("auto_activity", value)
	EventBus.setting_toggled.emit("auto_activity", value > 0)
	_submenu.refresh_radio("auto_activity", value)

func _update_activity_label(mode: int) -> void:
	_activity_btn.text = ACTIVITY_LABELS[mode]

# ── 步态 ──

const GAIT_LABELS := ["步态 · 蹦跳为主 [+]", "步态 · 滚动为主 [+]", "步态 · 混合平衡 [+]"]

func _on_radio_gait(value: int) -> void:
	_update_gait_label(value)
	SettingsManager.set_int("move_style", value)
	EventBus.setting_toggled.emit("move_style", value > 0)
	_submenu.refresh_radio("gait", value)

func _update_gait_label(mode: int) -> void:
	_gait_btn.text = GAIT_LABELS[mode]

# ── 分身 ──

## 构建分身操作 L3 面板 (操作按钮，非开关/单选)
func _build_clone_l3_panel() -> void:
	var panel = _submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var deploy_btn = _make_menu_btn("部署分身 (0/5)", Color(0.2, 0.85, 1.0, 1))
	deploy_btn.pressed.connect(_on_deploy_clone_pressed)
	vbox.add_child(deploy_btn)
	_deploy_clone_btn = deploy_btn

	_dismiss_btn = _make_menu_btn("回收全部分身", Color(0.2, 0.85, 1.0, 1))
	_dismiss_btn.add_theme_color_override("font_color", Color(0.55, 0.7, 0.75, 0.7))
	_dismiss_btn.pressed.connect(_on_dismiss_btn_pressed)
	vbox.add_child(_dismiss_btn)

	panel.mouse_entered.connect(func(): _submenu.on_l3_panel_enter())
	panel.mouse_exited.connect(func(): _submenu.on_l3_panel_exit())
	add_child(panel)
	_submenu.l3_panels["clone"] = panel
	_submenu._l3_parent_map["clone"] = "sec_pet"

var _deploy_clone_btn: Button

func _on_deploy_clone_pressed() -> void:
	if is_instance_valid(target):
		EventBus.clone_pet.emit(target)
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
		_clone_btn.text = "分身 (" + str(count) + "/" + str(max_c) + ") [+]"
		if _deploy_clone_btn:
			_deploy_clone_btn.text = "部署分身 (" + str(count) + "/" + str(max_c) + ")"

# ── 退出 ──

func _on_quit_btn_pressed() -> void:
	_tooltip.panel.hide()
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

	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and main_node.has_method("quit_with_farewell"):
		main_node.quit_with_farewell()
	else:
		get_tree().quit()

func _on_sysinfo_btn_pressed() -> void:
	_close_hud()
	_sysinfo_bubble.trigger()


# ═══════════════════════════════════════════
# 特效配色
# ═══════════════════════════════════════════

func _append_effect_color_radio() -> void:
	var effects_panel = _submenu.l3_panels.get("effects")
	if not effects_panel:
		return
	var vbox = effects_panel.get_child(0)

	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 3)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	var label = Label.new()
	label.text = "特效配色"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75, 0.5))
	vbox.add_child(label)

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
	var labels = ["虹彩模式", "跟随体色"]
	for i in range(_effect_color_btns.size()):
		_effect_color_btns[i].text = labels[i] + (" [●]" if i == value else " [○]")



# ═══════════════════════════════════════════
# 踏板外观胶囊
# ═══════════════════════════════════════════

func _append_platform_style_capsule() -> void:
	var mode_panel = _submenu.l3_panels.get("mode")
	if not mode_panel: return
	var vbox = mode_panel.get_child(0) as VBoxContainer
	if not vbox: return

	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.8, 1.0, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	var btn = Button.new()
	btn.text = "踏板外观"
	btn.add_theme_font_size_override("font_size", 17)
	_apply_capsule_style(btn,
		Color(0.08, 0.15, 0.3, 0.5),
		Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.35))
	btn.pressed.connect(func():
		_close_and_emit(EventBus.show_platform_style_panel)
	)
	vbox.add_child(btn)

# ═══════════════════════════════════════════
# 弹性形变
# ═══════════════════════════════════════════

func _on_radio_elastic(value: int) -> void:
	SettingsManager.set_int("elastic_mode", value)
	_apply_elastic_mode(value, true)

func _apply_elastic_mode(value: int, emit_signal: bool) -> void:
	if value == 0:
		_elastic_btn.text = "弹性 · 关闭 [+]"
		if emit_signal:
			EventBus.trigger_squash_test.emit(-1)
	else:
		var names := ["轻弹", "果冻", "弹力球"]
		var idx = clampi(value - 1, 0, 2)
		_elastic_btn.text = "弹性 · " + names[idx] + " [+]"
		if emit_signal:
			EventBus.trigger_squash_test.emit(idx)

# ═══════════════════════════════════════════
# 指令序列 (调试行为子菜单)
# ═══════════════════════════════════════════

func _build_debug_behavior_submenu() -> void:
	var panel = _submenu._make_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var debug_items := [
		{"label": "眼睑下垂", "behavior": "drowsy", "desc": "模拟困倦半闭眼效果"},
		{"label": "引导循环", "behavior": "loader", "desc": "显示加载旋转器动画"},
		{"label": "能源监测", "behavior": "battery", "desc": "显示电池充电图标"},
		{"label": "诊断扫描", "behavior": "scanning", "desc": "触发检索扫描动画"},
		{"label": "状态确认", "behavior": "scan_done", "desc": "触发扫描完成打勾动画"},
		{"label": "邮件标识", "behavior": "_icon:mail", "desc": "显示未读邮件图标"},
		{"label": "警告标识", "behavior": "_icon:alert", "desc": "显示警告感叹号图标"},
		{"label": "待解标识", "behavior": "_icon:question", "desc": "显示问号疑问图标"},
		{"label": "错误标识", "behavior": "_icon:error", "desc": "显示操作失败交叉图标"},
		{"label": "碎碎念", "behavior": "_chatter", "desc": "立即触发一次碎碎念气泡"},
		{"label": "空间跳跃", "behavior": "_free_roam", "desc": "触发一次空间跳跃踏板序列"},
		{"label": "自动对弈", "behavior": "_auto_game_2048", "desc": "宠物自己玩一局 2048"},
		{"label": "自动扫雷", "behavior": "_auto_game_mine", "desc": "宠物自己玩一局扫雷"},
		{"label": "自动导航", "behavior": "_auto_game_snake", "desc": "宠物自己玩一局贪吃蛇"},
	]

	for item in debug_items:
		var btn = Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.2, 1))
		btn.text = item.label
		var behavior = item.behavior
		btn.pressed.connect(func(): _on_debug_behavior_pressed(behavior))
		if item.has("desc"):
			var desc_text = item.desc
			var b = btn
			btn.mouse_entered.connect(func(): _tooltip.show_for(b, desc_text, true))
			btn.mouse_exited.connect(func(): _tooltip.show_for(b, desc_text, false))
		vbox.add_child(btn)

	panel.mouse_entered.connect(func(): _submenu.on_l3_panel_enter())
	panel.mouse_exited.connect(func(): _submenu.on_l3_panel_exit())
	add_child(panel)
	_submenu.l3_panels["debug_behavior"] = panel
	_submenu._l3_parent_map["debug_behavior"] = "sec_system"

func _on_debug_behavior_pressed(behavior: String) -> void:
	_tooltip.panel.hide()
	_submenu.hide_all_instant()
	hud.hide()
	_sidebar.panel.hide()
	target = null
	EventBus.context_menu_toggled.emit(false)

	# 深夜模式拒绝执行
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and "pet_instances" in main_node:
		var pets: Array = main_node.pet_instances
		if pets.size() > 0:
			var pet = pets[0]
			if "nighttime_mode" in pet and pet.nighttime_mode:
				pet.show_local_bubble("休眠周期中。指令已搁置。")
				return

	if behavior.begins_with("_icon:"):
		var icon_type = behavior.substr(6)
		EventBus.pet_show_eye_icon.emit(icon_type)
		await get_tree().create_timer(5.0).timeout
		EventBus.pet_show_eye_icon.emit("")
	elif behavior == "_chatter":
		if main_node:
			for child in main_node.get_children():
				if child.has_method("_trigger_chatter"):
					child._trigger_chatter()
					return
		EventBus.show_reminder_bubble.emit("碎碎念系统未就绪。")
	elif behavior == "_free_roam":
		EventBus.trigger_free_roam.emit()
	elif behavior == "_auto_game_2048":
		EventBus.launch_game_auto.emit("2048")
	elif behavior == "_auto_game_mine":
		EventBus.launch_game_auto.emit("minesweeper")
	elif behavior == "_auto_game_snake":
		EventBus.launch_game_auto.emit("snake")
	else:
		EventBus.trigger_idle_behavior.emit(behavior)

# ═══════════════════════════════════════════
# UI 主题色
# ═══════════════════════════════════════════

func _apply_ui_theme(hue: float) -> void:
	var style = hud.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style = style.duplicate()
		style.border_color = Color.from_hsv(hue, 0.8, 1.0, 0.8)
		hud.add_theme_stylebox_override("panel", style)
	if _submenu and _submenu.has_method("apply_ui_theme"):
		_submenu.apply_ui_theme(hue)
	if _sidebar and _sidebar.has_method("apply_ui_theme"):
		_sidebar.apply_ui_theme(hue)

# ═══════════════════════════════════════════
# 工具函数
# ═══════════════════════════════════════════

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

# context_menu.gd — 右键全息追踪面板
# 管理: 设置开关 (持久化) + 开机自启动 + 提醒管理入口
extends CanvasLayer

@onready var hud: PanelContainer = $HUDPanel
@onready var date_label: Label = $HUDPanel/Margin/VBox/DateLabel
@onready var track_btn: Button = $HUDPanel/Margin/VBox/EyeTrackBtn
@onready var shockwave_btn: Button = $HUDPanel/Margin/VBox/ShockwaveBtn
@onready var trail_btn: Button = $HUDPanel/Margin/VBox/TrailBtn
@onready var hud_clock_btn: Button = $HUDPanel/Margin/VBox/HUDClockBtn
@onready var autostart_btn: Button = $HUDPanel/Margin/VBox/AutoStartBtn
@onready var window_mode_btn: Button = $HUDPanel/Margin/VBox/WindowModeBtn
@onready var behavior_mode_btn: Button = $HUDPanel/Margin/VBox/BehaviorModeBtn
@onready var chatter_btn: Button = $HUDPanel/Margin/VBox/ChatterBtn
@onready var reminder_btn: Button = $HUDPanel/Margin/VBox/ReminderBtn
@onready var clone_btn: Button = $HUDPanel/Margin/VBox/CloneBtn
@onready var dismiss_btn: Button = $HUDPanel/Margin/VBox/DismissBtn
@onready var quit_btn: Button = $HUDPanel/Margin/VBox/QuitBtn

var _tooltip_panel: PanelContainer
var _tooltip_label: Label
var _tooltip_tween: Tween

var target: Node2D = null

func _ready() -> void:
	hud.hide()
	_build_mode_tooltip()
	
	# 从持久化存储恢复上次的设置状态
	_load_saved_settings()
	
	EventBus.show_context_menu.connect(_on_show_context_menu)
	track_btn.pressed.connect(_on_track_btn_pressed)
	shockwave_btn.pressed.connect(_on_shockwave_btn_pressed)
	trail_btn.pressed.connect(_on_trail_btn_pressed)
	hud_clock_btn.pressed.connect(_on_hud_clock_btn_pressed)
	autostart_btn.pressed.connect(_on_autostart_btn_pressed)
	window_mode_btn.pressed.connect(_on_window_mode_btn_pressed)
	window_mode_btn.mouse_entered.connect(func(): _show_mode_desc(true))
	window_mode_btn.mouse_exited.connect(func(): _show_mode_desc(false))
	behavior_mode_btn.pressed.connect(_on_behavior_mode_btn_pressed)
	behavior_mode_btn.mouse_entered.connect(func(): _show_behavior_desc(true))
	behavior_mode_btn.mouse_exited.connect(func(): _show_behavior_desc(false))
	chatter_btn.pressed.connect(_on_chatter_btn_pressed)
	chatter_btn.mouse_entered.connect(func(): _show_chatter_desc(true))
	chatter_btn.mouse_exited.connect(func(): _show_chatter_desc(false))
	reminder_btn.pressed.connect(_on_reminder_btn_pressed)
	clone_btn.pressed.connect(_on_clone_btn_pressed)
	dismiss_btn.pressed.connect(_on_dismiss_btn_pressed)
	quit_btn.pressed.connect(_on_quit_btn_pressed)
	
	# 监听外部行为模式变化同步按钮状态
	EventBus.behavior_mode_changed.connect(_on_behavior_mode_synced)

# ── 持久化加载 ──

func _load_saved_settings() -> void:
	var eye = SettingsManager.get_bool("eye_track", true)
	var shock = SettingsManager.get_bool("shockwave", true)
	var trail = SettingsManager.get_bool("trail_fx", true)
	var clock = SettingsManager.get_bool("hud_clock", false)
	
	# 应用到本地按钮显示 (pet 自己从 SettingsManager 读取，不依赖信号)
	_set_toggle(track_btn, eye, "◉ 眼球追踪鼠标", "○ 眼球追踪鼠标")
	_set_toggle(shockwave_btn, shock, "◉ 撞击冲击波特效", "○ 撞击冲击波特效")
	_set_toggle(trail_btn, trail, "◉ 粒子尾流特效", "○ 粒子尾流特效")
	_set_toggle(hud_clock_btn, clock, "◉ 赛博全息时钟", "○ 赛博全息时钟")
	
	# 窗口交互模式状态
	var wm = SettingsManager.get_int("window_mode", 0)
	_update_window_mode_label(wm)
	
	# 行为指令状态
	var bm = SettingsManager.get_int("behavior_mode", 0)
	_update_behavior_mode_label(bm)
	
	# 宠物碎碎念模式
	var chatter_mode = SettingsManager.get_int("pet_chatter_mode", 1)
	_update_chatter_label(chatter_mode)
	
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
		var target_pos = target.get_global_transform_with_canvas().get_origin() + Vector2(45, -65)
		target_pos = _clamp_to_viewport(target_pos)
		hud.position = hud.position.lerp(target_pos, delta * 15.0)
	# tooltip 跟随按钮位置
	if _tooltip_panel.visible:
		_update_tooltip_position()

func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	var hs = hud.size
	pos.x = clampf(pos.x, 4.0, vp.x - hs.x - 4.0)
	pos.y = clampf(pos.y, 4.0, vp.y - hs.y - 4.0)
	return pos

# ── 菜单开关 ──

func _on_show_context_menu(target_node: Node2D) -> void:
	target = target_node
	if hud.visible:
		_close_hud()
		return
	EventBus.context_menu_toggled.emit(true)
	_update_clone_label()  # 每次开菜单时刷新克隆计数
	_update_date_label()   # 刷新日期显示
	var pet_pos = target.get_global_transform_with_canvas().get_origin()
	var panel_pos = _clamp_to_viewport(pet_pos + Vector2(45, -65))
	hud.position = panel_pos
	hud.modulate.a = 0.0
	hud.show()
	# 等待一帧让布局计算出 size，再设缩放锚点
	await get_tree().process_frame
	# 缩放锚点设在宠物相对于面板的位置 → 面板从宠物处绽放展开
	hud.pivot_offset = pet_pos - hud.position
	hud.scale = Vector2(0.3, 0.3)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(hud, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(hud, "modulate:a", 1.0, 0.2)

func _close_hud() -> void:
	# 关闭时确保 tooltip 也消失
	_tooltip_panel.hide()
	# 收缩回宠物位置：更新锚点到当前宠物坐标
	if is_instance_valid(target):
		hud.pivot_offset = target.get_global_transform_with_canvas().get_origin() - hud.position
	# 穿透恢复延迟到动画结束，防止淡出中途被 DWM 裁剪
	var tween = create_tween().set_parallel(true)
	tween.tween_property(hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(hud, "modulate:a", 0.0, 0.15)
	tween.finished.connect(func():
		hud.hide()
		EventBus.context_menu_toggled.emit(false)
	)
	target = null

# ── 按钮回调 ──

func _on_track_btn_pressed() -> void:
	var on = _flip_toggle(track_btn, "◉ 眼球追踪鼠标", "○ 眼球追踪鼠标")
	SettingsManager.set_bool("eye_track", on)
	EventBus.setting_toggled.emit("eye_track", on)

func _on_shockwave_btn_pressed() -> void:
	var on = _flip_toggle(shockwave_btn, "◉ 撞击冲击波特效", "○ 撞击冲击波特效")
	SettingsManager.set_bool("shockwave", on)
	EventBus.setting_toggled.emit("shockwave", on)

func _on_trail_btn_pressed() -> void:
	var on = _flip_toggle(trail_btn, "◉ 粒子尾流特效", "○ 粒子尾流特效")
	SettingsManager.set_bool("trail_fx", on)
	EventBus.setting_toggled.emit("trail_fx", on)

func _on_hud_clock_btn_pressed() -> void:
	var on = _flip_toggle(hud_clock_btn, "◉ 赛博全息时钟", "○ 赛博全息时钟")
	SettingsManager.set_bool("hud_clock", on)
	EventBus.setting_toggled.emit("hud_clock", on)

func _on_autostart_btn_pressed() -> void:
	var win_mgr = _get_win_manager()
	if not win_mgr or not win_mgr.has_method("SetAutoStart"):
		return
	var current: bool = win_mgr.call("IsAutoStartEnabled")
	var new_val = not current
	win_mgr.call("SetAutoStart", new_val)
	_set_toggle(autostart_btn, new_val, "◉ 开机自启动", "○ 开机自启动")

# ── 碎碎念模式切换 ──

const CHATTER_MODE_LABELS := ["○ 宠物碎碎念", "◉ 碎碎念·30分钟", "◉ 碎碎念·60分钟"]
const CHATTER_MODE_DESCS := [
	"已关闭，宠物不会主动说话",
	"每到整点和半点，宠物会冒泡说点什么",
	"每到整点，宠物会冒泡说点什么",
]

func _on_chatter_btn_pressed() -> void:
	var current = SettingsManager.get_int("pet_chatter_mode", 1)
	var next_mode = (current + 1) % 3
	_update_chatter_label(next_mode)
	SettingsManager.set_int("pet_chatter_mode", next_mode)
	EventBus.setting_toggled.emit("pet_chatter_mode", next_mode > 0)
	# 如果 tooltip 正在显示则即时更新
	if _tooltip_panel.visible and _active_tooltip_btn == chatter_btn:
		_tooltip_label.text = CHATTER_MODE_DESCS[next_mode]

func _update_chatter_label(mode: int) -> void:
	chatter_btn.text = CHATTER_MODE_LABELS[mode]

func _show_chatter_desc(show: bool) -> void:
	var mode = SettingsManager.get_int("pet_chatter_mode", 1)
	_show_tooltip_for(chatter_btn, CHATTER_MODE_DESCS[mode], show)

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
	if main_node and main_node.has_method("get") and "pet_instances" in main_node:
		var count: int = (main_node.pet_instances as Array).size() - 1
		var max_c: int = main_node.MAX_CLONES
		clone_btn.text = "🧬 召唤分身 (" + str(count) + "/" + str(max_c) + ")"

func _update_date_label() -> void:
	var d = Time.get_date_dict_from_system()
	var weekdays = ["日", "一", "二", "三", "四", "五", "六"]
	var wd = weekdays[d.weekday % 7]
	date_label.text = "%d年%02d月%02d日 (周%s)" % [d.year, d.month, d.day, wd]

# ── 退出按钮 ──

func _on_quit_btn_pressed() -> void:
	# 关闭菜单
	_tooltip_panel.hide()
	if is_instance_valid(target):
		hud.pivot_offset = target.get_global_transform_with_canvas().get_origin() - hud.position
	var tween = create_tween().set_parallel(true)
	tween.tween_property(hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(hud, "modulate:a", 0.0, 0.15)
	tween.finished.connect(func():
		hud.hide()
		EventBus.context_menu_toggled.emit(false)
	)
	target = null
	# 调用 main.gd 的告别退出
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and main_node.has_method("quit_with_farewell"):
		main_node.quit_with_farewell()
	else:
		get_tree().quit()

# ── 窗口模式切换 ──

const WINDOW_MODE_LABELS := ["🌍 自由漫游", "🔒 窗口封闭", "🚫 窗口排斥"]
const WINDOW_MODE_DESCS := [
	"在窗口间自由行走，不受限制",
	"被困在当前窗口内，无法离开",
	"无法进入任何窗口，但可以出来",
]

func _on_window_mode_btn_pressed() -> void:
	var current = SettingsManager.get_int("window_mode", 0)
	var next_mode = (current + 1) % 3
	_update_window_mode_label(next_mode)
	EventBus.window_mode_changed.emit(next_mode)
	# 如果 tooltip 正在显示则即时更新文字
	if _tooltip_panel.visible and _active_tooltip_btn == window_mode_btn:
		_tooltip_label.text = WINDOW_MODE_DESCS[next_mode]

func _update_window_mode_label(mode: int) -> void:
	window_mode_btn.text = WINDOW_MODE_LABELS[mode]

# ── 行为指令切换 ──

const BEHAVIOR_MODE_LABELS := ["🏃 自由行动", "🧘 安静待命"]
const BEHAVIOR_MODE_DESCS := [
	"正常滚动、跳跃，活力满满",
	"安安静静，乖乖不动",
]

func _on_behavior_mode_btn_pressed() -> void:
	var current = SettingsManager.get_int("behavior_mode", 0)
	var next_mode = (current + 1) % 2
	_update_behavior_mode_label(next_mode)
	EventBus.behavior_mode_changed.emit(next_mode)
	# 如果 tooltip 正在显示则即时更新文字
	if _tooltip_panel.visible and _active_tooltip_btn == behavior_mode_btn:
		_tooltip_label.text = BEHAVIOR_MODE_DESCS[next_mode]

func _update_behavior_mode_label(mode: int) -> void:
	behavior_mode_btn.text = BEHAVIOR_MODE_LABELS[mode]

func _on_behavior_mode_synced(mode: int) -> void:
	# 同步按钮文字
	_update_behavior_mode_label(mode)

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
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
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
	var right_x = btn_pos.x + btn_size.x + 10
	if right_x + tip_w > vp_size.x - 10:
		# 左侧弹出
		_tooltip_panel.position = Vector2(btn_pos.x - tip_w - 10, y_pos)
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

func _show_mode_desc(show: bool) -> void:
	var mode = SettingsManager.get_int("window_mode", 0)
	_show_tooltip_for(window_mode_btn, WINDOW_MODE_DESCS[mode], show)

func _show_behavior_desc(show: bool) -> void:
	var mode = SettingsManager.get_int("behavior_mode", 0)
	_show_tooltip_for(behavior_mode_btn, BEHAVIOR_MODE_DESCS[mode], show)

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
		if not rect.has_point(local_mouse):
			_close_hud()
			get_viewport().set_input_as_handled()  # 消费事件，防止穿透到宠物

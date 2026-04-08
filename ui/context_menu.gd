# context_menu.gd — 右键全息追踪面板
# 管理: 设置开关 (持久化) + 开机自启动 + 提醒管理入口
extends CanvasLayer

@onready var hud: PanelContainer = $HUDPanel
@onready var track_btn: Button = $HUDPanel/Margin/VBox/EyeTrackBtn
@onready var shockwave_btn: Button = $HUDPanel/Margin/VBox/ShockwaveBtn
@onready var autostart_btn: Button = $HUDPanel/Margin/VBox/AutoStartBtn
@onready var reminder_btn: Button = $HUDPanel/Margin/VBox/ReminderBtn

var target: Node2D = null

func _ready() -> void:
	hud.hide()
	
	# 从持久化存储恢复上次的设置状态
	_load_saved_settings()
	
	EventBus.show_context_menu.connect(_on_show_context_menu)
	track_btn.pressed.connect(_on_track_btn_pressed)
	shockwave_btn.pressed.connect(_on_shockwave_btn_pressed)
	autostart_btn.pressed.connect(_on_autostart_btn_pressed)
	reminder_btn.pressed.connect(_on_reminder_btn_pressed)

# ── 持久化加载 ──

func _load_saved_settings() -> void:
	var eye = SettingsManager.get_bool("eye_track", true)
	var shock = SettingsManager.get_bool("shockwave", true)
	
	# 应用到本地按钮显示 (pet 自己从 SettingsManager 读取，不依赖信号)
	_set_toggle(track_btn, eye, "[X] 眼睛跟随鼠标", "[  ] 眼睛跟随鼠标")
	_set_toggle(shockwave_btn, shock, "[X] 撞击冲击波特效", "[  ] 撞击冲击波特效")
	
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
		_set_toggle(autostart_btn, on, "[X] 开机自启动", "[  ] 开机自启动")
	else:
		autostart_btn.text = "[  ] 开机自启动"

# ── 弹性追踪 (含边界钳制) ──

func _process(delta: float) -> void:
	_check_autostart_deferred(delta)
	if hud.visible and is_instance_valid(target):
		var target_pos = target.get_global_transform_with_canvas().get_origin() + Vector2(35, -55)
		target_pos = _clamp_to_viewport(target_pos)
		hud.position = hud.position.lerp(target_pos, delta * 15.0)

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
	hud.position = _clamp_to_viewport(target.get_global_transform_with_canvas().get_origin())
	hud.scale = Vector2(0.5, 0.5)
	hud.modulate.a = 0.0
	hud.show()
	var tween = create_tween().set_parallel(true)
	tween.tween_property(hud, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(hud, "modulate:a", 1.0, 0.2)

func _close_hud() -> void:
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
	var on = _flip_toggle(track_btn, "[X] 眼睛跟随鼠标", "[  ] 眼睛跟随鼠标")
	SettingsManager.set_bool("eye_track", on)
	EventBus.setting_toggled.emit("eye_track", on)

func _on_shockwave_btn_pressed() -> void:
	var on = _flip_toggle(shockwave_btn, "[X] 撞击冲击波特效", "[  ] 撞击冲击波特效")
	SettingsManager.set_bool("shockwave", on)
	EventBus.setting_toggled.emit("shockwave", on)

func _on_autostart_btn_pressed() -> void:
	var win_mgr = _get_win_manager()
	if not win_mgr or not win_mgr.has_method("SetAutoStart"):
		return
	var current: bool = win_mgr.call("IsAutoStartEnabled")
	var new_val = not current
	win_mgr.call("SetAutoStart", new_val)
	_set_toggle(autostart_btn, new_val, "[X] 开机自启动", "[  ] 开机自启动")

func _on_reminder_btn_pressed() -> void:
	# 只做视觉关闭，不发 toggled(false)，把穿透控制权移交给提醒面板
	var tween = create_tween().set_parallel(true)
	tween.tween_property(hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(hud, "modulate:a", 0.0, 0.15)
	tween.finished.connect(func(): hud.hide())
	target = null
	EventBus.show_reminder_panel.emit()

# ── 工具函数 ──

func _set_toggle(btn: Button, is_on: bool, on_text: String, off_text: String) -> void:
	btn.text = on_text if is_on else off_text

func _flip_toggle(btn: Button, on_text: String, off_text: String) -> bool:
	var is_on = btn.text.begins_with("[X]")
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

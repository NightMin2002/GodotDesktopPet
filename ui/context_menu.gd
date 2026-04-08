extends CanvasLayer

@onready var hud: PanelContainer = $HUDPanel
@onready var track_btn: Button = $HUDPanel/Margin/VBox/EyeTrackBtn

var target: Node2D = null
var eye_track_enabled := true

func _ready() -> void:
	hud.hide()
	EventBus.show_context_menu.connect(_on_show_context_menu)
	track_btn.pressed.connect(_on_track_btn_pressed)

func _process(delta: float) -> void:
	# 如果菜单打开且目标存在，持续进行弹性随动
	if hud.visible and is_instance_valid(target):
		var target_pos = target.get_global_transform_with_canvas().get_origin() + Vector2(35, -55)
		# Lerp 实现非常平滑的阻尼追踪
		hud.position = hud.position.lerp(target_pos, delta * 15.0)

func _on_show_context_menu(target_node: Node2D) -> void:
	target = target_node
	
	if hud.visible:
		_close_hud()
		return
		
	# 通知 main 开启全屏鼠标防穿透接管
	EventBus.context_menu_toggled.emit(true)
	
	# 从宠物中心生长弹出
	hud.position = target.get_global_transform_with_canvas().get_origin()
	hud.scale = Vector2(0.5, 0.5)
	hud.modulate.a = 0.0
	hud.show()
	
	# Q弹呼出动画 (Tween)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(hud, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(hud, "modulate:a", 1.0, 0.2)
	
func _close_hud() -> void:
	# 关闭全屏防穿透
	EventBus.context_menu_toggled.emit(false)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(hud, "modulate:a", 0.0, 0.15)
	tween.finished.connect(func(): hud.hide())
	target = null

func _on_track_btn_pressed() -> void:
	eye_track_enabled = not eye_track_enabled
	_update_btn_text()
	EventBus.setting_toggled.emit("eye_track", eye_track_enabled)

func _update_btn_text() -> void:
	if eye_track_enabled:
		track_btn.text = "[X] 眼睛跟随鼠标"
	else:
		track_btn.text = "[  ] 眼睛跟随鼠标"

# 点击 UI 黑框之外的宇宙，自动关闭菜单
func _unhandled_input(event: InputEvent) -> void:
	if hud.visible and event is InputEventMouseButton and event.pressed:
		var local_mouse = hud.get_local_mouse_position()
		var rect = Rect2(Vector2.ZERO, hud.size)
		if not rect.has_point(local_mouse):
			_close_hud()

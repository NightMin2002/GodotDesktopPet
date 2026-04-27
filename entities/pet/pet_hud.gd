# pet_hud.gd — 宠物本地气泡管理器
# 管理: 本地定向气泡 (戳一戳/吐槽/提醒，支持向上堆叠)
# 时钟已迁移至 hud_panel.gd 统一 HUD 面板
class_name PetHUD
extends RefCounted

var pet: RigidBody2D  # 宿主宠物引用

# ── 本地定向气泡 ──
const MAX_LOCAL_BUBBLES := 3
var _local_bubbles: Array[PanelContainer] = []

# ── 初始化 ──

func init_bubbles() -> void:
	pass  # 气泡按需创建，无需预初始化

# ── 主更新 (由 pet._process 调用) ──

func update(delta: float) -> void:
	_update_bubble_stacking(delta)


# ── 本地气泡系统 ──

## 创建一个本地气泡面板 (每次调用 show_bubble 动态创建)
func _create_bubble_panel(message: String) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.top_level = true  # 脱离刚体物理旋转
	panel.custom_minimum_size = Vector2(60, 30)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.1, 0.2, 0.92)
	var border_hue = fmod(0.13 + pet.clone_hue_shift, 1.0)  # 金色基底 + 色偏
	style.border_color = Color.from_hsv(border_hue, 0.7, 1.0, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	
	var label = Label.new()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.85, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = message
	panel.add_child(label)
	return panel

func show_bubble(message: String) -> void:
	# 超出上限时移除最旧的气泡
	while _local_bubbles.size() >= MAX_LOCAL_BUBBLES:
		var oldest = _local_bubbles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	
	var panel = _create_bubble_panel(message)
	pet.add_child(panel)
	_local_bubbles.append(panel)
	
	# 弹入动画
	var pet_pos = pet.get_global_transform_with_canvas().get_origin()
	var init_bubble_y = 50.0 if pet.anti_gravity else -90.0
	panel.position = pet_pos + Vector2(-80, init_bubble_y)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.5, 0.5)
	panel.show()
	
	var tween = pet.create_tween().set_parallel(true)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	
	# 独立协程管理消亡 (不影响其他气泡)
	_schedule_bubble_removal(panel)

## 气泡到期后淡出上飘并销毁
func _schedule_bubble_removal(panel: PanelContainer) -> void:
	await pet.get_tree().create_timer(4.0).timeout
	if not is_instance_valid(panel): return
	
	var fade = pet.create_tween().set_parallel(true)
	fade.tween_property(panel, "modulate:a", 0.0, 0.6)
	var fade_y = 30.0 if pet.anti_gravity else -30.0
	fade.tween_property(panel, "position:y", panel.position.y + fade_y, 0.6)
	await fade.finished
	if not is_instance_valid(panel): return
	_local_bubbles.erase(panel)
	panel.queue_free()

## 返回所有可见本地气泡的屏幕矩形 (供 main.gd 作为独立 DWM 小矩形注册)
func get_bubble_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for panel in _local_bubbles:
		if is_instance_valid(panel) and panel.visible:
			var r = Rect2(panel.position, panel.get_combined_minimum_size())
			r = r.grow(5)
			result.append(r)
	return result

## 获取当前气泡数量 (供外部判断)
func get_bubble_count() -> int:
	return _local_bubbles.size()

## 本地气泡堆叠跟随宠物位置 (最新的最靠近宠物，旧的依次向上推)
func _update_bubble_stacking(delta: float) -> void:
	if _local_bubbles.size() == 0:
		return
	
	# 清理已释放的无效引用
	var valid_bubbles: Array[PanelContainer] = []
	for b in _local_bubbles:
		if is_instance_valid(b) and b.visible:
			valid_bubbles.append(b)
	_local_bubbles = valid_bubbles
	
	var pet_pos = pet.get_global_transform_with_canvas().get_origin()
	var stack_y := 0.0
	var vp = pet.get_viewport_rect().size
	# 从最新到最旧遍历 (最新的紧贴宠物头顶)
	for i in range(_local_bubbles.size() - 1, -1, -1):
		var panel = _local_bubbles[i]
		var min_size = panel.get_combined_minimum_size()
		var bubble_y: float
		if pet.anti_gravity:
			bubble_y = 50 + stack_y  # 宠物下方向下堆叠
		else:
			bubble_y = -90 - stack_y  # 宠物上方向上堆叠
		var target_pos = pet_pos + Vector2(-min_size.x / 2.0, bubble_y)
		target_pos.x = clampf(target_pos.x, 8, vp.x - min_size.x - 8)
		target_pos.y = clampf(target_pos.y, 8, vp.y - min_size.y - 8)
		panel.position = panel.position.lerp(target_pos, delta * 10.0)
		stack_y += min_size.y + 6  # 堆叠间距

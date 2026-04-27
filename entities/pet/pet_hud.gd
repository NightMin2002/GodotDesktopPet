# pet_hud.gd — 宠物 HUD + 本地气泡管理器
# 管理: 全息时钟 HUD、本地定向气泡 (戳一戳/吐槽/提醒，支持向上堆叠)
# 从 pet.gd 拆分，与 eye_behavior.gd 同为 RefCounted 轻量挂载
class_name PetHUD
extends RefCounted

var pet: RigidBody2D  # 宿主宠物引用

# ── 全息时钟 HUD ──
var clock_label: Label
var clock_enabled: bool = false
var _bounce_time: float = 0.0
var _is_clock_hidden: bool = false

# ── 本地定向气泡 ──
const MAX_LOCAL_BUBBLES := 3
var _local_bubbles: Array[PanelContainer] = []

# ── 初始化 ──

func init_clock() -> void:
	clock_label = Label.new()
	clock_label.top_level = true # 脱离刚体物理旋转限定，保持悬浮
	# 极简高对比机能风：纯黑字核 + 闪亮的白金光晕边框
	clock_label.add_theme_font_size_override("font_size", 16)
	clock_label.add_theme_color_override("font_color", Color(0.02, 0.02, 0.02, 0.9)) # 核心深邃黑
	clock_label.add_theme_color_override("font_outline_color", Color(0.9, 0.95, 1.0, 0.9)) # 强力抗白光抗锯齿泛白边
	clock_label.add_theme_constant_override("outline_size", 6)
	clock_label.visible = clock_enabled
	pet.add_child(clock_label)

# ── 主更新 (由 pet._process 调用) ──

func update(delta: float) -> void:
	_update_clock(delta)
	_update_bubble_stacking(delta)

# ── 全息时钟 ──

func _update_clock(delta: float) -> void:
	if not clock_enabled or not is_instance_valid(clock_label):
		return
	
	_bounce_time += delta * 2.0
	var time_dict = Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d:%02d" % [time_dict.hour, time_dict.minute, time_dict.second]
	
	# 加入类似 AR 投影悬浮抖动的垂直缓动数学波
	var float_y = sin(_bounce_time) * 4.0
	var text_size = clock_label.get_minimum_size()
	var clock_offset_y: float
	if pet.anti_gravity:
		clock_offset_y = pet.PET_RADIUS + 14.0 + float_y
	else:
		clock_offset_y = -pet.PET_RADIUS - 28.0 + float_y
	var center_p = pet.global_position + Vector2(-text_size.x / 2.0, clock_offset_y)
	clock_label.global_position = center_p
	
	# 当气泡出现（全局或本地）时自动避让隐藏时钟，防字体重叠
	var should_hide = (pet.overlay_rect.size != Vector2.ZERO) or _local_bubbles.size() > 0
	if should_hide != _is_clock_hidden:
		_is_clock_hidden = should_hide
		var tw = pet.create_tween()
		if should_hide:
			tw.tween_property(clock_label, "modulate:a", 0.0, 0.2)
		else:
			tw.tween_property(clock_label, "modulate:a", 1.0, 0.3)

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

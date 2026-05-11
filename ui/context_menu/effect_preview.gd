# effect_preview.gd — 菜单预览子系统 (RefCounted)
# 负责: 菜单开关/单选项的 hover 动画预览面板
# 支持任意 L3 面板的预览注册，通过 l3_id 动态定位
# 从 context_menu.gd 拆分，遵循 RefCounted 子系统模式
extends RefCounted

var _menu  # context_menu 引用

# ── 预览条目注册表 ──
# key = 唯一ID, value = { panel, ctrl, btn, l3_id }
var _entries: Dictionary = {}

func _init(menu_ref) -> void:
	_menu = menu_ref

# ═══════════════════════════════════════════
# 公共接口
# ═══════════════════════════════════════════

## 构建全部预览 (在所有 L3 面板创建完毕后调用)
func build() -> void:
	# ── 特效预览 (L3: "effects") ──
	_register_toggle("shockwave", "effects", ShockwavePreview.new(), "高速撞击时爆发冲击波", Vector2(140, 100))
	_register_toggle("trail_fx",  "effects", TrailPreview.new(),     "运动轨迹的发光尾迹", Vector2(160, 80))
	_register_toggle("arc_fx",    "effects", ArcPreview.new(),       "宠物间的能量弧线",   Vector2(160, 80))
	# ── 窗口模式预览 (L3: "window_mode") ──
	_register_radio("window_mode", 0, "wm_free",     WindowFreePreview.new(),     "在窗口间自由行走跳跃", Vector2(180, 100))
	_register_radio("window_mode", 1, "wm_confined",  WindowConfinedPreview.new(), "被困在窗口内部无法离开", Vector2(180, 100))
	_register_radio("window_mode", 2, "wm_repelled",  WindowRepelledPreview.new(), "被窗口推开无法进入", Vector2(180, 100))
	_register_radio("behavior_mode", 0, "bm_free",  BehaviorFreePreview.new(),  "活力满满，随意滚动跳跃", Vector2(180, 100))
	_register_radio("behavior_mode", 1, "bm_quiet", BehaviorQuietPreview.new(), "安安静静，待机休眠不乱跑", Vector2(180, 100))
	# ── 步态模式预览 (L3: "gait") ──
	_register_radio("gait", 0, "g_jump", GaitJumpPreview.new(),  "纯蹦跳抛物移动，绝不贴地", Vector2(180, 100))
	_register_radio("gait", 1, "g_roll", GaitRollPreview.new(),  "纯滚动贴地平移，绝不跳跃", Vector2(180, 100))
	_register_radio("gait", 2, "g_mix",  GaitMixedPreview.new(), "二者结合，动静自如的平衡", Vector2(180, 100))
	# ── 模式预览 (L3: "mode") ──
	_register_toggle("eye_track", "mode", EyeTrackPreview.new(), "随着鼠标移动，宠物始终注视着光标", Vector2(180, 100))
	_register_toggle("anti_gravity", "mode", AntiGravityPreview.new(), "重力场反转，宠物将吸附在屏幕顶部行走", Vector2(180, 100))
	_register_toggle("free_roam", "mode", FreeRoamPreview.new(), "虚空生成能量踏板，宠物可在屏幕内四处落脚攀跃", Vector2(180, 100))
	_register_toggle("screen_wrap", "mode", ScreenWrapPreview.new(), "打破空间约束，当宠物离开屏幕边缘时，将在另一侧无缝继续前行", Vector2(180, 100))
## 每帧定位跟踪 (由 context_menu._process 调用)
func update_positions() -> void:
	for entry in _entries.values():
		var panel = entry.panel as PanelContainer
		if is_instance_valid(panel) and panel.visible:
			_position_panel(entry)

# ═══════════════════════════════════════════
# 内部: 注册
# ═══════════════════════════════════════════

## 注册 toggle 项预览 (通过 l3_items 查找按钮)
func _register_toggle(setting_id: String, l3_id: String, ctrl: Control, desc_text: String, ctrl_size: Vector2) -> void:
	var btn = _menu._submenu.l3_items.get(setting_id) as Button
	if not btn:
		return
	_add_entry(setting_id, btn, l3_id, ctrl, desc_text, ctrl_size)

## 注册 radio 项预览 (通过 _l3_radio_buttons 查找按钮)
func _register_radio(menu_id: String, value: int, entry_id: String, ctrl: Control, desc_text: String, ctrl_size: Vector2) -> void:
	var radio_group = _menu._submenu._l3_radio_buttons.get(menu_id) as Array
	if not radio_group:
		return
	for item in radio_group:
		if item.value == value:
			_add_entry(entry_id, item.btn, menu_id, ctrl, desc_text, ctrl_size)
			return

## 通用: 创建面板 + 绑定 hover + 写入注册表
func _add_entry(entry_id: String, btn: Button, l3_id: String, ctrl: Control, desc_text: String, ctrl_size: Vector2) -> void:
	var panel = _make_panel(ctrl, desc_text, ctrl_size)
	var entry = { "panel": panel, "ctrl": ctrl, "btn": btn, "l3_id": l3_id }
	_entries[entry_id] = entry
	btn.mouse_entered.connect(func(): _show(entry))
	btn.mouse_exited.connect(func(): _hide(entry))

# ═══════════════════════════════════════════
# 面板生命周期
# ═══════════════════════════════════════════

## 创建预览面板容器 (深色圆角卡片 + 动画区域 + 描述文字)
func _make_panel(ctrl: Control, desc_text: String, ctrl_size: Vector2) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.1, 0.95)
	style.border_color = Color.from_hsv(EventBus.ui_hue, 0.7, 1.0, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	ctrl.custom_minimum_size = ctrl_size
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(ctrl)
	var desc = Label.new()
	desc.text = desc_text
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.45, 0.6, 0.8, 0.7))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc)
	_menu.add_child(panel)
	panel.draw.connect(_menu.draw_panel_tail.bind(panel))
	return panel

## 弹簧动画显示
func _show(entry: Dictionary) -> void:
	var panel = entry.panel as PanelContainer
	var ctrl = entry.ctrl as Control
	ctrl.set_process(true)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.7, 0.7)
	panel.show()
	await _menu.get_tree().process_frame
	_position_panel(entry)
	var tween = _menu.create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 缩放淡出隐藏
func _hide(entry: Dictionary) -> void:
	var ctrl = entry.ctrl as Control
	var panel = entry.panel as PanelContainer
	ctrl.set_process(false)
	var tween = _menu.create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.1)
	tween.tween_property(panel, "scale", Vector2(0.7, 0.7), 0.1)
	tween.finished.connect(func(): panel.hide())

## 方向感知定位 (紧随对应 L3 面板外侧)
func _position_panel(entry: Dictionary) -> void:
	var btn = entry.btn as Button
	var panel = entry.panel as PanelContainer
	if not is_instance_valid(btn):
		return
	# 动态查找对应的 L3 面板作为定位参考
	var l3_panel = _menu._submenu.l3_panels.get(entry.l3_id)
	var bounds = _menu.get_panel_bounds_for_button(btn)
	var ref_pos = bounds.pos
	var ref_w = bounds.w
	
	if is_instance_valid(l3_panel) and l3_panel.visible:
		ref_pos = l3_panel.global_position
		ref_w = l3_panel.size.x
	var btn_pos = btn.global_position
	var btn_size = btn.size
	var vp_size = _menu.get_viewport().get_visible_rect().size
	var panel_w = panel.size.x
	var gap := 6.0
	var x: float
	if _menu._menu_side == 1:
		x = ref_pos.x + ref_w + gap
		if x + panel_w > vp_size.x - 10: x = ref_pos.x - panel_w - gap
		panel.pivot_offset = Vector2(0, panel.size.y / 2.0)
	else:
		x = ref_pos.x - panel_w - gap
		if x < 10: x = ref_pos.x + ref_w + gap
		panel.pivot_offset = Vector2(panel_w, panel.size.y / 2.0)
	var y = btn_pos.y + btn_size.y / 2.0 - panel.size.y / 2.0
	y = clampf(y, 8.0, vp_size.y - panel.size.y - 8.0)
	panel.position = Vector2(x, y)
	panel.set_meta("trigger_global_x", btn_pos.x + btn_size.x / 2.0)
	panel.set_meta("trigger_global_y", btn_pos.y + btn_size.y / 2.0)
	panel.queue_redraw()



# ═══════════════════════════════════════════
# 基础预览 Control (共用绘制方法)
# ═══════════════════════════════════════════
class ViewBase extends Control:
	func _init() -> void:
		clip_contents = true

	func _draw_holo_pet(center: Vector2, hue: float, r: float = 6.0, rot: float = 0.0, look_offset: Vector2 = Vector2.ZERO) -> void:
		draw_set_transform(center, rot, Vector2.ONE)
		
		var outline_c = Color.from_hsv(hue, 0.8, 0.2, 1.0)
		var main_c = Color.from_hsv(hue, 0.7, 0.5, 1.0)
		var dark_blue = Color.from_hsv(hue, 0.6, 0.3, 1.0)
		
		draw_circle(Vector2.ZERO, r + 1.2, outline_c, true, -1.0, true)
		draw_circle(Vector2.ZERO, r, main_c, true, -1.0, true)
		var border_radius = r * 0.85
		draw_arc(Vector2.ZERO, border_radius, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.8), 1.2, true)
		
		var base_r = r * 0.68
		var tip_dist = border_radius - 1.0
		draw_circle(Vector2.ZERO, base_r, dark_blue, true, -1.0, true)
		for i in range(4):
			var angle = i * PI / 2.0 + PI / 4.0
			var tip_pos = Vector2(cos(angle), sin(angle)) * tip_dist
			var half_hw = PI / 10.0
			var left_base = Vector2(cos(angle - half_hw), sin(angle - half_hw)) * (base_r * 0.95)
			var right_base = Vector2(cos(angle + half_hw), sin(angle + half_hw)) * (base_r * 0.95)
			draw_polygon(PackedVector2Array([left_base, tip_pos, right_base]), PackedColorArray([dark_blue, dark_blue, dark_blue]))
			
		# 完全张开的大眼睛，移除不稳定的眨眼变形
		var iris_scale = 1.0
		draw_circle(Vector2.ZERO, r * 0.54, Color(0.85, 0.88, 0.92, 1.0), true, -1.0, true)
		var pup_pos = look_offset.rotated(-rot)
		draw_circle(pup_pos, r * 0.42, Color.from_hsv(hue, 0.4, 0.8, 1.0), true, -1.0, true)
		draw_circle(pup_pos, r * 0.28, Color.from_hsv(hue, 0.6, 0.5, 1.0), true, -1.0, true)
		draw_circle(pup_pos, r * 0.16, Color.from_hsv(hue, 0.8, 0.15, 1.0), true, -1.0, true)
		var highlight_offset = pup_pos + Vector2(-r * 0.08, -r * 0.10)
		draw_circle(highlight_offset, r * 0.11, Color(1, 1, 1, 0.85), true, -1.0, true)
		draw_circle(highlight_offset, r * 0.06, Color(1, 1, 1, 1.0), true, -1.0, true)
		
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_dotted_parabola(start: Vector2, end: Vector2, height_offset: float, color: Color) -> void:
		var steps = 12
		for i in range(steps + 1):
			var t = float(i) / steps
			var x = lerpf(start.x, end.x, t)
			var base_y = lerpf(start.y, end.y, t)
			var y = base_y + height_offset * sin(t * PI)
			draw_circle(Vector2(x, y), 1.2, color, true, -1.0, true)

# ═══════════════════════════════════════════
# 动画预览 Control: 撞击冲击波
# ═══════════════════════════════════════════
class ShockwavePreview extends ViewBase:
	var _time: float = 0.0
	var _waves: Array[Dictionary] = []
	var _trigger_timer: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		_trigger_timer -= delta
		if _trigger_timer <= 0:
			_trigger_timer = 1.2
			_waves.append({"radius": 6.0, "alpha": 1.0, "thickness": 6.0})
			_waves.append({"radius": 2.4, "alpha": 0.8, "thickness": 2.5})
		var active: Array[Dictionary] = []
		for w in _waves:
			w["radius"] += 150.0 * delta
			w["alpha"] -= 1.6 * delta
			w["thickness"] = maxf(0.5, w["thickness"] - 5.0 * delta)
			if w["alpha"] > 0:
				active.append(w)
		_waves = active
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var r = 6.0
		var ground_y = size.y * 0.75
		var hue = EventBus.ui_hue

		# 宠物跳跃轨迹 (抛物线)
		var t = 1.0 - maxf(0.0, _trigger_timer / 1.2)
		var jump_y = ground_y - r - abs(sin(t * PI)) * 25.0
		var center = Vector2(cx, jump_y)

		# 科技感发光地面线
		draw_line(Vector2(cx - 50, ground_y), Vector2(cx + 50, ground_y), Color(0.3, 0.5, 0.8, 0.2), 2.0, true)
		draw_line(Vector2(cx - 20, ground_y), Vector2(cx + 20, ground_y), Color(0.4, 0.7, 1.0, 0.5), 1.0, true)

		# 以宠物真实中心为圆心的全方位冲击波 (严格匹配实机游戏中的跟随效果)
		for w in _waves:
			var wave_hue = fmod(_time * 0.2 + hue, 1.0)
			var c = Color.from_hsv(wave_hue, 0.6, 1.0, w["alpha"])
			
			# 核心扩散光晕
			var glow_color = c
			glow_color.a *= 0.15
			draw_circle(center, maxf(0.1, w["radius"] - w["thickness"]), glow_color)
			
			# 致密全圆弧
			draw_arc(center, w["radius"], 0, TAU, 32, c, w["thickness"], true)

		_draw_holo_pet(center, hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 粒子尾流
# ═══════════════════════════════════════════
class TrailPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 6.0
		var trail_len := 15
		var points = PackedVector2Array()
		var colors = PackedColorArray()
		
		# 柔和的无限大(Lissajous)轨迹
		var pet_pos = Vector2(cx + sin(_time * 2.5) * 45.0, cy + sin(_time * 5.0) * 15.0)
		
		# 尾迹追踪
		for i in range(trail_len):
			var t_off = float(i) * 0.035
			var hx = cx + sin((_time - t_off) * 2.5) * 45.0
			var hy = cy + sin((_time - t_off) * 5.0) * 15.0
			points.append(Vector2(hx, hy))
			var ratio = 1.0 - float(i) / trail_len
			# 顺滑的色相渐变
			var c = Color.from_hsv(fmod(hue + ratio * 0.2, 1.0), 0.6, 1.0, ratio * 0.7)
			colors.append(c)
			# 每隔几个点画一个残影虚圈
			if i % 3 == 0 and i > 0:
				draw_circle(Vector2(hx, hy), r * ratio * 0.8, Color(c.r, c.g, c.b, ratio * 0.2))

		# 主发光尾迹线
		if points.size() >= 2:
			draw_polyline_colors(points, colors, r * 1.2, true)
			
		_draw_holo_pet(pet_pos, hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 静电弧
# ═══════════════════════════════════════════
class ArcPreview extends ViewBase:
	var _time: float = 0.0
	var _regen_timer: float = 0.0
	var _path_cache: PackedVector2Array = []
	var _flash: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		_regen_timer -= delta
		if _flash > 0: _flash = maxf(_flash - delta * 5.0, 0.0)
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 6.0
		
		# 宠物轻微悬浮游动
		var left_c = Vector2(cx - 35 + sin(_time * 1.2) * 5.0, cy + cos(_time * 1.5) * 3.0)
		var right_c = Vector2(cx + 35 + sin(_time * 1.4) * 4.0, cy + sin(_time * 1.1) * 4.0)

		# 刷新闪电路径
		if _regen_timer <= 0:
			_regen_timer = randf_range(0.04, 0.08)
			_path_cache = _gen_lightning(left_c + Vector2(r, 0), right_c - Vector2(r, 0))
			if randf() < 0.15:
				_flash = 1.0
				
		# 绘制极光电弧
		if _path_cache.size() >= 2:
			var alpha = 0.6 + _flash * 0.4
			var glow_colors = PackedColorArray()
			for i in range(_path_cache.size()):
				var p_ratio = float(i) / _path_cache.size()
				glow_colors.append(Color.from_hsv(fmod(hue + p_ratio*0.2, 1.0), 0.6, 1.0, alpha * 0.6))
			
			draw_polyline_colors(_path_cache, glow_colors, 8.0, true)  # 外发光宽条
			draw_polyline(_path_cache, Color(1, 1, 1, alpha), 1.5, true) # 核心高亮
			
			# 两端电弧集结点的高光
			draw_circle(_path_cache[0], 3.0, Color(1,1,1, alpha*0.8))
			draw_circle(_path_cache[-1], 3.0, Color(1,1,1, alpha*0.8))

		_draw_holo_pet(left_c, hue, r)
		_draw_holo_pet(right_c, hue, r)

	func _gen_lightning(from: Vector2, to: Vector2) -> PackedVector2Array:
		var seg_count := 8
		var dir = to - from
		var perp = Vector2(-dir.y, dir.x).normalized()
		var points = PackedVector2Array()
		points.append(from)
		for i in range(1, seg_count):
			var t = float(i) / seg_count
			var base = from.lerp(to, t)
			var jitter_amp = 18.0 * sin(t * PI) # 中间抖动幅度大
			var jitter = perp * randf_range(-jitter_amp, jitter_amp)
			points.append(base + jitter)
		points.append(to)
		return points

# ═══════════════════════════════════════════
# 动画预览 Control: 窗口模式 - 自由漫游
# ═══════════════════════════════════════════
class WindowFreePreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 6.0
		var win_c = Color(0.2, 0.35, 0.6, 0.35)
		var win_border = Color(0.3, 0.5, 0.8, 0.5)
		
		var w1 = Rect2(cx - 70, cy - 15, 55, 35)
		var w2 = Rect2(cx + 15, cy - 10, 55, 35)
		draw_rect(w1, win_c, true)
		draw_rect(w1, win_border, false, 1.0)
		draw_rect(w2, win_c, true)
		draw_rect(w2, win_border, false, 1.0)
		
		# 窗口顶边/底边高亮
		draw_line(Vector2(w1.position.x, w1.position.y), Vector2(w1.end.x, w1.position.y), Color(0.4, 0.7, 1.0, 0.5), 2.0)
		draw_line(Vector2(w2.position.x + 2, w2.end.y - 1), Vector2(w2.end.x - 2, w2.end.y - 1), Color(0.3, 0.8, 0.5, 0.4), 1.5)
		
		var phase = fmod(_time * 0.55, 1.0)
		var px: float
		var py: float
		
		if phase < 0.35:
			# 在窗口1顶部行走
			var t = phase / 0.35
			px = w1.position.x + 6 + t * (w1.size.x - 12)
			py = w1.position.y - r
		elif phase < 0.5:
			# 跳入窗口2
			var t = (phase - 0.35) / 0.15
			px = lerpf(w1.end.x, w2.position.x + w2.size.x / 2, t)
			var start_y = w1.position.y - r
			var end_y = w2.end.y - r - 2
			py = lerpf(start_y, end_y, t) - sin(t * PI) * 22.0
		elif phase < 0.85:
			# 在窗口2内部游走
			var t = (phase - 0.5) / 0.35
			var inner_left = w2.position.x + r + 3
			var inner_right = w2.end.x - r - 3
			var inner_mid = w2.position.x + w2.size.x / 2
			if t < 0.5:
				px = lerpf(inner_mid, inner_right, t * 2)
			else:
				px = lerpf(inner_right, inner_left, (t - 0.5) * 2)
			py = w2.end.y - r - 2
		else:
			# 跳出
			var t = (phase - 0.85) / 0.15
			px = lerpf(w2.position.x + r + 3, w1.position.x + 6, t)
			var start_y = w2.end.y - r - 2
			var end_y = w1.position.y - r
			py = lerpf(start_y, end_y, t) - sin(t * PI) * 18.0

		# 自由路径虚线残留
		var path_c = Color(0.4, 0.8, 1.0, 0.15)
		for i in range(5):
			var dist_x = px - cx
			draw_circle(Vector2(px - float(i)*sign(dist_x)*2.0, py + float(i)*0.5), 1.5 - float(i)*0.2, path_c)

		_draw_holo_pet(Vector2(px, py), hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 窗口模式 - 窗口封闭
# ═══════════════════════════════════════════
class WindowConfinedPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 6.0
		
		var win = Rect2(cx - 35, cy - 20, 70, 40)
		draw_rect(win, Color(0.2, 0.4, 0.7, 0.15), true)
		draw_rect(win, Color(0.4, 0.6, 1.0, 0.4), false, 1.5)
		
		# 指示向内的法线箭头
		var arrow_c = Color(0.4, 0.7, 1.0, 0.5)
		_draw_dir_arrow(Vector2(win.position.x - 8, cy), Vector2(1, 0), arrow_c)
		_draw_dir_arrow(Vector2(win.end.x + 8, cy), Vector2(-1, 0), arrow_c)
		_draw_dir_arrow(Vector2(cx, win.position.y - 8), Vector2(0, 1), arrow_c)
		_draw_dir_arrow(Vector2(cx, win.end.y + 8), Vector2(0, -1), arrow_c)

		var phase = fmod(_time * 0.5, 1.0)
		var px = cx
		var py = 0.0
		var show_collision = false
		var collision_pt = Vector2.ZERO
		var entry_anim = 0.0
		
		if phase < 0.25:
			# 从高空无障碍落入
			var t = phase / 0.25
			py = lerpf(win.position.y - 35.0, win.end.y - r, t)
			# 检测穿透瞬间，产生空间门涟漪，消除“生硬穿模”感
			if abs(py - win.position.y) < 14.0:
				entry_anim = 1.0 - abs(py - win.position.y) / 14.0
		elif phase < 0.45:
			# 在底部准备起跳
			py = win.end.y - r
		elif phase < 0.65:
			# 起跳撞击天花板并被阻挡 (留出1.5px余量坚决不穿透边框)
			var t = (phase - 0.45) / 0.2
			py = lerpf(win.end.y - r, win.position.y + r + 1.5, t)
			if t > 0.85:
				show_collision = true
				collision_pt = Vector2(cx, win.position.y)
		elif phase < 0.85:
			# 弹回落地
			var t = (phase - 0.65) / 0.2
			py = lerpf(win.position.y + r + 1.5, win.end.y - r, t)
			if t < 0.15:
				show_collision = true
				collision_pt = Vector2(cx, win.position.y)
		else:
			py = win.end.y - r

		# 进入时的单向通行力场波纹
		if entry_anim > 0:
			var portal_c = Color(0.3, 0.9, 1.0, entry_anim * 0.9)
			var w = 18.0 * entry_anim
			draw_line(Vector2(cx - w, win.position.y), Vector2(cx + w, win.position.y), portal_c, 3.0, true)
			draw_arc(Vector2(cx, win.position.y), 10.0 * entry_anim, 0, PI, 16, portal_c, 1.5, true)

		# 撞击天花板的拒止红焰
		if show_collision:
			draw_line(collision_pt - Vector2(18, 0), collision_pt + Vector2(18, 0), Color(1.0, 0.3, 0.3, 0.8), 2.5, true)
			draw_circle(collision_pt, 4.0, Color(1.0, 0.3, 0.3, 0.5))

		_draw_holo_pet(Vector2(px, py), hue, r)

	func _draw_dir_arrow(pos: Vector2, dir: Vector2, color: Color) -> void:
		var p1 = pos + dir * 4.0
		var perp = Vector2(-dir.y, dir.x)
		var p2 = pos - dir * 2.0 + perp * 4.0
		var p3 = pos - dir * 2.0 - perp * 4.0
		draw_colored_polygon(PackedVector2Array([p1, p2, p3]), color)

# ═══════════════════════════════════════════
# 动画预览 Control: 窗口模式 - 窗口排斥
# ═══════════════════════════════════════════
class WindowRepelledPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var hue = EventBus.ui_hue
		var r = 6.0
		
		var win = Rect2(cx - 35, cy - 20, 70, 40)
		draw_rect(win, Color(0.7, 0.4, 0.2, 0.15), true)
		draw_rect(win, Color(1.0, 0.6, 0.3, 0.5), false, 1.5)
		
		# 指示向外的法线箭头
		var arrow_c = Color(1.0, 0.6, 0.3, 0.6)
		_draw_dir_arrow(Vector2(win.position.x - 8, cy), Vector2(-1, 0), arrow_c)
		_draw_dir_arrow(Vector2(win.end.x + 8, cy), Vector2(1, 0), arrow_c)
		_draw_dir_arrow(Vector2(cx, win.position.y - 8), Vector2(0, -1), arrow_c)
		_draw_dir_arrow(Vector2(cx, win.end.y + 8), Vector2(0, 1), arrow_c)

		var phase = fmod(_time * 0.5, 1.0)
		var px = cx
		var py = 0.0
		var show_collision = false
		var collision_pt = Vector2.ZERO
		
		# 将撞击点改去左侧墙面，物理上绝对不可能与窗口内部路径重合，彻底杜绝穿模感
		var hit_x = win.position.x - r - 1.5 
		
		if phase < 0.25:
			# 从左侧水平冲刺向窗口
			var t = phase / 0.25
			px = lerpf(cx - 80.0, hit_x, t)
			py = cy
			if t > 0.85:
				show_collision = true
				collision_pt = Vector2(win.position.x, cy)
		elif phase < 0.8:
			# 严格在左侧弹开，做抛物线后空翻重重坠入深渊
			var t = (phase - 0.25) / 0.55
			px = lerpf(hit_x, cx - 70.0, t)
			py = lerpf(cy, cy + 60.0, t) - sin(t * PI) * 15.0
			if t < 0.15:
				show_collision = true
				collision_pt = Vector2(win.position.x, cy)
		else:
			px = -100
			py = -100

		if show_collision:
			# 排斥护盾 (朝左展开)
			draw_arc(collision_pt, 12.0, PI/2, 3*PI/2, 16, Color(1.0, 0.6, 0.2, 0.8), 2.5, true)
			draw_line(collision_pt - Vector2(0, 15), collision_pt + Vector2(0, 15), Color(1.0, 0.7, 0.4, 0.8), 2.5, true)
			draw_circle(collision_pt, 3.0, Color(1.0, 0.8, 0.5, 0.6))

		if px > -50.0:
			_draw_holo_pet(Vector2(px, py), hue, r)

	func _draw_dir_arrow(pos: Vector2, dir: Vector2, color: Color) -> void:
		var p1 = pos + dir * 4.0
		var perp = Vector2(-dir.y, dir.x)
		var p2 = pos - dir * 2.0 + perp * 4.0
		var p3 = pos - dir * 2.0 - perp * 4.0
		draw_colored_polygon(PackedVector2Array([p1, p2, p3]), color)

# ═══════════════════════════════════════════
# 动画预览 Control: 指令 - 自由行动
# ═══════════════════════════════════════════
class BehaviorFreePreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var r = 6.0
		var ground_y = size.y * 0.75
		var hue = EventBus.ui_hue
		
		# 极简发光地面线
		draw_line(Vector2(cx - 60, ground_y), Vector2(cx + 60, ground_y), Color(0.3, 0.5, 0.8, 0.2), 2.0, true)
		draw_line(Vector2(cx - 30, ground_y), Vector2(cx + 30, ground_y), Color(0.4, 0.7, 1.0, 0.5), 1.0, true)
		
		# 相位动画：周期跳跃与左右跑动
		var phase = fmod(_time * 0.6, 1.0)
		var px = cx
		var py = ground_y - r
		
		if phase < 0.3:
			# 向右大跳
			var t = phase / 0.3
			px = lerpf(cx - 40, cx + 10, t)
			py = ground_y - r - sin(t * PI) * 35.0
		elif phase < 0.5:
			# 向左小跳
			var t = (phase - 0.3) / 0.2
			px = lerpf(cx + 10, cx - 20, t)
			py = ground_y - r - sin(t * PI) * 15.0
		elif phase < 0.7:
			# 向右小跳
			var t = (phase - 0.5) / 0.2
			px = lerpf(cx - 20, cx, t)
			py = ground_y - r - sin(t * PI) * 10.0
		elif phase < 1.0:
			# 原地蓄力准备下一次大跳
			var t = (phase - 0.7) / 0.3
			px = cx - 40 * t
			py = ground_y - r
		
		# 残影速度线 (充满活力)
		var path_c = Color.from_hsv(hue, 0.5, 1.0, 0.2)
		for i in range(1, 5):
			# 用微小的延迟采样前面的时间点
			var past_phase = fmod((_time - i * 0.04) * 0.6, 1.0)
			var ppx = cx
			var ppy = ground_y - r
			if past_phase < 0.3:
				var t = past_phase / 0.3
				ppx = lerpf(cx - 40, cx + 10, t)
				ppy = ground_y - r - sin(t * PI) * 35.0
			elif past_phase < 0.5:
				var t = (past_phase - 0.3) / 0.2
				ppx = lerpf(cx + 10, cx - 20, t)
				ppy = ground_y - r - sin(t * PI) * 15.0
			elif past_phase < 0.7:
				var t = (past_phase - 0.5) / 0.2
				ppx = lerpf(cx - 20, cx, t)
				ppy = ground_y - r - sin(t * PI) * 10.0
			elif past_phase < 1.0:
				var t = (past_phase - 0.7) / 0.3
				ppx = cx - 40 * t
				ppy = ground_y - r
			
			draw_circle(Vector2(ppx, ppy), r - i * 0.8, Color(path_c.r, path_c.g, path_c.b, 0.4 - i * 0.08))

		_draw_holo_pet(Vector2(px, py), hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 指令 - 安静待命
# ═══════════════════════════════════════════
class BehaviorQuietPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var r = 6.0
		var ground_y = size.y * 0.75
		var hue = EventBus.ui_hue
		
		# 极简发光地面线
		draw_line(Vector2(cx - 60, ground_y), Vector2(cx + 60, ground_y), Color(0.3, 0.5, 0.8, 0.2), 2.0, true)
		draw_line(Vector2(cx - 30, ground_y), Vector2(cx + 30, ground_y), Color(0.4, 0.7, 1.0, 0.5), 1.0, true)
		
		# 屏幕角落指示器 (表示 retreat_target)
		var corner_x = cx + 55.0
		draw_line(Vector2(corner_x, ground_y), Vector2(corner_x, ground_y - 15.0), Color(0.2, 0.7, 0.9, 0.4), 2.0, true)
		draw_line(Vector2(corner_x, ground_y), Vector2(corner_x - 10.0, ground_y), Color(0.2, 0.7, 0.9, 0.4), 2.0, true)
		
		# 动作流程
		# 0.0~0.25: 滚向角落 (retreat)
		# 0.25~0.4: 停泊到位，加上阻尼稳住
		# 0.4~1.0: 休眠阶段 (hibernate)
		var loop_time = 4.0
		var phase = fmod(_time, loop_time) / loop_time
		var px = cx - 20.0
		var py = ground_y - r
		var drowsy_amt = 0.0
		var show_zzz = false
		
		if phase < 0.25:
			# 滚动寻位
			var t = phase / 0.25
			# 用 ease_out 让它减速停靠
			t = 1.0 - (1.0 - t) * (1.0 - t)
			px = lerpf(cx - 40.0, corner_x - r - 3.0, t)
		elif phase < 0.4:
			# 停靠完毕，开始闭眼
			px = corner_x - r - 3.0
			var t = (phase - 0.25) / 0.15
			drowsy_amt = lerpf(0.0, 0.8, t)
		else:
			# 彻底休眠，呼吸闭眼
			px = corner_x - r - 3.0
			drowsy_amt = 0.8 + sin((phase - 0.4) * TAU * 3.0) * 0.1
			show_zzz = true
		
		var pet_center = Vector2(px, py)
		
		# 本体底座光晕
		var glow_c = Color.from_hsv(hue, 0.6, 1.0, 0.15)
		draw_circle(pet_center, r + 2.5, glow_c, true, -1.0, true)
		# 立体核心网络
		var c1 = Color.from_hsv(hue, 0.5, 0.9, 0.5)
		draw_circle(pet_center, r, c1, true, -1.0, true)
		var c2 = Color.from_hsv(hue, 0.3, 1.0, 0.7)
		draw_circle(pet_center, r * 0.7, c2, true, -1.0, true)
		
		# 休眠挡板 (机械眼睑) 覆盖核心网
		if drowsy_amt > 0.05:
			# 画上半闭的深蓝灰色挡板多边形
			var close_px = r * drowsy_amt * 1.5
			var flat_y = clampf(-r + close_px, -r + 0.1, r - 0.1)
			var dx = sqrt(maxf(0.0, r * r - flat_y * flat_y))
			var pts = PackedVector2Array()
			var arc_steps = 16
			var angle_l = atan2(flat_y, -dx)
			var angle_r = atan2(flat_y, dx)
			var span = angle_r - angle_l
			if span < 0: span += TAU
			for i in range(arc_steps + 1):
				var t = float(i) / float(arc_steps)
				var a = angle_l + span * t
				pts.append(Vector2(cos(a), sin(a)) * r)
			if pts.size() >= 3:
				var shutter_offset = PackedVector2Array()
				for pt in pts:
					shutter_offset.append(pet_center + pt)
				var shutter_c = Color.from_hsv(hue, 0.5, 0.25, 1.0) # 暗色遮罩
				draw_colored_polygon(shutter_offset, shutter_c)
				draw_polyline(shutter_offset, shutter_c, 1.0, true)
				
		# 锐利边界收尾
		var rim_c = Color.from_hsv(hue, 0.2, 1.0, 0.8)
		draw_arc(pet_center, r, 0, TAU, 24, rim_c, 1.0, true)
		
		# 漂浮 Zzz 气泡
		if show_zzz:
			var z_phase = fmod(_time * 0.8, 1.0)
			for i in range(3):
				var offset_phase = fmod(z_phase + float(i) * 0.33, 1.0)
				# 抛物线漂浮 (上飘且微微右偏)
				var zx = pet_center.x + offset_phase * 15.0
				var zy = pet_center.y - r - 8.0 - offset_phase * 25.0
				var alpha = sin(offset_phase * PI) * 0.8
				var z_color = Color(0.5, 0.8, 1.0, alpha)
				var s = 0.5 + offset_phase * 0.8
				
				# 画个缩放的Z折线
				var z_pts = PackedVector2Array([
					Vector2(zx - 3*s, zy - 3*s),
					Vector2(zx + 3*s, zy - 3*s),
					Vector2(zx - 3*s, zy + 3*s),
					Vector2(zx + 3*s, zy + 3*s)
				])
				draw_polyline(z_pts, z_color, 1.2 * s, true)

# ═══════════════════════════════════════════
# 动画预览 Control: 步态 - 蹦跳为主
# ═══════════════════════════════════════════
class GaitJumpPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var r = 6.0
		var ground_y = size.y * 0.75
		var hue = EventBus.ui_hue
		
		draw_line(Vector2(cx - 60, ground_y), Vector2(cx + 60, ground_y), Color(0.3, 0.5, 0.8, 0.2), 2.0, true)
		draw_line(Vector2(cx - 30, ground_y), Vector2(cx + 30, ground_y), Color(0.4, 0.7, 1.0, 0.5), 1.0, true)

		var arc_c = Color.from_hsv(hue, 0.6, 1.0, 0.3)
		_draw_dotted_parabola(Vector2(cx - 40, ground_y - r), Vector2(cx + 40, ground_y - r), -35.0, arc_c)

		var loop = 1.0
		var phase = fmod(_time, loop) / loop
		var px = cx
		var py = ground_y - r
		
		if phase < 0.5:
			var t = phase / 0.5
			px = lerpf(cx - 40, cx + 40, t)
			py = ground_y - r - sin(t * PI) * 35.0
		else:
			var t = (phase - 0.5) / 0.5
			px = lerpf(cx + 40, cx - 40, t)
			py = ground_y - r - sin(t * PI) * 35.0
			
		_draw_holo_pet(Vector2(px, py), hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 步态 - 滚动为主
# ═══════════════════════════════════════════
class GaitRollPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var r = 6.0
		var ground_y = size.y * 0.75
		var hue = EventBus.ui_hue
		
		# 极简发光地面线
		draw_line(Vector2(cx - 60, ground_y), Vector2(cx + 60, ground_y), Color(0.3, 0.5, 0.8, 0.2), 2.0, true)
		draw_line(Vector2(cx - 30, ground_y), Vector2(cx + 30, ground_y), Color(0.4, 0.7, 1.0, 0.5), 1.0, true)

		var loop = 1.6
		var phase = fmod(_time, loop) / loop
		var px = cx
		var py = ground_y - r
		var rot = 0.0
		
		if phase < 0.5:
			var t = phase / 0.5
			var eased_t = smoothstep(0.0, 1.0, t)
			px = lerpf(cx - 40, cx + 40, eased_t)
			rot = px * 0.6
		else:
			var t = (phase - 0.5) / 0.5
			var eased_t = smoothstep(0.0, 1.0, t)
			px = lerpf(cx + 40, cx - 40, eased_t)
			rot = px * 0.6
			


		_draw_holo_pet(Vector2(px, py), hue, r, rot)

# ═══════════════════════════════════════════
# 动画预览 Control: 步态 - 混合平衡
# ═══════════════════════════════════════════
class GaitMixedPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var r = 6.0
		var ground_y = size.y * 0.75
		var hue = EventBus.ui_hue
		
		# 极简发光地面线
		draw_line(Vector2(cx - 60, ground_y), Vector2(cx + 60, ground_y), Color(0.3, 0.5, 0.8, 0.2), 2.0, true)
		draw_line(Vector2(cx - 30, ground_y), Vector2(cx + 30, ground_y), Color(0.4, 0.7, 1.0, 0.5), 1.0, true)

		var arc_c = Color.from_hsv(hue, 0.6, 1.0, 0.3)
		var loop = 2.0
		var phase = fmod(_time, loop) / loop
		var px = cx
		var py = ground_y - r
		var rot = 0.0
		
		if phase < 0.25:
			var t = phase / 0.25
			var eased_t = smoothstep(0.0, 1.0, t)
			px = lerpf(cx - 40, cx, eased_t)
			rot = px * 0.6
		elif phase < 0.5:
			_draw_dotted_parabola(Vector2(cx, ground_y - r), Vector2(cx + 40, ground_y - r), -25.0, arc_c)
			var t = (phase - 0.25) / 0.25
			px = lerpf(cx, cx + 40, t)
			py = ground_y - r - sin(t * PI) * 25.0
			rot = 0
		elif phase < 0.75:
			var t = (phase - 0.5) / 0.25
			var eased_t = smoothstep(0.0, 1.0, t)
			px = lerpf(cx + 40, cx, eased_t)
			rot = px * 0.6
		else:
			_draw_dotted_parabola(Vector2(cx, ground_y - r), Vector2(cx - 40, ground_y - r), -25.0, arc_c)
			var t = (phase - 0.75) / 0.25
			px = lerpf(cx, cx - 40, t)
			py = ground_y - r - sin(t * PI) * 25.0
			rot = 0

		_draw_holo_pet(Vector2(px, py), hue, r, rot)

# ═══════════════════════════════════════════
# 动画预览 Control: 模式 - 指针跟踪
# ═══════════════════════════════════════════
class EyeTrackPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var center = Vector2(cx, cy)
		var r = 14.0 # 稍微放大以展示完美复刻的眼部细节！
		var hue = EventBus.ui_hue
		
		# 模拟光标靶点 (红色激光笔)
		var target_pos = center + Vector2(sin(_time * 1.8) * 55.0, cos(_time * 2.5) * 25.0)
		var dot_c = Color(1.0, 0.2, 0.3, 0.9)
		draw_circle(target_pos, 2.0, dot_c)
		draw_arc(target_pos, 5.0 + sin(_time * 12.0) * 1.5, 0, TAU, 16, Color(1.0, 0.2, 0.3, 0.4), 1.0, true)
		
		# 相对靶点的注视偏置计算
		var diff = target_pos - center
		var dist = diff.length()
		var look_dir = diff.normalized()
		var max_offset = r * 0.18 # 原版瞳孔活动范围大约是这个比例
		var look_offset = look_dir * (max_offset * minf(dist / 60.0, 1.0))
		
		# 采用纯净无眨眼动画的本体渲染
		_draw_holo_pet(center, hue, r, 0.0, look_offset)
		
		# 追踪扫描虚线
		var scan_c = Color.from_hsv(hue, 0.7, 1.0, 0.2)
		var dash_len = 3.0
		var dash_gap = 4.0
		var curr = r * 1.5
		while curr < dist - 8.0:
			var p1 = center + look_dir * curr
			curr += dash_len
			var p2 = center + look_dir * minf(curr, dist - 8.0)
			draw_line(p1, p2, scan_c, 1.0, true)
			curr += dash_gap

# ═══════════════════════════════════════════
# 动画预览 Control: 模式 - 反重力
# ═══════════════════════════════════════════
class AntiGravityPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var cx = size.x / 2.0
		var r = 14.0
		var hue = EventBus.ui_hue
		
		# 极简科技感天花板与地板
		var ceil_y = r + 15.0
		var ground_y = size.y - 15.0
		
		draw_line(Vector2(cx - 50, ceil_y), Vector2(cx + 50, ceil_y), Color(0.4, 0.6, 1.0, 0.5), 2.0, true)
		draw_line(Vector2(cx - 50, ground_y), Vector2(cx + 50, ground_y), Color(0.4, 0.6, 1.0, 0.2), 1.0, true)
		
		var loop_time = 4.0
		var phase = fmod(_time, loop_time)
		
		var pet_y = ground_y - r
		
		if phase < 1.0:
			# 在地板
			pet_y = ground_y - r
		elif phase < 1.4:
			# 腾空，冲向天花板
			var t = (phase - 1.0) / 0.4
			var eased = ease(t, 2.0)
			pet_y = lerpf(ground_y - r, ceil_y + r, eased)
		elif phase < 3.0:
			# 吸附于天花板
			pet_y = ceil_y + r
		else:
			# 掉落回地板
			var t = (phase - 3.0) / 0.4
			var eased = ease(t, 2.0)
			pet_y = lerpf(ceil_y + r, ground_y - r, eased)
			
		# 重力流向指示箭头
		var arrow_c = Color.from_hsv(hue, 0.6, 1.0, 0.6)
		if phase > 1.0 and phase < 1.6:
			# 向上流 (箭头形状为 ^，Y值应当减小，表现出向上的流动)
			var ay = ceil_y + 25.0 - fmod(_time * 60.0, 15.0)
			draw_line(Vector2(cx - 24, ay), Vector2(cx, ay - 12), arrow_c, 2.0, true)
			draw_line(Vector2(cx + 24, ay), Vector2(cx, ay - 12), arrow_c, 2.0, true)
		elif phase > 3.0 or phase < 0.2:
			# 向下流 (箭头形状为 v，Y值应当增大，表现出向下的流动)
			var anim_t = phase if phase < 0.2 else phase - 3.0
			if anim_t < 0.6:
				var ay = ground_y - 25.0 + fmod(_time * 60.0, 15.0)
				draw_line(Vector2(cx - 24, ay), Vector2(cx, ay + 12), arrow_c, 2.0, true)
				draw_line(Vector2(cx + 24, ay), Vector2(cx, ay + 12), arrow_c, 2.0, true)
			
		# 纯净展示，无面部动画
		_draw_holo_pet(Vector2(cx, pet_y), hue, r)

# ═══════════════════════════════════════════
# 动画预览 Control: 模式 - 空间跳跃
# ═══════════════════════════════════════════
class FreeRoamPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw_plat(plat_pos: Vector2, hw: float, alpha: float, hue: float) -> void:
		if alpha <= 0.01: return
		var c = Color.from_hsv(hue, 0.6, 1.0, alpha)
		# 极简能量束风格踏板
		draw_line(plat_pos + Vector2(-hw, 0), plat_pos + Vector2(hw, 0), Color(c.r, c.g, c.b, alpha * 0.15), 8.0, true)
		draw_line(plat_pos + Vector2(-hw, 0), plat_pos + Vector2(hw, 0), Color(c.r, c.g, c.b, alpha * 0.4), 3.0, true)
		draw_line(plat_pos + Vector2(-hw, 0), plat_pos + Vector2(hw, 0), Color(c.r, c.g, c.b, alpha * 0.9), 1.5, true)
		var dot_c = Color(c.r, c.g, c.b, alpha * 0.95)
		draw_circle(plat_pos + Vector2(-hw, 0), 2.5, dot_c, true, -1.0, true)
		draw_circle(plat_pos + Vector2(hw, 0), 2.5, dot_c, true, -1.0, true)

	func _draw() -> void:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var r = 14.0
		var hue = EventBus.ui_hue
		
		var loop = 3.5
		var phase = fmod(_time, loop)
		var t = 0.0
		
		# 定义两个悬空踏板的核心落点
		var p1 = Vector2(cx - 30.0, cy + 20.0)
		var p2 = Vector2(cx + 30.0, cy - 10.0)
		
		var pet_pos = Vector2.ZERO
		var p1_alpha = 0.0
		var p2_alpha = 0.0
		var rot = 0.0
		
		if phase < 1.0:
			pet_pos = p1
			p1_alpha = 1.0
			p2_alpha = 0.0
		elif phase < 1.5:
			# 从左下跳往右上
			t = (phase - 1.0) / 0.5
			var x = lerpf(p1.x, p2.x, t)
			var base_y = lerpf(p1.y, p2.y, t)
			pet_pos = Vector2(x, base_y - sin(t * PI) * 50.0)
			
			p1_alpha = 1.0 - t
			p2_alpha = t
			rot = sin(t * PI) * 0.4
			
			_draw_dotted_parabola(p1, p2, -50.0, Color.from_hsv(hue, 0.4, 1.0, 0.4))
		elif phase < 2.5:
			pet_pos = p2
			p1_alpha = 0.0
			p2_alpha = 1.0
		elif phase < 3.0:
			# 这边跳得较慢较低，平铺直叙地落回去
			t = (phase - 2.5) / 0.5
			var x = lerpf(p2.x, p1.x, t)
			var base_y = lerpf(p2.y, p1.y, t)
			pet_pos = Vector2(x, base_y - sin(t * PI) * 20.0)
			
			p1_alpha = t
			p2_alpha = 1.0 - t
			rot = -sin(t * PI) * 0.3
			
			_draw_dotted_parabola(p2, p1, -20.0, Color.from_hsv(hue, 0.4, 1.0, 0.4))
		else:
			# 落地带有微小缓冲
			pet_pos = p1
			p1_alpha = 1.0
			p2_alpha = 0.0
			var bump = sin((phase - 3.0)/0.5 * PI)
			pet_pos.y += bump * 3.0 
			
		var plat_w = 20.0
		_draw_plat(p1 + Vector2(0, r), plat_w, p1_alpha, hue)
		_draw_plat(p2 + Vector2(0, r), plat_w, p2_alpha, hue)
		
		# 极简虚空漂浮粒子，营造高空自由悬浮感
		for i in range(5):
			var hash_x = wrapf(i * 137.5, 0.0, size.x)
			var raw_y = i * 93.1 - _time * (10.0 + i * 5.0)
			var hash_y = wrapf(raw_y, -20.0, size.y + 20.0)
			var p_alpha = sin(_time * 2.0 + i) * 0.3 + 0.3
			draw_circle(Vector2(hash_x, hash_y), 1.0 + fmod(i*0.3, 1.5), Color(1, 1, 1, p_alpha * 0.5))
		
		# 我们不需要 look_offset 因为这个只是动作演示，睁着大眼睛即可
		_draw_holo_pet(pet_pos, hue, r, rot)

# ═══════════════════════════════════════════
# 动画预览 Control: 模式 - 屏幕穿越
# ═══════════════════════════════════════════
class ScreenWrapPreview extends ViewBase:
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var r = 14.0
		var hue = EventBus.ui_hue
		
		# 使用真实的控件边界，依靠 clip_contents = true 产生完美的硬切割视觉错觉
		var bound_l = 0.0
		var bound_r = size.x
		var span = size.x
		var ground_y = size.y - 20.0
		
		# 极简虚线贯穿整个控件作为基底
		draw_line(Vector2(0, ground_y), Vector2(size.x, ground_y), Color(0.4, 0.6, 1.0, 0.5), 2.0, true)
		
		# 匀速向右运动
		var speed = 75.0
		var total_dist = _time * speed
		# 无缝循环 x 控制在 0 到 size.x 之间
		var x = fmod(total_dist, span)
		var rot = total_dist * 0.18
		var pet_y = ground_y - r
		
		# 幽灵边界探测
		var ghost_offset = Vector2.ZERO
		var margin = r * 1.5
		
		if x > bound_r - margin:
			ghost_offset = Vector2(-span, 0)
		elif x < bound_l + margin:
			ghost_offset = Vector2(span, 0)
			
		var pet_center = Vector2(x, pet_y)
		
		# 借助 clip_contents，超出边界的部分会自动被裁掉
		# 左半边出去多少，右半边就会严格进来多少，形成真正物理上的无缝连接！
		_draw_holo_pet(pet_center, hue, r, rot)
		if ghost_offset != Vector2.ZERO:
			_draw_holo_pet(pet_center + ghost_offset, hue, r, rot)

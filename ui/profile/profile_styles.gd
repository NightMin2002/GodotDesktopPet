# profile_styles.gd — 装置档案共享样式工厂
# 提供统一的色值、科技感 StyleBox 与多层级文本/布局
class_name ProfileStyles

# ── 色值 ──

static func accent() -> Color:
	return Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.9)

static func dim() -> Color:
	return Color(0.45, 0.55, 0.65, 0.55)

static func bright() -> Color:
	return Color(0.75, 0.85, 0.95, 0.9)

static func val_color() -> Color:
	return Color(0.65, 0.78, 0.92, 0.85)

# ── 通用 StyleBox ──

## 科技感信息卡片
static func card_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.06, 0.10, 0.6)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.2)
	s.set_corner_radius_all(0) # 直角机能风
	s.content_margin_left = 16; s.content_margin_right = 16
	s.content_margin_top = 16; s.content_margin_bottom = 16
	return s

## 小按钮 (等级控制)
static func small_btn_normal() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.18, 0.7)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.5, 0.3)
	s.set_corner_radius_all(0) # 直角机能风
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 3; s.content_margin_bottom = 3
	return s

static func small_btn_hover() -> StyleBoxFlat:
	var s = small_btn_normal()
	s.bg_color = Color(0.18, 0.22, 0.35, 0.8)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.6)
	return s

## 分隔线
static func separator_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.border_width_top = 1
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.15)
	s.set_content_margin_all(0)
	return s

# ── 层级文本组件 (提升 UI 层级感) ──

static func title_label(text: String, font_size: int = 16) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.9, 0.9))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

static func value_label(text: String, font_size: int = 15) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", bright())
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

static func label_dim(text: String, font_size: int = 12) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", dim())
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

## 完全自定义颜色的普通 Label
static func make_label(text: String, font_size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

# ── 布局工厂 ──

static func make_tab_scroll() -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	return scroll

static func make_tab_vbox(separation: int = 10) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", separation)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	return vbox

static func setup_custom_scrollbar(scroll: ScrollContainer) -> void:
	var v_scroll = scroll.get_v_scroll_bar()
	var s_bg = StyleBoxFlat.new()
	s_bg.bg_color = Color(0.04, 0.05, 0.08, 0.6)
	s_bg.border_width_left = 1
	s_bg.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.4, 0.2)
	v_scroll.add_theme_stylebox_override("scroll", s_bg)
	v_scroll.add_theme_stylebox_override("scroll_focus", s_bg)
	
	var s_grabber = StyleBoxFlat.new()
	s_grabber.bg_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.6, 0.6)
	s_grabber.set_corner_radius_all(2)
	v_scroll.add_theme_stylebox_override("grabber", s_grabber)
	
	var s_grabber_hl = s_grabber.duplicate()
	s_grabber_hl.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.8)
	v_scroll.add_theme_stylebox_override("grabber_highlight", s_grabber_hl)
	v_scroll.add_theme_stylebox_override("grabber_pressed", s_grabber_hl)
	
	v_scroll.custom_minimum_size.x = 8

# ── 特效绘制: 科技感角落包边 (L型保护托座) ──

static func add_tech_brackets(control: Control, bracket_len: float = 8.0, inset: float = 0.0) -> void:
	control.draw.connect(func():
		var hue = EventBus.ui_hue
		var c = Color.from_hsv(hue, 0.5, 0.9, 0.8)
		var w = control.size.x
		var h = control.size.y
		var lw = 1.5 # 适中厚度
		
		var r = Rect2(inset, inset, w - inset*2, h - inset*2)
		
		# 左上
		control.draw_polyline(PackedVector2Array([
			r.position + Vector2(0, bracket_len), r.position, r.position + Vector2(bracket_len, 0)
		]), c, lw)
		
		# 右上
		control.draw_polyline(PackedVector2Array([
			Vector2(r.end.x - bracket_len, r.position.y), 
			Vector2(r.end.x, r.position.y), 
			Vector2(r.end.x, r.position.y + bracket_len)
		]), c, lw)
		
		# 左下
		control.draw_polyline(PackedVector2Array([
			Vector2(r.position.x + bracket_len, r.end.y), 
			Vector2(r.position.x, r.end.y), 
			Vector2(r.position.x, r.end.y - bracket_len)
		]), c, lw)
		
		# 右下
		control.draw_polyline(PackedVector2Array([
			Vector2(r.end.x, r.end.y - bracket_len), 
			r.end, 
			Vector2(r.end.x - bracket_len, r.end.y)
		]), c, lw)
	)
	EventBus.ui_theme_changed.connect(func(_h): if is_instance_valid(control): control.queue_redraw())

# ── 头像专用动态机甲雷达系统 ──

static func add_avatar_frame(control: Control) -> void:
	control.draw.connect(func():
		var hue = EventBus.ui_hue
		var w = control.size.x
		var h = control.size.y
		var c = Vector2(w*0.5, h*0.5)
		var t = Time.get_ticks_msec() * 0.001
		
		var cl = 28.0 # 八边形切角深度
		var pts = PackedVector2Array([
			Vector2(cl, 0), Vector2(w - cl, 0),
			Vector2(w, cl), Vector2(w, h - cl),
			Vector2(w - cl, h), Vector2(cl, h),
			Vector2(0, h - cl), Vector2(0, cl), Vector2(cl, 0)
		])
		
		# 1. 磨砂底层背景
		var bg_c = Color.from_hsv(hue, 0.4, 0.15, 0.6)
		control.draw_polygon(pts, PackedColorArray([bg_c]))
		
		# 2. 脉冲声纳波 (逐渐变淡，向外扩散)
		var pulse_r = fmod(t * 30.0, w * 0.6)
		if pulse_r > 0:
			var pulse_c = Color.from_hsv(hue, 0.6, 0.8, 0.15 * (1.0 - pulse_r / (w * 0.6)))
			control.draw_arc(c, pulse_r, 0, TAU, 32, pulse_c, 2.0, true)
		
		# 3. 基础边缘框
		var border_c = Color.from_hsv(hue, 0.4, 0.5, 0.3)
		control.draw_polyline(pts, border_c, 1.0, true)
		
		# 4. 高亮装甲护板 (添加呼吸泛光特效)
		var breathe = sin(t * 2.5) * 0.5 + 0.5
		var hl_c = Color.from_hsv(hue, 0.5, 0.95, 0.6 + 0.4 * breathe)
		var glow_c = Color.from_hsv(hue, 0.5, 0.95, 0.15 + 0.2 * breathe)
		var lw = 3.0
		
		var lt_pts = PackedVector2Array([Vector2(cl + 16, 0), Vector2(cl, 0), Vector2(0, cl), Vector2(0, cl + 16)])
		var rb_pts = PackedVector2Array([Vector2(w - cl - 16, h), Vector2(w - cl, h), Vector2(w, h - cl), Vector2(w, h - cl - 16)])
		
		# 光效渲染 (先画粗的泛光，再画细的核心)
		control.draw_polyline(lt_pts, glow_c, 8.0, true)
		control.draw_polyline(lt_pts, hl_c, lw, true)
		control.draw_polyline(rb_pts, glow_c, 8.0, true)
		control.draw_polyline(rb_pts, hl_c, lw, true)
		
		# 5. 旋转瞄准星环 (内外双层齿轮)
		var ring_r = minf(w, h) * 0.42
		var dash_c = Color.from_hsv(hue, 0.4, 0.8, 0.4)
		
		# 内层正转
		var rot1 = t * 0.6
		for i in range(3):
			control.draw_arc(c, ring_r, rot1 + i * TAU/3.0, rot1 + i * TAU/3.0 + 0.6, 16, dash_c, 2.0, true)
			
		# 外层反转
		var rot2 = -t * 0.4
		for i in range(4):
			control.draw_arc(c, ring_r + 8.0, rot2 + i * TAU/4.0, rot2 + i * TAU/4.0 + 0.3, 8, dash_c, 1.0, true)
		
		# 6. 四面准星十字线 (随呼吸变色)
		var m = 4.0
		control.draw_line(Vector2(w*0.5, m), Vector2(w*0.5, m + 8), hl_c, 1.5)
		control.draw_line(Vector2(w*0.5, h - m), Vector2(w*0.5, h - m - 8), hl_c, 1.5)
		control.draw_line(Vector2(m, h*0.5), Vector2(m + 8, h*0.5), hl_c, 1.5)
		control.draw_line(Vector2(w - m, h*0.5), Vector2(w - m - 8, h*0.5), hl_c, 1.5)
	)
	EventBus.ui_theme_changed.connect(func(_h): if is_instance_valid(control): control.queue_redraw())

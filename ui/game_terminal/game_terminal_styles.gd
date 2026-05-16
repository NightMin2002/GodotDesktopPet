# game_terminal_styles.gd — 游戏终端共享样式工厂
# 提供统一的色值、科技感 StyleBox 与布局工具
# 视觉定位: "战术终端" — 相比装置终端的 "维护诊断" 风格更锐利、更集中
class_name GameTerminalStyles

# ══════════════════════════════════════════════
#  色值
# ══════════════════════════════════════════════

static func accent() -> Color:
	return Color.from_hsv(EventBus.ui_hue, 0.6, 0.9)

static func dim() -> Color:
	return Color(0.40, 0.50, 0.60, 0.55)

static func bright() -> Color:
	return Color(0.85, 0.92, 1.0, 0.95)

static func bg_deep() -> Color:
	return Color(0.02, 0.03, 0.06, 0.96)

static func border_base() -> Color:
	return Color.from_hsv(EventBus.ui_hue, 0.45, 0.65, 0.4)

static func status_active() -> Color:
	return Color.from_hsv(0.35, 0.5, 0.8, 0.9)  # 绿色系 — 就绪

static func status_warning() -> Color:
	return Color.from_hsv(0.12, 0.6, 0.9, 0.9)  # 琥珀色 — 进行中

# ══════════════════════════════════════════════
#  StyleBox 工厂
# ══════════════════════════════════════════════

## 分隔线
static func separator_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.2)
	s.set_content_margin_all(0)
	return s

## 内容区域背景
static func content_area_bg() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.03, 0.06, 0.5)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(12)
	return s

## 状态条背景
static func status_bar_bg() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.05, 0.10, 0.4)
	s.set_corner_radius_all(0)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

## 小按钮 (普通态)
static func small_btn_normal() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.18, 0.6)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.5, 0.3)
	s.set_corner_radius_all(0)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 3; s.content_margin_bottom = 3
	return s

## 小按钮 (悬停态)
static func small_btn_hover() -> StyleBoxFlat:
	var s = small_btn_normal()
	s.bg_color = Color(0.14, 0.18, 0.30, 0.7)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.5)
	return s

# ══════════════════════════════════════════════
#  Label 工厂
# ══════════════════════════════════════════════

## 暗淡文本
static func dim_label(text: String, font_size: int = 14) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", dim())
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

## 自定义颜色 Label
static func make_label(text: String, font_size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

# ══════════════════════════════════════════════
#  绘制工具
# ══════════════════════════════════════════════

## 科技感角落包边 (L型靶向托座)
static func add_tech_brackets(control: Control, bracket_len: float = 8.0, inset: float = 0.0) -> void:
	control.draw.connect(func():
		var hue = EventBus.ui_hue
		var c = Color.from_hsv(hue, 0.5, 0.9, 0.8)
		var w = control.size.x
		var h = control.size.y
		var lw = 1.5
		var r = Rect2(Vector2(inset, inset), Vector2(w - inset * 2, h - inset * 2))
		# 四角 L 型
		control.draw_polyline(PackedVector2Array([
			r.position + Vector2(bracket_len, 0),
			r.position,
			r.position + Vector2(0, bracket_len)
		]), c, lw)
		control.draw_polyline(PackedVector2Array([
			Vector2(r.end.x - bracket_len, r.position.y),
			Vector2(r.end.x, r.position.y),
			Vector2(r.end.x, r.position.y + bracket_len)
		]), c, lw)
		control.draw_polyline(PackedVector2Array([
			Vector2(r.position.x, r.end.y - bracket_len),
			Vector2(r.position.x, r.end.y),
			Vector2(r.position.x + bracket_len, r.end.y)
		]), c, lw)
		control.draw_polyline(PackedVector2Array([
			Vector2(r.end.x, r.end.y - bracket_len),
			r.end,
			Vector2(r.end.x - bracket_len, r.end.y)
		]), c, lw)
	)
	EventBus.ui_theme_changed.connect(func(_h): if is_instance_valid(control): control.queue_redraw())

# terminal_theme_base.gd — 游戏终端主题基类
class_name TerminalThemeBase
extends RefCounted

# 必须返回对应外框的脚本
func get_frame_script() -> Script:
	return load("res://ui/game_terminal/theme/frame_minimal.gd")

func accent() -> Color:
	return Color.from_hsv(EventBus.ui_hue, 0.6, 0.9)

func dim() -> Color:
	return Color(0.40, 0.50, 0.60, 0.55)

func bright() -> Color:
	return Color(0.85, 0.92, 1.0, 0.95)

func bg_deep() -> Color:
	return Color(0.02, 0.03, 0.06, 0.96)

func border_base() -> Color:
	return Color.from_hsv(EventBus.ui_hue, 0.45, 0.65, 0.4)

func status_active() -> Color:
	return Color.from_hsv(0.35, 0.5, 0.8, 0.9)

func status_warning() -> Color:
	return Color.from_hsv(0.12, 0.6, 0.9, 0.9)

func separator_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = border_base()
	s.set_content_margin_all(0)
	return s

func content_area_bg() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.03, 0.06, 0.5)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(12)
	return s

func status_bar_bg() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.05, 0.10, 0.4)
	s.set_corner_radius_all(0)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

func small_btn_normal() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.18, 0.6)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.5, 0.3)
	s.set_corner_radius_all(0)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 3; s.content_margin_bottom = 3
	return s

func small_btn_hover() -> StyleBoxFlat:
	var s = small_btn_normal()
	s.bg_color = Color(0.14, 0.18, 0.30, 0.7)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.5)
	return s

func draw_tech_brackets(control: Control, bracket_len: float = 8.0, inset: float = 0.0) -> void:
	var hue = EventBus.ui_hue
	var c = Color.from_hsv(hue, 0.5, 0.9, 0.8)
	var w = control.size.x
	var h = control.size.y
	var lw = 1.5
	var r = Rect2(Vector2(inset, inset), Vector2(w - inset * 2, h - inset * 2))
	control.draw_polyline(PackedVector2Array([
		r.position + Vector2(bracket_len, 0), r.position, r.position + Vector2(0, bracket_len)
	]), c, lw)
	control.draw_polyline(PackedVector2Array([
		Vector2(r.end.x - bracket_len, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + bracket_len)
	]), c, lw)
	control.draw_polyline(PackedVector2Array([
		Vector2(r.position.x, r.end.y - bracket_len), Vector2(r.position.x, r.end.y), Vector2(r.position.x + bracket_len, r.end.y)
	]), c, lw)
	control.draw_polyline(PackedVector2Array([
		Vector2(r.end.x, r.end.y - bracket_len), r.end, Vector2(r.end.x - bracket_len, r.end.y)
	]), c, lw)

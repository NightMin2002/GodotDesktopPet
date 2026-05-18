# theme_retro.gd — 复古街机风格主题
extends TerminalThemeBase

func get_frame_script() -> Script:
	return load("res://ui/game_terminal/theme/frame_retro.gd")

func accent() -> Color: return Color.from_hsv(EventBus.ui_hue, 0.8, 1.0)
func dim() -> Color: return Color(0.50, 0.60, 0.70, 0.8)
func bright() -> Color: return Color(0.95, 0.95, 1.0, 1.0)
func bg_deep() -> Color: return Color(0.05, 0.05, 0.05, 1.0) 
func border_base() -> Color: return Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 1.0)
func status_active() -> Color: return Color(0.2, 0.9, 0.2, 1.0)
func status_warning() -> Color: return Color(0.9, 0.6, 0.1, 1.0)

func content_area_bg() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.08, 0.9)
	s.set_border_width_all(3)
	s.border_color = border_base()
	s.set_corner_radius_all(0)
	s.set_content_margin_all(12)
	s.shadow_color = Color(0.0, 0.0, 0.0, 1.0)
	s.shadow_size = 4
	return s

func status_bar_bg() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	s.set_border_width_all(2)
	s.border_color = border_base()
	s.border_width_top = 0
	s.set_corner_radius_all(0)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

func small_btn_normal() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	var hue = EventBus.ui_hue
	s.bg_color = Color.from_hsv(hue, 0.4, 0.3, 1.0)
	s.border_width_left = 2; s.border_width_top = 2
	s.border_width_right = 4; s.border_width_bottom = 4
	s.border_color = Color.from_hsv(hue, 0.8, 0.8, 1.0)
	s.set_corner_radius_all(0)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 4; s.content_margin_bottom = 4
	return s

func small_btn_hover() -> StyleBoxFlat:
	var s = small_btn_normal()
	var hue = EventBus.ui_hue
	s.bg_color = Color.from_hsv(hue, 0.6, 0.5, 1.0)
	s.border_color = bright()
	return s

func draw_tech_brackets(control: Control, bracket_len: float = 8.0, inset: float = 0.0) -> void:
	var c = accent()
	var w = control.size.x
	var h = control.size.y
	var block = 6.0 
	var r = Rect2(Vector2(inset, inset), Vector2(w - inset * 2, h - inset * 2))
	control.draw_rect(Rect2(r.position.x - block/2, r.position.y - block/2, block, block), c)
	control.draw_rect(Rect2(r.end.x - block/2, r.position.y - block/2, block, block), c)
	control.draw_rect(Rect2(r.position.x - block/2, r.end.y - block/2, block, block), c)
	control.draw_rect(Rect2(r.end.x - block/2, r.end.y - block/2, block, block), c)

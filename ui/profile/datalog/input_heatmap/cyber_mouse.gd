class_name CyberMouse extends Control

var left_clicks: int = 0
var mid_clicks: int = 0
var right_clicks: int = 0
var dist_px: int = 0
var max_count: int = 1
var key_hue: float = 0.0

var hl := 0.0
var hm := 0.0
var hr := 0.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_PASS

func _process(delta: float) -> void:
	var act_l := false
	var act_m := false
	var act_r := false
	
	if get_global_rect().has_point(get_global_mouse_position()):
		var local := get_local_mouse_position()
		if local.y < 85:
			if local.x < size.x * 0.4: act_l = true
			elif local.x > size.x * 0.6: act_r = true
			else: act_m = true
		else:
			act_l = true; act_m = true; act_r = true
			
	var spd := 8.0 * delta
	var o_hl = hl; hl = move_toward(hl, 1.0 if act_l else 0.0, spd)
	var o_hm = hm; hm = move_toward(hm, 1.0 if act_m else 0.0, spd)
	var o_hr = hr; hr = move_toward(hr, 1.0 if act_r else 0.0, spd)
	if abs(hl-o_hl)>0.01 or abs(hm-o_hm)>0.01 or abs(hr-o_hr)>0.01:
		queue_redraw()
		
func set_stats(m_data: Dictionary, mc: int, hue: float) -> void:
	left_clicks = int(m_data.get("left_clicks", 0))
	right_clicks = int(m_data.get("right_clicks", 0))
	mid_clicks = int(m_data.get("middle_clicks", 0))
	dist_px = int(m_data.get("distance_px", 0))
	max_count = maxi(mc, 1)
	key_hue = hue
	queue_redraw()
	
func _draw() -> void:
	var font := ThemeDB.fallback_font
	var mw := size.x
	var mh := size.y
	var btn_h := 85.0
	var mid_w := 24.0
	var side_w := (mw - mid_w) / 2.0
	var r := 22.0
	var press_l: float = floor(3.0 * hl)
	var press_m: float = floor(3.0 * hm)
	var press_r: float = floor(3.0 * hr)
	
	# 基础机体
	var body_c := Color(0.06, 0.07, 0.10, 0.85)
	draw_rect(Rect2(0, r, mw, mh - r * 2), body_c)
	draw_rect(Rect2(r, 0, mw - r * 2, mh), body_c)
	draw_circle(Vector2(r, r), r, body_c)
	draw_circle(Vector2(mw - r, r), r, body_c)
	draw_circle(Vector2(r, mh - r), r, body_c)
	draw_circle(Vector2(mw - r, mh - r), r, body_c)
	
	var outline := Color.from_hsv(key_hue, 0.2, 0.40, 0.35)
	draw_arc(Vector2(r, r), r, PI * 0.5, PI, 16, outline, 1.5)
	draw_arc(Vector2(mw - r, r), r, 0, PI * 0.5, 16, outline, 1.5)
	draw_arc(Vector2(r, mh - r), r, PI, PI * 1.5, 16, outline, 1.5)
	draw_arc(Vector2(mw - r, mh - r), r, PI * 1.5, PI * 2.0, 16, outline, 1.5)
	draw_line(Vector2(r, 0), Vector2(mw - r, 0), outline, 1.5)
	draw_line(Vector2(r, mh), Vector2(mw - r, mh), outline, 1.5)
	draw_line(Vector2(0, r), Vector2(0, mh - r), outline, 1.5)
	draw_line(Vector2(mw, r), Vector2(mw, mh - r), outline, 1.5)
	
	draw_line(Vector2(side_w, 4), Vector2(side_w, btn_h), outline, 1.0)
	draw_line(Vector2(side_w + mid_w, 4), Vector2(side_w + mid_w, btn_h), outline, 1.0)
	draw_line(Vector2(4, btn_h), Vector2(mw - 4, btn_h), outline, 1.0)
	
	# Left
	var l_heat = HeatUtil.heat_color(left_clicks, max_count, key_hue)
	var hl_c = l_heat.lightened(0.4)
	hl_c.a = 0.4 * hl
	var r_L = Rect2(3, 3 + press_l, side_w - 3, btn_h - 4)
	draw_rect(r_L, l_heat)
	if hl > 0: draw_rect(r_L, hl_c)
	draw_string(font, Vector2(16, 35 + press_l), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.75, 0.80, 0.88, 0.75) if left_clicks==0 else Color(1.0, 1.0, 1.0, 0.95))
	if left_clicks > 0:
		draw_string(font, Vector2(8, btn_h - 10 + press_l), HeatUtil.format_count(left_clicks), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.from_hsv(0.35, 0.55, 0.90, 0.90))
		
	# Middle
	var mid_x := side_w
	var m_heat = HeatUtil.heat_color(mid_clicks, max_count, key_hue)
	var hm_c = m_heat.lightened(0.4)
	hm_c.a = 0.4 * hm
	var r_M = Rect2(mid_x + 3, 14 + press_m, mid_w - 6, btn_h - 30)
	draw_rect(r_M, m_heat)
	draw_rect(r_M, Color.from_hsv(key_hue, 0.2, 0.4, 0.3), false, 1.0)
	if hm > 0: draw_rect(r_M, hm_c)
	for i in range(4):
		var ly: float = 14.0 + press_m + 6.0 + float(i * 9)
		draw_line(Vector2(mid_x + 5, ly), Vector2(mid_x + mid_w - 5, ly), Color(0.4, 0.45, 0.55, 0.35 + 0.3*hm), 1.0)
	if mid_clicks > 0:
		draw_string(font, Vector2(mid_x + 2, btn_h - 10 + press_m), HeatUtil.format_count(mid_clicks), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.from_hsv(0.35, 0.55, 0.90, 0.90))

	# Right
	var rx := side_w + mid_w
	var r_heat = HeatUtil.heat_color(right_clicks, max_count, key_hue)
	var hr_c = r_heat.lightened(0.4)
	hr_c.a = 0.4 * hr
	var r_R = Rect2(rx, 3 + press_r, side_w - 3, btn_h - 4)
	draw_rect(r_R, r_heat)
	if hr > 0: draw_rect(r_R, hr_c)
	draw_string(font, Vector2(rx + 22, 35 + press_r), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.75, 0.80, 0.88, 0.75) if right_clicks==0 else Color(1.0, 1.0, 1.0, 0.95))
	if right_clicks > 0:
		draw_string(font, Vector2(rx + 8, btn_h - 10 + press_r), HeatUtil.format_count(right_clicks), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.from_hsv(0.35, 0.55, 0.90, 0.90))

	# Total stats
	var sy := mh + 18
	var dim := Color(0.50, 0.55, 0.65, 0.55)
	draw_string(font, Vector2(0, sy), "L: %s" % HeatUtil.format_count(left_clicks), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	draw_string(font, Vector2(50, sy), "M: %s" % HeatUtil.format_count(mid_clicks), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	draw_string(font, Vector2(100, sy), "R: %s" % HeatUtil.format_count(right_clicks), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	if dist_px > 0:
		draw_string(font, Vector2(0, sy + 16), "移动: %.1f m" % (float(dist_px) / 3780.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)

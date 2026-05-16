class_name CyberKey extends Control

var label: String = ""
var data_key: String = ""
var count: int = 0
var max_count: int = 1
var max_delta: float = 1.0
var avg_count: float = 0.0
var delta_mode: bool = false
var key_hue: float = 0.0

var _hover_t := 0.0

func _init_key(l: String, dk: String) -> void:
	label = l
	data_key = dk
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
func _process(delta: float) -> void:
	var target := 1.0 if get_global_rect().has_point(get_global_mouse_position()) else 0.0
	if _hover_t != target:
		_hover_t = move_toward(_hover_t, target, delta * 8.0)
		queue_redraw()

func set_stats(c: int, mc: int, md: float, ac: float, dm: bool, hue: float) -> void:
	count = c
	max_count = maxi(mc, 1)
	max_delta = maxf(md, 1.0)
	avg_count = ac
	delta_mode = dm
	key_hue = hue
	queue_redraw()
	
func _draw() -> void:
	var w := size.x
	var h := size.y
	var press_y: float = floor(3.0 * _hover_t)
	var heat: Color
	if delta_mode and count > 0:
		heat = HeatUtil.delta_heat_color(count, max_delta, avg_count, key_hue)
	else:
		heat = HeatUtil.heat_color(count, max_count, key_hue)
		
	var base_color := heat.darkened(0.4)
	base_color.a = 0.55
	draw_rect(Rect2(0, 2, w, h), base_color)
	
	var tr = Rect2(0, press_y, w, h - 2)
	draw_rect(tr, heat)
	
	if _hover_t > 0:
		var hc = heat.lightened(0.4)
		hc.a = 0.4 * _hover_t
		draw_rect(tr, hc)
		
	if count > 0 or _hover_t > 0:
		var hl := heat.lightened(0.3)
		hl.a = 0.25 + 0.3 * _hover_t
		draw_line(Vector2(2, press_y + 1), Vector2(w - 2, press_y + 1), hl, 1.0)
		
	var ba := 0.20 if count == 0 else lerpf(0.30, 0.55, clampf(float(count) / float(max_count), 0.0, 1.0))
	ba += 0.3 * _hover_t
	draw_rect(tr, Color.from_hsv(key_hue, 0.2, 0.45, ba), false, 1.0)
	
	var glow_t := 0.0
	if count > 0:
		glow_t = clampf(float(count) / float(max_count), 0.0, 1.0)
		if delta_mode:
			glow_t = clampf(absf(float(count) - avg_count) / max_delta, 0.0, 1.0)
	var active_glow = maxf(glow_t - 0.4, 0.0) * 0.2
	active_glow += 0.4 * _hover_t
	if active_glow > 0:
		var glow_hue := key_hue
		if delta_mode and count > 0:
			glow_hue = 0.08 if float(count) > avg_count else 0.6
		var glow := Color.from_hsv(glow_hue, 0.5, 0.8, active_glow)
		draw_rect(Rect2(-1, press_y - 1, w + 2, h - 2 + 2), glow, false, 2.0)
		
	var font := ThemeDB.fallback_font
	var fs := 12
	if label.length() <= 1: fs = 16
	elif label.length() <= 3: fs = 13
	
	var text_color: Color
	if count == 0:
		text_color = Color(0.50, 0.55, 0.65, 0.65 + 0.3 * _hover_t)
	else:
		var t := clampf(float(count) / float(max_count), 0.0, 1.0)
		text_color = Color(1.0, 1.0, 1.0, lerpf(0.75, 1.0, t) + 0.2 * _hover_t)
		
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tx := (w - tw) * 0.5
	var ty: float = press_y + (h - 2.0) * 0.5 + (1.0 if count == 0 else -1.0)
	draw_string(font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	
	if count > 0 or _hover_t > 0:
		var cs: String
		var count_color: Color
		if delta_mode:
			var delta := int(round(float(count) - avg_count))
			if delta >= 0:
				cs = "+%s" % HeatUtil.format_count(delta)
				count_color = Color.from_hsv(0.08, 0.6, 0.95, 0.90)
			else:
				cs = "-%s" % HeatUtil.format_count(-delta)
				count_color = Color.from_hsv(0.58, 0.5, 0.85, 0.85)
		else:
			cs = HeatUtil.format_count(count)
			count_color = Color.from_hsv(0.35, 0.55, 0.90, 0.90)
			
		count_color.a = clampf(count_color.a + _hover_t, 0.0, 1.0)
		var csz := 10
		var cw := font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, csz).x
		draw_string(font, Vector2(w - cw - 3, press_y + h - 5),
			cs, HORIZONTAL_ALIGNMENT_LEFT, -1, csz, count_color)

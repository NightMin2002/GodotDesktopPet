class_name HeatUtil extends RefCounted

static func heat_color(count: int, max_count: int, hue: float) -> Color:
	if count == 0: return Color(0.045, 0.05, 0.07, 0.45)
	var t := clampf(float(count) / float(max_count), 0.0, 1.0)
	var h := lerpf(hue + 0.05, 0.12, t)
	var s := lerpf(0.25, 0.65, t)
	var v := lerpf(0.10, 0.32, t)
	return Color.from_hsv(fmod(h, 1.0), s, v, 0.85)

static func delta_heat_color(count: int, max_delta: float, avg_count: float, hue: float) -> Color:
	var delta := float(count) - avg_count
	var t := clampf(absf(delta) / max_delta, 0.0, 1.0)
	if delta >= 0:
		var h := lerpf(0.12, 0.06, t)
		var s := lerpf(0.20, 0.70, t)
		var v := lerpf(0.10, 0.35, t)
		return Color.from_hsv(h, s, v, 0.85)
	else:
		var h := lerpf(hue, 0.60, t)
		var s := lerpf(0.15, 0.55, t)
		var v := lerpf(0.08, 0.22, t)
		return Color.from_hsv(h, s, v, 0.85)

static func format_count(count: int) -> String:
	if count >= 10000: return "%.0fk" % (float(count) / 1000.0)
	if count >= 1000: return "%.1fk" % (float(count) / 1000.0)
	return str(count)

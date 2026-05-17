# icon.gd — 贪吃蛇大厅图标
# 沿卡片边缘巡航 + 交替伸缩 + 食物脉冲
extends TerminalGameIcon

# snake 图标有状态: 蛇在边缘巡航
var _s_pos: float = 0.0
var _s_len: int = 8
var _s_growing: bool = true
var _s_food: float = -1.0

func _process(delta: float) -> void:
	_time += delta
	_s_pos += delta * 60.0
	queue_redraw()

func _draw() -> void:
	var h = hue()
	var a = alphas()
	var alpha_base = a[0]
	var alpha_hi = a[1]
	var w = size.x
	var ht = size.y
	var t = _time
	var accent_c = accent_color()

	var margin = 3.0
	var pw = w - margin * 2
	var ph = ht - margin * 2
	var perim = 2.0 * (pw + ph)
	var seg_gap = 14.0
	# 食物初始化
	if _s_food < 0:
		_s_food = fmod(_s_pos + perim * 0.4, perim)
	# 吃食检测
	var head_p = fmod(_s_pos, perim)
	var d2f = absf(head_p - _s_food)
	d2f = minf(d2f, perim - d2f)
	if d2f < seg_gap * 0.8:
		if _s_growing:
			_s_len += 1
			if _s_len >= 18:
				_s_growing = false
		else:
			_s_len -= 1
			if _s_len <= 3:
				_s_growing = true
		_s_food = fmod(head_p + perim * randf_range(0.2, 0.45), perim)
	# 绘制蛇身
	var s = 12.0
	for i in range(_s_len):
		var sp = fmod(_s_pos - float(i) * seg_gap + perim * 999.0, perim)
		var pt = _perim_pt(sp, margin, pw, ph, perim)
		var a_val = lerpf(0.15, alpha_hi, 1.0 - float(i) / float(_s_len))
		if i == 0:
			draw_rect(Rect2(pt.x - s * 0.5 - 1.5, pt.y - s * 0.5 - 1.5, s + 3, s + 3), Color.from_hsv(h, 0.35, 0.8, 0.12))
			draw_rect(Rect2(pt.x - s * 0.5, pt.y - s * 0.5, s, s), accent_c)
		else:
			draw_rect(Rect2(pt.x - s * 0.5, pt.y - s * 0.5, s, s), Color.from_hsv(h, 0.4, 0.7, a_val))
	# 食物脉冲
	var fpt = _perim_pt(_s_food, margin, pw, ph, perim)
	var pulse = sin(t * 4.0) * 0.2 + 0.8
	draw_circle(fpt, 4.5 * pulse, Color(0.9, 0.55, 0.3, 0.12), true, -1.0, true)
	draw_circle(fpt, 3.5 * pulse, Color(0.9, 0.55, 0.3, alpha_hi), true, -1.0, true)

## 周长坐标 → 2D 坐标 (矩形路径: 右→下→左→上)
func _perim_pt(p: float, m: float, pw: float, ph: float, perim: float) -> Vector2:
	var pp = fmod(p, perim)
	if pp < 0: pp += perim
	if pp < pw:
		return Vector2(m + pp, m)
	pp -= pw
	if pp < ph:
		return Vector2(m + pw, m + pp)
	pp -= ph
	if pp < pw:
		return Vector2(m + pw - pp, m + ph)
	pp -= pw
	return Vector2(m, m + ph - pp)

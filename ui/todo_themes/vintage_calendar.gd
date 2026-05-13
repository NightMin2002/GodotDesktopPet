# vintage_calendar.gd — 撕页老黄历
# 大红大绿的刻板印刷排版、暴切撕碎的纸边、古法红圈印泥打卡
class_name TodoThemeVintageCalendar extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.96, 0.93, 0.85),   # paper: 发黄脆薄的老粗纸
		Color(0.12, 0.12, 0.12),   # text: 印刷深黑墨
		Color(0.1, 0.45, 0.2),     # accent: 传统排版绿框
		Color(0.85, 0.12, 0.12),   # danger: 朱砂红/大红
		1.0                        # alpha
	)
	
	card_corner = 0
	input_corner = 0
	list_spacing = 8
	checkbox_size_px = Vector2(28, 28)
	
	# 面板边界：顶部留足110px宽广空间给巨大日历红框版头
	panel_margins = [30, 110, 30, 40]
	
	bg_card_sel = Color.TRANSPARENT

class _CalendarPanel extends PanelContainer:
	var _t: TodoThemeBase
	func _init(t: TodoThemeBase) -> void: _t = t

	func _ready() -> void:
		var s = StyleBoxFlat.new()
		s.bg_color = Color.TRANSPARENT
		add_theme_stylebox_override("panel", s)

	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		
		# ==========================================
		# 1. 绘制顶部参差不齐残留碎纸的老黄历底板
		# ==========================================
		var pts = PackedVector2Array()
		var rng = RandomNumberGenerator.new()
		rng.seed = 2024
		
		pts.append(Vector2(0, 0))
		var w = 8.0
		var num_teeth = int(r.size.x / w)
		for i in range(num_teeth):
			var rx = (i + 0.5) * w
			var ry = rng.randf_range(2.0, 6.0)
			if i % 3 == 0: ry = rng.randf_range(6.0, 10.0) # 模拟更深不规则撕口
			pts.append(Vector2(rx, ry))
		pts.append(Vector2(r.size.x, 0))
		pts.append(Vector2(r.size.x, r.size.y))
		pts.append(Vector2(0, r.size.y))
		
		# 全局轻微悬浮阴影
		var s_pts = PackedVector2Array()
		for p in pts: s_pts.append(p + Vector2(2, 4))
		draw_polygon(s_pts, PackedColorArray([Color(0,0,0,0.15)]))
		
		# 黄纸涂满
		draw_polygon(pts, PackedColorArray([_t.bg_main]))
		
		# 顶部装订的生锈铁钉圈
		var nail_c = Color(0.35, 0.35, 0.4)
		draw_rect(Rect2(size.x*0.25, 0, 12, 12), nail_c)
		draw_rect(Rect2(size.x*0.75, 0, 12, 12), nail_c)
		draw_circle(Vector2(size.x*0.25+6, 12), 4, Color(0,0,0,0.2)) # 内打孔
		draw_circle(Vector2(size.x*0.75+6, 12), 4, Color(0,0,0,0.2))

		# ==========================================
		# 2. 招牌日历顶版: 粗暴的大红大绿与复古排版字样
		# ==========================================
		var bx = 16.0
		var by = 24.0
		var bw = size.x - 32.0
		var h_rect = Rect2(bx, by, bw, 60)
		
		# 暴力实心红块
		draw_rect(h_rect, _t.danger)
		# 撞色绿框嵌进去
		draw_rect(h_rect.grow(-3), _t.bg_main, false, 2.0)
		draw_rect(h_rect.grow(-8), _t.accent, false, 2.0)
		
		# “宜”和“忌”封建大字警语
		var font = ThemeDB.fallback_font
		var text1 = "【 宜 划 掉 待 办 】"
		var text2 = "【 忌 摸 鱼 拖 延 】"
		draw_string(font, Vector2(bx + 16, by + 28), text1, 0, -1, 14, _t.bg_main)
		draw_string(font, Vector2(bx + bw - 16 - font.get_string_size(text2, 0, -1, 14).x, by + 28), text2, 0, -1, 14, _t.bg_main)
		
		# 中间掏空显示系统今天是第几日
		var t_dict = Time.get_date_dict_from_system()
		var big_str = "%02d" % t_dict.day
		var ts = font.get_string_size(big_str, 0, -1, 38)
		# 中间巨大显眼的红框白字日期
		draw_string(font, Vector2(size.x*0.5 - ts.x*0.5, by + 46), big_str, 0, -1, 38, _t.bg_main)
		
		# 3. 日历下方经典的复古横向排版分隔细绿线条
		draw_line(Vector2(bx, by + 68), Vector2(bx + bw, by + 68), _t.accent, 1.0)
		draw_line(Vector2(bx, by + 72), Vector2(bx + bw, by + 72), _t.accent, 2.0)

func create_panel() -> PanelContainer:
	return _CalendarPanel.new(self)

# ==========================================
# 进度条：用复古公章矩阵表示 (打卡/盖章)
# ==========================================
class _StampProgress extends Control:
	var _t: TodoThemeBase
	var _done: int = 0
	var _total: int = 0
	
	func _init(t: TodoThemeBase) -> void: 
		_t = t; mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 40)

	func update(done: int, total: int) -> void:
		_done = done; _total = total; queue_redraw()

	func _draw() -> void:
		if _total <= 0: return
		
		var cx = 30.0
		var w = 18.0
		var pad = 6.0
		var font = ThemeDB.fallback_font
		
		var text = "计: %d   完: %d" % [_total, _done]
		var ts = font.get_string_size(text, 0, -1, 14)
		
		var max_avail_w = size.x - cx - ts.x - 30.0
		var max_visible = max(1, int(max_avail_w / (w + pad)))
		
		var draw_count = min(_total, max_visible)
		var fill_count = _done
		if _total > max_visible:
			fill_count = int(round(draw_count * (float(_done) / float(_total))))
		
		for i in range(draw_count):
			var is_done = (i < fill_count)
			var r_c = _t.danger if is_done else Color(_t.danger, 0.15)
			# 画个有轻微破损感的手绘方印
			var s_rect = Rect2(cx + i*(w+pad), size.y*0.5 - w*0.5, w, w)
			draw_rect(s_rect, r_c, false, 2.0)
			# 随机抽几根底色线条斜杠，造成印泥掉色的残破空虚感
			var rng = RandomNumberGenerator.new()
			rng.seed = i * 100
			draw_line(s_rect.position + Vector2(w*rng.randf(), 0), s_rect.position + Vector2(w*rng.randf(), w), _t.bg_main, 1.5)
			
			if is_done:
				# 里面用古风红墨写个篆刻的“功”字象征盖章
				draw_string(font, Vector2(s_rect.position.x + 3, s_rect.position.y + 14), "成", 0, -1, 12, r_c)
		
		draw_string(font, Vector2(size.x - 20 - ts.x, size.y*0.5 + ts.y*0.35), text, 0, -1, 14, _t.tx_primary)
		
		# 底部粗线隔离
		draw_line(Vector2(20, size.y-2), Vector2(size.x-20, size.y-2), _t.accent, 1.5)

func make_progress_indicator() -> Control:
	return _StampProgress.new(self)

func update_progress_indicator(c: Control, d: int, t: int) -> void:
	if c and c.has_method("update"): c.update(d, t)

# ==========================================
# 复选框：极为暴力不羁的朱砂毛笔圈画痕迹
# ==========================================
func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(0)
	s.bg_color = Color.TRANSPARENT
	
	if is_done:
		s.set_border_width_all(0)
		btn.draw.connect(func():
			var center = btn.size * 0.5
			# 用很多段粗细不一的线段连成一个随手重墨画出的大圆圈 (老一辈用毛笔直接在日历上画大红圈的感觉)
			var rng = RandomNumberGenerator.new()
			rng.seed = btn.get_instance_id()
			var rad = 14.0
			var pts = PackedVector2Array()
			# 重覆绕超过一整圈产生毛笔重叠收笔感
			for ang in range(-20, 390, 15):
				var rr = deg_to_rad(ang)
				var jitter = rng.randf_range(-1.0, 1.0)
				pts.append(center + Vector2(cos(rr), sin(rr)) * (rad + jitter))
			
			btn.draw_polyline(pts, danger, 3.5)
			
			# 旁边飞白(毛笔分岔干燥刷出的细散线)
			var f_pts = PackedVector2Array()
			for p in pts:
				f_pts.append(p + Vector2(rng.randf_range(1, 2), rng.randf_range(1, 2)))
			btn.draw_polyline(f_pts, Color(danger, 0.4), 1.5)
			
			# 墨斑飞溅
			for i in range(4):
				btn.draw_circle(center + Vector2(rng.randf_range(-18,18), rng.randf_range(-18,18)), rng.randf_range(0.5, 1.8), Color(danger, rng.randf_range(0.3, 0.8)))
		)
	else:
		s.set_border_width_all(1)
		s.border_color = Color(tx_primary, 0.2)
		# 未完成是淡淡的方框，假装是印刷装订的待办格
		
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	if is_done: h.bg_color = Color(danger, 0.05)
	else: h.bg_color = Color(tx_primary, 0.05)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	s.set_border_width_all(0)
	
	if is_selected:
		s.bg_color = Color(tx_primary, 0.04)
		s.border_width_left = 4
		s.border_color = danger
	else:
		s.bg_color = Color.TRANSPARENT
		
	return s

# 按钮统一做成细长条的红色方印泥框或者绿框字体
func _cal_btn(text: String, is_danger: bool) -> Button:
	var btn = Button.new()
	btn.text = text
	var c = danger if is_danger else accent
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", c)
	btn.add_theme_color_override("font_hover_color", bg_main)
	btn.flat = false
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.border_color = Color(c, 0.7)
	s.set_border_width_all(2)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 4; s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = c
	h.border_color = c
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_add_button(text: String) -> Button: return _cal_btn(text, false)
func make_close_button(text: String) -> Button: 
	var b = _cal_btn("关闭", true)
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return b
func make_theme_button(text: String) -> Button: return _cal_btn("换页", false)
func make_delete_button(text: String) -> Button:
	var b = _cal_btn("删", true)
	b.add_theme_font_size_override("font_size", 11)
	return b

func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s: 
		s.bg_color = Color.TRANSPARENT
		s.set_border_width_all(1)
		s.border_color = Color(accent, 0.2)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f: 
		f.bg_color = Color(tx_primary, 0.02)
		f.set_border_width_all(1)
		f.border_color = accent

func apply_card_title_style(label: Label, is_done: bool, is_selected: bool) -> void:
	label.add_theme_font_size_override("font_size", item_font_size)
	if is_done: 
		label.add_theme_color_override("font_color", Color(tx_primary, 0.35))
	else: 
		label.add_theme_color_override("font_color", tx_primary)

func apply_title_label_style(l: Label) -> void:
	l.add_theme_color_override("font_color", tx_primary)
	l.add_theme_font_size_override("font_size", title_font_size + 2)

# ==========================================
# 自定义滚动条：装订红绳与挂签标记
# ==========================================
class _CalendarScrollbar extends TodoScrollbar:
	func _draw_track(track: Rect2) -> void:
		var c = Color(_t.accent, 0.3)
		var cx = track.position.x + track.size.x * 0.5
		# 细细的穿书线绳
		draw_line(Vector2(cx, track.position.y), Vector2(cx, track.end.y), c, 1.5)

	func _draw_thumb(thumb: Rect2) -> void:
		var c = _t.danger if _dragging else _t.accent
		# 作为挂签（长条矩形，下面剪个燕尾口）
		var p_x = thumb.position.x + 2
		var p_w = thumb.size.x - 4
		var pts = PackedVector2Array([
			Vector2(p_x, thumb.position.y),
			Vector2(p_x + p_w, thumb.position.y),
			Vector2(p_x + p_w, thumb.end.y),
			Vector2(p_x + p_w * 0.5, thumb.end.y - 6),
			Vector2(p_x, thumb.end.y)
		])
		draw_polygon(pts, PackedColorArray([Color(c, 0.85)]))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[0]]), Color(c, 0.95), 1.0)
		
		# 穿过绳的孔
		draw_circle(Vector2(p_x + p_w*0.5, thumb.position.y + 6), 2, _t.bg_main)

func make_scrollbar() -> Control:
	return _CalendarScrollbar.new(self)

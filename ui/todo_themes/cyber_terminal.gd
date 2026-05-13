# cyber_terminal.gd — 全息赛博终端 V2.0 (重构突围版)
# 纯正的黑客UI、全息玻璃感、数据流瀑布与色散(Chromatic Aberration)故障艺术
class_name TodoThemeCyberTerminal extends TodoThemeBase

var cyber_bg = Color(0.015, 0.035, 0.045, 0.85) # 极深的暗黑全息底板
var neon_cyan = Color(0.02, 0.98, 0.88)
var neon_pink = Color(1.0, 0.05, 0.45)
var dim_cyan = Color(0.02, 0.98, 0.88, 0.25)
var text_bright = Color(0.85, 0.98, 1.0)

func _init() -> void:
	_from_seeds(
		cyber_bg,
		text_bright,
		neon_cyan,
		neon_pink,
		0.85
	)
	
	card_corner = 0
	input_corner = 0
	list_spacing = 6
	checkbox_size_px = Vector2(30, 30)
	
	# 面板边界，为两侧的数据流瀑布和外边框留出边距
	panel_margins = [36, 46, 52, 42]
	
	bg_card = Color(0.0, 0.1, 0.1, 0.3)
	bg_card_sel = Color(neon_cyan, 0.08)
	bd_light = dim_cyan

# ═══════════════════════════════════════════════
#  全息边框面板: 视觉错位、色散故障、数据流
# ═══════════════════════════════════════════════

class _CyberPanel extends PanelContainer:
	var _t: TodoThemeBase
	var _time: float = 0.0
	var _font: Font
	
	func _init(t: TodoThemeBase) -> void:
		_t = t
		_font = ThemeDB.fallback_font

	func _ready() -> void:
		var s = StyleBoxFlat.new()
		s.bg_color = Color.TRANSPARENT
		add_theme_stylebox_override("panel", s)

	func _process(delta: float) -> void:
		if not visible: return
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		
		# ==========================================
		# 1. 主框架底色与不对称超大缺角 (Chamfer)
		# ==========================================
		var cut_tl := 16.0
		var cut_br := 48.0
		var pts = PackedVector2Array([
			Vector2(cut_tl, 0), Vector2(size.x, 0),
			Vector2(size.x, size.y - cut_br), Vector2(size.x - cut_br, size.y),
			Vector2(0, size.y), Vector2(0, cut_tl)
		])
		
		# 绘制全息暗光底板
		draw_polygon(pts, PackedColorArray([_t.bg_main]))
		
		# ==========================================
		# 2. 边框的色散(色差 Chromatic Aberration)与心跳闪烁
		# ==========================================
		# 根据正弦波产生不稳定的脉冲毛刺信号
		var glitch_intensity = 0.0
		if randf() > 0.96: # 4% 的概率产生毛刺剧烈震动
			glitch_intensity = randf_range(2.0, 6.0)
		else:
			glitch_intensity = sin(_time * 15.0) * 0.5 + 0.5
			
		var split_dist = 1.0 + glitch_intensity
		
		# 使用红蓝通道分离的技术画三次多边形描边
		var bd_w = 1.5
		# 红色层（向左下偏移）
		var c_red = Color(1.0, 0.0, 0.3, 0.6)
		_draw_shifted_polyline(pts, Vector2(-split_dist, split_dist), c_red, bd_w)
		# 青色层（向右上偏移）
		var c_cyan = Color(0.0, 1.0, 0.8, 0.6)
		_draw_shifted_polyline(pts, Vector2(split_dist, -split_dist), c_cyan, bd_w)
		# 核心高白层
		_draw_shifted_polyline(pts, Vector2.ZERO, Color(1,1,1, 0.4), bd_w)

		# ==========================================
		# 3. 科技装饰线与刻度
		# ==========================================
		# 右下角超大缺角处的警告条纹
		var stripe_c = Color(_t.danger, 0.7)
		var lx = size.x - cut_br + 4
		var ly = size.y - 2
		for i in range(5):
			draw_line(Vector2(lx + i*7, ly - i*7), Vector2(lx + i*7 + 4, ly - i*7), stripe_c, 2.0)
		
		# 左上角的数据线口
		draw_line(Vector2(0, cut_tl + 10), Vector2(10, cut_tl + 10), _t.accent, 2.0)
		draw_line(Vector2(10, cut_tl + 10), Vector2(14, cut_tl + 14), _t.accent, 2.0)
		draw_line(Vector2(14, cut_tl + 14), Vector2(14, size.y * 0.4), _t.accent, 2.0)

		# ==========================================
		# 4. 滚动的十六进制数据流 (Hex Dump Waterfall)
		# ==========================================
		var raw_t = int(_time * 18)
		var text_color = Color(_t.accent, 0.3)
		# 右侧侧边栏下落的数据流
		for i in range(20):
			var y_pos = 45 + i * 16
			if y_pos < size.y - cut_br - 10:
				# 每一行算出一个伪随机的四位十六进制数，不断跳动
				var hex = "%04X" % ((raw_t * (i+1) + i*997) % 0xFFFF)
				# 偶尔有些变成警告红色
				var tc = text_color
				if (raw_t + i) % 30 == 0: tc = Color(_t.danger, 0.6)
				draw_string(_font, Vector2(size.x - 42, y_pos), hex, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tc)
				
		# ==========================================
		# 5. 雷达全息扫频线 (CRT Scanline Laser)
		# ==========================================
		var scan_y = fmod(_time * 150.0, size.y)
		# 高亮主光束
		draw_line(Vector2(2, scan_y), Vector2(size.x - 2, scan_y), Color(_t.accent, 0.5), 1.0)
		# 余晖带
		draw_rect(Rect2(2, scan_y - 30, size.x - 4, 30), Color(_t.accent, 0.04))

	func _draw_shifted_polyline(pts: PackedVector2Array, offset: Vector2, color: Color, width: float) -> void:
		var sp = PackedVector2Array()
		for p in pts: sp.append(p + offset)
		draw_polyline(sp, color, width)
		draw_line(sp[0], sp[sp.size()-1], color, width) # 闭合

func create_panel() -> PanelContainer:
	return _CyberPanel.new(self)

# ═══════════════════════════════════════════════
#  组件覆盖：强反馈式的科技电子组件
# ═══════════════════════════════════════════════

# 进度条：音波均衡器 / 数据带宽加载带
class _CyberEQProgress extends Control:
	var _t: TodoThemeBase
	var _done: int = 0
	var _total: int = 0
	var _time: float = 0.0

	func _init(t: TodoThemeBase) -> void:
		_t = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 36)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func update(done: int, total: int) -> void:
		_done = done; _total = total
		queue_redraw()

	func _draw() -> void:
		if _total <= 0: return
		var r = Rect2(Vector2.ZERO, size)
		
		# 左上角加上标志性的微缩字框
		var font = ThemeDB.fallback_font
		draw_rect(Rect2(0, 2, 40, 10), _t.accent)
		draw_string(font, Vector2(2, 11), "BANDWIDTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, _t.bg_main)
		
		var bx = 46.0
		var bar_h = 16.0
		var by = (size.y - bar_h) * 0.5
		var bar_w = size.x - bx - 80 
		
		# 用一根根密集的竖线代表进度带宽
		var lines_count = 50
		var gap = 2.0
		var line_w = (bar_w - gap * (lines_count - 1)) / float(lines_count)
		
		var ratio = float(_done) / float(_total)
		var active_lines = int(lines_count * ratio)
		
		for i in range(lines_count):
			var x = bx + i * (line_w + gap)
			var cur_h = bar_h
			
			if i < active_lines:
				# 正在加载的顶端产生跳动的均衡器效果
				if i >= active_lines - 3 and _done < _total:
					cur_h = bar_h * (0.6 + randf() * 0.4)
				var c = _t.accent
				if randf() > 0.95: c = Color(1,1,1,0.9) # 随机电流爆耀
				draw_rect(Rect2(x, by + (bar_h - cur_h)*0.5, line_w, cur_h), c)
			else:
				# 未激活的槽位就是暗色的
				draw_rect(Rect2(x, by + bar_h*0.3, line_w, bar_h*0.4), Color(_t.accent, 0.15))
		
		# 右侧是数字
		var text = "[ %02d/%02d ]" % [_done, _total]
		var text_c = _t.danger if _done == _total else _t.accent
		draw_string(font, Vector2(bx + bar_w + 12, by + bar_h*0.8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_c)

func make_progress_indicator() -> Control:
	return _CyberEQProgress.new(self)

func update_progress_indicator(ctrl: Control, done: int, total: int) -> void:
	if ctrl and ctrl.has_method("update"):
		ctrl.update(done, total)

# 复选框：六边形 / 瞄准框节点
func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(0)
	s.bg_color = Color.TRANSPARENT
	s.set_border_width_all(0)
	
	btn.draw.connect(func():
		var center = btn.size * 0.5
		var r = 10.0
		
		if is_done:
			# 完成时：实心青红渐变（假装）的多边形并带有高光，中心镂空对勾
			# 我们画一个充满科技感的填充菱形或者大区块
			var pts = PackedVector2Array([
				center + Vector2(0, -r-2), center + Vector2(r+2, 0),
				center + Vector2(0, r+2), center + Vector2(-r-2, 0)
			])
			btn.draw_polygon(pts, PackedColorArray([accent]))
			# 中心掏空错位的电子痕迹
			btn.draw_line(center + Vector2(-5,0), center + Vector2(-1,4), bg_main, 2.5)
			btn.draw_line(center + Vector2(-1,4), center + Vector2(6,-4), bg_main, 2.5)
			
			# 外面带一圈红色的危险锁定框表示彻底封存
			btn.draw_line(Vector2(0,0), Vector2(6,0), danger, 1.5)
			btn.draw_line(Vector2(0,0), Vector2(0,6), danger, 1.5)
			btn.draw_line(Vector2(btn.size.x, btn.size.y), Vector2(btn.size.x-6, btn.size.y), danger, 1.5)
			btn.draw_line(Vector2(btn.size.x, btn.size.y), Vector2(btn.size.x, btn.size.y-6), danger, 1.5)
		else:
			# 未完成时：类似相机的四角准星
			var len = 6.0
			var c = bd_light
			btn.draw_line(center + Vector2(-r, -r), center + Vector2(-r+len, -r), c, 2.0)
			btn.draw_line(center + Vector2(-r, -r), center + Vector2(-r, -r+len), c, 2.0)
			btn.draw_line(center + Vector2(r, -r), center + Vector2(r-len, -r), c, 2.0)
			btn.draw_line(center + Vector2(r, -r), center + Vector2(r, -r+len), c, 2.0)
			btn.draw_line(center + Vector2(-r, r), center + Vector2(-r+len, r), c, 2.0)
			btn.draw_line(center + Vector2(-r, r), center + Vector2(-r, r-len), c, 2.0)
			btn.draw_line(center + Vector2(r, r), center + Vector2(r-len, r), c, 2.0)
			btn.draw_line(center + Vector2(r, r), center + Vector2(r, r-len), c, 2.0)
			
			# 中心一个小原点
			btn.draw_rect(Rect2(center.x-1, center.y-1, 2, 2), Color(c, 0.5))
	)
		
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color(accent, 0.15)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

# 卡片：带数据读取块的列表项
func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(0)
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	s.set_border_width_all(0)
	
	if is_selected:
		s.bg_color = bg_card_sel
		# 左侧加厚扫描高亮，类似光剑
		s.border_width_left = 3
		s.border_color = accent
	elif is_done:
		s.bg_color = Color(0,0,0,0.25)
		s.border_width_left = 2
		s.border_color = Color(bd_light, 0.15)
	else:
		s.bg_color = bg_card
		s.border_width_left = 1
		s.border_color = bd_light
		
	return s

# 科幻操作扁平按钮
func _glitch_btn(text: String, c_accent: Color, c_bg: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", c_accent)
	btn.add_theme_color_override("font_hover_color", bg_main)
	btn.flat = false
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color(c_bg, 0.6)
	s.set_border_width_all(1)
	s.border_color = Color(c_accent, 0.5)
	s.set_corner_radius_all(0)
	s.content_margin_left = 16; s.content_margin_right = 16
	s.content_margin_top = 4; s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = c_accent
	h.border_color = c_accent
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_add_button(text: String) -> Button:
	return _glitch_btn("REQ_ADD // " + text, accent, Color(0,0,0,0.5))

func make_close_button(text: String) -> Button:
	var btn = _glitch_btn("X TERM // " + text, danger, Color(danger, 0.1))
	btn.custom_minimum_size.y = 26
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return btn

func make_delete_button(text: String) -> Button:
	var b = _glitch_btn("DEL", danger, Color(0,0,0,0))
	b.add_theme_font_size_override("font_size", 11)
	return b

func make_theme_button(text: String) -> Button:
	return _glitch_btn("MOD_" + text.to_upper(), accent, Color(accent, 0.1))

func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s:
		s.bg_color = Color(0, 0.05, 0.06, 0.5)
		s.set_border_width_all(1)
		s.border_color = Color(accent, 0.15)
		s.set_corner_radius_all(0)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f:
		f.bg_color = Color(0, 0.15, 0.12, 0.5)
		f.set_border_width_all(1)
		f.border_color = accent

func apply_card_title_style(label: Label, is_done: bool, is_selected: bool) -> void:
	label.add_theme_font_size_override("font_size", item_font_size)
	if is_selected:
		label.add_theme_color_override("font_color", text_bright) 
	elif is_done:
		label.add_theme_color_override("font_color", Color(text_bright, 0.3))
	else:
		label.add_theme_color_override("font_color", Color(text_bright, 0.8))

func apply_title_label_style(l: Label) -> void:
	l.add_theme_color_override("font_color", accent)
	l.add_theme_font_size_override("font_size", title_font_size)

# ==========================================
# 自定义滚动条：霓虹光导纤维与扫描块
# ==========================================
class _CyberScrollbar extends TodoScrollbar:
	func _draw_track(track: Rect2) -> void:
		var c = Color(_t.accent, 0.15)
		var cx = track.position.x + track.size.x * 0.5
		# 发光数据轨道
		draw_line(Vector2(cx, track.position.y), Vector2(cx, track.end.y), c, 1.0)
		for y in range(int(track.position.y), int(track.end.y), 30):
			draw_line(Vector2(cx-2, y), Vector2(cx+2, y), c, 1.0)

	func _draw_thumb(thumb: Rect2) -> void:
		var c = _t.accent if _dragging else Color(_t.accent, 0.6)
		# 扫描器主体
		draw_rect(thumb, Color(c, 0.3))
		draw_line(thumb.position, Vector2(thumb.end.x, thumb.position.y), c, 2.0)
		draw_line(Vector2(thumb.position.x, thumb.end.y), thumb.end, c, 2.0)
		# 侧边高亮三角箭头指示器
		var m_y = thumb.position.y + thumb.size.y * 0.5
		var pts = PackedVector2Array([
			Vector2(thumb.end.x - 2, m_y - 4),
			Vector2(thumb.end.x + 2, m_y),
			Vector2(thumb.end.x - 2, m_y + 4)
		])
		draw_polygon(pts, PackedColorArray([c]))
		
		if _dragging:
			draw_rect(thumb.grow(2), Color(c, 0.15), false, 1.0)

func make_scrollbar() -> Control:
	return _CyberScrollbar.new(self)

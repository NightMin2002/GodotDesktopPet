# receipt_paper.gd — 购物小票
# 具有被暴力撕扯下锯齿状边缘的热敏纸、条形码进度条及褪色印章
class_name TodoThemeReceiptPaper extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.93, 0.93, 0.90),   # base: 热敏纸泛黄白灰
		Color(0.12, 0.16, 0.22),   # text: 陈旧的热敏打印墨迹(偏褪色蓝紫)
		Color(0.12, 0.16, 0.22),   # accent: 同样颜色
		Color(0.85, 0.25, 0.20),   # danger: 鲜艳的结算红章、退款
		1.0                        # alpha
	)
	
	card_corner = 0
	input_corner = 0
	list_spacing = 8
	checkbox_size_px = Vector2(26, 26)
	
	# 小票边缘是锯齿，内边距加大避免字吃进去
	panel_margins = [32, 54, 32, 44]
	
	bg_card_sel = Color.TRANSPARENT

class _ReceiptPanel extends PanelContainer:
	var _t: TodoThemeBase
	func _init(t: TodoThemeBase) -> void: _t = t

	func _ready() -> void:
		var s = StyleBoxFlat.new()
		s.bg_color = Color.TRANSPARENT
		add_theme_stylebox_override("panel", s)

	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		
		# ==========================================
		# 1. 锯齿边缘计算 (Torn edge poly)
		# ==========================================
		var tooth_h := 8.0
		var tooth_count_x : int = maxi(2, int(r.size.x / 14.0))
		var tooth_w : float = r.size.x / float(tooth_count_x)
		
		var pts = PackedVector2Array()
		# 顶边锯齿 (从左向右)
		for i in range(tooth_count_x + 1):
			pts.append(Vector2(i * tooth_w, tooth_h if i%2==1 else 0))
		# 右沿
		pts.append(Vector2(size.x, size.y - tooth_h))
		# 底边锯齿 (从右向左)
		for i in range(tooth_count_x, -1, -1):
			pts.append(Vector2(i * tooth_w, size.y - (0 if i%2==1 else tooth_h)))
		# 回归
		pts.append(Vector2(0, 0))

		# ==========================================
		# 2. 立体纸张投影
		# ==========================================
		var s_pts = PackedVector2Array()
		for p in pts: s_pts.append(p + Vector2(2, 4))
		draw_polygon(s_pts, PackedColorArray([Color(0,0,0,0.12)]))
		
		# ==========================================
		# 3. 纸张底色与褪色杂质
		# ==========================================
		draw_polygon(pts, PackedColorArray([_t.bg_main]))
		# 一点微弱的纵向油墨涂抹痕迹
		draw_line(Vector2(12, 0), Vector2(12, size.y), Color(_t.tx_primary, 0.03), 8.0)
		draw_line(Vector2(size.x-20, 0), Vector2(size.x-20, size.y), Color(_t.tx_primary, 0.05), 14.0)

		# ==========================================
		# 4. 顶部打字机 Header 装饰
		# ==========================================
		var head_y = 22.0
		var font = ThemeDB.fallback_font
		var head_s = "=== PET STORE RECEIPT ==="
		var ts = font.get_string_size(head_s, 0, -1, 11)
		draw_string(font, Vector2((size.x - ts.x)*0.5, head_y), head_s, 0, -1, 11, Color(_t.tx_primary, 0.4))
		
		var head_y2 = 38.0
		var t_dict = Time.get_date_dict_from_system()
		var date_str = "DATE:  %04d-%02d-%02d ORDER" % [t_dict.year, t_dict.month, t_dict.day]
		var ts2 = font.get_string_size(date_str, 0, -1, 11)
		draw_string(font, Vector2((size.x - ts2.x)*0.5, head_y2), date_str, 0, -1, 11, Color(_t.tx_primary, 0.4))
		
func create_panel() -> PanelContainer:
	return _ReceiptPanel.new(self)

# 进度条：扫描条形码 Barcode！
class _BarcodeProgress extends Control:
	var _t: TodoThemeBase
	var _done: int = 0
	var _total: int = 0
	
	func _init(t: TodoThemeBase) -> void: 
		_t = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 48)

	func update(done: int, total: int) -> void:
		_done = done; _total = total; queue_redraw()

	func _draw() -> void:
		if _total <= 0: return
		var r = Rect2(Vector2.ZERO, size)
		
		# 左右预留点边距
		var bx = 24.0
		var bar_w = size.x - bx * 2
		var bar_h = 32.0
		var by = 8.0
		
		var ratio = float(_done) / float(_total)
		var ink_c = _t.tx_primary
		var empty_c = Color(_t.tx_primary, 0.1)
		
		# 用固定随机种子生成条形码的宽窄阵列
		var rng = RandomNumberGenerator.new()
		rng.seed = 10010 
		
		var x = bx
		var i = 0
		while x < bx + bar_w:
			# 随机一条线的宽度 1~4
			var line_w = rng.randf_range(1.0, 5.0)
			if x + line_w > bx + bar_w: line_w = bx + bar_w - x
			
			# 判断落入的区域
			var current_ratio = (x - bx) / bar_w
			var is_filled = (current_ratio <= ratio)
			
			# 完成则是强黑蓝墨水，否则是淡淡的浅灰表示等待被“打印”
			var line_c = ink_c if is_filled else empty_c
			
			# 有些条形码长一些下拉 (经典的辅助识别框边界)
			var is_long = (rng.randf() > 0.8)
			var cur_h = bar_h + 8.0 if is_long else bar_h
			
			# 条形码必然是黑白相间，跳过偶数
			if i % 2 == 0:
				draw_rect(Rect2(x, by, line_w, cur_h), line_c)
				
			x += line_w
			i += 1
			
		# 条形码底部写进度文字
		var font = ThemeDB.fallback_font
		var fs = 14
		var text = "NO. %02d   TOTAL %02d" % [_done, _total]
		# 找到条形码中间底端
		var ts = font.get_string_size(text, 0, -1, fs)
		# 避开 is_long 的线条
		draw_rect(Rect2(size.x*0.5 - ts.x*0.5 - 4, by + bar_h + 1, ts.x + 8, 14), _t.bg_main)
		draw_string(font, Vector2(size.x*0.5 - ts.x*0.5, by + bar_h + 12), text, 0, -1, fs, ink_c)

func make_progress_indicator() -> Control:
	return _BarcodeProgress.new(self)

func update_progress_indicator(c: Control, d: int, t: int) -> void:
	if c and c.has_method("update"): c.update(d, t)

# 复选框：空心方框 vs 狂野红色结算印章
func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(1)
	s.bg_color = Color.TRANSPARENT
	
	if is_done:
		s.set_border_width_all(0)
		btn.draw.connect(func():
			var center = btn.size * 0.5
			var stamp_c = Color(danger, 0.85) # 有点透出来的印泥感
			btn.draw_rect(Rect2(1, 4, btn.size.x-2, btn.size.y-8), stamp_c, false, 2.0)
			
			# 文字斜着盖上去
			var t_trans = Transform2D(deg_to_rad(-15), center)
			btn.draw_set_transform_matrix(t_trans)
			var font = ThemeDB.fallback_font
			btn.draw_string(font, Vector2(-8, 5), "OK", 0, -1, 16, stamp_c)
			btn.draw_set_transform_matrix(Transform2D())
		)
	else:
		s.set_border_width_all(1)
		s.border_color = Color(tx_primary, 0.5)
		s.border_blend = true
		
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	if is_done: h.bg_color = Color(danger, 0.1)
	else: h.bg_color = Color(tx_primary, 0.1)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

# 小票点阵划线，取消背景，被选中时有微微的条码扫描线反光感
func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	s.set_border_width_all(0)
	
	if is_selected:
		s.bg_color = Color(tx_primary, 0.04)
		s.border_width_left = 6
		s.border_color = tx_primary
	else:
		s.bg_color = Color.TRANSPARENT
		
	return s

# 打字机字母组成的按钮
func _receipt_btn(text: String, is_danger: bool) -> Button:
	var btn = Button.new()
	btn.text = text
	var c = danger if is_danger else tx_primary
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", c)
	btn.add_theme_color_override("font_hover_color", bg_main)
	btn.flat = false
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.border_color = Color(c, 0.5)
	s.set_border_width_all(1)
	s.content_margin_left = 8; s.content_margin_right = 8
	s.content_margin_top = 4; s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = c
	h.border_color = c
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_add_button(text: String) -> Button: return _receipt_btn("[+ " + text + "]", false)
func make_close_button(text: String) -> Button: 
	var b = _receipt_btn("<X>", true)
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return b
func make_theme_button(text: String) -> Button: return _receipt_btn("[-SWITCH-]", false)
func make_delete_button(text: String) -> Button:
	var b = _receipt_btn("void", true)
	b.add_theme_font_size_override("font_size", 11)
	return b

func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s: 
		s.bg_color = Color.TRANSPARENT
		s.set_border_width_all(1)
		s.border_color = Color(tx_primary, 0.2)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f: 
		f.bg_color = Color(tx_primary, 0.02)
		f.set_border_width_all(1)
		f.border_color = tx_primary

func apply_card_title_style(label: Label, is_done: bool, is_selected: bool) -> void:
	label.add_theme_font_size_override("font_size", item_font_size)
	if is_done: 
		label.add_theme_color_override("font_color", Color(tx_primary, 0.4))
	else: 
		label.add_theme_color_override("font_color", tx_primary)

func apply_title_label_style(l: Label) -> void:
	l.add_theme_color_override("font_color", tx_primary)
	l.add_theme_font_size_override("font_size", title_font_size)

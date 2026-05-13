# notebook_postit.gd — 手账便利贴
# 信纸格纹、红蓝划线、墨水笔触效果与胶带黏贴感
class_name TodoThemeNotebookPostit extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.99, 0.96, 0.89),   # base: 温暖的奶油黄纸张
		Color(0.15, 0.18, 0.22),   # text: 碳素墨水黑/深灰
		Color(0.88, 0.25, 0.25),   # accent: 红圆珠笔批注
		Color(0.60, 0.55, 0.65),   # danger: 褪色紫/暗灰完成感
		1.0                        # alpha: 纸张实体
	)
	
	card_corner = 6
	input_corner = 4
	list_spacing = 6
	checkbox_size_px = Vector2(30, 30)
	
	# 给左侧红线和顶部胶带留出空间
	panel_margins = [45, 38, 20, 24]

	# 选中时模拟黄色荧光笔高亮
	bg_card_sel = Color(1.0, 0.92, 0.20, 0.35)
	bd_select = Color.TRANSPARENT

# ═══════════════════════════════════════════════
#  手账纸张与胶带面板
# ═══════════════════════════════════════════════

class _NotebookPanel extends PanelContainer:
	var _t: TodoThemeBase
	var _rng := RandomNumberGenerator.new()
	
	func _init(t: TodoThemeBase) -> void:
		_t = t

	func _ready() -> void:
		var s = StyleBoxFlat.new()
		s.bg_color = Color.TRANSPARENT
		add_theme_stylebox_override("panel", s)

	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		
		# 1. 绘制纸张底色与极淡的纸张边缘阴影
		# 虽然面板本身是透明的，我们在这里画一个实心浅黄矩形作为纸身
		# 留出右下角一点点空间画阴影假透视
		var shadow_offset := Vector2(3, 4)
		draw_rect(Rect2(shadow_offset, size - shadow_offset), Color(0.0, 0.0, 0.0, 0.12))
		draw_rect(Rect2(Vector2.ZERO, size - shadow_offset), _t.bg_main)
		
		# 2. 绘制笔记本特有的横向虚线/浅蓝实线
		var line_spacing := 26.0
		var line_c = Color(0.35, 0.65, 0.85, 0.3)
		var y = 50.0
		while y < r.size.y - 10:
			draw_line(Vector2(0, y), Vector2(r.size.x - shadow_offset.x, y), line_c, 1.0)
			y += line_spacing
			
		# 3. 绘制左侧红线 (经典活页纸边缘双红线)
		var red_c = Color(0.9, 0.3, 0.4, 0.4)
		draw_line(Vector2(32, 0), Vector2(32, r.size.y - shadow_offset.y), red_c, 1.0)
		draw_line(Vector2(36, 0), Vector2(36, r.size.y - shadow_offset.y), red_c, 1.0)
		
		# 4. 绘制顶部的半透明"和纸胶带"
		# 使用多边形画一个略微倾斜的长方形以产生手撕贴上的感觉
		_rng.seed = 2026
		var tape_w := 90.0
		var tape_h := 24.0
		var tape_center = Vector2(r.size.x * 0.5, 6.0)
		var tape_ang = _rng.randf_range(-0.06, 0.06)
		var tape_c = Color(0.9, 0.8, 0.7, 0.6) # 半透明牛皮纸色
		
		var t_pts = PackedVector2Array()
		# 制造手撕毛边边缘
		var steps = 8
		# 左边缘(毛边)
		for i in range(steps + 1):
			var lp = Vector2(-tape_w*0.5 + _rng.randf_range(-3, 3), -tape_h*0.5 + tape_h * i / steps)
			t_pts.append(tape_center + lp.rotated(tape_ang))
		# 底边缘(直线)
		t_pts.append(tape_center + Vector2(tape_w*0.5, tape_h*0.5).rotated(tape_ang))
		# 右边缘(毛边)
		for i in range(steps + 1):
			var rp = Vector2(tape_w*0.5 + _rng.randf_range(-3, 3), tape_h*0.5 - tape_h * i / steps)
			t_pts.append(tape_center + rp.rotated(tape_ang))
		# 顶边缘(直线)
		t_pts.append(tape_center + Vector2(-tape_w*0.5, -tape_h*0.5).rotated(tape_ang))
		
		draw_polygon(t_pts, PackedColorArray([tape_c]))

func create_panel() -> PanelContainer:
	return _NotebookPanel.new(self)

# ═══════════════════════════════════════════════
#  手绘特化组件
# ═══════════════════════════════════════════════

# 进度条：手绘圈圈填涂法
class _PostitProgress extends Control:
	var _t: TodoThemeBase
	var _done: int = 0
	var _total: int = 0
	var _rng := RandomNumberGenerator.new()

	func _init(t: TodoThemeBase) -> void:
		_t = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 36)

	func update(done: int, total: int) -> void:
		_done = done; _total = total
		queue_redraw()

	func _draw() -> void:
		if _total <= 0: return
		
		var pad_x := 15.0
		var bar_y := size.y * 0.5
		var bar_w := size.x - pad_x * 2 - 30
		var bx = pad_x
		
		var gap := 24.0
		var start_x = bx + 5
		
		var ink_c = _t.tx_primary
		var fill_c = _t.accent
		
		# 仅仅最多画 12 个圆圈，多于12个则压缩间距，保证不溢出
		var visible_total = min(_total, int(bar_w / gap))
		var real_gap = bar_w / visible_total if visible_total > 0 else gap
		
		for i in range(visible_total):
			_rng.seed = 100 + i # 保证每个圈的毛躁不变
			var cx = start_x + i * real_gap
			var cr = 6.5
			var center = Vector2(cx, bar_y)
			
			# 手绘墨水线圈 (画两圈，起点终点有偏移)
			_draw_wobbly_circle(center, cr, ink_c, 1.2)
			_draw_wobbly_circle(center, cr-0.5, Color(ink_c, 0.6), 0.8)
			
			# 如果已完成，则在圈内用红色马克笔涂满 (随意的折线)
			var cur_done_ratio = float(_done) / float(_total)
			var active_blocks = int(visible_total * cur_done_ratio)
			
			if i < active_blocks:
				var pc = PackedVector2Array()
				# 随意涂五下
				pc.append(center + Vector2(-cr+1, -cr+2))
				pc.append(center + Vector2(cr-2, -cr*0.5))
				pc.append(center + Vector2(-cr+2, cr*0.1))
				pc.append(center + Vector2(cr-1, cr-2))
				pc.append(center + Vector2(-cr+3, cr))
				draw_polyline(pc, fill_c, 2.0)
				
		var font = ThemeDB.fallback_font
		var fs := 14
		var text = "%d/%d" % [_done, _total]
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		
		# 手写体感觉的进度数字，带一点倾斜
		var tx = start_x + visible_total * real_gap + 10
		var ty = bar_y + text_size.y * 0.3
		draw_string(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink_c)

	func _draw_wobbly_circle(center: Vector2, r: float, c: Color, w: float) -> void:
		var pts = PackedVector2Array()
		for ang in range(0, 380, 20):
			var rad = deg_to_rad(ang)
			var w_r = r + _rng.randf_range(-0.8, 1.2)
			pts.append(center + Vector2(cos(rad)*w_r, sin(rad)*w_r))
		draw_polyline(pts, c, w)

func make_progress_indicator() -> Control:
	return _PostitProgress.new(self)

func update_progress_indicator(ctrl: Control, done: int, total: int) -> void:
	if ctrl and ctrl.has_method("update"):
		ctrl.update(done, total)

func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.set_border_width_all(0)
	
	btn.draw.connect(func():
		var center = btn.size * 0.5
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(btn.get_instance_id()) # 按钮对象固定hash，保证每次刷新毛躁不变
		var ink = tx_primary
		var r = 8.0
		
		# 手绘正方形框
		var pts = PackedVector2Array([
			center + Vector2(-r, -r) + Vector2(rng.randf_range(-1,1), rng.randf_range(-1,1)),
			center + Vector2(r, -r) + Vector2(rng.randf_range(-1,1), rng.randf_range(-1,1)),
			center + Vector2(r, r) + Vector2(rng.randf_range(-1,1), rng.randf_range(-1,1)),
			center + Vector2(-r, r) + Vector2(rng.randf_range(-1,1), rng.randf_range(-1,1)),
			center + Vector2(-r, -r) + Vector2(rng.randf_range(-1,1), rng.randf_range(-1,1)) # 略微过冲
		])
		# 重复描两遍
		btn.draw_polyline(pts, Color(ink, 0.7), 1.5)
		
		if is_done:
			# 红色勾勾画出框外
			var red = accent
			var ck = PackedVector2Array([
				center + Vector2(-r-2, 0),
				center + Vector2(-2, r+4),
				center + Vector2(r+6, -r-6)
			])
			btn.draw_polyline(ck, red, 2.5)
	)
		
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(0,0,0,0.03) # 鼠标滑过时极淡的阴影
	h.set_corner_radius_all(12)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(card_corner)
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	s.set_border_width_all(0)
	
	if is_selected:
		s.bg_color = bg_card_sel # 黄色荧光高亮
	elif is_done:
		s.bg_color = Color(tx_primary, 0.03) # 铅笔扫过去的淡淡涂影
	else:
		s.bg_color = Color.TRANSPARENT
		
	return s

func _postit_btn(text: String, fg: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
	# 偏向带有纸张质感的深灰或红色
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg.lightened(0.2))
	btn.flat = false
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	# 按钮只用简单的下划线模拟
	s.border_color = Color(fg, 0.3)
	s.set_border_width_all(0)
	s.border_width_bottom = 2
	s.content_margin_left = 6; s.content_margin_right = 6
	s.content_margin_top = 4; s.content_margin_bottom = 2
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color(fg, 0.08)
	h.border_color = fg
	h.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_add_button(text: String) -> Button:
	return _postit_btn(text, tx_primary)

func make_close_button(text: String) -> Button:
	var btn = _postit_btn(text, danger)
	btn.custom_minimum_size.y = 28
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return btn

func make_delete_button(text: String) -> Button:
	# 行内的小按钮也要变柔和
	return _postit_btn(text, danger)

func make_theme_button(text: String) -> Button:
	return _postit_btn(text, accent)

func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s:
		s.bg_color = Color(0,0,0, 0.02)
		s.set_border_width_all(0)
		# 侧边留一条粗一点的高亮色块，像书签
		s.border_width_left = 4
		s.border_color = Color(bg_card_sel, 0.6)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f:
		f.bg_color = Color(1,1,1, 0.4)
		f.set_border_width_all(0)
		f.border_width_left = 4
		f.border_color = bg_card_sel

func apply_card_title_style(label: Label, is_done: bool, is_selected: bool) -> void:
	label.add_theme_font_size_override("font_size", item_font_size)
	if is_done:
		# 完成时的文字像是被铅笔划掉一样灰显
		label.add_theme_color_override("font_color", danger) 
	elif is_selected:
		label.add_theme_color_override("font_color", tx_primary)
	else:
		label.add_theme_color_override("font_color", tx_primary)

func apply_title_label_style(l: Label) -> void:
	l.add_theme_color_override("font_color", tx_primary)
	l.add_theme_font_size_override("font_size", title_font_size + 2) # 稍微放大

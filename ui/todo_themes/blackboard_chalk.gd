# blackboard_chalk.gd — 黑板与粉笔
# 怀旧木边框 + 残留擦痕 + 粉笔涂鸦体
# 自包含: 边框面板类 + 全部组件覆写
class_name TodoThemeBlackboardChalk extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.18, 0.28, 0.22),   # base: 深哑光墨绿色黑板
		Color(0.96, 0.96, 0.92),   # text: 白粉笔
		Color(0.95, 0.90, 0.45),   # accent: 黄粉笔
		Color(0.90, 0.48, 0.45),   # danger: 红粉笔
		1.0                        # alpha: 实体黑板不透明
	)
	
	card_corner = 2
	input_corner = 2
	list_spacing = 10
	checkbox_size_px = Vector2(24, 24)
	
	# 修改面板边距为适应木边框厚度 (比常规主题增加 10px 的内边距)
	panel_margins = [30, 28, 30, 36]
	
	bg_card_sel = Color.TRANSPARENT
	bd_select = accent

# ═══════════════════════════════════════════════
#  自定义边框面板: 木制边框 + 墨绿黑板 + 粉笔擦痕涂鸦
# ═══════════════════════════════════════════════

class _BlackboardPanel extends PanelContainer:
	var _t: TodoThemeBase
	func _init(t: TodoThemeBase) -> void: _t = t
	func _ready() -> void:
		var s = StyleBoxFlat.new()
		s.bg_color = Color.TRANSPARENT
		add_theme_stylebox_override("panel", s)
	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		
		# 1. 绘制木制边框底色 (实心外框)
		var wood_c = Color(0.35, 0.22, 0.14)
		draw_rect(r, wood_c)
		
		# 2. 内切黑板底色 (深墨绿)
		var bs := 10.0 # 边框厚度
		var board_r = r.grow(-bs)
		draw_rect(board_r, _t.bg_main)
		
		# 3. 木框立体感阴影
		draw_line(Vector2(bs, bs), Vector2(r.size.x - bs, bs), Color(0,0,0, 0.6), 2.0)
		draw_line(Vector2(bs, bs), Vector2(bs, r.size.y - bs), Color(0,0,0, 0.6), 2.0)
		draw_line(Vector2(bs, r.size.y - bs), Vector2(r.size.x - bs, r.size.y - bs), Color(1,1,1, 0.15), 2.0)
		draw_line(Vector2(r.size.x - bs, bs), Vector2(r.size.x - bs, r.size.y - bs), Color(1,1,1, 0.15), 2.0)
		
		# 4. 模拟粉笔黑板擦痕迹 (利用固定种子的随机大面积低透明度椭圆)
		var rng = RandomNumberGenerator.new()
		rng.seed = 8848 # 固定种子保持擦痕每次打开完全一致
		var dust_c = Color(1.0, 1.0, 1.0, 0.012)
		for i in range(25):
			var cx = rng.randf_range(bs, r.size.x - bs)
			var cy = rng.randf_range(bs, r.size.y - bs)
			var rad = rng.randf_range(30, 90)
			var pts = PackedVector2Array()
			var a_c = rng.randf_range(0.6, 1.8) # 拉伸实现横向/纵向擦抹轨迹
			for ang in range(0, 360, 30):
				var rad_ang = deg_to_rad(ang)
				pts.append(Vector2(cx + cos(rad_ang) * rad * a_c, cy + sin(rad_ang) * rad))
			draw_polygon(pts, PackedColorArray([dust_c]))
			
		# 5. 零散手绘涂鸦底纹 (增添黑板写擦过后的真实生活感)
		var dc = Color(1.0, 1.0, 1.0, 0.09)
		
		# 涂鸦 A：右上角的弹簧线圈物理练习图示
		var p1 = PackedVector2Array()
		var cx1 = r.size.x * 0.70
		var cy1 = r.size.y * 0.22
		for a in range(0, 1200, 15):
			var rr = deg_to_rad(a)
			p1.append(Vector2(cx1 + a * 0.09 + cos(rr)*16, cy1 + sin(rr)*26))
		if p1.size() >= 2: draw_polyline(p1, dc, 2.5)
		
		# 涂鸦 B：左下角微积分积分号与乱涂变量
		var p2 = PackedVector2Array()
		var cx2 = r.size.x * 0.14
		var cy2 = r.size.y * 0.78
		p2.append(Vector2(cx2+5, cy2-35))
		p2.append(Vector2(cx2-12, cy2+20))
		p2.append(Vector2(cx2-5, cy2+28))
		p2.append(Vector2(cx2+45, cy2-25)) # 夸张提笔飞线
		p2.append(Vector2(cx2+40, cy2-30))
		p2.append(Vector2(cx2+25, cy2+8))
		draw_polyline(p2, dc, 3.0)
		draw_line(Vector2(cx2+60, cy2-8), Vector2(cx2+80, cy2-8), dc, 2.5)
		draw_line(Vector2(cx2+60, cy2+2), Vector2(cx2+80, cy2+2), dc, 2.5)
		draw_line(Vector2(cx2+100, cy2-15), Vector2(cx2+120, cy2+5), dc, 2.5)
		draw_line(Vector2(cx2+120, cy2-15), Vector2(cx2+100, cy2+5), dc, 2.5)

		# 涂鸦 C：右下方的井字棋残局
		var tl = Vector2(r.size.x * 0.65, r.size.y * 0.78)
		var l3 = 35.0
		var p3_lines = [
			[Vector2(-l3, -12), Vector2(l3, -8)], [Vector2(-l3, 16), Vector2(l3, 18)],
			[Vector2(-15, -l3), Vector2(-12, l3)], [Vector2(16, -l3), Vector2(18, l3)]
		]
		for L in p3_lines: draw_line(tl + L[0], tl + L[1], dc, 3.0)
		var p3c = PackedVector2Array() # 画个大 O
		for a in range(0, 380, 20): p3c.append(tl + Vector2(25, -22) + Vector2(cos(deg_to_rad(a))*12, sin(deg_to_rad(a))*14))
		draw_polyline(p3c, dc, 2.5)
		# 画个大 X 飞出框
		draw_line(tl + Vector2(-35, -35), tl + Vector2(-5, -5), dc, 2.5)
		draw_line(tl + Vector2(-10, -35), tl + Vector2(-40, -5), dc, 2.5)
			
		# 6. 手绘感标题栏粉笔横线
		var th = _t.title_bar_height
		var ty = bs + th
		var chalk_c = Color(_t.tx_primary, 0.5)
		draw_line(Vector2(bs + 10, ty - 1.5), Vector2(r.size.x - bs - 10, ty + 1.5), chalk_c, 2.0)
		draw_line(Vector2(bs + 8, ty + 1.0), Vector2(r.size.x - bs - 12, ty - 1.0), chalk_c, 1.5)
		draw_line(Vector2(bs + 12, ty), Vector2(r.size.x - bs - 8, ty + 0.5), chalk_c, 1.0)

func create_panel() -> PanelContainer:
	return _BlackboardPanel.new(self)

# ═══════════════════════════════════════════════
#  组件覆写
# ═══════════════════════════════════════════════

# 进度指示器：粉笔手绘进度条 (全 _draw 自绘)
class _ChalkProgress extends Control:
	var _t: TodoThemeBase
	var _done: int = 0
	var _total: int = 0
	var _rng := RandomNumberGenerator.new()

	func _init(t: TodoThemeBase) -> void:
		_t = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 26)

	func update(done: int, total: int) -> void:
		_done = done; _total = total
		queue_redraw()

	func _draw() -> void:
		if _total <= 0: return
		var all_done = _done >= _total
		var chalk = _t.accent if all_done else Color(_t.tx_primary, 0.8)
		var ratio = float(_done) / float(_total)

		var pad_x := 20.0
		var bar_h := 14.0
		var bar_y := (size.y - bar_h) * 0.5
		var bar_w := size.x - pad_x * 2
		var bx := pad_x
		var by := bar_y
		_rng.seed = 99

		# ── 手绘矩形边框 (多层歪斜线条模拟粗粉笔) ──
		for layer in range(3):
			var a = [0.2, 0.35, 0.55][layer]
			var w = [2.5, 2.0, 1.5][layer]
			var lc = Color(chalk, a)
			# 上边
			_chalk_line(Vector2(bx - 2, by), Vector2(bx + bar_w + 2, by), lc, w)
			# 下边
			_chalk_line(Vector2(bx - 1, by + bar_h), Vector2(bx + bar_w + 1, by + bar_h), lc, w)
			# 左边
			_chalk_line(Vector2(bx, by - 1), Vector2(bx, by + bar_h + 1), lc, w)
			# 右边
			_chalk_line(Vector2(bx + bar_w, by - 1), Vector2(bx + bar_w, by + bar_h + 1), lc, w)

		# ── 填充区域：对角线粉笔笔触 ──
		var fill_w = bar_w * ratio
		if fill_w > 2:
			var stripe_sp := 5.0
			var x = bx + 2
			while x < bx + fill_w - 1:
				var jx = _rng.randf_range(-1.0, 1.0)
				var jy = _rng.randf_range(-0.5, 0.5)
				var sa = _rng.randf_range(0.25, 0.5)
				draw_line(
					Vector2(x + jx, by + 2 + jy),
					Vector2(x + 3 + jx, by + bar_h - 2 + jy),
					Color(chalk, sa), _rng.randf_range(1.5, 2.5)
				)
				x += stripe_sp

			# 底色填充 (低透明度整体涂抹)
			draw_rect(Rect2(bx + 1, by + 1, fill_w - 2, bar_h - 2), Color(chalk, 0.08))

		# ── 粉笔粉末 (边框和填充边缘散落) ──
		_rng.seed = 234
		for i in range(20):
			var px = _rng.randf_range(bx - 6, bx + bar_w + 6)
			var py = _rng.randf_range(by - 5, by + bar_h + 5)
			# 粉末集中在边框附近
			if absf(py - by) < 4 or absf(py - by - bar_h) < 4 or absf(px - bx) < 4 or absf(px - bx - bar_w) < 4:
				var pr = _rng.randf_range(0.5, 1.8)
				draw_circle(Vector2(px, py), pr, Color(chalk, _rng.randf_range(0.15, 0.4)))

		# ── 文字 ──
		var font = ThemeDB.fallback_font
		var fs := 12
		var text = "%d / %d" % [_done, _total]
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var tx = (size.x - text_size.x) * 0.5
		var ty = (size.y + text_size.y * 0.55) * 0.5

		# 板擦清理区：用多个椭圆叠加模拟擦拭痕迹，边缘自然模糊
		var cx = size.x * 0.5
		var cy = ty - text_size.y * 0.3
		var board_c = Color(_t.bg_main, 0.7)
		_rng.seed = 333
		for i in range(5):
			var ex = cx + _rng.randf_range(-8, 8)
			var ey = cy + _rng.randf_range(-2, 2)
			var rx = text_size.x * 0.5 + _rng.randf_range(4, 14)
			var ry = _rng.randf_range(6, 10)
			var pts = PackedVector2Array()
			for ang in range(0, 360, 15):
				var rad = deg_to_rad(ang)
				pts.append(Vector2(ex + cos(rad) * rx, ey + sin(rad) * ry))
			draw_polygon(pts, PackedColorArray([board_c]))

		# 粉笔多层叠绘
		_rng.seed = 55
		for i in range(3):
			var ox = _rng.randf_range(-1.2, 1.2)
			var oy = _rng.randf_range(-1.0, 1.0)
			draw_string(font, Vector2(tx + ox, ty + oy), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(chalk, 0.25))
		draw_string(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, chalk)

		# 文字周围粉末
		_rng.seed = 88
		for i in range(6):
			var px = tx + _rng.randf_range(-4, text_size.x + 4)
			var py = ty + _rng.randf_range(-text_size.y, 4)
			draw_circle(Vector2(px, py), _rng.randf_range(0.4, 1.0), Color(chalk, _rng.randf_range(0.15, 0.35)))

	## 手抖粉笔线：起终点加随机偏移，模拟手画
	func _chalk_line(from: Vector2, to: Vector2, c: Color, w: float) -> void:
		var jf = Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 1.0))
		var jt = Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 1.0))
		draw_line(from + jf, to + jt, c, w)

func make_progress_indicator() -> Control:
	return _ChalkProgress.new(self)

func update_progress_indicator(ctrl: Control, done: int, total: int) -> void:
	if not ctrl: return
	if ctrl.has_method("update"):
		ctrl.update(done, total)

# 复选框：模拟手绘的方块，打勾通过_draw回调绘制突破边界的粗糙粉笔线
func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(1)
	s.bg_color = Color.TRANSPARENT
	
	if is_done:
		# 框本身的痕迹变淡
		s.set_border_width_all(1)
		s.border_color = Color(tx_primary, 0.3)
		
		# 使用 signal 回调在按钮节点上"手绘"突破方框的对勾
		var chalk_c = accent
		btn.draw.connect(func():
			# 突破底线起笔，往右上角疯狂飞出
			var p1 = Vector2(-2, 14)
			var p2 = Vector2(10, 28) # 谷底突破按钮边界 (高度通常24)
			var p3 = Vector2(36, -10) # 终点飞出右上角
			
			# 主干线 (粗线条)
			btn.draw_line(p1, p2, chalk_c, 3.0)
			btn.draw_line(p2, p3, chalk_c, 4.0)
			
			# 粉笔粉末感：旁边重叠的轻虚线和散落的粉末点
			btn.draw_line(p1 + Vector2(1, -1), p2 + Vector2(1, -1), Color(chalk_c, 0.5), 1.0)
			btn.draw_line(p2 + Vector2(2, 0), p3 + Vector2(1, -2), Color(chalk_c, 0.6), 1.5)
			
			# 散落粉笔末 (随机几个圆点)
			btn.draw_circle(p2 + Vector2(-2, 4), 1.2, Color(chalk_c, 0.8))
			btn.draw_circle(p3 + Vector2(2, 2), 1.5, Color(chalk_c, 0.6))
			btn.draw_circle(p3 + Vector2(4, -1), 0.8, Color(chalk_c, 0.4))
			btn.draw_circle(Vector2(18, 8), 1.0, Color(chalk_c, 0.3))
		)
	else:
		s.set_border_width_all(2)
		s.border_color = Color(tx_primary, 0.5)
		
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	if is_done: 
		h.bg_color = Color(accent, 0.05)
	else: 
		h.bg_color = Color(tx_primary, 0.05)
		h.border_color = tx_primary
		
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

# 卡片样式：纯透明，选中时用黄粉笔在底部生硬地划一条下划线作为指示
func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(card_corner)
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	s.bg_color = Color.TRANSPARENT
	
	if is_selected:
		s.border_color = bd_select
		# 极度不对称的粉笔涂鸦高亮感
		s.border_width_bottom = 3
		s.border_width_left = 2
		s.border_width_top = 0
		s.border_width_right = 0
	elif is_done:
		s.bg_color = Color(tx_primary, 0.04) # 擦出一点白灰
		s.set_border_width_all(0)
	else:
		s.set_border_width_all(0)
		
	return s

# 按钮做成单纯的边框涂鸦，取消实心填充背景底色，模拟仅仅画个圈框起来
func _chalk_btn(text: String, c: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", c)
	btn.add_theme_color_override("font_hover_color", c.lightened(0.25))
	btn.flat = false
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.border_color = Color(c, 0.6)
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 4; s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color(c, 0.15)
	h.border_color = c
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_add_button(text: String) -> Button:
	return _chalk_btn(text, tx_primary)

func make_close_button(text: String) -> Button:
	var btn = _chalk_btn(text, danger)
	btn.custom_minimum_size.y = 28
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return btn

func make_theme_button(text: String) -> Button:
	return _chalk_btn(text, accent)

# 备忘录编辑区直接透明化融入黑板
func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s: 
		s.bg_color = Color.TRANSPARENT
		s.set_border_width_all(0)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f: 
		f.bg_color = Color(tx_primary, 0.05)
		f.set_border_width_all(1)
		f.border_color = Color(tx_primary, 0.25)

# 改写打钩完成的待办字体，让它在黑板上显得稍微变淡或像被抹掉一半
func apply_card_title_style(label: Label, is_done: bool, is_selected: bool) -> void:
	label.add_theme_font_size_override("font_size", item_font_size)
	if is_done: 
		# 半透明灰白色，就像残留的粉笔
		label.add_theme_color_override("font_color", Color(tx_primary, 0.35))
	elif is_selected: 
		label.add_theme_color_override("font_color", accent) # 选中变黄
	else: 
		label.add_theme_color_override("font_color", tx_primary)

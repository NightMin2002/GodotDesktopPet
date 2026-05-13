# blackboard_chalk.gd — 黑板与粉笔
# 怀旧木边框 + 残留擦痕 + 粉笔涂鸦体
class_name TodoThemeBlackboardChalk extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.18, 0.28, 0.22),   # base: 深哑光墨绿色黑板
		Color(0.96, 0.96, 0.92),   # text: 白粉笔
		Color(0.95, 0.90, 0.45),   # accent: 黄粉笔
		Color(0.90, 0.48, 0.45),   # danger: 红粉笔
		1.0,
		"blackboard"
	)
	
	card_corner = 2
	input_corner = 2
	list_spacing = 10
	checkbox_size_px = Vector2(24, 24)
	progress_block_px = Vector2(8, 8)
	
	# 修改面板边距为适应木边框厚度 (比常规主题增加 10px 的内边距)
	panel_margins = [30, 28, 30, 36]
	
	bg_card_sel = Color.TRANSPARENT
	bd_select = accent

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
		
		# 使用 signal 回调在按钮节点上“手绘”突破方框的对勾
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

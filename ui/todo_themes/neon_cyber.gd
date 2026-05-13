# neon_cyber.gd — 荧光赛博风
# 霓虹辉光 + 倒角多边形 + 极高对比
class_name TodoThemeNeonCyber extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.05, 0.04, 0.08),   # base: 极深暗紫/黑背景
		Color(0.96, 0.98, 1.0),    # text: 高对白
		Color(0.10, 0.95, 0.82),   # accent: 赛博荧光青 Cyan
		Color(0.95, 0.15, 0.45),   # danger: 霓虹粉 Pink
		0.94,                      # alpha
		"cyber"                    # border: 专属荧光多边形引擎
	)
	
	card_corner = 0
	input_corner = 0
	list_spacing = 10
	checkbox_size_px = Vector2(28, 22) # 稍微扁一点的长条形打勾框
	progress_block_px = Vector2(12, 6) # 粗短形进度块
	
	# 更暴力的选中高光
	bg_card_sel = Color(accent, 0.12)
	bd_select = accent

# 覆写卡片样式，纯黑色彩块+极细线
func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(card_corner)
	s.set_border_width_all(1)
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	
	if is_selected:
		s.bg_color = bg_card_sel
		s.border_color = bd_select
		s.border_width_left = 6    # 左侧厚重的高亮信号标
	elif is_done:
		s.bg_color = Color(0, 0, 0, 0.2)
		s.border_color = Color(tx_dim, 0.2)
	else:
		s.bg_color = Color(0, 0, 0, 0.4)
		s.border_color = Color(accent, 0.2)
	return s

# 统一提取赛博按钮生成器
func _cyber_btn(text: String, base_color: Color, pressed_offset: float = 0.2) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", base_color)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.flat = false
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color(base_color, 0.05); s.border_color = Color(base_color, 0.4)
	s.set_border_width_all(1); s.set_corner_radius_all(0)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 6; s.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color(base_color, 0.4); h.border_color = base_color
	# 强烈的顶部边框高光
	h.border_width_top = 3
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

# 覆写按钮组件
func make_add_button(text: String) -> Button:
	return _cyber_btn(text, accent)

func make_close_button(text: String) -> Button:
	var btn = _cyber_btn(text, danger)
	btn.custom_minimum_size.y = 28
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return btn

func make_delete_button(text: String) -> Button:
	return super.make_delete_button(text)

func make_theme_button(text: String) -> Button:
	var c = Color(accent_soft, 0.8)
	return _cyber_btn(text, c)

# 覆写复选框：完成时为高亮色块 + >> 机械确认符
func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(0); s.set_border_width_all(1)
	
	if is_done:
		btn.text = ">>"; btn.add_theme_font_size_override("font_size", 12)
		# 强制黑字，因为底色高亮
		btn.add_theme_color_override("font_color", Color(0,0,0, 0.8))
		s.bg_color = accent; s.border_color = accent
	else:
		btn.text = ""; btn.add_theme_font_size_override("font_size", 12)
		s.bg_color = Color(0,0,0, 0.5); s.border_color = Color(accent, 0.3)
		
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	if is_done: 
		h.bg_color = accent.lightened(0.25)
	else: 
		h.bg_color = Color(accent, 0.2); h.border_color = accent
		
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

# 覆写进度条样式 (偏方块)
func apply_progress_block_style(block: Panel) -> void:
	block.custom_minimum_size = progress_block_px
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0,0,0, 0.6); s.border_color = Color(accent, 0.3)
	s.set_border_width_all(1); s.set_corner_radius_all(0)
	block.add_theme_stylebox_override("panel", s)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE

# 重新控制编辑框风格 (去除所有圆润)
func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s: 
		s.set_corner_radius_all(0)
		s.bg_color = Color(0,0,0, 0.3)
		s.border_color = Color(accent, 0.15)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f: 
		f.set_corner_radius_all(0)
		f.bg_color = Color(0,0,0, 0.4)
		f.border_color = accent_soft

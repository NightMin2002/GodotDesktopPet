# paper_note.gd — 记事便笺风
# 泛黄信纸 + 圆润组件 + 钢笔蓝/批注红线
class_name TodoThemePaperNote extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.96, 0.94, 0.88),   # base: 泛黄的羊皮纸/信纸
		Color(0.12, 0.15, 0.20),   # text: 深墨黑
		Color(0.20, 0.45, 0.80),   # accent: 钢笔蓝
		Color(0.85, 0.25, 0.20),   # danger: 批注红
		1.0,                       # alpha: 实体纸张不透明
		"paper"                    # border: 纸质边框
	)
	
	card_corner = 6
	input_corner = 6
	list_spacing = 10
	checkbox_size_px = Vector2(24, 24)
	progress_block_px = Vector2(10, 10)
	progress_block_sp = 6
	
	# 自定义的字体厚度感知
	bg_card_sel = Color.TRANSPARENT
	bd_select = accent

# 用粗笔触圈起来的感觉作为选中态
func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(card_corner)
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	
	if is_selected:
		s.bg_color = bg_card_sel
		s.border_color = bd_select
		s.set_border_width_all(2) 
	elif is_done:
		s.bg_color = Color(0, 0, 0, 0.04)
		s.border_color = Color(0, 0, 0, 0.08)
		s.set_border_width_all(1)
	else:
		s.bg_color = Color(1, 1, 1, 0.5)
		s.border_color = Color(0, 0, 0, 0.1)
		s.set_border_width_all(1)
	return s

# 覆写复选框：改成圆溜溜的🔘
func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(12)  # 完全圆角
	s.set_border_width_all(2)
	
	if is_done:
		btn.text = "\u2713" # 对勾
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color.WHITE)
		s.bg_color = accent; s.border_color = accent.darkened(0.2)
	else:
		btn.text = ""
		btn.add_theme_font_size_override("font_size", 14)
		s.bg_color = Color(1, 1, 1, 0.6); s.border_color = bd_control
		
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	if is_done: h.bg_color = accent.lightened(0.12)
	else: h.bg_color = Color(1, 1, 1, 1.0); h.border_color = accent_soft
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn
	
# 将输入框去边框化，融入纸张本身背景
func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s: 
		s.bg_color = Color.TRANSPARENT
		s.set_border_width_all(0)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f: 
		f.bg_color = Color(1, 1, 1, 0.4) # 高亮时增加一点纸张涂白
		f.set_border_width_all(1); f.border_color = accent_soft

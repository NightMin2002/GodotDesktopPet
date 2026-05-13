# blueprint_draft.gd — 蓝图设计风
# 细线网格 + 极简蓝图 + 直角组件
class_name TodoThemeBlueprintDraft extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.08, 0.15, 0.28),   # base: 深海蓝图底色
		Color(0.95, 0.98, 1.0),    # text: 冰白
		Color(0.20, 0.65, 0.95),   # accent: 天蓝高亮
		Color(0.95, 0.35, 0.30),   # danger: 橘红警告
		0.98,                      # alpha: 极度不透明
		"blueprint"                # border: 蓝图定制风格
	)
	
	# 面板排版配置
	card_corner = 0
	input_corner = 0
	list_spacing = 8
	checkbox_size_px = Vector2(20, 20)
	progress_block_px = Vector2(10, 10)
	
	# 让选中背景呈现"底片"反色或高亮色块
	bg_card_sel = Color(accent, 0.15)
	bd_select = accent

# 覆写卡片样式，纯线框无背景填充(除选中和完成)
func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(card_corner)
	s.set_border_width_all(1)
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	
	if is_selected:
		s.bg_color = bg_card_sel
		s.border_color = bd_select
		s.border_width_left = 4
	elif is_done:
		s.bg_color = bg_card_done
		s.border_color = bd_card_done
	else:
		s.bg_color = Color.TRANSPARENT
		s.border_color = bd_light
	return s

# 覆写按钮：纯角直边、框线透明底
func make_add_button(text: String) -> Button:
	var btn = _build_pill_btn(text, Color.TRANSPARENT, Color(accent, 0.25), 14)
	var n = btn.get_theme_stylebox("normal") as StyleBoxFlat
	if n:
		n.set_corner_radius_all(0); n.set_border_width_all(1); n.border_color = accent
		n.bg_color = Color(accent, 0.05)
	var h = btn.get_theme_stylebox("hover") as StyleBoxFlat
	if h:
		h.set_corner_radius_all(0); h.set_border_width_all(1); h.border_color = accent.lightened(0.2)
	return btn

func make_close_button(text: String) -> Button:
	var btn = _build_pill_btn(text, Color.TRANSPARENT, Color(danger, 0.25), 13)
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	btn.custom_minimum_size.y = 28
	var n = btn.get_theme_stylebox("normal") as StyleBoxFlat
	if n: n.set_corner_radius_all(0); n.set_border_width_all(1); n.border_color = danger
	var h = btn.get_theme_stylebox("hover") as StyleBoxFlat
	if h: h.set_corner_radius_all(0); h.set_border_width_all(1); h.border_color = danger.lightened(0.2)
	return btn

func make_theme_button(text: String) -> Button:
	var btn = _build_pill_btn(text, Color.TRANSPARENT, Color(accent_soft, 0.25), 12)
	var n = btn.get_theme_stylebox("normal") as StyleBoxFlat
	if n: n.set_corner_radius_all(0); n.set_border_width_all(1); n.border_color = accent_soft
	var h = btn.get_theme_stylebox("hover") as StyleBoxFlat
	if h: h.set_corner_radius_all(0); h.set_border_width_all(1); h.border_color = accent_soft.lightened(0.2)
	return btn

# 覆写复选框：直角、大叉号
func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(0); s.set_border_width_all(1)
	
	if is_done:
		btn.text = "X"; btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", accent)
		s.bg_color = Color.TRANSPARENT; s.border_color = accent
	else:
		btn.text = ""; btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", tx_dim)
		s.bg_color = Color.TRANSPARENT; s.border_color = bd_control
		
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	if is_done: h.bg_color = Color(accent, 0.15)
	else: h.bg_color = Color(accent_soft, 0.15); h.border_color = accent_soft
	
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

# 覆写输入框：强制无背景（与蓝图本身更好融合）
func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s: s.bg_color = Color.TRANSPARENT; s.set_corner_radius_all(0)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f: f.bg_color = Color.TRANSPARENT; f.set_corner_radius_all(0)

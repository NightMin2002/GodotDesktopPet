# todo_theme_base.gd — 待办面板主题基类
# 种子色推算 + 布局参数 + 中性默认组件工厂
# 主题子类通过覆写工厂方法实现独立风格，基类提供"中性兜底"
class_name TodoThemeBase extends RefCounted

# ═══════════════════════════════════════════════
#  配色表 (由 _from_seeds 自动推算，也可手动覆盖)
# ═══════════════════════════════════════════════

var bg_main      := Color.GRAY
var bg_title     := Color.GRAY
var bg_card      := Color.GRAY
var bg_card_sel  := Color.GRAY
var bg_card_done := Color.GRAY
var bg_input     := Color.GRAY

var tx_primary   := Color.BLACK
var tx_secondary := Color.DARK_GRAY
var tx_dim       := Color.DIM_GRAY
var tx_done      := Color.DIM_GRAY
var tx_card      := Color.BLACK
var tx_note_edit := Color.BLACK
var tx_empty_icon:= Color.DIM_GRAY

var bd_light     := Color.DIM_GRAY
var bd_select    := Color.GREEN
var bd_card_done := Color.DIM_GRAY
var card_hover_bd:= Color.GREEN

var accent       := Color.GREEN
var accent_soft  := Color.GREEN
var danger       := Color.RED

var bg_control       := Color.LIGHT_GRAY
var bd_control       := Color.DIM_GRAY
var bg_control_hover := Color.LIGHT_GRAY

var btn_add_bg       := Color.GREEN
var btn_add_hover    := Color.GREEN
var btn_close_bg     := Color.DIM_GRAY
var btn_close_hover  := Color.RED
var btn_delete_fg    := Color.DIM_GRAY
var bg_btn_text      := Color.LIGHT_GRAY
var bd_btn_text      := Color.DIM_GRAY

var sep_color        := Color.DIM_GRAY
var vsep_color       := Color.DIM_GRAY
var scroll_hint_color:= Color.DIM_GRAY
var progress_unfilled:= Color.DIM_GRAY
var progress_bd      := Color.DIM_GRAY

# ═══════════════════════════════════════════════
#  布局参数
# ═══════════════════════════════════════════════

var panel_margins     := [20, 18, 20, 26]
var outer_spacing     := 12
var left_spacing      := 8
var right_spacing     := 10
var list_spacing      := 6
var col_ratio         := [1.0, 1.3]
var vsep_width        := 18
var bottom_pad        := 6

var title_font_size   := 20
var item_font_size    := 17
var note_font_size    := 16
var progress_font_size := 14
var badge_font_size   := 11

var checkbox_size_px  := Vector2(26, 26)
var progress_block_px := Vector2(8, 8)
var progress_block_sp := 3
var card_corner       := 4
var card_padding      := [12, 10, 10, 10]
var input_padding     := [14, 14, 12, 12]
var input_corner      := 4
var title_bar_height  := 56.0

# ═══════════════════════════════════════════════
#  种子色推算
# ═══════════════════════════════════════════════

func _from_seeds(p_base: Color, p_text: Color, p_accent: Color, p_danger: Color, p_alpha: float) -> void:
	var dark := p_base.v < 0.4

	# ── 背景 ──
	bg_main      = Color(p_base, p_alpha)
	bg_title     = _vshift(p_base, 0.05 if dark else -0.12, p_alpha * 0.9)
	bg_card      = _vshift(p_base, 0.06 if dark else 0.05, p_alpha * 0.67)
	bg_card_sel  = _vshift(p_base, 0.10 if dark else 0.08, p_alpha * 0.88)
	bg_card_done = _vshift(p_base, 0.02, p_alpha * 0.41)
	bg_input     = _vshift(p_base, 0.02 if dark else 0.12, p_alpha * 0.93)

	# ── 文字 ──
	tx_primary   = p_text
	tx_secondary = _tblend(p_text, p_base, 0.35, 0.8)
	tx_dim       = _tblend(p_text, p_base, 0.55, 0.55)
	tx_done      = _tblend(p_text, p_base, 0.55, 0.5)
	tx_card      = Color(p_text, 0.9)
	tx_note_edit = Color(p_text, 0.95)
	tx_empty_icon= Color(p_text, 0.25)

	# ── 边框 ──
	bd_light     = Color(p_text, 0.3)
	bd_select    = Color(p_accent, 0.6)
	bd_card_done = Color(p_text, 0.15)
	card_hover_bd= Color(p_accent, 0.35)

	# ── 强调 ──
	accent       = p_accent
	accent_soft  = Color(p_accent, 0.7)
	danger       = p_danger

	# ── 控件 ──
	bg_control       = _vshift(p_base, 0.05, 0.7)
	bd_control       = Color(p_text, 0.35)
	bg_control_hover = _vshift(p_base, 0.10, 0.9)

	# ── 按钮 ──
	btn_add_bg       = Color(p_accent.darkened(0.2), 0.85)
	btn_add_hover    = p_accent
	btn_close_bg     = Color(p_danger.darkened(0.35), 0.55)
	btn_close_hover  = Color(p_danger.darkened(0.10), 0.85)
	btn_delete_fg    = Color(p_danger, 0.4)
	bg_btn_text      = _vshift(p_base, 0.05 if dark else -0.05, 0.25)
	bd_btn_text      = Color(p_danger, 0.25)

	# ── 杂项 ──
	sep_color        = Color(p_text, 0.15)
	vsep_color       = Color(p_text, 0.18)
	scroll_hint_color= Color(p_text, 0.25)
	progress_unfilled= _vshift(p_base, 0.08, 0.35)
	progress_bd      = Color(p_text, 0.5)

func _vshift(c: Color, dv: float, a: float) -> Color:
	return Color.from_hsv(c.h, c.s, clampf(c.v + dv, 0.0, 1.0), a)

func _tblend(a: Color, b: Color, t: float, alpha: float) -> Color:
	var r = a.lerp(b, t)
	r.a = alpha
	return r

# ═══════════════════════════════════════════════
#  面板容器
# ═══════════════════════════════════════════════

## 创建面板容器。子类覆写此方法返回自定义边框面板。
func create_panel() -> PanelContainer:
	var p = PanelContainer.new()
	var s = StyleBoxFlat.new()
	s.bg_color = bg_main
	s.border_color = bd_light
	s.set_border_width_all(1)
	s.set_corner_radius_all(card_corner)
	p.add_theme_stylebox_override("panel", s)
	return p

## 响应 UI 主题色变化。有动态色需求的子类覆写。
func update_panel_hue(p: PanelContainer, hue: float) -> void:
	if p.has_method("set_ui_hue"):
		p.set_ui_hue(hue)
	p.queue_redraw()

# ═══════════════════════════════════════════════
#  组件工厂 — 中性默认实现
#  子类可覆写任意方法实现独立风格
# ═══════════════════════════════════════════════

func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(card_corner)
	s.set_border_width_all(1)
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	if is_selected:
		s.bg_color = bg_card_sel; s.border_color = bd_select
		s.border_width_left = 3
	elif is_done:
		s.bg_color = bg_card_done; s.border_color = bd_card_done
	else:
		s.bg_color = bg_card; s.border_color = bd_light
	return s

func make_card_hover_style(base: StyleBoxFlat) -> StyleBoxFlat:
	var hs = base.duplicate()
	hs.bg_color.a = minf(hs.bg_color.a + 0.15, 1.0)
	hs.border_color = card_hover_bd
	return hs

func make_add_button(text: String) -> Button:
	return _make_btn(text, bg_control, bd_control, tx_primary, accent_soft)

func make_close_button(text: String) -> Button:
	var btn = _make_btn(text, bg_control, bd_control, danger, btn_close_hover, 13)
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	btn.custom_minimum_size.y = 28
	return btn

func make_delete_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", btn_delete_fg)
	btn.add_theme_color_override("font_hover_color", danger)
	btn.flat = false
	btn.custom_minimum_size = Vector2(0, 24)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var s = StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.border_color = Color(bd_light, 0.3)
	s.set_border_width_all(1)
	s.set_corner_radius_all(card_corner)
	s.content_margin_left = 6; s.content_margin_right = 6
	s.content_margin_top = 3; s.content_margin_bottom = 3
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(danger, 0.1)
	h.border_color = Color(danger, 0.3)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_theme_button(text: String) -> Button:
	return _make_btn(text, bg_control, bd_control, accent_soft, accent, 12)

func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(card_corner)
	s.set_border_width_all(1)
	if is_done:
		btn.text = "\u2713"
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color.WHITE)
		s.bg_color = accent; s.border_color = accent.darkened(0.2)
	else:
		btn.text = ""
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", tx_dim)
		s.bg_color = bg_control; s.border_color = bd_control
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	if is_done:
		h.bg_color = accent.lightened(0.1)
	else:
		h.bg_color = bg_control_hover; h.border_color = accent_soft
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_separator() -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	var s = StyleBoxFlat.new()
	s.bg_color = sep_color; s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

func make_scroll_hint_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = scroll_hint_color; s.set_corner_radius_all(1)
	return s

# ═══════════════════════════════════════════════
#  样式应用
# ═══════════════════════════════════════════════

func apply_note_edit_style(edit: TextEdit) -> void:
	edit.add_theme_font_size_override("font_size", note_font_size)
	edit.add_theme_color_override("font_color", tx_note_edit)
	edit.add_theme_color_override("font_placeholder_color", tx_dim)
	var s = StyleBoxFlat.new()
	s.bg_color = bg_input; s.border_color = bd_light
	s.set_border_width_all(1); s.set_corner_radius_all(input_corner)
	s.content_margin_left = input_padding[0]; s.content_margin_right = input_padding[1]
	s.content_margin_top = input_padding[2]; s.content_margin_bottom = input_padding[3]
	edit.add_theme_stylebox_override("normal", s)
	var f = s.duplicate(); f.border_color = accent_soft
	edit.add_theme_stylebox_override("focus", f)

func apply_note_title_style(title: LineEdit) -> void:
	title.add_theme_font_size_override("font_size", title_font_size)
	title.add_theme_color_override("font_color", tx_primary)
	title.add_theme_color_override("font_placeholder_color", tx_dim)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT; s.set_border_width_all(0)
	s.content_margin_left = 2; s.content_margin_bottom = 4
	title.add_theme_stylebox_override("normal", s)
	var f = s.duplicate(); f.border_width_bottom = 2; f.border_color = accent_soft
	title.add_theme_stylebox_override("focus", f)

func apply_save_badge_style(badge: PanelContainer, label: Label) -> void:
	var s = StyleBoxFlat.new()
	s.bg_color = accent; s.set_corner_radius_all(8)
	s.content_margin_left = 8; s.content_margin_right = 8
	s.content_margin_top = 2; s.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", s)
	label.add_theme_font_size_override("font_size", badge_font_size)
	label.add_theme_color_override("font_color", Color.WHITE)

func apply_vsep_style(vsep: VSeparator) -> StyleBoxFlat:
	vsep.add_theme_constant_override("separation", vsep_width)
	var s = StyleBoxFlat.new()
	s.bg_color = vsep_color; s.set_content_margin_all(0)
	vsep.add_theme_stylebox_override("separator", s)
	return s

func apply_progress_block_style(block: Panel) -> void:
	block.custom_minimum_size = progress_block_px
	var s = StyleBoxFlat.new()
	s.bg_color = progress_unfilled; s.border_color = progress_bd
	s.set_border_width_all(1); s.set_corner_radius_all(0)
	block.add_theme_stylebox_override("panel", s)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_progress_block(block: Panel, is_filled: bool) -> void:
	var bs = block.get_theme_stylebox("panel") as StyleBoxFlat
	if bs: bs.bg_color = accent if is_filled else progress_unfilled

func apply_card_title_style(label: Label, is_done: bool, is_selected: bool) -> void:
	label.add_theme_font_size_override("font_size", item_font_size)
	if is_done: label.add_theme_color_override("font_color", tx_done)
	elif is_selected: label.add_theme_color_override("font_color", tx_primary)
	else: label.add_theme_color_override("font_color", tx_card)

func apply_note_indicator_style(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", accent_soft)

func apply_empty_icon_style(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 36)
	l.add_theme_color_override("font_color", tx_empty_icon)

func apply_empty_hint_style(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", tx_dim)

func apply_title_label_style(l: Label) -> void:
	l.add_theme_color_override("font_color", tx_primary)
	l.add_theme_font_size_override("font_size", title_font_size)

func apply_progress_label_style(l: Label) -> void:
	l.add_theme_font_size_override("font_size", progress_font_size)
	l.add_theme_color_override("font_color", tx_secondary)

func apply_progress_complete(l: Label, is_complete: bool) -> void:
	l.add_theme_color_override("font_color", accent if is_complete else tx_secondary)

# ═══════════════════════════════════════════════
#  辅助构建器 (子类可选调用，默认工厂不使用)
# ═══════════════════════════════════════════════

## 中性按钮工厂 — 默认工厂用此生成按钮
func _make_btn(text: String, bg: Color, border: Color, fg: Color, hover_fg: Color = Color.WHITE, font_size: int = 14) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", hover_fg)
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(1); s.set_corner_radius_all(card_corner)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 5; s.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(hover_fg, 0.15); h.border_color = hover_fg
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

## 胶囊按钮构建器 — 子类可选用
func _build_pill_btn(text: String, bg: Color, hover_bg: Color, font_size: int = 15) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = Color(bg.r + 0.08, bg.g + 0.08, bg.b + 0.08, 0.4)
	s.set_border_width_all(1); s.set_corner_radius_all(6)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 6; s.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = hover_bg; h.border_color = Color(hover_bg.r + 0.1, hover_bg.g + 0.1, hover_bg.b + 0.1, 0.6)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

## 文字按钮构建器 — 子类可选用
func _build_text_btn(text: String, normal_color: Color, hover_color: Color) -> Button:
	var btn = Button.new()
	btn.text = text; btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", normal_color)
	btn.add_theme_color_override("font_hover_color", hover_color)
	btn.flat = false; btn.custom_minimum_size = Vector2(0, 24)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var s = StyleBoxFlat.new()
	s.bg_color = bg_btn_text; s.border_color = bd_btn_text
	s.set_border_width_all(1); s.set_corner_radius_all(4)
	s.content_margin_left = 6; s.content_margin_right = 6
	s.content_margin_top = 3; s.content_margin_bottom = 3
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(hover_color.r, hover_color.g + 0.05, hover_color.b + 0.05, 0.15)
	h.border_color = Color(hover_color.r - 0.10, hover_color.g + 0.10, hover_color.b + 0.10, 0.4)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

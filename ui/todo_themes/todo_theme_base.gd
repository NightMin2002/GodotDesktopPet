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
var tx_on_accent := Color.WHITE
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

var badge_font_size   := 11

var checkbox_size_px  := Vector2(26, 26)
var card_corner       := 4
var card_padding      := [12, 10, 10, 10]
var input_padding     := [14, 14, 12, 12]
var input_corner      := 4
var title_bar_height  := 56.0
var scrollbar_width   := 14

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
	tx_on_accent = Color(0.1, 0.1, 0.1) if p_accent.get_luminance() > 0.6 else Color.WHITE
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

## 像素风进度条内嵌类
class _PixelProgressBar extends Control:
	var _t: TodoThemeBase
	var _done: int = 0
	var _total: int = 0
	var _display_ratio: float = 0.0
	var _target_ratio: float = 0.0

	func _init(t: TodoThemeBase) -> void:
		_t = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 18)

	func _process(delta: float) -> void:
		if absf(_display_ratio - _target_ratio) > 0.001:
			_display_ratio = lerpf(_display_ratio, _target_ratio, delta * 8.0)
			queue_redraw()
		elif _display_ratio != _target_ratio:
			_display_ratio = _target_ratio
			queue_redraw()

	func update(done: int, total: int) -> void:
		_done = done; _total = total
		_target_ratio = float(done) / float(total) if total > 0 else 0.0
		queue_redraw()

	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		var bw := 2.0 # 像素边框宽度

		# 外框 (像素风双色边框)
		draw_rect(r, Color(_t.bd_light, 0.6), false, 1.0)
		draw_rect(r.grow(-1), Color(_t.bg_card, 0.3), false, 1.0)

		# 内部背景
		var inner = Rect2(r.position + Vector2(bw, bw), r.size - Vector2(bw * 2, bw * 2))
		draw_rect(inner, Color(_t.bg_main, 0.6))

		# 分段填充
		var seg_w := 6.0
		var gap := 2.0
		var fill_w = inner.size.x * _display_ratio
		var x = inner.position.x + 1
		var y = inner.position.y + 1
		var seg_h = inner.size.y - 2
		var all_done = _total > 0 and _done >= _total
		var fill_c = _t.accent if not all_done else _t.accent.lightened(0.15)

		while x + seg_w <= inner.position.x + 1 + fill_w:
			# 主体色块
			draw_rect(Rect2(x, y, seg_w, seg_h), fill_c)
			# 顶部高光线 (像素风立体感)
			draw_line(Vector2(x, y), Vector2(x + seg_w, y), Color(1, 1, 1, 0.25), 1.0)
			# 底部暗线
			draw_line(Vector2(x, y + seg_h - 1), Vector2(x + seg_w, y + seg_h - 1), Color(0, 0, 0, 0.2), 1.0)
			x += seg_w + gap

		# 尾部余量
		var remaining = fill_w - (x - inner.position.x - 1)
		if remaining > 1:
			draw_rect(Rect2(x, y, remaining, seg_h), fill_c)
			draw_line(Vector2(x, y), Vector2(x + remaining, y), Color(1, 1, 1, 0.25), 1.0)

		# 文字 (居中，带暗底色带)
		if _total > 0:
			var text = "%d / %d" % [_done, _total]
			var font = ThemeDB.fallback_font
			var fs := 12
			var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			var tx = r.position.x + (r.size.x - text_size.x) * 0.5
			var ty = r.position.y + (r.size.y + text_size.y * 0.6) * 0.5
			# 暗底色带
			var bd_rect = Rect2(tx - 4, inner.position.y, text_size.x + 8, inner.size.y)
			draw_rect(bd_rect, Color(0, 0, 0, 0.55))
			# 文字描边 (8方向1px像素描边)
			var outline_c = Color(0, 0, 0, 0.9)
			for ox in [-1, 0, 1]:
				for oy in [-1, 0, 1]:
					if ox == 0 and oy == 0: continue
					draw_string(font, Vector2(tx + ox, ty + oy), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline_c)
			# 文字本体
			var text_c = Color.WHITE if not all_done else _t.accent.lightened(0.4)
			draw_string(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_c)

## 创建进度指示器。子类覆写可完全自定义形态，返回 null 则不显示。
func make_progress_indicator() -> Control:
	return _PixelProgressBar.new(self)

## 更新进度指示器。子类如果覆写了 make，也需要覆写此方法。
func update_progress_indicator(ctrl: Control, done: int, total: int) -> void:
	if not ctrl: return
	if ctrl.has_method("update"):
		ctrl.update(done, total)


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
	btn.custom_minimum_size.y = 26
	for state in ["normal", "hover", "pressed"]:
		var s = btn.get_theme_stylebox(state) as StyleBoxFlat
		if s:
			s.content_margin_top = 3
			s.content_margin_bottom = 3
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
		btn.add_theme_color_override("font_color", tx_on_accent)
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
	label.add_theme_color_override("font_color", tx_on_accent)

func apply_vsep_style(vsep: VSeparator) -> StyleBoxFlat:
	vsep.add_theme_constant_override("separation", vsep_width)
	var s = StyleBoxFlat.new()
	s.bg_color = vsep_color; s.set_content_margin_all(0)
	vsep.add_theme_stylebox_override("separator", s)
	return s


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

# ═══════════════════════════════════════════════
#  自定义滚动条 (像素风默认)
# ═══════════════════════════════════════════════

class TodoScrollbar extends Control:
	var _t: TodoThemeBase
	var _scroll: ScrollContainer
	var _dragging := false
	var _drag_offset := 0.0

	func _init(t: TodoThemeBase) -> void:
		_t = t
		mouse_filter = MOUSE_FILTER_STOP
		custom_minimum_size.x = t.scrollbar_width

	func bind(sc: ScrollContainer) -> void:
		_scroll = sc
		_scroll.get_v_scroll_bar().value_changed.connect(func(_v): queue_redraw())

	func _get_track_rect() -> Rect2:
		var pad := 6.0
		return Rect2(0, pad, size.x, size.y - pad * 2)

	func _get_thumb_rect() -> Rect2:
		if not _scroll: return Rect2()
		var vbar = _scroll.get_v_scroll_bar()
		if vbar.max_value <= vbar.page: return Rect2()
		var track = _get_track_rect()
		var ratio = vbar.page / vbar.max_value
		var thumb_h = maxf(16.0, track.size.y * ratio)
		var usable = track.size.y - thumb_h
		var scroll_ratio = 0.0
		if vbar.max_value - vbar.page > 0:
			scroll_ratio = vbar.value / (vbar.max_value - vbar.page)
		var thumb_y = track.position.y + scroll_ratio * usable
		return Rect2(2, thumb_y, size.x - 4, thumb_h)

	func _can_scroll() -> bool:
		if not _scroll: return false
		var vbar = _scroll.get_v_scroll_bar()
		return vbar.max_value > vbar.page

	func _draw() -> void:
		if not _can_scroll(): return
		var track = _get_track_rect()
		var thumb = _get_thumb_rect()
		_draw_track(track)
		_draw_thumb(thumb)

	func _draw_track(track: Rect2) -> void:
		var c = Color(_t.tx_primary, 0.25)
		var cx = track.position.x + track.size.x * 0.5
		# 上端横线
		draw_line(Vector2(track.position.x + 2, track.position.y), Vector2(track.end.x - 2, track.position.y), c, 1.0)
		# 下端横线
		draw_line(Vector2(track.position.x + 2, track.end.y), Vector2(track.end.x - 2, track.end.y), c, 1.0)
		# 中间竖轨道
		draw_line(Vector2(cx, track.position.y), Vector2(cx, track.end.y), c, 1.0)

	func _draw_thumb(thumb: Rect2) -> void:
		var c = Color(_t.tx_primary, 0.45)
		var hover_c = Color(_t.tx_primary, 0.65)
		var fc = hover_c if _dragging else c
		draw_rect(thumb, fc)
		# 中间两条抓握纹
		var mid_y = thumb.position.y + thumb.size.y * 0.5
		if thumb.size.y > 24:
			draw_line(Vector2(thumb.position.x + 3, mid_y - 2), Vector2(thumb.end.x - 3, mid_y - 2), Color(_t.bg_main, 0.5), 1.0)
			draw_line(Vector2(thumb.position.x + 3, mid_y + 2), Vector2(thumb.end.x - 3, mid_y + 2), Color(_t.bg_main, 0.5), 1.0)

	func _gui_input(event: InputEvent) -> void:
		if not _can_scroll(): return
		var vbar = _scroll.get_v_scroll_bar()

		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					var thumb = _get_thumb_rect()
					if thumb.has_point(event.position):
						_dragging = true
						_drag_offset = event.position.y - thumb.position.y
					else:
						var track = _get_track_rect()
						var r = clampf((event.position.y - track.position.y) / track.size.y, 0.0, 1.0)
						vbar.value = r * (vbar.max_value - vbar.page)
				else:
					_dragging = false
				queue_redraw()
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				vbar.value -= vbar.page * 0.15
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				vbar.value += vbar.page * 0.15

		elif event is InputEventMouseMotion and _dragging:
			var track = _get_track_rect()
			var thumb_h = _get_thumb_rect().size.y
			var usable = track.size.y - thumb_h
			if usable > 0:
				var r = clampf((event.position.y - _drag_offset - track.position.y) / usable, 0.0, 1.0)
				vbar.value = r * (vbar.max_value - vbar.page)

func make_scrollbar() -> Control:
	return TodoScrollbar.new(self)

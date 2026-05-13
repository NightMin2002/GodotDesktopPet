# retro_handheld.gd — 复古掌机
# 厚重的塑料机壳、包含电源指示灯的边框、Zelda式的像素爱心进度条以及GB同款“菠菜绿”四色LCD屏幕
class_name TodoThemeRetroHandheld extends TodoThemeBase

var gb_screen := Color(0.61, 0.73, 0.06)
var gb_dark   := Color(0.06, 0.22, 0.06)
var gb_mid    := Color(0.19, 0.38, 0.19)
var gb_light  := Color(0.55, 0.67, 0.06)

func _init() -> void:
	_from_seeds(
		gb_screen,  # base: 屏幕底色
		gb_dark,    # text: 最深墨绿色（LCD墨色）
		gb_mid,     # accent: 中等绿色
		Color(0.67, 0.15, 0.31),  # danger: 不用在 UI，仅作为外壳发光参考
		1.0         # alpha
	)
	
	card_corner = 0
	input_corner = 0
	list_spacing = 4
	checkbox_size_px = Vector2(28, 28)
	
	# 外壳厚度: body=20, bezel_left=28, bezel_top=36, bezel_right=12, bezel_bot=20
	# 屏幕内置内边距: padding=12
	# panel_margins = [ 20+28+12, 20+36+12, 20+12+12, 20+20+12 ]
	panel_margins = [60, 68, 44, 52]

	bg_card = Color(gb_light)
	bg_card_sel = gb_dark  # 选中时经典反色
	bd_light = gb_mid

# ═══════════════════════════════════════════════
#  巨厚掌机机身面板
# ═══════════════════════════════════════════════

class _RetroPanel extends PanelContainer:
	var _t: TodoThemeBase
	var _time: float = 0.0
	
	func _init(t: TodoThemeBase) -> void:
		_t = t

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
		
		# 1. 绘制复古灰白塑料机壳主体 (Light Grey body)
		var body_c = Color(0.85, 0.85, 0.82)
		draw_rect(r, body_c)
		draw_line(Vector2(0, 0), Vector2(r.size.x, 0), Color.WHITE, 4.0)
		draw_line(Vector2(0, 0), Vector2(0, r.size.y), Color.WHITE, 4.0)
		draw_line(Vector2(0, r.size.y - 1), Vector2(r.size.x, r.size.y - 1), Color(0.5, 0.5, 0.5), 3.0)
		draw_line(Vector2(r.size.x - 1, 0), Vector2(r.size.x - 1, r.size.y), Color(0.5, 0.5, 0.5), 3.0)
		
		var top_groove_y := 8.0
		for i in range(2):
			draw_line(Vector2(20, top_groove_y + i*6), Vector2(r.size.x - 20, top_groove_y + i*6), Color(0.6, 0.6, 0.6), 2.0)
			draw_line(Vector2(20, top_groove_y + i*6 + 2), Vector2(r.size.x - 20, top_groove_y + i*6 + 2), Color.WHITE, 1.0)
			
		# 3. 超厚屏幕黑色边框带 (Bezel)
		var body_m = 20.0
		var bezel = Rect2(body_m, body_m, r.size.x - body_m*2, r.size.y - body_m*2)
		draw_rect(bezel, Color(0.25, 0.25, 0.28))
		draw_line(Vector2(bezel.position.x, bezel.position.y), Vector2(bezel.end.x, bezel.position.y), Color(0.1, 0.1, 0.1), 3.0)
		draw_line(Vector2(bezel.position.x, bezel.position.y), Vector2(bezel.position.x, bezel.end.y), Color(0.1, 0.1, 0.1), 3.0)

		var screen_m_l = 28.0
		var screen_m_t = 36.0
		var screen_m_r = 12.0
		var screen_m_b = 20.0
		var screen_r = Rect2(
			bezel.position.x + screen_m_l,
			bezel.position.y + screen_m_t,
			bezel.size.x - screen_m_l - screen_m_r,
			bezel.size.y - screen_m_t - screen_m_b
		)
		
		# 4. 指示灯红点 (位于左侧较宽的 Bezel 区域上)
		var led_x = bezel.position.x + 14
		var led_y = screen_r.position.y + 40
		var led_c = Color.RED
		if fmod(_time, 2.0) > 1.8: led_c = Color.DARK_RED 
		draw_circle(Vector2(led_x, led_y), 4.0, led_c)
		draw_circle(Vector2(led_x, led_y), 1.5, Color.WHITE) 
		var font = ThemeDB.fallback_font
		draw_string(font, Vector2(led_x - 12, led_y - 8), "BATTERY", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6,0.6,0.6))

		# DOT MATRIX UI
		draw_string(font, Vector2(screen_r.end.x - 76, bezel.position.y + 20), "DOT MATRIX UI", HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, Color(0.5,0.5,0.55))
		
		# 5. LCD屏幕
		draw_rect(screen_r, _t.bg_main)
		draw_line(screen_r.position, Vector2(screen_r.end.x, screen_r.position.y), Color(_t.bg_main.darkened(0.15)), 4.0)

		# 6. LCD栅格纹理
		var s_c = Color(0.0, 0.2, 0.0, 0.05)
		var sy = screen_r.position.y
		while sy < screen_r.end.y:
			draw_line(Vector2(screen_r.position.x, sy), Vector2(screen_r.end.x, sy), s_c, 1.0)
			sy += 4.0

func create_panel() -> PanelContainer:
	return _RetroPanel.new(self)

# ═══════════════════════════════════════════════
#  像素组件覆盖
# ═══════════════════════════════════════════════

class _8BitHearts extends Control:
	var _t: TodoThemeBase
	var _done: int = 0
	var _total: int = 0

	func _init(t: TodoThemeBase) -> void:
		_t = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 32)

	func update(done: int, total: int) -> void:
		_done = done; _total = total
		queue_redraw()

	func _draw() -> void:
		if _total <= 0: return
		
		var c_full = _t.tx_primary
		var c_empty = _t.bd_light 
		var c_bg = _t.bg_main

		var heart_pts = [
			[1,0],[2,0],[4,0],[5,0],
			[0,1],[1,1],[2,1],[3,1],[4,1],[5,1],[6,1],
			[0,2],[1,2],[2,2],[3,2],[4,2],[5,2],[6,2],
			[1,3],[2,3],[3,3],[4,3],[5,3],
			[2,4],[3,4],[4,4],
			[3,5]
		]
		
		var scale_size := 3.0
		var heart_w = 7 * scale_size
		var gap = 6.0
		
		var font = ThemeDB.fallback_font
		var text = "Lv %02d/%02d" % [_done, _total]
		var fs := 14
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs)
		
		var max_visible_hearts = max(1, int((size.x - 20 - text_size.x - 10) / (heart_w + gap)))
		var hearts_to_draw = min(_total, max_visible_hearts)
		
		var fill_count = _done
		if _total > max_visible_hearts:
			fill_count = int(round(hearts_to_draw * (float(_done) / float(_total))))

		var cx = 10.0
		var cy = (size.y - 6 * scale_size) * 0.5
		
		for i in range(hearts_to_draw):
			var is_done = (i < fill_count)
			if is_done:
				for p in heart_pts: draw_rect(Rect2(cx + p[0]*scale_size, cy + p[1]*scale_size, scale_size, scale_size), c_full)
			else:
				for p in heart_pts: draw_rect(Rect2(cx + p[0]*scale_size, cy + p[1]*scale_size, scale_size, scale_size), c_empty)
				var empty_inner = [
					[1,1],[2,1],[4,1],[5,1],
					[1,2],[2,2],[3,2],[4,2],[5,2],
					[2,3],[3,3],[4,3],
					[3,4]
				]
				for p in empty_inner: draw_rect(Rect2(cx + p[0]*scale_size, cy + p[1]*scale_size, scale_size, scale_size), c_bg)
			cx += heart_w + gap

		draw_string(font, Vector2(size.x - 10 - text_size.x, size.y * 0.5 + text_size.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c_full)
		
		var sep_y = size.y - 2
		draw_line(Vector2(2, sep_y), Vector2(size.x - 2, sep_y), _t.tx_primary, 3.0)

func make_progress_indicator() -> Control:
	return _8BitHearts.new(self)

func update_progress_indicator(ctrl: Control, done: int, total: int) -> void:
	if ctrl and ctrl.has_method("update"):
		ctrl.update(done, total)

func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(0)
	s.bg_color = bg_card
	
	if is_done:
		s.set_border_width_all(3)
		s.border_color = tx_primary
		btn.draw.connect(func():
			# 画个大交叉作为完成符号
			var d = 6.0
			btn.draw_line(Vector2(d, d), Vector2(btn.size.x - d, btn.size.y - d), tx_primary, 3.0)
			btn.draw_line(Vector2(btn.size.x - d, d), Vector2(d, btn.size.y - d), tx_primary, 3.0)
		)
	else:
		s.set_border_width_all(2)
		s.border_color = tx_primary
		
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = tx_primary
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(0) # 全直角复古
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	s.set_border_width_all(2)
	
	if is_selected:
		s.bg_color = tx_primary
		s.border_color = tx_primary
		s.border_width_left = 6
	elif is_done:
		s.bg_color = bg_main
		s.border_color = gb_dark
	else:
		s.bg_color = bg_card
		s.border_color = tx_primary
		
	return s

# 创造液晶屏幕扁平按钮
func _lcd_btn(text: String, fill_bg: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", bg_main if fill_bg else tx_primary)
	btn.add_theme_color_override("font_hover_color", tx_primary if fill_bg else bg_main)
	btn.flat = false
	
	var s = StyleBoxFlat.new()
	s.bg_color = tx_primary if fill_bg else bg_main
	s.set_border_width_all(2)
	s.border_color = tx_primary
	s.set_corner_radius_all(0)
	s.content_margin_left = 8; s.content_margin_right = 8
	s.content_margin_top = 4; s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = bg_main if fill_bg else tx_primary
	h.border_color = tx_primary
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_add_button(text: String) -> Button:
	var btn = _lcd_btn(text, false)
	return btn

func make_close_button(text: String) -> Button:
	var btn = _lcd_btn("X CLOSE", true)
	btn.custom_minimum_size.y = 26
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return btn

func make_theme_button(text: String) -> Button:
	return _lcd_btn("SWITCH_THEME", false)

func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s:
		s.bg_color = bg_card
		s.set_border_width_all(2)
		s.border_color = tx_primary
		s.set_corner_radius_all(0)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f:
		f.bg_color = gb_screen
		f.set_border_width_all(3)
		f.border_color = tx_primary

func apply_card_title_style(label: Label, is_done: bool, is_selected: bool) -> void:
	label.add_theme_font_size_override("font_size", item_font_size)
	if is_selected:
		label.add_theme_color_override("font_color", bg_main) 
	elif is_done:
		label.add_theme_color_override("font_color", gb_mid)
	else:
		label.add_theme_color_override("font_color", tx_primary)

func apply_title_label_style(l: Label) -> void:
	l.add_theme_color_override("font_color", tx_primary)
	l.add_theme_font_size_override("font_size", title_font_size) 

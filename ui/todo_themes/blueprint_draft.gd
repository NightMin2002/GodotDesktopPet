# blueprint_draft.gd — 蓝图绘图板
# 经典的深海蓝底白色网格纸，包含建筑工程图纸的尺寸测量线、溢出线框等设计元素
class_name TodoThemeBlueprintDraft extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.04, 0.17, 0.28),   # base: 深海蓝/工程蓝图底色
		Color(0.92, 0.98, 1.00),   # text: 高亮白
		Color(0.35, 0.85, 0.98),   # accent: 制图专用明亮蓝
		Color(0.98, 0.40, 0.40),   # danger: 警示红
		1.0                        # alpha: 不透明
	)
	
	card_corner = 0
	input_corner = 0
	list_spacing = 8
	checkbox_size_px = Vector2(24, 24)
	panel_margins = [24, 24, 24, 28]

	# 自定义卡片背景
	bg_card = Color(0.02, 0.22, 0.35, 0.45)
	bg_card_sel = Color(accent, 0.12)
	bd_light = Color(1.0, 1.0, 1.0, 0.25)

# ═══════════════════════════════════════════════
#  蓝图边框与网格面板
# ═══════════════════════════════════════════════

class _BlueprintPanel extends PanelContainer:
	var _t: TodoThemeBase
	
	func _init(t: TodoThemeBase) -> void:
		_t = t

	func _ready() -> void:
		var s = StyleBoxFlat.new()
		s.bg_color = Color.TRANSPARENT
		add_theme_stylebox_override("panel", s)

	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		
		# 1. 绘制深蓝底色
		draw_rect(r, _t.bg_main)
		
		# 2. 绘制全屏背景网格
		var grid_size := 20.0
		var grid_c = Color(1.0, 1.0, 1.0, 0.06)
		var bold_c = Color(1.0, 1.0, 1.0, 0.15)
		
		# 横向网格线
		var y = 0.0
		var count = 0
		while y <= r.size.y:
			draw_line(Vector2(0, y), Vector2(r.size.x, y), bold_c if count % 5 == 0 else grid_c, 1.0)
			y += grid_size
			count += 1
			
		# 纵向网格线
		var x = 0.0
		count = 0
		while x <= r.size.x:
			draw_line(Vector2(x, 0), Vector2(x, r.size.y), bold_c if count % 5 == 0 else grid_c, 1.0)
			x += grid_size
			count += 1

		# 3. 边框：带外延的工程线条 (建筑手绘溢出感)
		# 实际上在CAD制图里，框线可能会在角处交叉并延伸一点点出去
		var bd_c = Color(1, 1, 1, 0.6)
		var m := 8.0 # 边框距离边缘距离
		var ext := 12.0 # 溢出长度
		
		# 上
		draw_line(Vector2(m - ext, m), Vector2(r.size.x - m + ext, m), bd_c, 1.5)
		# 下
		draw_line(Vector2(m - ext, r.size.y - m), Vector2(r.size.x - m + ext, r.size.y - m), bd_c, 1.5)
		# 左
		draw_line(Vector2(m, m - ext), Vector2(m, r.size.y - m + ext), bd_c, 1.5)
		# 右
		draw_line(Vector2(r.size.x - m, m - ext), Vector2(r.size.x - m, r.size.y - m + ext), bd_c, 1.5)

		# 4. 标题栏区域划分 (用极细的横线区隔)
		var th := _t.title_bar_height
		draw_line(Vector2(m, th), Vector2(r.size.x - m, th), Color(_t.accent, 0.4), 1.0)
		draw_rect(Rect2(m + 1, m + 1, r.size.x - m * 2 - 2, th - m - 1), Color(_t.bg_title, 0.6))

func create_panel() -> PanelContainer:
	return _BlueprintPanel.new(self)

# ═══════════════════════════════════════════════
#  组件覆盖：制图风格
# ═══════════════════════════════════════════════

# 进度条：尺寸标注线样式
class _BlueprintProgress extends Control:
	var _t: TodoThemeBase
	var _done: int = 0
	var _total: int = 0

	func _init(t: TodoThemeBase) -> void:
		_t = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 30)

	func update(done: int, total: int) -> void:
		_done = done; _total = total
		queue_redraw()

	func _draw() -> void:
		if _total <= 0: return
		
		var pad_x := 12.0
		var bar_y := size.y * 0.5 + 4
		var bar_w := size.x - pad_x * 2
		var bx = pad_x
		var by = bar_y
		
		var ratio = float(_done) / float(_total)
		var fill_w = bar_w * ratio
		
		# 1. 结构横线
		draw_line(Vector2(bx, by), Vector2(bx + bar_w, by), Color(_t.bd_light, 0.5), 1.0)
		
		# 2. 进度实线
		if fill_w > 0:
			draw_line(Vector2(bx, by), Vector2(bx + fill_w, by), _t.accent, 2.0)
			
		# 3. 端点标志：建筑制图特有的对角斜线标志 (Tick mark)
		_draw_arch_tick(Vector2(bx, by), _t.accent if _done > 0 else Color(_t.bd_light, 0.8))
		_draw_arch_tick(Vector2(bx + bar_w, by), Color(_t.bd_light, 0.8))
		
		if fill_w > 0 and fill_w < bar_w:
			_draw_arch_tick(Vector2(bx + fill_w, by), _t.accent)
			
		# 4. 中间文字标注
		var font = ThemeDB.fallback_font
		var fs := 12
		var text = "DONE: %d / %d" % [_done, _total]
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		
		# 截断文字底部的线条（画个底色矩形把线条盖住，类似中心文字居中标注线的效果）
		var tx = bx + (bar_w - text_size.x) * 0.5
		var ty = by + text_size.y * 0.35
		# 把中间的线遮一下，使其有"测量数字卡在线中间"的感觉
		draw_rect(Rect2(tx - 6, ty - text_size.y, text_size.x + 12, text_size.y + 2), _t.bg_main)
		draw_string(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _t.tx_primary)

	func _draw_arch_tick(pos: Vector2, c: Color) -> void:
		var s := 5.0
		draw_line(pos + Vector2(-s, s), pos + Vector2(s, -s), c, 2.0)

func make_progress_indicator() -> Control:
	return _BlueprintProgress.new(self)

func update_progress_indicator(ctrl: Control, done: int, total: int) -> void:
	if ctrl and ctrl.has_method("update"):
		ctrl.update(done, total)

func make_checkbox(is_done: bool) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = checkbox_size_px
	btn.flat = false
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(0)
	
	if is_done:
		btn.text = ""
		s.bg_color = Color(accent, 0.1)
		s.border_color = accent
		s.set_border_width_all(1)
		btn.draw.connect(func():
			var center = btn.size * 0.5
			var hr = min(btn.size.x, btn.size.y) * 0.5 - 4
			# 画个由于手绘涂抹感，稍微溢出并且十字相交的废除线
			var ext = 2
			btn.draw_line(center + Vector2(-hr-ext, -hr-ext), center + Vector2(hr+ext, hr+ext), accent, 2.0)
			btn.draw_line(center + Vector2(-hr-ext, hr+ext), center + Vector2(hr+ext, -hr-ext), accent, 2.0)
		)
	else:
		btn.text = ""
		s.bg_color = Color.TRANSPARENT
		s.border_color = bd_light
		s.set_border_width_all(1)
		# 给空框增加四角的定位延伸点
		btn.draw.connect(func():
			var c = Color(1.0, 1.0, 1.0, 0.6)
			var m = 4.0
			var b = btn.size
			btn.draw_line(Vector2(0, 0), Vector2(-m, 0), c)
			btn.draw_line(Vector2(0, 0), Vector2(0, -m), c)
			btn.draw_line(Vector2(b.x, 0), Vector2(b.x+m, 0), c)
			btn.draw_line(Vector2(b.x, 0), Vector2(b.x, -m), c)
			btn.draw_line(Vector2(0, b.y), Vector2(-m, b.y), c)
			btn.draw_line(Vector2(0, b.y), Vector2(0, b.y+m), c)
			btn.draw_line(Vector2(b.x, b.y), Vector2(b.x+m, b.y), c)
			btn.draw_line(Vector2(b.x, b.y), Vector2(b.x, b.y+m), c)
		)
		
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color(accent, 0.2)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(card_corner)
	s.content_margin_left = card_padding[0]; s.content_margin_right = card_padding[1]
	s.content_margin_top = card_padding[2]; s.content_margin_bottom = card_padding[3]
	
	s.set_border_width_all(1)
	
	if is_selected:
		s.bg_color = bg_card_sel
		s.border_color = bd_select
	elif is_done:
		s.bg_color = Color(1, 1, 1, 0.02)
		s.border_color = Color(bd_light, 0.15)
	else:
		s.bg_color = bg_card
		s.border_color = Color(bd_light, 0.4)
		
	return s

func _blueprint_btn(text: String, c: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", c)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.flat = false
	
	var s = StyleBoxFlat.new()
	s.bg_color = Color(c, 0.08)
	s.border_color = c
	s.set_border_width_all(1)
	s.set_corner_radius_all(0)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 4; s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	
	var h = s.duplicate()
	h.bg_color = Color(c, 0.3)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	return btn

func make_add_button(text: String) -> Button:
	var b = _blueprint_btn("+" + text.replace("+", "").strip_edges(), tx_primary)
	return b

func make_close_button(text: String) -> Button:
	var btn = _blueprint_btn("[ " + text + " ]", danger)
	btn.custom_minimum_size.y = 28
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return btn

func make_theme_button(text: String) -> Button:
	return _blueprint_btn(text, accent)

func apply_note_edit_style(edit: TextEdit) -> void:
	super.apply_note_edit_style(edit)
	var s = edit.get_theme_stylebox("normal") as StyleBoxFlat
	if s:
		s.bg_color = Color(1,1,1, 0.03)
		s.set_border_width_all(1)
		s.border_color = Color(1,1,1, 0.2)
	var f = edit.get_theme_stylebox("focus") as StyleBoxFlat
	if f:
		f.bg_color = Color(accent, 0.05)
		f.set_border_width_all(1)
		f.border_color = accent

func apply_card_title_style(label: Label, is_done: bool, is_selected: bool) -> void:
	label.add_theme_font_size_override("font_size", item_font_size)
	if is_done:
		label.add_theme_color_override("font_color", Color(tx_primary, 0.35))
	elif is_selected:
		label.add_theme_color_override("font_color", accent)
	else:
		label.add_theme_color_override("font_color", tx_primary)

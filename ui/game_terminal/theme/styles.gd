# game_terminal_styles.gd — 游戏终端主题代理管理器
class_name GameTerminalStyles

static var _current_theme: TerminalThemeBase = null
static var _current_theme_id: String = "retro"

static func _get_theme() -> TerminalThemeBase:
	if _current_theme == null:
		# 我们将默认使用复古风格，以保证向后兼容性
		_current_theme = load("res://ui/game_terminal/theme/theme_retro.gd").new()
	return _current_theme

static func get_current_theme_id() -> String:
	return _current_theme_id

static func toggle_theme() -> void:
	if _current_theme_id == "retro":
		_current_theme_id = "minimal"
		_current_theme = load("res://ui/game_terminal/theme/theme_minimal.gd").new()
	else:
		_current_theme_id = "retro"
		_current_theme = load("res://ui/game_terminal/theme/theme_retro.gd").new()
	EventBus.ui_theme_changed.emit(EventBus.ui_hue)

# ══════════════════════════════════════════════
#  代理色值
# ══════════════════════════════════════════════

static func accent() -> Color: return _get_theme().accent()
static func dim() -> Color: return _get_theme().dim()
static func bright() -> Color: return _get_theme().bright()
static func bg_deep() -> Color: return _get_theme().bg_deep()
static func border_base() -> Color: return _get_theme().border_base()
static func status_active() -> Color: return _get_theme().status_active()
static func status_warning() -> Color: return _get_theme().status_warning()

# ══════════════════════════════════════════════
#  代理 StyleBox 
# ══════════════════════════════════════════════

static func separator_style() -> StyleBoxFlat: return _get_theme().separator_style()
static func content_area_bg() -> StyleBoxFlat: return _get_theme().content_area_bg()
static func status_bar_bg() -> StyleBoxFlat: return _get_theme().status_bar_bg()
static func small_btn_normal() -> StyleBoxFlat: return _get_theme().small_btn_normal()
static func small_btn_hover() -> StyleBoxFlat: return _get_theme().small_btn_hover()

# ══════════════════════════════════════════════
#  工具 / Label 保留原生实现，因为它们依赖颜色
# ══════════════════════════════════════════════

static func dim_label(text: String, font_size: int = 14) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", dim())
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

static func make_label(text: String, font_size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

static func add_tech_brackets(control: Control, bracket_len: float = 8.0, inset: float = 0.0) -> void:
	# 强行避开旧闭包死绑：无论当前是什么状态，每次重绘必定请求最新主题。
	control.draw.connect(func():
		_get_theme().draw_tech_brackets(control, bracket_len, inset)
	)
	EventBus.ui_theme_changed.connect(func(_h): if is_instance_valid(control): control.queue_redraw())


# ══════════════════════════════════════════════
#  结算覆盖层依然作为独立工具方法
# ══════════════════════════════════════════════

static func create_result_overlay(btn_text: String, restart_cb: Callable) -> Dictionary:
	var overlay = PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.85)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(20)
	overlay.add_theme_stylebox_override("panel", s)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var lbl = Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(lbl)

	var btn = Button.new()
	btn.text = btn_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_stylebox_override("normal", small_btn_normal())
	btn.add_theme_stylebox_override("hover", small_btn_hover())
	btn.add_theme_stylebox_override("pressed", small_btn_hover())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.pressed.connect(restart_cb)
	vbox.add_child(btn)

	return { "overlay": overlay, "label": lbl, "btn": btn }

static func show_result_overlay(overlay: PanelContainer, label: Label, text: String, color: Color) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	overlay.visible = true

# styles.gd — 游戏终端主题代理管理器
# 所有终端 UI / 游戏代码通过本类的静态方法获取色值和 StyleBox
# 查询优先级: 游戏覆写层 > 当前终端主题 > 基类默认值
class_name GameTerminalStyles

# ══════════════════════════════════════════════
#  内部状态
# ══════════════════════════════════════════════

static var _current_theme: TerminalThemeBase = null
static var _current_theme_id: String = "minimal"
static var _game_override: GameThemeOverride = null

static func _get_theme() -> TerminalThemeBase:
	if _current_theme == null:
		_current_theme = load("res://ui/game_terminal/theme/theme_minimal.gd").new()
	return _current_theme

# ══════════════════════════════════════════════
#  终端主题切换 (骨架标题栏按钮调用)
# ══════════════════════════════════════════════

static func get_current_theme_id() -> String:
	return _current_theme_id

## 主题切换已移除，仅保留极简主题
static func toggle_theme() -> void:
	pass  # 只有一个主题，无需切换

# ══════════════════════════════════════════════
#  游戏专属主题覆写层
# ══════════════════════════════════════════════

## 进入游戏时推入覆写 (骨架自动调用)
static func push_game_override(ov: GameThemeOverride) -> void:
	_game_override = ov

## 退出游戏时弹出覆写 (骨架自动调用)
static func pop_game_override() -> void:
	_game_override = null

## 获取当前覆写实例 (游戏内访问专属扩展色值用)
## 用法: var ov = GameTerminalStyles.game_override()
##       if ov and ov.has_method("my_color"): var c = ov.my_color()
static func game_override() -> GameThemeOverride:
	return _game_override

# ══════════════════════════════════════════════
#  代理色值 — 覆写优先，回退到终端主题
# ══════════════════════════════════════════════

## 覆写解析: 游戏覆写层有同名方法且返回非 null 则使用，否则回退
static func _color(method: StringName) -> Color:
	if _game_override and _game_override.has_method(method):
		var v = _game_override.call(method)
		if v != null: return v
	return _get_theme().call(method)

static func accent() -> Color: return _color(&"accent")
static func dim() -> Color: return _color(&"dim")
static func bright() -> Color: return _color(&"bright")
static func bg_deep() -> Color: return _color(&"bg_deep")
static func border_base() -> Color: return _color(&"border_base")
static func status_active() -> Color: return _color(&"status_active")
static func status_warning() -> Color: return _color(&"status_warning")

# ══════════════════════════════════════════════
#  代理 StyleBox — 直通终端主题 (不经覆写层)
# ══════════════════════════════════════════════

static func separator_style() -> StyleBoxFlat: return _get_theme().separator_style()
static func content_area_bg() -> StyleBoxFlat: return _get_theme().content_area_bg()
static func status_bar_bg() -> StyleBoxFlat: return _get_theme().status_bar_bg()
static func small_btn_normal() -> StyleBoxFlat: return _get_theme().small_btn_normal()
static func small_btn_hover() -> StyleBoxFlat: return _get_theme().small_btn_hover()

# ── 扩展色值 (骨架专用，不经游戏覆写层) ──
static func status_danger() -> Color: return _get_theme().status_danger()
static func hint_color() -> Color: return _get_theme().hint_color()

# ── 扩展 StyleBox (骨架大厅/底栏) ──
static func preview_panel_bg() -> StyleBoxFlat: return _get_theme().preview_panel_bg()
static func list_item_normal() -> StyleBoxFlat: return _get_theme().list_item_normal()
static func list_item_selected() -> StyleBoxFlat: return _get_theme().list_item_selected()
static func lobby_btn_normal() -> StyleBoxFlat: return _get_theme().lobby_btn_normal()
static func lobby_btn_hover() -> StyleBoxFlat: return _get_theme().lobby_btn_hover()
static func footer_btn_normal() -> StyleBoxFlat: return _get_theme().footer_btn_normal()
static func footer_btn_hover() -> StyleBoxFlat: return _get_theme().footer_btn_hover()
static func footer_btn_color() -> Color: return _get_theme().footer_btn_color()
static func footer_btn_hover_color() -> Color: return _get_theme().footer_btn_hover_color()

# ══════════════════════════════════════════════
#  工具方法 — Label 工厂
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

# ══════════════════════════════════════════════
#  工具方法 — 四角包边
# ══════════════════════════════════════════════

static func add_tech_brackets(control: Control, bracket_len: float = 8.0, inset: float = 0.0) -> void:
	control.draw.connect(func():
		_get_theme().draw_tech_brackets(control, bracket_len, inset)
	)
	EventBus.ui_theme_changed.connect(func(_h):
		if is_instance_valid(control): control.queue_redraw()
	)

# ══════════════════════════════════════════════
#  工具方法 — 结算覆盖层
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

# profile_styles.gd — 装置档案共享样式工厂
# 提供统一的色值和 StyleBox，各模块按需调用
class_name ProfileStyles

# ── 色值 ──

static func accent() -> Color:
	return Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.9)

static func dim() -> Color:
	return Color(0.45, 0.55, 0.65, 0.55)

static func bright() -> Color:
	return Color(0.75, 0.85, 0.95, 0.9)

static func val_color() -> Color:
	return Color(0.65, 0.78, 0.92, 0.85)

# ── 通用 StyleBox ──

## 卡片容器 (游戏战绩卡片、信息区块)
static func card_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.14, 0.5)
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.2)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 10; s.content_margin_bottom = 10
	return s

## 小按钮 (等级控制 [-] [∝] [+])
static func small_btn_normal() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.13, 0.22, 0.7)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 3; s.content_margin_bottom = 3
	return s

static func small_btn_hover() -> StyleBoxFlat:
	var s = small_btn_normal()
	s.bg_color = Color(0.18, 0.22, 0.35, 0.8)
	return s

## 分隔线
static func separator_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.15)
	s.set_content_margin_all(0)
	return s

# ── 通用控件工厂 ──

## MOUSE_FILTER_IGNORE 的 Label
static func make_label(text: String, font_size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

## MOUSE_FILTER_PASS 的 ScrollContainer (Tab 专用)
static func make_tab_scroll() -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	return scroll

## MOUSE_FILTER_PASS 的 VBoxContainer (Tab 内容容器)
static func make_tab_vbox(separation: int = 10) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", separation)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	return vbox

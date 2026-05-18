# terminal_theme_base.gd — 游戏终端主题基类
# 定义终端全局主题的完整接口契约和中性默认实现
# 子类 (theme_retro / theme_minimal) 按需覆写各方法实现风格差异
class_name TerminalThemeBase
extends RefCounted

# ══════════════════════════════════════════════
#  边框渲染器
# ══════════════════════════════════════════════

## 返回对应外框渲染脚本 (extends Control, 自绘 _draw)
func get_frame_script() -> Script:
	return null  # 子类必须覆写

# ══════════════════════════════════════════════
#  色值 — 所有方法实时读取 EventBus.ui_hue
# ══════════════════════════════════════════════

## 主题强调色 (按钮高亮、选中指示等)
func accent() -> Color:
	return Color.from_hsv(EventBus.ui_hue, 0.6, 0.9)

## 低亮度/次要色 (描述文字、提示信息)
func dim() -> Color:
	return Color(0.40, 0.50, 0.60, 0.55)

## 高亮色 (标题、重点文字)
func bright() -> Color:
	return Color(0.85, 0.92, 1.0, 0.95)

## 深色背景
func bg_deep() -> Color:
	return Color(0.02, 0.03, 0.06, 0.96)

## 边框基色
func border_base() -> Color:
	return Color.from_hsv(EventBus.ui_hue, 0.45, 0.65, 0.4)

## 就绪/胜利状态色 (绿色系)
func status_active() -> Color:
	return Color.from_hsv(0.35, 0.5, 0.8, 0.9)

## 警告状态色 (琥珀色)
func status_warning() -> Color:
	return Color.from_hsv(0.12, 0.6, 0.9, 0.9)

# ══════════════════════════════════════════════
#  StyleBox — 骨架 UI 组件使用
# ══════════════════════════════════════════════

## 分隔线
func separator_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = border_base()
	s.set_content_margin_all(0)
	return s

## 内容区域背景
func content_area_bg() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.03, 0.06, 0.5)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(12)
	return s

## 底部状态栏背景
func status_bar_bg() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.05, 0.10, 0.4)
	s.set_corner_radius_all(0)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 4; s.content_margin_bottom = 4
	return s

## 小按钮 (正常态)
func small_btn_normal() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.18, 0.6)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.5, 0.3)
	s.set_corner_radius_all(0)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 3; s.content_margin_bottom = 3
	return s

## 小按钮 (悬浮态)
func small_btn_hover() -> StyleBoxFlat:
	var s = small_btn_normal()
	s.bg_color = Color(0.14, 0.18, 0.30, 0.7)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.5)
	return s

# ══════════════════════════════════════════════
#  装饰绘制 — 四角包边
# ══════════════════════════════════════════════

## 在控件四角绘制科技感包边 (L 形折线)
func draw_tech_brackets(control: Control, bracket_len: float = 8.0, inset: float = 0.0) -> void:
	var c = Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.8)
	var w = control.size.x
	var h = control.size.y
	var lw = 1.5
	var r = Rect2(Vector2(inset, inset), Vector2(w - inset * 2, h - inset * 2))
	# 四角 L 形折线
	control.draw_polyline(PackedVector2Array([
		r.position + Vector2(bracket_len, 0), r.position, r.position + Vector2(0, bracket_len)
	]), c, lw)
	control.draw_polyline(PackedVector2Array([
		Vector2(r.end.x - bracket_len, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + bracket_len)
	]), c, lw)
	control.draw_polyline(PackedVector2Array([
		Vector2(r.position.x, r.end.y - bracket_len), Vector2(r.position.x, r.end.y), Vector2(r.position.x + bracket_len, r.end.y)
	]), c, lw)
	control.draw_polyline(PackedVector2Array([
		Vector2(r.end.x, r.end.y - bracket_len), r.end, Vector2(r.end.x - bracket_len, r.end.y)
	]), c, lw)

# ══════════════════════════════════════════════
#  扩展色值 — 骨架 UI 专用
# ══════════════════════════════════════════════

## 失败/危险色 (结算败北、关闭按钮等)
func status_danger() -> Color:
	return Color(0.9, 0.35, 0.3, 0.9)

## 极淡提示色 (操作说明、游戏计数等)
func hint_color() -> Color:
	return Color(0.3, 0.4, 0.5, 0.3)

# ══════════════════════════════════════════════
#  扩展 StyleBox — 大厅布局
# ══════════════════════════════════════════════

## 右侧预览面板背景
func preview_panel_bg() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.025, 0.035, 0.06, 0.4)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.25, 0.4, 0.12)
	s.set_corner_radius_all(0)
	s.content_margin_left = 16; s.content_margin_right = 16
	s.content_margin_top = 12; s.content_margin_bottom = 12
	return s

## 列表条目 (默认态)
func list_item_normal() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.04, 0.08, 0.3)
	s.set_border_width_all(0)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.7, 0.0)
	s.set_corner_radius_all(0)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 7; s.content_margin_bottom = 7
	return s

## 列表条目 (选中态)
func list_item_selected() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.16, 0.6)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.4)
	s.set_corner_radius_all(0)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 7; s.content_margin_bottom = 7
	return s

## 大厅按钮 (正常态)
func lobby_btn_normal() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.06, 0.12, 0.4)
	s.set_border_width_all(1)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.2)
	s.set_corner_radius_all(0)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 4; s.content_margin_bottom = 4
	return s

## 大厅按钮 (悬浮态)
func lobby_btn_hover() -> StyleBoxFlat:
	var s = lobby_btn_normal()
	s.bg_color = Color(0.06, 0.08, 0.16, 0.6)
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.4)
	return s

## 底栏按钮 (正常态，暖色系)
func footer_btn_normal() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.08, 0.06, 0.3)
	s.set_corner_radius_all(0)
	s.set_border_width_all(1)
	s.border_color = Color(0.4, 0.3, 0.2, 0.2)
	s.content_margin_left = 8; s.content_margin_right = 8
	s.content_margin_top = 2; s.content_margin_bottom = 2
	return s

## 底栏按钮 (悬浮态)
func footer_btn_hover() -> StyleBoxFlat:
	var s = footer_btn_normal()
	s.bg_color = Color(0.15, 0.1, 0.08, 0.5)
	s.border_color = Color(0.6, 0.35, 0.25, 0.4)
	return s

## 底栏按钮文字色
func footer_btn_color() -> Color:
	return Color(0.6, 0.5, 0.4, 0.7)

## 底栏按钮悬浮文字色
func footer_btn_hover_color() -> Color:
	return Color(0.9, 0.5, 0.35, 1.0)

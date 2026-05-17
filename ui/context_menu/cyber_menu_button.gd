# cyber_menu_button.gd — 机械机能菜单按钮 (独立模块)
# 提供: 悬浮时左右 [ ] 装甲咬合框 + X轴光刃追踪
# 用法: var btn = CyberMenuButton.new()  或  btn.set_script(CyberMenuButton)
extends Button
class_name CyberMenuButton

var is_hovered: bool = false
var hover_t: float = 0.0

func _ready() -> void:
	clip_contents = false
	mouse_entered.connect(func():
		is_hovered = true
		set_process(true)
		queue_redraw()
	)
	mouse_exited.connect(func():
		is_hovered = false
		queue_redraw()
	)

func _process(delta: float) -> void:
	var needs_redraw = false
	if is_hovered:
		if hover_t < 1.0:
			hover_t = min(hover_t + delta * 8.0, 1.0)
		needs_redraw = true
	else:
		if hover_t > 0.0:
			hover_t = max(hover_t - delta * 6.0, 0.0)
			needs_redraw = true
		else:
			set_process(false)
	if needs_redraw:
		queue_redraw()

func _draw() -> void:
	if hover_t > 0.0:
		var ui_hue = EventBus.ui_hue
		var accent = Color.from_hsv(ui_hue, 0.5, 0.9, 0.85 * hover_t)
		var w = size.x
		var h = size.y
		
		var offset = 6.0 * (1.0 - hover_t) - 2.0
		var line_len = 3.0 + 3.0 * hover_t
		var th = 1.5
		
		# 左侧咬合 (形如 [ )
		draw_polyline(PackedVector2Array([
			Vector2(offset + line_len, offset),
			Vector2(offset, offset),
			Vector2(offset, h - offset),
			Vector2(offset + line_len, h - offset)
		]), accent, th)
		
		# 右侧咬合 (形如 ] )
		draw_polyline(PackedVector2Array([
			Vector2(w - offset - line_len, offset),
			Vector2(w - offset, offset),
			Vector2(w - offset, h - offset),
			Vector2(w - offset - line_len, h - offset)
		]), accent, th)
		
		if is_hovered:
			var mx = clamp(get_local_mouse_position().x, offset, w - offset)
			var blade_len = 12.0
			var x_start = clamp(mx - blade_len, offset, w - offset)
			var x_end = clamp(mx + blade_len, offset, w - offset)
			
			# X轴光刃 (必须和端点的 offset 对齐贴合上下沿，否则会有像素错位差)
			draw_line(Vector2(x_start, offset), Vector2(x_end, offset), accent, 2.0)
			draw_line(Vector2(x_start, h - offset), Vector2(x_end, h - offset), accent, 2.0)

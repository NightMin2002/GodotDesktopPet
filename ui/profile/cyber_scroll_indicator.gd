# cyber_scroll_indicator.gd — 超前设计的独立科幻滚动指示器
class_name CyberScrollIndicator extends Control

var target_control: Control
var _smooth_ratio: float = 0.0

func _init() -> void:
	custom_minimum_size.x = 42 # 预留左侧百分比数字与游标的空间
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _get_v_bar() -> VScrollBar:
	if is_instance_valid(target_control) and target_control.has_method("get_v_scroll_bar"):
		return target_control.get_v_scroll_bar()
	return null

func bind_scroll(ctrl: Control) -> void:
	target_control = ctrl
	var bar = _get_v_bar()
	if bar:
		bar.value_changed.connect(func(_v): queue_redraw())
		bar.changed.connect(func(): queue_redraw())
	set_process(true)

## 一行替换原生滚动条: 将目标控件包入 HBox + 科幻指示器
## 返回包装器 HBoxContainer, 已自动挂到原父级的同一位置
## 用法: var wrapper = CyberScrollIndicator.wrap(my_scroll_container)
static func wrap(target: Control) -> HBoxContainer:
	var wrapper = HBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var parent = target.get_parent()
	if parent:
		var idx = target.get_index()
		parent.remove_child(target)
		parent.add_child(wrapper)
		parent.move_child(wrapper, idx)

	wrapper.add_child(target)

	# 隐藏原生滚动条
	if target is ScrollContainer:
		target.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	elif target.has_method("get_v_scroll_bar"):
		target.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)

	# 挂载科幻指示器
	var indicator = CyberScrollIndicator.new()
	indicator.bind_scroll(target)
	wrapper.add_child(indicator)

	return wrapper

func _process(delta: float) -> void:
	var bar = _get_v_bar()
	if not bar: return
	
	var mx = bar.max_value - bar.page
	var ratio = 0.0
	if mx > 0.001:
		ratio = clampf(bar.value / mx, 0.0, 1.0)
	
	# 非等比例追踪的平滑插值，体现机械阻尼感
	if abs(_smooth_ratio - ratio) > 0.001:
		_smooth_ratio = lerpf(_smooth_ratio, ratio, 18.0 * delta)
		queue_redraw()

func _draw() -> void:
	var bar = _get_v_bar()
	if not bar or bar.max_value <= bar.page:
		return # 内容过少不需要滚动条时直接隐身
		
	var w = size.x
	var h = size.y
	var hue = EventBus.ui_hue
	
	# 对齐基准线：偏右侧
	var cx = w - 8.0 
	var pad = 10.0
	var track_h = h - pad * 2.0
	
	var dim_c = Color.from_hsv(hue, 0.4, 0.6, 0.2)
	var glow_c = Color.from_hsv(hue, 0.6, 0.95, 0.8)
	var high_c = Color.from_hsv(hue, 0.3, 1.0, 1.0)
	
	# === 1. 画背景雷达刻度轨道 ===
	var ticks = 24
	for i in range(ticks + 1):
		var ty = pad + (track_h / ticks) * i
		var is_major = (i % 6 == 0)
		var t_width = 5.0 if is_major else 2.0
		# 未滑过的地方是暗色，滑过的地方给一点极微弱的亮光
		var tick_c = dim_c
		if ty < pad + track_h * _smooth_ratio:
			tick_c = Color.from_hsv(hue, 0.5, 0.7, 0.4)
		draw_line(Vector2(cx, ty), Vector2(cx + t_width, ty), tick_c, 1.0)
	
	# 贯穿到底的主引线
	draw_line(Vector2(cx, pad), Vector2(cx, h - pad), dim_c, 1.0)
	
	# === 2. 高科技游标绘制 ===
	var cursor_y = pad + track_h * _smooth_ratio
	
	# 发光主瞄准三角 (◁)
	var pts = PackedVector2Array([
		Vector2(cx - 3, cursor_y),
		Vector2(cx - 9, cursor_y - 4),
		Vector2(cx - 9, cursor_y + 4)
	])
	draw_polygon(pts, PackedColorArray([glow_c]))
	# 高亮边框
	draw_polyline(PackedVector2Array([Vector2(cx - 9, cursor_y + 4), Vector2(cx - 3, cursor_y), Vector2(cx - 9, cursor_y - 4)]), high_c, 1.5)
	
	# 随动的拖尾扫描杆段
	draw_line(Vector2(cx, cursor_y - 12), Vector2(cx, cursor_y + 12), glow_c, 2.0)
	draw_line(Vector2(cx, cursor_y - 4), Vector2(cx, cursor_y + 4), high_c, 1.5) # 中心核心泛白
	
	# === 3. 微型百分比数据 ===
	var font = ThemeDB.fallback_font
	if font:
		var pct_val = clampf(_smooth_ratio * 100.0, 0, 100)
		var pct_str = "%02d%%" % int(pct_val)
		# 让数值随着滑动在游标旁边跳动
		draw_string(font, Vector2(0, cursor_y + 4), pct_str, HORIZONTAL_ALIGNMENT_RIGHT, cx - 14, 10, high_c)

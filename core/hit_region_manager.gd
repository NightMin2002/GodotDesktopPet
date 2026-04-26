# hit_region_manager.gd — DWM 鼠标穿透管理器 (从 main.gd 拆分)
# 职责: 收集宠物/UI 命中区域，通过 C# 层注册到 Windows DWM
# 拖拽/菜单打开时切换为全窗口可交互模式
extends Node

var _main: Node2D

# ── 穿透状态 ──
var is_dragging := false
var is_menu_open := false

# ── 限流与变化检测 ──
var _passthrough_timer: float = 0.0
var _last_circles: PackedFloat32Array = PackedFloat32Array()
var _last_rects: PackedFloat32Array = PackedFloat32Array()
const PASSTHROUGH_INTERVAL := 0.008  # ~120fps

func setup(main: Node2D) -> void:
	_main = main
	
	EventBus.drag_started.connect(_on_drag_started)
	EventBus.drag_ended.connect(_on_drag_ended)
	EventBus.context_menu_toggled.connect(_on_context_menu_toggled)

func _process(delta: float) -> void:
	if is_dragging or is_menu_open:
		return
	_passthrough_timer += delta
	if _passthrough_timer >= PASSTHROUGH_INTERVAL:
		_passthrough_timer = 0.0
		_update_hit_regions()

func _update_passthrough_state() -> void:
	if is_dragging or is_menu_open:
		for p in _main.pet_instances:
			if is_instance_valid(p):
				p.queue_redraw()
		RenderingServer.force_draw(false)
		if _main.win_manager and _main.win_manager.has_method("SetFullWindowHit"):
			_main.win_manager.call("SetFullWindowHit", true)
		else:
			var full := PackedVector2Array([
				Vector2.ZERO,
				Vector2(_main.boundary_size.x, 0),
				Vector2(_main.boundary_size.x, _main.boundary_size.y),
				Vector2(0, _main.boundary_size.y),
			])
			DisplayServer.window_set_mouse_passthrough(full)
	else:
		if _main.win_manager and _main.win_manager.has_method("SetFullWindowHit"):
			_main.win_manager.call("SetFullWindowHit", false)
		_last_circles = PackedFloat32Array()
		_last_rects = PackedFloat32Array()
		_update_hit_regions()

## 收集所有宠物/UI 元素的命中区域，传递给 C# 层
func _update_hit_regions() -> void:
	var circles := PackedFloat32Array()
	var rects := PackedFloat32Array()
	
	for p in _main.pet_instances:
		if not is_instance_valid(p):
			continue
		
		# 宠物本体: 精确圆形命中
		var pet_pos = p.global_position
		var pet_r = p.PET_RADIUS + 15.0
		circles.append(_q(pet_pos.x))
		circles.append(_q(pet_pos.y))
		circles.append(_q(pet_r))
		
		# ── 特效视觉保护: 拖影单个 AABB 包围盒 (矩形计算量极大低于椭圆，不会掉帧) ──
		if p.trail_enabled and p.trail_history.size() > 0:
			var min_x: float = pet_pos.x
			var min_y: float = pet_pos.y
			var max_x: float = pet_pos.x
			var max_y: float = pet_pos.y
			for trail_pos in p.trail_history:
				min_x = minf(min_x, trail_pos.x - p.PET_RADIUS)
				min_y = minf(min_y, trail_pos.y - p.PET_RADIUS)
				max_x = maxf(max_x, trail_pos.x + p.PET_RADIUS)
				max_y = maxf(max_y, trail_pos.y + p.PET_RADIUS)
			rects.append(_q(min_x - 5))
			rects.append(_q(min_y - 5))
			rects.append(_q(max_x - min_x + 10))
			rects.append(_q(max_y - min_y + 10))
			
		# ── 特效视觉保护: 冲击波单个 AABB 包围盒 ──
		for shock in p.shockwaves:
			if shock["alpha"] > 0.1:
				var s_pos = pet_pos + shock["local_pos"]
				var sr: float = shock["radius"] + 10.0
				rects.append(_q(s_pos.x - sr))
				rects.append(_q(s_pos.y - sr))
				rects.append(_q(sr * 2.0))
				rects.append(_q(sr * 2.0))
				
		# 全息时钟 HUD: 矩形
		if p.hud_clock_enabled and is_instance_valid(p.hud_clock_label) and p.hud_clock_label.visible:
			var clock_pos = p.hud_clock_label.global_position
			var clock_size = p.hud_clock_label.get_minimum_size()
			rects.append(_q(clock_pos.x - 5))
			rects.append(_q(clock_pos.y - 5))
			rects.append(_q(clock_size.x + 10))
			rects.append(_q(clock_size.y + 10))
		
		# 全局气泡覆盖层: 矩形
		if p.overlay_rect.size != Vector2.ZERO:
			var ov = p.overlay_rect
			rects.append(_q(ov.position.x))
			rects.append(_q(ov.position.y))
			rects.append(_q(ov.size.x))
			rects.append(_q(ov.size.y))
		
		# 本地定向气泡堆栈: 每个气泡独立矩形
		if p.has_method("get_local_bubble_rects"):
			for br in p.get_local_bubble_rects():
				rects.append(_q(br.position.x))
				rects.append(_q(br.position.y))
				rects.append(_q(br.size.x))
				rects.append(_q(br.size.y))
	
	# 变化检测: 栅格量化后只有显著变化才跨语言传递
	if circles == _last_circles and rects == _last_rects:
		return
	_last_circles = circles
	_last_rects = rects
	
	if _main.win_manager and _main.win_manager.has_method("UpdateHitRegions"):
		_main.win_manager.call("UpdateHitRegions", circles, rects)
	else:
		# 回退: Godot API (单多边形 AABB)
		if circles.size() >= 3:
			var min_x := circles[0] - circles[2]
			var min_y := circles[1] - circles[2]
			var max_x := circles[0] + circles[2]
			var max_y := circles[1] + circles[2]
			for i in range(0, circles.size(), 3):
				min_x = minf(min_x, circles[i] - circles[i+2])
				min_y = minf(min_y, circles[i+1] - circles[i+2])
				max_x = maxf(max_x, circles[i] + circles[i+2])
				max_y = maxf(max_y, circles[i+1] + circles[i+2])
			for i in range(0, rects.size(), 4):
				min_x = minf(min_x, rects[i])
				min_y = minf(min_y, rects[i+1])
				max_x = maxf(max_x, rects[i] + rects[i+2])
				max_y = maxf(max_y, rects[i+1] + rects[i+3])
			DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
				Vector2(min_x, min_y),
				Vector2(max_x, min_y),
				Vector2(max_x, max_y),
				Vector2(min_x, max_y),
			]))

## 4px 栅格量化: 减少亚像素抖动导致的无意义 SetWindowRgn 刷新
func _q(v: float) -> float:
	return float(int(v / 4.0) * 4)

func _on_drag_started() -> void:
	is_dragging = true
	_update_passthrough_state()

func _on_drag_ended() -> void:
	is_dragging = false
	_update_passthrough_state()

func _on_context_menu_toggled(is_open: bool) -> void:
	is_menu_open = is_open
	_update_passthrough_state()

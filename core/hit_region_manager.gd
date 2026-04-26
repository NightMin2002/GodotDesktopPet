# hit_region_manager.gd — DWM 鼠标穿透管理器 (从 main.gd 拆分)
# 双模式架构:
#   模式A (完美): WS_EX_LAYERED 注入成功 → 本地命中检测 + WS_EX_TRANSPARENT 切换 → 零裁剪
#   模式B (回退): 注入失败 → SetWindowRgn AABB 矩形区域 → 特效区域有裁剪
extends Node

var _main: Node2D

# ── 模式标志 ──
var _transparent_mode := false  # true=完美模式, false=SetWindowRgn回退模式

# ── 穿透状态 ──
var is_dragging := false
var is_menu_open := false
var _is_click_through := false  # 当前 WS_EX_TRANSPARENT 状态 (初始为 false，与窗口实际一致)

# ── 命中区域数据 ──
var _hit_circles := PackedFloat32Array()  # [cx, cy, r, ...]
var _hit_rects := PackedFloat32Array()    # [x, y, w, h, ...]

# ── 回退模式用: 变化检测 ──
var _last_circles := PackedFloat32Array()
var _last_rects := PackedFloat32Array()

# ── 限流 ──
var _collect_timer: float = 0.0
const COLLECT_INTERVAL := 0.008  # ~120fps

## 栅格量化 (回退模式用)
func _q(v: float) -> float:
	return float(int(v / 4.0) * 4)

func setup(main: Node2D) -> void:
	_main = main
	
	EventBus.drag_started.connect(_on_drag_started)
	EventBus.drag_ended.connect(_on_drag_ended)
	EventBus.context_menu_toggled.connect(_on_context_menu_toggled)
	
	# 尝试注入 WS_EX_LAYERED 启用完美模式
	if _main.win_manager and _main.win_manager.has_method("InjectLayeredStyle"):
		_transparent_mode = _main.win_manager.call("InjectLayeredStyle")
	
	if _transparent_mode:
		# 完美模式: 清除 SetWindowRgn，启用 WS_EX_TRANSPARENT 穿透
		_set_click_through(true)
	else:
		# 回退模式: 使用传统 SetWindowRgn
		pass

func _process(delta: float) -> void:
	if is_dragging or is_menu_open:
		return
	
	_collect_timer += delta
	if _collect_timer >= COLLECT_INTERVAL:
		_collect_timer = 0.0
		_collect_hit_regions()
		if _transparent_mode:
			_update_click_through()
		else:
			_update_hit_regions_fallback()

## 收集所有宠物/UI 元素的命中区域
func _collect_hit_regions() -> void:
	var circles := PackedFloat32Array()
	var rects := PackedFloat32Array()
	
	for p in _main.pet_instances:
		if not is_instance_valid(p):
			continue
		
		# 宠物本体: 精确圆形命中
		var pet_pos = p.global_position
		var pet_r = p.PET_RADIUS + 15.0
		circles.append(pet_pos.x)
		circles.append(pet_pos.y)
		circles.append(pet_r)
		
		# 全息时钟 HUD: 矩形
		if p.hud_clock_enabled and is_instance_valid(p.hud_clock_label) and p.hud_clock_label.visible:
			var clock_pos = p.hud_clock_label.global_position
			var clock_size = p.hud_clock_label.get_minimum_size()
			rects.append(clock_pos.x - 5)
			rects.append(clock_pos.y - 5)
			rects.append(clock_size.x + 10)
			rects.append(clock_size.y + 10)
		
		# 全局气泡覆盖层: 矩形
		if p.overlay_rect.size != Vector2.ZERO:
			var ov = p.overlay_rect
			rects.append(ov.position.x)
			rects.append(ov.position.y)
			rects.append(ov.size.x)
			rects.append(ov.size.y)
		
		# 本地定向气泡堆栈: 每个气泡独立矩形
		if p.has_method("get_local_bubble_rects"):
			for br in p.get_local_bubble_rects():
				rects.append(br.position.x)
				rects.append(br.position.y)
				rects.append(br.size.x)
				rects.append(br.size.y)
	
	_hit_circles = circles
	_hit_rects = rects

# ══════════════════════════════════════════
#  模式A: 完美穿透 (WS_EX_TRANSPARENT 切换)
# ══════════════════════════════════════════

## 根据鼠标位置切换穿透状态 (仅在进出宠物区域时调用一次 SetWindowLong)
func _update_click_through() -> void:
	var screen_pos = DisplayServer.mouse_get_position()
	var win_pos = get_window().position
	var mx = float(screen_pos.x - win_pos.x)
	var my = float(screen_pos.y - win_pos.y)
	
	var hit = _point_in_any_region(mx, my)
	
	if hit and _is_click_through:
		_set_click_through(false)  # 鼠标在宠物/UI 上 → 可点击
	elif not hit and not _is_click_through:
		_set_click_through(true)   # 鼠标不在宠物/UI 上 → 穿透

## 精确命中检测: 圆形 (dx²+dy²≤r²) + 矩形 (AABB)
func _point_in_any_region(mx: float, my: float) -> bool:
	var i = 0
	while i + 2 < _hit_circles.size():
		var cx = _hit_circles[i]
		var cy = _hit_circles[i + 1]
		var r = _hit_circles[i + 2]
		if (mx - cx) * (mx - cx) + (my - cy) * (my - cy) <= r * r:
			return true
		i += 3
	
	i = 0
	while i + 3 < _hit_rects.size():
		var x = _hit_rects[i]
		var y = _hit_rects[i + 1]
		var w = _hit_rects[i + 2]
		var h = _hit_rects[i + 3]
		if mx >= x and mx <= x + w and my >= y and my <= y + h:
			return true
		i += 4
	
	return false

## 切换穿透状态
func _set_click_through(transparent: bool) -> void:
	if transparent == _is_click_through:
		return
	_is_click_through = transparent
	if _main.win_manager and _main.win_manager.has_method("SetClickThrough"):
		_main.win_manager.call("SetClickThrough", transparent)

# ══════════════════════════════════════════
#  模式B: 回退 (SetWindowRgn AABB)
# ══════════════════════════════════════════

func _update_hit_regions_fallback() -> void:
	var circles := PackedFloat32Array()
	var rects := PackedFloat32Array()
	
	for p in _main.pet_instances:
		if not is_instance_valid(p):
			continue
		
		var pet_pos = p.global_position
		var pet_r = p.PET_RADIUS + 15.0
		circles.append(_q(pet_pos.x))
		circles.append(_q(pet_pos.y))
		circles.append(_q(pet_r))
		
		# 拖影 AABB
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
		
		# 冲击波 AABB
		for shock in p.shockwaves:
			if shock["alpha"] > 0.1:
				var s_pos = pet_pos + shock["local_pos"]
				var sr: float = shock["radius"] + 10.0
				rects.append(_q(s_pos.x - sr))
				rects.append(_q(s_pos.y - sr))
				rects.append(_q(sr * 2.0))
				rects.append(_q(sr * 2.0))
		
		# HUD/气泡
		if p.hud_clock_enabled and is_instance_valid(p.hud_clock_label) and p.hud_clock_label.visible:
			var clock_pos = p.hud_clock_label.global_position
			var clock_size = p.hud_clock_label.get_minimum_size()
			rects.append(_q(clock_pos.x - 5))
			rects.append(_q(clock_pos.y - 5))
			rects.append(_q(clock_size.x + 10))
			rects.append(_q(clock_size.y + 10))
		
		if p.overlay_rect.size != Vector2.ZERO:
			var ov = p.overlay_rect
			rects.append(_q(ov.position.x))
			rects.append(_q(ov.position.y))
			rects.append(_q(ov.size.x))
			rects.append(_q(ov.size.y))
		
		if p.has_method("get_local_bubble_rects"):
			for br in p.get_local_bubble_rects():
				rects.append(_q(br.position.x))
				rects.append(_q(br.position.y))
				rects.append(_q(br.size.x))
				rects.append(_q(br.size.y))
	
	# 变化检测
	if circles == _last_circles and rects == _last_rects:
		return
	_last_circles = circles
	_last_rects = rects
	
	if _main.win_manager and _main.win_manager.has_method("UpdateHitRegions"):
		_main.win_manager.call("UpdateHitRegions", circles, rects)

# ══════════════════════════════════════════
#  事件处理 (两种模式共用)
# ══════════════════════════════════════════

func _on_drag_started() -> void:
	is_dragging = true
	if _transparent_mode:
		_set_click_through(false)
	else:
		_update_passthrough_state()

func _on_drag_ended() -> void:
	is_dragging = false
	if _transparent_mode:
		_collect_hit_regions()
		_update_click_through()
	else:
		_update_passthrough_state()

func _on_context_menu_toggled(is_open: bool) -> void:
	is_menu_open = is_open
	if _transparent_mode:
		if is_open:
			_set_click_through(false)
		else:
			_collect_hit_regions()
			_update_click_through()
	else:
		_update_passthrough_state()

func _update_passthrough_state() -> void:
	if is_dragging or is_menu_open:
		if _main.win_manager and _main.win_manager.has_method("SetFullWindowHit"):
			_main.win_manager.call("SetFullWindowHit", true)
	else:
		if _main.win_manager and _main.win_manager.has_method("SetFullWindowHit"):
			_main.win_manager.call("SetFullWindowHit", false)
		_last_circles = PackedFloat32Array()
		_last_rects = PackedFloat32Array()

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
var _menu_open_count: int = 0   # 面板打开引用计数 (解决多面板时序竞争)
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
	# 拖拽/菜单期间：强制保持可点击 (每帧自动修正，防止时序问题)
	if is_dragging or is_menu_open:
		if _transparent_mode and _is_click_through:
			_set_click_through(false)
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
		
		# HUD 监控面板: 矩形
		if p.hud_panel:
			var hud_r = p.hud_panel.get_panel_rect()
			if hud_r.size != Vector2.ZERO:
				rects.append(hud_r.position.x)
				rects.append(hud_r.position.y)
				rects.append(hud_r.size.x)
				rects.append(hud_r.size.y)
		
		# 全息屏关闭按钮: 矩形
		if p.holo_screen:
			var btn_r = p.holo_screen.get_close_btn_rect()
			if btn_r.size != Vector2.ZERO:
				rects.append(btn_r.position.x)
				rects.append(btn_r.position.y)
				rects.append(btn_r.size.x)
				rects.append(btn_r.size.y)
		# 游戏态关闭按钮: 矩形
		if p.gaming:
			var gbtn_r = p.gaming.get_close_btn_rect()
			if gbtn_r.size != Vector2.ZERO:
				rects.append(gbtn_r.position.x)
				rects.append(gbtn_r.position.y)
				rects.append(gbtn_r.size.x)
				rects.append(gbtn_r.size.y)
		# 待办提醒按钮: 矩形
		if p.has_meta("prompt_btn_rect"):
			var pr: Rect2 = p.get_meta("prompt_btn_rect")
			if pr.size != Vector2.ZERO:
				rects.append(pr.position.x)
				rects.append(pr.position.y)
				rects.append(pr.size.x)
				rects.append(pr.size.y)
	
	_hit_circles = circles
	_hit_rects = rects

	# 游戏面板 (game_container + tutorial_panel)
	if _main.game_mgr and _main.game_mgr.has_method("get_panel_rects"):
		for r in _main.game_mgr.get_panel_rects():
			_hit_rects.append(r.position.x)
			_hit_rects.append(r.position.y)
			_hit_rects.append(r.size.x)
			_hit_rects.append(r.size.y)

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
		if p.pet_effects.trail_enabled and p.pet_effects.trail_history.size() > 0:
			var min_x: float = pet_pos.x
			var min_y: float = pet_pos.y
			var max_x: float = pet_pos.x
			var max_y: float = pet_pos.y
			for trail_pos in p.pet_effects.trail_history:
				min_x = minf(min_x, trail_pos.x - p.PET_RADIUS)
				min_y = minf(min_y, trail_pos.y - p.PET_RADIUS)
				max_x = maxf(max_x, trail_pos.x + p.PET_RADIUS)
				max_y = maxf(max_y, trail_pos.y + p.PET_RADIUS)
			rects.append(_q(min_x - 5))
			rects.append(_q(min_y - 5))
			rects.append(_q(max_x - min_x + 10))
			rects.append(_q(max_y - min_y + 10))
		
		# 冲击波 AABB
		for shock in p.pet_effects.shockwaves:
			if shock["alpha"] > 0.1:
				var s_pos = pet_pos + shock["local_pos"]
				var sr: float = shock["radius"] + 10.0
				rects.append(_q(s_pos.x - sr))
				rects.append(_q(s_pos.y - sr))
				rects.append(_q(sr * 2.0))
				rects.append(_q(sr * 2.0))
		
		# 全局气泡
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
		
		# HUD 监控面板
		if p.hud_panel:
			var hud_r = p.hud_panel.get_panel_rect()
			if hud_r.size != Vector2.ZERO:
				rects.append(_q(hud_r.position.x))
				rects.append(_q(hud_r.position.y))
				rects.append(_q(hud_r.size.x))
				rects.append(_q(hud_r.size.y))
		
		# 全息屏关闭按钮
		if p.holo_screen:
			var btn_r = p.holo_screen.get_close_btn_rect()
			if btn_r.size != Vector2.ZERO:
				rects.append(_q(btn_r.position.x))
				rects.append(_q(btn_r.position.y))
				rects.append(_q(btn_r.size.x))
				rects.append(_q(btn_r.size.y))
		# 游戏态关闭按钮
		if p.gaming:
			var gbtn_r = p.gaming.get_close_btn_rect()
			if gbtn_r.size != Vector2.ZERO:
				rects.append(_q(gbtn_r.position.x))
				rects.append(_q(gbtn_r.position.y))
				rects.append(_q(gbtn_r.size.x))
				rects.append(_q(gbtn_r.size.y))
		# 待办提醒按钮
		if p.has_meta("prompt_btn_rect"):
			var pr: Rect2 = p.get_meta("prompt_btn_rect")
			if pr.size != Vector2.ZERO:
				rects.append(_q(pr.position.x))
				rects.append(_q(pr.position.y))
				rects.append(_q(pr.size.x))
				rects.append(_q(pr.size.y))

	# 游戏面板
	if _main.game_mgr and _main.game_mgr.has_method("get_panel_rects"):
		for gr in _main.game_mgr.get_panel_rects():
			rects.append(_q(gr.position.x))
			rects.append(_q(gr.position.y))
			rects.append(_q(gr.size.x))
			rects.append(_q(gr.size.y))
	
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
	# 引用计数: 多个面板可能同时处于打开状态 (菜单/提醒/主题)
	# 只有所有面板都关闭后才恢复穿透
	if is_open:
		_menu_open_count += 1
	else:
		_menu_open_count = maxi(_menu_open_count - 1, 0)
	is_menu_open = _menu_open_count > 0
	if _transparent_mode:
		if is_menu_open:
			_set_click_through(false)
		else:
			# 所有面板关闭：立即刷新命中区域和穿透状态
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

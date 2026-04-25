# ghost_wall_manager.gd — 幽灵墙管理器 (从 main.gd 拆分)
# 职责: Win32 窗口感知 + 三模式建墙 (FREE/CONFINED/REPELLED)
# 使用 Geometry2D.merge_polygons (Clipper) 计算重叠窗口的精确外轮廓
extends Node

var _main: Node2D  # 主系统引用 (访问 win_manager/screen_rect/boundary_size/pet_instances)

# ── 对象池 ──
var ghost_walls: Array[StaticBody2D] = []

# ── 常量 ──
const MAX_PLATFORM_SEGMENTS := 3
const MIN_SEGMENT_WIDTH := 30.0
const CHILDREN_PER_WALL := MAX_PLATFORM_SEGMENTS * 2 + 2

func setup(main: Node2D) -> void:
	_main = main
	
	if _main.win_manager:
		var sync_timer = Timer.new()
		sync_timer.wait_time = 0.1
		sync_timer.autostart = true
		sync_timer.timeout.connect(_sync_ghost_walls)
		add_child(sync_timer)
		print("[DesktopPet] 幽灵侦测雷达已启动")
	
	EventBus.window_mode_changed.connect(_on_window_mode_changed)

# ── 窗口模式切换回调 ──

func _on_window_mode_changed(mode: int) -> void:
	_main.window_mode = mode
	SettingsManager.set_int("window_mode", mode)
	
	for p in _main.pet_instances:
		if is_instance_valid(p):
			p.window_mode = mode
	
	print("[DesktopPet] 窗口交互模式切换: ", ["自由漫游", "窗口封闭", "窗口排斥"][mode])

# ── 幽灵墙同步 ──

func _sync_ghost_walls() -> void:
	if not is_instance_valid(_main.win_manager): return
	
	var rects: Array = _main.win_manager.call("GetVisibleWindowRects")
	var count = rects.size()
	
	# 动态伸缩对象池
	while ghost_walls.size() < count:
		var wall = StaticBody2D.new()
		for k in range(CHILDREN_PER_WALL):
			var col = CollisionShape2D.new()
			col.shape = RectangleShape2D.new()
			col.disabled = true
			wall.add_child(col)
		var mat = PhysicsMaterial.new()
		mat.bounce = 0.2
		mat.friction = 0.8
		wall.physics_material_override = mat
		_main.add_child(wall)
		ghost_walls.append(wall)
		
	while ghost_walls.size() > count:
		var wall = ghost_walls.pop_back()
		wall.queue_free()
	
	# rect 转本地坐标缓存
	var local_rects: Array[Rect2] = []
	for i in range(count):
		var desk_rect = rects[i] as Rect2i
		var lx = float(desk_rect.position.x - _main.screen_rect.position.x)
		var ly = float(desk_rect.position.y - _main.screen_rect.position.y)
		local_rects.append(Rect2(lx, ly, float(desk_rect.size.x), float(desk_rect.size.y)))
	
	# 根据当前模式分派处理
	match _main.window_mode:
		0:  # FREE
			_apply_free_mode(local_rects, count)
		1:  # CONFINED
			_apply_confined_mode(local_rects, count)
		2:  # REPELLED
			_apply_repelled_mode(local_rects, count)

# ── FREE 模式: 只生成顶/底单向踏板 ──

func _apply_free_mode(local_rects: Array[Rect2], count: int) -> void:
	var floor_thickness = 10.0
	for i in range(count):
		var lr = local_rects[i]
		var wall = ghost_walls[i]
		
		_ensure_children(wall)
		
		wall.position = lr.position + lr.size / 2.0
		
		var win_left = lr.position.x
		var win_right = lr.position.x + lr.size.x
		var top_y = lr.position.y
		var bottom_y = lr.position.y + lr.size.y
		
		var top_segs = _compute_exposed_segments(win_left, win_right, top_y, local_rects, i)
		var bottom_segs = _compute_exposed_segments(win_left, win_right, bottom_y, local_rects, i)
		
		var wall_cx = lr.position.x + lr.size.x / 2.0
		var top_rel_y = -lr.size.y / 2.0 + floor_thickness / 2.0
		var bot_rel_y = lr.size.y / 2.0 - floor_thickness / 2.0
		_apply_platform_segments(wall, 0, top_segs, wall_cx, top_rel_y, floor_thickness, true)
		_apply_platform_segments(wall, MAX_PLATFORM_SEGMENTS, bottom_segs, wall_cx, bot_rel_y, floor_thickness, true)
		
		_disable_side_walls(wall)

# ── REPELLED / CONFINED 模式 ──

func _apply_repelled_mode(local_rects: Array[Rect2], count: int) -> void:
	_apply_polygon_wall_mode(local_rects, count, 0.0)

func _apply_confined_mode(local_rects: Array[Rect2], count: int) -> void:
	_apply_polygon_wall_mode(local_rects, count, PI)

# ── 通用多边形合并建墙 (CONFINED / REPELLED 共用) ──

func _apply_polygon_wall_mode(local_rects: Array[Rect2], count: int, rotation_offset: float) -> void:
	var polys: Array[PackedVector2Array] = []
	for i in range(count):
		if _is_maximized_window(local_rects[i]):
			continue
		var r = local_rects[i]
		polys.append(PackedVector2Array([
			r.position,
			Vector2(r.end.x, r.position.y),
			r.end,
			Vector2(r.position.x, r.end.y)
		]))
		
	# 多边形合并 (Clipper)
	var merged_polys: Array[PackedVector2Array] = polys.duplicate()
	var merged_happened = true
	while merged_happened and merged_polys.size() > 1:
		merged_happened = false
		var next_polys: Array[PackedVector2Array] = []
		while merged_polys.size() > 0:
			var p1 = merged_polys.pop_back()
			var found_merge = false
			for i in range(merged_polys.size()):
				if not Geometry2D.intersect_polygons(p1, merged_polys[i]).is_empty():
					var res = Geometry2D.merge_polygons(p1, merged_polys[i])
					merged_polys.remove_at(i)
					merged_polys.append_array(res)
					found_merge = true
					merged_happened = true
					break
			if not found_merge:
				next_polys.append(p1)
		merged_polys = next_polys
		
	# 建墙
	var wall_idx = 0
	for poly in merged_polys:
		if wall_idx >= ghost_walls.size(): break
		var wall = ghost_walls[wall_idx]
		wall.position = Vector2.ZERO
		var child_idx = 0
		var n = poly.size()
		
		for i in range(n):
			var a = poly[i]
			var b = poly[(i + 1) % n]
			var length = a.distance_to(b)
			if length < 5.0: continue
			
			while child_idx >= wall.get_child_count():
				var c = CollisionShape2D.new()
				c.shape = RectangleShape2D.new()
				c.disabled = true
				wall.add_child(c)
				
			var col = wall.get_child(child_idx) as CollisionShape2D
			col.position = (a + b) / 2.0
			var rect_shape = col.shape as RectangleShape2D
			if rect_shape == null:
				rect_shape = RectangleShape2D.new()
				col.shape = rect_shape
				
			rect_shape.size = Vector2(length + 10.0, 10.0)
			col.rotation = (b - a).angle() + rotation_offset
			col.one_way_collision = true
			col.disabled = false
			child_idx += 1
			
		for i in range(child_idx, wall.get_child_count()):
			(wall.get_child(i) as CollisionShape2D).disabled = true
			
		wall_idx += 1

	for i in range(wall_idx, ghost_walls.size()):
		var w = ghost_walls[i]
		for k in range(w.get_child_count()):
			(w.get_child(k) as CollisionShape2D).disabled = true

func _is_maximized_window(lr: Rect2) -> bool:
	return lr.size.x >= _main.boundary_size.x * 0.9 and lr.size.y >= _main.boundary_size.y * 0.85

# ── 辅助函数 ──

func _ensure_children(wall: StaticBody2D) -> void:
	while wall.get_child_count() < CHILDREN_PER_WALL:
		var col = CollisionShape2D.new()
		col.shape = RectangleShape2D.new()
		col.disabled = true
		wall.add_child(col)

func _disable_side_walls(wall: StaticBody2D) -> void:
	var side_idx_left = MAX_PLATFORM_SEGMENTS * 2
	var side_idx_right = MAX_PLATFORM_SEGMENTS * 2 + 1
	if wall.get_child_count() > side_idx_right:
		var col_l = wall.get_child(side_idx_left) as CollisionShape2D
		col_l.disabled = true
		col_l.rotation = 0.0
		var col_r = wall.get_child(side_idx_right) as CollisionShape2D
		col_r.disabled = true
		col_r.rotation = 0.0

func _compute_exposed_segments(full_left: float, full_right: float, platform_y: float, all_rects: Array[Rect2], idx: int) -> Array:
	var segs: Array = [[full_left, full_right]]
	for j in range(idx):
		var hr = all_rects[j]
		if hr.position.y < platform_y - 5.0 and hr.position.y + hr.size.y > platform_y + 5.0:
			segs = _subtract_range(segs, hr.position.x, hr.position.x + hr.size.x)
	var result: Array = []
	for s in segs:
		if s[1] - s[0] >= MIN_SEGMENT_WIDTH:
			result.append(s)
	return result.slice(0, MAX_PLATFORM_SEGMENTS)

func _subtract_range(segs: Array, cut_l: float, cut_r: float) -> Array:
	var out: Array = []
	for s in segs:
		if cut_r <= s[0] or cut_l >= s[1]:
			out.append(s)
		else:
			if s[0] < cut_l:
				out.append([s[0], cut_l])
			if s[1] > cut_r:
				out.append([cut_r, s[1]])
	return out

func _apply_platform_segments(wall: StaticBody2D, child_offset: int, segs: Array, wall_cx: float, rel_y: float, thickness: float, one_way: bool, seg_rotation: float = 0.0) -> void:
	for k in range(MAX_PLATFORM_SEGMENTS):
		var col = wall.get_child(child_offset + k) as CollisionShape2D
		if k < segs.size():
			var seg = segs[k]
			var seg_cx = (seg[0] + seg[1]) / 2.0
			col.position = Vector2(seg_cx - wall_cx, rel_y)
			(col.shape as RectangleShape2D).size = Vector2(seg[1] - seg[0], thickness)
			col.one_way_collision = one_way
			col.rotation = seg_rotation
			col.disabled = false
		else:
			col.disabled = true
			col.rotation = 0.0

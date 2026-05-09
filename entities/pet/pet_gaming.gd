# pet_gaming.gd — 宠物游戏态管理器 (RefCounted)
# 管理游戏态行为: 锁定宠物、踏板升降、瞳孔跟踪、全息迷你屏渲染
# 从 pet.gd 抽离，与 PetEffects / EyeBehavior / IdleBehaviors 等子系统同级
class_name PetGaming
extends RefCounted

var pet: RigidBody2D  # 由 pet.gd 注入

# ── 游戏态状态 ──
var active: bool = false
var game: RefCounted = null  # 当前游戏引用 (BaseGame)
var holo_side: float = 1.0  # 全息屏方向: 1=右侧, -1=左侧
var holo_aspect: float = 0.0  # 全息屏宽高比 (初始化后固定)

# ── 悬浮踏板 ──
var _platform: StaticBody2D = null  # 游戏态悬浮踏板
var _lift_phase: int = 0     # 0=空闲, 1=上升中, 2=已到位
var _lift_target_y: float = 0.0  # 踏板目标高度

# ── 接口 ──

## 游戏启停信号处理
func on_gaming_changed(is_active: bool, game_ref: RefCounted) -> void:
	if pet.is_clone:
		return
	active = is_active
	game = game_ref
	if is_active:
		holo_aspect = 0.0  # 重置，让新游戏初始化自己的比例
		# 取消正在进行的空间跳跃 (清理踏板+状态)
		if pet.free_roam_sys.active:
			pet.free_roam_sys.finish()
		# 决定全息屏在宠物哪边
		if pet.global_position.x > pet.boundary_size.x * 0.5:
			holo_side = -1.0
		else:
			holo_side = 1.0
		# 高阻尼停下来 (保留重力，在空中会自然落地)
		pet.linear_damp = 20.0
		pet.linear_velocity = Vector2.ZERO
		# 切到 idle 状态
		if pet.current_state_name != "idle":
			pet.transition_to("idle")
		# 生成踏板，缓缓升起
		_spawn_platform()
	else:
		pet.eye_behavior.forced_look_dir = Vector2.ZERO
		# 清除踏板
		_remove_platform()
		# 设置空间跳跃冷却 (退出游戏后 60 秒内不触发 roam)
		pet.set_meta("_roam_cooldown", Time.get_ticks_msec())
		# 切到 fall 状态自然过渡 (fall.enter 会恢复阻尼)
		pet.transition_to("fall")
	pet.queue_redraw()

## 每帧更新: 瞳孔追踪 + 位置锁定 + 踏板升降驱动
func update(delta: float) -> void:
	if not active:
		return
	pet.eye_behavior.forced_look_dir = Vector2(holo_side, 0.15)
	pet.linear_velocity = Vector2.ZERO
	# 踏板上升驱动
	if _lift_phase == 1 and is_instance_valid(_platform):
		var lift_speed = 80.0
		_platform.position.y -= lift_speed * delta * pet.gravity_sign
		# 宠物跟随踏板
		pet.global_position.y = _platform.position.y - pet.PET_RADIUS * pet.gravity_sign
		# 检测抵达目标高度
		var dist = (_platform.position.y - _lift_target_y) * pet.gravity_sign
		if dist <= 0.0:
			_platform.position.y = _lift_target_y
			pet.global_position.y = _lift_target_y - pet.PET_RADIUS * pet.gravity_sign
			_lift_phase = 2
	elif _lift_phase == 2 and is_instance_valid(_platform):
		# 已到位: 持续锁定宠物在踏板上
		pet.global_position.y = _platform.position.y - pet.PET_RADIUS * pet.gravity_sign
	# 落地后锁 idle
	if pet.current_state_name != "idle" and pet.is_settled():
		pet.transition_to("idle")

## 全息迷你屏渲染 (由 pet.gd._draw() 调用)
func render_hologram() -> void:
	var hue = EventBus.ui_hue
	# 在世界坐标系中绘制 (反旋转刚体旋转)
	pet.draw_set_transform(Vector2.ZERO, -pet.rotation, Vector2.ONE)

	var side = holo_side
	var gap = pet.PET_RADIUS + 5.0

	# 获取 SubViewport 纹理，按比例计算全息屏尺寸
	var viewport_tex: Texture2D = null
	if game and game.game_viewport:
		viewport_tex = game.game_viewport.get_texture()
	var holo_w: float
	var holo_h: float
	if viewport_tex and viewport_tex.get_size().y > 0:
		var tex_size = viewport_tex.get_size()
		# 首次获取时记录宽高比，后续固定 (防止面板大小变化导致跳变)
		if holo_aspect <= 0.0:
			holo_aspect = tex_size.x / tex_size.y
		holo_h = pet.PET_RADIUS * 2.5
		holo_w = holo_h * holo_aspect
	else:
		holo_w = pet.PET_RADIUS * 1.6
		holo_h = pet.PET_RADIUS * 1.6

	# 全息屏中心
	var cx = side * (gap + holo_w * 0.5)
	var cy = 0.0  # 垂直居中于宠物中心

	# 投影支架线
	var near_edge_x = cx - side * holo_w * 0.5  # 靠近宠物的边
	var beam_start = Vector2(side * pet.PET_RADIUS * 0.6, 0)
	var beam_end = Vector2(near_edge_x, cy)
	pet.draw_line(beam_start, beam_end, Color.from_hsv(hue, 0.3, 0.8, 0.2), 0.8, true)
	pet.draw_circle(beam_start, 1.5, Color.from_hsv(hue, 0.4, 1.0, 0.4), true, -1.0, true)

	# 梯形透视: 靠近宠物的边上下收缩，远离的边保持原高
	# 模拟"侧面看投影屏幕"的真实感
	var half_w = holo_w / 2.0
	var half_h = holo_h / 2.0
	var shrink = 0.15  # 近端收缩比例 (15%)
	var near_half_h = half_h * (1.0 - shrink)  # 近端半高 (较短)
	var far_half_h = half_h                     # 远端半高 (原高)

	# 梯形 4 个顶点 (左上→右上→右下→左下)
	var pts: PackedVector2Array
	if side > 0:  # 全息屏在右侧: 左边(近端)窄，右边(远端)宽
		pts = PackedVector2Array([
			Vector2(cx - half_w, cy - near_half_h),  # 左上 (近)
			Vector2(cx + half_w, cy - far_half_h),   # 右上 (远)
			Vector2(cx + half_w, cy + far_half_h),   # 右下 (远)
			Vector2(cx - half_w, cy + near_half_h),  # 左下 (近)
		])
	else:  # 全息屏在左侧: 右边(近端)窄，左边(远端)宽
		pts = PackedVector2Array([
			Vector2(cx - half_w, cy - far_half_h),   # 左上 (远)
			Vector2(cx + half_w, cy - near_half_h),  # 右上 (近)
			Vector2(cx + half_w, cy + near_half_h),  # 右下 (近)
			Vector2(cx - half_w, cy + far_half_h),   # 左下 (远)
		])
	var uvs = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	])

	# 外框光晕 (梯形轮廓)
	var glow_pts = pts.duplicate()
	glow_pts.append(pts[0])  # 闭合
	pet.draw_polyline(glow_pts, Color.from_hsv(hue, 0.3, 0.8, 0.1), 2.0, true)
	pet.draw_polyline(glow_pts, Color.from_hsv(hue, 0.4, 0.9, 0.35), 0.6, true)

	# SubViewport 纹理映射到梯形 (自动镜像任何游戏面板)
	if viewport_tex:
		pet.draw_polygon(pts, [Color(1, 1, 1, 0.75)], uvs, viewport_tex)

	# 恢复变换
	pet.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# ── 踏板管理 (私有) ──

## 在宠物脚下生成踏板，缓缓升起把宠物托到空中
func _spawn_platform() -> void:
	var parent = pet.get_parent()
	if not parent:
		return
	# 踏板位置 = 宠物脚下
	var plat_y = pet.global_position.y + pet.PET_RADIUS * pet.gravity_sign
	var body = StaticBody2D.new()
	body.position = Vector2(pet.global_position.x, plat_y)
	# 碰撞体 (单向踏板)
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(pet.PET_RADIUS * 2.0, 8.0)
	col.shape = shape
	col.one_way_collision = true
	if pet.anti_gravity:
		col.rotation = PI
	body.add_child(col)
	# 视觉效果 (复用 FreeRoamSystem 的 PlatformVisual)
	var visual = FreeRoamSystem.PlatformVisual.new()
	visual.platform_width = pet.PET_RADIUS * 2.0
	visual.platform_color = pet.palette.shift_color(Color(0.2, 0.6, 1.0, 0.6))
	body.add_child(visual)
	parent.add_child(body)
	# 淡入
	body.modulate.a = 0.0
	var tween = body.create_tween()
	tween.tween_property(body, "modulate:a", 1.0, 0.3)
	_platform = body
	# 目标高度: 上升约 15px
	_lift_target_y = plat_y - 15.0 * pet.gravity_sign
	_lift_phase = 1
	# 关闭重力，让踏板完全控制宠物高度
	pet.gravity_scale = 0.0

func _remove_platform() -> void:
	_lift_phase = 0
	pet.gravity_scale = pet.gravity_sign  # 恢复重力
	if is_instance_valid(_platform):
		# 立即禁用碰撞体，让宠物能马上下落
		for child in _platform.get_children():
			if child is CollisionShape2D:
				child.disabled = true
		# 淡出 + 移除
		var plat = _platform
		_platform = null
		var tween = plat.create_tween()
		tween.tween_property(plat, "modulate:a", 0.0, 0.3)
		tween.finished.connect(func():
			if is_instance_valid(plat):
				plat.queue_free()
		)

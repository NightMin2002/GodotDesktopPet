# pet_holo_screen.gd — 宠物全息屏主控制器 (RefCounted)
# 管理全息迷你屏的渲染 (梯形透视)、屏幕矩形计算
# 从 pet_gaming.gd 提取渲染逻辑
# Phase 1: 仅游戏模式, 后续阶段扩展为多模式个人终端
class_name PetHoloScreen extends RefCounted

var pet: RigidBody2D  # 由 pet.gd 注入

# ── 屏幕状态 ──
var visible: bool = false
var side: float = 1.0  # 全息屏方向: 1=右侧, -1=左侧

# ── 纹理源 (游戏模式通过回调获取) ──
var _texture_provider: Callable = Callable()  # 返回 Texture2D 的回调

## 显示全息屏 (游戏模式: 接收纹理回调)
func show_game(texture_provider: Callable, screen_side: float) -> void:
	visible = true
	side = screen_side
	_texture_provider = texture_provider

## 隐藏全息屏
func hide() -> void:
	visible = false
	_texture_provider = Callable()

## 全息迷你屏渲染 (由 pet.gd._draw() 调用)
func render() -> void:
	if not visible:
		return
	var hue = EventBus.ui_hue
	# 在世界坐标系中绘制 (反旋转刚体旋转)
	pet.draw_set_transform(Vector2.ZERO, -pet.rotation, Vector2.ONE)

	# 固定尺寸: 所有模式的全息迷你屏大小/位置一致
	var gap = pet.PET_RADIUS * 0.1  # 近端留一小段空隙

	# 获取纹理
	var viewport_tex: Texture2D = null
	if _texture_provider.is_valid():
		viewport_tex = _texture_provider.call()
	var holo_w: float = pet.PET_RADIUS * 2.0
	var holo_h: float = pet.PET_RADIUS * 2.5

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
	var half_w = holo_w / 2.0
	var half_h = holo_h / 2.0
	var shrink = 0.15  # 近端收缩比例 (15%)
	var near_half_h = half_h * (1.0 - shrink)  # 近端半高 (较短)
	var far_half_h = half_h                     # 远端半高 (原高)

	# 微后仰: 顶部向远离宠物方向偏移，模拟屏幕微倾
	var tilt = side * holo_w * 0.16

	# 梯形 4 个顶点 (左上→右上→右下→左下)
	var pts: PackedVector2Array
	if side > 0:  # 全息屏在右侧: 左边(近端)窄，右边(远端)宽
		pts = PackedVector2Array([
			Vector2(cx - half_w + tilt, cy - near_half_h),  # 左上 (近, 后仰)
			Vector2(cx + half_w + tilt, cy - far_half_h),   # 右上 (远, 后仰)
			Vector2(cx + half_w, cy + far_half_h),           # 右下 (远)
			Vector2(cx - half_w, cy + near_half_h),          # 左下 (近)
		])
	else:  # 全息屏在左侧: 右边(近端)窄，左边(远端)宽
		pts = PackedVector2Array([
			Vector2(cx - half_w + tilt, cy - far_half_h),   # 左上 (远, 后仰)
			Vector2(cx + half_w + tilt, cy - near_half_h),  # 右上 (近, 后仰)
			Vector2(cx + half_w, cy + near_half_h),          # 右下 (近)
			Vector2(cx - half_w, cy + far_half_h),           # 左下 (远)
		])
	var uvs = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	])

	# 合成纹理映射到梯形 (面板 + 悬浮组件的完整画面)
	if viewport_tex:
		pet.draw_polygon(pts, [Color(1, 1, 1, 0.75)], uvs, viewport_tex)

	# 恢复变换
	pet.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## 返回全息迷你屏在屏幕上的包围矩形 (供游戏面板定位时避让)
func get_screen_rect() -> Rect2:
	if not visible:
		return Rect2()
	var gap_val = pet.PET_RADIUS * 0.1
	var holo_w: float = pet.PET_RADIUS * 2.0
	var holo_h: float = pet.PET_RADIUS * 2.5
	var cx = side * (gap_val + holo_w * 0.5)
	var cy = 0.0
	# 转到屏幕坐标
	var pet_screen = pet.get_global_transform_with_canvas().get_origin()
	var rect_x = pet_screen.x + cx - holo_w * 0.5 - 4.0
	var rect_y = pet_screen.y + cy - holo_h * 0.5 - 4.0
	return Rect2(rect_x, rect_y, holo_w + 8.0, holo_h + 8.0)

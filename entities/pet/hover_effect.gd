# hover_effect.gd — 鼠标悬停视觉特效管理器
# 鼠标靠近宠物时的"选中态"视觉反馈
# 支持多种可切换样式, 从 pet.gd 委托调用
class_name HoverEffect
extends RefCounted

var pet: RigidBody2D  # 宿主宠物引用

# ── 状态 ──
var style: int = 0           # 0=关闭, 1=柔光环, 2=边缘呼吸, 3=锁定框
var _amount: float = 0.0     # 悬停动画进度 (0→1 平滑过渡)
var _time: float = 0.0       # 动画计时器

# ── 样式配置 ──
const STYLE_NAMES := ["关闭", "柔光环", "边缘呼吸", "锁定框", "遥测模式"]
const STYLE_COUNT := 5

# ── 数据更新 (由 pet._process 调用) ──
## 返回是否有视觉变化 (用于按需 queue_redraw)
func update(delta: float, is_hovering: bool) -> bool:
	if style == 0:
		if _amount > 0.0:
			_amount = move_toward(_amount, 0.0, delta * 5.0)
			return true
		return false
	
	var target = 1.0 if is_hovering else 0.0
	var prev = _amount
	_amount = move_toward(_amount, target, delta * 4.0)
	
	if _amount > 0.01:
		_time += delta
	else:
		_time = 0.0
	
	return _amount > 0.01 or prev > 0.01

# ── 渲染 (由 pet._draw 调用) ──
func render(canvas: Node2D) -> void:
	if _amount <= 0.01:
		return
	match style:
		1: _render_soft_glow(canvas)
		2: _render_edge_breathe(canvas)
		3: _render_lock_frame(canvas)
		4: _render_telemetry(canvas)

# ══════════════════════════════════════
#  样式 1: 柔光环
#  外壳外围一圈柔和的发光环, 呼吸式透明度
# ══════════════════════════════════════

func _render_soft_glow(canvas: Node2D) -> void:
	var alpha = _amount
	var t = _time
	var hue = EventBus.ui_hue
	var r = pet.PET_RADIUS
	
	# 呼吸脉冲
	var pulse = sin(t * 2.5) * 0.08 + 1.0
	var glow_r = (r + 6.0) * pulse
	
	# 外层漫射光晕
	var glow_outer = Color.from_hsv(hue, 0.4, 1.0, alpha * 0.12)
	canvas.draw_circle(Vector2.ZERO, glow_r + 8.0, glow_outer, true, -1.0, true)
	
	# 主环
	var ring_color = Color.from_hsv(hue, 0.5, 1.0, alpha * 0.35)
	canvas.draw_arc(Vector2.ZERO, glow_r, 0, TAU, 64, ring_color, 2.5, true)
	
	# 内层紧贴外壳的窄光带
	var inner_color = Color.from_hsv(hue, 0.3, 1.0, alpha * 0.2 * pulse)
	canvas.draw_arc(Vector2.ZERO, r + 2.0, 0, TAU, 64, inner_color, 1.5, true)

# ══════════════════════════════════════
#  样式 2: 边缘呼吸
#  外壳轮廓线节奏性变亮, 像脉搏跳动
# ══════════════════════════════════════

func _render_edge_breathe(canvas: Node2D) -> void:
	var alpha = _amount
	var t = _time
	var hue = EventBus.ui_hue
	var r = pet.PET_RADIUS
	
	# 双频脉冲: 主呼吸 + 微颤
	var pulse = sin(t * 2.0) * 0.5 + 0.5  # 0~1
	var micro = sin(t * 7.0) * 0.1
	var intensity = (pulse + micro) * alpha
	
	# 边缘高亮 (在外壳轮廓线外侧叠加一圈)
	var edge_color = Color.from_hsv(hue, 0.6, 1.0, intensity * 0.5)
	canvas.draw_arc(Vector2.ZERO, r + 1.5, 0, TAU, 64, edge_color, 3.0, true)
	
	# 脉冲扩散环 (心跳节奏)
	var beat = fmod(t * 1.2, 1.0)  # 0→1 循环
	var beat_r = r + 3.0 + beat * 15.0
	var beat_alpha = (1.0 - beat) * intensity * 0.3
	if beat_alpha > 0.01:
		canvas.draw_arc(Vector2.ZERO, beat_r, 0, TAU, 48, Color.from_hsv(hue, 0.5, 1.0, beat_alpha), 1.5, true)

# ══════════════════════════════════════
#  样式 3: 锁定框
#  科幻准星/锁定框风格, 四角标记 + 旋转
# ══════════════════════════════════════

func _render_lock_frame(canvas: Node2D) -> void:
	var alpha = _amount
	var t = _time
	var hue = EventBus.ui_hue
	var r = pet.PET_RADIUS
	
	# 锁定时的收缩动效：从外向内“砸”进去，营造硬核锁定感
	# pow() 让动画有一个非线性的减速贴合效果
	var expand = pow(1.0 - alpha, 3.0) * 20.0
	var base_r = r + 6.0 + expand
	
	var theme_color = Color.from_hsv(hue, 0.6, 1.0, alpha * 0.8)
	var accent_color = Color(1.0, 0.25, 0.25, alpha * 0.7)
	var dim_color = Color.from_hsv(hue, 0.4, 1.0, alpha * 0.3)
	
	# 1. 绘制四个机械边角 ┏ ┓ ┗ ┛
	var corner_len = 8.0
	var corner_thick = 2.0
	var dirs = [
		Vector2(-1, -1), # 左上
		Vector2(1, -1),  # 右上
		Vector2(1, 1),   # 右下
		Vector2(-1, 1)   # 左下
	]
	
	for d in dirs:
		# 让对角线向量稍微向外延伸一点
		var origin = d.normalized() * base_r
		# h_dir 和 v_dir 决定画线的方向，全部朝向中心
		var h_dir = Vector2(-sign(d.x), 0)
		var v_dir = Vector2(0, -sign(d.y))
		
		# 画机械折角
		canvas.draw_line(origin, origin + h_dir * corner_len, theme_color, corner_thick, true)
		canvas.draw_line(origin, origin + v_dir * corner_len, theme_color, corner_thick, true)
		
		# 在拐角处点缀高光点
		canvas.draw_circle(origin, 1.0, accent_color, true, -1.0, true)
		
	# 2. 四级雷达指示器 (缓慢旋转)
	var inner_r = r + 2.0
	var spin = t * 0.8
	for i in range(4):
		var angle = spin + i * (PI / 2.0)
		var dir = Vector2(cos(angle), sin(angle))
		# 画四个稍微向外延伸的精简刻度
		canvas.draw_line(dir * (inner_r - 1.0), dir * (inner_r + 3.0), accent_color, 1.5, true)
			
	# 3. 极简硬核十字准星 (带呼吸闪烁)
	var pulse = sin(t * 5.0) * 0.2 + 0.8
	var cross_size = 3.0
	var center_color = Color(1.0, 0.3, 0.2, alpha * pulse)
	canvas.draw_line(Vector2(-cross_size, 0), Vector2(cross_size, 0), center_color, 1.0, true)
	canvas.draw_line(Vector2(0, -cross_size), Vector2(0, cross_size), center_color, 1.0, true)

# ══════════════════════════════════════
#  样式 4: 遥测模式 (Telemetry UI)
#  全息调试面板风格，带有滑入动效、十字基准线和高频刷新的模拟数据流
# ══════════════════════════════════════
func _render_telemetry(canvas: Node2D) -> void:
	var alpha = _amount
	var t = _time
	var hue = EventBus.ui_hue
	var r = pet.PET_RADIUS
	
	var c_main = Color.from_hsv(hue, 0.6, 1.0, alpha * 0.8)
	var c_dim = Color.from_hsv(hue, 0.4, 1.0, alpha * 0.25)
	
	# 随 _amount 展开的滑入动画
	var expand = ease(alpha, 0.4)
	
	# 1. 贯穿的十字基准线 (大幅收缩尺寸，显得更克制)
	var ext = (r + 15.0) * expand
	var gap = 12.0
	if ext > gap:
		canvas.draw_line(Vector2(-ext, 0), Vector2(-gap, 0), c_dim, 1.0, true)
		canvas.draw_line(Vector2(gap, 0), Vector2(ext, 0), c_dim, 1.0, true)
		canvas.draw_line(Vector2(0, -ext), Vector2(0, -gap), c_dim, 1.0, true)
		canvas.draw_line(Vector2(0, gap), Vector2(0, ext), c_dim, 1.0, true)
	
	# 2. 中心精密准星 (微缩)
	var center_pulse = sin(t * 8.0) * 0.3 + 0.7
	var c_center = Color.from_hsv(hue, 0.2, 1.0, alpha * center_pulse)
	canvas.draw_line(Vector2(-3, 0), Vector2(3, 0), c_center, 1.0, true)
	canvas.draw_line(Vector2(0, -3), Vector2(0, 3), c_center, 1.0, true)
	canvas.draw_rect(Rect2(-5, -5, 10, 10), c_dim, false, 1.0)
	
	# 3. 四角界限标识 (紧贴外壳边缘)
	var corners = [
		Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)
	]
	# 动画：从 r+15 滑入到 r+3
	var corner_dist = r + 3.0 + (1.0 - expand) * 12.0
	var len = 5.0
	for d in corners:
		var origin = d * corner_dist
		var end_x = origin + Vector2(-d.x, 0) * len
		var end_y = origin + Vector2(0, -d.y) * len
		canvas.draw_line(origin, end_x, c_main, 1.5, true)
		canvas.draw_line(origin, end_y, c_main, 1.5, true)
		
		# 4. 迷你高频数据流面板 (减弱存在感，更精致)
		var data_origin = origin + Vector2(d.x * 2.0, d.y * 1.5)
		for j in range(2): # 从 3 行减少到 2 行
			var w = 2.0 + fmod(abs(sin(t * 15.0 + d.x * 11.0 + j * 7.0)), 1.0) * 6.0
			canvas.draw_line(data_origin + Vector2(0, j * 3.0), data_origin + Vector2(w * d.x, j * 3.0), c_main, 1.0, true)

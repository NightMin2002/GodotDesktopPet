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
const STYLE_NAMES := ["关闭", "柔光环", "边缘呼吸", "锁定框"]
const STYLE_COUNT := 4

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
	
	# 缺口间隙 (弧度)
	var gap = 0.4
	# 每段弧的角度范围
	var arc_span = PI / 2.0 - gap * 2.0
	
	# ── 外层: 主题色大弧 (正向慢旋转) ──
	var outer_r = r + 10.0
	var spin1 = t * 0.5
	var outer_color = Color.from_hsv(hue, 0.5, 1.0, alpha * 0.55)
	for i in range(4):
		var start = spin1 + i * PI / 2.0 + gap
		canvas.draw_arc(Vector2.ZERO, outer_r, start, start + arc_span, 24, outer_color, 2.0, true)
		# 弧段端点高光
		var p1 = Vector2(cos(start), sin(start)) * outer_r
		var p2 = Vector2(cos(start + arc_span), sin(start + arc_span)) * outer_r
		canvas.draw_circle(p1, 1.5, Color.from_hsv(hue, 0.3, 1.0, alpha * 0.7), true, -1.0, true)
		canvas.draw_circle(p2, 1.5, Color.from_hsv(hue, 0.3, 1.0, alpha * 0.7), true, -1.0, true)
	
	# ── 内层: 红色小弧 (反向旋转, 与外层交错) ──
	var inner_r = r + 3.0
	var spin2 = -t * 0.7  # 反向 + 不同速度
	var red_color = Color(1.0, 0.3, 0.2, alpha * 0.4)
	for i in range(4):
		var start = spin2 + i * PI / 2.0 + gap
		canvas.draw_arc(Vector2.ZERO, inner_r, start, start + arc_span, 20, red_color, 1.5, true)
	
	# ── 中心十字准星 (呼吸, 红色) ──
	var cross_size = 4.0 * (sin(t * 3.0) * 0.2 + 1.0)
	var cross_color = Color(1.0, 0.35, 0.25, alpha * 0.35)
	canvas.draw_line(Vector2(-cross_size, 0), Vector2(cross_size, 0), cross_color, 1.0, true)
	canvas.draw_line(Vector2(0, -cross_size), Vector2(0, cross_size), cross_color, 1.0, true)

# holo_mode_globe.gd — 全息屏终端网络监控渲染模块 (终极彩蛋/隐藏模式)
# 纯 2D 代码解析的完全 3D 旋转线框地球，附带坐标追踪定位器与独立轨道
class_name HoloModeGlobe extends RefCounted

var screen: PetHoloScreen
var time: float = 0.0

func init() -> void:
	time = 0.0

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var alpha = deploy * 0.8
	var hue = _hue
	
	var base_color = Color.from_hsv(hue, 0.7, 0.9, alpha)
	var glow_color = Color.from_hsv(hue, 0.8, 1.0, alpha * 0.9)
	var dim_color = Color.from_hsv(hue, 0.5, 0.6, alpha * 0.3)
	var back_color = Color.from_hsv(hue, 0.4, 0.4, alpha * 0.05) # 地球背面的线极暗

	pet.draw_polygon(pts, [Color.from_hsv(hue, 0.8, 0.1, alpha * 0.3)])

	var c_uv = Vector2(0.5, 0.45)
	var R = 0.28
	
	# ── 纯2D算力折叠 3D球体投影 ──
	var tilt_x = 0.35 # 全局俯视倾角
	var rot_y = time * -0.6 # 地球持续自转
	
	var project = func(lat: float, lon: float) -> Vector3:
		# 球坐标转 3D 直角坐标
		var x = cos(lat) * sin(lon)
		var y = sin(lat)
		var z = cos(lat) * cos(lon)
		# 地球自转 (绕 Y 轴)
		var rx = x * cos(rot_y) - z * sin(rot_y)
		var rz = x * sin(rot_y) + z * cos(rot_y)
		var ry = y
		# 上帝视角倾斜 (绕 X 轴向下探)
		var p_y = ry * cos(tilt_x) - rz * sin(tilt_x)
		var p_z = ry * sin(tilt_x) + rz * cos(tilt_x)
		return Vector3(rx, p_y, p_z)
		
	# 内部辅助绘图工具：三维线段压平映射到2D画布，自带前后灯光判定
	var draw_3d_line = func(p1: Vector3, p2: Vector3):
		var uv1 = screen._map_uv(pts, c_uv.x + p1.x * R, c_uv.y + p1.y * R)
		var uv2 = screen._map_uv(pts, c_uv.x + p2.x * R, c_uv.y + p2.y * R)
		# 平均深度
		var avg_z = (p1.z + p2.z) * 0.5
		# 如果转到了背面，就以极低的透明度绘制（或者纯粹暗色）
		var c = glow_color if avg_z > 0.0 else back_color
		var w = 1.5 if avg_z > 0.0 else 1.0
		pet.draw_line(uv1, uv2, c, w, true)

	# ── 1. 绘制行星纬线 (横圈) ──
	var lat_bands = 8
	var lon_bands = 16
	for i in range(1, lat_bands):
		var lat = -PI/2.0 + PI * i / lat_bands
		var prev_p = Vector3.ZERO
		for j in range(lon_bands + 1):
			var lon = TAU * j / lon_bands
			var p = project.call(lat, lon)
			if j > 0:
				draw_3d_line.call(prev_p, p)
			prev_p = p

	# ── 2. 绘制行星经线 (竖圈) ──
	for j in range(lon_bands):
		var lon = TAU * j / lon_bands
		var prev_p = Vector3.ZERO
		var segments = 16
		for i in range(segments + 1):
			var lat = -PI/2.0 + PI * i / segments
			var p = project.call(lat, lon)
			if i > 0:
				draw_3d_line.call(prev_p, p)
			prev_p = p

	# ── 3. 卫星轨道环与扫描信号 ──
	# 计算一个存在大角度仰角并独立反向快速旋转的外部监听轨道
	var ring_r = R * 1.3
	var prev_rp = Vector3.ZERO
	var orbit_rot_y = time * 1.5
	var orbit_tilt_z = 0.4
	var orbit_tilt_x = -0.2
	var prj_orbit = func(angle: float) -> Vector3:
		var x = cos(angle)
		var y = 0.0
		var z = sin(angle)
		# 轨道自身飞速自转
		var rx = x * cos(orbit_rot_y) - z * sin(orbit_rot_y)
		var rz = x * sin(orbit_rot_y) + z * cos(orbit_rot_y)
		# 复合倾角扭曲 (Z 和 X 轴双扭)
		var rx2 = rx * cos(orbit_tilt_z) - y * sin(orbit_tilt_z)
		var ry2 = rx * sin(orbit_tilt_z) + y * cos(orbit_tilt_z)
		var rz2 = rz
		
		var ry3 = ry2 * cos(orbit_tilt_x) - rz2 * sin(orbit_tilt_x)
		var rz3 = ry2 * sin(orbit_tilt_x) + rz2 * cos(orbit_tilt_x)
		return Vector3(rx2, ry3, rz3)
		
	# 绘制卫星轨道圈
	for i in range(33):
		var a = i * TAU / 32.0
		var op = prj_orbit.call(a)
		if i > 0:
			var uv1 = screen._map_uv(pts, c_uv.x + prev_rp.x * ring_r, c_uv.y + prev_rp.y * ring_r)
			var uv2 = screen._map_uv(pts, c_uv.x + op.x * ring_r, c_uv.y + op.y * ring_r)
			# 只要转到最底面临界就弱显示
			if (prev_rp.z + op.z) > -1.0:
				pet.draw_line(uv1, uv2, Color(glow_color.r, glow_color.g, glow_color.b, alpha*0.5), 2.0, true)
		prev_rp = op
		
	# 轨道上的机动光点通信器 (极小化聚焦体)
	var sat_p = prj_orbit.call(time * -2.5) # 逆向小圆
	var sat_uv = screen._map_uv(pts, c_uv.x + sat_p.x * ring_r, c_uv.y + sat_p.y * ring_r)
	if sat_p.z > -0.5:
		pet.draw_circle(sat_uv, 3.0, Color.WHITE, true, -1.0, true)
		# 跟本体的一根链接射线
		pet.draw_line(screen._map_uv(pts, c_uv.x, c_uv.y), sat_uv, dim_color, 1.0, true)

	# ── 4. 定位坐标的信号脉冲点阵 ──
	# 随机在星球上绑定几个信标(IP 定位 / 网络入侵节点)
	for i in range(4):
		# 根据 hash 算出一些硬核经纬度
		var target_lat = (float(hash(i*10) & 0xFF)/255.0) * PI - PI/2.0
		var target_lon = (float(hash(i*20) & 0xFF)/255.0) * TAU
		var tp = project.call(target_lat, target_lon)
		
		# 只有球自转到正面时，信标才启动脉冲
		if tp.z > 0.1:  
			var tuv = screen._map_uv(pts, c_uv.x + tp.x * R, c_uv.y + tp.y * R)
			# 发射连续雷达圈
			var r_prog = fmod(time * 1.5 + i * 0.25, 1.0)
			pet.draw_circle(tuv, 2.0 + r_prog * 18.0, Color(glow_color.r, glow_color.g, glow_color.b, alpha * (1.0 - r_prog) * 0.8), false, 1.0, true)
			# 本体核心点
			pet.draw_circle(tuv, 2.0, Color.WHITE, true, -1.0, true)
			# 射出一段锁定射线，直指外天空
			var ex_pt = screen._map_uv(pts, c_uv.x + tp.x * (R*1.4), c_uv.y + tp.y * (R*1.4))
			pet.draw_line(tuv, ex_pt, glow_color, 1.0, true)
			pet.draw_circle(ex_pt, 1.0, glow_color, true, -1.0, true)

	# ── 5. 底部巨型宏观状态占位 ──
	var bar_y = 0.88
	var bar_w = 0.5
	var bar_pts = PackedVector2Array([
		screen._map_uv(pts, 0.5 - bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5, bar_y - 0.02),
		screen._map_uv(pts, 0.5 + bar_w*0.5 - 0.02, bar_y + 0.02),
		screen._map_uv(pts, 0.5 - bar_w*0.5 - 0.02, bar_y + 0.02)
	])
	pet.draw_polygon(bar_pts, [Color(base_color.r, base_color.g, base_color.b, alpha * 0.15)])
	
	# WORLD.MAP.SYNC 文字占位方框 (左、中、右宽细错落)
	for i in range(3):
		var off = (i - 1) * 0.15
		var w = 0.12 if i == 1 else 0.06
		var b_pts = PackedVector2Array([
			screen._map_uv(pts, 0.5 + off - w*0.5, bar_y - 0.01),
			screen._map_uv(pts, 0.5 + off + w*0.5, bar_y - 0.01),
			screen._map_uv(pts, 0.5 + off + w*0.5 - 0.01, bar_y + 0.01),
			screen._map_uv(pts, 0.5 + off - w*0.5 - 0.01, bar_y + 0.01)
		])
		var color = glow_color if (hash(i + int(time*8)) % 10 > 3) else dim_color
		pet.draw_polygon(b_pts, [color])

	# ── 6. 常规四角护甲锚点 ──
	var borders = PackedVector2Array([pts[0], pts[1], pts[1], pts[2], pts[2], pts[3], pts[3], pts[0]])
	pet.draw_multiline(borders, Color(dim_color.r, dim_color.g, dim_color.b, alpha * 0.3), 1.5, true)
	var cc = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.6)
	var cu = 0.08
	var cv = 0.08
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 0, cv), pts[0], screen._map_uv(pts, cu, 0)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1-cu, 0), pts[1], screen._map_uv(pts, 1, cv)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1, 1-cv), pts[2], screen._map_uv(pts, 1-cu, 1)]), cc, 2.0, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, cu, 1), pts[3], screen._map_uv(pts, 0, 1-cv)]), cc, 2.0, true)

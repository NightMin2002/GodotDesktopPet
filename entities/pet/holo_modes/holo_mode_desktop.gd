# holo_mode_desktop.gd — 全息屏桌面监控渲染模块
# 实时捕捉桌面画面并带全息扫描线效果显示在全息屏上
# "桌面观测装置"名副其实 — 它在观测你的桌面
class_name HoloModeDesktop extends RefCounted

var screen: PetHoloScreen
var time: float = 0.0

# ── 截屏配置 ──
const CAPTURE_W := 160      # 截屏目标宽度 (全息屏实际显示~80-160px, 多了浪费)
const CAPTURE_H := 90       # 截屏目标高度 (16:9)
const CAPTURE_INTERVAL_MS := 42  # ~24fps (电影帧率, 流畅且省 CPU)

# ── 运行时状态 ──
var _texture: ImageTexture = null
var _win_mgr = null  # WindowsManager C# 桥接引用
var _capture_started: bool = false
var _cached_img: Image = null

func init() -> void:
	time = 0.0
	_texture = null
	_capture_started = false
	# 获取 C# 桥接
	if _win_mgr == null:
		var main = screen.pet.get_tree().root.get_node_or_null("Main")
		if main and "win_manager" in main:
			_win_mgr = main.win_manager
	# 启动后台截屏线程
	_start_capture()

func render(pts: PackedVector2Array, _hue: float, deploy: float) -> void:
	var pet = screen.pet
	var hue = _hue
	var alpha = deploy * 0.85

	# ── 拉取最新帧 (零阻塞: 有新帧就更新纹理, 没有就用旧的) ──
	if deploy >= 0.8 and _win_mgr != null:
		var pixels = _win_mgr.call("GetCaptureFrame")
		if pixels != null and pixels.size() > 0:
			if _cached_img == null:
				_cached_img = Image.create_from_data(CAPTURE_W, CAPTURE_H, false, Image.FORMAT_RGBA8, pixels)
			else:
				_cached_img.set_data(CAPTURE_W, CAPTURE_H, false, Image.FORMAT_RGBA8, pixels)
			if _cached_img != null:
				if _texture == null:
					_texture = ImageTexture.create_from_image(_cached_img)
				else:
					_texture.update(_cached_img)

	# ── 1. 暗色底板 ──
	pet.draw_polygon(pts, [Color(0.02, 0.03, 0.06, alpha * 0.9)])

	# ── 2. 桌面纹理 (带内边距) ──
	if _texture != null:
		var m = 0.03
		var inner_pts = PackedVector2Array([
			screen._map_uv(pts, m, m),
			screen._map_uv(pts, 1.0 - m, m),
			screen._map_uv(pts, 1.0 - m, 1.0 - m),
			screen._map_uv(pts, m, 1.0 - m),
		])
		var uvs = PackedVector2Array([
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
		])
		pet.draw_polygon(inner_pts, [Color(0.85, 0.9, 1.0, alpha * 0.75)], uvs, _texture)

	# ── 3. 全息扫描线 ──
	var scan_count = 30
	var scan_offset = fmod(time * 0.3, 1.0)
	for i in range(scan_count):
		var v = fmod(float(i) / scan_count + scan_offset, 1.0)
		var p1 = screen._map_uv(pts, 0.02, v)
		var p2 = screen._map_uv(pts, 0.98, v)
		pet.draw_line(p1, p2, Color(hue, 0.3, 0.8, alpha * 0.06), 0.5, true)

	# ── 4. 主扫描光束 ──
	var beam_v = fmod(time * 0.4, 1.2)
	if beam_v < 1.0:
		var bp1 = screen._map_uv(pts, 0.0, beam_v)
		var bp2 = screen._map_uv(pts, 1.0, beam_v)
		pet.draw_line(bp1, bp2, Color.from_hsv(hue, 0.6, 1.0, alpha * 0.3 * (1.0 - beam_v)), 1.5, true)

	# ── 5. 角标装甲 ──
	var cc = Color.from_hsv(hue, 0.7, 0.9, alpha * 0.6)
	var dim = Color.from_hsv(hue, 0.5, 0.6, alpha * 0.25)
	var cu = 0.08
	var cv = 0.08
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 0, cv), pts[0], screen._map_uv(pts, cu, 0)]), cc, 1.5, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1-cu, 0), pts[1], screen._map_uv(pts, 1, cv)]), cc, 1.5, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, 1, 1-cv), pts[2], screen._map_uv(pts, 1-cu, 1)]), cc, 1.5, true)
	pet.draw_polyline(PackedVector2Array([screen._map_uv(pts, cu, 1), pts[3], screen._map_uv(pts, 0, 1-cv)]), cc, 1.5, true)

	# ── 6. 四边框 ──
	pet.draw_multiline(PackedVector2Array([pts[0], pts[1], pts[1], pts[2], pts[2], pts[3], pts[3], pts[0]]), dim, 1.0, true)

	# ── 7. 底部状态标识 ──
	for i in range(4):
		var u = 0.35 + i * 0.08
		var dot_c = cc if (int(time * 2.0) % 4) == i else dim
		pet.draw_circle(screen._map_uv(pts, u, 0.94), 1.5, dot_c, true, -1.0, true)

	# ── 8. "LIVE" 指示灯 ──
	if fmod(time, 1.2) < 0.8:
		var live_pos = screen._map_uv(pts, 0.88, 0.08)
		pet.draw_circle(live_pos, 2.0, Color(0.9, 0.15, 0.1, alpha * 0.8), true, -1.0, true)
		pet.draw_circle(live_pos, 4.0, Color(0.9, 0.15, 0.1, alpha * 0.15), true, -1.0, true)

# ── 后台截屏控制 ──

func _start_capture() -> void:
	if _win_mgr == null or _capture_started:
		return
	_win_mgr.call("StartCapture", CAPTURE_W, CAPTURE_H, CAPTURE_INTERVAL_MS)
	_capture_started = true

func stop_capture() -> void:
	if _win_mgr == null or not _capture_started:
		return
	_win_mgr.call("StopCapture")
	_capture_started = false

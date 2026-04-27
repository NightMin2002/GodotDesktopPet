# hud_panel.gd — 统一 HUD 悬浮面板
# 宠物侧边的紧凑信息卡片，整合所有 HUD 小组件
# 当前组件: 时钟、WiFi  |  可扩展: CPU、内存、电量等
class_name HudPanel
extends RefCounted

var pet: RigidBody2D
var panel: PanelContainer

# ── 组件开关 ──
var clock_enabled: bool = false
var wifi_enabled: bool = false

# ── 时钟组件 ──
var _clock_label: Label
var _clock_row: HBoxContainer
var _bounce_time: float = 0.0

# ── WiFi 组件 ──
var _wifi_label: Label
var _wifi_dot: Label
var _wifi_row: Control  # Button
var _wifi_refresh_timer: float = 0.0
var _wifi_pending: String = ""  # 线程安全缓冲区
var _wifi_pending_connected: bool = false
var _wifi_has_pending: bool = false  # 原子标志: 后台线程写入, 主线程读取+清除
const WIFI_REFRESH_INTERVAL := 15.0

var _menu_hidden: bool = false  # 被右键菜单遮挡时临时隐藏

func init(p: RigidBody2D) -> void:
	pet = p
	_build_panel()
	EventBus.context_menu_toggled.connect(_on_menu_toggled)

func _on_menu_toggled(is_open: bool) -> void:
	if not (clock_enabled or wifi_enabled):
		return
	_menu_hidden = is_open
	if is_open:
		var tw = pet.create_tween()
		tw.tween_property(panel, "modulate:a", 0.0, 0.15)
	else:
		var tw = pet.create_tween()
		tw.tween_property(panel, "modulate:a", 1.0, 0.25)

# ── 构建 UI ──

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.top_level = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.18, 0.9)
	var border_hue = fmod(0.13 + pet.clone_hue_shift, 1.0)
	style.border_color = Color.from_hsv(border_hue, 0.6, 0.9, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)
	
	_build_clock_row(vbox)
	_build_wifi_row(vbox)
	
	pet.add_child(panel)

func _build_clock_row(parent: VBoxContainer) -> void:
	_clock_row = HBoxContainer.new()
	_clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_row.add_theme_constant_override("separation", 6)
	_clock_row.visible = false
	parent.add_child(_clock_row)
	
	# 时钟标签
	var clock_tag = Label.new()
	clock_tag.text = "TIME"
	clock_tag.add_theme_font_size_override("font_size", 9)
	clock_tag.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.6))
	clock_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_row.add_child(clock_tag)
	
	_clock_label = Label.new()
	_clock_label.text = "00:00:00"
	_clock_label.add_theme_font_size_override("font_size", 15)
	_clock_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.95))
	_clock_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.3))
	_clock_label.add_theme_constant_override("outline_size", 1)
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_row.add_child(_clock_label)

func _build_wifi_row(parent: VBoxContainer) -> void:
	# 普通容器行 (和时钟行一致的结构，确保面板自动撑开)
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = "点击打开网络设置"
	row.add_theme_constant_override("separation", 6)
	row.visible = false
	row.gui_input.connect(_on_wifi_row_input)
	_wifi_row = row
	parent.add_child(row)
	
	# 连接状态指示点
	_wifi_dot = Label.new()
	_wifi_dot.text = "\u25cf"
	_wifi_dot.add_theme_font_size_override("font_size", 10)
	_wifi_dot.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4, 0.9))
	_wifi_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_wifi_dot)
	
	var wifi_tag = Label.new()
	wifi_tag.text = "WiFi"
	wifi_tag.add_theme_font_size_override("font_size", 11)
	wifi_tag.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.7))
	wifi_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(wifi_tag)
	
	_wifi_label = Label.new()
	_wifi_label.text = "..."
	_wifi_label.add_theme_font_size_override("font_size", 13)
	_wifi_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.95))
	_wifi_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_wifi_label)

# ── 组件开关控制 ──

func set_clock(on: bool) -> void:
	clock_enabled = on
	if is_instance_valid(_clock_row):
		_clock_row.visible = on
	_refresh_panel_visibility()

func set_wifi(on: bool) -> void:
	wifi_enabled = on
	if is_instance_valid(_wifi_row):
		_wifi_row.visible = on
	if on:
		_wifi_refresh_timer = 0.0
		_refresh_wifi_async()
	_refresh_panel_visibility()

## 任意组件开启 → 面板显示；全部关闭 → 面板隐藏
func _refresh_panel_visibility() -> void:
	var should_show = clock_enabled or wifi_enabled
	if should_show and not panel.visible:
		panel.modulate.a = 0.0
		panel.visible = true
		_snap_position()
		var tw = pet.create_tween()
		tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	elif not should_show and panel.visible:
		var tw = pet.create_tween()
		tw.tween_property(panel, "modulate:a", 0.0, 0.2)
		tw.tween_callback(func(): panel.visible = false)

# ── 主更新 ──

func update(delta: float) -> void:
	if not panel.visible:
		return
	
	if clock_enabled:
		_update_clock(delta)
	
	if wifi_enabled:
		# 检查后台线程结果
		if _wifi_has_pending:
			_wifi_has_pending = false
			_wifi_label.text = _wifi_pending
			var color = Color(0.3, 0.8, 0.4, 0.9) if _wifi_pending_connected else Color(0.8, 0.3, 0.3, 0.9)
			_wifi_dot.add_theme_color_override("font_color", color)
		# 定时刷新
		_wifi_refresh_timer += delta
		if _wifi_refresh_timer >= WIFI_REFRESH_INTERVAL:
			_wifi_refresh_timer = 0.0
			_refresh_wifi_async()
	
	_update_position(delta)

func _update_clock(_delta: float) -> void:
	_bounce_time += _delta * 2.0
	var time_dict = Time.get_time_dict_from_system()
	_clock_label.text = "%02d:%02d:%02d" % [time_dict.hour, time_dict.minute, time_dict.second]

# ── 定位 ──

func _snap_position() -> void:
	if is_instance_valid(panel):
		panel.position = _calc_target_pos()

func _update_position(delta: float) -> void:
	panel.position = panel.position.lerp(_calc_target_pos(), delta * 8.0)

func _calc_target_pos() -> Vector2:
	var pet_pos = pet.global_position
	var vp = pet.get_viewport_rect().size
	var panel_size = panel.get_combined_minimum_size()
	
	# 宠物在屏幕右半边 → 面板放左边，否则放右边
	var side_x: float
	if pet_pos.x > vp.x * 0.5:
		side_x = pet_pos.x - panel_size.x - pet.PET_RADIUS - 18.0
	else:
		side_x = pet_pos.x + pet.PET_RADIUS + 18.0
	
	var center_y = pet_pos.y - panel_size.y / 2.0
	
	side_x = clampf(side_x, 8, vp.x - panel_size.x - 8)
	center_y = clampf(center_y, 8, vp.y - panel_size.y - 8)
	
	return Vector2(side_x, center_y)

# ── WiFi 数据 ──

func _refresh_wifi_async() -> void:
	WorkerThreadPool.add_task(_wifi_worker)

## 后台线程: 执行 PowerShell 查询 (不在主线程, 零卡顿)
func _wifi_worker() -> void:
	var output = []
	var args = PackedStringArray([
		"-NoProfile", "-Command",
		"(Get-NetConnectionProfile | Where-Object {$_.InterfaceAlias -match 'Wi-Fi|WLAN|Wireless'} | Select-Object -First 1).Name"
	])
	var code = OS.execute("powershell", args, output, false, false)
	
	if code == 0 and output.size() > 0:
		var ssid = output[0].strip_edges()
		if ssid.length() > 0:
			_wifi_pending = ssid
			_wifi_pending_connected = true
			_wifi_has_pending = true
			return
	
	_wifi_pending = "未连接"
	_wifi_pending_connected = false
	_wifi_has_pending = true

func _on_wifi_row_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		OS.shell_open("ms-settings:network-wifi")

# ── 命中区域 ──

func get_panel_rect() -> Rect2:
	if panel.visible and is_instance_valid(panel):
		return Rect2(panel.position, panel.get_combined_minimum_size()).grow(5)
	return Rect2()

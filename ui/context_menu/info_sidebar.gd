# info_sidebar.gd — 信息侧栏子系统 (RefCounted)
# 负责: 日期/时钟/WiFi/电池/开机时长 的 UI 构建与异步查询
# 从 context_menu.gd 拆分，由主控制器持有引用并在 _process 中调度
extends RefCounted

var _menu  # context_menu 引用 (CanvasLayer)
var panel: PanelContainer
var _date_label: Label
var _time_label: Label
var _rows: Dictionary = {}  # key -> Label (值标签)
var _sysinfo_pending: Dictionary = {}
var _sysinfo_has_pending: bool = false
var _sysinfo_query_running: bool = false
var _boot_timestamp: float = 0.0

func _init(menu_ref) -> void:
	_menu = menu_ref

# ── UI 构建 ──

func build() -> void:
	panel = PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.1, 0.92)
	style.border_color = Color.from_hsv(EventBus.ui_hue, 0.8, 1.0, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", style)
	_menu.add_child(panel)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)
	# 日期
	_date_label = Label.new()
	_date_label.add_theme_font_size_override("font_size", 14)
	_date_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.95, 0.7))
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_date_label)
	# 时钟
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 28)
	_time_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.95))
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_time_label)
	vbox.add_child(_make_sep())
	# 信息行
	_add_row(vbox, "wifi", "●", "WiFi", Color(0.3, 0.8, 0.4))
	_add_row(vbox, "battery", "■", "电池", Color(0.4, 0.85, 0.3))
	_add_row(vbox, "uptime", "▲", "开机", Color(0.6, 0.7, 0.85))
	vbox.add_child(_make_sep())
	_add_row(vbox, "cpu", "◆", "CPU", Color(0.85, 0.55, 0.3))
	_add_row(vbox, "ram", "◆", "RAM", Color(0.7, 0.45, 0.85))

func _add_row(parent: VBoxContainer, key: String, icon: String, tag: String, color: Color) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var dot = Label.new()
	dot.text = icon
	dot.add_theme_font_size_override("font_size", 9)
	dot.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.8))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)
	var tag_lbl = Label.new()
	tag_lbl.text = tag
	tag_lbl.add_theme_font_size_override("font_size", 11)
	tag_lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.55))
	tag_lbl.custom_minimum_size.x = 32
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag_lbl)
	var val_lbl = Label.new()
	val_lbl.text = "..."
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.add_theme_color_override("font_color", Color(0.7, 0.82, 0.95, 0.85))
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(val_lbl)
	_rows[key] = val_lbl

func _make_sep() -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var s = StyleBoxFlat.new()
	s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.8, 1.0, 0.15)
	s.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", s)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

# ── 刷新与更新 ──

func refresh() -> void:
	var d = Time.get_date_dict_from_system()
	var weekdays = ["日", "一", "二", "三", "四", "五", "六"]
	var wd = weekdays[d.weekday % 7]
	_date_label.text = "%d年%02d月%02d日 周%s" % [d.year, d.month, d.day, wd]
	update_time()
	update_uptime()

func update_time() -> void:
	var t = Time.get_time_dict_from_system()
	_time_label.text = "%02d:%02d:%02d" % [t.hour, t.minute, t.second]

func update_uptime() -> void:
	if _boot_timestamp <= 0.0:
		return
	var now = Time.get_unix_time_from_system()
	var elapsed = int(now - _boot_timestamp)
	@warning_ignore("integer_division")
	var hours = elapsed / 3600
	@warning_ignore("integer_division")
	var minutes = (elapsed % 3600) / 60
	if "uptime" in _rows:
		_rows["uptime"].text = "%dh %dm" % [hours, minutes]

func update_position(hud: PanelContainer) -> void:
	if not panel.visible:
		return
	var info_w = panel.size.x if panel.size.x > 0 else 120.0
	var info_h = panel.size.y if panel.size.y > 0 else 200.0
	var vp = _menu.get_viewport().get_visible_rect().size
	var gap := 6.0
	var x: float
	if _menu._menu_side == 1:
		# 菜单在宠物右侧 → 侧栏放菜单更右侧 (远离宠物)
		x = hud.position.x + hud.size.x + gap
		if x + info_w > vp.x - 4.0:
			# 放不下再退回菜单左边
			x = hud.position.x - info_w - gap
	else:
		# 菜单在宠物左侧 → 侧栏放菜单更左侧 (远离宠物)
		x = hud.position.x - info_w - gap
		if x < 4.0:
			x = hud.position.x + hud.size.x + gap
	# Y 坐标: 与菜单对齐，但限制在屏幕范围内
	var y = clampf(hud.position.y, 4.0, vp.y - info_h - 4.0)
	panel.position = Vector2(x, y)

# ── 异步查询 ──

func query() -> void:
	if _sysinfo_query_running:
		return
	for key in ["wifi", "battery", "cpu", "ram"]:
		if key in _rows: _rows[key].text = "..."
	if _boot_timestamp <= 0.0 and "uptime" in _rows:
		_rows["uptime"].text = "..."
	_sysinfo_query_running = true
	WorkerThreadPool.add_task(_sysinfo_task)

# WiFi SSID 修正: .Name 返回配置文件名(可能带数字后缀), 需用 netsh wlan show profiles 反向匹配真实 SSID
const _PS_SIDEBAR := "$w=(Get-NetConnectionProfile|?{$_.InterfaceAlias -match 'Wi-Fi|WLAN|Wireless'}|Select -First 1).Name;if($w){$ss=@();(netsh wlan show profiles 2>$null)|%{if($_ -match ' : (.+)$'){$ss+=$Matches[1].Trim()}};foreach($s in ($ss|Sort-Object Length -Desc)){if($w.StartsWith($s)){$w=$s;break}}}else{$w='N/A'};$b=Get-CimInstance Win32_Battery;if($b){$bp=$b.EstimatedChargeRemaining.ToString()+'%';if($b.BatteryStatus-eq 2){$bp+=' 充电中'}}else{$bp='无电池'};Write-Host wifi=$w;Write-Host battery=$bp;$cl=(Get-CimInstance Win32_Processor|Select-Object -First 1).LoadPercentage;Write-Host cpu=$cl%;$os=Get-CimInstance Win32_OperatingSystem;$ru=[math]::Round(($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)*100/$os.TotalVisibleMemorySize);Write-Host ram=$ru%"
const _PS_BOOT_TIME := "[int](([DateTimeOffset](Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToUnixTimeSeconds())"

func _sysinfo_task() -> void:
	var out: Array = []
	OS.execute("powershell", ["-NoProfile", "-Command", _PS_SIDEBAR], out, true, false)
	var result: Dictionary = {}
	if out.size() > 0:
		for line in out[0].strip_edges().split("\n"):
			line = line.strip_edges()
			var eq = line.find("=")
			if eq > 0:
				result[line.substr(0, eq)] = line.substr(eq + 1)
	if _boot_timestamp <= 0.0:
		out = []
		OS.execute("powershell", ["-NoProfile", "-Command", _PS_BOOT_TIME], out, true, false)
		if out.size() > 0:
			var ts = out[0].strip_edges()
			if ts.is_valid_int():
				result["_boot_ts"] = ts
	_sysinfo_pending = result
	_sysinfo_has_pending = true
	_sysinfo_query_running = false

## 主线程调用: 消费异步结果
func apply_pending() -> void:
	if not _sysinfo_has_pending:
		return
	_sysinfo_has_pending = false
	for key in _sysinfo_pending:
		if key == "_boot_ts":
			_boot_timestamp = float(_sysinfo_pending[key])
		elif key in _rows:
			_rows[key].text = _sysinfo_pending[key]
	update_uptime()

## 是否有待处理的异步结果
func has_pending() -> bool:
	return _sysinfo_has_pending

## UI 主题色运行时更新
func apply_ui_theme(hue: float) -> void:
	var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style = style.duplicate()
		style.border_color = Color.from_hsv(hue, 0.8, 1.0, 0.5)
		panel.add_theme_stylebox_override("panel", style)

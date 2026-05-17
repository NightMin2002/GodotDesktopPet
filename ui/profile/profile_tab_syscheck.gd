# profile_tab_syscheck.gd — 机体诊断 Tab (装置终端)
# 异步查询系统硬件信息，以符合宠物人设的白话风格展示，采用高科幻机甲卡片布局
extends HBoxContainer

var _content_box: VBoxContainer
var _scan_btn: Button
var _status_lbl: Label
var _scanning: bool = false
var _screen_res: String = ""

var _pending_result: Dictionary = {}
var _has_pending: bool = false

class CyberCard extends MarginContainer:
	var is_hovered: bool = false
	var hover_t: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		clip_contents = false
		add_theme_constant_override("margin_left", 16)
		add_theme_constant_override("margin_right", 16)
		add_theme_constant_override("margin_top", 16)
		add_theme_constant_override("margin_bottom", 16)
		mouse_entered.connect(func(): is_hovered = true; set_process(true); queue_redraw())
		mouse_exited.connect(func(): is_hovered = false; queue_redraw())

	func _process(delta: float) -> void:
		var needs_redraw = false
		if is_hovered:
			if hover_t < 1.0: hover_t = min(hover_t + delta * 6.0, 1.0)
			needs_redraw = true
		else:
			if hover_t > 0.0: hover_t = max(hover_t - delta * 5.0, 0.0)
			else: set_process(false)
			needs_redraw = true
		if needs_redraw: queue_redraw()

	func _draw() -> void:
		var rect = Rect2(Vector2.ZERO, size)
		var ui_hue = EventBus.ui_hue
		var base_bg = Color.from_hsv(ui_hue, 0.15, 0.08, 0.4)
		var hover_bg = Color.from_hsv(ui_hue, 0.25, 0.15, 0.6)
		draw_rect(rect, base_bg.lerp(hover_bg, hover_t))
		
		var dim_line = Color.from_hsv(ui_hue, 0.3, 0.4, 0.3)
		draw_rect(rect, dim_line, false, 1.0)
		
		if hover_t > 0.0:
			var mouse_pos = get_local_mouse_position()
			var accent = Color.from_hsv(ui_hue, 0.5, 0.9, 0.85 * hover_t)
			var offset = 6.0 * (1.0 - hover_t)
			var length = 12.0 + 4.0 * hover_t
			var th = 1.5
			draw_polyline(PackedVector2Array([ Vector2(-offset, length - offset), Vector2(-offset, -offset), Vector2(length - offset, -offset) ]), accent, th)
			draw_polyline(PackedVector2Array([ Vector2(size.x - length + offset, -offset), Vector2(size.x + offset, -offset), Vector2(size.x + offset, length - offset) ]), accent, th)
			draw_polyline(PackedVector2Array([ Vector2(-offset, size.y - length + offset), Vector2(-offset, size.y + offset), Vector2(length - offset, size.y + offset) ]), accent, th)
			draw_polyline(PackedVector2Array([ Vector2(size.x - length + offset, size.y + offset), Vector2(size.x + offset, size.y + offset), Vector2(size.x + offset, size.y - length + offset) ]), accent, th)
			
			if is_hovered:
				var mx = clamp(mouse_pos.x, 0, size.x)
				var my = clamp(mouse_pos.y, 0, size.y)
				var line_len = 16.0
				var x_start = clamp(mx - line_len, 0, size.x)
				var x_end = clamp(mx + line_len, 0, size.x)
				var y_start = clamp(my - line_len, 0, size.y)
				var y_end = clamp(my + line_len, 0, size.y)
				draw_line(Vector2(x_start, 0), Vector2(x_end, 0), accent, 2.0)
				draw_line(Vector2(x_start, size.y), Vector2(x_end, size.y), accent, 2.0)
				draw_line(Vector2(0, y_start), Vector2(0, y_end), accent, 2.0)
				draw_line(Vector2(size.x, y_start), Vector2(size.x, y_end), accent, 2.0)

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	var scroll = ProfileStyles.make_tab_scroll()
	# 关键修复：隐藏原生垂直滚动条，完全依赖赛博指示器
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(margin)

	_content_box = ProfileStyles.make_tab_vbox(16)
	margin.add_child(_content_box)

	_build_header()

	var cols = HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	cols.set_meta("cols", true)
	_content_box.add_child(cols)

	var left_col = ProfileStyles.make_tab_vbox(16)
	left_col.set_meta("col", "left")
	cols.add_child(left_col)

	var right_col = ProfileStyles.make_tab_vbox(16)
	right_col.set_meta("col", "right")
	cols.add_child(right_col)
	
	_build_idle()

	var indicator = preload("res://ui/profile/cyber_scroll_indicator.gd").new()
	indicator.bind_scroll(scroll)
	add_child(indicator)

func refresh() -> void:
	if not _scanning and not _has_pending and not _is_rendered():
		_start_scan()

func _is_rendered() -> bool:
	for child in _content_box.get_children():
		if child.has_meta("cols"):
			var l = child.get_child(0)
			for item in l.get_children():
				if item.has_meta("dyn_card"): return true
	return false

func _build_header() -> void:
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_box.add_child(header)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(vb)

	var title = ProfileStyles.title_label("机体诊断", 20)
	vb.add_child(title)

	var desc = ProfileStyles.label_dim("本机已接入系统总线。将提取宿主机硬件状态报告。")
	vb.add_child(desc)

	_scan_btn = Button.new()
	_scan_btn.text = "启动检索"
	_scan_btn.custom_minimum_size = Vector2(100, 0)
	_scan_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_scan_btn.add_theme_font_size_override("font_size", 13)
	_scan_btn.add_theme_color_override("font_color", ProfileStyles.bright())
	_scan_btn.mouse_filter = Control.MOUSE_FILTER_PASS

	var s_norm = ProfileStyles.small_btn_normal()
	s_norm.content_margin_left = 16; s_norm.content_margin_right = 16
	s_norm.content_margin_top = 8; s_norm.content_margin_bottom = 8
	_scan_btn.add_theme_stylebox_override("normal", s_norm)
	
	var s_hov = ProfileStyles.small_btn_hover()
	s_hov.content_margin_left = 16; s_hov.content_margin_right = 16
	s_hov.content_margin_top = 8; s_hov.content_margin_bottom = 8
	_scan_btn.add_theme_stylebox_override("hover", s_hov)
	_scan_btn.add_theme_stylebox_override("pressed", s_hov)
	
	_scan_btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			_start_scan()
	)
	var center = CenterContainer.new()
	center.add_child(_scan_btn)
	header.add_child(center)

func _get_col(lr: String) -> VBoxContainer:
	for child in _content_box.get_children():
		if child.has_meta("cols"):
			for col in child.get_children():
				if col.get_meta("col") == lr:
					return col
	return null

func _build_idle() -> void:
	var l = _get_col("left")
	if not l: return
	for child in l.get_children(): child.queue_free()
	var c = _build_cyber_card("SYS_INFO", "等待指令", l, true)
	_status_lbl = ProfileStyles.label_dim("尚未获取授权。点击按钮开启状态同步。")
	c.add_child(_status_lbl)

func _build_cyber_card(sub_title: String, main_title: String, parent_col: Control, is_idle: bool = false) -> VBoxContainer:
	var card = CyberCard.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("dyn_card", true)
	parent_col.add_child(card)

	var group = ProfileStyles.make_tab_vbox(12)
	card.add_child(group)

	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim(sub_title + " //", 11))
	title_row.add_child(ProfileStyles.value_label(main_title, 15))
	group.add_child(title_row)

	var hsep = HSeparator.new()
	hsep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	hsep.add_theme_constant_override("separation", 1)
	group.add_child(hsep)

	return group

func _add_kv(parent: Control, key: String, val: String, warn: bool = false, crit: bool = false, highlight: bool = false, progress_pct: float = -1.0) -> void:
	var bg = PanelContainer.new()
	var bg_s = StyleBoxFlat.new()
	bg_s.bg_color = Color(0,0,0,0)
	bg.add_theme_stylebox_override("panel", bg_s)
	parent.add_child(bg)
	
	if progress_pct >= 0.0:
		bg.draw.connect(func():
			var w = bg.size.x * clampf(progress_pct, 0.0, 1.0)
			var p_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.7, 0.15)
			if crit: p_color = Color(0.9, 0.25, 0.25, 0.22)
			elif warn: p_color = Color(0.9, 0.65, 0.2, 0.18)
			bg.draw_rect(Rect2(0, 0, w, bg.size.y), p_color)
			if w > 1: bg.draw_line(Vector2(w - 1, 0), Vector2(w - 1, bg.size.y), p_color * Color(1,1,1,1.5), 2.0)
		)
		bg.resized.connect(bg.queue_redraw)
	
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	bg.add_child(row)

	var deco = ColorRect.new()
	deco.custom_minimum_size = Vector2(2, 0)
	deco.color = Color.from_hsv(EventBus.ui_hue, 0.8, 0.9, 0.8) if highlight else Color.from_hsv(EventBus.ui_hue, 0.4, 0.4, 0.4)
	if crit: deco.color = Color(0.9, 0.35, 0.35, 0.9)
	elif warn: deco.color = Color(0.9, 0.7, 0.25, 0.9)
	row.add_child(deco)

	var k_lbl = ProfileStyles.make_label(key, 12, ProfileStyles.accent())
	k_lbl.custom_minimum_size = Vector2(56, 0)
	if highlight: k_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(k_lbl)

	var c = ProfileStyles.val_color()
	if highlight: c = ProfileStyles.bright()
	if crit: c = Color(0.9, 0.35, 0.35, 1.0)
	elif warn: c = Color(0.9, 0.7, 0.25, 1.0)

	var v_lbl = ProfileStyles.make_label(val, 12, c)
	if highlight: v_lbl.add_theme_font_size_override("font_size", 13)
	v_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v_lbl)
	
	bg.mouse_filter = Control.MOUSE_FILTER_PASS
	bg.mouse_entered.connect(func(): bg_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.8, 0.08))
	bg.mouse_exited.connect(func(): bg_s.bg_color = Color(0,0,0,0))

func _start_scan() -> void:
	if _scanning:
		return
	_scanning = true
	
	if is_instance_valid(_scan_btn):
		var s = ProfileStyles.small_btn_normal()
		s.border_color = Color.from_hsv(EventBus.ui_hue, 0.8, 0.9)
		s.content_margin_left = 16; s.content_margin_right = 16
		s.content_margin_top = 8; s.content_margin_bottom = 8
		_scan_btn.add_theme_stylebox_override("normal", s)
		_scan_btn.text = "数据采集中..."
	
	if is_instance_valid(_status_lbl):
		_status_lbl.text = "数据已接入...正在提取本地拓扑..."
		_status_lbl.add_theme_color_override("font_color", ProfileStyles.accent())

	var screen = DisplayServer.screen_get_size()
	_screen_res = "%d x %d" % [screen.x, screen.y]
	WorkerThreadPool.add_task(_query_task)

func _process(_delta: float) -> void:
	if _has_pending:
		_has_pending = false
		_scanning = false
		_render_results(_pending_result)
		if is_instance_valid(_scan_btn):
			_scan_btn.text = "更新数据"
			_scan_btn.remove_theme_stylebox_override("normal")

func _render_results(r: Dictionary) -> void:
	var l_col = _get_col("left")
	var r_col = _get_col("right")
	if not l_col or not r_col: return
	
	for child in l_col.get_children() + r_col.get_children():
		if child.has_meta("dyn_card"):
			child.queue_free()
	
	for child in _content_box.get_children():
		if child.has_meta("dyn_ts"):
			child.queue_free()
	
	var host = r.get("host", "?")
	var user = r.get("user", "?")
	var os_info = r.get("os", "?")
	var cpu = r.get("cpu", "?").replace(" with Radeon Graphics", "")
	var cores = r.get("cores", "?")
	var freq = r.get("freq", "?")
	var gpu = r.get("gpu", "?")
	var ram = r.get("ram", "?")
	var mobo = r.get("mobo", "?")
	var mon = r.get("mon", "N/A")
	var ip = r.get("ip", "N/A")
	var disk = r.get("disk", "?")
	var uptime_str = r.get("uptime", "?")
	var bat_pct = r.get("bat", "")
	var bat_status = r.get("bstat", "0")

	var up_text = uptime_str
	var boot_time = "?"
	if uptime_str != "?":
		var up_min = uptime_str.to_int()
		if up_min >= 60:
			up_text = "%d 小时 %d 分钟" % [up_min / 60, up_min % 60]
		else:
			up_text = "%d 分钟" % up_min
		var now_unix = Time.get_unix_time_from_system()
		var boot_unix = now_unix - up_min * 60
		var tz = Time.get_time_zone_from_system()
		var bd = Time.get_datetime_dict_from_unix_time(int(boot_unix) + tz.bias * 60)
		boot_time = "%04d.%02d.%02d %02d:%02d" % [bd.year, bd.month, bd.day, bd.hour, bd.minute]
		
	var freq_text = freq
	if freq != "?":
		var mhz = freq.to_float()
		freq_text = "%.1f GHz" % (mhz / 1000.0)

	# 左侧栏 Card 1: 核心配置
	var c_core = _build_cyber_card("CORE", "核心配置", l_col)
	_add_kv(c_core, "处理器", "%s  (基频 %s)" % [cpu, freq_text])
	_add_kv(c_core, "核心数", cores)
	_add_kv(c_core, "显卡", gpu)
	_add_kv(c_core, "内存", ram + " GB")
	_add_kv(c_core, "主板", mobo)

	# 左侧栏 Card 2: 存储状况
	var c_disk = _build_cyber_card("STORAGE", "存储状况", l_col)
	var has_disks = false
	var total_all_gb = 0
	var used_all_gb = 0
	for part in disk.split("|"):
		part = part.strip_edges()
		if part == "": continue
		var segs = part.split(":")
		if segs.size() < 3: continue
		var free_gb = segs[1].to_int()
		var total_gb = segs[2].to_int()
		total_all_gb += total_gb
		used_all_gb += (total_gb - free_gb)
			
	if total_all_gb > 0:
		var pct_int = (used_all_gb * 100 / total_all_gb)
		var pct_float = float(used_all_gb) / float(total_all_gb)
		var warn = pct_int > 70 and pct_int <= 90
		var crit = pct_int > 90
		_add_kv(c_disk, "总容量", "已部署 %d GB / 总配额 %d GB  (%d%% 占用)" % [used_all_gb, total_all_gb, pct_int], warn, crit, true, pct_float)
		
		# separator line between aggregate and disks
		var sep = HSeparator.new()
		sep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
		sep.add_theme_constant_override("separation", 4)
		c_disk.add_child(sep)

	for part in disk.split("|"):
		part = part.strip_edges()
		if part == "": continue
		var segs = part.split(":")
		if segs.size() < 3:
			_add_kv(c_disk, "磁盘", part)
			has_disks = true
			continue
		var drive = segs[0]
		var free_gb = segs[1].to_int()
		var total_gb = segs[2].to_int()
		var free_pct = (free_gb * 100 / total_gb) if total_gb > 0 else 0
		var used_pct_float = (1.0 - float(free_gb)/float(total_gb)) if total_gb > 0 else 0.0
		var warn = free_pct < 30 and free_pct >= 10
		var crit = free_pct < 10
		_add_kv(c_disk, "%s 盘" % drive, "剩余 %d GB / 共 %d GB  (%d%% 空闲)" % [free_gb, total_gb, free_pct], warn, crit, false, used_pct_float)
		has_disks = true
	if not has_disks:
		_add_kv(c_disk, "阵列", "读取失败")

	# 右侧栏 Card 3: 运行状态
	var c_env = _build_cyber_card("ENV", "运行状态", r_col)
	_add_kv(c_env, "设备名", host)
	_add_kv(c_env, "操作员", user)
	_add_kv(c_env, "系统", os_info)
	_add_kv(c_env, "显示器", mon + "  /  " + _screen_res)
	_add_kv(c_env, "局域网", ip)
	_add_kv(c_env, "开机时长", up_text)
	_add_kv(c_env, "开机时间", boot_time)
	
	if bat_pct != "" and bat_pct != "N/A":
		var bp = bat_pct.to_int()
		var charging = " (正在充能)" if bat_status == "2" else ""
		_add_kv(c_env, "电池", "%s%%%s" % [bat_pct, charging], bp < 50 and bp >= 20, bp < 20)

	var t = Time.get_datetime_dict_from_system()
	var ts = "%04d.%02d.%02d %02d:%02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	var ts_lbl = ProfileStyles.label_dim("报告生成于 " + ts)
	ts_lbl.set_meta("dyn_ts", true)
	r_col.add_child(ts_lbl)


# ═══════════════════════════════════════════════
#  后台查询 (在工作线程执行)
# ═══════════════════════════════════════════════

const _PS_SCRIPT := "$h=$env:COMPUTERNAME;$u=$env:USERNAME;$o=Get-CimInstance Win32_OperatingSystem;$osN=$o.Caption -replace 'Microsoft ','';$p=Get-CimInstance Win32_Processor|Select-Object -First 1;$cpu=$p.Name;$cores=$p.NumberOfCores.ToString()+'C / '+$p.NumberOfLogicalProcessors.ToString()+'T';$freq=$p.MaxClockSpeed;$g=Get-CimInstance Win32_VideoController|Where-Object{$_.Name -notmatch 'Virtual|MuMu|GameViewer'};$nv=$g|Where-Object{$_.Name -match 'NVIDIA|GeForce|RTX|GTX'};$gpu=if($nv){($nv|Select-Object -First 1).Name}else{($g|Select-Object -First 1).Name};$used=[math]::Round(($o.TotalVisibleMemorySize-$o.FreePhysicalMemory)/1MB,1);$total=[math]::Round($o.TotalVisibleMemorySize/1MB,1);$mb=Get-CimInstance Win32_BaseBoard|Select-Object -First 1;$mobo=$mb.Manufacturer+' '+$mb.Product;$ip=(Get-NetIPAddress -AddressFamily IPv4|Where-Object{$_.InterfaceAlias -notmatch 'Loopback|vEthernet|Radmin|FlClash|VPN|Bluetooth' -and $_.InterfaceAlias -notlike '*蓝牙*' -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '198.18.*'}|Select-Object -First 1).IPAddress;if(!$ip){$ip='N/A'};$disks=Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'|ForEach-Object{($_.DeviceID -replace ':','')+':'+[math]::Round($_.FreeSpace/1GB).ToString()+':'+[math]::Round($_.Size/1GB).ToString()};$boot=$o.LastBootUpTime;$upMin=[math]::Round(((Get-Date)-$boot).TotalMinutes);$bat=try{(Get-CimInstance Win32_Battery -ErrorAction Stop|Select-Object -First 1)}catch{$null};$bp=if($bat){$bat.EstimatedChargeRemaining}else{'N/A'};$bs=if($bat){$bat.BatteryStatus}else{0};Write-Host host=$h;Write-Host user=$u;Write-Host os=$osN;Write-Host cpu=$cpu;Write-Host cores=$cores;Write-Host freq=$freq;Write-Host gpu=$gpu;Write-Host ram=$used/$total;Write-Host mobo=$mobo;Write-Host ip=$ip;Write-Host disk=($disks -join '|');Write-Host uptime=$upMin;Write-Host bat=$bp;Write-Host bstat=$bs"

func _query_task() -> void:
	var r: Dictionary = {}
	var out: Array = []
	OS.execute("powershell", ["-NoProfile", "-Command", _PS_SCRIPT], out, true, false)
	if out.size() > 0:
		for line in out[0].strip_edges().split("\n"):
			line = line.strip_edges()
			var eq = line.find("=")
			if eq > 0:
				r[line.substr(0, eq)] = line.substr(eq + 1)
				
	var mon_out: Array = []
	OS.execute("powershell", ["-NoProfile", "-Command",
		"try{$m=Get-CimInstance WmiMonitorID -Namespace root/wmi -ErrorAction Stop|Select-Object -First 1;$n=($m.UserFriendlyName|Where-Object{$_ -ne 0}|ForEach-Object{[char]$_}) -join '';$mf=($m.ManufacturerName|Where-Object{$_ -ne 0}|ForEach-Object{[char]$_}) -join '';Write-Host mon=$mf $n}catch{Write-Host mon=N/A}"],
		mon_out, true, false)
	if mon_out.size() > 0:
		for line in mon_out[0].strip_edges().split("\n"):
			line = line.strip_edges()
			var eq = line.find("=")
			if eq > 0:
				r[line.substr(0, eq)] = line.substr(eq + 1)

	_pending_result = r
	_has_pending = true

func _get_pet() -> Node:
	return ProfileStyles.get_pet(get_tree())

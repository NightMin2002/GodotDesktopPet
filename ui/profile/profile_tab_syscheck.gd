# profile_tab_syscheck.gd — 机体诊断 Tab (装置终端)
# 异步查询系统硬件信息，以符合宠物人设的白话风格展示
extends HBoxContainer

var _status_label: RichTextLabel
var _scan_btn: Button
var _scanning: bool = false
var _pending: String = ""
var _has_pending: bool = false
var _screen_res: String = ""

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(vbox)

	# 标题区
	var title = Label.new()
	title.text = "机体诊断"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.70, 0.80, 0.92, 0.9))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	var desc = Label.new()
	desc.text = "检索当前宿主机的软硬件配置。数据从系统内部读取，不联网。"
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.6))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc)

	# 扫描按钮
	_scan_btn = Button.new()
	_scan_btn.text = "开始检索"
	_scan_btn.add_theme_font_size_override("font_size", 15)
	_scan_btn.add_theme_color_override("font_color", Color(0.3, 0.85, 0.5, 0.9))
	_scan_btn.add_theme_color_override("font_hover_color", Color(0.4, 1.0, 0.6, 1.0))
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(0.06, 0.15, 0.1, 0.6)
	bs.set_corner_radius_all(0)
	bs.set_border_width_all(1)
	bs.border_color = Color(0.2, 0.6, 0.4, 0.5)
	bs.content_margin_left = 16; bs.content_margin_right = 16
	bs.content_margin_top = 6; bs.content_margin_bottom = 6
	_scan_btn.add_theme_stylebox_override("normal", bs)
	var bh = bs.duplicate()
	bh.bg_color = Color(0.08, 0.2, 0.14, 0.8)
	bh.border_color = Color(0.3, 0.8, 0.5, 0.7)
	_scan_btn.add_theme_stylebox_override("hover", bh)
	_scan_btn.add_theme_stylebox_override("pressed", bh)
	_scan_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	_scan_btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var pet = _get_pet()
			if pet and pet.is_mouse_on_pet():
				return
			_start_scan()
	)
	vbox.add_child(_scan_btn)

	# 结果显示区
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.04, 0.06, 0.1, 0.4)
	cs.border_width_left = 2
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.3)
	cs.set_corner_radius_all(0)
	cs.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", cs)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(card)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("normal_font_size", 14)
	_status_label.add_theme_color_override("default_color", Color(0.78, 0.88, 1.0, 0.95))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.text = "[color=#607888]尚未检索。点击上方按钮开始。[/color]"
	card.add_child(_status_label)

func refresh() -> void:
	# Tab 切换到此页时自动开始检索
	if not _scanning:
		_start_scan()

func _process(_delta: float) -> void:
	if _has_pending:
		_has_pending = false
		_scanning = false
		if is_instance_valid(_status_label):
			_status_label.text = _pending
		if is_instance_valid(_scan_btn):
			_scan_btn.text = "重新检索"

func _start_scan() -> void:
	if _scanning:
		return
	_scanning = true
	if is_instance_valid(_status_label):
		_status_label.text = "[color=#4dd9e6]正在检索宿主机信息...[/color]"
	if is_instance_valid(_scan_btn):
		_scan_btn.text = "检索中..."
	var screen = DisplayServer.screen_get_size()
	_screen_res = "%d x %d" % [screen.x, screen.y]
	WorkerThreadPool.add_task(_query_task)

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
	# 显示器单独查询
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

	# ── 提取字段 ──
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

	# ── 格式化 ──
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
	var t = Time.get_datetime_dict_from_system()
	var ts = "%04d.%02d.%02d %02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute]

	# ── 颜色 ──
	var C_TITLE := "#4dd9e6"
	var C_KEY   := "#7799dd"
	var C_VAL   := "#c8dce8"
	var C_SUB   := "#607888"
	var C_OK    := "#6ccf6c"
	var C_WARN  := "#d4a030"
	var C_CRIT  := "#e05555"
	var C_SEP   := "#2a4055"

	# ── 工具函数 ──
	var kv = func(key: String, val: String) -> String:
		return "[color=%s]%s[/color]  [color=%s]%s[/color]" % [C_KEY, key, C_VAL, val]

	# ── 磁盘 ──
	var disk_lines := ""
	for part in disk.split("|"):
		part = part.strip_edges()
		if part == "": continue
		var segs = part.split(":")
		if segs.size() < 3:
			disk_lines += "[color=%s]%s[/color]\n" % [C_VAL, part]
			continue
		var drive = segs[0]
		var free_gb = segs[1].to_int()
		var total_gb = segs[2].to_int()
		var pct = 0
		if total_gb > 0:
			pct = free_gb * 100 / total_gb
		var c_disk = C_OK
		if pct < 10:
			c_disk = C_CRIT
		elif pct < 30:
			c_disk = C_WARN
		disk_lines += "  [color=%s]%s 盘  剩余 %dGB / 共 %dGB  (%d%%)[/color]\n" % [c_disk, drive, free_gb, total_gb, pct]

	# ── 电池 ──
	var bat_line := ""
	if bat_pct != "" and bat_pct != "N/A":
		var bp = bat_pct.to_int()
		var c_bat = C_OK
		if bp < 20:
			c_bat = C_CRIT
		elif bp < 50:
			c_bat = C_WARN
		var charging = " (充电中)" if bat_status == "2" else ""
		bat_line = kv.call("电池", "%s%%%s" % [bat_pct, charging]).replace(C_VAL, c_bat) + "\n"

	# ── 组装 (人设风格: 保持技术数据，用中文标签，简洁直接) ──
	var sep = "[color=%s]────────────────────────[/color]" % C_SEP
	_pending = "[color=%s]── 机体诊断报告 ──[/color]\n" % C_TITLE \
		+ "\n" \
		+ kv.call("宿主机", host) + "\n" \
		+ kv.call("操作员", user) + "\n" \
		+ kv.call("系统", os_info) + "\n" \
		+ kv.call("屏幕", _screen_res) + "\n" \
		+ sep + "\n" \
		+ kv.call("处理器", cpu) + "\n" \
		+ "  [color=%s]%s / 基频 %s[/color]\n" % [C_SUB, cores, freq_text] \
		+ kv.call("显卡", gpu) + "\n" \
		+ kv.call("内存", ram + " GB") + "\n" \
		+ kv.call("主板", mobo) + "\n" \
		+ kv.call("显示器", mon) + "\n" \
		+ kv.call("局域网", ip) + "\n" \
		+ sep + "\n" \
		+ "[color=%s]存储空间[/color]\n" % C_KEY \
		+ disk_lines \
		+ sep + "\n" \
		+ kv.call("开机时间", boot_time) + "\n" \
		+ kv.call("已运行", up_text) + "\n" \
		+ bat_line \
		+ "\n[color=%s]检索完毕 / %s[/color]" % [C_TITLE, ts]
	_has_pending = true

# ═══════════════════════════════════════════════
#  工具
# ═══════════════════════════════════════════════

func _get_pet() -> Node:
	var main_n = get_tree().root.get_node_or_null("Main")
	if main_n and "pet_instances" in main_n and main_n.pet_instances.size() > 0:
		return main_n.pet_instances[0]
	return null

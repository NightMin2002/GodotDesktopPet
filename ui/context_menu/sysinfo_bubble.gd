# sysinfo_bubble.gd — 系统信息气泡子系统 (RefCounted)
# 负责: 按需查询系统软硬件信息并以终端扫描报告风格展示
# 从 context_menu.gd 拆分，由主控制器持有引用并在 _process 中调度
extends RefCounted

var _menu  # context_menu 引用 (CanvasLayer)
var _bubble: PanelContainer = null
var _label: RichTextLabel = null
var _confirm_btn: Button = null
var _pending: String = ""
var _has_pending: bool = false
var _screen_res: String = ""  # 屏幕分辨率 (主线程读取, 传给后台)

func _init(menu_ref) -> void:
	_menu = menu_ref

# ── 触发 ──

func trigger() -> void:
	# 屏幕分辨率在主线程读取 (后台线程无法访问 DisplayServer)
	var screen = DisplayServer.screen_get_size()
	_screen_res = "%d × %d" % [screen.x, screen.y]
	_show("[center][color=#4dd9e6]SCANNING HOST...[/color][/center]", false)
	WorkerThreadPool.add_task(_query_task)

# ── 显示/关闭 ──

func _show(text: String, show_confirm: bool = false) -> void:
	if _bubble == null:
		_build()
	_label.text = text
	_confirm_btn.visible = show_confirm
	_bubble.reset_size()
	var pet = _find_pet()
	if is_instance_valid(pet):
		var pos = pet.get_global_transform_with_canvas().get_origin()
		# 反重力时气泡出现在宠物下方, 正常时出现在上方
		var y_off = 80.0 if pet.anti_gravity else -120.0
		var init_pos = pos + Vector2(-100, y_off)
		_bubble.position = _clamp_to_viewport(init_pos)
	if not _bubble.visible:
		_bubble.modulate.a = 0.0
		_bubble.scale = Vector2(0.5, 0.5)
		_bubble.show()
		# 等一帧让布局计算完成再设锚点
		await _menu.get_tree().process_frame
		_bubble.pivot_offset = _bubble.size * 0.5
		var tween = _menu.create_tween().set_parallel(true)
		tween.tween_property(_bubble, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
		tween.tween_property(_bubble, "modulate:a", 1.0, 0.2)
	else:
		# 已显示 (内容更新), 刷新锚点
		await _menu.get_tree().process_frame
		_bubble.pivot_offset = _bubble.size * 0.5

func _build() -> void:
	_bubble = PanelContainer.new()
	_bubble.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.16, 0.95)
	style.border_color = Color.from_hsv(EventBus.ui_hue, 0.8, 1.0, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(16)
	_bubble.add_theme_stylebox_override("panel", style)
	_menu.add_child(_bubble)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_bubble.add_child(vbox)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.add_theme_font_size_override("normal_font_size", 14)
	_label.add_theme_color_override("default_color", Color(0.78, 0.88, 1.0, 0.95))
	vbox.add_child(_label)
	_confirm_btn = Button.new()
	_confirm_btn.text = "确认"
	_confirm_btn.add_theme_font_size_override("font_size", 14)
	_confirm_btn.flat = true
	_confirm_btn.add_theme_color_override("font_color", Color(0.3, 0.85, 0.5, 0.9))
	_confirm_btn.add_theme_color_override("font_hover_color", Color(0.4, 1.0, 0.6, 1.0))
	_confirm_btn.pressed.connect(_on_confirm)
	_confirm_btn.visible = false
	vbox.add_child(_confirm_btn)

func _on_confirm() -> void:
	if _bubble == null:
		return
	_bubble.pivot_offset = _bubble.size * 0.5
	var tween = _menu.create_tween().set_parallel(true)
	tween.tween_property(_bubble, "modulate:a", 0.0, 0.3)
	tween.tween_property(_bubble, "scale", Vector2(0.8, 0.8), 0.3)
	await tween.finished
	_bubble.hide()
	_bubble.scale = Vector2.ONE
	var pet = _find_pet()
	if is_instance_valid(pet):
		pet.overlay_rect = Rect2()

# ── 每帧调度 (由主控制器调用) ──

## 消费异步结果 + 跟随宠物
func process_tick() -> void:
	# 异步结果到了 → 更新气泡
	if _has_pending:
		_has_pending = false
		_show(_pending, true)
		# 通知宠物弹出核准状态个人终端
		var pet = _find_pet()
		if is_instance_valid(pet) and "holo_screen" in pet and is_instance_valid(pet.holo_screen):
			var s: float = -1.0 if pet.global_position.x > pet.boundary_size.x * 0.5 else 1.0
			pet.holo_screen.show_done(s, 4.0)
	# 气泡跟随宠物
	if _bubble != null and _bubble.visible:
		var pet = _find_pet()
		if is_instance_valid(pet):
			var pos = pet.get_global_transform_with_canvas().get_origin()
			# 反重力时气泡跟随在宠物下方, 正常时跟随在上方
			var tp: Vector2
			if pet.anti_gravity:
				tp = pos + Vector2(-_bubble.size.x * 0.5, 30)
			else:
				tp = pos + Vector2(-_bubble.size.x * 0.5, -_bubble.size.y - 30)
			tp = _clamp_to_viewport(tp)
			_bubble.position = _bubble.position.lerp(tp, 0.15)
			pet.overlay_rect = Rect2(_bubble.position, _bubble.size).grow(10)

func is_visible() -> bool:
	return _bubble != null and _bubble.visible

# ── 后台查询 ──

# PS 脚本: 通过 run_command 注入 (避免 GDScript 反斜杠转义)
const _PS_SCRIPT := "$h=$env:COMPUTERNAME;$u=$env:USERNAME;$o=Get-CimInstance Win32_OperatingSystem;$osN=$o.Caption -replace 'Microsoft ','';$p=Get-CimInstance Win32_Processor|Select-Object -First 1;$cpu=$p.Name;$cores=$p.NumberOfCores.ToString()+'C / '+$p.NumberOfLogicalProcessors.ToString()+'T';$freq=$p.MaxClockSpeed;$g=Get-CimInstance Win32_VideoController|Where-Object{$_.Name -notmatch 'Virtual|MuMu|GameViewer'};$nv=$g|Where-Object{$_.Name -match 'NVIDIA|GeForce|RTX|GTX'};$gpu=if($nv){($nv|Select-Object -First 1).Name}else{($g|Select-Object -First 1).Name};$used=[math]::Round(($o.TotalVisibleMemorySize-$o.FreePhysicalMemory)/1MB,1);$total=[math]::Round($o.TotalVisibleMemorySize/1MB,1);$mb=Get-CimInstance Win32_BaseBoard|Select-Object -First 1;$mobo=$mb.Manufacturer+' '+$mb.Product;$ip=(Get-NetIPAddress -AddressFamily IPv4|Where-Object{$_.InterfaceAlias -notmatch 'Loopback|vEthernet|Radmin|FlClash|VPN|Bluetooth' -and $_.InterfaceAlias -notlike '*蓝牙*' -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '198.18.*'}|Select-Object -First 1).IPAddress;if(!$ip){$ip='N/A'};$disks=Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'|ForEach-Object{($_.DeviceID -replace ':','')+':'+[math]::Round($_.FreeSpace/1GB).ToString()+':'+[math]::Round($_.Size/1GB).ToString()};$boot=$o.LastBootUpTime;$upMin=[math]::Round(((Get-Date)-$boot).TotalMinutes);$bat=try{(Get-CimInstance Win32_Battery -ErrorAction Stop|Select-Object -First 1)}catch{$null};$bp=if($bat){$bat.EstimatedChargeRemaining}else{'N/A'};$bs=if($bat){$bat.BatteryStatus}else{0};Write-Host host=$h;Write-Host user=$u;Write-Host os=$osN;Write-Host cpu=$cpu;Write-Host cores=$cores;Write-Host freq=$freq;Write-Host gpu=$gpu;Write-Host ram=$used/$total;Write-Host mobo=$mobo;Write-Host ip=$ip;Write-Host disk=($disks -join '|');Write-Host uptime=$upMin;Write-Host bat=$bp;Write-Host bstat=$bs"

func _query_task() -> void:
	var r: Dictionary = {}
	# 主查询
	var out: Array = []
	OS.execute("powershell", ["-NoProfile", "-Command", _PS_SCRIPT], out, true, false)
	if out.size() > 0:
		for line in out[0].strip_edges().split("\n"):
			line = line.strip_edges()
			var eq = line.find("=")
			if eq > 0:
				r[line.substr(0, eq)] = line.substr(eq + 1)
	# 显示器单独查询 (root/wmi 命名空间, 可能需要权限)
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
	# ── 格式化计算值 ──
	# 开机时长 + 反推开机时间
	var up_text = uptime_str
	var boot_time = "?"
	if uptime_str != "?":
		var up_min = uptime_str.to_int()
		if up_min >= 60:
			up_text = "%dh %dm" % [up_min / 60, up_min % 60]
		else:
			up_text = "%dm" % up_min
		# 用当前 Unix 时间减去 uptime 反推开机时间
		var now_unix = Time.get_unix_time_from_system()
		var boot_unix = now_unix - up_min * 60
		# get_datetime_dict_from_unix_time 返回 UTC, 需加时区偏移转本地
		var tz = Time.get_time_zone_from_system()
		var bd = Time.get_datetime_dict_from_unix_time(int(boot_unix) + tz.bias * 60)
		boot_time = "%04d.%02d.%02d %02d:%02d" % [bd.year, bd.month, bd.day, bd.hour, bd.minute]
	# CPU 基频
	var freq_text = freq
	if freq != "?":
		var mhz = freq.to_float()
		freq_text = "%.1f GHz" % (mhz / 1000.0)
	# 时间戳
	var t = Time.get_datetime_dict_from_system()
	var ts = "%04d.%02d.%02d %02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute]
	# ── 颜色定义 ──
	var C_HEAD := "#4dd9e6"   # 标题/结尾: 亮青色
	var C_ID   := "#5bb8c5"   # 身份标签: 青色调
	var C_HW   := "#7799dd"   # 硬件标签: 蓝色调
	var C_STR  := "#d4a030"   # 存储标题: 金色调
	var C_RT   := "#b07dd4"   # 运行时标题: 紫色调
	var C_SEP  := "#2a4055"   # 分隔线: 暗色
	var C_VAL  := "#c8dce8"   # 值文本: 浅白
	var C_SUB  := "#607888"   # 副行补充: 较暗
	var C_OK   := "#6ccf6c"   # 正常: 绿
	var C_WARN := "#d4a030"   # 注意: 金
	var C_CRIT := "#e05555"   # 危险: 红
	# ── BBCode 标签工具 ──
	var tag_id = func(n: String) -> String:
		return "[color=%s][lb]%s[rb][/color]" % [C_ID, n]
	var tag_hw = func(n: String) -> String:
		return "[color=%s][lb]%s[rb][/color]" % [C_HW, n]
	var tag_rt = func(n: String) -> String:
		return "[color=%s][lb]%s[rb][/color]" % [C_RT, n]
	# ── 磁盘竖排 + 百分比 + 颜色分级 ──
	var disk_lines := ""
	for part in disk.split("|"):
		part = part.strip_edges()
		if part == "":
			continue
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
		disk_lines += "[color=%s]%s  %dGB / %dGB  (%d%%)[/color]\n" % [c_disk, drive, free_gb, total_gb, pct]
	# ── 电池行 (可选, 台式机可能无电池) ──
	var bat_line := ""
	if bat_pct != "" and bat_pct != "N/A":
		var bp = bat_pct.to_int()
		var c_bat = C_OK
		if bp < 20:
			c_bat = C_CRIT
		elif bp < 50:
			c_bat = C_WARN
		var charging = " · Charging" if bat_status == "2" else ""
		bat_line = "%s   [color=%s]%s%%%s[/color]\n" % [tag_rt.call("BAT"), c_bat, bat_pct, charging]
	# ── 组装 BBCode ──
	var sep = "[center][color=%s]─ ─ ─ ─ ─ ─ ─ ─ ─ ─[/color][/center]" % C_SEP
	_pending = "[center][color=%s]── SYSTEM SCAN ──[/color][/center]\n" % C_HEAD \
		+ "%s  [color=%s]%s[/color]\n" % [tag_id.call("HOST"), C_VAL, host] \
		+ "%s  [color=%s]%s[/color]\n" % [tag_id.call("USER"), C_VAL, user] \
		+ "%s    [color=%s]%s[/color]\n" % [tag_id.call("OS"), C_VAL, os_info] \
		+ "%s  [color=%s]%s[/color]\n" % [tag_id.call("DISP"), C_VAL, _screen_res] \
		+ sep + "\n" \
		+ "%s   [color=%s]%s[/color]\n" % [tag_hw.call("CPU"), C_VAL, cpu] \
		+ "        [color=%s]%s · %s[/color]\n" % [C_SUB, cores, freq_text] \
		+ "%s   [color=%s]%s[/color]\n" % [tag_hw.call("GPU"), C_VAL, gpu] \
		+ "%s   [color=%s]%s GB[/color]\n" % [tag_hw.call("MEM"), C_VAL, ram] \
		+ "%s  [color=%s]%s[/color]\n" % [tag_hw.call("MOBO"), C_VAL, mobo] \
		+ "%s   [color=%s]%s[/color]\n" % [tag_hw.call("MON"), C_VAL, mon] \
		+ "%s    [color=%s]%s[/color]\n" % [tag_hw.call("IP"), C_VAL, ip] \
		+ "[center][color=%s]── STORAGE ──[/color][/center]\n" % C_STR \
		+ disk_lines \
		+ "[center][color=%s]── RUNTIME ──[/color][/center]\n" % C_RT \
		+ "%s  [color=%s]%s[/color]\n" % [tag_rt.call("BOOT"), C_VAL, boot_time] \
		+ "%s    [color=%s]%s[/color]\n" % [tag_rt.call("UP"), C_VAL, up_text] \
		+ bat_line \
		+ sep + "\n" \
		+ "[center][color=%s]SCAN COMPLETE · %s[/color][/center]" % [C_HEAD, ts]
	_has_pending = true

# ── 工具 ──

func _find_pet() -> Node2D:
	var main = _menu.get_tree().root.get_node_or_null("Main")
	if main and "pet_instance" in main and is_instance_valid(main.pet_instance):
		return main.pet_instance
	return null

## 视口边界钳制: 确保气泡始终在屏幕内
func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var vp = _menu.get_viewport().get_visible_rect().size
	var bs = _bubble.size if _bubble.size.x > 0 else Vector2(300, 120)
	pos.x = clampf(pos.x, 8.0, vp.x - bs.x - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - bs.y - 8.0)
	return pos

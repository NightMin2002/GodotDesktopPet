# sysinfo_bubble.gd — 系统信息气泡子系统 (RefCounted)
# 负责: 按需查询 CPU/GPU/RAM/Disk 并以气泡形式展示
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
		var init_pos = pos + Vector2(-100, -120)
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
	# 气泡跟随宠物
	if _bubble != null and _bubble.visible:
		var pet = _find_pet()
		if is_instance_valid(pet):
			var pos = pet.get_global_transform_with_canvas().get_origin()
			var tp = pos + Vector2(-_bubble.size.x * 0.5, -_bubble.size.y - 30)
			tp = _clamp_to_viewport(tp)
			_bubble.position = _bubble.position.lerp(tp, 0.15)
			pet.overlay_rect = Rect2(_bubble.position, _bubble.size).grow(10)

func is_visible() -> bool:
	return _bubble != null and _bubble.visible

# ── 后台查询 ──

const _PS_HW_SCRIPT := "$h=$env:COMPUTERNAME;$u=$env:USERNAME;$o=Get-CimInstance Win32_OperatingSystem;$osN=$o.Caption -replace 'Microsoft ','';$cpu=(Get-CimInstance Win32_Processor|Select-Object -First 1).Name;$g=Get-CimInstance Win32_VideoController|Where-Object{$_.Name -notmatch 'Virtual|MuMu|GameViewer'};$nv=$g|Where-Object{$_.Name -match 'NVIDIA|GeForce|RTX|GTX'};$gpu=if($nv){($nv|Select-Object -First 1).Name}else{($g|Select-Object -First 1).Name};$used=[math]::Round(($o.TotalVisibleMemorySize-$o.FreePhysicalMemory)/1MB,1);$total=[math]::Round($o.TotalVisibleMemorySize/1MB,1);$ip=(Get-NetIPAddress -AddressFamily IPv4|Where-Object{$_.InterfaceAlias -notmatch 'Loopback|vEthernet|Radmin|FlClash|VPN|Bluetooth' -and $_.InterfaceAlias -notlike '*蓝牙*' -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '198.18.*'}|Select-Object -First 1).IPAddress;if(!$ip){$ip='N/A'};$disks=Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'|ForEach-Object{($_.DeviceID -replace ':','')+':'+[math]::Round($_.FreeSpace/1GB).ToString()+':'+[math]::Round($_.Size/1GB).ToString()};Write-Host host=$h;Write-Host user=$u;Write-Host os=$osN;Write-Host cpu=$cpu;Write-Host gpu=$gpu;Write-Host ram=$used/$total;Write-Host ip=$ip;Write-Host disk=($disks -join '|')"

func _query_task() -> void:
	var out: Array = []
	OS.execute("powershell", ["-NoProfile", "-Command", _PS_HW_SCRIPT], out, true, false)
	if out.size() > 0:
		var r: Dictionary = {}
		for line in out[0].strip_edges().split("\n"):
			line = line.strip_edges()
			var eq = line.find("=")
			if eq > 0:
				r[line.substr(0, eq)] = line.substr(eq + 1)
		var host = r.get("host", "?")
		var user = r.get("user", "?")
		var os_info = r.get("os", "?")
		var cpu = r.get("cpu", "?").replace(" with Radeon Graphics", "")
		var gpu = r.get("gpu", "?")
		var ram = r.get("ram", "?")
		var ip = r.get("ip", "N/A")
		var disk = r.get("disk", "?")
		var t = Time.get_datetime_dict_from_system()
		var ts = "%04d.%02d.%02d %02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute]
		var C_HEAD := "#4dd9e6"   # 标题/结尾: 亮青色
		var C_ID   := "#5bb8c5"   # 身份标签: 青色调
		var C_HW   := "#7799dd"   # 硬件标签: 蓝色调
		var C_STR  := "#d4a030"   # 存储标题: 金色调
		var C_SEP  := "#2a4055"   # 分隔线: 暗色
		var C_VAL  := "#c8dce8"   # 值文本: 浅白
		var C_OK   := "#6ccf6c"   # 磁盘正常 (>30%): 绿
		var C_WARN := "#d4a030"   # 磁盘注意 (10~30%): 金
		var C_CRIT := "#e05555"   # 磁盘危险 (<10%): 红
		# BBCode 中 [TAG] 需用 [lb]/[rb] 转义方括号
		var tag_id = func(t: String) -> String:
			return "[color=%s][lb]%s[rb][/color]" % [C_ID, t]
		var tag_hw = func(t: String) -> String:
			return "[color=%s][lb]%s[rb][/color]" % [C_HW, t]
		# 磁盘竖排 + 百分比 + 颜色分级
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
		var sep = "[center][color=%s]─ ─ ─ ─ ─ ─ ─ ─ ─ ─[/color][/center]" % C_SEP
		_pending = "[center][color=%s]── SYSTEM SCAN ──[/color][/center]\n" % C_HEAD \
			+ "%s  [color=%s]%s[/color]\n" % [tag_id.call("HOST"), C_VAL, host] \
			+ "%s  [color=%s]%s[/color]\n" % [tag_id.call("USER"), C_VAL, user] \
			+ "%s    [color=%s]%s[/color]\n" % [tag_id.call("OS"), C_VAL, os_info] \
			+ "%s  [color=%s]%s[/color]\n" % [tag_id.call("DISP"), C_VAL, _screen_res] \
			+ sep + "\n" \
			+ "%s   [color=%s]%s[/color]\n" % [tag_hw.call("CPU"), C_VAL, cpu] \
			+ "%s   [color=%s]%s[/color]\n" % [tag_hw.call("GPU"), C_VAL, gpu] \
			+ "%s   [color=%s]%s GB[/color]\n" % [tag_hw.call("MEM"), C_VAL, ram] \
			+ "%s    [color=%s]%s[/color]\n" % [tag_hw.call("IP"), C_VAL, ip] \
			+ "[center][color=%s]── STORAGE ──[/color][/center]\n" % C_STR \
			+ disk_lines \
			+ sep + "\n" \
			+ "[center][color=%s]SCAN COMPLETE · %s[/color][/center]" % [C_HEAD, ts]
	else:
		_pending = "SCAN FAILED"
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

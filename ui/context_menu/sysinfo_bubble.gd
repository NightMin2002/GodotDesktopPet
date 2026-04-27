# sysinfo_bubble.gd — 系统信息气泡子系统 (RefCounted)
# 负责: 按需查询 CPU/GPU/RAM/Disk 并以气泡形式展示
# 从 context_menu.gd 拆分，由主控制器持有引用并在 _process 中调度
extends RefCounted

var _menu  # context_menu 引用 (CanvasLayer)
var _bubble: PanelContainer = null
var _label: Label = null
var _confirm_btn: Button = null
var _pending: String = ""
var _has_pending: bool = false

func _init(menu_ref) -> void:
	_menu = menu_ref

# ── 触发 ──

func trigger() -> void:
	_show("正在检索主人的电脑...", false)
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
		_bubble.position = pos + Vector2(-100, -120)
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
	style.border_color = Color(0.1, 0.8, 1.0, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(16)
	_bubble.add_theme_stylebox_override("panel", style)
	_menu.add_child(_bubble)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_bubble.add_child(vbox)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0, 0.95))
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
			_bubble.position = _bubble.position.lerp(tp, 0.15)
			pet.overlay_rect = Rect2(_bubble.position, _bubble.size).grow(10)

func is_visible() -> bool:
	return _bubble != null and _bubble.visible

# ── 后台查询 ──

const _PS_HW_SCRIPT := "$g=Get-CimInstance Win32_VideoController|Where-Object{$_.Name -notmatch 'Virtual|MuMu|GameViewer'};$nv=$g|Where-Object{$_.Name -match 'NVIDIA|GeForce|RTX|GTX'};$gpu=if($nv){($nv|Select-Object -First 1).Name}else{($g|Select-Object -First 1).Name};$cpu=(Get-CimInstance Win32_Processor|Select-Object -First 1).Name;$o=Get-CimInstance Win32_OperatingSystem;$used=[math]::Round(($o.TotalVisibleMemorySize-$o.FreePhysicalMemory)/1MB,1);$total=[math]::Round($o.TotalVisibleMemorySize/1MB,1);$disks=Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'|ForEach-Object{$_.DeviceID+' '+[math]::Round($_.FreeSpace/1GB).ToString()+'/'+[math]::Round($_.Size/1GB).ToString()+'GB'};Write-Host cpu=$cpu;Write-Host gpu=$gpu;Write-Host ram=$used/$total;Write-Host disk=($disks -join ' | ')"

func _query_task() -> void:
	var out: Array = []
	OS.execute("powershell", ["-NoProfile", "-Command", _PS_HW_SCRIPT], out, true, false)
	if out.size() > 0:
		var result: Dictionary = {}
		for line in out[0].strip_edges().split("\n"):
			line = line.strip_edges()
			var eq = line.find("=")
			if eq > 0:
				result[line.substr(0, eq)] = line.substr(eq + 1)
		var cpu = result.get("cpu", "?").replace(" with Radeon Graphics", "")
		var gpu = result.get("gpu", "?")
		var ram = result.get("ram", "?")
		var disk = result.get("disk", "?")
		_pending = "CPU  %s\nGPU  %s\nRAM  %s GB\nDisk  %s" % [cpu, gpu, ram, disk]
	else:
		_pending = "查询失败"
	_has_pending = true

# ── 工具 ──

func _find_pet() -> Node2D:
	var main = _menu.get_tree().root.get_node_or_null("Main")
	if main and "pet_instance" in main and is_instance_valid(main.pet_instance):
		return main.pet_instance
	return null

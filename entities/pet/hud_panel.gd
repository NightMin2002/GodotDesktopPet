# hud_panel.gd — 统一 HUD 悬浮面板
# 宠物侧边的紧凑信息卡片，整合所有 HUD 小组件
# 当前组件: 时钟、WiFi、待办计数  |  可扩展: CPU、内存、电量等
class_name HudPanel
extends RefCounted

var pet: RigidBody2D
var panel: PanelContainer

# ── 组件开关 ──
var clock_enabled: bool = false
var wifi_enabled: bool = false
var todo_enabled: bool = false
var hud_pin: bool = false  # true=常驻显示, false=鼠标悬浮显示

# ── 时钟组件 ──
var _clock_label: Label
var _clock_row: HBoxContainer

# ── WiFi 组件 ──
var _wifi_label: Label
var _wifi_dot: Label
var _wifi_row: HBoxContainer
var _wifi_refresh_timer: float = 0.0
var _wifi_pending: String = ""  # 线程安全缓冲区
var _wifi_pending_connected: bool = false
var _wifi_has_pending: bool = false  # 原子标志: 后台线程写入, 主线程读取+清除
var _wifi_in_flight: bool = false   # 并发查询保护: 防止多个 PowerShell 进程同时运行
const WIFI_REFRESH_INTERVAL := 15.0

# ── 待办计数组件 ──
var _todo_row: HBoxContainer
var _todo_label: Label
var _todo_dot: Label
var _todo_pending: int = 0
var _todo_total: int = 0

var _menu_hidden: bool = false  # 被右键菜单遮挡时临时隐藏

# ── 悬浮显示状态 ──
var _hover: bool = false         # 鼠标是否在宠物上
var _hover_visible: bool = false  # 悬浮模式下面板是否可见
var _hover_fade_timer: float = 0.0  # 离开宠物后延迟消失
const HOVER_FADE_DELAY := 0.3  # 鼠标离开后 0.3 秒开始淡出

func init(p: RigidBody2D) -> void:
	pet = p
	_build_panel()
	EventBus.context_menu_toggled.connect(_on_menu_toggled)
	EventBus.pet_color_changed.connect(_on_pet_color_changed)
	EventBus.todo_count_changed.connect(_on_todo_count_changed)

func _on_menu_toggled(is_open: bool) -> void:
	if not _has_any_component():
		return
	if not is_instance_valid(panel):
		return
	_menu_hidden = is_open
	if is_open:
		if panel.visible:
			var tw = pet.create_tween()
			tw.tween_property(panel, "modulate:a", 0.0, 0.15)
	else:
		# 菜单关闭后重新评估可见性
		var should_visible = hud_pin or _hover_visible
		if should_visible:
			if not panel.visible:
				# 在菜单打开期间刚切换了模式/组件 → 完整显示
				_show_panel_animated()
			else:
				# 面板本来就在 → 恢复透明度
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
	var border_hue = pet.palette.effective_hue()  # 面板边框跟随宠物色调
	style.border_color = Color.from_hsv(border_hue, 0.6, 0.9, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)
	
	_build_clock_row(vbox)
	_build_wifi_row(vbox)
	_build_todo_row(vbox)
	
	pet.add_child(panel)

func _build_clock_row(parent: VBoxContainer) -> void:
	_clock_row = HBoxContainer.new()
	_clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_row.add_theme_constant_override("separation", 4)
	_clock_row.visible = false
	parent.add_child(_clock_row)
	
	# 标签列 — 与 WiFi 行结构一致: [●绿点 + TIME标签], 固定宽度对齐
	var tag_box = HBoxContainer.new()
	tag_box.custom_minimum_size = Vector2(38, 0)
	tag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_theme_constant_override("separation", 2)
	_clock_row.add_child(tag_box)
	
	var clock_dot = Label.new()
	clock_dot.text = "\u25cf"
	clock_dot.add_theme_font_size_override("font_size", 8)
	clock_dot.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4, 0.9))
	clock_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_child(clock_dot)
	
	var clock_tag = Label.new()
	clock_tag.text = "TIME"
	clock_tag.add_theme_font_size_override("font_size", 10)
	clock_tag.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.6))
	clock_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_child(clock_tag)
	
	_clock_label = Label.new()
	_clock_label.text = "00:00:00"
	_clock_label.add_theme_font_size_override("font_size", 17)
	_clock_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.95))
	_clock_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.3))
	_clock_label.add_theme_constant_override("outline_size", 1)
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_row.add_child(_clock_label)

func _build_wifi_row(parent: VBoxContainer) -> void:
	# WiFi 行 — 结构与时钟行对齐: [固定宽标签列] [SSID值]
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = "点击打开网络设置"
	row.add_theme_constant_override("separation", 4)
	row.visible = false
	row.gui_input.connect(_on_wifi_row_input)
	_wifi_row = row
	parent.add_child(row)
	
	# 标签列 — 固定宽度容器, 内含指示点+WiFi标签, 与 TIME 列等宽
	var tag_box = HBoxContainer.new()
	tag_box.custom_minimum_size = Vector2(38, 0)
	tag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_theme_constant_override("separation", 2)
	row.add_child(tag_box)
	
	# 连接状态指示点
	_wifi_dot = Label.new()
	_wifi_dot.text = "\u25cf"
	_wifi_dot.add_theme_font_size_override("font_size", 8)
	_wifi_dot.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4, 0.9))
	_wifi_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_child(_wifi_dot)
	
	var wifi_tag = Label.new()
	wifi_tag.text = "WiFi"
	wifi_tag.add_theme_font_size_override("font_size", 10)
	wifi_tag.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.7))
	wifi_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_child(wifi_tag)
	
	_wifi_label = Label.new()
	_wifi_label.text = "..."
	_wifi_label.add_theme_font_size_override("font_size", 17)
	_wifi_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.95))
	_wifi_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_wifi_label)

# ── 组件开关控制 ──

func set_clock(on: bool) -> void:
	clock_enabled = on
	if is_instance_valid(_clock_row):
		_clock_row.visible = on
	if is_instance_valid(panel):
		panel.reset_size()
	_refresh_panel_visibility()

func set_wifi(on: bool) -> void:
	wifi_enabled = on
	if is_instance_valid(_wifi_row):
		_wifi_row.visible = on
	if is_instance_valid(panel):
		panel.reset_size()
	if on:
		_wifi_refresh_timer = 0.0
		_refresh_wifi_async()
	_refresh_panel_visibility()

func set_todo(on: bool) -> void:
	todo_enabled = on
	if is_instance_valid(_todo_row):
		_todo_row.visible = on
	if is_instance_valid(panel):
		panel.reset_size()
	_refresh_panel_visibility()

func set_pin(on: bool) -> void:
	hud_pin = on
	if on:
		# 切换到常驻: 立即显示
		_hover_visible = false
		_refresh_panel_visibility()
	else:
		# 切换到悬浮: 如果鼠标不在宠物上则淡出
		if not _hover:
			_fade_out_panel()

## 由 pet.gd 在 _process 中调用, 转发鼠标悬浮状态
func set_hover(is_hovering: bool) -> void:
	if hud_pin:
		return  # 常驻模式无需响应悬浮
	if not _has_any_component():
		return
	
	var was_hover = _hover
	_hover = is_hovering
	
	if is_hovering and not was_hover:
		# 鼠标进入 → 显示面板
		_hover_fade_timer = 0.0
		if not _hover_visible:
			_hover_visible = true
			_show_panel_animated()
	elif not is_hovering and was_hover:
		# 鼠标离开 → 启动延迟消失计时器
		_hover_fade_timer = HOVER_FADE_DELAY

func _has_any_component() -> bool:
	return clock_enabled or wifi_enabled or todo_enabled

## 可见性统一入口: 常驻模式直接显示, 悬浮模式由 hover 状态控制
func _refresh_panel_visibility() -> void:
	var has_comp = _has_any_component()
	if not has_comp:
		# 没有任何组件开启 → 隐藏
		if panel.visible:
			_fade_out_panel()
		_hover_visible = false
		return
	
	if hud_pin:
		# 常驻模式: 直接显示
		if not panel.visible:
			_show_panel_animated()
	else:
		# 悬浮模式: 只在悬停时显示
		if _hover_visible and not panel.visible:
			_show_panel_animated()
		elif not _hover_visible and panel.visible:
			_fade_out_panel()

func _show_panel_animated() -> void:
	if _menu_hidden:
		return
	panel.reset_size()
	panel.modulate.a = 0.0
	panel.visible = true
	_snap_position()
	var tw = pet.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
	# 面板重新显示时立即刷新 WiFi (悬浮模式下 timer 长期冻结，数据可能过旧)
	if wifi_enabled and not _wifi_has_pending:
		_wifi_refresh_timer = 0.0
		_refresh_wifi_async()

func _fade_out_panel() -> void:
	if not panel.visible:
		return
	var tw = pet.create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): panel.visible = false)

# ── 主更新 ──

func update(delta: float) -> void:
	# 悬浮模式: 延迟消失计时器
	if not hud_pin and _hover_fade_timer > 0.0:
		_hover_fade_timer -= delta
		if _hover_fade_timer <= 0.0 and _hover_visible and not _hover:
			_hover_visible = false
			_fade_out_panel()
	
	# WiFi 后台结果消费: 不受面板可见性限制，避免 pending 数据被卡住
	if wifi_enabled and _wifi_has_pending:
		_wifi_has_pending = false
		var old_text = _wifi_label.text
		_wifi_label.text = _wifi_pending
		if old_text != _wifi_pending and panel.visible:
			panel.reset_size()
		var color = Color(0.3, 0.8, 0.4, 0.9) if _wifi_pending_connected else Color(0.8, 0.3, 0.3, 0.9)
		_wifi_dot.add_theme_color_override("font_color", color)
	
	if not panel.visible:
		return
	
	if clock_enabled:
		_update_clock(delta)
	
	if wifi_enabled:
		# 定时刷新 (仅面板可见时递增，避免后台频繁查询)
		_wifi_refresh_timer += delta
		if _wifi_refresh_timer >= WIFI_REFRESH_INTERVAL:
			_wifi_refresh_timer = 0.0
			_refresh_wifi_async()
	
	_update_position(delta)

func _update_clock(_delta: float) -> void:
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
	var panel_size = panel.size
	
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

# PowerShell 命令: 获取真实 SSID
# 1. Get-NetConnectionProfile.Name 返回的是网络配置文件名 (可能带数字后缀如 "MyWiFi 3")
# 2. netsh wlan show profiles 返回的是真实 SSID (如 "MyWiFi")
# 3. 用已保存的 SSID 列表反向匹配，找到最长前缀匹配的那个就是真实 SSID
const _PS_WIFI := "$n=(Get-NetConnectionProfile|?{$_.InterfaceAlias -match 'Wi-Fi|WLAN|Wireless'}|Select -First 1).Name;if($n){$ss=@();(netsh wlan show profiles 2>$null)|%{if($_ -match ' : (.+)$'){$ss+=$Matches[1].Trim()}};foreach($s in ($ss|Sort-Object Length -Desc)){if($n.StartsWith($s)){$n=$s;break}};$n}else{''}"

func _refresh_wifi_async() -> void:
	if _wifi_in_flight:
		return  # 上一次查询尚未完成, 跳过
	_wifi_in_flight = true
	WorkerThreadPool.add_task(_wifi_worker)

## 后台线程: 执行 PowerShell 查询 (不在主线程, 零卡顿)
func _wifi_worker() -> void:
	var output = []
	var args = PackedStringArray(["-NoProfile", "-Command", _PS_WIFI])
	var code = OS.execute("powershell", args, output, false, false)
	
	if code == 0 and output.size() > 0:
		var ssid = output[0].strip_edges()
		if ssid.length() > 0:
			_wifi_pending = ssid
			_wifi_pending_connected = true
			_wifi_has_pending = true
			_wifi_in_flight = false
			return
	
	_wifi_pending = "未连接"
	_wifi_pending_connected = false
	_wifi_has_pending = true
	_wifi_in_flight = false

func _on_wifi_row_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		OS.shell_open("ms-settings:network-wifi")

# ── 待办计数 ──

func _build_todo_row(parent: VBoxContainer) -> void:
	_todo_row = HBoxContainer.new()
	_todo_row.mouse_filter = Control.MOUSE_FILTER_STOP
	_todo_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_todo_row.tooltip_text = "点击打开待办清单"
	_todo_row.add_theme_constant_override("separation", 4)
	_todo_row.visible = false
	_todo_row.gui_input.connect(_on_todo_row_input)
	parent.add_child(_todo_row)

	# 标签列
	var tag_box = HBoxContainer.new()
	tag_box.custom_minimum_size = Vector2(38, 0)
	tag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_theme_constant_override("separation", 2)
	_todo_row.add_child(tag_box)

	_todo_dot = Label.new()
	_todo_dot.text = "\u25cf"
	_todo_dot.add_theme_font_size_override("font_size", 8)
	_todo_dot.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75, 0.5))
	_todo_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_child(_todo_dot)

	var todo_tag = Label.new()
	todo_tag.text = "TODO"
	todo_tag.add_theme_font_size_override("font_size", 10)
	todo_tag.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.6))
	todo_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_child(todo_tag)

	_todo_label = Label.new()
	_todo_label.text = "0/0"
	_todo_label.add_theme_font_size_override("font_size", 17)
	_todo_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.95))
	_todo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_todo_row.add_child(_todo_label)

func _on_todo_count_changed(pending: int, total: int) -> void:
	_todo_pending = pending
	_todo_total = total
	if is_instance_valid(_todo_label):
		var done = total - pending
		_todo_label.text = "%d/%d" % [done, total] if total > 0 else "0"
	if is_instance_valid(_todo_dot):
		var c: Color
		if pending > 0:
			c = Color(0.9, 0.7, 0.2, 0.9)  # 有待办: 金色
		else:
			c = Color(0.3, 0.8, 0.4, 0.9)  # 全完成: 绿色
		_todo_dot.add_theme_color_override("font_color", c)

func _on_todo_row_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		EventBus.show_todo_panel.emit()

# ── 主题色联动 ──

func _on_pet_color_changed(pet_index: int, _hue, _sat, _val) -> void:
	# 仅响应自己所属宠物的颜色变更
	if not is_instance_valid(pet) or not is_instance_valid(panel):
		return
	var my_index = pet.get_meta("pet_index", 0)
	if pet_index != my_index:
		return
	var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style = style.duplicate()
		style.border_color = Color.from_hsv(pet.palette.effective_hue(), 0.6, 0.9, 0.7)
		panel.add_theme_stylebox_override("panel", style)

# ── 命中区域 ──

func get_panel_rect() -> Rect2:
	if is_instance_valid(panel) and panel.visible:
		return Rect2(panel.position, panel.size).grow(5)
	return Rect2()

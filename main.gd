# main.gd — 启动场景主脚本 (精简后的调度器)
# 职责: 窗口初始化、屏幕边界、宠物实例化、子系统编排
# 实际逻辑已委托给: ghost_wall_manager / hit_region_manager / clone_manager / farewell_manager
extends Node2D

var pet_scene := preload("res://entities/pet/pet.tscn")
var clone_scene := preload("res://entities/pet/clone_pet.tscn")
const _PetColorPalette = preload("res://entities/pet/pet_color_palette.gd")
var pet_instance: RigidBody2D  # 原体引用
var pet_instances: Array[RigidBody2D] = []  # 所有宠物 (原体 + 克隆体)
var screen_rect: Rect2i
var boundary_size: Vector2  # 实际使用的边界尺寸 (视口坐标系)

# -- 双端架构 C# 桥接 --
var win_manager: Node
var input_monitor: Node  # InputMonitor (C# 键鼠采集)
var file_ops: Node       # FileOperations (C# 文件操作)

# ── 快捷键管理器 ──
var hotkey_mgr: Node

# ── 共享状态 (被子管理器读写) ──
var window_mode: int = 0  # 0=FREE, 1=CONFINED, 2=REPELLED
var behavior_mode: int = 0  # 0=FREE, 1=QUIET

# ── 子管理器引用 ──
var ghost_wall_mgr: Node
var hit_region_mgr: Node
var clone_mgr: Node
var farewell_mgr: Node


func _ready() -> void:
	# ── 性能调频 ──
	Engine.max_fps = 120
	Engine.physics_ticks_per_second = 120
	
	# ── C# 底层桥接 (先加载，用于提权) ──
	if ResourceLoader.exists("res://interop/WindowsManager.cs"):
		win_manager = load("res://interop/WindowsManager.cs").new()
		add_child(win_manager)
		if win_manager.has_method("BoostProcessPriority"):
			win_manager.call("BoostProcessPriority")
	
	# 双保险：设置窗口前先隐藏，防止任务栏闪烁
	var win = get_window()
	if win and win.get_parent():
		win.visible = false
	
	_setup_window()
	
	# 等待 5 帧让窗口内部 (GPU Context + DWM Surface) 完全就绪
	for i in range(5):
		await get_tree().process_frame
	
	# 先恢复可见，再推 ToolWindow 标记
	get_window().visible = true
	await get_tree().process_frame
	if win_manager and win_manager.has_method("HideFromTaskbar"):
		win_manager.call("HideFromTaskbar")
	
	_create_boundaries()
	_spawn_pet()
	
	# 从持久化恢复共享状态
	window_mode = SettingsManager.get_int("window_mode", 0)
	behavior_mode = SettingsManager.get_int("behavior_mode", 0)
	
	# ── 初始化子管理器 ──
	_setup_managers()
	
	# 从持久化恢复克隆体 + 行为指令
	clone_mgr.restore_clones()
	if behavior_mode == 1:
		EventBus.behavior_mode_changed.emit(1)
	
	# 启动任务栏样式守护 Timer
	if win_manager and win_manager.has_method("EnsureHiddenFromTaskbar"):
		var taskbar_timer = Timer.new()
		taskbar_timer.wait_time = 5.0
		taskbar_timer.autostart = true
		taskbar_timer.timeout.connect(_guard_taskbar_style)
		add_child(taskbar_timer)
	
	# 挂载提醒系统
	_setup_reminder_system()
	_setup_todo_system()
	_setup_pet_chatter()
	_setup_platform_style_panel()
	_setup_hotkey_manager()
	_setup_memo_popup()
	_setup_pet_profile_panel()
	_setup_game_terminal()
	_setup_file_search_panel()
	
	# 触发首次启用日期记录 (首次运行时自动写入)
	SettingsManager.get_first_launch_date()
	
	# 监听屏幕穿越开关
	EventBus.setting_toggled.connect(_on_main_setting_toggled)
	
	# 恢复 UI 主题色
	var saved_ui_hue = SettingsManager.get_ui_hue()
	if saved_ui_hue >= 0:
		EventBus.ui_hue = float(saved_ui_hue) / 360.0
	
	_setup_system_tray()
	_setup_update_checker()
	_setup_input_monitor()
	_setup_file_operations()

# ── 子管理器初始化 ──

func _setup_managers() -> void:
	# 直接用 Script.new() 创建，确保 _process() 等虚方法在构造时注册
	var GhostWallManager = load("res://core/ghost_wall_manager.gd")
	ghost_wall_mgr = GhostWallManager.new()
	add_child(ghost_wall_mgr)
	ghost_wall_mgr.setup(self)
	
	var HitRegionManager = load("res://core/hit_region_manager.gd")
	hit_region_mgr = HitRegionManager.new()
	add_child(hit_region_mgr)
	hit_region_mgr.setup(self)
	
	var CloneManager = load("res://core/clone_manager.gd")
	clone_mgr = CloneManager.new()
	add_child(clone_mgr)
	clone_mgr.setup(self)
	
	var FarewellManager = load("res://core/farewell_manager.gd")
	farewell_mgr = FarewellManager.new()
	add_child(farewell_mgr)
	farewell_mgr.setup(self)

# ── 系统托盘 ──

func _setup_system_tray() -> void:
	if ClassDB.class_exists("StatusIndicator"):
		var tray = ClassDB.instantiate("StatusIndicator")
		
		if ResourceLoader.exists("res://icon.png"):
			tray.icon = load("res://icon.png")
		elif ResourceLoader.exists("res://icon.svg"):
			tray.icon = load("res://icon.svg")
		else:
			var grad = Gradient.new()
			grad.colors = PackedColorArray([
				Color.WHITE,
				Color.WHITE,
				Color(0.20, 0.60, 1.00, 1.0),
				Color(0.10, 0.30, 0.85, 1.0),
				Color(0.05, 0.15, 0.45, 1.0),
				Color(0.05, 0.15, 0.45, 1.0),
				Color.WHITE,
				Color.WHITE,
				Color(0.02, 0.08, 0.25, 1.0),
				Color(0.02, 0.08, 0.25, 1.0),
				Color.TRANSPARENT
			])
			grad.offsets = PackedFloat32Array([
				0.0, 0.22,
				0.24, 0.50,
				0.52, 0.70,
				0.72, 0.82,
				0.84, 0.96,
				0.98
			])
			var tex = GradientTexture2D.new()
			tex.gradient = grad
			tex.width = 64
			tex.height = 64
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.5)
			tex.fill_to = Vector2(0.5, 0.0)
			tray.icon = tex
			
		tray.tooltip = "桌面宠物"
		
		var tray_menu = PopupMenu.new()
		tray_menu.add_item("关闭 (告别退出)", 1)
		tray_menu.add_separator()
		tray_menu.add_item("强制退出", 2)
		tray_menu.id_pressed.connect(func(id: int):
			if id == 1:
				quit_with_farewell()
			elif id == 2:
				save_exit_reports()
				get_tree().quit()
		)
		add_child(tray_menu)
		
		add_child(tray)
		tray.menu = tray_menu.get_path()
		print("[DesktopPet] 系统托盘托管成功启动！")

# ── 窗口设置 ──

func _setup_window() -> void:
	screen_rect = DisplayServer.screen_get_usable_rect()
	
	var window := get_window()
	# 窗口位置/大小比屏幕各多 1px (四边各扩 1px)
	# 修复: 窗口与屏幕完全等大时, 某些 Windows+GPU 组合会触发全屏独占检测,
	# 跳过 DWM 桌面合成, 导致透明背景变黑屏 (Godot 已知问题 #109693/#107582)
	window.position = Vector2i(screen_rect.position.x - 1, screen_rect.position.y - 1)
	window.size = Vector2i(screen_rect.size.x + 2, screen_rect.size.y + 2)
	window.transparent = true
	window.borderless = true
	window.always_on_top = true
	window.gui_embed_subwindows = false
	
	get_viewport().transparent_bg = true
	
	print("[DesktopPet] 屏幕可用区域: ", screen_rect)
	print("[DesktopPet] 窗口大小: ", window.size, " (±1px 防全屏独占黑屏)")

# ── 屏幕边界 ──
var _wall_left: StaticBody2D
var _wall_right: StaticBody2D

func _create_boundaries() -> void:
	var vp_size := get_viewport_rect().size
	boundary_size = vp_size
	
	var w := vp_size.x
	var h := vp_size.y
	var thickness := 400.0
	
	print("[DesktopPet] 视口尺寸: ", vp_size, " (以此创建边界)")
	
	_add_wall(Vector2(w / 2.0, h + thickness / 2.0), Vector2(w * 2, thickness))
	_add_wall(Vector2(w / 2.0, -thickness / 2.0), Vector2(w * 2, thickness))
	_wall_left = _add_wall(Vector2(-thickness / 2.0, h / 2.0), Vector2(thickness, h * 2))
	_wall_right = _add_wall(Vector2(w + thickness / 2.0, h / 2.0), Vector2(thickness, h * 2))
	
	# 从持久化恢复屏幕穿越状态
	if SettingsManager.get_bool("screen_wrap", false):
		_set_side_walls_enabled(false)
	
	print("[DesktopPet] 边界墙已创建 — 地面y=", h, " 右墙x=", w)

func _add_wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = pos
	
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.3
	wall.physics_material_override = mat
	
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	
	wall.add_child(collision)
	add_child(wall)
	return wall

## 启用/禁用左右墙壁碰撞 (屏幕穿越模式)
func _set_side_walls_enabled(enabled: bool) -> void:
	if is_instance_valid(_wall_left):
		_wall_left.get_child(0).disabled = not enabled
	if is_instance_valid(_wall_right):
		_wall_right.get_child(0).disabled = not enabled

# ── 宠物实例化 ──

func _spawn_pet() -> void:
	pet_instance = pet_scene.instantiate()
	pet_instance.screen_rect = screen_rect
	pet_instance.boundary_size = boundary_size
	pet_instance.window_mode = window_mode
	pet_instance.set_meta("pet_index", 0)
	# 从持久化恢复原体颜色
	var saved_color = SettingsManager.get_pet_color(0)
	if saved_color.hue >= 0:
		pet_instance.palette = _PetColorPalette.new()
		pet_instance.palette.set_hue_degrees(saved_color.hue)
		pet_instance.palette.set_sat_percent(saved_color.sat)
		pet_instance.palette.set_val_percent(saved_color.val)
	
	# ── 入场动画 ──
	# 先设透明再加入场景树, 避免第一帧闪现
	pet_instance.modulate = Color(1, 1, 1, 0)
	add_child(pet_instance)
	pet_instances.append(pet_instance)
	perform_side_entrance(pet_instance)

## 统一侧方入场动画 (从屏幕边缘空中抛入)
## 宠物必须已在场景树中 (add_child 之后调用)
func perform_side_entrance(pet: RigidBody2D) -> void:
	var from_left: bool = randf() < 0.5
	var ag = SettingsManager.get_bool("anti_gravity", false)
	var g_sign: float = -1.0 if ag else 1.0
	
	# 出生位置: 屏幕边缘空中 (随机高度, 重力拉出抛物线)
	var spawn_x: float = 35.0 if from_left else boundary_size.x - 35.0
	var spawn_y: float
	if ag:
		spawn_y = boundary_size.y * randf_range(0.6, 0.85)
	else:
		spawn_y = boundary_size.y * randf_range(0.15, 0.4)
	pet.position = Vector2(spawn_x, spawn_y)
	
	# 淡入
	pet.modulate = Color(1, 1, 1, 0)
	var fade_tw = pet.create_tween()
	fade_tw.tween_property(pet, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)
	
	# 临时关闭屏幕穿越 (防止被传送到对面)
	var had_wrap: bool = pet.screen_wrap
	if had_wrap:
		pet.screen_wrap = false
	
	# 延迟一帧施加入场冲量
	var dir: float = 1.0 if from_left else -1.0
	_apply_entrance.call_deferred(pet, dir, had_wrap, g_sign)
	
	print("[DesktopPet] 宠物从%s侧空中入场" % ("左" if from_left else "右"))

## 入场冲量: 水平推入 + 轻微上抛, 重力形成自然抛物线
func _apply_entrance(pet: RigidBody2D, dir: float, had_wrap: bool, g_sign: float) -> void:
	if not is_instance_valid(pet):
		return
	pet.apply_central_impulse(Vector2(
		dir * randf_range(350, 550),
		g_sign * randf_range(-120, -50),
	))
	pet.apply_torque_impulse(dir * randf_range(2000, 5000))
	
	# 恢复屏幕穿越
	if had_wrap:
		_restore_wrap_after_entrance.call_deferred(pet)

## 等宠物离开边缘后恢复屏幕穿越 (防止刚入场就被传送到对面)
func _restore_wrap_after_entrance(pet: RigidBody2D) -> void:
	if not is_instance_valid(pet):
		return
	while is_instance_valid(pet):
		var x = pet.global_position.x
		if x > 80.0 and x < boundary_size.x - 80.0:
			break
		await get_tree().process_frame
	if is_instance_valid(pet):
		pet.screen_wrap = true

# ── 提醒系统 ──

func _setup_reminder_system() -> void:
	# 后台服务: 定时检查提醒 (UI 由装置终端 Tab 负责)
	var service_script = load("res://ui/reminder_service.gd")
	if service_script:
		var service_node = Node.new()
		service_node.set_script(service_script)
		add_child(service_node)
	
	var bubble_script = load("res://ui/reminder_bubble.gd")
	if bubble_script:
		var bubble_node = CanvasLayer.new()
		bubble_node.set_script(bubble_script)
		add_child(bubble_node)
		if pet_instance and bubble_node.has_method("link_pet"):
			bubble_node.link_pet(pet_instance)

# ── 待办事项系统 ──

func _setup_todo_system() -> void:
	var todo_script = load("res://ui/todo_panel.gd")
	if todo_script:
		var todo_node = CanvasLayer.new()
		todo_node.set_script(todo_script)
		add_child(todo_node)
	# 主动提醒系统
	var prompt_script = load("res://ui/todo_prompt.gd")
	if prompt_script:
		var prompt_node = CanvasLayer.new()
		prompt_node.set_script(prompt_script)
		add_child(prompt_node)
		if pet_instance and prompt_node.has_method("link_pet"):
			prompt_node.link_pet(pet_instance)

func _setup_platform_style_panel() -> void:
	var script = load("res://ui/platform_style_panel.gd")
	if script:
		var node = CanvasLayer.new()
		node.set_script(script)
		add_child(node)

# ── 宠物碎碎念 ──

func _setup_pet_chatter() -> void:
	var chatter_script = load("res://ui/pet_chatter.gd")
	if chatter_script:
		var chatter_node = Node.new()
		chatter_node.set_script(chatter_script)
		add_child(chatter_node)
		if pet_instance and chatter_node.has_method("link_pet"):
			chatter_node.link_pet(pet_instance)
		print("[DesktopPet] 宠物碎碎念系统已启动 (30分钟间隔)")


# ── 宠物档案面板 ──

func _setup_pet_profile_panel() -> void:
	var script = load("res://ui/pet_profile_panel.gd")
	if script:
		var node = CanvasLayer.new()
		node.set_script(script)
		add_child(node)

# ── 游戏终端面板 ──

func _setup_game_terminal() -> void:
	var script = load("res://ui/game_terminal/game_terminal.gd")
	if script:
		var node = CanvasLayer.new()
		node.set_script(script)
		add_child(node)

# ── 文件检索终端面板 ──

func _setup_file_search_panel() -> void:
	var script = load("res://ui/file_search/file_search_panel.gd")
	if script:
		var node = CanvasLayer.new()
		node.set_script(script)
		add_child(node)

# ── 版本更新检测 ──

func _setup_update_checker() -> void:
	var script = load("res://core/update_checker.gd")
	if script:
		var node = Node.new()
		node.set_script(script)
		add_child(node)

# ── 键鼠输入监控 ──

func _setup_input_monitor() -> void:
	if not ResourceLoader.exists("res://interop/InputMonitor.cs"):
		print("[InputMonitor] C# 脚本不存在, 跳过")
		return
	input_monitor = load("res://interop/InputMonitor.cs").new()
	add_child(input_monitor)
	# 默认启动监控 (用户可在设置中关闭, 后期加)
	if input_monitor.has_method("StartMonitoring"):
		input_monitor.call("StartMonitoring")
	# 连接手动触发信号
	if EventBus.has_signal("trigger_input_report"):
		EventBus.trigger_input_report.connect(_on_trigger_input_report)
	if EventBus.has_signal("trigger_window_report"):
		EventBus.trigger_window_report.connect(_on_trigger_window_report)
	print("[InputMonitor] 键鼠+窗口采集系统已挂载")

# ── 文件拖放操作桥接 ──

func _setup_file_operations() -> void:
	if not ResourceLoader.exists("res://interop/FileOperations.cs"):
		print("[FileOps] C# 脚本不存在, 跳过")
		return
	file_ops = load("res://interop/FileOperations.cs").new()
	add_child(file_ops)
	print("[FileOps] 文件操作桥接已加载")
	
	# 监听文件拖放事件
	get_window().files_dropped.connect(_on_files_dropped)
	print("[FileOps] 文件拖放监听已注册")
	
	# 加载 Everything 搜索引擎
	_setup_everything_search()

func _setup_everything_search() -> void:
	if not ResourceLoader.exists("res://interop/FileSearchEngine.cs"):
		print("[FileSearch] C# 脚本不存在, 跳过")
		return
	var node = load("res://interop/FileSearchEngine.cs").new()
	add_child(node)
	print("[FileSearch] 文件搜索引擎已加载")

func _on_files_dropped(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	# 只有拖到原体宠物身上才触发
	if pet_instance and is_instance_valid(pet_instance) and pet_instance.is_mouse_on_pet():
		if pet_instance.file_drop:
			pet_instance.file_drop.receive(paths)
			print("[FileOps] 接收拖放文件: %d 个" % paths.size())

func _on_trigger_input_report() -> void:
	if not input_monitor or not input_monitor.has_method("GetFullSnapshot"):
		return
	var snapshot: Dictionary = input_monitor.call("GetFullSnapshot")
	_save_input_report(snapshot)

func _on_trigger_window_report() -> void:
	if not input_monitor or not input_monitor.has_method("GetWindowStats"):
		return
	var win_stats: Dictionary = input_monitor.call("GetWindowStats")
	_save_window_report(win_stats)

## 退出时自动保存报告 (供 farewell_manager 调用)
func save_exit_reports() -> void:
	if not input_monitor:
		return
	if input_monitor.has_method("GetFullSnapshot"):
		var snapshot: Dictionary = input_monitor.call("GetFullSnapshot")
		_save_input_report(snapshot)
	if input_monitor.has_method("GetWindowStats"):
		var win_stats: Dictionary = input_monitor.call("GetWindowStats")
		_save_window_report(win_stats)
	print("[InputMonitor] 退出保存: 报告已归档")

# ═══════════════════════════════════════════════
#  报告生成 (当天叠加模式)
# ═══════════════════════════════════════════════

## 获取今天的日期字符串 (MM-DD)
func _today_date_key() -> String:
	var td = Time.get_datetime_dict_from_system()
	return "%02d-%02d" % [td.month, td.day]

## 查找今天已有的同类型报告 (返回在 logs 中的索引, -1 表示没有)
func _find_today_report(logs: Array, tag: String) -> int:
	var today = _today_date_key()
	for i in range(logs.size()):
		var entry: Dictionary = logs[i]
		if entry.get("source", "") != "pet":
			continue
		var tags: Array = entry.get("tags", [])
		if tag not in tags:
			continue
		# 检查创建日期是否为今天 (格式: 2026-05-15 23:08:36 → 取 MM-DD)
		var created: String = entry.get("created", "")
		if created.length() >= 10:
			var parts = created.split("-")
			if parts.size() >= 3:
				var entry_date = "%s-%s" % [parts[1], parts[2].substr(0, 2)]
				if entry_date == today:
					return i
	return -1

# ── 输入报告 ──

func _save_input_report(snapshot: Dictionary) -> void:
	var now = Time.get_datetime_string_from_system(false, true)
	var td = Time.get_datetime_dict_from_system()
	var logs = SettingsManager.get_datalogs()

	var existing_idx = _find_today_report(logs, "sys:input")
	if existing_idx >= 0:
		var existing: Dictionary = logs[existing_idx]
		var old_data: Dictionary = existing.get("input_data", {})
		var last_raw: Dictionary = existing.get("input_data_raw", old_data)
		var merged = _merge_input_data(old_data, snapshot, last_raw)
		var delta = _diff_input(old_data, merged)
		existing["input_data"] = merged
		existing["input_data_raw"] = snapshot.duplicate(true)
		existing["input_delta"] = delta
		existing["content"] = _format_input_report(merged)
		existing["updated"] = now
		existing["title"] = "输入行为报告 %02d-%02d (累计)" % [td.month, td.day]
		existing["merge_count"] = existing.get("merge_count", 1) + 1
		logs[existing_idx] = existing
		SettingsManager.save_datalogs(logs)
		print("[InputMonitor] 叠加: +%d 击键 (第 %d 次)" % [delta.get("keystrokes", 0), existing.get("merge_count", 2)])
	else:
		var entry = {
			"id": "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000],
			"title": "输入行为报告 %02d-%02d %02d:%02d" % [td.month, td.day, td.hour, td.minute],
			"content": _format_input_report(snapshot),
			"input_data": snapshot.duplicate(true),
			"input_data_raw": snapshot.duplicate(true),
			"tags": ["sys:input", "auto"],
			"source": "pet",
			"created": now,
			"updated": now,
			"merge_count": 1,
		}
		logs.insert(0, entry)
		SettingsManager.save_datalogs(logs)
		print("[InputMonitor] 新建: 输入报告已写入")

## 合并输入数据 (跨会话安全累积)
func _merge_input_data(old: Dictionary, new_snap: Dictionary, last_raw: Dictionary) -> Dictionary:
	var merged: Dictionary = {}
	merged["session_sec"] = int(old.get("session_sec", 0)) + _raw_delta(last_raw, new_snap, "session_sec")
	merged["total_keystrokes"] = int(old.get("total_keystrokes", 0)) + _raw_delta(last_raw, new_snap, "total_keystrokes")
	merged["keys"] = _merge_dict_values(old.get("keys", {}), new_snap.get("keys", {}), last_raw.get("keys", {}))
	merged["combos"] = _merge_dict_values(old.get("combos", {}), new_snap.get("combos", {}), last_raw.get("combos", {}))
	var old_m: Dictionary = old.get("mouse", {})
	var new_m: Dictionary = new_snap.get("mouse", {})
	var last_m: Dictionary = last_raw.get("mouse", {})
	merged["mouse"] = {}
	for key in ["left_clicks", "right_clicks", "middle_clicks", "distance_px"]:
		merged["mouse"][key] = int(old_m.get(key, 0)) + _raw_delta(last_m, new_m, key)
	merged["timestamp"] = new_snap.get("timestamp", "")
	return merged

## C# 原始增量: 新值 < 旧原始值 → C# 重启了, 新值本身就是增量
func _raw_delta(last_raw: Dictionary, new_snap: Dictionary, key: String) -> int:
	var new_v = int(new_snap.get(key, 0))
	var last_v = int(last_raw.get(key, 0))
	return new_v if new_v < last_v else (new_v - last_v)

## 逐 key 累加增量 (按键/组合键字典)
func _merge_dict_values(old_dict: Dictionary, new_dict: Dictionary, last_dict: Dictionary) -> Dictionary:
	var result = old_dict.duplicate(true)
	for k in new_dict:
		var new_v = int(new_dict[k])
		var last_v = int(last_dict.get(k, 0))
		var d = new_v if new_v < last_v else (new_v - last_v)
		result[k] = int(result.get(k, 0)) + d
	return result

## 两份累积数据的差值 (用于 UI 绿字)
func _diff_input(old: Dictionary, merged: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	delta["keystrokes"] = int(merged.get("total_keystrokes", 0)) - int(old.get("total_keystrokes", 0))
	
	var old_keys: Dictionary = old.get("keys", {})
	var new_keys: Dictionary = merged.get("keys", {})
	var keys_delta: Dictionary = {}
	for k in new_keys:
		var d = int(new_keys[k]) - int(old_keys.get(k, 0))
		if d > 0:
			keys_delta[k] = d
	delta["keys"] = keys_delta
	
	var old_combos: Dictionary = old.get("combos", {})
	var new_combos: Dictionary = merged.get("combos", {})
	var combos_delta: Dictionary = {}
	for k in new_combos:
		var d = int(new_combos[k]) - int(old_combos.get(k, 0))
		if d > 0:
			combos_delta[k] = d
	delta["combos"] = combos_delta
	
	var old_m: Dictionary = old.get("mouse", {})
	var new_m: Dictionary = merged.get("mouse", {})
	delta["left_clicks"] = int(new_m.get("left_clicks", 0)) - int(old_m.get("left_clicks", 0))
	delta["right_clicks"] = int(new_m.get("right_clicks", 0)) - int(old_m.get("right_clicks", 0))
	delta["distance_px"] = int(new_m.get("distance_px", 0)) - int(old_m.get("distance_px", 0))
	return delta

func _format_input_report(snap: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("=== 输入行为统计报告 ===")
	lines.append("会话时长: %d 秒" % snap.get("session_sec", 0))
	lines.append("总击键: %d 次" % snap.get("total_keystrokes", 0))
	lines.append("")
	
	# 按键 (全部)
	var keys: Dictionary = snap.get("keys", {})
	if keys.size() > 0:
		lines.append("-- 按键统计 (全量) --")
		var sorted_keys = []
		for k in keys:
			sorted_keys.append([k, keys[k]])
		sorted_keys.sort_custom(func(a, b): return a[1] > b[1])
		for i in range(sorted_keys.size()):
			lines.append("  %s: %d" % [sorted_keys[i][0], sorted_keys[i][1]])
		lines.append("")
	
	# 组合键
	var combos: Dictionary = snap.get("combos", {})
	if combos.size() > 0:
		lines.append("-- 组合键统计 --")
		var sorted_combos = []
		for k in combos:
			sorted_combos.append([k, combos[k]])
		sorted_combos.sort_custom(func(a, b): return a[1] > b[1])
		for item in sorted_combos:
			lines.append("  %s: %d" % [item[0], item[1]])
		lines.append("")
	
	# 鼠标
	var mouse: Dictionary = snap.get("mouse", {})
	if mouse.size() > 0:
		lines.append("-- 鼠标统计 --")
		lines.append("  左键: %d 次" % mouse.get("left_clicks", 0))
		lines.append("  右键: %d 次" % mouse.get("right_clicks", 0))
		lines.append("  中键: %d 次" % mouse.get("middle_clicks", 0))
		var dist_px = mouse.get("distance_px", 0)
		if dist_px > 0:
			lines.append("  移动: %.1f m (估算)" % (float(dist_px) / 3780.0))  # 96dpi ≈ 3780px/m

	return "\n".join(lines)

# ── 窗口报告 ──

func _save_window_report(win_stats: Dictionary) -> void:
	var now = Time.get_datetime_string_from_system(false, true)
	var td = Time.get_datetime_dict_from_system()
	var logs = SettingsManager.get_datalogs()

	var existing_idx = _find_today_report(logs, "sys:window")
	if existing_idx >= 0:
		var existing: Dictionary = logs[existing_idx]
		var old_data: Dictionary = existing.get("window_data", {})
		var last_raw: Dictionary = existing.get("window_data_raw", old_data)
		var merged = _merge_window_data(old_data, win_stats, last_raw)
		var delta = _diff_window(old_data, merged)
		existing["window_data"] = merged
		existing["window_data_raw"] = win_stats.duplicate(true)
		existing["window_delta"] = delta
		existing["updated"] = now
		existing["title"] = "窗口活动报告 %02d-%02d (累计)" % [td.month, td.day]
		var app_count = merged.size()
		var total_sec = 0
		for proc_name in merged:
			total_sec += int(merged[proc_name].get("focus_sec", 0))
		var summary = "检测到 %d 个应用" % app_count
		if total_sec >= 60:
			summary += ", 累计前台 %dm" % (total_sec / 60)
		existing["content"] = summary
		existing["merge_count"] = existing.get("merge_count", 1) + 1
		logs[existing_idx] = existing
		SettingsManager.save_datalogs(logs)
		print("[InputMonitor] 叠加: 窗口报告合并 (第 %d 次)" % existing.get("merge_count", 2))
	else:
		var app_count = win_stats.size()
		var total_sec = 0
		for proc_name in win_stats:
			total_sec += int(win_stats[proc_name].get("focus_sec", 0))
		var summary = "检测到 %d 个应用" % app_count
		if total_sec >= 60:
			summary += ", 累计前台 %dm" % (total_sec / 60)
		var entry = {
			"id": "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000],
			"title": "窗口活动报告 %02d-%02d %02d:%02d" % [td.month, td.day, td.hour, td.minute],
			"content": summary,
			"window_data": win_stats.duplicate(true),
			"window_data_raw": win_stats.duplicate(true),
			"tags": ["sys:window", "auto"],
			"source": "pet",
			"created": now,
			"updated": now,
			"merge_count": 1,
		}
		logs.insert(0, entry)
		SettingsManager.save_datalogs(logs)
		print("[InputMonitor] 新建: 窗口报告 (%d 个应用)" % app_count)

## 合并窗口数据 (跨会话安全累积)
func _merge_window_data(old_data: Dictionary, new_data: Dictionary, last_raw: Dictionary) -> Dictionary:
	var merged = old_data.duplicate(true)
	for proc_name in new_data:
		var new_info: Dictionary = new_data[proc_name]
		var new_sec = int(new_info.get("focus_sec", 0))
		if merged.has(proc_name):
			var existing_info: Dictionary = merged[proc_name]
			var old_sec = int(existing_info.get("focus_sec", 0))
			var last_sec = int(last_raw.get(proc_name, {}).get("focus_sec", 0))
			var d = new_sec if new_sec < last_sec else (new_sec - last_sec)
			existing_info["focus_sec"] = old_sec + d
			var old_titles: Array = existing_info.get("titles", [])
			for t in new_info.get("titles", []):
				if t not in old_titles:
					old_titles.append(t)
			existing_info["titles"] = old_titles
			existing_info["last_active"] = new_info.get("last_active", existing_info.get("last_active", ""))
			merged[proc_name] = existing_info
		else:
			merged[proc_name] = new_info.duplicate(true) if new_info is Dictionary else new_info
	return merged

## 窗口增量 (merged - old, 用于 UI 绿字)
func _diff_window(old_data: Dictionary, merged: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	for proc_name in merged:
		var merged_sec = int(merged[proc_name].get("focus_sec", 0))
		var old_sec = int(old_data.get(proc_name, {}).get("focus_sec", 0))
		var diff = merged_sec - old_sec
		if diff > 0:
			delta[proc_name] = {"focus_sec_delta": diff}
		if not old_data.has(proc_name):
			delta[proc_name] = {"focus_sec_delta": merged_sec, "is_new": true}
	return delta

# ── 任务栏样式守护 ──

func _guard_taskbar_style() -> void:
	if win_manager and win_manager.has_method("EnsureHiddenFromTaskbar"):
		var fixed: bool = win_manager.call("EnsureHiddenFromTaskbar")
		if fixed:
			print("[DesktopPet] 任务栏样式守护：已自动修复 ToolWindow 标记")

func _on_main_setting_toggled(setting_id: String, is_on: bool) -> void:
	if setting_id == "screen_wrap":
		_set_side_walls_enabled(not is_on)

# ── 告别退出 (委托给 farewell_manager) ──

func quit_with_farewell() -> void:
	if farewell_mgr:
		farewell_mgr.quit_with_farewell()
	else:
		get_tree().quit()

# ── 外部访问接口 (供 context_menu/fall.gd 等调用) ──

func reorganize_quiet_queue() -> void:
	if clone_mgr:
		clone_mgr.reorganize_quiet_queue()

# ── 全局快捷键管理器 ──

func _setup_hotkey_manager() -> void:
	var script = load("res://core/hotkey_manager.gd")
	if script:
		hotkey_mgr = Node.new()
		hotkey_mgr.set_script(script)
		add_child(hotkey_mgr)
		if hotkey_mgr.has_method("setup"):
			hotkey_mgr.setup(self)

# ── 快速备忘弹窗 ──

func _setup_memo_popup() -> void:
	var script = load("res://ui/memo_popup.gd")
	if script:
		var node = CanvasLayer.new()
		node.set_script(script)
		add_child(node)

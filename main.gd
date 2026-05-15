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

# ── 共享状态 (被子管理器读写) ──
var window_mode: int = 0  # 0=FREE, 1=CONFINED, 2=REPELLED
var behavior_mode: int = 0  # 0=FREE, 1=QUIET

# ── 子管理器引用 ──
var ghost_wall_mgr: Node
var hit_region_mgr: Node
var clone_mgr: Node
var farewell_mgr: Node
var game_mgr: CanvasLayer


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
	_setup_game_system()
	_setup_pet_profile_panel()
	
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
	
	# ── 入场动画: 从屏幕左/右侧外弹入 ──
	var from_left: bool = randf() < 0.5
	var roll_style: bool = randf() < 0.5  # true=滚动入场, false=斜抛弹入
	var spawn_margin := 60.0
	var spawn_x: float
	if from_left:
		spawn_x = -spawn_margin
	else:
		spawn_x = boundary_size.x + spawn_margin
	# 地面附近 (地面墙在 boundary_size.y，宠物半径 30)
	var spawn_y := boundary_size.y - 50.0
	pet_instance.position = Vector2(spawn_x, spawn_y)
	
	# 临时禁用入场侧的墙壁，让宠物从外面穿入
	var entry_wall: StaticBody2D = _wall_left if from_left else _wall_right
	if is_instance_valid(entry_wall):
		entry_wall.get_child(0).disabled = true
	
	add_child(pet_instance)
	pet_instances.append(pet_instance)
	
	# 入场期间临时关闭屏幕穿越 (防止 _update_screen_wrap 传送/画幽灵)
	var had_wrap: bool = pet_instance.screen_wrap
	if had_wrap:
		pet_instance.screen_wrap = false
	
	# 延迟一帧施加入场冲量 (等 RigidBody2D 物理就绪)
	var dir: float = 1.0 if from_left else -1.0
	_apply_entrance.call_deferred(pet_instance, dir, entry_wall, had_wrap, roll_style)
	
	var style_name := "滚动" if roll_style else "弹跳"
	print("[DesktopPet] 宠物从%s侧%s入场" % [("左" if from_left else "右"), style_name])

## 入场冲量 + 墙壁恢复
func _apply_entrance(pet: RigidBody2D, dir: float, wall: StaticBody2D, had_wrap: bool, is_roll: bool) -> void:
	if not is_instance_valid(pet):
		return
	if is_roll:
		# 滚动: 沿地面平推 + 强旋转，优雅自然
		pet.apply_central_impulse(Vector2(
			dir * randf_range(400, 600),
			randf_range(-50, -20),  # 微微离地，不会飞起
		))
		pet.apply_torque_impulse(dir * randf_range(4000, 7000))
	else:
		# 斜抛: 高抛物线弹入
		pet.apply_central_impulse(Vector2(
			dir * randf_range(600, 900),
			randf_range(-550, -380),
		))
		pet.apply_torque_impulse(dir * randf_range(2000, 4000))
	
	# 等宠物进入屏幕后恢复墙壁 + 屏幕穿越
	_restore_after_entrance.call_deferred(pet, wall, had_wrap)

## 轮询等待宠物进入屏幕范围后恢复墙壁碰撞和屏幕穿越
func _restore_after_entrance(pet: RigidBody2D, wall: StaticBody2D, had_wrap: bool) -> void:
	if not is_instance_valid(pet):
		return
	# 等宠物 x 进入安全范围 (留 80px 余量避免卡墙)
	while is_instance_valid(pet):
		var x = pet.global_position.x
		if x > 80.0 and x < boundary_size.x - 80.0:
			break
		await get_tree().process_frame
	# 恢复屏幕穿越
	if had_wrap and is_instance_valid(pet):
		pet.screen_wrap = true
	# 墙壁: 屏幕穿越模式下不恢复
	if not had_wrap and is_instance_valid(wall):
		wall.get_child(0).disabled = false

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

# ── 游戏系统 ──

func _setup_game_system() -> void:
	var gm_script = load("res://core/game_manager.gd")
	if gm_script:
		game_mgr = CanvasLayer.new()
		game_mgr.set_script(gm_script)
		add_child(game_mgr)
		EventBus.launch_game.connect(func(game_id: String):
			if game_mgr and game_mgr.has_method("launch_game"):
				game_mgr.launch_game(game_id, pet_instance)
		)
		EventBus.launch_game_auto.connect(func(game_id: String):
			if game_mgr and game_mgr.has_method("launch_game_auto"):
				game_mgr.launch_game_auto(game_id, pet_instance)
		)
		print("[DesktopPet] 游戏系统已就绪 (", game_mgr.get_installed_games().size(), " 个游戏)")

# ── 宠物档案面板 ──

func _setup_pet_profile_panel() -> void:
	var script = load("res://ui/pet_profile_panel.gd")
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

func _on_trigger_input_report() -> void:
	if not input_monitor or not input_monitor.has_method("GetFullSnapshot"):
		return
	var snapshot: Dictionary = input_monitor.call("GetFullSnapshot")
	# 写入机体记录
	var now = Time.get_datetime_string_from_system(false, true)
	var td = Time.get_datetime_dict_from_system()
	var entry = {
		"id": "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000],
		"title": "输入行为报告 %02d-%02d %02d:%02d" % [td.month, td.day, td.hour, td.minute],
		"content": _format_input_report(snapshot),
		"tags": ["sys:input", "auto"],
		"source": "pet",
		"created": now,
		"updated": now,
	}
	var logs = SettingsManager.get_datalogs()
	logs.insert(0, entry)
	SettingsManager.save_datalogs(logs)
	print("[InputMonitor] 手动触发: 已写入机体记录")

func _format_input_report(snap: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("=== 输入行为统计报告 ===")
	lines.append("会话时长: %d 秒" % snap.get("session_sec", 0))
	lines.append("总击键: %d 次" % snap.get("total_keystrokes", 0))
	lines.append("")
	
	# 按键 Top 10
	var keys: Dictionary = snap.get("keys", {})
	if keys.size() > 0:
		lines.append("-- 按键排行 (Top 10) --")
		var sorted_keys = []
		for k in keys:
			sorted_keys.append([k, keys[k]])
		sorted_keys.sort_custom(func(a, b): return a[1] > b[1])
		for i in range(mini(10, sorted_keys.size())):
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

func _on_trigger_window_report() -> void:
	if not input_monitor or not input_monitor.has_method("GetWindowStats"):
		return
	var win_stats: Dictionary = input_monitor.call("GetWindowStats")
	var now = Time.get_datetime_string_from_system(false, true)
	var td = Time.get_datetime_dict_from_system()

	# 生成摘要 (用于列表预览) 和 JSON 数据 (用于卡片渲染)
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
		"window_data": win_stats,  # 结构化数据, 供卡片渲染
		"tags": ["sys:window", "auto"],
		"source": "pet",
		"created": now,
		"updated": now,
	}
	var logs = SettingsManager.get_datalogs()
	logs.insert(0, entry)
	SettingsManager.save_datalogs(logs)
	print("[InputMonitor] 手动触发: 窗口活动报告已写入 (%d 个应用)" % app_count)

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

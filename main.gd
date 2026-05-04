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
	_setup_pet_chatter()
	_setup_theme_panel()
	_setup_platform_style_panel()
	
	# 恢复 UI 主题色
	var saved_ui_hue = SettingsManager.get_ui_hue()
	if saved_ui_hue >= 0:
		EventBus.ui_hue = float(saved_ui_hue) / 360.0
	
	_setup_system_tray()

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
		tray_menu.add_item("让宠物休息 (告别退出)", 1)
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
	window.position = Vector2i(screen_rect.position)
	window.size = Vector2i(screen_rect.size)
	window.transparent = true
	window.borderless = true
	window.always_on_top = true
	window.gui_embed_subwindows = false
	
	get_viewport().transparent_bg = true
	
	print("[DesktopPet] 屏幕可用区域: ", screen_rect)
	print("[DesktopPet] 窗口大小: ", window.size)

# ── 屏幕边界 ──

func _create_boundaries() -> void:
	var vp_size := get_viewport_rect().size
	boundary_size = vp_size
	
	var w := vp_size.x
	var h := vp_size.y
	var thickness := 400.0
	
	print("[DesktopPet] 视口尺寸: ", vp_size, " (以此创建边界)")
	
	_add_wall(Vector2(w / 2.0, h + thickness / 2.0), Vector2(w * 2, thickness))
	_add_wall(Vector2(w / 2.0, -thickness / 2.0), Vector2(w * 2, thickness))
	_add_wall(Vector2(-thickness / 2.0, h / 2.0), Vector2(thickness, h * 2))
	_add_wall(Vector2(w + thickness / 2.0, h / 2.0), Vector2(thickness, h * 2))
	
	print("[DesktopPet] 边界墙已创建 — 地面y=", h, " 右墙x=", w)

func _add_wall(pos: Vector2, size: Vector2) -> void:
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
	pet_instance.position = Vector2(
		boundary_size.x / 2.0,
		boundary_size.y / 3.0
	)
	add_child(pet_instance)
	pet_instances.append(pet_instance)
	
	print("[DesktopPet] 宠物生成于: ", pet_instance.position)

# ── 提醒系统 ──

func _setup_reminder_system() -> void:
	var panel_script = load("res://ui/reminder_panel.gd")
	if panel_script:
		var panel_node = CanvasLayer.new()
		panel_node.set_script(panel_script)
		add_child(panel_node)
	
	var bubble_script = load("res://ui/reminder_bubble.gd")
	if bubble_script:
		var bubble_node = CanvasLayer.new()
		bubble_node.set_script(bubble_script)
		add_child(bubble_node)
		if pet_instance and bubble_node.has_method("link_pet"):
			bubble_node.link_pet(pet_instance)

func _setup_theme_panel() -> void:
	var theme_script = load("res://ui/theme_panel.gd")
	if theme_script:
		var theme_node = CanvasLayer.new()
		theme_node.set_script(theme_script)
		add_child(theme_node)

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

# ── 任务栏样式守护 ──

func _guard_taskbar_style() -> void:
	if win_manager and win_manager.has_method("EnsureHiddenFromTaskbar"):
		var fixed: bool = win_manager.call("EnsureHiddenFromTaskbar")
		if fixed:
			print("[DesktopPet] 任务栏样式守护：已自动修复 ToolWindow 标记")

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

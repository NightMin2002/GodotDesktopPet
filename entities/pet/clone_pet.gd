# clone_pet.gd — 克隆分身控制器
# 继承原体 pet.gd 的全部物理/渲染/状态机，但剥离交互功能
# 克隆体完全自治: 自主走动、跳跃、物理碰撞，但不响应鼠标、不阻挡桌面点击
extends "res://entities/pet/pet.gd"

func _ready() -> void:
	is_clone = true
	# clone_hue_shift 由 main.gd 在 add_child 前设置
	super._ready()

func _unhandled_input(event: InputEvent) -> void:
	# 传递给状态机 (支持拖拽等交互)
	if current_state:
		current_state.input(event)
	# 不响应右键菜单 (菜单仅限原体)

func _init_hud_clock() -> void:
	# 克隆体不需要 HUD 时钟，创建隐藏占位避免其他代码 null 引用
	hud_clock_label = Label.new()
	hud_clock_label.visible = false
	add_child(hud_clock_label)

func _on_setting_toggled(setting_id: String, is_on: bool) -> void:
	# 只响应通用视觉设置，忽略时钟等原体专属功能
	if setting_id == "eye_track":
		eye_behavior.tracking_enabled = is_on
	elif setting_id == "shockwave":
		shockwave_enabled = is_on
	elif setting_id == "trail_fx":
		trail_enabled = is_on
	elif setting_id == "stroll":
		stroll_enabled = is_on
	elif setting_id == "anti_gravity":
		_set_anti_gravity(is_on)
	# hud_clock: 克隆体永远不显示，无需处理

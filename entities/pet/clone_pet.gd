# clone_pet.gd — 克隆分身控制器
# 继承原体 pet.gd 的全部物理/渲染/状态机，但剥离交互功能
# 克隆体完全自治: 自主走动、跳跃、物理碰撞，但不响应鼠标、不阻挡桌面点击
extends "res://entities/pet/pet.gd"

func _ready() -> void:
	is_clone = true
	# palette 由 clone_manager.gd 在 add_child 前设置
	super._ready()

func _unhandled_input(event: InputEvent) -> void:
	# 传递给状态机 (支持拖拽等交互)
	if current_state:
		current_state.input(event)
	# 不响应右键菜单 (菜单仅限原体)

func _on_setting_toggled(setting_id: String, is_on: bool) -> void:
	# 克隆体不支持的功能: 直接忽略
	if setting_id in ["hud_clock", "hud_wifi", "hud_pin"]:
		return
	# 其余全部复用原体逻辑
	super._on_setting_toggled(setting_id, is_on)

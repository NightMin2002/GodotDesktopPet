# dark_terminal.gd — 深色终端风主题
# 角标边框 + 扫描线 + 终端绿
class_name TodoThemeDarkTerminal extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.04, 0.06, 0.04),   # base: 深黑绿底
		Color(0.20, 0.92, 0.35),   # text: 终端绿
		Color(0.20, 0.92, 0.35),   # accent: 同色
		Color(0.95, 0.20, 0.15),   # danger: 红
		0.97,                       # alpha: 近不透明
		"bracket"                   # border: L 形角标
	)

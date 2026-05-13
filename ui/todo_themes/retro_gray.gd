# retro_gray.gd — 灰白复古风主题
# 像素九宫格边框 + 灰白色系
class_name TodoThemeRetroGray extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.78, 0.80, 0.84),   # base: 浅灰蓝底
		Color(0.10, 0.12, 0.18),   # text: 深色文字
		Color(0.25, 0.72, 0.40),   # accent: 绿
		Color(0.85, 0.25, 0.20),   # danger: 红
		0.97,                       # alpha: 近不透明
		"pixel"                     # border: 像素九宫格
	)

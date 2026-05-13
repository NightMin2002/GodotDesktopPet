# holo_glass.gd — 全息玻璃主题
# 磨砂圆角面板 + 棱镜色边框 + 半透明
class_name TodoThemeHoloGlass extends TodoThemeBase

func _init() -> void:
	_from_seeds(
		Color(0.12, 0.14, 0.22),   # base: 深蓝底
		Color(0.92, 0.94, 1.0),    # text: 近白
		Color(0.40, 0.70, 0.98),   # accent: 全息蓝
		Color(0.95, 0.35, 0.30),   # danger: 红
		0.72,                       # alpha: 半透明玻璃
		"glass"                     # border: 磨砂圆角
	)
	card_corner = 8   # 玻璃风更圆润

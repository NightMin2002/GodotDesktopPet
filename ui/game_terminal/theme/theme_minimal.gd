# theme_minimal.gd — 极简科幻风格主题
# 八角切角 + 脉冲角标 + 扫描线 — 第一版方案的现代机甲风
extends TerminalThemeBase

func get_frame_script() -> Script:
	return load("res://ui/game_terminal/theme/frame_minimal.gd")

# 色值和 StyleBox 全部使用基类默认实现

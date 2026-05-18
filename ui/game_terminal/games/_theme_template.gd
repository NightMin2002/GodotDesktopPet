# _theme_template.gd — 游戏专属主题模板
# 复制到 games/你的游戏/theme.gd，按需覆写
extends GameThemeOverride

# ══════════════════════════════════════════════
#  终端通用色值覆写
#  定义与 TerminalThemeBase 同名的方法即可覆写
#  返回 Color → 使用覆写值
#  返回 null  → 回退到终端全局主题
#  不定义     → 回退
# ══════════════════════════════════════════════

# func accent() -> Variant:
# 	return Color.from_hsv(0.55, 0.7, 0.95)

# func dim() -> Variant:
# 	return Color(0.45, 0.5, 0.55, 0.6)

# func bright() -> Variant:
# 	return Color(0.9, 0.95, 1.0, 0.95)

# func bg_deep() -> Variant:
# 	return Color(0.02, 0.03, 0.06, 0.96)

# ══════════════════════════════════════════════
#  游戏专属扩展色值
#  这些方法不在终端主题中，自行定义即可
#  game.gd 中访问:
#    var ov = GameTerminalStyles.game_override()
#    if ov and ov.has_method("grid_color"):
#        var c = ov.grid_color()
# ══════════════════════════════════════════════

# func grid_color() -> Color:
# 	return Color(0.3, 0.4, 0.5, 0.4)

# func piece_color_p1() -> Color:
# 	return Color.WHITE

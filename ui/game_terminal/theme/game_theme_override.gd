# game_theme_override.gd — 游戏专属主题覆写基类
# 放在 games/xxx/theme.gd 中 extends 本类，按需覆写色值
#
# 使用方式:
#   子类直接定义与 TerminalThemeBase 同名的方法即可覆写
#   返回 Color → 使用覆写值
#   返回 null  → 回退到终端全局主题
#   不定义方法 → 同上 (回退)
#
# 可覆写的终端色值 (与 TerminalThemeBase 对齐):
#   accent, dim, bright, bg_deep, border_base,
#   status_active, status_warning
#
# 也可以自由定义游戏专属扩展方法 (终端主题中不存在的):
#   func grid_color() -> Color: return Color(...)
#   func piece_color_p1() -> Color: return Color(...)
#
# game.gd 中访问专属方法:
#   var ov = GameTerminalStyles.game_override()
#   if ov and ov.has_method("grid_color"):
#       var c = ov.grid_color()
class_name GameThemeOverride
extends RefCounted

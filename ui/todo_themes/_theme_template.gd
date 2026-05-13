# _theme_template.gd — 新建主题参考模板
# 复制本文件到 ui/todo_themes/ 并重命名，按注释指引填入自己的风格
#
# 要点:
#   1. 继承 TodoThemeBase
#   2. _init() 中调用 _from_seeds() 传入 5 个种子色参数
#   3. 覆写 create_panel() 返回自定义边框面板 (可选)
#   4. 覆写 make_xxx() / apply_xxx() 实现独立风格 (可选)
#   5. 没覆写的方法自动使用基类的中性默认
#   6. 在 todo_panel.gd 的 _create_theme() 中切换使用
#
# 可用的辅助构建器 (基类提供，可选调用):
#   _build_pill_btn(text, bg, hover_bg, font_size)  — 圆角胶囊按钮
#   _build_text_btn(text, normal_color, hover_color) — 纯文字按钮
#   _make_btn(text, bg, border, fg, hover_fg, font_size) — 中性按钮
#
class_name TodoThemeExample extends TodoThemeBase

# ── 可选: 自定义边框面板类 ──
# 继承 PanelContainer，通过 _draw() 自绘边框装饰。
# 如果不需要自定义边框，删掉这个类，create_panel() 也不用覆写，
# 基类会返回纯色 + 1px 边框的默认面板。
#
class _ExamplePanel extends PanelContainer:
	var _t: TodoThemeBase

	func _init(t: TodoThemeBase) -> void:
		_t = t

	func _ready() -> void:
		# 清除默认 panel StyleBox，全部由 _draw 接管
		var s = StyleBoxFlat.new()
		s.bg_color = Color.TRANSPARENT
		add_theme_stylebox_override("panel", s)

	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		# 底色
		draw_rect(r, _t.bg_main)
		# 边框
		draw_rect(r, Color(_t.bd_light, 0.5), false, 1.0)
		# 标题栏
		var th := _t.title_bar_height
		draw_rect(Rect2(1, 1, r.size.x - 2, th), _t.bg_title)
		draw_line(Vector2(1, 1 + th), Vector2(r.size.x - 1, 1 + th), Color(_t.accent, 0.3))
		# ... 在这里添加任意装饰绘制

	# 可选: 如果面板需要响应 UI 主题色变化 (如全息玻璃的棱镜色边框)
	# func set_ui_hue(hue: float) -> void:
	#     _ui_hue = hue

func _init() -> void:
	# ── 种子色参数 ──
	# base:   面板底色调性 → 推算所有 bg_* 背景色
	# text:   主文字色 → 推算所有 tx_* 文字色、bd_* 边框色
	# accent: 强调色 → 完成/选中/新建按钮
	# danger: 危险色 → 删除/关闭
	# alpha:  整体透明度 (0.0~1.0)
	#
	# 暗色底 (base.v < 0.4) 和亮色底会自动切换推算方向
	_from_seeds(
		Color(0.12, 0.14, 0.20),   # base
		Color(0.88, 0.90, 0.96),   # text
		Color(0.35, 0.70, 0.90),   # accent
		Color(0.90, 0.30, 0.25),   # danger
		0.95                        # alpha
	)

	# ── 可选: 微调布局参数 ──
	# card_corner = 0           # 直角卡片
	# input_corner = 0          # 直角输入框
	# list_spacing = 10         # 列表项间距
	# checkbox_size_px = Vector2(24, 24)
	# progress_block_px = Vector2(10, 10)
	# panel_margins = [20, 18, 20, 26]  # 面板内边距 [左, 上, 右, 下]

	# ── 可选: 覆盖推算出的个别颜色 ──
	# bg_card_sel = Color(accent, 0.15)
	# bd_select = accent

# ═══════════════════════════════════════════════
#  可覆写的工厂方法一览
#  只覆写需要特殊风格的，其余自动继承中性默认
# ═══════════════════════════════════════════════

# ── 面板容器 ──
func create_panel() -> PanelContainer:
	return _ExamplePanel.new(self)

# ── 卡片样式 ──
# func make_card_style(is_done: bool, is_selected: bool) -> StyleBoxFlat:
# func make_card_hover_style(base: StyleBoxFlat) -> StyleBoxFlat:

# ── 按钮 ──
# func make_add_button(text: String) -> Button:
# func make_close_button(text: String) -> Button:
# func make_delete_button(text: String) -> Button:
# func make_theme_button(text: String) -> Button:

# ── 复选框 ──
# func make_checkbox(is_done: bool) -> Button:
#     示例: 用 ">>" 代替对勾 (赛博风)
#     示例: 用 _draw 回调绘制手绘粉笔线 (黑板风)
#     示例: 用圆角12的圆形 (便笺风)

# ── 样式应用 ──
# func apply_note_edit_style(edit: TextEdit) -> void:
#     示例: 透明背景融入面板 (蓝图风/黑板风)
# func apply_card_title_style(label: Label, is_done: bool, is_selected: bool) -> void:
#     示例: 完成项用半透明色模拟被擦掉 (黑板风)

# ── 进度指示器 ──
# func make_progress_indicator() -> Control:
#     返回自绘 Control，由 update_progress_indicator() 驱动
#     示例: 粉笔涂鸦条 (黑板风)、条形码 (小票风)、像素爱心 (掌机风)
# func update_progress_indicator(ctrl: Control, done: int, total: int) -> void:

# ── 自定义滚动条 ──
# func make_scrollbar() -> Control:
#     返回 TodoScrollbar 子类，默认像素风竖轨道 + 方块拇指
#     示例: 粉笔竖线 (黑板风)、霓虹发光条 (赛博风)、LCD栅格 (掌机风)

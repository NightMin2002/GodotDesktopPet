# menu_tooltip.gd — 浮动 Tooltip 子系统 (RefCounted)
# 负责: 子菜单项的描述性浮动提示构建、显示、定位
# 从 context_menu.gd 拆分
extends RefCounted

var _menu  # context_menu 引用
var panel: PanelContainer
var _label: Label
var _tween: Tween
var _active_btn: Button

func _init(menu_ref) -> void:
	_menu = menu_ref

# ── 构建 ──

func build() -> void:
	panel = PanelContainer.new()
	panel.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.16, 0.92)
	style.border_color = Color(0.1, 0.8, 1.0, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95, 0.95))
	panel.add_child(_label)
	_menu.add_child(panel)

# ── 更新位置 ──

func update_position() -> void:
	if not is_instance_valid(_active_btn):
		return
	var btn_pos = _active_btn.global_position
	var btn_size = _active_btn.size
	var vp_size = _menu.get_viewport().get_visible_rect().size
	var tip_w = panel.size.x
	var tip_h = panel.size.y
	var y_pos = btn_pos.y + btn_size.y / 2.0 - tip_h / 2.0
	var gap := 16.0
	if _menu._menu_side == 1:
		# 菜单在宠物右侧 → tooltip 优先右侧
		var right_x = btn_pos.x + btn_size.x + gap
		if right_x + tip_w > vp_size.x - 10:
			panel.position = Vector2(btn_pos.x - tip_w - gap, y_pos)
			panel.pivot_offset = Vector2(tip_w, tip_h / 2.0)
		else:
			panel.position = Vector2(right_x, y_pos)
			panel.pivot_offset = Vector2(0, tip_h / 2.0)
	else:
		# 菜单在宠物左侧 → tooltip 优先左侧
		var left_x = btn_pos.x - tip_w - gap
		if left_x < 10:
			panel.position = Vector2(btn_pos.x + btn_size.x + gap, y_pos)
			panel.pivot_offset = Vector2(0, tip_h / 2.0)
		else:
			panel.position = Vector2(left_x, y_pos)
			panel.pivot_offset = Vector2(tip_w, tip_h / 2.0)

# ── 显示/隐藏 ──

func show_for(btn: Button, text: String, show: bool) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	if show:
		_active_btn = btn
		_label.text = text
		panel.reset_size()  # 强制重算尺寸适配当前文字
		panel.modulate.a = 0.0
		panel.scale = Vector2(0.7, 0.7)
		panel.show()
		await _menu.get_tree().process_frame
		update_position()
		_tween = _menu.create_tween().set_parallel(true)
		_tween.tween_property(panel, "modulate:a", 1.0, 0.15)
		_tween.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween = _menu.create_tween().set_parallel(true)
		_tween.tween_property(panel, "modulate:a", 0.0, 0.1)
		_tween.tween_property(panel, "scale", Vector2(0.7, 0.7), 0.1)
		_tween.finished.connect(func(): panel.hide())

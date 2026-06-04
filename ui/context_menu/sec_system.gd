# sec_system.gd — 系统分区 (构建 + 回调)
extends RefCounted

var ctx  # ContextMenu 引用

# ── 按钮引用 ──

func _init(context_menu) -> void:
	ctx = context_menu

func build() -> void:
	var panel = ctx.make_submenu_panel()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var placeholder = Label.new()
	placeholder.text = "SYS_PARTITION_EMPTY\n[ 扩展系统功能预留区域 ]\n\n>> 敬请期待机体后续更新 <<"
	placeholder.add_theme_font_size_override("font_size", 14)
	placeholder.add_theme_color_override("font_color", Color(0.8, 0.55, 0.55, 0.5))
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.add_child(placeholder)
	
	vbox.add_child(margin)

	ctx.register_l2_panel("sec_system", panel)

# ── 退出 ──

func on_quit_pressed() -> void:
	ctx.cleanup_toys()
	ctx._tooltip.panel.hide()
	if is_instance_valid(ctx.target):
		ctx.hud.pivot_offset = ctx.target.get_global_transform_with_canvas().get_origin() - ctx.hud.position

	var tween = ctx.create_tween().set_parallel(true)
	tween.tween_property(ctx.hud, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(ctx.hud, "modulate:a", 0.0, 0.15)
	if ctx._menu_side == 1:
		ctx._sidebar.panel.pivot_offset = Vector2(ctx._sidebar.panel.size.x, ctx._sidebar.panel.size.y * 0.5)
	else:
		ctx._sidebar.panel.pivot_offset = Vector2(0, ctx._sidebar.panel.size.y * 0.5)
	tween.tween_property(ctx._sidebar.panel, "scale", Vector2(0.3, 0.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(ctx._sidebar.panel, "modulate:a", 0.0, 0.15)

	tween.finished.connect(func():
		ctx.hud.hide()
		ctx._sidebar.panel.hide()
		EventBus.context_menu_toggled.emit(false)
	)
	ctx.target = null

	var main_node = ctx.get_tree().root.get_node_or_null("Main")
	if main_node and main_node.has_method("quit_with_farewell"):
		main_node.quit_with_farewell()
	else:
		ctx.get_tree().quit()

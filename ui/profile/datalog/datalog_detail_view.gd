# datalog_detail_view.gd — 数据日志详情面板（选中/编辑/保存/标签/删除)
# 非独立节点, 由主控 datalog_tab.gd 持有 UI 引用, 通过回调协作
extends RefCounted

## 选中日志条目, 回调刷新列表和详情
static func select_log(ctx: Dictionary, idx: int) -> void:
	ctx.selected_idx = idx
	reset_delete_state(ctx)
	ctx.render_list.call()
	update_detail_panel(ctx)

## 更新详情面板显示
static func update_detail_panel(ctx: Dictionary) -> void:
	var idx = ctx.selected_idx
	var filtered = ctx.filtered
	var ui = ctx.ui

	if idx < 0 or idx >= filtered.size():
		ui.detail_panel.visible = false
		ui.detail_empty.visible = true
		return

	ui.detail_panel.visible = true
	ui.detail_empty.visible = false
	reset_delete_state(ctx)

	var entry = filtered[idx]
	var is_pet = (entry.get("source", "user") == "pet")

	if is_pet:
		ui.detail_header.text = "ENTRY // 机体记录"
	else:
		ui.detail_header.text = "ENTRY // 操作员备忘"

	ui.title_edit.text = entry.get("title", "")
	ui.title_edit.editable = true

	# 检测条目类型
	var tags = entry.get("tags", [])
	var is_window_report = ("sys:window" in tags and entry.has("window_data"))
	var is_input_report = ("sys:input" in tags and is_pet)

	# 三种显示模式: 窗口卡片 / 机体记录 BBCode / 普通 TextEdit
	if ui.has("content_wrapper"): ui.content_wrapper.visible = false
	if ui.has("pet_content_wrapper"): ui.pet_content_wrapper.visible = false
	if ui.has("window_cards_wrapper"): ui.window_cards_wrapper.visible = false
	if ui.has("heatmap_btn"): ui.heatmap_btn.visible = false

	if is_window_report:
		if ui.has("window_cards_wrapper"):
			ui.window_cards_wrapper.visible = true
			if ui.has("window_cards_inner") and ctx.has("render_window_cards"):
				ctx.render_window_cards.call(ui.window_cards_inner, entry.get("window_data", {}), entry.get("window_delta", {}))
	elif is_input_report:
		# 输入报告: 用 RichTextLabel 显示带增量绿字的内容
		if ui.has("pet_content_wrapper") and ui.has("pet_content_rtl"):
			ui.pet_content_wrapper.visible = true
			var bbcode = _format_input_bbcode(entry)
			ui.pet_content_rtl.text = ""
			ui.pet_content_rtl.parse_bbcode(bbcode)
		# 键鼠全图按钮
		if ui.has("heatmap_btn"):
			ui.heatmap_btn.visible = true
	else:
		# 普通模式: TextEdit
		if ui.has("content_wrapper"): ui.content_wrapper.visible = true
		ui.content_edit.text = entry.get("content", "")
		ui.content_edit.editable = not is_pet
		if ui.has("heatmap_btn"):
			ui.heatmap_btn.visible = false

	ui.del_btn.visible = true
	ui.tag_input.visible = true

	var created = entry.get("created", "")
	ui.save_badge.text = "创建于 %s" % created if created != "" else ""

	_refresh_tags_display(ctx, entry.get("tags", []))

## 生成输入报告的 BBCode (内联绿字增量)
static func _format_input_bbcode(entry: Dictionary) -> String:
	var data: Dictionary = entry.get("input_data", {})
	var delta: Dictionary = entry.get("input_delta", {})
	var has_delta = not delta.is_empty()
	var green = "4cf06a"  # 增量绿色

	var lines: PackedStringArray = []
	lines.append("=== 输入行为统计报告 ===")
	var sess = int(data.get("session_sec", 0))
	lines.append("会话时长: %d 秒" % sess)
	var total_keys = int(data.get("total_keystrokes", 0))
	var dk = int(delta.get("keystrokes", 0))
	if has_delta and dk > 0:
		lines.append("总击键: %d 次[color=#%s]+%d次[/color]" % [total_keys, green, dk])
	else:
		lines.append("总击键: %d 次" % total_keys)
	lines.append("")

	# 按键 (全部)
	var keys: Dictionary = data.get("keys", {})
	var keys_delta: Dictionary = delta.get("keys", {})
	if keys.size() > 0:
		lines.append("-- 按键统计 (全量) --")
		var sorted_keys = []
		for k in keys:
			sorted_keys.append([k, keys[k]])
		sorted_keys.sort_custom(func(a, b): return a[1] > b[1])
		for i in range(sorted_keys.size()):
			var k_name = sorted_keys[i][0]
			var k_val = sorted_keys[i][1]
			var dk_i = int(keys_delta.get(k_name, 0))
			if has_delta and dk_i > 0:
				lines.append("  %s: %d 次[color=#%s]+%d次[/color]" % [k_name, k_val, green, dk_i])
			else:
				lines.append("  %s: %d 次" % [k_name, k_val])
		lines.append("")

	# 组合键
	var combos: Dictionary = data.get("combos", {})
	var combos_delta: Dictionary = delta.get("combos", {})
	if combos.size() > 0:
		lines.append("-- 组合键统计 --")
		var sorted_combos = []
		for k in combos:
			sorted_combos.append([k, combos[k]])
		sorted_combos.sort_custom(func(a, b): return a[1] > b[1])
		for item in sorted_combos:
			var c_name = item[0]
			var c_val = item[1]
			var dc = int(combos_delta.get(c_name, 0))
			if has_delta and dc > 0:
				lines.append("  %s: %d 次[color=#%s]+%d次[/color]" % [c_name, c_val, green, dc])
			else:
				lines.append("  %s: %d 次" % [c_name, c_val])
		lines.append("")

	# 鼠标 (逐项标注增量)
	var mouse: Dictionary = data.get("mouse", {})
	if mouse.size() > 0:
		lines.append("-- 鼠标统计 --")
		var lc = int(mouse.get("left_clicks", 0))
		var d_lc = int(delta.get("left_clicks", 0))
		if has_delta and d_lc > 0:
			lines.append("  左键: %d 次[color=#%s]+%d次[/color]" % [lc, green, d_lc])
		else:
			lines.append("  左键: %d 次" % lc)
		var rc = int(mouse.get("right_clicks", 0))
		var d_rc = int(delta.get("right_clicks", 0))
		if has_delta and d_rc > 0:
			lines.append("  右键: %d 次[color=#%s]+%d次[/color]" % [rc, green, d_rc])
		else:
			lines.append("  右键: %d 次" % rc)
		lines.append("  中键: %d 次" % int(mouse.get("middle_clicks", 0)))
		var dist_px = int(mouse.get("distance_px", 0))
		if dist_px > 0:
			lines.append("  移动: %.1f m (估算)" % (float(dist_px) / 3780.0))

	return "\n".join(lines)

## 刷新标签徽章列表
static func _refresh_tags_display(ctx: Dictionary, tags: Array) -> void:
	var tags_flow = ctx.ui.tags_flow
	for child in tags_flow.get_children():
		child.queue_free()
	for tag in tags:
		tags_flow.add_child(ctx.make_tag_badge.call(str(tag), true))

## 新建用户日志
static func on_new_pressed(ctx: Dictionary) -> void:
	var now = Time.get_datetime_string_from_system(false, true)
	var id = "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	var td = Time.get_datetime_dict_from_system()
	var default_title = "备忘 %02d-%02d %02d:%02d" % [td.month, td.day, td.hour, td.minute]
	var entry = {
		"id": id,
		"title": default_title,
		"content": "",
		"tags": [],
		"source": "user",
		"created": now,
		"updated": now,
	}
	ctx.logs.insert(0, entry)
	SettingsManager.save_datalogs(ctx.logs)

	ctx.selected_idx = 0
	ctx.animate_new_card = true
	ctx.apply_filter.call()
	update_detail_panel(ctx)

	if ctx.ui.title_edit:
		ctx.ui.title_edit.grab_focus()
		ctx.ui.title_edit.select_all()

## 删除日志 (两段确认)
static func on_delete_pressed(ctx: Dictionary) -> void:
	var idx = ctx.selected_idx
	var filtered = ctx.filtered
	if idx < 0 or idx >= filtered.size():
		return

	if not ctx.del_pending:
		ctx.del_pending = true
		var del_btn = ctx.ui.del_btn
		del_btn.text = "确认删除?"
		del_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5, 1.0))
		var crit_s = StyleBoxFlat.new()
		crit_s.bg_color = Color(0.5, 0.12, 0.12, 0.8)
		crit_s.set_corner_radius_all(2)
		crit_s.set_border_width_all(1)
		crit_s.border_color = Color(0.9, 0.3, 0.3, 0.8)
		crit_s.content_margin_left = 10; crit_s.content_margin_right = 10
		crit_s.content_margin_top = 3; crit_s.content_margin_bottom = 3
		del_btn.add_theme_stylebox_override("normal", crit_s)
		del_btn.add_theme_stylebox_override("hover", crit_s)
		# 3秒自动取消
		if ctx.del_reset_tween and ctx.del_reset_tween.is_valid():
			ctx.del_reset_tween.kill()
		ctx.del_reset_tween = ctx.owner.create_tween()
		ctx.del_reset_tween.tween_interval(3.0)
		ctx.del_reset_tween.tween_callback(func(): reset_delete_state(ctx))
		return

	# 第二次点击: 真正删除
	var entry = filtered[idx]
	var target_id = entry.get("id", "")
	var logs = ctx.logs
	for i in range(logs.size() - 1, -1, -1):
		if logs[i].get("id", "") == target_id:
			logs.remove_at(i)
			break
	SettingsManager.save_datalogs(logs)
	ctx.selected_idx = -1
	ctx.del_pending = false
	ctx.apply_filter.call()
	update_detail_panel(ctx)

## 重置删除按钮状态
static func reset_delete_state(ctx: Dictionary) -> void:
	ctx.del_pending = false
	var del_btn = ctx.ui.del_btn
	if not is_instance_valid(del_btn):
		return
	del_btn.text = "删除记录"
	del_btn.add_theme_color_override("font_color", Color(0.65, 0.4, 0.4, 0.6))
	var ds = StyleBoxFlat.new()
	ds.bg_color = Color(0.10, 0.04, 0.04, 0.4)
	ds.set_corner_radius_all(2)
	ds.set_border_width_all(1)
	ds.border_color = Color(0.4, 0.18, 0.18, 0.25)
	ds.content_margin_left = 10; ds.content_margin_right = 10
	ds.content_margin_top = 3; ds.content_margin_bottom = 3
	del_btn.add_theme_stylebox_override("normal", ds)
	var dh = ds.duplicate()
	dh.bg_color = Color(0.25, 0.08, 0.08, 0.7)
	dh.border_color = Color(0.8, 0.3, 0.3, 0.5)
	del_btn.add_theme_stylebox_override("hover", dh)
	del_btn.add_theme_stylebox_override("pressed", dh)

## 内容变更 → 触发保存防抖
static func on_content_changed(ctx: Dictionary) -> void:
	ctx.ui.save_timer.start()

## 防抖保存
static func do_save(ctx: Dictionary) -> void:
	var idx = ctx.selected_idx
	var filtered = ctx.filtered
	if idx < 0 or idx >= filtered.size():
		return
	var entry = filtered[idx]
	var target_id = entry.get("id", "")

	entry["title"] = ctx.ui.title_edit.text
	entry["content"] = ctx.ui.content_edit.text
	entry["updated"] = Time.get_datetime_string_from_system(false, true)

	var logs = ctx.logs
	for i in range(logs.size()):
		if logs[i].get("id", "") == target_id:
			logs[i] = entry
			break
	SettingsManager.save_datalogs(logs)
	ctx.render_list.call()

	var save_badge = ctx.ui.save_badge
	if save_badge:
		save_badge.text = "已保存"
		save_badge.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.9))
		var tw = ctx.owner.create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(func():
			if is_instance_valid(save_badge):
				var created = entry.get("created", "")
				save_badge.text = "创建于 %s" % created if created != "" else ""
				save_badge.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.7, 0.6))
		)

## 添加标签
static func on_tag_submitted(ctx: Dictionary, text: String) -> void:
	var tag = text.strip_edges()
	var idx = ctx.selected_idx
	if tag == "" or idx < 0 or idx >= ctx.filtered.size():
		return
	var entry = ctx.filtered[idx]
	var tags = entry.get("tags", [])
	if tag in tags:
		ctx.ui.tag_input.text = ""
		return
	tags.append(tag)
	entry["tags"] = tags
	entry["updated"] = Time.get_datetime_string_from_system(false, true)
	_save_log_to_main(ctx, entry)
	ctx.ui.tag_input.text = ""
	_refresh_tags_display(ctx, tags)
	ctx.render_list.call()

## 删除标签
static func remove_tag(ctx: Dictionary, tag: String) -> void:
	var idx = ctx.selected_idx
	if idx < 0 or idx >= ctx.filtered.size():
		return
	var entry = ctx.filtered[idx]
	var tags = entry.get("tags", [])
	tags.erase(tag)
	entry["tags"] = tags
	entry["updated"] = Time.get_datetime_string_from_system(false, true)
	_save_log_to_main(ctx, entry)
	_refresh_tags_display(ctx, tags)
	ctx.render_list.call()

## 回写单条日志到主列表
static func _save_log_to_main(ctx: Dictionary, entry: Dictionary) -> void:
	var target_id = entry.get("id", "")
	var logs = ctx.logs
	for i in range(logs.size()):
		if logs[i].get("id", "") == target_id:
			logs[i] = entry
			break
	SettingsManager.save_datalogs(logs)

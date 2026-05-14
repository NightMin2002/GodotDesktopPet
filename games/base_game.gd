# base_game.gd — 小游戏接口基类
# 所有游戏包中的游戏脚本必须继承此类，实现标准接口
# 生命周期: GameManager 注入属性 → start() → [游戏进行中] → game_finished 信号 → cleanup()
class_name BaseGame extends RefCounted

enum Result { WIN, LOSE, DRAW }

## 游戏结束信号 (GameManager 监听)
signal game_finished(result: Result)

# ── 重开按钮布局预留常量 (防止显隐跳动) ──
const _RESTART_RESERVE := Vector2(100, 32)  # 和 custom_minimum_size 保持一致
const _RESTART_GAP := 8.0

# ── GameManager 注入的运行时引用 (start 前自动设置) ──
var game_viewport: SubViewport            # 游戏 UI 渲染到的 SubViewport
var game_container: SubViewportContainer   # 屏幕上的容器 (定位/拖拽用)
var screen_size: Vector2                   # 屏幕实际大小
var _pet: Node2D = null                    # 宠物原体引用

# ── 战绩 (通用, 子类可直接使用) ──
var _wins: int = 0
var _losses: int = 0
var _game_over: bool = false
var _takeover: bool = false  # 用户接管自玩局 → 战绩作废不计
var _panel_hidden: bool = false  # 面板隐藏状态 (游戏仍在后台运行, 全息屏不受影响)

# ── 自动操作 (AI 自玩, 通用基础设施) ──
var _auto_play: bool = false
var _auto_timer: Timer = null
const AUTO_PLAY_ALPHA := 0.6  # 自玩时面板透明度

# ── 教程面板 ──
var _tutorial_panel: PanelContainer = null
var _tutorial_visible: bool = false

# ── 悬浮组件 (委托给 GameChrome) ──
var _chrome: GameChrome = null
var _compare_label: Label = null  # 双方成绩对比行
var _pending_speech: String = ""  # _say() 在 chrome 创建前调用时暂存

# ── 元数据 (子类覆写) ──

func get_game_id() -> String:
	return ""

func get_game_name() -> String:
	return ""

func get_game_desc() -> String:
	return ""

# ── 生命周期 (子类覆写) ──

## 启动游戏: 构建 UI (add_child 到 game_viewport)、初始化逻辑
func start() -> void:
	pass

## 清理资源: 移除所有 UI 节点、断开信号
func cleanup() -> void:
	if _chrome:
		_chrome.cleanup()
		_chrome = null
	_destroy_tutorial()

# ── 教程系统 (子类按需覆写) ──

## 覆写: 返回简报步骤。空数组 = 不显示简报按钮
## 格式: [{text: String}]
func get_tutorial_steps() -> Array[Dictionary]:
	return []

## 覆写: 返回预览动画 Control 节点 (可选, 显示在教程面板顶部)
func get_tutorial_preview() -> Control:
	return null

# ── 通用话术工具 ──

## 洗牌防重复话术抽取 (子类共用, 不需要各自定义)
func _pick(queue: Array, pool: Array) -> String:
	if queue.is_empty():
		queue.append_array(pool)
		queue.shuffle()
	return queue.pop_back()

# ── 通用 UI 工厂 ──

## 创建游戏面板标准背景 (深色半透明 + 主题色边框 + 圆角)
## 子类可在返回后自行调整 content_margin
func _create_game_panel_bg() -> StyleBoxFlat:
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.12, 0.95)
	bg.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.9, 0.4)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 0
	bg.content_margin_right = 0
	bg.content_margin_top = 0
	bg.content_margin_bottom = 6
	return bg

## 创建面板骨架 (PanelContainer + MarginContainer + VBoxContainer)
## 返回 {panel: PanelContainer, vbox: VBoxContainer}
func _create_panel_skeleton(min_width: float, margins: Dictionary = {}) -> Dictionary:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0)
	panel.add_theme_stylebox_override("panel", _create_game_panel_bg())

	var outer = MarginContainer.new()
	outer.add_theme_constant_override("margin_left", margins.get("left", 14))
	outer.add_theme_constant_override("margin_right", margins.get("right", 14))
	outer.add_theme_constant_override("margin_top", margins.get("top", 12))
	outer.add_theme_constant_override("margin_bottom", margins.get("bottom", 6))
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(outer)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", margins.get("separation", 8))
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(vbox)

	return {panel = panel, vbox = vbox}

## 创建双方成绩对比行 (统一样式, 自动挂载到 _compare_label)
func _create_compare_row(parent: Control, text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.6))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	_compare_label = label
	return label

## 创建战绩 RichTextLabel (统一样式: BBCode + 自适应 + 无滚动)
func _create_score_rich_label() -> RichTextLabel:
	var rich = RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.custom_minimum_size = Vector2(0, 20)
	rich.add_theme_font_size_override("normal_font_size", 12)
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rich

# ── 战绩持久化 ──

## 战绩存储 key (自玩/手动分开)
func _score_key(suffix: String) -> String:
	var id = get_game_id()
	if _auto_play:
		return "game_" + id + "_auto_" + suffix
	return "game_" + id + "_" + suffix

## 读取对方数据的 key (自玩时读用户, 手动时读宠物)
func _other_score_key(suffix: String) -> String:
	var id = get_game_id()
	if _auto_play:
		return "game_" + id + "_" + suffix
	return "game_" + id + "_auto_" + suffix

## 从 SettingsManager 加载战绩 (子类 start() 中调用)
func _load_scores() -> void:
	if get_game_id() == "":
		return
	_wins = SettingsManager.get_int(_score_key("wins"), 0)
	_losses = SettingsManager.get_int(_score_key("losses"), 0)

## 保存战绩到 SettingsManager (结束/关闭时调用)
func _save_scores() -> void:
	if get_game_id() == "" or _takeover:
		return
	SettingsManager.set_int(_score_key("wins"), _wins)
	SettingsManager.set_int(_score_key("losses"), _losses)

# ── 游戏熟练度 (委托 SettingsManager) ──

## 增加游戏经验值
func _add_gaming_xp(amount: int) -> void:
	var old_level = SettingsManager.get_gaming_level()
	SettingsManager.add_gaming_xp(amount)
	var new_level = SettingsManager.get_gaming_level()
	if new_level > old_level:
		if is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
			var lines = [
				"...系统升级。游戏熟练度 Lv.%d。" % new_level,
				"技能精进。Lv.%d。" % new_level,
				"经验积累到位。Lv.%d。" % new_level,
			]
			_pet.show_local_bubble(lines[randi() % lines.size()])
	_show_xp_popup(amount)

## XP 飘字动画 (面板底部, 带背景, 向上浮起淡出)
func _show_xp_popup(amount: int) -> void:
	if _panel_hidden:
		return
	if not is_instance_valid(game_container):
		return
	var parent = game_container.get_parent()
	if not is_instance_valid(parent):
		return

	var hue = EventBus.ui_hue

	# 带背景的小标签
	var tag = PanelContainer.new()
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.12, 0.85)
	bg.border_color = Color.from_hsv(fmod(hue + 0.1, 1.0), 0.5, 0.8, 0.4)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 4
	bg.content_margin_bottom = 4
	tag.add_theme_stylebox_override("panel", bg)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.z_index = 50

	var label = Label.new()
	label.text = "+%d XP" % amount
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color.from_hsv(fmod(hue + 0.1, 1.0), 0.5, 1.0, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(label)

	parent.add_child(tag)

	# 定位: 面板底部居中
	var panel_pos = game_container.global_position
	var panel_size = game_container.size
	tag.position = Vector2(panel_pos.x + panel_size.x * 0.5 - 30, panel_pos.y + panel_size.y - 10)

	# 动画: 上浮 35px + 淡出
	var tween = parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(tag, "position:y", tag.position.y - 35.0, 1.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(tag, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(tag.queue_free)

## 获取 AI 失误率
func _get_mistake_rate() -> float:
	return SettingsManager.get_gaming_mistake_rate()

# ── 自玩通用基础设施 ──

## 淡入/淡出面板 + 所有悬浮组件
func _auto_fade(target_alpha: float, dur: float = 0.25) -> void:
	if not is_instance_valid(game_container):
		return
	var tw = game_container.create_tween().set_parallel(true)
	tw.tween_property(game_container, "modulate:a", target_alpha, dur)
	for node in [_chrome.title_bubble, _chrome.side_container, _chrome.connector, _chrome.speech_bubble, _chrome.restart_bubble] if _chrome else []:
		if is_instance_valid(node):
			tw.tween_property(node, "modulate:a", target_alpha, dur)

## 创建自玩定时器 (连接到 _auto_play_step)
func _auto_create_timer(interval: float = 0.4) -> void:
	if is_instance_valid(_auto_timer):
		_auto_timer.queue_free()
	_auto_timer = Timer.new()
	_auto_timer.wait_time = interval
	_auto_timer.timeout.connect(_auto_play_step)
	game_viewport.add_child(_auto_timer)
	_auto_timer.start()

## 销毁自玩定时器
func _auto_destroy_timer() -> void:
	if is_instance_valid(_auto_timer):
		_auto_timer.stop()
		_auto_timer.queue_free()
		_auto_timer = null

## 自玩步骤 (子类覆写, 实现 AI 逻辑)
func _auto_play_step() -> void:
	pass

## 启动自玩 — 模板方法, 子类通过覆写 hook 提供话术和参数
## 子类只需覆写: get_auto_start_lines(), get_auto_play_interval()
## 如有特殊启动逻辑(如贪吃蛇需要启动 tick_timer), 覆写 _on_auto_play_started()
func _start_auto_play() -> void:
	_auto_play = true
	var lines = get_auto_start_lines()
	if lines.size() > 0 and is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
		_pet.show_local_bubble(lines[randi() % lines.size()])
	if is_instance_valid(game_viewport):
		await game_viewport.get_tree().create_timer(0.6).timeout
	if not _auto_play or not is_instance_valid(game_container):
		return
	_on_auto_play_started()
	_auto_create_timer(get_auto_play_interval())

## 子类覆写: 自玩启动话术
func get_auto_start_lines() -> Array:
	return ["自主训练开始。", "...自检模式。"]

## 子类覆写: 自玩定时器间隔 (秒)
func get_auto_play_interval() -> float:
	return 0.4

## 子类覆写: 自玩启动后的额外初始化 (如启动游戏计时器)
func _on_auto_play_started() -> void:
	pass

## 停止自玩 (用户接管) — 通用逻辑, 子类一般不需要覆写
func _stop_auto_play() -> void:
	var was_auto = _auto_play
	_auto_play = false
	_auto_destroy_timer()
	if was_auto:
		_takeover = true  # 用户接管 → 本局战绩作废
		# 恢复发言气泡
		if is_instance_valid(_chrome.speech_bubble) if _chrome else false:
			_chrome.speech_bubble.visible = true
		# 恢复面板透明度 + 显示接管台词
		if not _game_over:
			# 恢复面板显示
			set_panel_visible(true)
			var lines = _get_takeover_lines()
			if lines.size() > 0 and is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
				_pet.show_local_bubble(lines[randi() % lines.size()])

## 接管台词 (子类覆写提供专属台词)
func _get_takeover_lines() -> Array:
	return ["...你来？好。", "操作权移交。"]

## 自玩结束 + 等待后自动关闭游戏 (子类在 game_over 时调用)
func _auto_finish_and_close() -> void:
	_auto_play = false
	_auto_destroy_timer()
	if is_instance_valid(game_viewport):
		await game_viewport.get_tree().create_timer(3.0).timeout
		if is_instance_valid(game_viewport):
			_close_game()

# ── 辅助方法 ──

## 宠物发言 (通过悬浮气泡 + 淡入高亮动画)
func _say(text: String) -> void:
	if _chrome:
		_chrome.say(text)
	elif not _auto_play:
		_pending_speech = text

## 同步 SubViewport 大小到面板内容 (面板 resized 时调用)
func sync_viewport_size() -> void:
	if not game_viewport or not game_container:
		return
	if game_viewport.get_child_count() > 0:
		var panel = game_viewport.get_child(0)
		if panel is Control:
			var s = panel.size
			game_viewport.size = Vector2i(s)
			game_container.custom_minimum_size = s
			game_container.size = s

## 子类覆写: 默认面板尺寸 (用于定位时面板 size 尚未确定的 fallback)
func get_default_panel_size() -> Vector2:
	return Vector2(280, 400)

## 子类覆写: 中途关闭时的吐槽话术 (空字符串 = 不显示)
func get_close_speech() -> String:
	return ""

## 子类覆写: 中途关闭话术池 (用于 _pick 抽取, 优先级高于 get_close_speech)
func get_close_speech_pool() -> Array:
	return []

## 子类覆写: 自玩被关闭时的话术
func get_auto_close_lines() -> Array:
	return ["...？", "...中断。"]

# ── 通用面板管理 ──

## 将面板挂载到 SubViewport，等布局完成后同步大小并定位
## 子类在 _build_ui() 构建面板后调用此方法完成后续流程
func _mount_panel(panel: PanelContainer) -> void:
	panel.gui_input.connect(_on_panel_input)
	panel.resized.connect(sync_viewport_size)

	game_viewport.add_child(panel)
	await game_viewport.get_tree().process_frame
	sync_viewport_size()
	_position_near_pet()

	if _auto_play:
		# 自玩模式: 面板从一开始就隐藏 (modulate.a=0 保持 SubViewport 渲染)
		game_container.modulate.a = 0.0
		_panel_hidden = true
	else:
		# 弹入动画
		game_container.modulate.a = 0.0
		game_container.scale = Vector2(0.6, 0.6)
		game_container.pivot_offset = game_container.size / 2.0
		var tween = game_container.create_tween().set_parallel(true)
		tween.tween_property(game_container, "modulate:a", 1.0, 0.2)
		tween.tween_property(game_container, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

	# 悬浮组件 (委托给 GameChrome)
	_chrome = GameChrome.new()
	_chrome.game = self
	_chrome.pending_speech = _pending_speech
	_pending_speech = ""
	_chrome.setup(get_game_name(), _close_game, _on_restart)

## 面板定位: 宠物侧面, 避让全息迷你屏, 底部预留重开按钮空间
func _position_near_pet() -> void:
	var vp = screen_size
	var pet_pos := Vector2(vp.x / 2.0, vp.y / 2.0)
	if is_instance_valid(_pet):
		pet_pos = _pet.get_global_transform_with_canvas().get_origin()
	var default_size = get_default_panel_size()
	var pw: float = game_container.size.x if game_container.size.x > 10 else default_size.x
	var ph: float = game_container.size.y if game_container.size.y > 10 else default_size.y
	# 获取全息屏区域 (避让用)
	var holo_rect := Rect2()
	if is_instance_valid(_pet) and _pet.gaming and _pet.gaming.active:
		holo_rect = _pet.gaming.get_holo_screen_rect()
	var pet_r := 30.0
	var base_gap := pet_r + pet_r * 1.2 + pet_r * 1.5
	var x: float
	if pet_pos.x > vp.x * 0.5:
		x = pet_pos.x - pw - base_gap
		if holo_rect.size.x > 0:
			var panel_right = x + pw
			if panel_right > holo_rect.position.x:
				x = holo_rect.position.x - pw - 8.0
	else:
		x = pet_pos.x + base_gap
		if holo_rect.size.x > 0:
			var holo_right = holo_rect.position.x + holo_rect.size.x
			if x < holo_right:
				x = holo_right + 8.0
	var y = pet_pos.y - ph * 0.35
	var bottom_reserve := _RESTART_GAP + _RESTART_RESERVE.y + _RESTART_GAP
	x = clampf(x, 8.0, vp.x - pw - 8.0)
	y = clampf(y, 8.0, vp.y - ph - bottom_reserve)
	# 强制推离: clamp 后面板仍可能与宠物+全息屏横向重叠
	var pet_zone_left = pet_pos.x - pet_r
	var pet_zone_right = pet_pos.x + pet_r
	if holo_rect.size.x > 0:
		pet_zone_left = minf(pet_zone_left, holo_rect.position.x)
		pet_zone_right = maxf(pet_zone_right, holo_rect.position.x + holo_rect.size.x)
	var panel_left = x
	var panel_right = x + pw
	# 检测横向重叠 (面板和宠物区域有交集)
	if panel_right > pet_zone_left and panel_left < pet_zone_right:
		# 推到空间更大的一侧
		var space_left = pet_zone_left - 8.0
		var space_right = vp.x - pet_zone_right - 8.0
		if space_left >= pw:
			x = pet_zone_left - pw - 8.0
		elif space_right >= pw:
			x = pet_zone_right + 8.0
		else:
			# 两侧都放不下，选更大的那边挤进去
			if space_left > space_right:
				x = 8.0
			else:
				x = vp.x - pw - 8.0
	game_container.position = Vector2(x, y)

## 限制面板不超出屏幕
func _clamp_panel_to_screen() -> void:
	if not is_instance_valid(game_container):
		return
	var vp = screen_size
	var pos = game_container.position
	pos.x = clampf(pos.x, 8.0, vp.x - game_container.size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - game_container.size.y - 8.0)
	game_container.position = pos
	_update_chrome_positions()

## 面板拖拽处理 (顶部区域可拖拽)
func _on_panel_input(event: InputEvent) -> void:
	if not is_instance_valid(game_container):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var panel = game_viewport.get_child(0) as Control if game_viewport and game_viewport.get_child_count() > 0 else null
		if not panel:
			return
		var local = panel.get_local_mouse_position()
		if event.pressed and local.y < 50.0:
			if _chrome: _chrome._dragging = true
			if _chrome: _chrome._drag_offset = game_container.get_viewport().get_mouse_position() - game_container.position
			EventBus.drag_started.emit()
		else:
			if _chrome and _chrome._dragging:
				EventBus.drag_ended.emit()
			if _chrome: _chrome._dragging = false
	elif event is InputEventMouseMotion and _chrome and _chrome._dragging:
		var vp = screen_size
		var new_pos = game_container.get_viewport().get_mouse_position() - _chrome._drag_offset
		new_pos.x = clampf(new_pos.x, 8.0, vp.x - game_container.size.x - 8.0)
		new_pos.y = clampf(new_pos.y, 8.0, vp.y - game_container.size.y - 8.0)
		game_container.position = new_pos
		_update_chrome_positions()

## 子类覆写: 重开逻辑 (由悬浮重开按钮触发)
func _on_restart() -> void:
	pass

## 中途关闭处理 — 模板方法 (子类通过 hook 提供话术和特殊清理)
## 子类需要额外清理时覆写 _on_close_extra_cleanup()
func _on_close_cleanup() -> bool:
	var was_auto = _auto_play
	if not _game_over:
		_game_over = true
		_on_close_extra_cleanup()
		if not _takeover:
			_losses += 1
			_save_scores()
		game_finished.emit(Result.LOSE)
		if is_instance_valid(_pet) and _pet.has_method("show_local_bubble"):
			if was_auto:
				var lines = get_auto_close_lines()
				_pet.show_local_bubble(lines[randi() % lines.size()])
			else:
				var pool = get_close_speech_pool()
				if pool.size() > 0:
					_pet.show_local_bubble(pool[randi() % pool.size()])
				else:
					var speech = get_close_speech()
					if speech != "":
						_pet.show_local_bubble(speech)
	return true

## 子类覆写: 中途关闭时的额外清理 (如停计时器、保存特殊数据)
func _on_close_extra_cleanup() -> void:
	pass

## 通用关闭流程: 中途退出处理 + 退场动画 + 发射关闭信号
func _close_game() -> void:
	# 子类额外清理
	_on_close_cleanup()
	# 退场动画
	if _chrome: _chrome.animate_out()
	if is_instance_valid(game_container):
		game_container.pivot_offset = game_container.size / 2.0
		var tween = game_container.create_tween().set_parallel(true)
		tween.tween_property(game_container, "modulate:a", 0.0, 0.15)
		tween.tween_property(game_container, "scale", Vector2(0.5, 0.5), 0.15)
		tween.finished.connect(func():
			EventBus.close_game_requested.emit()
		)

# ══════════════════════════════════════════════
# 悬浮组件委托 (实现在 game_chrome.gd)
# ══════════════════════════════════════════════

func _show_restart_bubble() -> void:
	if _chrome: _chrome.show_restart()

func _hide_restart_bubble() -> void:
	if _chrome: _chrome.hide_restart()

func _update_chrome_positions() -> void:
	if _chrome: _chrome.update_positions()

func get_chrome_rects() -> Array[Rect2]:
	if _chrome: return _chrome.get_rects()
	return []

func get_holo_texture() -> Texture2D:
	if _chrome: return _chrome.get_holo_texture()
	if game_viewport: return game_viewport.get_texture()
	return null

## 显示/隐藏游戏面板 (隐藏时游戏继续运行, 全息屏不受影响)
func set_panel_visible(show: bool) -> void:
	if show == (not _panel_hidden):
		return  # 状态未变
	_panel_hidden = not show
	if show:
		# 重新定位面板 (避开宠物和全息屏)
		_position_near_pet()
		_update_chrome_positions()
		# 显示面板 + 弹入动画
		if is_instance_valid(game_container):
			game_container.modulate.a = 0.0
			game_container.scale = Vector2(0.85, 0.85)
			game_container.pivot_offset = game_container.size / 2.0
			var tw = game_container.create_tween().set_parallel(true)
			tw.tween_property(game_container, "modulate:a", 1.0, 0.2)
			tw.tween_property(game_container, "scale", Vector2.ONE, 0.25) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var show_nodes: Array = []
		if _chrome:
			show_nodes = [_chrome.title_bubble, _chrome.side_container, _chrome.connector]
			if not _auto_play:
				show_nodes.append(_chrome.speech_bubble)
		for node in show_nodes:
			if is_instance_valid(node):
				node.visible = true
				node.modulate.a = 0.0
				var tw2 = node.create_tween()
				tw2.tween_property(node, "modulate:a", 1.0, 0.2)
		if _chrome and is_instance_valid(_chrome.restart_bubble) and _game_over:
			_chrome.restart_bubble.visible = true
		if is_instance_valid(_tutorial_panel) and _tutorial_visible:
			_tutorial_panel.visible = true
		# 自玩中显示面板时保持半透明
		if _auto_play and is_instance_valid(game_container):
			await game_container.get_tree().process_frame
			_auto_fade(AUTO_PLAY_ALPHA)
	else:
		# 隐藏悬浮组件 (带退场动画)
		var chrome_nodes: Array[Control] = []
		if _chrome:
			for node in [_chrome.title_bubble, _chrome.side_container, _chrome.connector, _chrome.speech_bubble, _chrome.restart_bubble]:
				if is_instance_valid(node) and node.visible:
					chrome_nodes.append(node)
		if is_instance_valid(_tutorial_panel):
			chrome_nodes.append(_tutorial_panel)
		# 面板用 modulate.a=0 而不是 visible=false (SubViewport 需要继续渲染)
		if is_instance_valid(game_container):
			var tw = game_container.create_tween()
			tw.tween_property(game_container, "modulate:a", 0.0, 0.15)
		# chrome 组件直接隐藏
		for node in chrome_nodes:
			var tw2 = node.create_tween()
			tw2.tween_property(node, "modulate:a", 0.0, 0.15)
			tw2.finished.connect(func():
				if is_instance_valid(node):
					node.visible = false
			)

# ══════════════════════════════════════════════
# 教程面板 (内部)
# ══════════════════════════════════════════════

func _toggle_tutorial() -> void:
	if _tutorial_visible:
		_hide_tutorial()
	else:
		_show_tutorial()

func _show_tutorial() -> void:
	if _tutorial_visible:
		return
	var steps = get_tutorial_steps()
	if steps.is_empty():
		return
	_tutorial_visible = true
	_build_tutorial_panel(steps)

	# 按钮高亮 (表示教程已展开)
	if _chrome and _chrome.help_btn:
		_chrome.help_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.5, 1.0, 0.9))

func _hide_tutorial() -> void:
	_tutorial_visible = false
	if _chrome and _chrome.help_btn:
		_chrome.help_btn.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65, 0.7))
	if is_instance_valid(_tutorial_panel):
		var panel = _tutorial_panel
		_tutorial_panel = null
		var tween = panel.create_tween().set_parallel(true)
		tween.tween_property(panel, "modulate:a", 0.0, 0.15)
		tween.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.15)
		tween.finished.connect(func():
			if is_instance_valid(panel):
				panel.queue_free()
		)

func _destroy_tutorial() -> void:
	_tutorial_visible = false
	if is_instance_valid(_tutorial_panel):
		_tutorial_panel.queue_free()
		_tutorial_panel = null

func _build_tutorial_panel(steps: Array[Dictionary]) -> void:
	var hue = EventBus.ui_hue
	_tutorial_panel = PanelContainer.new()
	_tutorial_panel.custom_minimum_size = Vector2(200, 0)

	# 面板背景 (同游戏面板风格，略透明)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.12, 0.92)
	bg.border_color = Color.from_hsv(hue, 0.4, 0.7, 0.3)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 12
	bg.content_margin_right = 12
	bg.content_margin_top = 10
	bg.content_margin_bottom = 10
	_tutorial_panel.add_theme_stylebox_override("panel", bg)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_panel.add_child(vbox)

	# 标题
	var title_label = Label.new()
	title_label.text = "任务简报"
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color.from_hsv(hue, 0.4, 1.0, 0.85))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_label)

	# 分割线
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = Color.from_hsv(hue, 0.5, 0.7, 0.15)
	sep_style.set_content_margin_all(0)
	sep.add_theme_stylebox_override("separator", sep_style)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# 可选: 预览动画区
	var preview = get_tutorial_preview()
	if preview:
		var preview_wrapper = PanelContainer.new()
		var preview_bg = StyleBoxFlat.new()
		preview_bg.bg_color = Color(0.03, 0.05, 0.10, 0.7)
		preview_bg.set_corner_radius_all(6)
		preview_bg.set_content_margin_all(4)
		preview_wrapper.add_theme_stylebox_override("panel", preview_bg)
		preview_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_wrapper.add_child(preview)
		vbox.add_child(preview_wrapper)

	# 教程步骤
	for i in range(steps.size()):
		var step = steps[i]
		var step_hbox = HBoxContainer.new()
		step_hbox.add_theme_constant_override("separation", 6)
		step_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# 序号圆点
		var num_label = Label.new()
		num_label.text = str(i + 1)
		num_label.add_theme_font_size_override("font_size", 11)
		num_label.add_theme_color_override("font_color", Color.from_hsv(hue, 0.4, 0.9, 0.6))
		num_label.custom_minimum_size = Vector2(14, 0)
		num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		step_hbox.add_child(num_label)

		# 步骤文字
		var text_label = Label.new()
		text_label.text = step.get("text", "")
		text_label.add_theme_font_size_override("font_size", 12)
		text_label.add_theme_color_override("font_color", Color(0.6, 0.72, 0.85, 0.9))
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		step_hbox.add_child(text_label)

		vbox.add_child(step_hbox)

	# 添加到屏幕层 (不进 SubViewport, 不会显示在全息屏上)
	var parent = game_container.get_parent()
	if parent:
		parent.add_child(_tutorial_panel)

	# 定位 (游戏面板的外侧)
	await _tutorial_panel.get_tree().process_frame
	_position_tutorial()

	# 弹入动画
	_tutorial_panel.modulate.a = 0.0
	_tutorial_panel.scale = Vector2(0.85, 0.85)
	_tutorial_panel.pivot_offset = _tutorial_panel.size / 2.0
	var tween = _tutorial_panel.create_tween().set_parallel(true)
	tween.tween_property(_tutorial_panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(_tutorial_panel, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _position_tutorial() -> void:
	if not is_instance_valid(_tutorial_panel) or not is_instance_valid(game_container):
		return
	var gc_pos = game_container.position
	var gc_size = game_container.size
	var tp_size = _tutorial_panel.size
	var vp = screen_size
	var gap := 8.0

	# 优先放在游戏面板远离宠物的一侧
	var pet_x: float = vp.x / 2.0
	if is_instance_valid(_pet):
		pet_x = _pet.get_global_transform_with_canvas().get_origin().x

	var x: float
	if gc_pos.x + gc_size.x / 2.0 > pet_x:
		# 游戏面板在宠物右边 → 教程放游戏面板右边
		x = gc_pos.x + gc_size.x + gap
		# 如果有侧边按钮在右边，教程再往外推
		if _chrome and _chrome.chrome_side > 0 and is_instance_valid(_chrome.side_container):
			x += _chrome.side_container.size.x + gap
	else:
		# 游戏面板在宠物左边 → 教程放游戏面板左边
		x = gc_pos.x - tp_size.x - gap
		if _chrome and _chrome.chrome_side < 0 and is_instance_valid(_chrome.side_container):
			x -= _chrome.side_container.size.x + gap

	# Y: 顶部对齐游戏面板
	var y = gc_pos.y

	# 边界保护
	x = clampf(x, 8.0, vp.x - tp_size.x - 8.0)
	y = clampf(y, 8.0, vp.y - tp_size.y - 8.0)

	# 如果放不下 (被挤出屏幕), 叠在游戏面板上方
	if x < 8.0 or x + tp_size.x > vp.x - 8.0:
		x = gc_pos.x
		y = gc_pos.y - tp_size.y - gap
		y = clampf(y, 8.0, vp.y - tp_size.y - 8.0)

	_tutorial_panel.position = Vector2(x, y)



# ═══════════════════════════════════════════
# 通用内嵌类: 网格渲染器
# ═══════════════════════════════════════════

## 自绘网格控件 — 贪吃蛇/俄罗斯方块等基于 Canvas 的游戏共用。
## 子类需实现 _render(canvas)、_on_grid_input(event)、_grid_process(delta)。
class GridRenderer extends Control:
	var game

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		grab_focus()

	func _draw() -> void:
		if game:
			game._render(self)

	func _gui_input(event: InputEvent) -> void:
		if game:
			game._on_grid_input(event)

	func _process(delta: float) -> void:
		if game:
			game._grid_process(delta)

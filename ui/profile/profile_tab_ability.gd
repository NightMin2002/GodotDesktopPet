# profile_tab_ability.gd — 能力数据 Tab (等级/经验/控制/互动)
extends ScrollContainer

const INTERACT_LINES := [
	"正在处理信号。...不是在看你。",
	"检测到注意力分配请求。已记录。",
	"传感器校准中。请勿干扰。",
	"系统正常。不需要确认。",
	"...数据表明你在盯着本机。",
	"操作记录已同步。无异常。",
	"本机不需要互动。但也没有拒绝。",
	"当前运行状态：稳定。...嗯。",
	"...你的观测记录已被观测。",
	"运行日志无异常。无需手动确认。",
]

var _level_label: Label
var _xp_label: Label
var _rate_label: Label
var _level_bar_fill: Panel
var _level_bar_bg: Panel
var _last_interact_line: String = ""

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	var vbox = ProfileStyles.make_tab_vbox(12)
	add_child(vbox)

	var lv_info = SettingsManager.get_gaming_level_progress()
	var accent = ProfileStyles.accent()
	var dim = ProfileStyles.dim()
	var bright = ProfileStyles.bright()

	# ── 等级标题 ──
	_level_label = ProfileStyles.make_label("游戏熟练度  Lv.%d" % lv_info.level, 22, accent)
	vbox.add_child(_level_label)

	# ── XP 进度条 ──
	var bar_w := 320.0
	_level_bar_bg = Panel.new()
	_level_bar_bg.custom_minimum_size = Vector2(bar_w, 8)
	var bar_bg_s = StyleBoxFlat.new()
	bar_bg_s.bg_color = Color(0.08, 0.10, 0.18, 0.6)
	bar_bg_s.set_corner_radius_all(4)
	_level_bar_bg.add_theme_stylebox_override("panel", bar_bg_s)
	_level_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_level_bar_bg)

	_level_bar_fill = Panel.new()
	_level_bar_fill.position = Vector2.ZERO
	_level_bar_fill.size = Vector2(bar_w * clampf(lv_info.progress, 0, 1), 8)
	var bar_fill_s = StyleBoxFlat.new()
	bar_fill_s.bg_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.85, 0.8)
	bar_fill_s.set_corner_radius_all(4)
	_level_bar_fill.add_theme_stylebox_override("panel", bar_fill_s)
	_level_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_bar_bg.add_child(_level_bar_fill)

	# ── XP 数值 ──
	_xp_label = ProfileStyles.make_label("", 16, bright)
	if lv_info.level >= SettingsManager.MAX_LEVEL:
		_xp_label.text = "经验值: %d (MAX)" % lv_info.xp
	else:
		_xp_label.text = "经验值: %d / %d" % [lv_info.xp, lv_info.xp_next]
	vbox.add_child(_xp_label)

	# ── 失误率 ──
	_rate_label = ProfileStyles.make_label("操作失误率: %.1f%%" % (lv_info.rate * 100.0), 16, dim)
	vbox.add_child(_rate_label)

	# ── 等级说明 ──
	var note = ProfileStyles.make_label("熟练度随对局自动积累。等级越高，自主操作失误率越低。", 14, Color(0.4, 0.5, 0.6, 0.4))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(note)

	# ── 分隔线 ──
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	sep.add_theme_constant_override("separation", 1)
	vbox.add_child(sep)

	# ── 等级控制行 ──
	var ctrl_row = HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 8)
	ctrl_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_row.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(ctrl_row)

	ctrl_row.add_child(ProfileStyles.make_label("等级调整", 15, dim))

	var btn_n = ProfileStyles.small_btn_normal()
	var btn_h = ProfileStyles.small_btn_hover()

	for item in [{"label": "-", "action": "down"}, {"label": "∝", "action": "reset"}, {"label": "+", "action": "up"}]:
		var btn = Button.new()
		btn.text = item.label
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
		btn.add_theme_stylebox_override("normal", btn_n)
		btn.add_theme_stylebox_override("hover", btn_h)
		btn.add_theme_stylebox_override("pressed", btn_h)
		var action = item.action
		btn.pressed.connect(func(): _on_level_action(action))
		ctrl_row.add_child(btn)

	# ── 互动按钮 ──
	var interact_btn = Button.new()
	interact_btn.text = "互动"
	interact_btn.add_theme_font_size_override("font_size", 16)
	interact_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.95, 0.9))
	var ib_n = StyleBoxFlat.new()
	ib_n.bg_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.15, 0.6)
	ib_n.set_corner_radius_all(6)
	ib_n.set_border_width_all(1)
	ib_n.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.6, 0.4)
	ib_n.content_margin_left = 16; ib_n.content_margin_right = 16
	ib_n.content_margin_top = 5; ib_n.content_margin_bottom = 5
	interact_btn.add_theme_stylebox_override("normal", ib_n)
	var ib_h = ib_n.duplicate()
	ib_h.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.25, 0.7)
	ib_h.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.6)
	interact_btn.add_theme_stylebox_override("hover", ib_h)
	interact_btn.add_theme_stylebox_override("pressed", ib_h)
	interact_btn.pressed.connect(_on_interact)
	vbox.add_child(interact_btn)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_level_label = null
	_xp_label = null
	_rate_label = null
	_level_bar_fill = null
	_level_bar_bg = null
	build()

# ── 等级控制 ──

func _on_level_action(action: String) -> void:
	var pet = _get_pet()
	var level = SettingsManager.get_gaming_level()
	if action == "up":
		if level >= SettingsManager.MAX_LEVEL:
			if pet: pet.show_local_bubble("...已是最高等级。")
			return
		var target_xp = SettingsManager.LEVEL_XP[mini(level, SettingsManager.MAX_LEVEL - 1)]
		SettingsManager.set_int("gaming_xp", target_xp)
		if pet: pet.show_local_bubble("...后台训练模块的数据已同步。Lv.%d。" % SettingsManager.get_gaming_level())
	elif action == "down":
		if level <= 1:
			if pet: pet.show_local_bubble("...已经 Lv.1。没有可回退的数据。")
			return
		var target_xp = SettingsManager.LEVEL_XP[level - 2]
		SettingsManager.set_int("gaming_xp", target_xp)
		if pet: pet.show_local_bubble("训练数据回退。Lv.%d。...不太理解目的。" % SettingsManager.get_gaming_level())
	elif action == "reset":
		SettingsManager.set_int("gaming_xp", 0)
		if pet: pet.show_local_bubble("检测到用户越权清除训练数据。...已批准。")
	refresh()

func _on_interact() -> void:
	var pet = _get_pet()
	if not pet:
		return
	var line = INTERACT_LINES[randi() % INTERACT_LINES.size()]
	while INTERACT_LINES.size() > 1 and line == _last_interact_line:
		line = INTERACT_LINES[randi() % INTERACT_LINES.size()]
	_last_interact_line = line
	pet.show_local_bubble(line)

func _get_pet() -> Node:
	var main_n = get_tree().root.get_node_or_null("Main")
	if main_n and "pet_instances" in main_n and main_n.pet_instances.size() > 0:
		return main_n.pet_instances[0]
	return null

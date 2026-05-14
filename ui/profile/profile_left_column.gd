# profile_left_column.gd — 档案左栏 (头像 + 状态 + 身份信息)
extends VBoxContainer

const BIRTH_DATE := "2026.04.07 14:08:17"
const MODEL_NAME := "桌面观测单元"
const UNIT_ID := "#0001"

var _days_label: Label
var _launch_label: Label

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

var _last_interact_line: String = ""
var _avatar_frame: Control

func _init() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size.x = 220
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)

func _process(_delta: float) -> void:
	if is_instance_valid(_avatar_frame):
		_avatar_frame.queue_redraw()

func build() -> void:
	# ── 头像边框 (八角形 HUD 雷达扫描框) ──
	_avatar_frame = PanelContainer.new()
	var af_s = StyleBoxEmpty.new()
	_avatar_frame.add_theme_stylebox_override("panel", af_s)
	_avatar_frame.custom_minimum_size = Vector2(200, 200)
	_avatar_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_avatar_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	_avatar_frame.clip_contents = true # 切掉溢出的雷达波
	ProfileStyles.add_avatar_frame(_avatar_frame)

	var avatar = ProfileAvatar.new()
	avatar.custom_minimum_size = Vector2(186, 186)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar.mouse_filter = Control.MOUSE_FILTER_PASS
	_avatar_frame.add_child(avatar)

	# ── 交互指令 (戳一戳) ──
	var interact_btn = Button.new()
	interact_btn.text = "> 发送 [戳一戳] 指令"
	interact_btn.add_theme_font_size_override("font_size", 13)
	interact_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.95, 0.9))
	var ib_n = StyleBoxFlat.new()
	ib_n.bg_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.15, 0.4)
	ib_n.set_border_width_all(1)
	ib_n.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.6, 0.5)
	ib_n.content_margin_left = 16; ib_n.content_margin_right = 16
	ib_n.content_margin_top = 8; ib_n.content_margin_bottom = 8
	interact_btn.add_theme_stylebox_override("normal", ib_n)
	var ib_h = ib_n.duplicate()
	ib_h.bg_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.3, 0.6)
	interact_btn.add_theme_stylebox_override("hover", ib_h)
	interact_btn.add_theme_stylebox_override("pressed", ib_h)
	interact_btn.pressed.connect(_on_interact)

	# ── 状态气泡徽章 ──
	var status_badge = PanelContainer.new()
	var sb_s = StyleBoxFlat.new()
	sb_s.bg_color = Color(0.05, 0.18, 0.08, 0.7)
	sb_s.border_width_left = 3
	sb_s.border_color = Color(0.2, 0.8, 0.4, 0.8)
	sb_s.content_margin_left = 12; sb_s.content_margin_right = 16
	sb_s.content_margin_top = 4; sb_s.content_margin_bottom = 4
	status_badge.add_theme_stylebox_override("panel", sb_s)
	status_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var status_row = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_badge.add_child(status_row)

	status_row.add_child(ProfileStyles.make_label("■", 10, Color(0.3, 1.0, 0.5, 0.95)))
	status_row.add_child(ProfileStyles.make_label("状态正常", 12, Color(0.3, 1.0, 0.5, 0.9)))

	# ── 性格描述 ──
	var persona_label = ProfileStyles.label_dim("「不要擅自解读本机的行为模式。」", 13)
	persona_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	persona_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ── 布局
	var top_sp = Control.new()
	top_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_sp)

	add_child(_avatar_frame)
	add_child(interact_btn)
	add_child(status_badge)
	add_child(persona_label)

	var bot_sp = Control.new()
	bot_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bot_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bot_sp)

	_build_identity_section()

# ── 身份信息 (方框数据卡片) ──

func _build_identity_section() -> void:
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", ProfileStyles.card_style())
	ProfileStyles.add_tech_brackets(card, 5.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(vbox)

	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim("数据块 // 身份标识", 12))
	vbox.add_child(title_row)

	var hsep = HSeparator.new()
	hsep.add_theme_stylebox_override("separator", ProfileStyles.separator_style())
	vbox.add_child(hsep)

	_add_info_row(vbox, "型号", MODEL_NAME)
	_add_info_row(vbox, "编号", UNIT_ID)
	_add_info_row(vbox, "出厂", BIRTH_DATE)

	var launch_date = SettingsManager.get_first_launch_date()
	var formatted = launch_date.replace("-", ".").replace("T", " ")
	_launch_label = _add_info_row(vbox, "启用", formatted)
	_days_label = _add_info_row(vbox, "运行", _calc_running_time())
	
	add_child(card)

func _add_info_row(parent: Control, label_text: String, value_text: String) -> Label:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var k = ProfileStyles.label_dim(label_text, 12)
	k.custom_minimum_size.x = 36
	var v = ProfileStyles.value_label(value_text, 14)
	
	row.add_child(k)
	row.add_child(v)
	parent.add_child(row)
	return v

func _calc_running_time() -> String:
	var launch_str = SettingsManager.get_first_launch_date()
	var date_part = launch_str.split("T")[0] if "T" in launch_str else launch_str.split(" ")[0]
	var time_part = launch_str.split("T")[1] if "T" in launch_str else "00:00:00"
	var dp = date_part.split("-")
	var tp = time_part.split(":")
	if dp.size() < 3:
		return "0 天 00:00:00"
	var launch_dict = {
		"year": int(dp[0]), "month": int(dp[1]), "day": int(dp[2]),
		"hour": int(tp[0]) if tp.size() > 0 else 0,
		"minute": int(tp[1]) if tp.size() > 1 else 0,
		"second": int(tp[2]) if tp.size() > 2 else 0,
	}
	var now = Time.get_datetime_dict_from_system()
	var launch_unix = Time.get_unix_time_from_datetime_dict(launch_dict)
	var now_unix = Time.get_unix_time_from_datetime_dict(now)
	var diff = maxi(0, int(now_unix - launch_unix))
	var days = diff / 86400
	var hours = (diff % 86400) / 3600
	var mins = (diff % 3600) / 60
	var secs = diff % 60
	return "%d 天 %02d:%02d:%02d" % [days, hours, mins, secs]

# ── 数据刷新 ──

func refresh() -> void:
	if _days_label:
		_days_label.text = _calc_running_time()

func _get_pet() -> Node:
	var main_n = get_tree().root.get_node_or_null("Main")
	if main_n and "pet_instances" in main_n and main_n.pet_instances.size() > 0:
		return main_n.pet_instances[0]
	return null

func _on_interact() -> void:
	var pet = _get_pet()
	if not pet:
		return
	var line = INTERACT_LINES[randi() % INTERACT_LINES.size()]
	while INTERACT_LINES.size() > 1 and line == _last_interact_line:
		line = INTERACT_LINES[randi() % INTERACT_LINES.size()]
	_last_interact_line = line
	if pet.has_method("show_local_bubble"):
		pet.show_local_bubble(line)

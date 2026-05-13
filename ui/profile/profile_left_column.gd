# profile_left_column.gd — 档案左栏 (头像 + 状态 + 身份信息)
extends VBoxContainer

const BIRTH_DATE := "2026.04.07 14:08:17"
const MODEL_NAME := "桌面观测单元"
const UNIT_ID := "#0001"

var _days_label: Label
var _launch_label: Label

func _init() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size.x = 220
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	# ── 头像边框 ──
	var avatar_frame = PanelContainer.new()
	var af_s = StyleBoxFlat.new()
	af_s.bg_color = Color(0.03, 0.05, 0.10, 0.6)
	af_s.set_border_width_all(2)
	af_s.border_color = Color.from_hsv(EventBus.ui_hue, 0.4, 0.7, 0.5)
	af_s.set_corner_radius_all(4)
	af_s.set_content_margin_all(6)
	avatar_frame.add_theme_stylebox_override("panel", af_s)
	avatar_frame.custom_minimum_size = Vector2(200, 200)
	avatar_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar_frame.mouse_filter = Control.MOUSE_FILTER_PASS

	var avatar = ProfileAvatar.new()
	avatar.custom_minimum_size = Vector2(186, 186)
	avatar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avatar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avatar.mouse_filter = Control.MOUSE_FILTER_PASS
	avatar_frame.add_child(avatar)

	# ── 状态气泡徽章 ──
	var status_badge = PanelContainer.new()
	var sb_s = StyleBoxFlat.new()
	sb_s.bg_color = Color(0.05, 0.18, 0.08, 0.7)
	sb_s.set_border_width_all(1)
	sb_s.border_color = Color(0.2, 0.8, 0.4, 0.4)
	sb_s.set_corner_radius_all(10)
	sb_s.content_margin_left = 12; sb_s.content_margin_right = 12
	sb_s.content_margin_top = 3; sb_s.content_margin_bottom = 3
	status_badge.add_theme_stylebox_override("panel", sb_s)
	status_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var status_row = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 5)
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_badge.add_child(status_row)

	status_row.add_child(ProfileStyles.make_label("●", 9, Color(0.3, 1.0, 0.5, 0.95)))
	status_row.add_child(ProfileStyles.make_label("运行中", 13, Color(0.3, 1.0, 0.5, 0.8)))

	# ── 性格描述 ──
	var persona_label = ProfileStyles.make_label("「不要擅自解读本机的行为模式。」", 13, Color(0.5, 0.6, 0.7, 0.35))
	persona_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	persona_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ── 布局: 上 spacer → 头像组 → 下 spacer → 身份信息 ──
	var top_sp = Control.new()
	top_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_sp)

	add_child(avatar_frame)
	add_child(status_badge)
	add_child(persona_label)

	var bot_sp = Control.new()
	bot_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bot_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bot_sp)

	_build_identity_section()

# ── 身份信息 ──

func _build_identity_section() -> void:
	var dim = ProfileStyles.dim()
	var bright = ProfileStyles.bright()
	var accent = ProfileStyles.accent()

	_add_info_row("型号", MODEL_NAME, dim, bright)
	_add_info_row("编号", UNIT_ID, dim, accent)
	_add_info_row("出厂", BIRTH_DATE, dim, bright)

	var launch_date = SettingsManager.get_first_launch_date()
	var formatted = launch_date.replace("-", ".").replace("T", " ")
	_launch_label = _add_info_row("启用", formatted, dim, bright)
	_days_label = _add_info_row("运行", _calc_running_time(), dim, accent)

func _add_info_row(label_text: String, value_text: String, dim: Color, bright: Color) -> Label:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	row.add_child(ProfileStyles.make_label(label_text, 17, dim))
	row.get_child(0).custom_minimum_size.x = 38

	var val = ProfileStyles.make_label(value_text, 17, bright)
	row.add_child(val)
	add_child(row)
	return val

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

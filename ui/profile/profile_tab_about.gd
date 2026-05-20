# profile_tab_about.gd — 关于 Tab (装置终端 Tab 3)
# 版本信息 + 更新检测 + 项目链接
extends HBoxContainer

const _UpdateChecker = preload("res://core/update_checker.gd")

var _status_label: Label
var _check_btn: Button

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func build() -> void:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 20)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(main_vbox)

	# ── 1. 版本信息卡片 ──
	_build_version_card(main_vbox)

	# ── 2. 系统概况 ──
	_build_system_info(main_vbox)

	# ── 3. 项目链接 ──
	_build_links(main_vbox)

	# ── 4. 开源致谢 ──
	_build_credits(main_vbox)

	# 滚动指示器
	var indicator = preload("res://ui/profile/cyber_scroll_indicator.gd").new()
	indicator.bind_scroll(scroll)
	add_child(indicator)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	build()

# ═══════════════════════════════════════════════
#  版本信息
# ═══════════════════════════════════════════════

func _build_version_card(parent: VBoxContainer) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color.from_hsv(EventBus.ui_hue, 0.35, 0.16, 0.45)
	cs.border_width_left = 4
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.6, 0.8, 0.7)
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 24; cs.content_margin_right = 24
	cs.content_margin_top = 20; cs.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	# 标题行
	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim("SYS_VERSION //", 13))
	title_row.add_child(ProfileStyles.make_label("版本信息", 17, Color(0.85, 0.9, 0.95)))
	vbox.add_child(title_row)

	# 版本号 (大字)
	var ver_row = HBoxContainer.new()
	ver_row.add_theme_constant_override("separation", 12)
	var ver_label = Label.new()
	ver_label.text = "v%s" % _UpdateChecker.CURRENT_VERSION
	ver_label.add_theme_font_size_override("font_size", 32)
	ver_label.add_theme_color_override("font_color", ProfileStyles.accent())
	ver_row.add_child(ver_label)

	var name_label = Label.new()
	name_label.text = "桌面宠物"
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 0.7))
	var name_center = CenterContainer.new()
	name_center.add_child(name_label)
	ver_row.add_child(name_center)
	vbox.add_child(ver_row)

	# 分隔线
	var hsep = HSeparator.new()
	var sep_s = StyleBoxFlat.new()
	sep_s.border_width_top = 1
	sep_s.border_color = Color(1, 1, 1, 0.05)
	hsep.add_theme_stylebox_override("separator", sep_s)
	hsep.add_theme_constant_override("separation", 1)
	vbox.add_child(hsep)

	# 更新状态行
	var update_row = HBoxContainer.new()
	update_row.add_theme_constant_override("separation", 12)

	_status_label = Label.new()
	_status_label.text = "> 版本状态检测中..."
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", ProfileStyles.dim())
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	update_row.add_child(_status_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	update_row.add_child(spacer)

	_check_btn = Button.new()
	_check_btn.text = "检查更新"
	_check_btn.add_theme_font_size_override("font_size", 13)
	_check_btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
	_check_btn.add_theme_stylebox_override("normal", ProfileStyles.small_btn_normal())
	_check_btn.add_theme_stylebox_override("hover", ProfileStyles.small_btn_hover())
	_check_btn.add_theme_stylebox_override("pressed", ProfileStyles.small_btn_hover())
	_check_btn.pressed.connect(_on_check_update)
	update_row.add_child(_check_btn)

	vbox.add_child(update_row)

	# 异步检查当前版本状态
	_check_version_status.call_deferred()

func _check_version_status() -> void:
	var http = HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body):
		if not is_instance_valid(_status_label):
			return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_status_label.text = "> 无法连接更新服务器"
			_status_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.4, 0.7))
		else:
			var json = JSON.parse_string(body.get_string_from_utf8())
			if json and json is Dictionary:
				var remote_tag: String = json.get("tag_name", "")
				var remote_ver = _norm(remote_tag)
				var local_ver = _norm(_UpdateChecker.CURRENT_VERSION)
				if _is_newer(remote_ver, local_ver):
					_status_label.text = "> 新版本 %s 可用" % remote_tag
					_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6, 0.9))
				else:
					_status_label.text = "> 当前已是最新版本"
					_status_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.5, 0.7))
		if is_instance_valid(http):
			http.queue_free()
	)
	var headers = ["User-Agent: GodotDesktopPet", "Accept: application/vnd.github.v3+json"]
	http.request(_UpdateChecker.API_URL, headers)

func _on_check_update() -> void:
	if _status_label:
		_status_label.text = "> 正在检查..."
		_status_label.add_theme_color_override("font_color", ProfileStyles.dim())
	_check_version_status()

func _norm(ver: String) -> Array[int]:
	var c = ver.strip_edges().to_lower()
	if c.begins_with("v"): c = c.substr(1)
	var r: Array[int] = []
	for p in c.split("."): r.append(int(p))
	while r.size() < 3: r.append(0)
	return r

func _is_newer(remote: Array[int], local: Array[int]) -> bool:
	for i in range(max(remote.size(), local.size())):
		var r: int = remote[i] if i < remote.size() else 0
		var l: int = local[i] if i < local.size() else 0
		if r > l: return true
		if r < l: return false
	return false

# ═══════════════════════════════════════════════
#  系统概况
# ═══════════════════════════════════════════════

func _build_system_info(parent: VBoxContainer) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.04, 0.06, 0.1, 0.4)
	cs.border_width_left = 2
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.3)
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 20; cs.content_margin_right = 20
	cs.content_margin_top = 16; cs.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim("SYS_INFO //", 12))
	title_row.add_child(ProfileStyles.make_label("运行概况", 15, Color(0.75, 0.82, 0.9)))
	vbox.add_child(title_row)

	# 首次启用日期
	var first_launch = SettingsManager.get_first_launch_date()
	if first_launch != "":
		_add_info_row(vbox, "启用日期", first_launch)

	# 运行引擎
	_add_info_row(vbox, "运行引擎", "Godot %s" % Engine.get_version_info().string)

	# 渲染器
	var renderer := "未知"
	var rs_name = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	if rs_name == "gl_compatibility":
		renderer = "OpenGL (兼容模式)"
	elif rs_name == "mobile":
		renderer = "Vulkan Mobile"
	elif rs_name == "forward_plus":
		renderer = "Vulkan Forward+"
	_add_info_row(vbox, "渲染后端", renderer)

	# 操作系统 (Windows 11 内部版本号仍为 10.0.x，需根据 build 区分)
	var os_str := OS.get_name()
	var os_ver := OS.get_version()
	if os_str == "Windows":
		# os_ver 格式: "10.0.22631" 等, build >= 22000 为 Win11
		var parts = os_ver.split(".")
		if parts.size() >= 3 and int(parts[2]) >= 22000:
			os_str = "Windows 11"
		else:
			os_str = "Windows 10"
		os_str += " (Build %s)" % parts[2] if parts.size() >= 3 else ""
	else:
		os_str += " " + os_ver
	_add_info_row(vbox, "操作系统", os_str)

	# 数据迭代次数
	_add_info_row(vbox, "数据迭代", "第 %d 次更新" % _UpdateChecker.COMMIT_COUNT)

func _add_info_row(parent: VBoxContainer, key: String, value: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var k = Label.new()
	k.text = key
	k.add_theme_font_size_override("font_size", 13)
	k.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 0.6))
	k.custom_minimum_size = Vector2(80, 0)
	row.add_child(k)

	var v = Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 14)
	v.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85, 0.85))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)

	parent.add_child(row)

# ═══════════════════════════════════════════════
#  项目链接
# ═══════════════════════════════════════════════

func _build_links(parent: VBoxContainer) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.04, 0.06, 0.1, 0.4)
	cs.border_width_left = 2
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.3)
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 20; cs.content_margin_right = 20
	cs.content_margin_top = 16; cs.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim("LINKS //", 12))
	title_row.add_child(ProfileStyles.make_label("项目", 15, Color(0.75, 0.82, 0.9)))
	vbox.add_child(title_row)

	_add_link_btn(vbox, "GitHub 仓库", "https://github.com/" + _UpdateChecker.REPO_OWNER + "/" + _UpdateChecker.REPO_NAME)
	_add_link_btn(vbox, "Release 下载", _UpdateChecker.RELEASE_PAGE)

func _add_link_btn(parent: VBoxContainer, text: String, url: String) -> void:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.4, 0.85, 0.8))
	btn.add_theme_color_override("font_hover_color", Color.from_hsv(EventBus.ui_hue, 0.5, 1.0, 1.0))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.06, 0.1, 0.3)
	s.border_width_left = 2
	s.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.25)
	s.set_corner_radius_all(0)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 6; s.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(0.06, 0.1, 0.18, 0.6)
	h.border_color = Color.from_hsv(EventBus.ui_hue, 0.5, 0.8, 0.5)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	var u = url
	btn.pressed.connect(func(): OS.shell_open(u))
	parent.add_child(btn)

# ═══════════════════════════════════════════════
#  开源致谢
# ═══════════════════════════════════════════════

func _build_credits(parent: VBoxContainer) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.04, 0.06, 0.1, 0.4)
	cs.border_width_left = 2
	cs.border_color = Color.from_hsv(EventBus.ui_hue, 0.3, 0.5, 0.3)
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 20; cs.content_margin_right = 20
	cs.content_margin_top = 16; cs.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", cs)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var title_row = HBoxContainer.new()
	title_row.add_child(ProfileStyles.label_dim("CREDITS //", 12))
	title_row.add_child(ProfileStyles.make_label("开源致谢", 15, Color(0.75, 0.82, 0.9)))
	vbox.add_child(title_row)

	_add_credit_row(vbox, "Everything", "voidtools", "MIT License", "https://www.voidtools.com/", "文件检索引擎")
	_add_credit_row(vbox, "Godot Engine", "Godot Community", "MIT License", "https://godotengine.org/", "游戏引擎")

func _add_credit_row(parent: VBoxContainer, name: String, author: String, license: String, url: String, desc: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 2)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 名称行
	var name_row = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var name_label = Label.new()
	name_label.text = name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9, 0.9))
	name_row.add_child(name_label)

	var license_label = Label.new()
	license_label.text = "(%s)" % license
	license_label.add_theme_font_size_override("font_size", 12)
	license_label.add_theme_color_override("font_color", Color(0.45, 0.55, 0.45, 0.6))
	name_row.add_child(license_label)
	info_vbox.add_child(name_row)

	# 描述行
	var desc_label = Label.new()
	desc_label.text = "%s — by %s" % [desc, author]
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 0.55))
	info_vbox.add_child(desc_label)

	row.add_child(info_vbox)

	# 链接按钮
	var link_btn = Button.new()
	link_btn.text = ">"
	link_btn.add_theme_font_size_override("font_size", 14)
	link_btn.add_theme_color_override("font_color", Color.from_hsv(EventBus.ui_hue, 0.3, 0.7, 0.6))
	link_btn.add_theme_color_override("font_hover_color", Color.from_hsv(EventBus.ui_hue, 0.5, 1.0, 1.0))
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.06, 0.1, 0.2)
	s.set_corner_radius_all(2)
	s.content_margin_left = 8; s.content_margin_right = 8
	s.content_margin_top = 4; s.content_margin_bottom = 4
	link_btn.add_theme_stylebox_override("normal", s)
	var h = s.duplicate()
	h.bg_color = Color(0.08, 0.12, 0.2, 0.5)
	link_btn.add_theme_stylebox_override("hover", h)
	link_btn.add_theme_stylebox_override("pressed", h)
	var u = url
	link_btn.pressed.connect(func(): OS.shell_open(u))
	row.add_child(link_btn)

	parent.add_child(row)

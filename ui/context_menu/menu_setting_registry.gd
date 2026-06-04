# menu_setting_registry.gd — 右键菜单设置项注册表
extends RefCounted

const TOGGLE_GROUPS := {
	"sec_display": [
		{"id": "hud_pin", "on": "常驻显示 [●]", "off": "常驻显示 [○]", "key": "hud_pin", "default": false},
		{"id": "hud_clock", "on": "系统时钟 [●]", "off": "系统时钟 [○]", "key": "hud_clock", "default": false},
		{"id": "hud_wifi", "on": "WiFi 信息 [●]", "off": "WiFi 信息 [○]", "key": "hud_wifi", "default": false},
		{"id": "hud_todo", "on": "待办计数 [●]", "off": "待办计数 [○]", "key": "hud_todo", "default": false},
	],
	"mode": [
		{"id": "eye_track", "on": "指针跟踪 [●]", "off": "指针跟踪 [○]", "key": "eye_track", "default": true},
		{"id": "anti_gravity", "on": "反重力 [●]", "off": "反重力 [○]", "key": "anti_gravity", "default": false},
		{"id": "free_roam", "on": "空间跳跃 [●]", "off": "空间跳跃 [○]", "key": "free_roam", "default": false},
		{"id": "screen_wrap", "on": "屏幕穿越 [●]", "off": "屏幕穿越 [○]", "key": "screen_wrap", "default": false},
	],
	"effects": [
		{"id": "shockwave", "on": "撞击冲击波 [●]", "off": "撞击冲击波 [○]", "key": "shockwave", "default": true},
		{"id": "arc_fx", "on": "静电弧 [●]", "off": "静电弧 [○]", "key": "arc_fx", "default": true},
		{"id": "roam_spark", "on": "踏板收缩火花 [●]", "off": "踏板收缩火花 [○]", "key": "roam_spark", "default": true},
	],
}

const RADIO_GROUPS := {
	"window_mode": {
		"setting_key": "window_mode",
		"default": 0,
		"event": "window_mode_changed",
		"title_labels": ["窗口 · 自由漫游 [+]", "窗口 · 窗口封闭 [+]", "窗口 · 窗口排斥 [+]"],
		"items": [
			{"value": 0, "label": "自由漫游"},
			{"value": 1, "label": "窗口封闭"},
			{"value": 2, "label": "窗口排斥"},
		],
	},
	"behavior_mode": {
		"setting_key": "behavior_mode",
		"default": 0,
		"event": "behavior_mode_changed",
		"title_labels": ["指令 · 自由行动 [+]", "指令 · 安静待命 [+]"],
		"items": [
			{"value": 0, "label": "自由行动"},
			{"value": 1, "label": "安静待命"},
		],
	},
	"gait": {
		"setting_key": "move_style",
		"default": 0,
		"event": "setting_toggled",
		"title_labels": ["步态 · 蹦跳为主 [+]", "步态 · 滚动为主 [+]", "步态 · 混合平衡 [+]"],
		"items": [
			{"value": 0, "label": "蹦跳为主"},
			{"value": 1, "label": "滚动为主"},
			{"value": 2, "label": "混合平衡"},
		],
	},
	"chatter": {
		"setting_key": "pet_chatter_mode",
		"default": 1,
		"event": "setting_toggled",
		"title_labels": ["碎碎念 · 已关闭 [+]", "碎碎念 · 每30分钟 [+]", "碎碎念 · 每60分钟 [+]"],
		"items": [
			{"value": 0, "label": "关闭", "desc": "宠物不会主动说话"},
			{"value": 1, "label": "每30分钟", "desc": "每到整点和半点，冒泡说点什么"},
			{"value": 2, "label": "每60分钟", "desc": "每到整点，冒泡说点什么"},
		],
	},
	"auto_activity": {
		"setting_key": "auto_activity",
		"default": 1,
		"event": "setting_toggled",
		"title_labels": ["运行功耗 · 待机 [+]", "运行功耗 · 节能 [+]", "运行功耗 · 性能 [+]"],
		"items": [
			{"value": 0, "label": "待机", "desc": "不会自发执行任何活动"},
			{"value": 1, "label": "节能", "desc": "偶尔自发活动，间隔较长"},
			{"value": 2, "label": "性能", "desc": "频繁自发活动，保持活跃"},
		],
	},
	"appearance": {
		"setting_key": "appearance_style",
		"default": 1,
		"event": "appearance_changed",
		"title_labels": ["机体外观 · 经典 [+]", "机体外观 · 现代 [+]"],
		"items": [
			{"value": 0, "label": "经典 (v1.0)", "desc": "初代紧凑设计，白色细环偏内，眼瞳小巧"},
			{"value": 1, "label": "现代 (v2.0)", "desc": "新版饱满设计，白色亮环在最外圈，瞳孔整体等比例放大"},
		],
	},
	"pet_size": {
		"setting_key": "pet_size",
		"default": 50,
		"event": "pet_size_changed",
		"title_template": "机体大小 · %spx [+]",
		"title_by_value": {
			30: "机体大小 · 30px [+]",
			50: "机体大小 · 50px [+]",
			60: "机体大小 · 60px [+]",
			80: "机体大小 · 80px [+]",
			100: "机体大小 · 100px [+]",
		},
		"items": [
			{"value": 30, "label": "微型 (30px)", "desc": "极限紧凑的观测模式"},
			{"value": 50, "label": "常规 (50px)", "desc": "推荐默认尺寸"},
			{"value": 60, "label": "舒适 (60px)", "desc": "2K 分辨率推荐尺寸"},
			{"value": 80, "label": "中型 (80px)", "desc": "中型视觉尺寸"},
			{"value": 100, "label": "大型 (100px)", "desc": "清晰的大型观测尺寸"},
		],
	},
	"elastic": {
		"setting_key": "elastic_mode",
		"default": 0,
		"event": "squash_test",
		"title_labels": ["弹性 · 关闭 [+]", "弹性 · 轻弹 [+]", "弹性 · 果冻 [+]", "弹性 · 弹力球 [+]"],
		"items": [
			{"value": 0, "label": "关闭", "desc": "标准球体，无弹性效果"},
			{"value": 1, "label": "轻弹", "desc": "自然柔弹，快速恢复"},
			{"value": 2, "label": "果冻", "desc": "QQ弹弹，慢速晃动恢复"},
			{"value": 3, "label": "弹力球", "desc": "弹性十足，强力回弹"},
		],
	},
	"hover_fx": {
		"setting_key": "hover_style",
		"default": 1,
		"event": "setting_toggled",
		"title_labels": ["悬停 · 关闭 [+]", "悬停 · 柔光环 [+]", "悬停 · 边缘呼吸 [+]", "悬停 · 锁定框 [+]", "悬停 · 遥测模式 [+]"],
		"items": [
			{"value": 0, "label": "关闭", "desc": "鼠标靠近不显示视觉反馈"},
			{"value": 1, "label": "柔光环", "desc": "柔和的呼吸光晕环绕外壳"},
			{"value": 2, "label": "边缘呼吸", "desc": "外壳边缘节奏性脉冲"},
			{"value": 3, "label": "锁定框", "desc": "科幻准星锁定标记"},
			{"value": 4, "label": "遥测模式", "desc": "极简调试坐标系与高频数据流"},
		],
	},
	"trail_style": {
		"setting_key": "trail_style",
		"default": 1,
		"event": "setting_toggled",
		"title_labels": ["尾流 · 关闭 [+]", "尾流 · 默认 [+]"],
		"items": [
			{"value": 0, "label": "关闭", "desc": "不显示拖影"},
			{"value": 1, "label": "默认", "desc": "基础光晕粒子尾流"},
		],
	},
	"effect_color_mode": {
		"setting_key": "effect_color_mode",
		"default": 0,
		"event": "setting_toggled",
		"items": [
			{"value": 0, "label": "虹彩模式"},
			{"value": 1, "label": "跟随体色"},
		],
	},
}

static func get_toggle_group(group_id: String) -> Array:
	return TOGGLE_GROUPS.get(group_id, []).duplicate(true)

static func get_toggle_ids() -> Array:
	var ids := []
	for group in TOGGLE_GROUPS.values():
		for item in group:
			ids.append(item.id)
	return ids

static func get_toggle_def(item_id: String) -> Dictionary:
	for group in TOGGLE_GROUPS.values():
		for item in group:
			if item.id == item_id:
				return item.duplicate(true)
	return {}

static func get_radio_group(menu_id: String) -> Dictionary:
	return RADIO_GROUPS.get(menu_id, {}).duplicate(true)

static func get_radio_items(menu_id: String) -> Array:
	var group := get_radio_group(menu_id)
	return group.get("items", []).duplicate(true)

static func get_radio_ids() -> Array:
	return RADIO_GROUPS.keys()

static func get_radio_value(menu_id: String) -> int:
	var group := get_radio_group(menu_id)
	var key: String = group.get("setting_key", "")
	var default_value: int = group.get("default", 0)
	if key == "":
		return default_value
	return SettingsManager.get_int(key, default_value)

static func get_radio_title(menu_id: String, value: int) -> String:
	var group := get_radio_group(menu_id)
	if group.has("title_by_value"):
		var by_value: Dictionary = group.title_by_value
		if by_value.has(value):
			return by_value[value]
	if group.has("title_labels"):
		var labels: Array = group.title_labels
		if value >= 0 and value < labels.size():
			return labels[value]
	if group.has("title_template"):
		return group.title_template % str(value)
	return group.get("title", str(value) + " [+]")

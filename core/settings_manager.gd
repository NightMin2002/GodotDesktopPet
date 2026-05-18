# settings_manager.gd — 持久化设置管理器 (Autoload)
# 通过 ConfigFile 将用户偏好和提醒数据保存到磁盘
# Section 分离: "switches" 存 bool, "values" 存 int, "reminders" 存提醒列表, "todos" 存待办事项
extends Node

const SETTINGS_PATH := "user://settings.cfg"
const SECTION_BOOL := "switches"
const SECTION_INT := "values"

var _config := ConfigFile.new()

func _ready() -> void:
	_config.load(SETTINGS_PATH)
	_migrate_legacy_toggles()

## 历史兼容: 旧版本将 bool 和 int 混存在 "toggles" section，自动迁移到分类 section
func _migrate_legacy_toggles() -> void:
	if not _config.has_section("toggles"):
		return
	for key in _config.get_section_keys("toggles"):
		var val = _config.get_value("toggles", key)
		if val is bool:
			_config.set_value(SECTION_BOOL, key, val)
		elif val is int:
			_config.set_value(SECTION_INT, key, val)
	_config.erase_section("toggles")
	_config.save(SETTINGS_PATH)

## 开关型设置 (bool)

func get_bool(key: String, default_val: bool = true) -> bool:
	return _config.get_value(SECTION_BOOL, key, default_val) as bool

func set_bool(key: String, value: bool) -> void:
	_config.set_value(SECTION_BOOL, key, value)
	_config.save(SETTINGS_PATH)

## 数值型设置 (int)

func get_int(key: String, default_val: int = 0) -> int:
	return _config.get_value(SECTION_INT, key, default_val) as int

func set_int(key: String, value: int) -> void:
	_config.set_value(SECTION_INT, key, value)
	_config.save(SETTINGS_PATH)

## ── 游戏熟练度系统 [已清理] ──
## 能力成长系统待重新规划，相关 API 已移除。
## 引用此 API 的 games/base_game.gd 属于冻结代码，不受影响。

## 提醒数据存取
## 提醒格式: [{"time": "09:00", "msg": "该休息了", "on": true, "once": false}, ...]

func get_reminders() -> Array:
	var data = _config.get_value("reminders", "list", [])
	if data is Array:
		return data
	return []

func save_reminders(list: Array) -> void:
	_config.set_value("reminders", "list", list)
	_config.save(SETTINGS_PATH)

## ── 首次启用日期 ──

func get_first_launch_date() -> String:
	var saved = _config.get_value("profile", "first_launch", "")
	if saved == "":
		saved = Time.get_datetime_string_from_system(false, true)  # 本地时间, 含时分秒
		_config.set_value("profile", "first_launch", saved)
		_config.save(SETTINGS_PATH)
	return saved

## 待办事项数据存取
## 格式: [{"id": "uuid", "text": "任务内容", "done": false, "created": "2025-05-12"}, ...]

func get_todos() -> Array:
	var data = _config.get_value("todos", "list", [])
	return data if data is Array else []

func save_todos(list: Array) -> void:
	_config.set_value("todos", "list", list)
	_config.save(SETTINGS_PATH)

## 数据日志存取
## 格式: [{"id": "ts_rand", "title": "标题", "content": "正文", "tags": [], "source": "user"|"pet", "created": "...", "updated": "..."}, ...]

func get_datalogs() -> Array:
	var data = _config.get_value("datalogs", "entries", [])
	return data if data is Array else []

func save_datalogs(list: Array) -> void:
	_config.set_value("datalogs", "entries", list)
	_config.save(SETTINGS_PATH)

## ── 颜色系统 ──
## pet_index: 0=原体, 1~5=克隆体
## 存储格式: [colors] pet_0_hue=223, pet_0_sat=50, pet_0_val=50, ui_hue=190

func get_pet_color(pet_index: int) -> Dictionary:
	var section := "colors"
	var prefix := "pet_%d_" % pet_index
	return {
		"hue": _config.get_value(section, prefix + "hue", -1) as int,
		"sat": _config.get_value(section, prefix + "sat", 50) as int,
		"val": _config.get_value(section, prefix + "val", 50) as int,
	}

func set_pet_color(pet_index: int, hue: int, sat: int, val: int) -> void:
	var section := "colors"
	var prefix := "pet_%d_" % pet_index
	_config.set_value(section, prefix + "hue", hue)
	_config.set_value(section, prefix + "sat", sat)
	_config.set_value(section, prefix + "val", val)
	_config.save(SETTINGS_PATH)

func get_ui_hue() -> int:
	return _config.get_value("colors", "ui_hue", -1) as int

func set_ui_hue(hue: int) -> void:
	_config.set_value("colors", "ui_hue", hue)
	_config.save(SETTINGS_PATH)

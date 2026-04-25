# settings_manager.gd — 持久化设置管理器 (Autoload)
# 通过 ConfigFile 将用户偏好和提醒数据保存到磁盘
# Section 分离: "switches" 存 bool, "values" 存 int, "reminders" 存提醒列表
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

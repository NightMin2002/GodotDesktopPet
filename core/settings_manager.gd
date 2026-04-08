# settings_manager.gd — 持久化设置管理器 (Autoload)
# 通过 ConfigFile 将用户偏好和提醒数据保存到磁盘
extends Node

const SETTINGS_PATH := "user://settings.cfg"

var _config := ConfigFile.new()

func _ready() -> void:
	_config.load(SETTINGS_PATH)

## 开关型设置

func get_bool(key: String, default_val: bool = true) -> bool:
	return _config.get_value("toggles", key, default_val) as bool

func set_bool(key: String, value: bool) -> void:
	_config.set_value("toggles", key, value)
	_config.save(SETTINGS_PATH)

## 提醒数据存取
## 提醒格式: [{"time": "09:00", "msg": "该休息了", "on": true}, ...]

func get_reminders() -> Array:
	var data = _config.get_value("reminders", "list", [])
	if data is Array:
		return data
	return []

func save_reminders(list: Array) -> void:
	_config.set_value("reminders", "list", list)
	_config.save(SETTINGS_PATH)

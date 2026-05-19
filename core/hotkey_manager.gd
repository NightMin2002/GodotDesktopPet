# hotkey_manager.gd — 全局快捷键管理器 (Node, main.gd 挂载)
# 职责: 通过 C# RegisterHotKey 注册系统级全局热键, 每帧轮询 WM_HOTKEY 消息
# 支持: 注册/注销/冲突探测/持久化/Godot按键码与Win32 VK映射
extends Node

# ── 热键定义 ──
# { action_id: { id: int, modifiers: int, vk: int, default_combo: String } }
const HOTKEY_DEFS := {
	"quick_memo": {"id": 1, "default": "ctrl+shift+n"},
}

# ── Win32 modifier flags (与 C# 层对应) ──
const MOD_ALT := 1
const MOD_CTRL := 2
const MOD_SHIFT := 4
const MOD_WIN := 8

# ── 常见系统快捷键白名单 (冲突检测辅助) ──
const SYSTEM_COMBOS := [
	"ctrl+c", "ctrl+v", "ctrl+x", "ctrl+z", "ctrl+a", "ctrl+s",
	"ctrl+w", "ctrl+t", "ctrl+n", "ctrl+p", "ctrl+f", "ctrl+h",
	"ctrl+shift+esc", "ctrl+alt+delete",
	"alt+tab", "alt+f4", "alt+space",
	"win+d", "win+e", "win+l", "win+r", "win+i", "win+s",
	"win+tab", "win+shift+s", "win+v", "win+g",
	"ctrl+shift+t", "ctrl+shift+i",
]

# ── 内部状态 ──
var _win_mgr: Node
var _bindings: Dictionary = {}  # action_id -> combo_string
var _enabled: Dictionary = {}   # action_id -> bool
var _active: bool = false
# action_id -> signal_name 回调映射
var _callbacks: Dictionary = {
	"quick_memo": "show_memo_popup",
}

func setup(main_node: Node) -> void:
	_win_mgr = main_node.win_manager
	if not _win_mgr or not _win_mgr.has_method("RegisterGlobalHotKey"):
		print("[HotKey] C# 桥接不可用, 全局热键功能禁用")
		return
	_active = true
	# 加载持久化绑定, 注册热键
	for action in HOTKEY_DEFS:
		var def = HOTKEY_DEFS[action]
		var saved = SettingsManager.get_hotkey(action, def["default"])
		var enabled = SettingsManager.get_hotkey_enabled(action, true)
		_bindings[action] = saved
		_enabled[action] = enabled
		if enabled:
			_register_combo(action, saved)
	print("[HotKey] 全局热键管理器就绪, %d 个绑定" % _bindings.size())

func _process(_delta: float) -> void:
	if not _active:
		return
	# 轮询 WM_HOTKEY 消息
	var pressed_id: int = _win_mgr.call("PollHotKey")
	if pressed_id < 0:
		return
	# 查找触发的 action
	for action in HOTKEY_DEFS:
		if HOTKEY_DEFS[action]["id"] == pressed_id:
			_dispatch(action)
			return

func _dispatch(action: String) -> void:
	if action in _callbacks:
		var sig_name = _callbacks[action]
		if EventBus.has_signal(sig_name):
			EventBus.emit_signal(sig_name)

# ═══════════════════════════════════════════════
#  注册 / 注销
# ═══════════════════════════════════════════════

func _register_combo(action: String, combo: String) -> bool:
	if not _active or combo == "":
		return false
	var parsed = parse_combo(combo)
	if parsed.is_empty():
		return false
	var def = HOTKEY_DEFS.get(action, {})
	var hk_id: int = def.get("id", 0)
	return _win_mgr.call("RegisterGlobalHotKey", hk_id, parsed.mods, parsed.vk)

func unregister(action: String) -> void:
	if not _active:
		return
	var def = HOTKEY_DEFS.get(action, {})
	if def.is_empty():
		return
	_win_mgr.call("UnregisterGlobalHotKey", def["id"])

## 更换绑定 (持久化 + 重注册)
func rebind(action: String, combo: String) -> bool:
	unregister(action)
	_bindings[action] = combo
	SettingsManager.set_hotkey(action, combo)
	return _register_combo(action, combo)

## 获取当前绑定
func get_binding(action: String) -> String:
	return _bindings.get(action, "")

## 获取启用状态
func is_enabled(action: String) -> bool:
	return _enabled.get(action, true)

## 设置启用/禁用 (持久化 + 注册/注销)
func set_enabled(action: String, enabled: bool) -> void:
	_enabled[action] = enabled
	SettingsManager.set_hotkey_enabled(action, enabled)
	if enabled:
		_register_combo(action, _bindings.get(action, ""))
	else:
		unregister(action)

# ═══════════════════════════════════════════════
#  冲突检测
# ═══════════════════════════════════════════════

## 检测结果: { "available": bool, "reason": String }
## reason: "" = 可用, "internal:xxx" = 内部冲突, "system" = 系统白名单, "occupied" = 被其他程序占用
func check_conflict(combo: String, exclude_action: String = "") -> Dictionary:
	combo = combo.to_lower().strip_edges()
	if combo == "":
		return {"available": false, "reason": "empty"}

	# Layer 1: 内部冲突
	for action in _bindings:
		if action == exclude_action:
			continue
		if _bindings[action].to_lower() == combo:
			return {"available": false, "reason": "internal:" + action}

	# Layer 2: 系统白名单
	if combo in SYSTEM_COMBOS:
		return {"available": false, "reason": "system"}

	# Layer 3: RegisterHotKey 探测
	if _active:
		var parsed = parse_combo(combo)
		if not parsed.is_empty():
			var ok: bool = _win_mgr.call("TestHotKeyAvailable", parsed.mods, parsed.vk)
			if not ok:
				return {"available": false, "reason": "occupied"}

	return {"available": true, "reason": ""}

# ═══════════════════════════════════════════════
#  组合键字符串解析
# ═══════════════════════════════════════════════

## "ctrl+shift+n" -> { mods: int, vk: int }
static func parse_combo(combo: String) -> Dictionary:
	combo = combo.to_lower().strip_edges()
	if combo == "":
		return {}
	var parts = combo.split("+")
	var mods: int = 0
	var key_part: String = ""
	for p in parts:
		p = p.strip_edges()
		match p:
			"ctrl", "control":
				mods |= MOD_CTRL
			"alt":
				mods |= MOD_ALT
			"shift":
				mods |= MOD_SHIFT
			"win", "super", "meta":
				mods |= MOD_WIN
			_:
				key_part = p
	if key_part == "":
		return {}
	var vk = _key_to_vk(key_part)
	if vk < 0:
		return {}
	return {"mods": mods, "vk": vk}

## 键名 -> Win32 VK 码
static func _key_to_vk(key: String) -> int:
	key = key.to_upper()
	# 单字母 A-Z
	if key.length() == 1:
		var code = key.unicode_at(0)
		if code >= 65 and code <= 90:  # A-Z
			return code
		if code >= 48 and code <= 57:  # 0-9
			return code
	# 功能键 F1-F24
	if key.begins_with("F") and key.length() >= 2:
		var num = key.substr(1).to_int()
		if num >= 1 and num <= 24:
			return 0x70 + num - 1  # VK_F1 = 0x70
	# 特殊键
	match key:
		"SPACE": return 0x20
		"ENTER", "RETURN": return 0x0D
		"TAB": return 0x09
		"ESCAPE", "ESC": return 0x1B
		"BACKSPACE", "BACK": return 0x08
		"DELETE", "DEL": return 0x2E
		"INSERT", "INS": return 0x2D
		"HOME": return 0x24
		"END": return 0x23
		"PAGEUP", "PGUP": return 0x21
		"PAGEDOWN", "PGDN": return 0x22
		"UP": return 0x26
		"DOWN": return 0x28
		"LEFT": return 0x25
		"RIGHT": return 0x27
		"NUMPAD0": return 0x60
		"NUMPAD1": return 0x61
		"NUMPAD2": return 0x62
		"NUMPAD3": return 0x63
		"NUMPAD4": return 0x64
		"NUMPAD5": return 0x65
		"NUMPAD6": return 0x66
		"NUMPAD7": return 0x67
		"NUMPAD8": return 0x68
		"NUMPAD9": return 0x69
		";", "SEMICOLON": return 0xBA
		"=", "EQUAL": return 0xBB
		",", "COMMA": return 0xBC
		"-", "MINUS": return 0xBD
		".", "PERIOD": return 0xBE
		"/", "SLASH": return 0xBF
		"`", "GRAVE": return 0xC0
		"[", "BRACKETLEFT": return 0xDB
		"\\", "BACKSLASH": return 0xDC
		"]", "BRACKETRIGHT": return 0xDD
		"'", "QUOTE": return 0xDE
	return -1

## VK 码 -> 可读键名
static func vk_to_name(vk: int) -> String:
	if vk >= 65 and vk <= 90:
		return char(vk)
	if vk >= 48 and vk <= 57:
		return str(vk - 48)
	if vk >= 0x70 and vk <= 0x87:
		return "F%d" % (vk - 0x70 + 1)
	match vk:
		0x20: return "Space"
		0x0D: return "Enter"
		0x09: return "Tab"
		0x1B: return "Esc"
		0x08: return "Backspace"
		0x2E: return "Delete"
		0x2D: return "Insert"
		0x24: return "Home"
		0x23: return "End"
		0x21: return "PageUp"
		0x22: return "PageDown"
		0x26: return "Up"
		0x28: return "Down"
		0x25: return "Left"
		0x27: return "Right"
	if vk >= 0x60 and vk <= 0x69:
		return "Num%d" % (vk - 0x60)
	return "0x%02X" % vk

## 组合键字符串格式化 (显示用)
static func format_combo(combo: String) -> String:
	if combo == "":
		return "未绑定"
	var parts = combo.to_lower().split("+")
	var result: PackedStringArray = []
	for p in parts:
		p = p.strip_edges()
		match p:
			"ctrl", "control": result.append("Ctrl")
			"alt": result.append("Alt")
			"shift": result.append("Shift")
			"win", "super", "meta": result.append("Win")
			_: result.append(p.to_upper() if p.length() == 1 else p.capitalize())
	return "+".join(result)

## 从 Godot InputEventKey 构建组合键字符串
static func event_to_combo(event: InputEventKey) -> String:
	var parts: PackedStringArray = []
	if event.ctrl_pressed:
		parts.append("ctrl")
	if event.alt_pressed:
		parts.append("alt")
	if event.shift_pressed:
		parts.append("shift")
	if event.meta_pressed:
		parts.append("win")
	# 提取主键 (排除单独的修饰键)
	var kc = event.keycode
	match kc:
		KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META:
			return ""  # 只按了修饰键, 忽略
	var vk = _godot_key_to_vk(kc)
	if vk < 0:
		return ""
	parts.append(_vk_to_combo_part(vk))
	return "+".join(parts)

## Godot Key -> VK
static func _godot_key_to_vk(kc: int) -> int:
	# A-Z
	if kc >= KEY_A and kc <= KEY_Z:
		return 65 + (kc - KEY_A)
	# 0-9
	if kc >= KEY_0 and kc <= KEY_9:
		return 48 + (kc - KEY_0)
	# F1-F12
	if kc >= KEY_F1 and kc <= KEY_F12:
		return 0x70 + (kc - KEY_F1)
	match kc:
		KEY_SPACE: return 0x20
		KEY_ENTER: return 0x0D
		KEY_TAB: return 0x09
		KEY_ESCAPE: return 0x1B
		KEY_BACKSPACE: return 0x08
		KEY_DELETE: return 0x2E
		KEY_INSERT: return 0x2D
		KEY_HOME: return 0x24
		KEY_END: return 0x23
		KEY_PAGEUP: return 0x21
		KEY_PAGEDOWN: return 0x22
		KEY_UP: return 0x26
		KEY_DOWN: return 0x28
		KEY_LEFT: return 0x25
		KEY_RIGHT: return 0x27
	return -1

static func _vk_to_combo_part(vk: int) -> String:
	if vk >= 65 and vk <= 90:
		return char(vk).to_lower()
	if vk >= 48 and vk <= 57:
		return str(vk - 48)
	return vk_to_name(vk).to_lower()

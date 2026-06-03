# update_checker.gd — 版本更新检测 (启动后单次检查)
# 职责: 请求 GitHub Releases API → 比对版本号 → 气泡通知用户
extends Node

## 当前版本号 (发版时同步修改此处 + installer.iss)
const CURRENT_VERSION := "2.2"
const COMMIT_COUNT := 369  ## 发版时由 release.ps1 自动更新

## GitHub 仓库信息
const REPO_OWNER := "NightMin2002"
const REPO_NAME := "GodotDesktopPet"
const API_URL := "https://api.github.com/repos/" + REPO_OWNER + "/" + REPO_NAME + "/releases/latest"
const RELEASE_PAGE := "https://github.com/" + REPO_OWNER + "/" + REPO_NAME + "/releases/latest"

var _http: HTTPRequest
var _checked := false

func _ready() -> void:
	# 延迟 15 秒再检查，让启动动画和核心系统先跑起来
	var timer = get_tree().create_timer(15.0)
	timer.timeout.connect(_start_check)

func _start_check() -> void:
	if _checked:
		return
	_checked = true
	
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_response)
	
	# GitHub API 要求 User-Agent
	var headers = ["User-Agent: GodotDesktopPet/%s" % CURRENT_VERSION, "Accept: application/vnd.github.v3+json"]
	var err = _http.request(API_URL, headers)
	if err != OK:
		print("[UpdateChecker] 请求失败: ", err)
		_cleanup()

func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[UpdateChecker] 检查更新失败 (HTTP %d, result %d)" % [code, result])
		_cleanup()
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json or not json is Dictionary:
		print("[UpdateChecker] 解析 Release 数据失败")
		_cleanup()
		return
	
	var remote_tag: String = json.get("tag_name", "")
	var remote_ver := _normalize_version(remote_tag)
	var local_ver := _normalize_version(CURRENT_VERSION)
	
	print("[UpdateChecker] 本地版本: %s, 远程版本: %s" % [CURRENT_VERSION, remote_tag])
	
	if _is_newer(remote_ver, local_ver):
		var release_name: String = json.get("name", remote_tag)
		_notify_update(remote_tag, release_name)
	else:
		print("[UpdateChecker] 当前已是最新版本")
	
	_cleanup()

## 版本号标准化: "v1.2.3" → [1, 2, 3]
func _normalize_version(ver: String) -> Array[int]:
	var clean = ver.strip_edges().to_lower()
	if clean.begins_with("v"):
		clean = clean.substr(1)
	var parts = clean.split(".")
	var result: Array[int] = []
	for p in parts:
		result.append(int(p))
	# 补齐到至少 3 段
	while result.size() < 3:
		result.append(0)
	return result

## 比较版本号: remote > local?
func _is_newer(remote: Array[int], local: Array[int]) -> bool:
	var len_max = max(remote.size(), local.size())
	for i in range(len_max):
		var r: int = remote[i] if i < remote.size() else 0
		var l: int = local[i] if i < local.size() else 0
		if r > l:
			return true
		if r < l:
			return false
	return false

## 通过气泡通知用户
func _notify_update(tag: String, name: String) -> void:
	var msg := "检测到新版本 %s 可用。" % tag
	# 延迟一帧确保气泡系统就绪
	await get_tree().process_frame
	EventBus.show_reminder_bubble.emit(msg)
	
	# 记录用于"戳宠物"时告知下载地址
	var pet = _find_pet()
	if pet and "poke_system" in pet:
		pet.poke_system.pending_reminders.append({
			"time": "", 
			"msg": "新版本 %s 已发布。访问 GitHub Release 页面下载更新。" % tag
		})
	
	print("[UpdateChecker] 新版本通知已发送: %s (%s)" % [tag, name])

func _find_pet() -> Node:
	var main = get_tree().root.get_node_or_null("Main")
	if main and "pet_instance" in main:
		return main.pet_instance
	return null

func _cleanup() -> void:
	if is_instance_valid(_http):
		_http.queue_free()
		_http = null

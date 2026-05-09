# game_manager.gd — 小游戏生命周期管理器
# 职责: 扫描/加载本地游戏、SubViewport 包装、管理游戏启动/清理
# 由 main.gd 实例化并挂载
extends CanvasLayer

var _current_game: BaseGame = null
var _installed_games: Array[Dictionary] = []  # [{id, name, desc, script_path}]
var _pet_ref: Node2D = null

# ── SubViewport 包装层 ──
var _game_container: SubViewportContainer = null
var _game_viewport: SubViewport = null

func _ready() -> void:
	layer = 110
	_scan_local_games()
	EventBus.close_game_requested.connect(close_game)

# ══════════════════════════════════════════════
# 游戏扫描 (本地已安装)
# ══════════════════════════════════════════════

func _scan_local_games() -> void:
	_installed_games.clear()
	# 扫描 res://games/ 下的子目录
	var base_dir = "res://games"
	var dir = DirAccess.open(base_dir)
	if not dir:
		return
	dir.list_dir_begin()
	var folder = dir.get_next()
	while folder != "":
		if dir.current_is_dir() and folder != "." and folder != "..":
			var meta_path = base_dir + "/" + folder + "/meta.json"
			if ResourceLoader.exists(meta_path) or FileAccess.file_exists(meta_path):
				var meta = _load_meta(meta_path)
				if meta.size() > 0:
					_installed_games.append(meta)
		folder = dir.get_next()
	dir.list_dir_end()

	# 也扫描 user://games/ (下载的 PCK 加载后)
	var user_dir = "user://games"
	dir = DirAccess.open(user_dir)
	if dir:
		dir.list_dir_begin()
		folder = dir.get_next()
		while folder != "":
			if dir.current_is_dir() and folder != "." and folder != "..":
				var meta_path = user_dir + "/" + folder + "/meta.json"
				if FileAccess.file_exists(meta_path):
					var meta = _load_meta(meta_path)
					if meta.size() > 0 and not _has_game(meta.get("id", "")):
						_installed_games.append(meta)
			folder = dir.get_next()
		dir.list_dir_end()

func _load_meta(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return {}
	var data = json.data
	if data is Dictionary and data.has("id") and data.has("script"):
		return data
	return {}

func _has_game(id: String) -> bool:
	for g in _installed_games:
		if g.get("id", "") == id:
			return true
	return false

# ══════════════════════════════════════════════
# 游戏列表 (供 UI 查询)
# ══════════════════════════════════════════════

func get_installed_games() -> Array[Dictionary]:
	return _installed_games

func is_game_running() -> bool:
	return _current_game != null

## 获取当前游戏的 SubViewport (供 pet.gd 全息屏纹理)
func get_game_viewport() -> SubViewport:
	return _game_viewport

# ══════════════════════════════════════════════
# SubViewport 包装层
# ══════════════════════════════════════════════

func _create_viewport_wrapper() -> void:
	_game_container = SubViewportContainer.new()
	_game_container.stretch = false  # 不缩放，Container.size 跟随 SubViewport.size
	_game_container.mouse_filter = Control.MOUSE_FILTER_STOP

	_game_viewport = SubViewport.new()
	_game_viewport.transparent_bg = true
	_game_viewport.gui_disable_input = false
	_game_viewport.handle_input_locally = true
	_game_viewport.size = Vector2i(280, 400)  # 初始大小，后续由面板驱动

	_game_container.add_child(_game_viewport)
	add_child(_game_container)

func _destroy_viewport_wrapper() -> void:
	if is_instance_valid(_game_container):
		_game_container.queue_free()
	_game_container = null
	_game_viewport = null

# ══════════════════════════════════════════════
# 启动 / 结束游戏
# ══════════════════════════════════════════════

func launch_game(game_id: String, pet: Node2D) -> bool:
	if _current_game:
		return false  # 已有游戏在运行
	_pet_ref = pet
	var meta: Dictionary = {}
	for g in _installed_games:
		if g.get("id", "") == game_id:
			meta = g
			break
	if meta.is_empty():
		return false
	var script_path: String = meta.get("script", "")
	if not ResourceLoader.exists(script_path):
		return false
	var script = load(script_path)
	if not script:
		return false
	var game = script.new()
	if not game is BaseGame:
		return false
	_current_game = game

	# 创建 SubViewport 包装层
	_create_viewport_wrapper()

	# 注入运行时引用
	_current_game.game_viewport = _game_viewport
	_current_game.game_container = _game_container
	_current_game.screen_size = get_viewport().get_visible_rect().size
	_current_game._pet = pet

	_current_game.game_finished.connect(_on_game_finished)
	_current_game.start()
	EventBus.context_menu_toggled.emit(true)  # 阻止穿透
	EventBus.pet_gaming_changed.emit(true, _current_game)
	return true

func _on_game_finished(_result: BaseGame.Result) -> void:
	# 不自动清理面板，让用户选择 "再来一局" 或手动关闭
	pass

func _cleanup_current_game() -> void:
	if _current_game:
		_current_game.cleanup()
		_current_game = null
	_destroy_viewport_wrapper()
	EventBus.pet_gaming_changed.emit(false, null)
	EventBus.context_menu_toggled.emit(false)  # 恢复穿透

func close_game() -> void:
	_cleanup_current_game()

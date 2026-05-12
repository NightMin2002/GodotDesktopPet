# holo_compositor.gd — 全息合成器 (RefCounted)
# 管理全息合成视口: 将游戏面板纹理 + 悬浮组件克隆体合成为完整画面
# 供 PetGaming/PetHoloScreen 通过 get_texture() 获取合成纹理
# 从 base_game.gd 提取
class_name HoloCompositor extends RefCounted

# ── 全息合成视口 ──
var _viewport: SubViewport = null
var _game_rect: TextureRect = null
var _title: Control = null
var _connector: Control = null
var _side: Control = null
var _restart: Control = null
var _speech: Control = null

# ── 布局常量 (与 BaseGame 保持一致) ──
const _RESTART_RESERVE := Vector2(100, 32)
const _RESTART_GAP := 8.0

## 创建全息合成视口 (独立 SubViewport, 不显示在屏幕上)
## chrome_refs: 悬浮组件原件引用字典
##   {title, connector, side, restart, speech, game_viewport, parent}
func setup(chrome_refs: Dictionary) -> void:
	var game_viewport: SubViewport = chrome_refs.get("game_viewport")
	var parent: Node = chrome_refs.get("parent")
	if not game_viewport or not parent:
		return

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# 游戏面板内容 (通过 ViewportTexture 实时镜像)
	_game_rect = TextureRect.new()
	_game_rect.texture = game_viewport.get_texture()
	_game_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_game_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_game_rect)

	# 克隆悬浮组件 (纯视觉副本, 无交互)
	# 注意: 克隆时入场动画正在执行, 原件可能处于透明/缩小状态
	# 必须强制重置克隆体的 modulate 和 scale
	var title_bubble: Control = chrome_refs.get("title")
	if is_instance_valid(title_bubble):
		_title = title_bubble.duplicate(0)
		_disable_input(_title)
		_title.modulate = Color.WHITE
		_title.scale = Vector2.ONE
		_viewport.add_child(_title)

	var connector: Control = chrome_refs.get("connector")
	if is_instance_valid(connector):
		_connector = connector.duplicate(0)
		_connector.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_connector.modulate = Color.WHITE
		_viewport.add_child(_connector)

	var side_container: Control = chrome_refs.get("side")
	if is_instance_valid(side_container):
		_side = side_container.duplicate(0)
		_disable_input(_side)
		_side.modulate = Color.WHITE
		_side.scale = Vector2.ONE
		# 子按钮也需要重置 (入场动画逐个设置了子按钮的透明度和缩放)
		for child in _side.get_children():
			if child is Control:
				child.modulate = Color.WHITE
				child.scale = Vector2.ONE
		_viewport.add_child(_side)

	var restart_bubble: Control = chrome_refs.get("restart")
	if is_instance_valid(restart_bubble):
		_restart = restart_bubble.duplicate(0)
		_disable_input(_restart)
		_restart.modulate = Color.WHITE
		_restart.scale = Vector2.ONE
		_restart.visible = restart_bubble.visible
		_viewport.add_child(_restart)

	var speech_bubble: Control = chrome_refs.get("speech")
	if is_instance_valid(speech_bubble):
		_speech = speech_bubble.duplicate(0)
		_disable_input(_speech)
		_speech.modulate = Color.WHITE
		_speech.scale = Vector2.ONE
		# duplicate(0) 不复制 meta，手动关联子节点引用
		# wrapper 的子节点顺序: [0]=arrow, [1]=bubble
		if _speech.get_child_count() >= 2:
			_speech.set_meta("_arrow", _speech.get_child(0))
			_speech.set_meta("_bubble", _speech.get_child(1))
		_viewport.add_child(_speech)

	parent.add_child(_viewport)
	update_layout(chrome_refs)

## 递归禁用克隆体的鼠标交互
func _disable_input(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_disable_input(child)

## 更新全息视口布局 (重算包围盒 + 定位克隆体)
## 使用理想位置 (基于面板坐标系, 不受屏幕边缘 clamp 影响)
## chrome_refs: 同 setup(), 需要额外字段:
##   {game_container, chrome_side, restart_bubble_ref (原件, 用于读取 visible/size)}
func update_layout(chrome_refs: Dictionary) -> void:
	var game_container: SubViewportContainer = chrome_refs.get("game_container")
	if not is_instance_valid(_viewport) or not is_instance_valid(game_container):
		return

	var gc_pos = game_container.position
	var gc_size = game_container.size
	var gap := 8.0
	var chrome_side: int = chrome_refs.get("chrome_side", 1)

	# ── 计算理想位置 (以面板为基准, 不 clamp 到屏幕) ──
	var title_ref: Control = chrome_refs.get("title")
	var title_size = title_ref.size if is_instance_valid(title_ref) else Vector2(100, 30)
	var ideal_title = Vector2(
		gc_pos.x + (gc_size.x - title_size.x) / 2.0,
		gc_pos.y - title_size.y - gap
	)

	var conn_top = ideal_title.y + title_size.y
	var conn_h = maxf(gc_pos.y - conn_top, 1.0)
	var ideal_conn = Vector2(gc_pos.x + gc_size.x / 2.0, conn_top)
	var ideal_conn_size = Vector2(1, conn_h)

	var side_ref: Control = chrome_refs.get("side")
	var side_size = side_ref.size if is_instance_valid(side_ref) else Vector2(40, 80)
	var ideal_side: Vector2
	if chrome_side > 0:
		ideal_side = Vector2(gc_pos.x + gc_size.x + gap, gc_pos.y)
	else:
		ideal_side = Vector2(gc_pos.x - side_size.x - gap, gc_pos.y)

	var rb_pos = Vector2(
		gc_pos.x + (gc_size.x - _RESTART_RESERVE.x) / 2.0,
		gc_pos.y + gc_size.y + _RESTART_GAP
	)

	# 发言气泡理想位置
	var ideal_bubble_pos := Vector2.ZERO
	var ideal_bubble_size := Vector2.ZERO
	var ideal_arrow_pos := Vector2.ZERO
	var ideal_arrow_size := Vector2(8, 12)
	var has_speech := false
	var speech_ref: Control = chrome_refs.get("speech")
	if is_instance_valid(speech_ref):
		var bubble: PanelContainer = speech_ref.get_meta("_bubble") as PanelContainer
		if bubble:
			has_speech = true
			ideal_bubble_size = bubble.size
			var speech_side = -chrome_side
			var arrow_w := 8.0
			if speech_side > 0:
				ideal_bubble_pos = Vector2(gc_pos.x + gc_size.x + gap + arrow_w, gc_pos.y + 8.0)
				ideal_arrow_pos = Vector2(ideal_bubble_pos.x - arrow_w, ideal_bubble_pos.y + ideal_bubble_size.y / 2.0 - 6.0)
			else:
				ideal_bubble_pos = Vector2(gc_pos.x - ideal_bubble_size.x - gap - arrow_w, gc_pos.y + 8.0)
				ideal_arrow_pos = Vector2(ideal_bubble_pos.x + ideal_bubble_size.x, ideal_bubble_pos.y + ideal_bubble_size.y / 2.0 - 6.0)

	# ── 包围盒 (理想位置) ──
	var bounds = Rect2(gc_pos, gc_size)
	bounds = bounds.merge(Rect2(ideal_title, title_size))
	if conn_h > 1:
		bounds = bounds.merge(Rect2(ideal_conn, ideal_conn_size))
	bounds = bounds.merge(Rect2(ideal_side, side_size))
	bounds = bounds.merge(Rect2(rb_pos, _RESTART_RESERVE))
	var restart_ref: Control = chrome_refs.get("restart")
	if is_instance_valid(restart_ref) and restart_ref.visible:
		var rb_ideal = Vector2(
			gc_pos.x + (gc_size.x - restart_ref.size.x) / 2.0,
			gc_pos.y + gc_size.y + gap
		)
		bounds = bounds.merge(Rect2(rb_ideal, restart_ref.size))
	if has_speech:
		bounds = bounds.merge(Rect2(ideal_bubble_pos, ideal_bubble_size))
	bounds = bounds.grow(2)

	# 更新视口大小
	_viewport.size = Vector2i(int(bounds.size.x), int(bounds.size.y))
	var offset = bounds.position

	# 定位游戏面板纹理
	if is_instance_valid(_game_rect):
		_game_rect.position = gc_pos - offset
		_game_rect.size = gc_size

	# 定位克隆体 (用理想位置)
	if is_instance_valid(_title):
		_title.position = ideal_title - offset
		_title.size = title_size

	if is_instance_valid(_connector):
		_connector.position = ideal_conn - offset
		_connector.size = ideal_conn_size
		_connector.visible = conn_h > 1

	if is_instance_valid(_side):
		_side.position = ideal_side - offset

	if is_instance_valid(_restart) and is_instance_valid(restart_ref):
		var rb_ideal = Vector2(
			gc_pos.x + (gc_size.x - restart_ref.size.x) / 2.0,
			gc_pos.y + gc_size.y + gap
		)
		_restart.position = rb_ideal - offset
		_restart.size = restart_ref.size
		_restart.visible = restart_ref.visible

	if is_instance_valid(_speech) and has_speech:
		var holo_bubble: PanelContainer = _speech.get_meta("_bubble") as PanelContainer
		var holo_arrow: Control = _speech.get_meta("_arrow") as Control
		if holo_bubble:
			holo_bubble.position = ideal_bubble_pos - offset
			holo_bubble.size = ideal_bubble_size
		if holo_arrow:
			holo_arrow.position = ideal_arrow_pos - offset
			holo_arrow.size = ideal_arrow_size
			holo_arrow.queue_redraw()

## 同步重开按钮可见性
func sync_restart_visible(visible: bool) -> void:
	if is_instance_valid(_restart):
		_restart.visible = visible

## 同步发言文字到克隆体
func sync_speech_text(text: String) -> void:
	if is_instance_valid(_speech):
		var holo_bubble = _speech.get_meta("_bubble") as PanelContainer
		if holo_bubble and holo_bubble.get_child_count() > 0:
			var holo_label = holo_bubble.get_child(0) as Label
			if holo_label:
				holo_label.text = text

## 获取全息合成纹理
func get_texture() -> Texture2D:
	if is_instance_valid(_viewport):
		return _viewport.get_texture()
	return null

## 清理全部资源
func cleanup() -> void:
	if is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	_game_rect = null
	_title = null
	_connector = null
	_side = null
	_restart = null
	_speech = null

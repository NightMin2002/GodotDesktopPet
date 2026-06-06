# floating_panel_helper.gd — 低层级浮窗交互基础设施
class_name FloatingPanelHelper
extends RefCounted

var _host: CanvasLayer
var _panel_id: String = ""
var _owner: String = ""
var _panel_getter: Callable
var _open_getter: Callable
var _rect_getter: Callable
var _main_getter: Callable

func setup(
	host_ref: CanvasLayer,
	panel_id: String,
	owner: String,
	panel_getter: Callable,
	open_getter: Callable,
	rect_getter: Callable,
	main_getter: Callable = Callable()
) -> FloatingPanelHelper:
	_host = host_ref
	_panel_id = panel_id
	_owner = owner
	_panel_getter = panel_getter
	_open_getter = open_getter
	_rect_getter = rect_getter
	_main_getter = main_getter
	return self

func sync() -> void:
	if not is_open():
		return
	var rect := get_panel_rect()
	if rect.size == Vector2.ZERO:
		return
	var pet := get_pet()
	if pet:
		OverlayRegionHelper.update_rect(pet, _panel_id, rect, _owner)
	EventBus._active_panel_rects[_panel_id] = { "rect": rect, "layer": _host.layer }

func cleanup() -> void:
	EventBus._active_panel_rects.erase(_panel_id)
	var pet := get_pet()
	if pet:
		OverlayRegionHelper.clear(pet, _panel_id, _owner)

func handle_input(event: InputEvent) -> bool:
	if not is_open():
		return false
	var rect := get_panel_rect()
	if rect.size == Vector2.ZERO:
		return false

	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var mouse_pos: Vector2 = event.position
		if rect.has_point(mouse_pos):
			var pet_hit := find_pet_at_mouse()
			if pet_hit:
				pet_hit._unhandled_input(event)
				_host.get_viewport().set_input_as_handled()
				return true

	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = event.position
		if rect.has_point(pos):
			if _is_covered_by_higher_panel(pos):
				return true
			request_focus_if_needed()

	return false

func request_focus() -> void:
	EventBus.panel_focus_requested.emit(_panel_id)

func request_focus_if_needed() -> void:
	if _host.layer != -1:
		request_focus()

func apply_focus(focused_panel_id: String) -> void:
	if not is_open():
		return
	_host.layer = -1 if focused_panel_id == _panel_id else -2

func is_open() -> bool:
	if _open_getter.is_valid():
		return bool(_open_getter.call())
	return false

func get_panel_rect() -> Rect2:
	if _rect_getter.is_valid():
		var rect = _rect_getter.call()
		if rect is Rect2:
			return rect
	var panel := get_panel()
	if panel:
		return Rect2(panel.position, panel.size)
	return Rect2()

func get_panel() -> Control:
	if _panel_getter.is_valid():
		var panel = _panel_getter.call()
		if panel is Control:
			return panel
	return null

func get_pet() -> Node:
	var main_node := get_main_node()
	if main_node and "pet_instance" in main_node and is_instance_valid(main_node.pet_instance):
		return main_node.pet_instance
	return null

func find_pet_at_mouse() -> Node:
	var main_node := get_main_node()
	if not main_node or not "pet_instances" in main_node:
		return null
	for p in main_node.pet_instances:
		if is_instance_valid(p) and p.is_mouse_on_pet():
			return p
	return null

func get_main_node() -> Node:
	if _main_getter.is_valid():
		var main_node = _main_getter.call()
		if main_node is Node:
			return main_node
	if _host and is_instance_valid(_host):
		return _host.get_tree().root.get_node_or_null("Main")
	return null

func _is_covered_by_higher_panel(pos: Vector2) -> bool:
	if _host.layer >= -1:
		return false
	for pid in EventBus._active_panel_rects:
		if pid == _panel_id:
			continue
		var info = EventBus._active_panel_rects[pid]
		if info.layer > _host.layer and info.rect.has_point(pos):
			return true
	return false

# overlay_region_helper.gd — DWM 覆盖层命中区域工具
class_name OverlayRegionHelper
extends RefCounted

const DEBUG_LOG := false

static func update_rect(pet: Node, key: String, rect: Rect2, owner: String = "") -> void:
	update_rects(pet, key, [rect], owner)

static func update_rects(pet: Node, key: String, rects: Array, owner: String = "") -> void:
	if not is_instance_valid(pet):
		_log(owner, key, "skip: pet invalid")
		return
	if pet.has_method("set_overlay_rects"):
		pet.set_overlay_rects(key, rects)
	elif pet.has_method("set_overlay_rect") and not rects.is_empty():
		var first = rects[0]
		if first is Rect2:
			pet.set_overlay_rect(key, first)
	_log(owner, key, "update %d rects" % rects.size())

static func clear(pet: Node, key: String, owner: String = "") -> void:
	if not is_instance_valid(pet):
		_log(owner, key, "skip clear: pet invalid")
		return
	if pet.has_method("remove_overlay_rect"):
		pet.remove_overlay_rect(key)
	_log(owner, key, "clear")

static func _log(owner: String, key: String, message: String) -> void:
	if not DEBUG_LOG:
		return
	var prefix := owner if owner != "" else "overlay"
	print("[%s] %s: %s" % [prefix, key, message])

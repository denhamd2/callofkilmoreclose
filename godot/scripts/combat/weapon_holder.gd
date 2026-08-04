## Shows a Styloo weapon GLB on the right-hand bone.
class_name WeaponHolder
extends Node3D

const HAND_BONE_CANDIDATES: Array[StringName] = [
	&"DEF-hand.R",
	&"mixamorig:RightHand",
	&"RightHand",
	&"hand.R",
	&"Hand_R",
]

var _weapon_id := WeaponCatalog.UNARMED
var _model_root: Node3D = null
var _rigged := false


func setup_on_body(body: Node3D) -> void:
	if _rigged:
		return
	var sk := body.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return
	var bone_name := _find_hand_bone(sk)
	if bone_name.is_empty():
		return
	var attach := BoneAttachment3D.new()
	attach.name = "WeaponBoneAttach"
	attach.bone_name = bone_name
	sk.add_child(attach)
	reparent(attach)
	_rigged = true


func set_weapon(id: StringName) -> void:
	if _weapon_id == id:
		return
	_weapon_id = id
	_clear()
	var entry := WeaponCatalog.get_entry(id)
	var path := str(entry.get("model", ""))
	if path.is_empty():
		return
	var scene := load(path) as PackedScene
	if scene == null:
		var res := load(path)
		if res is PackedScene:
			scene = res
	if scene == null:
		return
	_model_root = scene.instantiate() as Node3D
	if _model_root == null:
		return
	add_child(_model_root)
	_fit_model(entry)


func get_weapon_id() -> StringName:
	return _weapon_id


func _find_hand_bone(sk: Skeleton3D) -> StringName:
	for cand in HAND_BONE_CANDIDATES:
		if sk.find_bone(cand) >= 0:
			return cand
	for i in sk.get_bone_count():
		var n := String(sk.get_bone_name(i))
		var lower := n.to_lower()
		if "hand" in lower and (".r" in lower or "right" in lower or lower.ends_with("_r")):
			return StringName(n)
	return &""


func _fit_model(entry: Dictionary) -> void:
	if _model_root == null:
		return
	var target_len := float(entry.get("hold_length", 0.42))
	var user_scale := float(entry.get("scale", 1.0))
	var aabb := _mesh_aabb(_model_root)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var fit := 1.0
	if longest > 0.001:
		fit = target_len / longest
	_model_root.scale = Vector3.ONE * fit * user_scale
	_model_root.position = entry.get("offset", Vector3.ZERO) as Vector3
	_model_root.rotation_degrees = entry.get("rotation_deg", Vector3.ZERO) as Vector3


func _mesh_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var has := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		var local := mesh.transform * mesh.get_aabb()
		if not has:
			merged = local
			has = true
		else:
			merged = merged.merge(local)
	if not has:
		return AABB(Vector3.ZERO, Vector3(0.2, 0.2, 0.2))
	return merged


func _clear() -> void:
	if _model_root != null:
		_model_root.queue_free()
		_model_root = null

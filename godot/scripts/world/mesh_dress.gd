## Applies readable PBR colours to offline-generated glTF hero meshes.
##
## Generated glTFs carry vertex COLOR_0 but Godot does not use that as albedo
## unless explicitly enabled — without this pass they render flat white.

class_name MeshDress
extends RefCounted

const SKIN := Color(0.86, 0.72, 0.62)
const DENIM := Color(0.18, 0.22, 0.30)
const SHOE := Color(0.12, 0.12, 0.14)
const JACKET := Color(0.22, 0.28, 0.38)
const GLASS := Color(0.15, 0.20, 0.28)
const RUBBER := Color(0.08, 0.08, 0.09)
const TRIM := Color(0.12, 0.12, 0.13)
const BARK := Color(0.35, 0.22, 0.14)
const CANOPY := Color(0.22, 0.48, 0.24)


static func _mat(colour: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = false
	if rough > 0.82:
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


static func _part_name(node: Node) -> String:
	var n := node.name
	var cut := n.find("_")
	if cut > 0:
		n = n.substr(0, cut)
	return n


static func dress_mannequin(root: Node3D, main_colour: Color = JACKET) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var active: Material = mi.get_active_material(i)
			var name_hint := ""
			if active != null:
				name_hint = active.resource_name
			var colour := main_colour
			var rough := 0.55
			if "Joint" in name_hint:
				colour = main_colour.darkened(0.35)
				rough = 0.45
			mi.set_surface_override_material(i, _mat(colour, rough, 0.08))


static func dress_person(root: Node3D, jacket: Color = JACKET) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var part := _part_name(mi)
		var colour := jacket
		if part == "Head" or part.begins_with("Arm"):
			colour = SKIN
		elif part.begins_with("Leg"):
			colour = DENIM
		elif part.begins_with("Foot"):
			colour = SHOE
		mi.material_override = _mat(colour, 0.88)


static func _car_surface_kind(part: String) -> StringName:
	var p := part.to_lower()
	if "glass" in p or "window" in p or "bulb" in p:
		return &"glass"
	if "tyre" in p or "wheel" in p or "alloy" in p or "disc" in p or "brake" in p or "nut" in p:
		return &"rubber"
	if "bumper" in p or "mirror" in p or "trim" in p or "logo" in p or "handle" in p \
			or "indicator" in p or "casing" in p or "plate" in p or "lock" in p or "ariel" in p:
		return &"trim"
	return &"paint"


static func dress_car(root: Node3D, paint: Color = Color(0.78, 0.80, 0.84)) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var part := _part_name(mi)
		var kind := _car_surface_kind(part)
		if kind == &"glass":
			mi.material_override = _mat(GLASS, 0.10, 0.05)
		elif kind == &"rubber":
			mi.material_override = _mat(RUBBER, 0.94)
		elif kind == &"trim":
			mi.material_override = _mat(TRIM, 0.42, 0.25)
		else:
			mi.material_override = _mat(paint, 0.32, 0.18)


static func _plant_surface_kind(part: String) -> StringName:
	var p := part.to_lower()
	if "trunk" in p or "bark" in p or "stem" in p or p == "tree":
		return &"bark"
	if "leaf" in p or "leaves" in p or "canopy" in p or "branch" in p:
		return &"canopy"
	return &"canopy"


static func dress_tree(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var part := _part_name(mi)
		var kind := _plant_surface_kind(part)
		if kind == &"bark":
			mi.material_override = _mat(BARK, 0.96)
		else:
			mi.material_override = _mat(CANOPY, 0.90)


static func dress_bush(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var part := _part_name(mi)
		var kind := _plant_surface_kind(part)
		if kind == &"bark":
			mi.material_override = _mat(BARK, 0.94)
		else:
			mi.material_override = _mat(CANOPY, 0.88)

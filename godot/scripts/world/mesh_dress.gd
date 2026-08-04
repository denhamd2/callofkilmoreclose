## Applies readable PBR colours to the glTF hero meshes.
##
## These models ship with either no materials at all (`tree_*.glb`, `bush_a.glb`
## are single primitives carrying only POSITION and NORMAL) or two flat untextured
## ones (the Quaternius mannequin). Without this pass they render as default
## white. Note they do NOT carry vertex COLOR_0 — an earlier comment here claimed
## they did, which is wrong; there is no vertex colour to fall back on, which is
## why every surface has to be assigned a colour explicitly.

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


## Cache of materials by (colour, roughness, metallic).
##
## `dress_car()` assigns a material per MeshInstance3D, and the Golf glTF has 58
## meshes — so six cars on the street were allocating ~348 unique
## StandardMaterial3Ds for what is really four surface kinds in five paints. That
## defeats both the shared-material intent stated at the top of street_builder.gd
## and the renderer's ability to batch by material.
static var _cache: Dictionary = {}


static func _mat(colour: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%.3f_%.3f_%.3f_%.3f_%.3f_%.3f" % [
		colour.r, colour.g, colour.b, colour.a, rough, metal]
	var hit: Variant = _cache.get(key)
	if hit != null:
		return hit as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = false
	_cache[key] = m
	return m


static func _part_name(node: Node) -> String:
	var n := node.name
	var cut := n.find("_")
	if cut > 0:
		n = n.substr(0, cut)
	return n


## The mannequin is two separate primitives — M_Main (the limb segments) and
## M_Joints (the ball joints). Giving them different colours makes every joint
## read as a seam, which is the single worst thing about how the cast looks.
## One material across both surfaces so the body reads as one piece.
static func dress_mannequin(root: Node3D, main_colour: Color = JACKET) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var skin := _mat(main_colour, 0.55, 0.08)
		for i in mesh.get_surface_count():
			mi.set_surface_override_material(i, skin)


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


## Dark interior trim, for the procedurally generated steering wheel and seat in
## `car.gd` — the glTF ships no interior geometry at all.
static func cabin_trim() -> StandardMaterial3D:
	return _mat(Color(0.09, 0.09, 0.10), 0.55, 0.05)


## Windscreen and side glazing. Transparent, so the driver is visible in the cabin
## — it used to be an opaque dark panel (alpha 1.0), which meant David could not be
## seen inside the car no matter where he was seated.
##
## ALPHA_DEPTH_PRE_PASS, not plain alpha: the pre-pass writes depth first so the
## near and far glazing of the same car sort correctly against each other. Cached
## like every other material here, so all six cars share one instance.
static func _car_glass() -> StandardMaterial3D:
	var key := "car_glass"
	var hit: Variant = _cache.get(key)
	if hit != null:
		return hit as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.40, 0.47, 0.54, 0.30)
	m.roughness = 0.06
	m.metallic = 0.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	# Back-face culling stays ON. The bodyshell is closed, so drawing both faces of
	# every pane doubles the transparent-pass cost for nothing.
	_cache[key] = m
	return m


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


static func car_glass_bloodied() -> StandardMaterial3D:
	var key := "car_glass_bloodied"
	var hit: Variant = _cache.get(key)
	if hit != null:
		return hit as StandardMaterial3D
	var m := _car_glass().duplicate() as StandardMaterial3D
	m.albedo_color = Color(0.35, 0.12, 0.10, 0.42)
	m.roughness = 0.18
	_cache[key] = m
	return m


static func apply_car_damage(root: Node3D, paint: Color, health_frac: float) -> void:
	var darken := clampf(1.0 - (1.0 - health_frac) * 0.55, 0.35, 1.0)
	var damaged_paint := paint * darken
	var shattered := health_frac < 0.35
	var heavy := health_frac < 0.55
	var critical := health_frac < 0.25
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var part := _part_name(mi)
		var kind := _car_surface_kind(part)
		var pl := part.to_lower()
		if kind == &"glass":
			mi.visible = not shattered
			if not shattered:
				mi.material_override = car_glass_bloodied() if health_frac < 0.7 else _car_glass()
		elif kind == &"rubber":
			mi.material_override = _mat(RUBBER, 0.94)
		elif kind == &"trim":
			# Mirrors and indicators detach visually once the body is beat up.
			if critical and ("mirror" in pl or "indicator" in pl or "casing" in pl):
				mi.visible = false
			elif heavy and ("mirror" in pl or "plate" in pl):
				mi.material_override = _mat(TRIM.darkened(0.45), 0.55, 0.1)
			else:
				mi.material_override = _mat(TRIM, 0.42, 0.25)
		else:
			var dent := 0.32 + (1.0 - health_frac) * 0.28
			if heavy:
				dent += 0.08
			mi.material_override = _mat(damaged_paint, dent, 0.14 if critical else 0.18)


static func prop_mat(colour: Color, rough: float = 0.88) -> StandardMaterial3D:
	return _mat(colour, rough)


static func dress_car(root: Node3D, paint: Color = Color(0.78, 0.80, 0.84)) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var part := _part_name(mi)
		var kind := _car_surface_kind(part)
		if kind == &"glass":
			mi.material_override = _car_glass()
		elif kind == &"rubber":
			mi.material_override = _mat(RUBBER, 0.94)
		elif kind == &"trim":
			mi.material_override = _mat(TRIM, 0.42, 0.25)
		else:
			mi.material_override = _mat(paint, 0.32, 0.18)


## The `p == "tree"` test that used to be here is why one in five street trees
## rendered entirely brown: `tree_a.glb`'s single mesh node is named exactly
## "tree" while b–e are "tree.001".."tree.004", so only tree_a matched and got
## painted bark from trunk to crown. These models are one primitive each with no
## UVs and no materials, so a whole tree can only ever be one flat colour —
## canopy green is the right one, and a trunk needs actual trunk geometry.
static func _plant_surface_kind(part: String) -> StringName:
	var p := part.to_lower()
	if "trunk" in p or "bark" in p or "stem" in p:
		return &"bark"
	return &"canopy"


static func dress_tree(root: Node3D) -> void:
	var canopy_bottom := INF
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "GeneratedTrunk":
			continue
		var part := _part_name(mi)
		var kind := _plant_surface_kind(part)
		if kind == &"bark":
			mi.material_override = _mat(BARK, 0.96)
		else:
			mi.material_override = _mat(CANOPY, 0.90)
		var local_aabb: AABB = mi.transform * mi.get_aabb()
		canopy_bottom = minf(canopy_bottom, local_aabb.position.y)
	if root.get_node_or_null("GeneratedTrunk") == null:
		var trunk_h := 1.6 if canopy_bottom == INF else clampf(canopy_bottom, 1.0, 2.8)
		_add_tree_trunk(root, trunk_h)


static func _add_tree_trunk(root: Node3D, height: float) -> void:
	var trunk := MeshInstance3D.new()
	trunk.name = &"GeneratedTrunk"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.22
	cyl.height = height
	trunk.mesh = cyl
	trunk.position = Vector3(0.0, height * 0.5, 0.0)
	trunk.material_override = _mat(BARK, 0.96)
	root.add_child(trunk)
	root.move_child(trunk, 0)


static func dress_bush(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var part := _part_name(mi)
		var kind := _plant_surface_kind(part)
		if kind == &"bark":
			mi.material_override = _mat(BARK, 0.94)
		else:
			mi.material_override = _mat(CANOPY, 0.88)

## STREET BUILDER — generates the Kilmore Close slice at load time.
##
## The street is built in code rather than authored as a scene, for three
## reasons that all still hold in Godot:
##
##   1. The geometry IS the data. `KilmoreClose` holds measured spacings; a
##      hand-placed scene would let a house drift off the rhythm silently,
##      which is exactly how the prototype's row went out of alignment.
##      Generated rows cannot drift.
##   2. It keeps the repository free of binary scene blobs for what is, in the
##      end, twenty boxes on a grid.
##   3. It makes the whole street one place to change. Extending the slice to
##      the full 13 pairs a side is two constants in `KilmoreClose`.
##
## MOBILE BUDGET — this is the part that decides whether the target phone can
## run it at all. Everything repeated is drawn with MultiMeshInstance3D, which
## submits one draw call per *material* regardless of instance count. The whole
## street — 10 pairs, 20 dwellings, 60 windows, 20 garages, 20 porches — costs
## roughly a dozen draw calls rather than the ~400 that individual MeshInstances
## would. Collision is separate and free of draw cost: static box shapes only.
##
## The house archetype itself is stated once, in `_add_house()`, and applied to
## every dwelling. There is no second building type on Kilmore Close.

class_name StreetBuilder
extends Node3D

## Emitted once the street exists, so gameplay can position itself against it.
signal built

# Materials are shared instances — one per surface, reused across every
# MultiMesh. Fewer unique materials means fewer state changes, which matters
# more than shader complexity on a low-end GPU.
var _mat: Dictionary = {}

# Transform buckets, filled during generation and flushed into MultiMeshes.
var _batch: Dictionary = {}

var _collision: StaticBody3D


func _ready() -> void:
	_build_materials()
	_collision = StaticBody3D.new()
	_collision.name = "StreetCollision"
	add_child(_collision)

	_build_ground()
	for h in KilmoreClose.houses():
		_add_house(h)
	for p in KilmoreClose.pairs():
		_add_pair_shell(p)
	_flush_batches()
	built.emit()


# --------------------------------------------------------------- materials

func _flat(colour: Color, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	# Specular evaluation is wasted cost on a basic phone for matte surfaces.
	if rough > 0.85:
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


## Dress a material with a shared tileable albedo. Triplanar world UVs keep
## texel density stable across MultiMesh boxes of different sizes (unit mesh +
## instance scale would otherwise stretch one UV face across a whole pair).
## No normal maps — fill-rate budget on Android.
func _dress(m: StandardMaterial3D, tex_path: String, world_scale: float,
		tint: Color = Color(1, 1, 1)) -> StandardMaterial3D:
	var tex := load(tex_path) as Texture2D
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(world_scale, world_scale, world_scale)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.albedo_color = tint
	return m


func _build_materials() -> void:
	# The pebbledash is the single most identifying surface on the street:
	# off-white, very rough, no sheen at all.
	_mat["dash"] = _dress(_flat(Color(1, 1, 1), 0.98),
		"res://assets/textures/pebbledash.png", 0.55, Color(0.95, 0.94, 0.91))
	# The painted band around the base of the wall.
	_mat["band"] = _dress(_flat(Color(1, 1, 1), 0.92),
		"res://assets/textures/band.png", 0.7, Color(1.0, 0.98, 0.96))
	_mat["roof"] = _dress(_flat(Color(1, 1, 1), 0.88),
		"res://assets/textures/roof.png", 0.45, Color(0.95, 0.95, 0.97))
	_mat["chimney"] = _dress(_flat(Color(1, 1, 1), 0.95),
		"res://assets/textures/chimney.png", 0.8, Color(1, 1, 1))
	# Glass is deliberately OPAQUE. A transparent material forces the whole
	# surface into the alpha-blended pass, which is the most bandwidth-hungry
	# thing you can do on a mobile tiler. A dark, low-roughness opaque panel
	# reads as glass at every distance this street is seen from.
	_mat["glass"] = _flat(Color(0.115, 0.155, 0.185), 0.12, 0.0)
	_mat["frame"] = _flat(Color(0.94, 0.94, 0.93), 0.75)
	_mat["door"] = _flat(Color(0.21, 0.27, 0.38), 0.65)
	# Number 18's door, in a different colour from every other door on the
	# street. On a road where every house is deliberately the same archetype,
	# something has to say "this one is his" from across the carriageway.
	_mat["door_home"] = _flat(Color(0.36, 0.11, 0.13), 0.55)
	_mat["garage_door"] = _flat(Color(0.62, 0.62, 0.63), 0.60, 0.0)
	_mat["tarmac"] = _dress(_flat(Color(1, 1, 1), 0.97),
		"res://assets/textures/tarmac.png", 0.25, Color(0.92, 0.92, 0.94))
	_mat["path"] = _dress(_flat(Color(1, 1, 1), 0.95),
		"res://assets/textures/path.png", 0.5, Color(1, 1, 1))
	_mat["kerb"] = _dress(_flat(Color(1, 1, 1), 0.92),
		"res://assets/textures/kerb.png", 0.9, Color(1, 1, 1))
	_mat["grass"] = _dress(_flat(Color(1, 1, 1), 0.98),
		"res://assets/textures/grass.png", 0.35, Color(0.95, 1.0, 0.9))
	_mat["hedge"] = _dress(_flat(Color(1, 1, 1), 0.98),
		"res://assets/textures/hedge.png", 0.6, Color(1, 1, 1))


# ------------------------------------------------------------------- batching
#
# `_push` records one instance of one box (or prism) against a material key.
# Nothing becomes a node until `_flush_batches()`, so instance counts are known
# up front and each MultiMesh is allocated exactly once.

## Record one instance. The source mesh is always a UNIT box or prism and the
## real dimensions are carried in the instance transform's basis scale. That is
## what lets a single MultiMesh hold boxes of differing sizes — hedge runs
## between gates are all different lengths, and an earlier version of this that
## stored one size per batch quietly drew them all at the first one's length.
func _push(key: String, mat_key: String, shape: String, size: Vector3,
		origin: Vector3) -> void:
	if not _batch.has(key):
		_batch[key] = {"mat": mat_key, "shape": shape, "xf": []}
	_batch[key]["xf"].append(Transform3D(Basis.IDENTITY.scaled(size), origin))


func _flush_batches() -> void:
	for key in _batch:
		var b: Dictionary = _batch[key]
		var xforms: Array = b["xf"]
		if xforms.is_empty():
			continue

		# Typed as PrimitiveMesh, not Mesh: `material` is a PrimitiveMesh
		# property. (`surface_set_material` belongs to ArrayMesh and does not
		# exist on the primitives, which is a easy and silent mistake to make.)
		var mesh: PrimitiveMesh
		if b["shape"] == "prism":
			var pm := PrismMesh.new()
			# PrismMesh's cross-section is a triangle in XY extruded along Z,
			# apex centred at left_to_right = 0.5. That is a pitched roof whose
			# ridge runs along Z — which is the street axis, and therefore the
			# correct ridge direction for pairs fronting this road.
			pm.size = Vector3.ONE
			pm.left_to_right = 0.5
			mesh = pm
		else:
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE
			mesh = bm
		mesh.material = _mat[b["mat"]]

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# Order matters: `mesh` must be assigned before `instance_count`, or
		# the instance buffer is sized against a null mesh.
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])

		var node := MultiMeshInstance3D.new()
		node.name = key
		node.multimesh = mm
		# Shadow pass is the main mobile GPU cost after draw calls. Keep it on
		# wall and roof batches only; detail geometry reads fine in baked daylight.
		if _shadows_off(key):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	_batch.clear()


func _shadows_off(key: String) -> bool:
	return not (key.begins_with("wall") or key.begins_with("roof"))


func _static_box(size: Vector3, origin: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = origin
	_collision.add_child(col)


func _mesh_box(mat_key: String, size: Vector3, origin: Vector3) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat[mat_key]
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = origin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- the ground

func _build_ground() -> void:
	var zr := KilmoreClose.road_z_range()
	var z_len := zr.y - zr.x
	var z_mid := (zr.x + zr.y) * 0.5
	var walk_h := KilmoreClose.WALK_H
	var footpath_w := KilmoreClose.KERB - KilmoreClose.HALF_WIDTH   # 2.0 m

	# Base plate: everything beyond the gardens. Sits just under the road so
	# there is never a gap at the seams.
	_mesh_box("grass", Vector3(140.0, 0.4, z_len + 60.0),
		Vector3(0.0, -0.22, z_mid))

	# Carriageway — 7.63 m kerb to kerb, which is the measured width and is
	# noticeably narrower than a modern estate road. It should feel tight.
	_mesh_box("tarmac", Vector3(KilmoreClose.HALF_WIDTH * 2.0, 0.2, z_len),
		Vector3(0.0, -0.1, z_mid))

	for side in [KilmoreClose.SIDE_NEAR, KilmoreClose.SIDE_FAR]:
		var s := float(side)
		# Footpath, raised by the kerb upstand.
		_mesh_box("path", Vector3(footpath_w, 0.2, z_len),
			Vector3(s * (KilmoreClose.HALF_WIDTH + footpath_w * 0.5),
				walk_h - 0.1, z_mid))
		# Kerb face — a thin strip at the carriageway edge, so the level change
		# reads from a distance instead of being a bare colour seam.
		_mesh_box("kerb", Vector3(0.14, 0.2, z_len),
			Vector3(s * (KilmoreClose.HALF_WIDTH + 0.07), walk_h - 0.1, z_mid))
		# Front gardens: kerb line out to the house faces.
		_mesh_box("grass", Vector3(KilmoreClose.SETBACK, 0.2, z_len),
			Vector3(s * (KilmoreClose.KERB + KilmoreClose.SETBACK * 0.5),
				walk_h - 0.1, z_mid))
		_build_boundary(side, zr)

	# One ground collider for the whole slice. Flat street, so a single box is
	# both correct and the cheapest possible broadphase result.
	_static_box(Vector3(140.0, 0.4, z_len + 60.0), Vector3(0.0, -0.2, z_mid))


## The garden boundary for one side of the street: a low hedge along the kerb
## line, BROKEN BY A GATE at every front door, with a path from each gate up to
## the porch.
##
## The gates matter more than they look. An unbroken hedge is one line of code
## shorter and it silently walls the player out of every front garden on the
## street — including his own — which turns the houses into scenery you can
## only ever look at. Kilmore Close is a place you walk up the path of.
func _build_boundary(side: int, zr: Vector2) -> void:
	var s := float(side)
	var walk_h := KilmoreClose.WALK_H
	var hedge_x := s * (KilmoreClose.KERB + 0.25)
	var gate_half := 0.7

	# Gate positions: one per house on this side, aligned with its front door.
	var gates: Array[float] = []
	for h in KilmoreClose.houses():
		if int(h["side"]) != side:
			continue
		var gz: float = KilmoreClose.gate_z(h)
		gates.append(gz)
		_add_gate_number(side, gz, int(h["number"]))
		# Garden path, gate to porch front. Batched rather than added as its
		# own MeshInstance3D — there is one per house, and twenty individual
		# draw calls for twenty identical paving strips is exactly the sort of
		# thing that quietly eats a low-end phone's frame budget.
		var run := KilmoreClose.SETBACK - KilmoreClose.PORCH_D
		_push("garden_path", "path", "box", Vector3(run, 0.2, 1.15),
			Vector3(s * (KilmoreClose.KERB + run * 0.5), walk_h - 0.1, gz))
	gates.sort()

	# Hedge segments filling everything the gates do not open.
	var cursor := zr.x
	for gz in gates:
		var stop := gz - gate_half
		if stop > cursor:
			_hedge_run(hedge_x, walk_h, cursor, stop)
		cursor = maxf(cursor, gz + gate_half)
	if zr.y > cursor:
		_hedge_run(hedge_x, walk_h, cursor, zr.y)


## A pair of gate piers with the house number on them.
##
## This exists so that "David spawns outside 18 Kilmore Close" is something you
## can VERIFY from inside the game rather than take on trust. The archetype is
## the point of this street — every house is deliberately the same — which means
## without a number on the gate there is no way to tell his from the nineteen
## others, and the single most testable claim in the brief becomes unfalsifiable.
##
## The number is BILLBOARDED. A flat plaque would need its facing rotated per
## side of the street, and Label3D's default orientation is exactly the kind of
## detail that is wrong 50% of the time when you cannot open the editor to look.
## A number you cannot read from the pavement is worse than no number. This is a
## slice affordance; a real plaque mesh replaces it once the street is dressed.
func _add_gate_number(side: int, gz: float, number: int) -> void:
	var s := float(side)
	var walk_h := KilmoreClose.WALK_H
	var pier_h := 1.05
	var pier_x := s * (KilmoreClose.KERB + 0.17)
	for sgn in [-1.0, 1.0]:
		_push("gate_pier", "kerb", "box", Vector3(0.34, pier_h, 0.34),
			Vector3(pier_x, walk_h + pier_h * 0.5, gz + sgn * 0.87))

	var label := Label3D.new()
	label.name = "No%d" % number
	label.text = str(number)
	label.font_size = 96
	label.pixel_size = 0.0032
	label.modulate = Color(0.11, 0.11, 0.12)
	label.outline_size = 14
	label.outline_modulate = Color(0.95, 0.95, 0.93)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = Vector3(pier_x, walk_h + pier_h + 0.2, gz - 0.87)
	add_child(label)


func _hedge_run(x: float, walk_h: float, z0: float, z1: float) -> void:
	var length := z1 - z0
	if length <= 0.01:
		return
	var centre := Vector3(x, walk_h + 0.4, (z0 + z1) * 0.5)
	_push("hedge", "hedge", "box", Vector3(0.5, 0.8, length), centre)
	# Visual only — low hedge does not need per-segment physics (profile cost).


# ----------------------------------------------------- the pair, and the house

## The shared shell of a joined semi-detached PAIR: one wall block, one band,
## one pitched roof, two chimneys. Built per pair rather than per dwelling
## because that is what the building physically is — two houses under one roof
## with no seam down the middle.
func _add_pair_shell(p: Dictionary) -> void:
	var c: Vector3 = p["centre"]
	var wall_h := KilmoreClose.WALL_H
	var depth := KilmoreClose.HOUSE_D
	var width := KilmoreClose.PAIR_W

	# Wall block.
	_push("wall", "dash", "box",
		Vector3(depth, wall_h, width),
		Vector3(c.x, wall_h * 0.5, c.z))
	# Painted band around the base, stood slightly proud of the pebbledash.
	_push("band", "band", "box",
		Vector3(depth + 0.10, 0.9, width + 0.10),
		Vector3(c.x, 0.45, c.z))
	# Pitched roof, ridge along the street, with a small eave overhang.
	_push("roof", "roof", "prism",
		Vector3(depth + 0.6, KilmoreClose.ROOF_H, width + 0.4),
		Vector3(c.x, wall_h + KilmoreClose.ROOF_H * 0.5, c.z))
	# A chimney at each gable end of the pair.
	for sgn in [-1.0, 1.0]:
		_push("chimney", "chimney", "box",
			Vector3(0.9, 1.5, 0.7),
			Vector3(c.x, wall_h + KilmoreClose.ROOF_H * 0.55,
				c.z + sgn * (width * 0.5 - 0.75)))

	# Collision: one box for the pair's wall block. The roof is above head
	# height and the porch/garage carry their own boxes, so this is all the
	# solidity the building needs.
	_static_box(Vector3(depth, wall_h, width), Vector3(c.x, wall_h * 0.5, c.z))


## THE CANONICAL KILMORE CLOSE HOUSE — the per-dwelling half of the archetype:
## two windows upstairs, one window and the front door downstairs, a porch with
## a glazed sliding door over that door, and a single-storey garage at the
## outer end of the frontage.
##
## `mirror` hands the whole arrangement. Within a pair the two dwellings are
## mirrored, so the doors meet at the party wall and the garages land on the
## outer ends — standing in the 3 m gap between pairs, which is exactly where a
## side garage goes on this kind of estate.
func _add_house(h: Dictionary) -> void:
	var face_x: float = h["face_x"]
	var z: float = h["z"]
	var mirror: bool = h["mirror"]
	# Outward normal along X: the direction from the wall toward the road.
	var out := -float(h["side"])
	var n := KilmoreClose.bay_count()

	# Bay roles. Counting from the door end: bay 0 is the door, bay 1 the
	# downstairs window; upstairs, bays 0 and 1 are windows. Everything else is
	# blank wall. That is what yields exactly two up and one down on every
	# house, whatever the bay count works out to.
	for b in n:
		var i := (n - 1 - b) if mirror else b
		var along := KilmoreClose.bay_centre(b)
		if i == 0:
			_add_door(face_x, out, z + along,
				int(h["number"]) == KilmoreClose.DAVID_HOUSE)
		elif i == 1:
			_add_window(face_x, out, z + along, KilmoreClose.WIN_LO_SILL,
				KilmoreClose.WIN_LO_W, KilmoreClose.WIN_LO_H)
		if i < 2:
			_add_window(face_x, out, z + along, KilmoreClose.WIN_HI_SILL,
				KilmoreClose.WIN_HI_W, KilmoreClose.WIN_HI_H)

	# Porch over the front door, garage at the far end. Both clamped inside the
	# frontage so neither overhangs the corner of the wall.
	var half := KilmoreClose.HOUSE_W * 0.5
	var far_bay := 0 if mirror else (n - 1)
	var garage_along := clampf(KilmoreClose.bay_centre(far_bay),
		-(half - KilmoreClose.GARAGE_W * 0.5),
		half - KilmoreClose.GARAGE_W * 0.5)

	_add_porch(face_x, out, z + KilmoreClose.door_along(mirror))
	_add_garage(face_x, out, z + garage_along)


func _add_window(face_x: float, out: float, z: float, sill: float,
		w: float, h: float) -> void:
	# The frame stands 30 mm proud of the wall and the glass 20 mm proud of
	# that, so the reveal catches the light instead of the opening reading as a
	# flat decal painted on the pebbledash.
	var y := sill + h * 0.5
	_push("win_frame", "frame", "box",
		Vector3(0.06, h + 0.16, w + 0.16),
		Vector3(face_x + out * 0.03, y, z))
	_push("win_glass", "glass", "box",
		Vector3(0.04, h, w),
		Vector3(face_x + out * 0.06, y, z))


func _add_door(face_x: float, out: float, z: float, is_home: bool) -> void:
	var dh := KilmoreClose.DOOR_H
	var dw := KilmoreClose.DOOR_W
	_push("door_frame", "frame", "box",
		Vector3(0.06, dh + 0.14, dw + 0.14),
		Vector3(face_x + out * 0.03, (dh + 0.14) * 0.5, z))
	# Two batches, not one, so number 18 can carry its own door colour without
	# breaking the single-draw-call-per-material rule the street relies on.
	var key := "door_home" if is_home else "door_leaf"
	var mat := "door_home" if is_home else "door"
	_push(key, mat, "box",
		Vector3(0.05, dh, dw),
		Vector3(face_x + out * 0.06, dh * 0.5, z))


## Porch: a shallow box projecting from the front wall, with a glazed sliding
## door across its face and a flat lid.
func _add_porch(face_x: float, out: float, z: float) -> void:
	var pd := KilmoreClose.PORCH_D
	var pw := KilmoreClose.PORCH_W
	var ph := KilmoreClose.PORCH_H
	var cx := face_x + out * (pd * 0.5)
	var glass_h := ph - 0.28

	# Two side cheeks in pebbledash, so the porch reads as built rather than
	# stuck on.
	for sgn in [-1.0, 1.0]:
		_push("porch_side", "dash", "box",
			Vector3(pd, ph, 0.16),
			Vector3(cx, ph * 0.5, z + sgn * (pw * 0.5 - 0.08)))
	# Lid.
	_push("porch_lid", "frame", "box",
		Vector3(pd + 0.16, 0.14, pw + 0.20),
		Vector3(cx, ph + 0.07, z))
	# The glazed sliding door across the front of the porch.
	_push("porch_glass", "glass", "box",
		Vector3(0.06, glass_h, pw - 0.20),
		Vector3(face_x + out * pd, glass_h * 0.5 + 0.06, z))
	# A centre mullion, which is what makes it read as a *sliding* door rather
	# than one big pane.
	_push("porch_mullion", "frame", "box",
		Vector3(0.09, glass_h, 0.07),
		Vector3(face_x + out * (pd + 0.02), glass_h * 0.5 + 0.06, z))
	# Visual only — porch collision duplicated the pair wall and added 52 extra
	# broadphase boxes across the full street (profile: 185 shapes).


## Garage: single storey, flat roof, pebbledash to match the house, with a
## panelled up-and-over door on the street face.
func _add_garage(face_x: float, out: float, z: float) -> void:
	var gd := KilmoreClose.GARAGE_D
	var gw := KilmoreClose.GARAGE_W
	var gh := KilmoreClose.GARAGE_H
	var cx := face_x + out * (gd * 0.5)

	_push("garage", "dash", "box",
		Vector3(gd, gh, gw), Vector3(cx, gh * 0.5, z))
	# Coping, so the flat roof has a visible edge.
	_push("garage_lid", "frame", "box",
		Vector3(gd + 0.18, 0.16, gw + 0.18), Vector3(cx, gh + 0.08, z))
	# The door itself, on the street-facing end.
	_push("garage_door", "garage_door", "box",
		Vector3(0.08, gh - 0.30, gw - 0.22),
		Vector3(face_x + out * gd, (gh - 0.30) * 0.5, z))
	# Visual only — pair wall collision blocks the dwelling; garage is set dressing.

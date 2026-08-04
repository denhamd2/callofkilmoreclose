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
## Emitted once the walkable surface exists, with its polygon count. Cast AI must
## wait for this: a NavigationAgent3D queried before the map has synchronised
## returns Vector3.ZERO, and every agent then slides to the world origin.
signal navmesh_ready(polygon_count: int)

## Parked-car slots the live `Car` can possess. Each entry:
## `{ transform, visual, collider, claimed }`.
var park_slots: Array[Dictionary] = []

## Scene group the navmesh bake reads its source colliders from.
const NAV_SOURCE_GROUP := &"navmesh_source"

## Length of one MultiMesh batch bucket along the street, in metres. ~70 m over a
## 275 m run gives four or five buckets per surface: still trivially few draw
## calls, but small enough that each one has a tight AABB and can be culled.
const BATCH_BUCKET_M := 70.0

## Street furniture spacing, in metres along the road.
const TREE_SPACING_M := 13.0
const LAMP_SPACING_M := 26.0
const LAMP_HEIGHT := 5.2

# Materials are shared instances — one per surface, reused across every
# MultiMesh. Fewer unique materials means fewer state changes, which matters
# more than shader complexity on a low-end GPU.
var _mat: Dictionary = {}

# Transform buckets, filled during generation and flushed into MultiMeshes.
var _batch: Dictionary = {}

var _collision: StaticBody3D

const _CAR_MESH: PackedScene = preload("res://assets/models/golf_mk4/golf_mk4_visual.tscn")
const _TREE_VARIANTS: Array[PackedScene] = [
	preload("res://assets/models/trees_bushes/tree_a_visual.tscn"),
	preload("res://assets/models/trees_bushes/tree_b_visual.tscn"),
	preload("res://assets/models/trees_bushes/tree_c_visual.tscn"),
	preload("res://assets/models/trees_bushes/tree_d_visual.tscn"),
	preload("res://assets/models/trees_bushes/tree_e_visual.tscn"),
]
const _BUSH_MESH: PackedScene = preload("res://assets/models/trees_bushes/bush_a_visual.tscn")
const _DESTRUCTIBLE_TREE: PackedScene = preload("res://scenes/fx/destructible_tree.tscn")
const _BIN_SCRIPT: Script = preload("res://scripts/fx/destructible_bin.gd")
const _HEALTH_SCRIPT: Script = preload("res://scripts/combat/health.gd")

# 7-segment digit patterns (segments: top, UR, LR, bottom, LL, UL, mid).
const _DIGIT_SEG: Dictionary = {
	0: [1, 1, 1, 1, 1, 1, 0], 1: [0, 1, 1, 0, 0, 0, 0],
	2: [1, 1, 0, 1, 1, 0, 1], 3: [1, 1, 1, 1, 0, 0, 1],
	4: [0, 1, 1, 0, 0, 1, 1], 5: [1, 0, 1, 1, 0, 1, 1],
	6: [1, 0, 1, 1, 1, 1, 1], 7: [1, 1, 1, 0, 0, 0, 0],
	8: [1, 1, 1, 1, 1, 1, 1], 9: [1, 1, 1, 1, 0, 1, 1],
}

var _tree_spots: Array = []
var _lawn_spots: Array = []  # Vector3 centres of remnant lawns
var _lawn_sizes: Array = []  # Vector2(len_x, width_z) per lawn
var _garden_rects: Array = []  # {centre: Vector3, size: Vector2} full front plots
var _driveway_spots: Array = []  # {pos: Vector3, yaw: float} for static cars
var _verge_y: float = 0.0
var _footpath_verge_y: float = 0.0

const _CAR_PAINTS: Array = [
	Color(0.92, 0.92, 0.94),   # white
	Color(0.72, 0.74, 0.76),   # silver
	Color(0.55, 0.10, 0.12),   # red
	Color(0.12, 0.18, 0.38),   # navy
	Color(0.08, 0.08, 0.10),   # black
	Color(0.18, 0.38, 0.22),   # green
	Color(0.42, 0.10, 0.14),   # burgundy
	Color(0.78, 0.72, 0.58),   # beige
	Color(0.32, 0.34, 0.36),   # dark grey
	Color(0.22, 0.38, 0.62),   # blue
]


func _ready() -> void:
	_build_materials()
	_collision = StaticBody3D.new()
	_collision.name = "StreetCollision"
	# Tagged so the navmesh bake can find it by group — see _bake_navmesh().
	_collision.add_to_group(NAV_SOURCE_GROUP)
	add_child(_collision)

	_build_ground()
	for h in KilmoreClose.houses():
		_add_house(h)
	for p in KilmoreClose.pairs():
		_add_pair_shell(p)
	_build_street_dressing()
	_flush_batches()
	_spawn_static_cars()
	_spawn_driveway_cars()
	_spawn_static_trees()
	_spawn_garden_bushes()
	_spawn_detail_grass()
	built.emit()
	_bake_navmesh()


# --------------------------------------------------------------- navigation

## Walkable surface for the cast, baked at load time because the street itself is
## generated at load time — there is no authored geometry to bake in the editor.
##
## Source geometry is STATIC_COLLIDERS, not the visual meshes. Godot's parser does
## handle MultiMeshInstance3D, but the visual batches carry roof prisms, gutters,
## overhead wires and 7-segment house-number boxes — none of which mean anything
## for walking, all of which would perturb the surface, and 4205 instances of
## which is a slow bake. The 81 collision boxes are exactly the right input: one
## ground plate, 26 pair blocks, 54 boundary wall runs. Baking those carves the
## houses and garden walls out of the plate and leaves road, footpaths and front
## gardens — which is the brawl arena.
##
## The pedestrian gates are visual-only (`_add_ped_gate` never adds collision), so
## the 1.4 m openings stay physically clear and the gardens remain reachable.
func _bake_navmesh() -> void:
	var region := NavigationRegion3D.new()
	region.name = "StreetNav"
	add_child(region)

	var nav := NavigationMesh.new()
	# Must match navigation/3d/default_cell_size in project.godot, or Godot warns
	# and paths degrade against the map's own rasterisation.
	nav.cell_size = 0.25 if ProfileToggles.has(&"nav_coarse") else 0.15
	nav.cell_height = nav.cell_size
	nav.agent_height = 1.8
	nav.agent_radius = 0.4
	# The kerb upstand is KilmoreClose.WALK_H (0.125 m), so it has to be
	# climbable or the cast can never step off the footpath onto the road.
	nav.agent_max_climb = 0.2
	nav.agent_max_slope = 45.0
	nav.region_min_size = 2.0
	nav.edge_max_length = 6.0
	nav.detail_sample_distance = 3.0
	nav.detail_sample_max_error = 0.5
	nav.filter_low_hanging_obstacles = true
	nav.filter_ledge_spans = true
	nav.filter_walkable_low_height_spans = true
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	# Group-sourced, not ROOT_NODE_CHILDREN: that mode parses the children of the
	# NavigationRegion3D itself, and StreetCollision is the region's *sibling*, so
	# it silently baked zero polygons.
	nav.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav.geometry_source_group_name = NAV_SOURCE_GROUP
	nav.geometry_collision_mask = 1

	# Bound the bake. The ground plate is 140 x 335 m; unbounded, this would
	# rasterise ~47,000 m² of empty hinterland — slow, and it gives the cast
	# somewhere pointless to wander off to.
	var zr := KilmoreClose.road_z_range()
	nav.filter_baking_aabb = AABB(
		Vector3(-24.0, -1.0, zr.x - 4.0),
		Vector3(48.0, 6.0, (zr.y - zr.x) + 8.0))

	region.navigation_mesh = nav
	region.bake_finished.connect(_on_navmesh_baked.bind(region), CONNECT_ONE_SHOT)
	region.bake_navigation_mesh(true)


func _on_navmesh_baked(region: NavigationRegion3D) -> void:
	var polys := 0
	if region.navigation_mesh != null:
		polys = region.navigation_mesh.get_polygon_count()
	navmesh_ready.emit(polys)


# --------------------------------------------------------------- materials

## Untextured surfaces. Specular is no longer disabled: the old rule switched it
## off for anything rougher than 0.85, which was nearly every surface on the
## street, and damp Dublin tarmac with no specular response is a flat grey sheet.
## Forward+ gets the highlight for free where gl_compatibility did not.
func _flat(colour: Color, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m


## Dress a material with a shared tileable albedo, plus the derived normal and
## packed-ORM maps from `tools/generate_pbr_maps.py` when they exist.
##
## Triplanar world UVs keep texel density stable across MultiMesh boxes of
## different sizes — a unit mesh scaled by the instance basis would otherwise
## stretch one UV face across a whole semi-detached pair.
##
## Returns an ORMMaterial3D (a StandardMaterial3D subclass) whenever an ORM map is
## present: one texture fetch for occlusion + roughness + metallic instead of
## three, and the roughness map is what lets one tarmac material read as wet in
## the channel and dry on the crown.
## Returns BaseMaterial3D, not StandardMaterial3D: ORMMaterial3D is a *sibling* of
## StandardMaterial3D under BaseMaterial3D, not a subclass of it.
func _dress(m: StandardMaterial3D, tex_path: String, world_scale: float,
		tint: Color = Color(1, 1, 1)) -> BaseMaterial3D:
	var base := tex_path.get_basename()
	var orm := load(base + "_orm.png") as Texture2D
	var out: BaseMaterial3D = m
	if orm != null:
		var om := ORMMaterial3D.new()
		om.roughness = m.roughness
		om.metallic = m.metallic
		om.orm_texture = orm
		out = om

	var tex := load(tex_path) as Texture2D
	if tex != null:
		out.albedo_texture = tex
		out.uv1_triplanar = true
		out.uv1_world_triplanar = true
		out.uv1_scale = Vector3(world_scale, world_scale, world_scale)
		out.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	var nrm := load(base + "_normal.png") as Texture2D
	if nrm != null:
		out.normal_enabled = true
		out.normal_texture = nrm
		out.normal_scale = 1.0

	out.albedo_color = tint
	return out


func _build_materials() -> void:
	# The pebbledash is the single most identifying surface on the street:
	# off-white, very rough, no sheen at all.
	_mat["dash"] = _dress(_flat(Color(1, 1, 1), 0.88),
		"res://assets/textures/pebbledash.png", 0.38, Color(0.88, 0.86, 0.82))
	# The painted band around the base of the wall.
	_mat["band"] = _dress(_flat(Color(1, 1, 1), 0.92),
		"res://assets/textures/band.png", 0.7, Color(0.98, 0.94, 0.90))
	# Mid-height salmon/terracotta panels (reference facades).
	_mat["band_mid"] = _dress(_flat(Color(1, 1, 1), 0.90),
		"res://assets/textures/band_mid.png", 0.65, Color(1.0, 0.96, 0.94))
	# Roof: weathered charcoal concrete interlocking tiles (Marley-style courses).
	# Dark albedo + tighter world_scale so tile laps read from the footpath.
	_mat["roof"] = _dress(_flat(Color(1, 1, 1), 0.88),
		"res://assets/textures/roof.png", 0.24, Color(0.48, 0.46, 0.43))
	# Chimney stack: rendered and painted like the house, not brick. In the
	# reference the stack is a pale grey-cream render with a plain concrete capping
	# slab — no exposed brickwork at all.
	_mat["chimney"] = _dress(_flat(Color(1, 1, 1), 0.95),
		"res://assets/textures/chimney.png", 0.8, Color(0.80, 0.78, 0.73))
	# Cast concrete: chimney capping slab and the pots that sit on it.
	_mat["concrete"] = _flat(Color(0.60, 0.58, 0.55), 0.90)
	# Painted timber fascia at the eaves — the pale line under every roof edge in
	# the reference, which was missing entirely.
	_mat["fascia"] = _flat(Color(0.86, 0.85, 0.81), 0.72)
	# Real glass now that Forward+ gives us SSR. ALPHA_DEPTH_PRE_PASS rather than
	# plain alpha: the ~700 panes live in three MultiMesh batches with no
	# intra-batch depth sort, so ordinary blending sorts them wrong against each
	# other. The pre-pass writes depth first, which is exactly the setting
	# architectural glazing wants.
	_mat["glass"] = _flat(Color(0.55, 0.62, 0.68, 0.22), 0.03, 0.0)
	_mat["glass"].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_mat["glass"].cull_mode = BaseMaterial3D.CULL_DISABLED
	# Mahogany window/door frames (reference brown trim).
	_mat["frame"] = _flat(Color(0.42, 0.28, 0.18), 0.72)
	_mat["door"] = _flat(Color(0.21, 0.27, 0.38), 0.65)
	_mat["door_home"] = _flat(Color(0.36, 0.11, 0.13), 0.55)
	_mat["garage_door"] = _dress(_flat(Color(1, 1, 1), 0.62),
		"res://assets/textures/garage_door.png", 0.5, Color(0.95, 0.92, 0.88))
	_mat["tarmac"] = _dress(_flat(Color(1, 1, 1), 0.72),
		"res://assets/textures/tarmac.png", 0.22, Color(0.60, 0.60, 0.62))
	_mat["path"] = _dress(_flat(Color(1, 1, 1), 0.85),
		"res://assets/textures/path.png", 0.34, Color(0.50, 0.50, 0.48))
	_mat["drive"] = _dress(_flat(Color(1, 1, 1), 0.82),
		"res://assets/textures/drive.png", 0.45, Color(1, 1, 1))
	_mat["kerb"] = _dress(_flat(Color(1, 1, 1), 0.80),
		"res://assets/textures/kerb.png", 0.9, Color(0.82, 0.82, 0.80))
	# P0: split grass reads — hinterland, verge, and remnant lawns differ.
	_mat["grass_far"] = _dress(_flat(Color(1, 1, 1), 0.98),
		"res://assets/textures/grass.png", 0.22, Color(0.44, 0.50, 0.36))
	_mat["grass_verge"] = _dress(_flat(Color(1, 1, 1), 0.98),
		"res://assets/textures/grass.png", 0.48, Color(0.40, 0.47, 0.32))
	_mat["grass_lawn"] = _dress(_flat(Color(1, 1, 1), 0.98),
		"res://assets/textures/grass_lawn.png", 0.34, Color(0.52, 0.60, 0.42))
	_mat["grass_footpath_verge"] = _dress(_flat(Color(1, 1, 1), 0.98),
		"res://assets/textures/grass_lawn.png", 0.36, Color(0.46, 0.54, 0.38))
	# Soft soil/grit at lawn–drive and lawn–path joints.
	_mat["soil"] = _flat(Color(0.32, 0.26, 0.18), 0.96)
	_mat["hedge"] = _dress(_flat(Color(1, 1, 1), 0.98),
		"res://assets/textures/hedge.png", 0.55, Color(0.78, 0.86, 0.62))
	# Front boundary walls, coping, gutters, pipes, gates.
	_mat["block_wall"] = _dress(_flat(Color(1, 1, 1), 0.96),
		"res://assets/textures/block_wall.png", 0.72, Color(0.92, 0.92, 0.90))
	_mat["brick_red"] = _dress(_flat(Color(1, 1, 1), 0.94),
		"res://assets/textures/brick_red.png", 0.55, Color(0.98, 0.96, 0.94))
	_mat["coping"] = _flat(Color(0.38, 0.38, 0.36), 0.88)
	_mat["pipe"] = _flat(Color(0.18, 0.18, 0.20), 0.55, 0.15)
	# Gates and wall-top railings. Was 0.08 albedo at 0.4 metallic, which under
	# sky-only ambient rendered as flat black holes in the boundary wall — the
	# most obvious remaining artefact on the street. Real painted ironwork is dark
	# but still catches the sky, so lift the albedo and drop the metallic: a
	# metallic surface with nothing to reflect goes black, a rough dielectric does
	# not.
	_mat["metal_black"] = _flat(Color(0.34, 0.35, 0.38), 0.38, 0.10)
	_mat["bin_red"] = _flat(Color(0.62, 0.12, 0.10), 0.75)
	_mat["bin_green"] = _flat(Color(0.14, 0.38, 0.16), 0.75)
	_mat["plaque"] = _flat(Color(0.14, 0.14, 0.15), 0.82)
	_mat["plaque_text"] = _flat(Color(0.94, 0.94, 0.92), 0.70)


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
	_push_xf(key, mat_key, shape, Transform3D(Basis.IDENTITY.scaled(size), origin))


## Batch keys are suffixed with a Z bucket, which is the single highest-leverage
## rendering change available here.
##
## Keying purely by material — "wall", "roof", "win_glass" — meant one MultiMesh
## held every instance of that surface along the whole 275 m street, so its AABB
## spanned the whole street too. The consequence is that all ~46 batches were
## frustum-visible from every camera position and were therefore submitted every
## single frame, with no possibility of frustum culling, mesh LOD or
## visibility_range. Bucketing by Z turns each batch into a spatially coherent
## node the renderer can actually reject.
func _push_xf(key: String, mat_key: String, shape: String,
		xf: Transform3D) -> void:
	var bucketed := "%s#%d" % [key, int(floor(xf.origin.z / BATCH_BUCKET_M))]
	if not _batch.has(bucketed):
		_batch[bucketed] = {"mat": mat_key, "shape": shape, "xf": [], "base": key}
	_batch[bucketed]["xf"].append(xf)


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
		# Shadow casting is now the default rather than the exception. It used to
		# be limited to wall and roof batches to protect an Android fill-rate
		# budget; with that target dropped and Forward+ doing PCSS off a 4096 map,
		# contact shadows under bins, piers, porches and gutters are most of what
		# makes the street read as solid geometry rather than decals on a plane.
		if _shadows_off(str(b.get("base", key))):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	_batch.clear()


## Inverted from an allow-list to a deny-list. Only surfaces whose shadow would be
## noise are excluded now: the glazing (it is transparent), the flat house-number
## digits, and the overhead wires — a 0.03 m wire casts a shimmering dashed line
## across the road at any shadow resolution, which reads as an artefact.
func _shadows_off(key: String) -> bool:
	for excluded in ["glass", "digit", "plaque", "wire"]:
		if key.begins_with(excluded) or key.contains(excluded):
			return true
	return false


## A static box tilted about Z, used to build the kerb chamfer. `_static_box` alone
## can only ever produce axis-aligned steps, and a step is not climbable.
func _static_box_tilted(size: Vector3, origin: Vector3, roll: float) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = Transform3D(Basis.from_euler(Vector3(0.0, 0.0, roll)), origin)
	_collision.add_child(col)


func _static_box(size: Vector3, origin: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = origin
	_collision.add_child(col)
	return col


func claim_park_slot(index: int) -> void:
	if index < 0 or index >= park_slots.size():
		return
	var slot: Dictionary = park_slots[index]
	if bool(slot.get("claimed", false)):
		return
	slot["claimed"] = true
	var visual := slot.get("visual") as Node3D
	if visual != null:
		visual.visible = false
	var collider := slot.get("collider") as CollisionShape3D
	if collider != null:
		collider.disabled = true


func nearest_open_park_slot(near: Vector3, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist
	for i in park_slots.size():
		var slot: Dictionary = park_slots[i]
		if bool(slot.get("claimed", false)):
			continue
		var pos: Vector3 = slot.get("transform", Transform3D.IDENTITY).origin
		var d := near.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func park_slot_place(index: int) -> Transform3D:
	if index < 0 or index >= park_slots.size():
		return Transform3D.IDENTITY
	var visual := park_slots[index].get("visual") as Node3D
	if visual == null:
		return Transform3D.IDENTITY
	var at := visual.global_transform
	at.origin.y = Car.RIDE_HEIGHT
	return at


## A box occluder. Not a CollisionShape3D, so it costs nothing in the physics
## broadphase and does not count against the probe's collision budget.
func _add_occluder(size: Vector3, origin: Vector3) -> void:
	var box := BoxOccluder3D.new()
	box.size = size
	var node := OccluderInstance3D.new()
	node.occluder = box
	node.position = origin
	add_child(node)


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
	# there is never a gap at the seams. Far grass stays flat (no blade scatter).
	_mesh_box("grass_far", Vector3(140.0, 0.4, z_len + 60.0),
		Vector3(0.0, -0.22, z_mid))

	# Carriageway — 7.63 m kerb to kerb, which is the measured width and is
	# noticeably narrower than a modern estate road. It should feel tight.
	_mesh_box("tarmac", Vector3(KilmoreClose.HALF_WIDTH * 2.0, 0.2, z_len),
		Vector3(0.0, -0.1, z_mid))

	_verge_y = walk_h - 0.14
	_footpath_verge_y = walk_h - 0.10
	var footpath_verge_w := 0.45
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
		# Roadside verge — narrow grass between kerb and carriageway.
		_mesh_box("grass_verge", Vector3(0.55, 0.12, z_len),
			Vector3(s * (KilmoreClose.HALF_WIDTH + 0.38), _verge_y, z_mid))
		# Footpath outer verge — grass strip between path and garden wall.
		_mesh_box("grass_footpath_verge", Vector3(footpath_verge_w, 0.10, z_len),
			Vector3(s * (KilmoreClose.KERB + 0.12), _footpath_verge_y, z_mid))
		# Front-plot underlay: lawn texture across the full garden depth.
		_mesh_box("grass_lawn", Vector3(KilmoreClose.SETBACK, 0.18, z_len),
			Vector3(s * (KilmoreClose.KERB + KilmoreClose.SETBACK * 0.5),
				walk_h - 0.12, z_mid))
		_build_boundary(side, zr)

	# Base ground collider: correct for the carriageway, whose visual top is also
	# y = 0. Everything raised above it needs its own box, below.
	_static_box(Vector3(140.0, 0.4, z_len + 60.0), Vector3(0.0, -0.2, z_mid))

	# The raised surfaces were previously VISUALS ONLY — `_mesh_box()` creates a
	# MeshInstance3D and never any collision. So the only floor anywhere was the
	# plate above, topped at y = 0, while the pavement is drawn at y = WALK_H
	# (0.125) and the front gardens at 0.095. Everyone therefore stood exactly
	# WALK_H below the surface they appeared to be on — the sinking bug.
	#
	# Each box below is sized so its TOP FACE lands on the matching visual height.
	# The navmesh bakes from static colliders, so this also lifts the walkable
	# surface onto the pavement for free, and `agent_max_climb = 0.2` still covers
	# the 0.125 kerb step down to the road.
	#
	# The 0.045-high verge is deliberately left uncollided: it is shallower than
	# CharacterBody3D's default 0.1 floor_snap_length, so walkers step onto it
	# without a visible pop and it costs no broadphase.
	var garden_top := walk_h - 0.03          # 0.095, matching the plot underlay
	# Horizontal run of the kerb chamfer. CharacterBody3D does not step up — it only
	# snaps downward — so a bare 0.125 m kerb is an unclimbable wall and everyone
	# gets stuck in the road. A ramp shallower than floor_max_angle (45 deg) is
	# walkable; 0.125 over 0.30 is about 23 deg.
	var chamfer := 0.30
	var roll := atan2(walk_h, chamfer)
	for side in [KilmoreClose.SIDE_NEAR, KilmoreClose.SIDE_FAR]:
		var s := float(side)
		# Footpath and kerb strip as one box — they share a top face at WALK_H.
		var path_w := footpath_w + 0.14
		_static_box(Vector3(path_w, 0.5, z_len),
			Vector3(s * (KilmoreClose.HALF_WIDTH + path_w * 0.5),
				walk_h - 0.25, z_mid))
		# The chamfer. Rolling about Z by +angle raises the +X end of the top face,
		# so the sign follows the side and both kerbs slope up away from the road.
		# Positioned so the top face passes through the road edge and the kerb top.
		var thick := 0.30
		var mid_x := s * (KilmoreClose.HALF_WIDTH + chamfer * 0.5)
		var phi := s * roll
		_static_box_tilted(
			Vector3(chamfer + 0.10, thick, z_len),
			Vector3(mid_x + thick * 0.5 * sin(phi),
				walk_h * 0.5 - thick * 0.5 * cos(phi), z_mid),
			phi)
		# Front gardens, so the cast can walk up to the doors without sinking.
		_static_box(Vector3(KilmoreClose.SETBACK, 0.5, z_len),
			Vector3(s * (KilmoreClose.KERB + KilmoreClose.SETBACK * 0.5),
				garden_top - 0.25, z_mid))


## The garden boundary for one side of the street: low block walls along the
## kerb line, broken by pedestrian gates, with driveways and remnant lawns.
func _build_boundary(side: int, zr: Vector2) -> void:
	var s := float(side)
	var walk_h := KilmoreClose.WALK_H
	var wall_x := s * (KilmoreClose.KERB + 0.25)
	var gate_half := 0.7

	var gates: Array[float] = []
	for h in KilmoreClose.houses():
		if int(h["side"]) != side:
			continue
		var gz: float = KilmoreClose.gate_z(h)
		gates.append(gz)
		_add_gate_number(side, gz, int(h["number"]))
		_add_ped_gate(wall_x, walk_h, gz)
		_add_house_plot(h, walk_h)
		var run := KilmoreClose.SETBACK - KilmoreClose.PORCH_D
		_push("garden_path", "path", "box", Vector3(run, 0.2, 1.15),
			Vector3(s * (KilmoreClose.KERB + run * 0.5), walk_h - 0.1, gz))
	gates.sort()

	var cursor := zr.x
	for gz in gates:
		var stop := gz - gate_half
		if stop > cursor:
			_wall_run(wall_x, walk_h, cursor, stop)
		cursor = maxf(cursor, gz + gate_half)
	if zr.y > cursor:
		_wall_run(wall_x, walk_h, cursor, zr.y)


func _wall_run(x: float, walk_h: float, z0: float, z1: float) -> void:
	var length := z1 - z0
	if length <= 0.01:
		return
	var wall_h := 0.62
	var centre := Vector3(x, walk_h + wall_h * 0.5, (z0 + z1) * 0.5)
	_push("wall_boundary", "block_wall", "box", Vector3(0.22, wall_h, length), centre)
	_static_box(Vector3(0.22, wall_h, length), centre)
	_push("wall_coping", "coping", "box", Vector3(0.26, 0.06, length),
		Vector3(x, walk_h + wall_h + 0.03, (z0 + z1) * 0.5))
	if length > 2.8:
		_push("wall_rail", "metal_black", "box", Vector3(0.04, 0.32, length),
			Vector3(x, walk_h + wall_h + 0.22, (z0 + z1) * 0.5))


func _add_ped_gate(x: float, walk_h: float, gz: float) -> void:
	var gate_h := 1.05
	_push("ped_gate", "metal_black", "box", Vector3(0.04, gate_h, 1.35),
		Vector3(x, walk_h + gate_h * 0.5, gz))


func _garage_along_z(h: Dictionary) -> float:
	# Outer-end garages project half of PAIR_GAP into the inter-pair passage so
	# adjacent pairs meet with no visible hole (PAIR_GAP is where garages stand).
	var p: int = h["pair"]
	var pair_origin := float(p) * KilmoreClose.PITCH
	if h["mirror"]:
		return pair_origin - KilmoreClose.PAIR_GAP * 0.5 + KilmoreClose.GARAGE_W * 0.5
	return pair_origin + KilmoreClose.PAIR_W + KilmoreClose.PAIR_GAP * 0.5 \
		- KilmoreClose.GARAGE_W * 0.5


func _add_house_plot(h: Dictionary, walk_h: float) -> void:
	var side := int(h["side"])
	var s := float(side)
	var out := -float(side)
	var gz := KilmoreClose.gate_z(h)
	var g_z := _garage_along_z(h)
	var kerb_x := s * KilmoreClose.KERB
	var drive_len := KilmoreClose.SETBACK * 0.72
	var drive_w := KilmoreClose.GARAGE_W + 0.35
	var drive_cx := kerb_x - out * drive_len * 0.5
	_push("driveway", "drive", "box", Vector3(drive_len, 0.06, drive_w),
		Vector3(drive_cx, walk_h - 0.07, g_z))
	# Soil wear strips along drive edges (reference grit at hard/soft joints).
	_push("soil_edge", "soil", "box", Vector3(drive_len, 0.04, 0.18),
		Vector3(drive_cx, walk_h - 0.06, g_z - drive_w * 0.5 - 0.05))
	_push("soil_edge", "soil", "box", Vector3(drive_len, 0.04, 0.18),
		Vector3(drive_cx, walk_h - 0.06, g_z + drive_w * 0.5 + 0.05))

	var door_z := float(h["z"]) + KilmoreClose.door_along(bool(h["mirror"]))
	var lawn_z := (gz + door_z) * 0.5
	var lawn_w := KilmoreClose.HOUSE_W * 0.42
	var lawn_len := KilmoreClose.SETBACK * 0.55
	var lawn_cx := kerb_x - out * lawn_len * 0.5
	_push("lawn_patch", "grass_lawn", "box", Vector3(lawn_len, 0.05, lawn_w),
		Vector3(lawn_cx, walk_h - 0.05, lawn_z))
	# Thin soil band where lawn meets the garden path / wall.
	_push("soil_edge", "soil", "box", Vector3(0.22, 0.035, lawn_w * 0.92),
		Vector3(kerb_x - out * 0.35, walk_h - 0.04, lawn_z))

	_lawn_spots.append(Vector3(lawn_cx, walk_h - 0.02, lawn_z))
	_lawn_sizes.append(Vector2(lawn_len * 0.85, lawn_w * 0.85))

	var garden_cx := kerb_x - out * KilmoreClose.SETBACK * 0.5
	_garden_rects.append({
		"centre": Vector3(garden_cx, walk_h - 0.02, float(h["z"])),
		"size": Vector2(KilmoreClose.SETBACK * 0.88, KilmoreClose.HOUSE_W * 0.92),
	})

	if int(h["number"]) % 2 == 0:
		# Length along the driveway (X); nose toward the garage. Opposite yaw to
		# kerbside slots, which park parallel to the street (Z).
		var car_yaw := -PI * 0.5 if side == KilmoreClose.SIDE_NEAR else PI * 0.5
		_driveway_spots.append({
			"pos": Vector3(drive_cx, walk_h - 0.04, g_z),
			"yaw": car_yaw,
			"house_z": float(h["z"]),
		})

	# P1: sparse multi-part shrubs (not a single cube).
	if int(h["number"]) % 3 == 0:
		_add_shrub(kerb_x - out * (KilmoreClose.SETBACK * 0.82), walk_h, door_z)
	# Occasional thin bed under the front window bay.
	if int(h["number"]) % 4 == 1:
		var face_x: float = float(h["face_x"])
		var bed_z := door_z + (1.1 if bool(h["mirror"]) else -1.1)
		_push("soil_bed", "soil", "box", Vector3(0.55, 0.06, 1.2),
			Vector3(face_x - out * 0.35, walk_h - 0.02, bed_z))
		_push("shrub_low", "hedge", "box", Vector3(0.35, 0.22, 0.40),
			Vector3(face_x - out * 0.35, walk_h + 0.12, bed_z - 0.25))
		_push("shrub_low", "hedge", "box", Vector3(0.30, 0.18, 0.35),
			Vector3(face_x - out * 0.35, walk_h + 0.10, bed_z + 0.28))


func _add_shrub(x: float, walk_h: float, z: float) -> void:
	# Two–three stacked rounded volumes read as a bush at street distance.
	_push("shrub_core", "hedge", "box", Vector3(0.55, 0.38, 0.50),
		Vector3(x, walk_h + 0.22, z))
	_push("shrub_lobe", "hedge", "box", Vector3(0.42, 0.32, 0.40),
		Vector3(x + 0.18, walk_h + 0.28, z + 0.12))
	_push("shrub_lobe", "hedge", "box", Vector3(0.36, 0.28, 0.38),
		Vector3(x - 0.14, walk_h + 0.30, z - 0.10))


## Gate piers with a dark plaque and 7-segment house number facing the pavement.
func _add_gate_number(side: int, gz: float, number: int) -> void:
	var s := float(side)
	var walk_h := KilmoreClose.WALK_H
	var pier_h := 1.05
	var pier_x := s * (KilmoreClose.KERB + 0.17)
	var face := -s  # toward the road centre from the garden wall.
	for sgn in [-1.0, 1.0]:
		_push("gate_pier", "kerb", "box", Vector3(0.34, pier_h, 0.34),
			Vector3(pier_x, walk_h + pier_h * 0.5, gz + sgn * 0.87))

	var plaque_y := walk_h + pier_h + 0.10
	var plaque_z := gz - 0.87
	_push("number_plaque", "plaque", "box",
		Vector3(0.05, 0.24, 0.34),
		Vector3(pier_x + face * 0.10, plaque_y, plaque_z))
	_push_gate_digits(pier_x + face * 0.13, plaque_y, plaque_z, face, number)


func _push_gate_digits(px: float, py: float, pz: float, face: float,
		number: int) -> void:
	var digits := str(number)
	var count := digits.length()
	var cell := 0.11
	var start_z := pz - (count - 1) * cell * 0.5
	for i in count:
		_push_digit_7(px, py, start_z + i * cell, face, int(digits[i]))


func _push_digit_7(px: float, py: float, pz: float, face: float,
		digit: int) -> void:
	var pat: Array = _DIGIT_SEG.get(digit, _DIGIT_SEG[8])
	var segs: Array = [
		[Vector3(0.0, 0.075, 0.0), Vector3(0.03, 0.028, 0.075)],   # top
		[Vector3(0.0, 0.038, 0.038), Vector3(0.03, 0.052, 0.024)],  # UR
		[Vector3(0.0, -0.038, 0.038), Vector3(0.03, 0.052, 0.024)], # LR
		[Vector3(0.0, -0.075, 0.0), Vector3(0.03, 0.028, 0.075)],  # bottom
		[Vector3(0.0, -0.038, -0.038), Vector3(0.03, 0.052, 0.024)],# LL
		[Vector3(0.0, 0.038, -0.038), Vector3(0.03, 0.052, 0.024)], # UL
		[Vector3(0.0, 0.0, 0.0), Vector3(0.03, 0.024, 0.075)],     # mid
	]
	for si in segs.size():
		if pat[si] == 0:
			continue
		var off: Vector3 = segs[si][0]
		var sz: Vector3 = segs[si][1]
		_push("digit_seg", "plaque_text", "box", sz,
			Vector3(px, py + off.y, pz + off.z))


# -------------------------------------------------------- street dressing

## One lamppost: column, bracket arm reaching over the kerb, and a lantern head.
## Geometry only — the street runs on a single fixed sun and adding 12 OmniLights
## would cost more than it buys under a permanently overcast midday sky.
func _add_lamppost(x: float, walk_h: float, z: float) -> void:
	var lean := signf(x)   # the arm reaches out over the carriageway
	_push("lamp_column", "concrete", "box",
		Vector3(0.16, LAMP_HEIGHT, 0.16),
		Vector3(x, walk_h + LAMP_HEIGHT * 0.5, z))
	# Bracket arm.
	_push("lamp_arm", "concrete", "box",
		Vector3(0.9, 0.10, 0.10),
		Vector3(x - lean * 0.45, walk_h + LAMP_HEIGHT - 0.12, z))
	# Lantern, canted slightly so it reads as pointing at the road.
	_push("lamp_head", "metal_black", "box",
		Vector3(0.62, 0.14, 0.30),
		Vector3(x - lean * 0.86, walk_h + LAMP_HEIGHT - 0.24, z))


func _build_street_dressing() -> void:
	var zr := KilmoreClose.road_z_range()
	var walk_h := KilmoreClose.WALK_H
	# Street trees in the verge, BOTH sides, at a regular interval. The reference
	# photographs show a mature tree roughly every other house down each side; the
	# previous spacing was 21-28 m with every third one skipped, which left long
	# bare stretches and read as a new estate rather than a 1970s one.
	var z := zr.x + 12.0
	var tree_i := 0
	while z < zr.y - 10.0:
		for side in [KilmoreClose.SIDE_NEAR, KilmoreClose.SIDE_FAR]:
			var s := float(side)
			var tx := s * (KilmoreClose.HALF_WIDTH + 1.15)
			# Stagger the two sides so they do not line up in pairs across the road.
			var jitter := 0.0 if side == KilmoreClose.SIDE_NEAR else 6.5
			_tree_spots.append(Vector3(tx, walk_h, z + jitter))
		z += TREE_SPACING_M
		tree_i += 1

	# Lampposts, alternating sides, offset from the trees so they do not grow out of
	# a canopy. Concrete column, short bracket arm, and a shallow lantern head.
	var lamp_z := zr.x + 22.0
	var lamp_i := 0
	while lamp_z < zr.y - 8.0:
		var ls := float(KilmoreClose.SIDE_NEAR if lamp_i % 2 == 0
			else KilmoreClose.SIDE_FAR)
		_add_lamppost(ls * (KilmoreClose.HALF_WIDTH + 0.62), walk_h, lamp_z)
		lamp_z += LAMP_SPACING_M
		lamp_i += 1

	for h in KilmoreClose.houses():
		if int(h["number"]) % 3 != 1:
			continue
		var s := float(int(h["side"]))
		var gz := KilmoreClose.gate_z(h)
		var bx := s * (KilmoreClose.KERB + 0.45)
		var num := int(h["number"])
		var bin_mat := "bin_red" if num % 5 == 0 else (
			"bin_green" if num % 2 == 0 else "metal_black")
		_add_wheelie_bin(bx, walk_h, gz + 0.6, bin_mat)

	for pz in [38.0, 118.0, 198.0]:
		var px := float(KilmoreClose.SIDE_NEAR) * (KilmoreClose.HALF_WIDTH - 0.55)
		_push("utility_pole", "pipe", "box", Vector3(0.22, 5.5, 0.22),
			Vector3(px, 2.75 + walk_h, pz))

	for wi in range(3):
		var wz := 52.0 + wi * 68.0
		var wh := 4.9 + walk_h
		_push("wire", "metal_black", "box",
			Vector3(KilmoreClose.FACE_X * 1.62, 0.03, 0.03),
			Vector3(0.0, wh, wz))
		_push("wire", "metal_black", "box", Vector3(0.03, 0.03, 16.0),
			Vector3(0.0, wh - 0.35, wz + 8.0))


func _add_wheelie_bin(x: float, walk_h: float, z: float, mat_key: String) -> void:
	_spawn_wheelie_bin(x, walk_h, z, mat_key)


func _spawn_wheelie_bin(x: float, walk_h: float, z: float, mat_key: String) -> void:
	var bin := RigidBody3D.new()
	bin.name = "WheelieBin"
	bin.set_script(_BIN_SCRIPT)
	bin.collision_layer = 1
	bin.collision_mask = 1 | 2 | 4 | 8
	bin.mass = 14.0
	bin.position = Vector3(x, walk_h + 0.41, z)
	var health := Node.new()
	health.name = "Health"
	health.set_script(_HEALTH_SCRIPT)
	health.set("max_hp", 28.0)
	bin.add_child(health)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.48, 0.82, 0.42)
	shape.shape = box
	bin.add_child(shape)
	var colour := _mat_colour(mat_key)
	for part in [
		[Vector3(0.48, 0.82, 0.42), Vector3(0.0, 0.0, 0.0)],
		[Vector3(0.50, 0.10, 0.44), Vector3(0.0, 0.47, 0.0)],
	]:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		mi.mesh = mesh
		mi.material_override = MeshDress.prop_mat(colour, 0.88)
		mi.position = part[1]
		bin.add_child(mi)
	add_child(bin)


func _mat_colour(mat_key: String) -> Color:
	match mat_key:
		"bin_red":
			return Color(0.55, 0.12, 0.10)
		"bin_green":
			return Color(0.12, 0.38, 0.18)
		_:
			return Color(0.12, 0.12, 0.13)


func _spawn_static_trees() -> void:
	var spot_i := 0
	for spot in _tree_spots:
		if _TREE_VARIANTS.is_empty():
			continue
		var wrapper := _DESTRUCTIBLE_TREE.instantiate() as Node3D
		if wrapper == null:
			continue
		wrapper.name = "StreetTree"
		wrapper.position = spot
		wrapper.rotation.y = float(spot_i % 5) * 0.35 - 0.7
		var scene := _TREE_VARIANTS[spot_i % _TREE_VARIANTS.size()]
		var tree := scene.instantiate() as Node3D
		if tree != null:
			wrapper.add_child(tree)
			MeshDress.dress_tree(tree)
			_disable_shadows(tree)
		add_child(wrapper)
		spot_i += 1


func _spawn_garden_bushes() -> void:
	if _BUSH_MESH == null:
		return
	for i in _lawn_spots.size():
		if i % 3 != 1:
			continue
		var centre := _lawn_spots[i] as Vector3
		var size := _lawn_sizes[i] as Vector2
		var bush := _BUSH_MESH.instantiate() as Node3D
		if bush == null:
			continue
		bush.name = "GardenBush"
		var jitter_x := (float((i * 5) % 7) - 3.0) * size.x * 0.08
		var jitter_z := (float((i * 3) % 5) - 2.0) * size.y * 0.08
		bush.position = Vector3(centre.x + jitter_x, centre.y, centre.z + jitter_z)
		bush.rotation.y = float(i % 8) * (TAU / 8.0)
		var scale := 0.85 + float(i % 4) * 0.08
		bush.scale = Vector3.ONE * scale
		MeshDress.dress_bush(bush)
		_disable_shadows(bush)
		add_child(bush)


## SimpleGrassTextured blades on garden lawns, remnant patches, and verges.
func _spawn_detail_grass() -> void:
	var grass_script: Script = load("res://addons/simplegrasstextured/grass.gd") as Script
	if grass_script == null:
		push_warning("SimpleGrassTextured missing — skipping blade scatter")
		return

	var lawn_node: MultiMeshInstance3D = grass_script.new() as MultiMeshInstance3D
	lawn_node.name = "LawnBlades"
	lawn_node.set("interactive", false)
	add_child(lawn_node)
	_configure_sgt(lawn_node, Color(0.72, 0.80, 0.55), 0.50, 0.65)

	var verge_node: MultiMeshInstance3D = grass_script.new() as MultiMeshInstance3D
	verge_node.name = "VergeBlades"
	verge_node.set("interactive", false)
	add_child(verge_node)
	_configure_sgt(verge_node, Color(0.62, 0.70, 0.48), 0.38, 0.55)

	var up := Vector3.UP
	var blade_budget := 1200
	var blades := 0

	# Full front gardens — ~7 blades each × 52 houses.
	for i in _garden_rects.size():
		if blades >= blade_budget:
			break
		var rect: Dictionary = _garden_rects[i]
		var centre: Vector3 = rect["centre"]
		var sz: Vector2 = rect["size"]
		var seed_i := i * 23 + 7
		for k in 7:
			if blades >= blade_budget:
				break
			var fx := _hash01(seed_i + k * 3) - 0.5
			var fz := _hash01(seed_i + k * 3 + 1) - 0.5
			var pos := centre + Vector3(fx * sz.x, 0.0, fz * sz.y)
			var sc := 0.72 + _hash01(seed_i + k * 3 + 2) * 0.38
			lawn_node.call("add_grass", pos, up, Vector3(sc, sc, sc),
				_hash01(seed_i + k) * TAU)
			blades += 1

	# Remnant lawn patches (same material, extra density).
	for i in _lawn_spots.size():
		if blades >= blade_budget:
			break
		var centre: Vector3 = _lawn_spots[i]
		var sz: Vector2 = _lawn_sizes[i]
		var seed_i := i * 17 + 3
		for k in 4:
			if blades >= blade_budget:
				break
			var fx := _hash01(seed_i + k * 3) - 0.5
			var fz := _hash01(seed_i + k * 3 + 1) - 0.5
			var pos := centre + Vector3(fx * sz.x, 0.0, fz * sz.y)
			var sc := 0.75 + _hash01(seed_i + k * 3 + 2) * 0.35
			lawn_node.call("add_grass", pos, up, Vector3(sc, sc, sc),
				_hash01(seed_i + k) * TAU)
			blades += 1

	# Roadside + footpath verges: both sides, every ~2.8 m.
	var zr := KilmoreClose.road_z_range()
	var z := zr.x + 4.0
	var vi := 0
	while z < zr.y - 4.0 and blades < blade_budget:
		for side in [KilmoreClose.SIDE_NEAR, KilmoreClose.SIDE_FAR]:
			if blades >= blade_budget:
				break
			var s := float(side)
			var road_vx := s * (KilmoreClose.HALF_WIDTH + 0.38)
			var path_vx := s * (KilmoreClose.KERB + 0.12)
			for k in 2:
				if blades >= blade_budget:
					break
				var oz := (_hash01(vi * 11 + k) - 0.5) * 0.35
				var ox := (_hash01(vi * 11 + k + 5) - 0.5) * 0.18
				var pos_r := Vector3(road_vx + ox, _verge_y + 0.08, z + oz)
				var sc_r := 0.55 + _hash01(vi + k) * 0.25
				verge_node.call("add_grass", pos_r, up, Vector3(sc_r, sc_r, sc_r),
					_hash01(vi * 7 + k) * TAU)
				blades += 1
				var pos_p := Vector3(path_vx + ox * 0.6, _footpath_verge_y + 0.06, z + oz)
				var sc_p := 0.50 + _hash01(vi + k + 3) * 0.22
				verge_node.call("add_grass", pos_p, up, Vector3(sc_p, sc_p, sc_p),
					_hash01(vi * 9 + k) * TAU)
				blades += 1
			vi += 1
		z += 2.8

	lawn_node.call("_update_multimesh")
	verge_node.call("_update_multimesh")


func _configure_sgt(node: MultiMeshInstance3D, albedo: Color, h: float, w: float) -> void:
	node.set("interactive", false)
	node.set("optimization_by_distance", true)
	node.set("optimization_dist_min", 14.0)
	node.set("optimization_dist_max", 48.0)
	node.set("optimization_level", 7.0)
	node.set("scale_h", h)
	node.set("scale_w", w)
	node.set("scale_var", -0.2)
	node.set("grass_strength", 0.75)
	node.set("albedo", albedo)
	node.set("sgt_dist_min", 0.28)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _hash01(n: int) -> float:
	# Deterministic 0..1 — no Math.random / no ctx.rng in this Godot port file.
	var x := (n * 1103515245 + 12345) & 0x7fffffff
	return float(x) / 2147483647.0


func _spawn_static_cars() -> void:
	park_slots.clear()
	var park_yaw := PI * 0.5
	var spots: Array = [
		[Vector3(-(KilmoreClose.HALF_WIDTH - 0.95), 0.0, 22.0), park_yaw],
		[Vector3(-(KilmoreClose.HALF_WIDTH - 0.95), 0.0, 30.0), park_yaw],
		[Vector3(KilmoreClose.HALF_WIDTH - 0.95, 0.0, 52.0), -park_yaw],
		[Vector3(KilmoreClose.HALF_WIDTH - 0.95, 0.0, 68.0), -park_yaw],
		[Vector3(-(KilmoreClose.HALF_WIDTH - 0.95), 0.0, 98.0), park_yaw + 0.02],
		[Vector3(KilmoreClose.HALF_WIDTH - 0.95, 0.0, 118.0), -park_yaw],
		[Vector3(-(KilmoreClose.HALF_WIDTH - 0.95), 0.0, 142.0), park_yaw + 0.04],
		[Vector3(KilmoreClose.HALF_WIDTH - 0.95, 0.0, 162.0), -park_yaw - 0.02],
		[Vector3(-(KilmoreClose.HALF_WIDTH - 0.95), 0.0, 188.0), -park_yaw - 0.03],
		[Vector3(KilmoreClose.HALF_WIDTH - 0.95, 0.0, 188.0), -park_yaw - 0.03],
		[Vector3(-(KilmoreClose.HALF_WIDTH - 0.95), 0.0, 210.0), park_yaw],
		[Vector3(KilmoreClose.HALF_WIDTH - 0.95, 0.0, 228.0), -park_yaw],
		[Vector3(-(KilmoreClose.HALF_WIDTH - 0.95), 0.0, 228.0), park_yaw],
		[Vector3(KilmoreClose.HALF_WIDTH - 0.95, 0.0, 248.0), -park_yaw + 0.03],
	]
	for i in spots.size():
		var spot: Array = spots[i]
		_place_static_car(spot[0] as Vector3, spot[1] as float, i, true)


func _spawn_driveway_cars() -> void:
	var paint_i := 20
	for spot in _driveway_spots:
		var pos: Vector3 = spot["pos"]
		if _kerb_slot_near(pos.z, 3.5):
			continue
		var yaw: float = spot["yaw"]
		_place_static_car(pos, yaw, paint_i, false)
		paint_i += 1


func _kerb_slot_near(z: float, radius: float) -> bool:
	for slot in park_slots:
		var t: Transform3D = slot["transform"]
		if absf(t.origin.z - z) < radius:
			return true
	return false


func _place_static_car(pos: Vector3, yaw: float, paint_i: int, possessable: bool) -> void:
	var car := _CAR_MESH.instantiate() as Node3D
	if car == null:
		return
	car.name = "ParkedCar" if possessable else "DrivewayCar"
	car.position = pos
	car.rotation.y = yaw
	MeshDress.dress_car(car, _CAR_PAINTS[paint_i % _CAR_PAINTS.size()])
	_disable_shadows(car)
	add_child(car)
	if possessable:
		var coll := _static_box(Vector3(1.95, 1.5, 4.1), pos + Vector3(0.0, 0.75, 0.0))
		park_slots.append({
			"transform": Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), pos),
			"visual": car,
			"collider": coll,
			"claimed": false,
		})


func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)


# ----------------------------------------------------- the pair, and the house

## The shared shell of a joined semi-detached PAIR: one wall block, one band,
## one pitched roof, two chimneys. Built per pair rather than per dwelling
## because that is what the building physically is — two houses under one roof
## with no seam down the middle.
func _add_pair_shell(p: Dictionary) -> void:
	var c: Vector3 = p["centre"]
	var wall_h := KilmoreClose.WALL_H
	var floor_h := KilmoreClose.FLOOR_H
	var upper_h := wall_h - floor_h
	var depth := KilmoreClose.HOUSE_D
	var width := KilmoreClose.PAIR_W
	var wing_w := KilmoreClose.GARAGE_W
	var upper_w := width - 2.0 * wing_w

	# Wall block — ground floor full width; first floor only over the inner span
	# so the garage wings at each pair end read as single-storey.
	_push("wall", "dash", "box",
		Vector3(depth, floor_h, width),
		Vector3(c.x, floor_h * 0.5, c.z))
	if upper_h > 0.05 and upper_w > 0.05:
		_push("wall", "dash", "box",
			Vector3(depth, upper_h, upper_w),
			Vector3(c.x, floor_h + upper_h * 0.5, c.z))
	# Brick course around the base, stood slightly proud of the pebbledash. Height
	# 0.85 rather than 0.9: at 0.9 its top clipped 0.03 m off the bottom of the
	# ground-floor window frame, which starts at WIN_LO_SILL - 0.08 = 0.87.
	_push("band", "band", "box",
		Vector3(depth + 0.10, 0.85, width + 0.10),
		Vector3(c.x, 0.425, c.z))
	# Pitched roof, ridge along the street, with a small eave overhang. ROOF_H over
	# half the prism depth (~4.55 m) is ~24° — interlocking tile pitch on these semis.
	_push("roof", "roof", "prism",
		Vector3(depth + 0.6, KilmoreClose.ROOF_H, upper_w + 0.4),
		Vector3(c.x, wall_h + KilmoreClose.ROOF_H * 0.5, c.z))
	# Painted fascia board under the eaves — the pale line running under every roof
	# edge in the reference. Sits proud of the gutter so it reads as the board the
	# gutter is fixed to. Shortened to match the upper wall — no eaves line over
	# the single-storey garage wings.
	_push("fascia", "fascia", "box",
		Vector3(depth + 0.62, 0.16, upper_w + 0.42),
		Vector3(c.x, wall_h + 0.08, c.z))
	# Gutter, hung on the fascia.
	_push("gutter", "pipe", "box",
		Vector3(depth + 0.66, 0.09, upper_w + 0.46),
		Vector3(c.x, wall_h - 0.02, c.z))
	# A chimney at each gable end of the pair. Rendered and painted like the house
	# rather than exposed brick — in the reference the stack is the same pale render
	# as the walls, weathered greyer, finished with a plain concrete capping slab
	# and two squat pots. It used to be red brick, which is the wrong material and
	# the wrong period.
	var stack_h := 1.7
	for sgn in [-1.0, 1.0]:
		var stack_z: float = c.z + sgn * (upper_w * 0.5 - 0.75)
		var stack_top := wall_h + KilmoreClose.ROOF_H * 0.55 + stack_h * 0.5
		_push("chimney", "chimney", "box",
			Vector3(0.9, stack_h, 0.7),
			Vector3(c.x, wall_h + KilmoreClose.ROOF_H * 0.55, stack_z))
		# Capping slab, oversailing the stack slightly so it throws a shadow line.
		_push("chimney_cap", "concrete", "box",
			Vector3(1.0, 0.12, 0.8),
			Vector3(c.x, stack_top + 0.06, stack_z))
		# Two clay pots on the slab.
		for pot in [-1.0, 1.0]:
			_push("chimney_pot", "concrete", "box",
				Vector3(0.26, 0.34, 0.26),
				Vector3(c.x, stack_top + 0.29, stack_z + pot * 0.17))

	# Collision: one box for the pair's wall block (visual upper storey is trimmed,
	# but solidity stays one volume for the collision budget).
	_static_box(Vector3(depth, wall_h, width), Vector3(c.x, wall_h * 0.5, c.z))

	# And an occluder on the same volume. With 5 m walls down both sides of a
	# 7.6 m carriageway, a street-level camera has the far row's interior
	# geometry — windows, porches, garages, gate piers — almost entirely hidden
	# behind the near row. Requires occlusion_culling/use_occlusion_culling.
	_add_occluder(Vector3(depth, wall_h, width), Vector3(c.x, wall_h * 0.5, c.z))


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

	_add_porch(face_x, out, z + KilmoreClose.door_along(mirror), int(h["number"]))
	_add_garage(face_x, out, _garage_along_z(h))
	_add_facade_trim(face_x, out, h)
	_add_downpipe(face_x, out, z, mirror)


## The brick spandrel between the window tiers, plus the brick head over the door.
##
## Both of these used to sit ON their opening rather than beside it. The spandrel
## was centred at FLOOR_H + 1.55 = 4.15 with a height of 1.15, i.e. y 3.575–4.725,
## while the first-floor glass spans 3.48–4.72 — a 92% overlap, and at 0.08 proud
## it was coplanar with the glass, so the brick z-fought its way over the window.
##
## The correct band is the bare pebbledash gap between the tiers: the ground-floor
## window frame tops out at WIN_LO_SILL + WIN_LO_H + 0.08 = 2.43 and the
## first-floor frame starts at WIN_HI_SILL - 0.08 = 3.37. Centre 2.90, height 0.94
## fills exactly that and touches neither.
func _add_facade_trim(face_x: float, out: float, h: Dictionary) -> void:
	var z: float = h["z"]
	var mirror: bool = h["mirror"]
	var lo_frame_top := KilmoreClose.WIN_LO_SILL + KilmoreClose.WIN_LO_H + 0.08
	var hi_frame_bottom := KilmoreClose.WIN_HI_SILL - 0.08
	var panel_h := hi_frame_bottom - lo_frame_top
	var panel_y := (lo_frame_top + hi_frame_bottom) * 0.5
	# Inner frontage only — stop short of the single-storey garage bay.
	var garage_z := _garage_along_z(h)
	var garage_sign := signf(garage_z - z if absf(garage_z - z) > 0.01 else 1.0)
	var panel_w := (KilmoreClose.HOUSE_W - KilmoreClose.GARAGE_W) * 0.72
	var panel_z := z - garage_sign * KilmoreClose.GARAGE_W * 0.22
	_push("band_mid", "band_mid", "box",
		Vector3(0.08, panel_h, panel_w),
		Vector3(face_x + out * 0.04, panel_y, panel_z))

	# Brick head over the front door. This was a full-height 0.10–2.40 slab that
	# sat coplanar with the door leaf and rendered over it; the brick jambs either
	# side already exist as `porch_brick` in _add_porch(), so all that was missing
	# is the panel above the opening.
	var door_z := z + KilmoreClose.door_along(mirror)
	var door_top := KilmoreClose.DOOR_H + 0.14
	var head_h := KilmoreClose.PORCH_H - door_top
	if head_h > 0.05:
		_push("porch_panel", "band_mid", "box",
			Vector3(0.07, head_h, KilmoreClose.PORCH_W + 0.1),
			Vector3(face_x + out * 0.05, door_top + head_h * 0.5, door_z))


func _add_downpipe(face_x: float, out: float, z: float, mirror: bool) -> void:
	var half := KilmoreClose.HOUSE_W * 0.5
	var along := half * 0.82 if mirror else -half * 0.82
	var wall_h := KilmoreClose.WALL_H
	_push("downpipe", "pipe", "box",
		Vector3(0.06, wall_h - 0.4, 0.06),
		Vector3(face_x + out * 0.10, wall_h * 0.5, z + along))


func _add_window(face_x: float, out: float, z: float, sill: float,
		w: float, h: float) -> void:
	var y := sill + h * 0.5
	_push("win_frame", "frame", "box",
		Vector3(0.06, h + 0.16, w + 0.16),
		Vector3(face_x + out * 0.03, y, z))
	_push("win_sill", "frame", "box",
		Vector3(0.08, 0.06, w + 0.22),
		Vector3(face_x + out * 0.04, sill, z))
	# Tripartite glazing: two mullions, three panes.
	var pane_w := (w - 0.10) / 3.0
	var pane_x := [-w * 0.33, 0.0, w * 0.33]
	for px in pane_x:
		_push("win_glass", "glass", "box",
			Vector3(0.04, h - 0.06, pane_w),
			Vector3(face_x + out * 0.06, y, z + px))
	for mx in [-w * 0.165, w * 0.165]:
		_push("win_mullion", "frame", "box",
			Vector3(0.05, h - 0.04, 0.05),
			Vector3(face_x + out * 0.055, y, z + mx))


func _add_door(face_x: float, out: float, z: float, is_home: bool) -> void:
	var dh := KilmoreClose.DOOR_H
	var dw := KilmoreClose.DOOR_W
	_push("door_frame", "frame", "box",
		Vector3(0.06, dh + 0.14, dw + 0.14),
		Vector3(face_x + out * 0.03, (dh + 0.14) * 0.5, z))
	var key := "door_home" if is_home else "door_leaf"
	var mat := "door_home" if is_home else "door"
	_push(key, mat, "box",
		Vector3(0.05, dh, dw),
		Vector3(face_x + out * 0.06, dh * 0.5, z))
	if is_home:
		_push("mailbox", "metal_black", "box",
			Vector3(0.08, 0.22, 0.16),
			Vector3(face_x + out * 0.12, 1.35, z + dw * 0.55))
		_push_gate_digits(face_x + out * 0.10, dh * 0.62, z, out, 18)


## Porch: a shallow box projecting from the front wall, with a glazed sliding
## door across its face and a flat lid.
func _add_porch(face_x: float, out: float, z: float, _number: int) -> void:
	var pd := KilmoreClose.PORCH_D
	var pw := KilmoreClose.PORCH_W
	var ph := KilmoreClose.PORCH_H
	var cx := face_x + out * (pd * 0.5)
	var glass_h := ph - 0.28

	# Brick porch surround (reference no. 19).
	for sgn in [-1.0, 1.0]:
		_push("porch_brick", "brick_red", "box",
			Vector3(pd + 0.06, ph, 0.22),
			Vector3(cx, ph * 0.5, z + sgn * (pw * 0.5 + 0.02)))
	# Pebbledash side cheeks inside the brick frame.
	for sgn in [-1.0, 1.0]:
		_push("porch_side", "dash", "box",
			Vector3(pd, ph, 0.14),
			Vector3(cx, ph * 0.5, z + sgn * (pw * 0.5 - 0.10)))
	# Lean-to tiled porch roof (reference porches).
	_push("porch_roof", "roof", "prism",
		Vector3(pd + 0.18, 0.32, pw + 0.22),
		Vector3(cx, ph + 0.16, z))
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
## The side garage: SINGLE STOREY, projecting only slightly past the front wall.
##
## Two bugs, in sequence. It was originally centred at `face_x + out * (gd * 0.5)`,
## putting all 5.4 m of depth in FRONT of the wall — the garage stood out in the
## middle of the front garden. Pulling it fully behind the wall then hid it inside
## the two-storey volume, so all you saw was a door on a 5.2 m wall and the garage
## read as two storeys tall.
##
## The reference has it as a low flat-roofed lean-to against the house, its front
## roughly in line with the porch, with the two-storey wall rising behind and its
## own roof line clearly visible. So it projects `PROUD` — about the porch depth —
## and the rest of its length runs back alongside the dwelling.
func _add_garage(face_x: float, out: float, z: float) -> void:
	var gd := KilmoreClose.GARAGE_D
	var gw := KilmoreClose.GARAGE_W
	var gh := KilmoreClose.GARAGE_H
	# How far the garage front stands ahead of the main wall.
	var proud := 1.4
	var cx := face_x + out * (proud - gd * 0.5)
	var front_x := face_x + out * proud

	_push("garage", "dash", "box",
		Vector3(gd, gh, gw), Vector3(cx, gh * 0.5, z))
	# Flat roof with a coping edge — this is what makes it read as single storey
	# against the two-storey wall behind, so it must stay visible.
	_push("garage_lid", "concrete", "box",
		Vector3(gd + 0.18, 0.16, gw + 0.18), Vector3(cx, gh + 0.08, z))
	# The door, on the street-facing end.
	_push("garage_door", "garage_door", "box",
		Vector3(0.08, gh - 0.30, gw - 0.22),
		Vector3(front_x + out * 0.04, (gh - 0.30) * 0.5, z))
	# Lintel row of three small panes above the garage door.
	var lintel_y := gh - 0.08
	var lintel_w := (gw - 0.40) / 3.0
	for li in [-1, 0, 1]:
		_push("garage_lintel", "glass", "box",
			Vector3(0.06, 0.18, lintel_w),
			Vector3(front_x + out * 0.06, lintel_y, z + li * (lintel_w + 0.04)))
	# Visual only — pair wall collision blocks the dwelling; garage is set dressing.

## KILMORE CLOSE — the measured street, as data.
##
## This is the one thing carried over from the Three.js prototype essentially
## intact, because it is the only part of that project that is *evidence* rather
## than implementation: a set of real measurements of a real Dublin street.
## Everything else (rendering, physics, AI, materials) is being rebuilt in
## Godot, but these numbers must not drift, or the place stops being Kilmore
## Close.
##
## Ported from `src/world/layout.js`. The provenance notes there are worth
## reading in full; the short version:
##
##   16.55 m  one joined semi-detached PAIR    (measured)
##    3.00 m  gap between pairs, where the garages stand   (measured)
##    7.63 m  carriageway, no footpaths -> HALF_WIDTH 3.815 (measured)
##    8.71 m  front garden depth -> SETBACK    (measured)
##  304.69 m  full road length                 (measured)
##       13   joined pairs per side            (from the map)
##
## NOT measured, carried across as set-dressing decisions: plot depth, floor
## count, wall materials, and the house archetype itself.
##
## NOT AVAILABLE ANYWHERE: real house numbers. OSM carries zero
## `addr:housenumber` for this street. The evens/odds numbering below is a
## documented convention inherited from the prototype, not a survey fact. It is
## what puts David outside number 18.
##
## COORDINATE FRAME (Godot, right-handed, Y up):
##   +Z runs up the street (the long axis)
##   +X / -X are the two sides of the road
##   the carriageway is centred on x = 0
## This matches the prototype's LEVEL space, so every number below transfers
## without a projection step. Real-world compass bearing is not preserved — it
## was not preserved in the prototype either, and nothing depends on it.

class_name KilmoreClose
extends RefCounted

# ---------------------------------------------------------------- carriageway

## Half the carriageway. Full width reads 7.63 m.
const HALF_WIDTH := 3.815
## Kerb line: carriageway + a 2.0 m footpath strip.
const KERB := 5.815
## Kerb upstand. A residential estate is laid to a 125 mm kerb face.
const WALK_H := 0.125
## Front-garden depth, kerb line to house face.
const SETBACK := 8.71

# --------------------------------------------------------------------- houses

## Measured width of one joined semi-detached PAIR.
const PAIR_W := 16.55
## One dwelling's frontage — half a pair, since the two are joined.
const HOUSE_W := PAIR_W / 2.0            # 8.275
## Gap between adjacent pairs. Reads as the side-passage / garage gap.
const PAIR_GAP := 3.0
## Pair-to-pair pitch along the street.
const PITCH := PAIR_W + PAIR_GAP         # 19.55
## Pairs per side over the full street.
const PAIRS_PER_SIDE := 13
## Plot depth, perpendicular to the street. Provisional — never measured.
const HOUSE_D := 8.5
## Storey height and storey count. Provisional.
const FLOOR_H := 2.6
const FLOORS := 2
## Wall height to the eaves.
const WALL_H := FLOOR_H * FLOORS         # 5.2
## Ridge height above the eaves.
const ROOF_H := 1.9

## House front face, and house box centre, as distances from the road centre.
const FACE_X := KERB + SETBACK           # 14.525
const CENTRE_X := FACE_X + HOUSE_D / 2.0 # 18.775

## Full housing run: 12 gaps + 13 pair widths = 251.15 m.
const HOUSING_RUN := (PAIRS_PER_SIDE - 1) * PITCH + PAIR_W

# ----------------------------------------------------------------- the slice
#
# Phase 2 builds the full measured street: all 13 joined pairs per side (52
# dwellings). David still spawns outside number 18; spacing and setbacks are
# unchanged from phase 1 — only the pair range widens.

## First and last pair index (0-based) included in the built street.
const SLICE_FIRST_PAIR := 0
const SLICE_LAST_PAIR := 12
## How far the drawn carriageway runs past the end of the slice's houses.
const SLICE_ROAD_MARGIN := 12.0

# ------------------------------------------------------------------- archetype
#
# THE CANONICAL KILMORE CLOSE HOUSE. There is no second building type on this
# street. Stated once, here, so it cannot drift house by house.
#
#   white pebbledash front over a painted band
#   two windows upstairs
#   one window downstairs, beside the front door
#   a porch with a glazed sliding door
#   a single-storey garage at the outer end of the frontage

## Bay divisions across one dwelling's frontage. round(8.275 / 3.05) == 3,
## which is what yields exactly two upper windows and one lower + door.
const BAY_DIVISOR := 3.05

const PORCH_W := 1.9
const PORCH_D := 1.5
const PORCH_H := 2.5

## Garage footprint. The prototype carried 2.6 x 2.5, which is shed-sized and
## was explicitly flagged there as provisional set-dressing rather than a
## measurement. Deepened to 5.4 m so it reads as something you could actually
## put a car in; at 5.4 m it still leaves 3.3 m of the 8.71 m front garden.
const GARAGE_W := 2.7
const GARAGE_D := 5.4
const GARAGE_H := 2.4

const DOOR_W := 0.95
const DOOR_H := 2.05
## Ground-floor window: wide, low sill. Upper: narrower, higher sill.
const WIN_LO_W := 1.75
const WIN_LO_H := 1.4
const WIN_LO_SILL := 0.95
const WIN_HI_W := 1.2
const WIN_HI_H := 1.3
const WIN_HI_SILL := FLOOR_H + 0.85      # 3.45

# ------------------------------------------------------------------ addresses

## The address the slice is built around.
const DAVID_HOUSE := 18

## Side identifiers. NEAR is the -X row (even numbers), FAR is +X (odds).
## Both rows are numbered from the same end, so `n` faces `n + 1` across the
## road. This is the local convention, and it is a convention, not a survey.
const SIDE_NEAR := -1
const SIDE_FAR := 1


## Number of window/door bays across one dwelling's frontage.
static func bay_count() -> int:
	return maxi(1, roundi(HOUSE_W / BAY_DIVISOR))


## Centre of bay `b`, in frontage-local metres (0 == centre of the frontage).
static func bay_centre(b: int) -> float:
	var n := bay_count()
	return -HOUSE_W / 2.0 + (float(b) + 0.5) * (HOUSE_W / float(n))


## Offset of the front door — and therefore the porch, the garden gate, the
## garden path and the number on the pier — from the centre of a dwelling's
## frontage.
##
## Lives here rather than in the builder because it is not only a rendering
## detail: it is where the front of the house actually IS. Spawn positions are
## derived from it too, and when this was defined only inside the builder,
## David spawned at the centre of his frontage — 2.76 m up the street from his
## own gate, standing in front of next door.
static func door_along(mirror: bool) -> float:
	var n := bay_count()
	var half := HOUSE_W / 2.0
	var door_bay := (n - 1) if mirror else 0
	var limit := half - PORCH_W / 2.0
	return clampf(bay_centre(door_bay), -limit, limit)


## Street-axis position of a house's garden gate.
static func gate_z(h: Dictionary) -> float:
	return float(h["z"]) + door_along(bool(h["mirror"]))


## Street-axis (Z) centre of dwelling index `i` on a side, where `i` counts
## dwellings from the low-Z end: i == p * 2 + k for pair p, half k.
static func dwelling_z(i: int) -> float:
	var p := i / 2          # integer division — pair index
	var k := i % 2          # 0 == low-Z half of the pair, 1 == high-Z half
	return float(p) * PITCH + float(k) * HOUSE_W + HOUSE_W / 2.0


## House number of dwelling index `i` on `side` (SIDE_NEAR / SIDE_FAR).
static func house_number(side: int, i: int) -> int:
	# Near side runs evens from 2, far side odds from 1.
	return (2 if side == SIDE_NEAR else 1) + i * 2


## Every dwelling in the slice, as a table of plain dictionaries.
##
## Each entry carries everything the builder needs and nothing it does not:
##
##   number       int    Kilmore Close house number
##   side         int    SIDE_NEAR (-1) or SIDE_FAR (+1)
##   pair         int    pair index along the street
##   centre       Vector3  house box centre, at ground level
##   face_x       float  X of the street-facing wall
##   front        Vector3  unit vector from the house toward the road
##   z            float  street-axis centre of this dwelling
##   mirror       bool   true for the low-Z half of a pair — its door sits at
##                       the high-Z end of its frontage, so the two doors of a
##                       pair meet at the party wall and the two garages land
##                       on the OUTER ends, in the gap between pairs. Without
##                       this, 13 pairs read as one long terrace.
static func houses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for side in [SIDE_NEAR, SIDE_FAR]:
		for p in range(SLICE_FIRST_PAIR, SLICE_LAST_PAIR + 1):
			for k in 2:
				var i := p * 2 + k
				var z := dwelling_z(i)
				var cx := float(side) * CENTRE_X
				out.append({
					"number": house_number(side, i),
					"side": side,
					"pair": p,
					"z": z,
					"centre": Vector3(cx, 0.0, z),
					"face_x": float(side) * FACE_X,
					"front": Vector3(-float(side), 0.0, 0.0),
					"mirror": k == 0,
				})
	return out


## The pairs in the slice, as [side, pair_index, z_centre_of_pair].
static func pairs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for side in [SIDE_NEAR, SIDE_FAR]:
		for p in range(SLICE_FIRST_PAIR, SLICE_LAST_PAIR + 1):
			out.append({
				"side": side,
				"pair": p,
				"z": float(p) * PITCH + PAIR_W / 2.0,
				"centre": Vector3(float(side) * CENTRE_X, 0.0,
					float(p) * PITCH + PAIR_W / 2.0),
			})
	return out


## Look a slice house up by its number. Returns an empty dictionary if the
## number is outside the built stretch.
static func house_by_number(number: int) -> Dictionary:
	for h in houses():
		if h["number"] == number:
			return h
	return {}


## Z extent of the drawn carriageway for the slice.
static func road_z_range() -> Vector2:
	var z0 := float(SLICE_FIRST_PAIR) * PITCH - SLICE_ROAD_MARGIN
	var z1 := float(SLICE_LAST_PAIR) * PITCH + PAIR_W + SLICE_ROAD_MARGIN
	return Vector2(z0, z1)


## Where David starts: on the footpath outside his own front garden, facing
## the house. Falls back to the road centre if 18 is somehow outside the slice.
static func david_spawn() -> Transform3D:
	var h := house_by_number(DAVID_HOUSE)
	if h.is_empty():
		return Transform3D.IDENTITY
	var side := int(h["side"])
	# Mid-footpath: between the carriageway edge and the kerb line.
	var x := float(side) * (HALF_WIDTH + KERB) * 0.5
	# Squarely outside his own GATE, not the centre of his frontage — those are
	# 2.76 m apart, which is a whole house-width's worth of standing in front of
	# the wrong door.
	var pos := Vector3(x, 0.0, gate_z(h))
	# Face the house — i.e. away from the road — so the number on the gate pier
	# is the first thing on screen.
	var look := Vector3(float(side), 0.0, 0.0)
	return _looking_at(pos, look)


## Where the car is parked: at the kerb outside 18, nose up the street (+Z).
static func car_spawn() -> Transform3D:
	var h := house_by_number(DAVID_HOUSE)
	if h.is_empty():
		return _looking_at(Vector3(HALF_WIDTH - 0.95, 0.0, 84.0),
			Vector3(0.0, 0.0, 1.0))
	var side := int(h["side"])
	# Just up from his gate, so it is plainly "the car outside 18" and not
	# ambiguous between two houses.
	var z := gate_z(h) + 1.6
	# Parked against the kerb: body half-width (~0.9 m) in from the carriageway
	# edge, so the near flank sits on the channel line.
	var x := float(side) * (HALF_WIDTH - 0.95)
	return _looking_at(Vector3(x, 0.0, z), Vector3(0.0, 0.0, 1.0))


## Build a Transform3D at `pos` whose -Z (Godot forward) points along `fwd`.
static func _looking_at(pos: Vector3, fwd: Vector3) -> Transform3D:
	var f := fwd.normalized()
	var basis := Basis.looking_at(f, Vector3.UP)
	return Transform3D(basis, pos)

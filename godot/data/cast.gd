## KILMORE CAST — named residents and their house numbers.
##
## Ported from the Three.js roster in `src/ai/index.js`. David (the player) is
## intentionally absent. Phase 2 stages these as idle street presence only —
## no pathfinding, no combat AI, no missions.

class_name KilmoreCast
extends RefCounted

## One cast entry: display name, house number, optional gate offset (metres along
## +Z from the house gate when two people share a door).
const ROSTER: Array[Dictionary] = [
	{"name": "MickMcCabe", "house": 14, "gate_z_offset": -0.45,
		"jacket": Color(0.22, 0.28, 0.36)},
	{"name": "Deco McCabe", "house": 14, "gate_z_offset": 0.45,
		"jacket": Color(0.35, 0.22, 0.18)},
	{"name": "Oysters", "house": 26, "gate_z_offset": 0.0,
		"jacket": Color(0.42, 0.38, 0.34)},
	{"name": "Angela Carpenter", "house": 27, "gate_z_offset": 0.0,
		"jacket": Color(0.55, 0.28, 0.32)},
	{"name": "Paddy Mason", "house": 31, "gate_z_offset": 0.0,
		"jacket": Color(0.18, 0.32, 0.24)},
]


static func members() -> Array[Dictionary]:
	return ROSTER.duplicate()


## Footpath position outside a cast member's gate, facing the house.
static func doorstep(entry: Dictionary) -> Transform3D:
	var h := KilmoreClose.house_by_number(int(entry["house"]))
	if h.is_empty():
		return Transform3D.IDENTITY
	var side := int(h["side"])
	var x := float(side) * (KilmoreClose.HALF_WIDTH + KilmoreClose.KERB) * 0.5
	var z := KilmoreClose.gate_z(h) + float(entry.get("gate_z_offset", 0.0))
	var pos := Vector3(x, KilmoreClose.WALK_H, z)
	var look := Vector3(float(side), 0.0, 0.0)
	var f := look.normalized()
	var basis := Basis.looking_at(f, Vector3.UP)
	return Transform3D(basis, pos)

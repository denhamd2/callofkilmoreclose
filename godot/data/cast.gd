## KILMORE CAST — named residents and their house numbers.
##
## Ported from the Three.js roster in `src/ai/index.js`. David (the player) is
## intentionally absent. Phase 2 stages these as idle street presence only —
## no pathfinding, no combat AI, no missions.

class_name KilmoreCast
extends RefCounted

## One cast entry: display name, house number, optional gate offset (metres along
## +Z from the house gate when two people share a door), jacket tint, faction and
## weapon.
##
## The McCabes share number 14 and stand against the rest of the road; David
## sides against them. Loadouts are mixed on purpose — an all-firearms street
## resolves into a shootout in about two seconds, whereas a mix keeps fists in
## play and lets the brawl read as a neighbourhood row.
const ROSTER: Array[Dictionary] = [
	{"name": "MickMcCabe", "house": 14, "gate_z_offset": -0.45,
		"jacket": Color(0.22, 0.28, 0.36),
		"faction": Factions.MCCABE, "weapon": &"pistol"},
	{"name": "Deco McCabe", "house": 14, "gate_z_offset": 0.45,
		"jacket": Color(0.35, 0.22, 0.18),
		"faction": Factions.MCCABE, "weapon": WeaponCatalog.UNARMED},
	{"name": "Oysters", "house": 26, "gate_z_offset": 0.0,
		"jacket": Color(0.42, 0.38, 0.34),
		"faction": Factions.RESIDENTS, "weapon": &"shotgun"},
	{"name": "Angela Carpenter", "house": 27, "gate_z_offset": 0.0,
		"jacket": Color(0.55, 0.28, 0.32),
		"faction": Factions.RESIDENTS, "weapon": WeaponCatalog.UNARMED},
	{"name": "Paddy Mason", "house": 31, "gate_z_offset": 0.0,
		"jacket": Color(0.18, 0.32, 0.24),
		"faction": Factions.RESIDENTS, "weapon": &"mac10"},
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
	# A settle margin, matching main.gd's SETTLE for David and the dummy. Spawning
	# flush with the pavement leaves no room for the first depenetration tick.
	var pos := Vector3(x, KilmoreClose.WALK_H + 0.3, z)
	var look := Vector3(float(side), 0.0, 0.0)
	var f := look.normalized()
	var basis := Basis.looking_at(f, Vector3.UP)
	return Transform3D(basis, pos)

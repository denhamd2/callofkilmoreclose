## Static weapon definitions — Styloo gun meshes + combat tuning.
##
## BALANCE NOTE. `fire_damage` here is roughly half what it was. Against 100 hp the
## original figures — shotgun 48, MAC-10 16 every 0.14 s = 114 dps — killed a
## neighbour, or the player, in about a second, so a street fight was over before
## it read as one. Halved, plus the raised actor health in `Health.max_hp`, a scrap
## runs long enough to watch and to join in on. Damage is shared between the player
## and `CombatBrain`, so tuning one number tunes both sides.
class_name WeaponCatalog
extends RefCounted

const UNARMED := &"unarmed"

const ENTRIES: Dictionary = {
	&"unarmed": {
		"label": "Unarmed",
		"model": "",
		"ranged": false,
		"fire_damage": 0.0,
		"fire_cooldown": 0.0,
		"fire_range": 0.0,
		"hold_length": 0.0,
		"scale": 1.0,
		"offset": Vector3.ZERO,
		"rotation_deg": Vector3.ZERO,
	},
	&"pistol": {
		"label": "Pistol",
		"model": "res://assets/weapons/styloo/pew.glb",
		"ranged": true,
		"fire_damage": 11.0,
		"fire_cooldown": 0.32,
		"fire_range": 38.0,
		"hold_length": 0.22,
		"scale": 1.0,
		"offset": Vector3(0.02, 0.02, 0.04),
		"rotation_deg": Vector3(0, 90, 0),
	},
	&"shotgun": {
		"label": "Shotgun",
		"model": "res://assets/weapons/styloo/shotgun.glb",
		"ranged": true,
		"fire_damage": 20.0,
		"fire_cooldown": 0.72,
		"fire_range": 22.0,
		"hold_length": 0.55,
		"scale": 1.0,
		"offset": Vector3(0.04, 0.02, 0.06),
		"rotation_deg": Vector3(0, 90, 0),
	},
	&"mac10": {
		"label": "MAC-10",
		"model": "res://assets/weapons/styloo/mac10.glb",
		"ranged": true,
		"fire_damage": 7.0,
		"fire_cooldown": 0.14,
		"fire_range": 32.0,
		"hold_length": 0.28,
		"scale": 1.0,
		"offset": Vector3(0.02, 0.02, 0.05),
		"rotation_deg": Vector3(0, 90, 0),
	},
	&"ak47": {
		"label": "AK-47",
		"model": "res://assets/weapons/styloo/ak47.glb",
		"ranged": true,
		"fire_damage": 11.0,
		"fire_cooldown": 0.18,
		"fire_range": 45.0,
		"hold_length": 0.62,
		"scale": 1.0,
		"offset": Vector3(0.04, 0.02, 0.08),
		"rotation_deg": Vector3(0, 90, 0),
	},
	&"awp": {
		"label": "AWP",
		"model": "res://assets/weapons/styloo/awp.glb",
		"ranged": true,
		"fire_damage": 34.0,
		"fire_cooldown": 1.1,
		"fire_range": 80.0,
		"hold_length": 0.95,
		"scale": 1.0,
		"offset": Vector3(0.05, 0.02, 0.1),
		"rotation_deg": Vector3(0, 90, 0),
	},
	&"rocket": {
		"label": "Rocket",
		"model": "res://assets/weapons/styloo/rocketlaucher.glb",
		"ranged": true,
		"fire_damage": 30.0,
		"fire_cooldown": 1.4,
		"fire_range": 55.0,
		"hold_length": 0.75,
		"scale": 1.0,
		"offset": Vector3(0.05, 0.03, 0.1),
		"rotation_deg": Vector3(0, 90, 0),
	},
}


static func list_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in ENTRIES.keys():
		out.append(key)
	return out


static func get_entry(id: StringName) -> Dictionary:
	return ENTRIES.get(id, ENTRIES[UNARMED])

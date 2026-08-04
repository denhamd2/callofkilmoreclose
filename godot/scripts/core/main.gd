## MAIN — places the slice's actors against the street data.
##
## Deliberately thin. Spawn positions are NOT typed into the scene file: they
## are derived from `KilmoreClose`, so that moving a house, changing the setback
## or extending the slice moves David and the car with it. Hard-coded spawn
## coordinates in a .tscn are how a player ends up standing inside a wall three
## refactors later.
##
## LIGHTING — Sky3D static overcast midday (`scenes/sky_kilmore.tscn`).
## Time does not advance in play; sun energy and cloud cover are tuned for a soft
## Dublin suburban read without a day/night cycle.

extends Node3D

## Small drop so both actors settle onto the ground on the first physics tick
## rather than starting fractionally interpenetrated with it.
const SETTLE := 0.3

@onready var _david: DavidController = $David
@onready var _car: Car = $Car
@onready var _prompt: Label = $HUD/Prompt

const _CAST_SCENE: PackedScene = preload("res://scenes/cast/cast_member.tscn")
const _DUMMY_SCENE: PackedScene = preload("res://scenes/combat/training_dummy.tscn")
const _COMBAT_HUD_SCENE: PackedScene = preload("res://scenes/ui/combat_hud.tscn")
const _WEAPON_SELECTOR_SCENE: PackedScene = preload("res://scenes/ui/weapon_selector.tscn")
const _COMBAT_CONTROLS_SCENE: PackedScene = preload("res://scenes/ui/combat_controls.tscn")


func _ready() -> void:
	var spawn := KilmoreClose.david_spawn()
	spawn.origin.y = KilmoreClose.WALK_H + SETTLE
	_david.teleport(spawn)

	var park := KilmoreClose.car_spawn()
	park.origin.y = 0.12
	_car.place(park)

	_spawn_cast()
	_spawn_training_dummy()
	_spawn_combat_hud()
	_spawn_weapon_selector()
	_spawn_combat_controls()
	_david.melee_hit.connect(_on_melee_hit)
	_david.shot_fired.connect(_on_shot_fired)
	_david.shot_hit.connect(_on_shot_hit)

	if _prompt != null:
		_prompt.visible = false

	# Headless verification path used by the engine tune-up pass.
	#   godot --path godot --headless -- --probe
	if OS.get_cmdline_user_args().has("--probe"):
		var probe_script := load("res://tools/runtime_probe.gd") as Script
		if probe_script != null:
			var probe := Node.new()
			probe.set_script(probe_script)
			probe.name = "RuntimeProbe"
			add_child(probe)

	# Performance profile path (measure before tuning).
	#   godot --path godot --headless --quit-after 600 -- --profile
	if OS.get_cmdline_user_args().has("--profile"):
		var prof_script := load("res://tools/performance_profile.gd") as Script
		if prof_script != null:
			var prof := Node.new()
			prof.set_script(prof_script)
			prof.name = "PerformanceProfile"
			add_child(prof)


func _spawn_cast() -> void:
	var root := Node3D.new()
	root.name = "Cast"
	add_child(root)
	for entry in KilmoreCast.members():
		var member := _CAST_SCENE.instantiate() as CastMember
		if member == null:
			continue
		root.add_child(member)
		member.global_transform = KilmoreCast.doorstep(entry)
		member.setup(entry)
		member.bind_player(_david)


func _spawn_training_dummy() -> void:
	var spawn := KilmoreClose.david_spawn()
	var ahead := spawn.origin + (-spawn.basis.z) * 4.0
	ahead.y = KilmoreClose.WALK_H + SETTLE
	var dummy := _DUMMY_SCENE.instantiate() as Node3D
	if dummy == null:
		return
	add_child(dummy)
	dummy.global_position = ahead
	dummy.look_at(Vector3(spawn.origin.x, ahead.y, spawn.origin.z), Vector3.UP)


func _spawn_combat_hud() -> void:
	var hud := $HUD
	var combat := _COMBAT_HUD_SCENE.instantiate()
	if combat != null and hud != null:
		hud.add_child(combat)


func _spawn_weapon_selector() -> void:
	var hud := $HUD
	var selector := _WEAPON_SELECTOR_SCENE.instantiate() as WeaponSelector
	if selector != null and hud != null:
		hud.add_child(selector)
		selector.bind_player(_david)


func _spawn_combat_controls() -> void:
	var hud := $HUD
	var controls := _COMBAT_CONTROLS_SCENE.instantiate()
	if controls != null and hud != null:
		hud.add_child(controls)


func _on_melee_hit(target: Node3D) -> void:
	if target != null and target.has_method(&"take_hit"):
		target.take_hit(DavidController.MELEE_DAMAGE, _david)
		StreetAudio.play_melee_thud()
		return
	if target == null or not target.is_in_group("cast"):
		return
	StreetAudio.play_melee_thud()
	var label := target.get_node_or_null("NameLabel") as Label3D
	if label != null:
		label.modulate = Color(1.0, 0.92, 0.55, 1.0)


func _on_shot_fired() -> void:
	StreetAudio.play_gun_crack()


func _on_shot_hit(target: Node3D) -> void:
	if target != null and target.has_method(&"take_hit"):
		target.take_hit(_david.get_fire_damage(), _david)
		StreetAudio.play_melee_thud()

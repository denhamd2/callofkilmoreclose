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
@onready var _street: Node3D = $Street

var _cast: Array[CastMember] = []

const _CAST_SCENE: PackedScene = preload("res://scenes/cast/cast_member.tscn")
const _COMBAT_HUD_SCENE: PackedScene = preload("res://scenes/ui/combat_hud.tscn")
const _WEAPON_SELECTOR_SCENE: PackedScene = preload("res://scenes/ui/weapon_selector.tscn")
const _COMBAT_CONTROLS_SCENE: PackedScene = preload("res://scenes/ui/combat_controls.tscn")


func _ready() -> void:
	var spawn := KilmoreClose.david_spawn()
	spawn.origin.y = KilmoreClose.WALK_H + SETTLE
	_david.teleport(spawn)

	var park := KilmoreClose.car_spawn()
	# The sprung body's natural ride height, measured from Pogo's suspension at
	# rest. It used to be parked at 0.12, far below where the suspension actually
	# holds it, so the car visibly jumped the moment you got in.
	park.origin.y = Car.RIDE_HEIGHT
	_car.place(park)

	_spawn_cast()
	# The cast stay planted at their doors until the street navmesh exists —
	# agents queried against an unsynchronised map return Vector3.ZERO and the
	# whole roster slides to the world origin.
	if _street != null and _street.has_signal(&"navmesh_ready"):
		_street.navmesh_ready.connect(_on_navmesh_ready)
	_spawn_combat_hud()
	_spawn_weapon_selector()
	_spawn_combat_controls()
	# melee_swung had no listeners at all, so a punch that missed was silent and
	# gave the player no feedback that the swing had even happened.
	_david.melee_swung.connect(_on_melee_swung)
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

	# Screenshot gate — the visual counterpart to --probe. MUST be windowed:
	# --headless has a dummy RenderingDevice and captures blank images.
	#   godot --path godot -- --shot
	if OS.get_cmdline_user_args().has("--shot"):
		var shot_script := load("res://tools/screenshot.gd") as Script
		if shot_script != null:
			var shot := Node.new()
			shot.set_script(shot_script)
			shot.name = "Screenshot"
			add_child(shot)

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
	_cast.clear()
	var i := 0
	for entry in KilmoreCast.members():
		var member := _CAST_SCENE.instantiate() as CastMember
		if member == null:
			continue
		root.add_child(member)
		member.global_transform = KilmoreCast.doorstep(entry)
		member.setup(entry)
		member.bind_player(_david)
		# Fixed per-actor seeds keep wander paths reproducible across runs, so a
		# probe failure means a real regression rather than a different dice roll.
		member.seed_rng(0x5F00 + i * 7919)
		_cast.append(member)
		i += 1


func _on_navmesh_ready(polygon_count: int) -> void:
	if polygon_count <= 0:
		push_warning("navmesh baked with no polygons — cast will stay at their doors")
		return
	# One physics frame for NavigationServer to publish the new region before any
	# agent asks it for a path.
	await get_tree().physics_frame
	for member in _cast:
		if member != null:
			member.enable_roaming()


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


func _on_melee_swung() -> void:
	StreetAudio.play_melee_swing()


func _on_melee_hit(target: Node3D) -> void:
	if Damage.apply(target, DavidController.MELEE_DAMAGE, _david):
		StreetAudio.play_melee_thud()


func _on_shot_fired() -> void:
	StreetAudio.play_gun_crack()


func _on_shot_hit(target: Node3D) -> void:
	if Damage.apply(target, _david.get_fire_damage(), _david):
		StreetAudio.play_melee_thud()

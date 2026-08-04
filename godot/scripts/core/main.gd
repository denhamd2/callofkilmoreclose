## MAIN — places the slice's actors against the street data.
##
## Deliberately thin. Spawn positions are NOT typed into the scene file: they
## are derived from `KilmoreClose`, so that moving a house, changing the setback
## or extending the slice moves David and the car with it. Hard-coded spawn
## coordinates in a .tscn are how a player ends up standing inside a wall three
## refactors later.
##
## LIGHTING IS PERMANENTLY DAYTIME, and there is no code here to change it.
##
## The sun and the WorldEnvironment are fixed in `main.tscn`: one
## DirectionalLight3D at a high midday angle, neutral white, with sky-sourced
## ambient lifting the shadowed sides. There is no day/night cycle, no sunset
## variation, no weather, and no time-of-day scripting anywhere in this project.
##
## That is a deliberate constraint for the whole migration, not an oversight. A
## moving sun means the street, the house, David and the car are lit differently
## every time you look at them, and you end up unable to tell whether a change
## improved the work or just caught better light. Fixed lighting makes the
## comparison honest. It also happens to be the cheapest option on a basic
## phone: one shadow-casting light, one orthogonal shadow split, no relighting
## cost ever.

extends Node3D

## Small drop so both actors settle onto the ground on the first physics tick
## rather than starting fractionally interpenetrated with it.
const SETTLE := 0.3

@onready var _david: DavidController = $David
@onready var _car: Car = $Car
@onready var _prompt: Label = $HUD/Prompt

const _CAST_SCENE: PackedScene = preload("res://scenes/cast/cast_member.tscn")


func _ready() -> void:
	var spawn := KilmoreClose.david_spawn()
	spawn.origin.y = KilmoreClose.WALK_H + SETTLE
	_david.teleport(spawn)

	var park := KilmoreClose.car_spawn()
	park.origin.y = 0.12
	_car.place(park)

	_spawn_cast()
	_david.melee_hit.connect(_on_melee_hit)

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


func _on_melee_hit(target: Node3D) -> void:
	if target == null or not target.is_in_group("cast"):
		return
	# Report-only: David's punch connected with a named neighbour. No damage model.
	var label := target.get_node_or_null("NameLabel") as Label3D
	if label != null:
		label.modulate = Color(1.0, 0.92, 0.55, 1.0)

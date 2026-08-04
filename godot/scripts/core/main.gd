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


func _ready() -> void:
	var spawn := KilmoreClose.david_spawn()
	spawn.origin.y = KilmoreClose.WALK_H + SETTLE
	_david.teleport(spawn)

	var park := KilmoreClose.car_spawn()
	park.origin.y = 0.12
	_car.place(park)

	if _prompt != null:
		_prompt.visible = false

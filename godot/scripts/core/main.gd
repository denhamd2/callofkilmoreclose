## MAIN — places the slice's actors against the street data.
##
## Deliberately thin. Spawn positions are NOT typed into the scene file: they
## are derived from `KilmoreClose`, so that moving a house, changing the setback
## or extending the slice moves David and the car with it. Hard-coded spawn
## coordinates in a .tscn are how a player ends up standing inside a wall three
## refactors later.

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

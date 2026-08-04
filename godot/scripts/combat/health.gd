## HEALTH — hit points for anything that can be damaged.
##
## A child node rather than a base class, for two reasons. The three actor types
## already have three different bases (`CharacterBody3D` for David and the cast,
## `StaticBody3D` for the training dummy) and GDScript has no multiple
## inheritance, so a `Damageable` base would force a rewrite of all three. And as
## a node it is visible in the scene tree and can be bound directly by the HUD.
##
## Actors keep a small `take_hit()` forwarder so the pre-existing
## `has_method("take_hit")` contract in `main.gd` and the runtime probe stay true.

class_name Health
extends Node

signal damaged(amount: float, source: Node, hp: float)
signal died(source: Node)
signal revived

## 160 rather than 100, paired with the halved weapon damage in `WeaponCatalog`, so
## a brawl lasts ~8-12 s instead of ending on the first burst.
@export var max_hp := 160.0

var hp := 0.0
var last_source: Node = null


func _ready() -> void:
	hp = max_hp


## Returns true if this call actually landed damage. Already-dead targets absorb
## nothing, so a brain can tell a wasted swing from a connecting one.
func apply(amount: float, source: Node = null) -> bool:
	if hp <= 0.0 or amount <= 0.0:
		return false
	last_source = source
	hp = maxf(0.0, hp - amount)
	damaged.emit(amount, source, hp)
	if hp <= 0.0:
		died.emit(source)
	return true


func is_alive() -> bool:
	return hp > 0.0


func fraction() -> float:
	if max_hp <= 0.0:
		return 0.0
	return hp / max_hp


func revive() -> void:
	hp = max_hp
	last_source = null
	revived.emit()

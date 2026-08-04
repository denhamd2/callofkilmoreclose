## DAMAGE — the one way anything in Kilmore Close gets hurt.
##
## Before this, `main.gd` reached straight for `target.take_hit()`, and only the
## training dummy implemented it — so the cast were literally unkillable and
## nothing at all could hurt David. Routing every hit through here means adding a
## `Health` child to an actor is the whole job of making it damageable.

class_name Damage
extends RefCounted


## Resolve and apply damage. Returns true only if a live target absorbed it, so
## callers can distinguish a landed hit from one that struck scenery.
static func apply(target: Node, amount: float, source: Node = null) -> bool:
	var health := health_of(target)
	if health != null:
		return health.apply(amount, source)
	# Legacy path: an actor with its own take_hit and no Health node. Kept so a
	# half-migrated scene degrades to "no damage recorded" rather than a crash.
	if target != null and target.has_method(&"take_hit"):
		target.take_hit(amount, source)
		return true
	return false


static func health_of(target: Node) -> Health:
	if target == null:
		return null
	return target.get_node_or_null(^"Health") as Health


static func is_alive(target: Node) -> bool:
	var health := health_of(target)
	if health == null:
		return target != null
	return health.is_alive()

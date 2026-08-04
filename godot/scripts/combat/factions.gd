## FACTIONS — who is willing to hit whom.
##
## Deliberately separate from collision layers. Layers decide what physically
## blocks or detects what; factions decide what a `CombatBrain` is prepared to
## target. Conflating the two means you cannot have two hostile actors that still
## bump into each other, which is exactly what a street brawl needs.
##
## Kilmore Close's alignment: the McCabes against the rest of the road, with
## David siding against the McCabes. That produces an unprompted 2v3 the moment
## the scene loads, without anyone having to be scripted into it.

class_name Factions
extends RefCounted

const NEUTRAL := &"neutral"
const DAVID := &"david"
const MCCABE := &"mccabe"
const RESIDENTS := &"residents"

## FREE-FOR-ALL. Everybody on Kilmore Close is willing to hit everybody else,
## including their own family — the McCabes brawl with each other too. The faction
## labels are kept because they still read in the roster and the killfeed, but they
## no longer gate targeting.
##
## NEUTRAL is the one exception, and it is load-bearing rather than cosmetic:
## the training dummy and the **car** both resolve to NEUTRAL, and
## `CombatBrain._on_damaged()` retaliates against whatever it is passed as the
## damage source. Without NEUTRAL staying non-hostile, everyone run over by the car
## would turn round and start punching the car.
const FREE_FOR_ALL := true

## Retained for the non-free-for-all case, and as a record of the original
## alignment: McCabes against the rest of the road, David against the McCabes.
const _HOSTILE: Dictionary = {
	DAVID: [MCCABE],
	MCCABE: [DAVID, RESIDENTS],
	RESIDENTS: [MCCABE],
	NEUTRAL: [],
}


static func hostile(a: StringName, b: StringName) -> bool:
	if a == NEUTRAL or b == NEUTRAL:
		return false
	if FREE_FOR_ALL:
		# Note this returns true for a == b. Callers already skip self
		# (`CombatBrain._reselect()` filters `other == _host`), so same-faction
		# hostility is what makes a same-household pair fight.
		return true
	if a == b:
		return false
	return b in _HOSTILE.get(a, [])


## Faction of any actor, read from the `faction` property when it has one.
## Anything unlabelled is a bystander rather than a target.
static func of(actor: Node) -> StringName:
	if actor == null:
		return NEUTRAL
	var f: Variant = actor.get(&"faction")
	if f is StringName:
		return f
	if f is String and not (f as String).is_empty():
		return StringName(f)
	return NEUTRAL

## COMBAT BRAIN — perception, target selection and attacks for one actor.
##
## A child node of the actor, like `Health`, and for the same reason: the actors
## do not share a base class. The brain never moves the body itself — it hands a
## destination to the host's `set_move_target()` and lets the NavigationAgent3D
## and avoidance do the driving. That keeps pathfinding in one place.
##
## Perception runs at 6 Hz rather than per physics tick. With six actors and six
## candidates that is ~216 line-of-sight rays a second, which is nothing, and it
## also stops the roster from all reacting on the identical frame.
##
## Fights are resolved with hitscan against `Damage.apply`, using the same
## `WeaponCatalog` numbers the player's weapons use, so tuning one tunes both.

class_name CombatBrain
extends Node

enum State { IDLE, CHASE, ATTACK_MELEE, ATTACK_RANGED, FLINCH, DEAD }

## How far this actor will notice an enemy at all. The roster lives at houses 14,
## 26, 27 and 31 — spread over roughly 100 m of street — so at the old 30 m only
## the two McCabes sharing number 14 ever met, and the street stayed quiet.
const SIGHT_RANGE := 120.0
const SIGHT_RANGE_PROBE := 30.0
## Inside this range a target must be in line of sight to be engaged. Beyond it an
## actor will still set off towards the nearest enemy it knows about, which is what
## actually collapses the roster into one brawl.
const LOS_RANGE := 34.0
## Melee engage distance, and the reach used to resolve a landed punch.
const MELEE_RANGE := 2.1
const MELEE_DAMAGE := 18.0
const MELEE_COOLDOWN := 0.9
## Ranged actors hold at this fraction of their weapon's range.
const STANDOFF := 0.65
## Human reaction time. Without it a MAC-10 neighbour empties into David the
## instant he rounds the corner and the fight is over before it reads as one.
const REACTION := 0.35
## Re-evaluate targets at 6 Hz.
const THINK_INTERVAL := 1.0 / 6.0
## Seconds of stagger after taking a hit, during which this actor cannot attack.
const FLINCH_TIME := 0.35
## Rounds per burst for fully automatic weapons, then a pause.
const BURST := 3
const BURST_PAUSE := 0.55
const GRENADE_PAUSE := 2.0
const THROW_RANGE := 18.0

var state: State = State.IDLE
var target: Node3D = null

var _host: Node3D = null
var _health: Health = null
var _animator: QuaterniusAnimDriver = null
var _weapon_id: StringName = WeaponCatalog.UNARMED
var _rng := RandomNumberGenerator.new()

var _think := 0.0
var _attack_cd := 0.0
var _reaction := 0.0
var _flinch := 0.0
var _burst_left := BURST
var _enabled := false


func setup(host: Node3D, weapon_id: StringName, rng_seed: int) -> void:
	_host = host
	_weapon_id = weapon_id
	_rng.seed = rng_seed
	_health = Damage.health_of(host)
	_animator = host.get_node_or_null(^"QuaterniusAnim") as QuaterniusAnimDriver
	if _health != null:
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)
		_health.revived.connect(_on_revived)
	# Stagger the first think so the roster does not perceive in lockstep.
	_think = _rng.randf_range(0.0, THINK_INTERVAL)


func enable() -> void:
	_enabled = true


func is_ranged() -> bool:
	return bool(WeaponCatalog.get_entry(_weapon_id).get("ranged", false))


func is_throwable() -> bool:
	return bool(WeaponCatalog.get_entry(_weapon_id).get("throwable", false))


func _physics_process(delta: float) -> void:
	if not _enabled or _host == null:
		return
	if state == State.DEAD:
		return
	# Suspend entirely while thrown by a car — the host owns its own motion and
	# animation through the launch, landing and get-up.
	if _host.has_method(&"is_knocked") and _host.is_knocked():
		target = null
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_flinch = maxf(0.0, _flinch - delta)

	_think -= delta
	if _think <= 0.0:
		_think = THINK_INTERVAL
		_reselect()

	if target == null:
		if state != State.IDLE:
			state = State.IDLE
			_release()
		return

	if _flinch > 0.0:
		state = State.FLINCH
		return

	# Reaction delay only runs down while a target is actually in view.
	_reaction = maxf(0.0, _reaction - delta)

	var dist := _host.global_position.distance_to(target.global_position)
	if is_throwable():
		_act_throw(dist)
	elif is_ranged():
		_act_ranged(dist)
	else:
		_act_melee(dist)


# ------------------------------------------------------------ perception

func _sight_range() -> float:
	if ProfileToggles.has(&"sight_30"):
		return SIGHT_RANGE_PROBE
	return SIGHT_RANGE


func _reselect() -> void:
	var best: Node3D = null
	var best_score := -INF
	var my_faction := Factions.of(_host)
	for node in _host.get_tree().get_nodes_in_group("hittable"):
		var other := node as Node3D
		if other == null or other == _host:
			continue
		if not Factions.hostile(my_faction, Factions.of(other)):
			continue
		if not Damage.is_alive(other):
			continue
		var d := _host.global_position.distance_to(other.global_position)
		if d > _sight_range():
			continue
		# Line of sight gates *engagement*, not awareness. A neighbour four houses
		# down is walked towards; only once close does the wall between you matter.
		if d <= LOS_RANGE and not _can_see(other):
			continue
		var score := 1.0 / maxf(d, 0.5)
		# Prefer whoever is actually hurting me over whoever is merely nearest.
		if _health != null and _health.last_source == other:
			score += 1.5
		if other == target:
			score += 2.0
		if score > best_score:
			best_score = score
			best = other
	if best != target:
		# New target: pay the reaction cost again.
		_reaction = REACTION
		_burst_left = BURST
	target = best


## Eye-height ray against `world` only, so a neighbour cannot see through a house
## but is not blocked by the person they are about to hit.
func _can_see(other: Node3D) -> bool:
	var space := _host.get_world_3d().direct_space_state
	var from := _host.global_position + Vector3(0.0, 1.5, 0.0)
	var to := other.global_position + Vector3(0.0, 1.4, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()


# ---------------------------------------------------------------- acting

func _act_melee(dist: float) -> void:
	if dist > MELEE_RANGE:
		state = State.CHASE
		_pursue(target.global_position)
		return
	state = State.ATTACK_MELEE
	_release()
	_face_target()
	if _attack_cd > 0.0 or _reaction > 0.0:
		return
	_attack_cd = MELEE_COOLDOWN
	if _animator != null:
		_animator.play_melee(MELEE_COOLDOWN * 0.55)
	# Damage lands on the swing, not on contact frames — the mannequin has no
	# attack-event track to hang a precise hit on.
	if dist <= MELEE_RANGE + 0.3:
		if Damage.apply(target, MELEE_DAMAGE, _host):
			StreetAudio.play_melee_thud()


func _act_throw(dist: float) -> void:
	var entry := WeaponCatalog.get_entry(_weapon_id)
	var range_m := float(entry.get("fire_range", THROW_RANGE))
	if dist > range_m:
		state = State.CHASE
		_pursue(target.global_position)
		return
	state = State.ATTACK_RANGED
	_release()
	_face_target()
	if _attack_cd > 0.0 or _reaction > 0.0:
		return
	if _burst_left <= 0:
		_burst_left = BURST
		_attack_cd = GRENADE_PAUSE
		return
	_burst_left = 0
	_attack_cd = float(entry.get("fire_cooldown", 4.5))
	if _animator != null:
		_animator.play_throw(0.5)
	var from := _host.global_position + Vector3(0.0, 1.4, 0.0)
	var to := target.global_position + Vector3(0.0, 0.8, 0.0)
	GrenadeThrow.launch(from, to, _host, entry)


func _act_ranged(dist: float) -> void:
	var entry := WeaponCatalog.get_entry(_weapon_id)
	var range_m := float(entry.get("fire_range", 30.0))
	var hold := range_m * STANDOFF
	# Close in before shooting if there is no clear line — otherwise an armed actor
	# stands at standoff distance firing into the back of a house.
	if dist > hold or not _can_see(target):
		state = State.CHASE
		_pursue(target.global_position)
		return
	state = State.ATTACK_RANGED
	_release()
	_face_target()
	if _attack_cd > 0.0 or _reaction > 0.0:
		return

	var cooldown := float(entry.get("fire_cooldown", 0.4))
	if _burst_left <= 0:
		_burst_left = BURST
		_attack_cd = BURST_PAUSE
		return
	_burst_left -= 1
	_attack_cd = cooldown
	if _animator != null:
		_animator.play_shoot(cooldown)
	StreetAudio.play_gun_crack()
	_fire(entry, range_m)


## Hitscan with a spread cone. The spread is what stops five NPCs with perfect
## aim from deleting each other instantly, and it comes from the per-actor seeded
## RNG so a probe run reproduces exactly.
func _fire(entry: Dictionary, range_m: float) -> void:
	var from := _host.global_position + Vector3(0.0, 1.45, 0.0)
	var to_target := (target.global_position + Vector3(0.0, 1.2, 0.0)) - from
	if to_target.length_squared() < 0.01:
		return
	var dir := to_target.normalized()
	var spread := 0.035
	dir = (dir + Vector3(
		_rng.randfn(0.0, spread),
		_rng.randfn(0.0, spread * 0.6),
		_rng.randfn(0.0, spread))).normalized()

	var space := _host.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * range_m)
	query.collision_mask = 1 | 2 | 4 | 8
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var hit_pos: Vector3 = hit.get("position", from + dir * range_m)
	var hit_normal: Vector3 = hit.get("normal", -dir)
	DecalPool.project(DecalPool.Kind.BULLET, hit_pos, hit_normal)
	var collider := hit.get("collider") as Node3D
	if collider == null or collider == _host:
		return
	# Friendly fire is possible — a stray round that clips an ally still counts,
	# which is what makes a crossfire feel like one.
	Damage.apply(collider, float(entry.get("fire_damage", 20.0)), _host)


# ------------------------------------------------------------- movement

func _pursue(to: Vector3) -> void:
	if _host.has_method(&"set_move_target"):
		_host.set_move_target(to)


func _release() -> void:
	if _host.has_method(&"clear_move_target"):
		_host.clear_move_target()


func _face_target() -> void:
	if target == null or not _host.has_method(&"face_towards"):
		return
	_host.face_towards(target.global_position)


# --------------------------------------------------------------- signals

func _on_damaged(_amount: float, source: Node, _hp: float) -> void:
	_flinch = FLINCH_TIME
	if _animator != null:
		_animator.play_flinch()
	# Being shot from outside your view cone is how a fight spreads.
	if source is Node3D and target == null \
			and Factions.hostile(Factions.of(_host), Factions.of(source)):
		target = source as Node3D
		_reaction = REACTION


func _on_died(_source: Node) -> void:
	state = State.DEAD
	target = null
	_release()


func _on_revived() -> void:
	state = State.IDLE
	target = null
	_flinch = 0.0
	_attack_cd = 0.0
	_burst_left = BURST

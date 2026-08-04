## CAST MEMBER — a named neighbour who walks the street.
##
## Movement runs on the street navmesh baked by `street_builder.gd`, through a
## NavigationAgent3D with avoidance so neighbours steer around each other, the
## parked cars and David rather than clipping through. Targeting and attacking are
## not here: `CombatBrain` drives those and takes priority over wandering by
## setting an explicit destination.
##
## Roaming stays off until `navmesh_ready` fires. An agent queried before the
## navigation map has synchronised returns Vector3.ZERO, and the whole cast then
## slides to the world origin — the classic way this goes wrong.

class_name CastMember
extends CharacterBody3D

const FACE_DIST := 6.0
const SLEEP_DIST := 14.0
const TURN_RATE := 4.0

const WALK_SPEED := 1.45
const GRAVITY := 20.6
## How close counts as arrived, before a new wander target is picked.
const ARRIVE_DIST := 1.1
## Seconds to loiter on arrival, so they do not ping-pong across the road.
const LOITER := Vector2(1.5, 5.0)

@export var display_name := "Neighbour"
@export var jacket_color := Color(0.25, 0.3, 0.35)

## Read by `Factions.of()`. Neutral until the roster assigns one.
var faction: StringName = Factions.NEUTRAL
var weapon_id: StringName = WeaponCatalog.UNARMED

var _base_yaw := 0.0
var _player: Node3D

## Roaming stays parked until the navmesh exists — see the class comment.
var _roam_enabled := false
var _loiter := 0.0
var _home := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
## Set by CombatBrain to override wandering; cleared when it lets go.
var _forced_target := false

## Knockdown phases. There is no prone or get-up clip in the Quaternius library, so
## AIRBORNE reuses the jump loop, DOWN parks on the last frame of Death01 (a
## one-shot leaves the AnimationPlayer holding its final pose), and GETUP borrows
## Sitting_Exit, which is the library's only authored stand-up.
enum KnockPhase { NONE, AIRBORNE, DOWN, GETUP }

## Seconds face-down before trying to stand.
const DOWN_TIME := 1.5
const GETUP_TIME := 1.1
## Ignore the floor for this long after launch, so leaving the ground is possible
## even though the impact happens while standing on it.
const LAUNCH_GRACE := 0.18

var _knocked: KnockPhase = KnockPhase.NONE
var _knock_timer := 0.0
var _launch_grace := 0.0
## Planar speed we intend to move at this frame — what the animator is fed.
var _desired_speed := 0.0

@onready var _body: Node3D = $Body
@onready var _animator: QuaterniusAnimDriver = $QuaterniusAnim
@onready var _health: Health = $Health
@onready var _agent: NavigationAgent3D = $NavAgent
@onready var _weapon: WeaponHolder = $Body/WeaponMount
@onready var _brain: CombatBrain = $Brain


func _ready() -> void:
	_base_yaw = rotation.y
	_home = global_position
	add_to_group("cast")
	# Neighbours were previously undamageable — the training dummy was the only
	# thing in the world with hit points.
	add_to_group("hittable")
	_apply_colors()
	_label_name()
	if _animator != null:
		_animator.setup(_body)
	if _health != null:
		_health.died.connect(_on_died)
		_health.revived.connect(_on_revived)
	if _agent != null:
		_agent.velocity_computed.connect(_on_velocity_computed)


## Seeded per actor so a probe run is reproducible; the project's no-Math.random
## doctrine came from the Three.js prototype, and a seeded RNG is its Godot
## equivalent.
func seed_rng(value: int) -> void:
	_rng.seed = value
	# The brain needs its own stream so perception jitter and weapon spread are
	# reproducible per actor without being identical across the roster.
	if _brain != null:
		_brain.setup(self, weapon_id, value ^ 0x9E37)
	if _weapon != null:
		_weapon.setup_on_body(_body)
		_weapon.set_weapon(weapon_id)


## Called once the street navmesh is baked. Fighting waits on the same signal:
## a brain that starts chasing before there is a path just stands still.
func enable_roaming() -> void:
	if ProfileToggles.has(&"no_ai"):
		return
	_roam_enabled = true
	_loiter = _rng.randf_range(0.0, LOITER.y)
	if _brain != null:
		_brain.enable()


## Thrown by a vehicle. `dir` is the horizontal push direction, `speed` the impact
## speed in m/s. Called by `Car`; safe to call repeatedly (ignored while already
## down, so one collision does not re-launch every contact frame).
func knock_down(dir: Vector3, speed: float) -> void:
	if _knocked != KnockPhase.NONE:
		return
	_knocked = KnockPhase.AIRBORNE
	_knock_timer = 0.0
	_launch_grace = LAUNCH_GRACE
	_desired_speed = 0.0

	var push := Vector3(dir.x, 0.0, dir.z)
	if push.length_squared() < 0.0001:
		push = -global_transform.basis.z
	push = push.normalized()
	# Faster impacts throw further and higher, with a floor so a slow nudge still
	# reads as being knocked over rather than gently nudged.
	var throw := clampf(speed * 0.55, 3.0, 11.0)
	var lift := clampf(speed * 0.34, 3.4, 7.5)
	velocity = push * throw + Vector3.UP * lift

	# Stop the avoidance solver feeding walking velocity back over the launch.
	if _agent != null:
		_agent.velocity = Vector3.ZERO
	if _animator != null:
		_animator.play_knock_airborne()


func is_knocked() -> bool:
	return _knocked != KnockPhase.NONE


## Cancel a knockdown immediately and stand up. Used by the probe so its knockdown
## assertion does not leave an actor prone for the checks that follow.
func recover_now() -> void:
	if _knocked == KnockPhase.NONE:
		return
	_knocked = KnockPhase.NONE
	_knock_timer = 0.0
	_launch_grace = 0.0
	velocity = Vector3.ZERO
	if _animator != null:
		_animator.reset_after_knock()
	clear_move_target()


func _tick_knocked(delta: float) -> void:
	_launch_grace = maxf(0.0, _launch_grace - delta)
	_knock_timer += delta

	match _knocked:
		KnockPhase.AIRBORNE:
			velocity.y -= GRAVITY * delta
			# Bleed horizontal speed so they skid to a stop rather than sliding on.
			velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
			move_and_slide()
			if _launch_grace <= 0.0 and is_on_floor():
				_knocked = KnockPhase.DOWN
				_knock_timer = 0.0
				if _animator != null:
					_animator.play_knock_down()
		KnockPhase.DOWN:
			velocity.x = 0.0
			velocity.z = 0.0
			_fall(delta)
			move_and_slide()
			if _knock_timer < DOWN_TIME:
				return
			if not is_alive():
				# Dead stays down. play_death() has already been run by _on_died.
				return
			_knocked = KnockPhase.GETUP
			_knock_timer = 0.0
			if _animator != null:
				_animator.play_get_up(GETUP_TIME)
		KnockPhase.GETUP:
			velocity.x = 0.0
			velocity.z = 0.0
			_fall(delta)
			move_and_slide()
			if _knock_timer >= GETUP_TIME:
				_knocked = KnockPhase.NONE
				_knock_timer = 0.0
				# Re-seat the locomotion state machine and pick a fresh destination.
				if _animator != null:
					_animator.reset_after_knock()
				clear_move_target()


## Turn to look at a world point. Used by CombatBrain so an actor squares up to
## whoever it is hitting; -Z forward, matching david_controller.gd.
func face_towards(point: Vector3) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0004:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z),
		1.0 - exp(-TURN_RATE * get_physics_process_delta_time()))


## CombatBrain hands a destination down; while one is set, wandering is suspended.
func set_move_target(target: Vector3) -> void:
	if _agent == null:
		return
	_forced_target = true
	_agent.target_position = target


func clear_move_target() -> void:
	_forced_target = false
	_loiter = _rng.randf_range(LOITER.x, LOITER.y)


## Kept so the pre-existing `has_method("take_hit")` contract in `main.gd` and
## the runtime probe still holds; `Health` is the actual store.
func take_hit(amount: float, source: Node = null) -> void:
	if _health != null:
		_health.apply(amount, source)


func is_alive() -> bool:
	return _health == null or _health.is_alive()


func _on_died(_source: Node) -> void:
	if _animator != null:
		_animator.play_death()
	# Stop occupying the footpath as a solid obstacle once down.
	set_collision_layer_value(3, false)


func _on_revived() -> void:
	set_collision_layer_value(3, true)
	_knocked = KnockPhase.NONE
	_knock_timer = 0.0
	_launch_grace = 0.0
	velocity = Vector3.ZERO
	if _animator != null:
		_animator.reset_alive()


func bind_player(player: Node3D) -> void:
	_player = player


func setup(entry: Dictionary) -> void:
	display_name = str(entry["name"])
	if entry.has("jacket"):
		jacket_color = entry["jacket"] as Color
	if entry.has("faction"):
		faction = entry["faction"] as StringName
	if entry.has("weapon"):
		weapon_id = entry["weapon"] as StringName
	_apply_colors()
	_label_name()


## MOVEMENT CONTRACT — read before editing.
##
## `move_and_slide()` is called from exactly ONE place: `_on_velocity_computed()`,
## the NavigationAgent3D avoidance callback. That callback fires every physics
## frame once avoidance is enabled, whether or not this script assigned
## `_agent.velocity`. Previously several branches here also called
## `move_and_slide()` themselves, so on most frames the body integrated TWICE —
## doubling gravity to 41.2 m/s² and applying stale avoidance velocity a second
## time. Every branch below must therefore set `_agent.velocity` and return
## without moving.
##
## The animator is fed `_desired_speed`, the speed we are about to move at, not
## `velocity`. `velocity` is written by the callback which runs *after* this
## function, so reading it here samples last frame — it was ~0 while walking, so
## the cast played Idle while sliding along, which is the "floating" look.
func _physics_process(delta: float) -> void:
	# Knockdown is checked first, ahead of the alive test: a fatal car impact must
	# still fly, and the not-alive branch zeroes horizontal velocity.
	if _knocked != KnockPhase.NONE:
		_tick_knocked(delta)
		return

	if not is_alive():
		_desired_speed = 0.0
		_request_velocity(Vector3.ZERO, delta)
		return

	if not _roam_enabled or _agent == null:
		_idle_at_door(delta)
		return

	if not _forced_target:
		_tick_wander(delta)

	var moving := _steer(delta)
	if _animator != null:
		# Talking only makes sense standing still next to the player.
		var chatting := not moving and _near_player(FACE_DIST)
		_animator.set_talking(chatting)
		_animator.set_locomotion(_desired_speed, false, is_on_floor(), 4.57, 7.01)
	if not moving:
		_face_idle(delta)


## Hand a desired planar velocity to the avoidance solver. When there is no agent
## at all (pre-navmesh, or a failed bake) there is no callback to move us, so this
## integrates directly — still exactly one `move_and_slide()` per frame.
func _request_velocity(planar: Vector3, delta: float) -> void:
	if _agent != null:
		_agent.velocity = Vector3(planar.x, 0.0, planar.z)
		return
	velocity.x = planar.x
	velocity.z = planar.z
	_fall(delta)
	move_and_slide()


## Pre-navmesh behaviour, and the fallback if the bake ever fails: stand at the
## door and turn to the player, which is what the whole cast used to do forever.
func _idle_at_door(delta: float) -> void:
	_desired_speed = 0.0
	if _animator != null:
		_animator.set_locomotion(0.0, false, true, 4.57, 7.01)
		_animator.set_talking(_near_player(FACE_DIST))
	if _player != null:
		_face_idle(delta)
	# Unconditional: this used to early-return before moving when `_player` was
	# unbound, so a cast member never integrated gravity and hung in mid-air.
	_request_velocity(Vector3.ZERO, delta)


func _tick_wander(delta: float) -> void:
	_loiter = maxf(0.0, _loiter - delta)
	if _loiter > 0.0:
		return
	if _agent.is_navigation_finished() \
			or global_position.distance_to(_agent.target_position) < ARRIVE_DIST:
		_agent.target_position = _pick_wander_target()
		_loiter = _rng.randf_range(LOITER.x, LOITER.y)


## A point on the navmesh, biased to stay in this neighbour's own stretch of the
## road so the five of them do not all converge on one spot.
func _pick_wander_target() -> Vector3:
	var map := _agent.get_navigation_map()
	var want := _home + Vector3(
		_rng.randf_range(-7.0, 7.0), 0.0, _rng.randf_range(-14.0, 14.0))
	if map.is_valid():
		return NavigationServer3D.map_get_closest_point(map, want)
	return want


## Returns true if actually walking. Never moves the body — see the movement
## contract on `_physics_process`.
func _steer(delta: float) -> bool:
	if _agent.is_navigation_finished():
		_desired_speed = 0.0
		_request_velocity(Vector3.ZERO, delta)
		return false
	var next := _agent.get_next_path_position()
	var to_next := next - global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.0004:
		_desired_speed = 0.0
		_request_velocity(Vector3.ZERO, delta)
		return false
	var desired := to_next.normalized() * WALK_SPEED
	_desired_speed = WALK_SPEED
	_request_velocity(desired, delta)
	_face(to_next, delta)
	return true


## The single `move_and_slide()` site. Fires every physics frame while avoidance is
## enabled, so it must bail out of any state that owns its own motion.
func _on_velocity_computed(safe: Vector3) -> void:
	if _knocked != KnockPhase.NONE:
		return
	velocity.x = safe.x
	velocity.z = safe.z
	_fall(get_physics_process_delta_time())
	move_and_slide()


## The `velocity.y < 0.0` guard matches david_controller.gd. Without it an upward
## launch is stomped on the same frame it is applied, which is precisely what a car
## knockdown needs to survive.
func _fall(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -2.0
	else:
		velocity.y -= GRAVITY * delta


func _near_player(dist: float) -> bool:
	if _player == null:
		return false
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	return to_player.length_squared() <= dist * dist


## Godot's forward is -Z, hence atan2(-x, -z) — the same convention as
## `david_controller.gd`.
func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0004:
		return
	var want := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-TURN_RATE * delta))


func _face_idle(delta: float) -> void:
	if _near_player(FACE_DIST) and _player != null:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		_face(to_player, delta)
		return
	rotation.y = lerp_angle(rotation.y, _base_yaw, 1.0 - exp(-TURN_RATE * delta))


func _apply_colors() -> void:
	if _body != null:
		MeshDress.dress_mannequin(_body, jacket_color)


func _label_name() -> void:
	var label := get_node_or_null("NameLabel") as Label3D
	if label != null:
		label.text = display_name

## DAVID — the player character.
##
## Third-person, and UNARMED BY DEFAULT. That default is a design fact about
## this game rather than a stage of implementation: David starts on his own
## road with his hands empty, and melee is what he has. There is a `Loadout`
## enum with exactly one member today so that adding a weapon later is an
## additive change to a stated concept, not a retrofit of one.
##
## MOVEMENT TUNING is carried over from the prototype's `src/player/tuning.js`,
## which was calibrated against Modern Warfare's numbers (authored in inches at
## 20 units = 1 ft, converted to metres). Keeping the numbers means the character
## keeps his weight and pace across the engine change, which is the part players
## actually notice:
##
##   walk        4.57 m/s      sprint      7.01 m/s
##   gravity    20.6 m/s^2     jump apex   0.60 m
##   turn rate   6.2 rad/s
##
## The state that is deliberately NOT ported yet: slide, mantle, lean, prone,
## tactical sprint, ADS. Those belong to a shooter that this slice is not trying
## to be yet, and every one of them is a place to get the feel subtly wrong
## while there is nothing to shoot at to judge it against.

class_name DavidController
extends CharacterBody3D

signal melee_swung
## Emitted when David's melee sweep connects with something.
signal melee_hit(target: Node3D)

enum Loadout {
	## Hands empty, melee ready. The default and, for now, the only state.
	UNARMED,
}

const WALK_SPEED := 4.57
const SPRINT_SPEED := 7.01
const GRAVITY := 20.6
const JUMP_APEX := 0.6
## v = sqrt(2 g h), solved from the apex so tuning the apex stays meaningful.
const JUMP_SPEED := 4.972
## Ground response. 92 m/s^2 reaches walk speed in ~50 ms — effectively instant,
## which is what makes the character feel tight rather than floaty.
const GROUND_ACCEL := 92.0
const GROUND_DECEL := 52.0
## Air control is a quarter of ground authority and cannot add speed.
const AIR_ACCEL_SCALE := 0.25
## Radians/second the body turns toward its heading. Scaled up by how far there
## is to turn, so an about-face does not crawl.
const TURN_RATE := 6.2
## Grace windows that hide input and timing error.
const COYOTE_TIME := 0.09
const JUMP_BUFFER := 0.13

const MELEE_REACH := 1.9
const MELEE_RADIUS := 0.55
const MELEE_COOLDOWN := 0.55
## Seconds into the swing at which the hitbox is tested.
const MELEE_CONTACT := 0.14

var loadout: Loadout = Loadout.UNARMED
## Set by the car while David is a passenger; movement and collision go quiet.
var driving: bool = false

var _coyote := 0.0
var _buffered_jump := 0.0
var _melee_timer := 0.0
var _swing := 0.0
var _facing := 0.0

@onready var _camera: ThirdPersonCamera = $CamYaw
@onready var _body: Node3D = $Body

var _melee_query := PhysicsShapeQueryParameters3D.new()
var _melee_shape := SphereShape3D.new()


func _ready() -> void:
	_facing = rotation.y
	_melee_shape.radius = MELEE_RADIUS
	_melee_query.shape = _melee_shape
	_melee_query.collide_with_bodies = true
	_melee_query.collide_with_areas = false
	# Never report ourselves as a melee hit.
	var skip: Array[RID] = [get_rid()]
	_melee_query.exclude = skip
	PlayerInput.jump_pressed.connect(_on_jump)
	PlayerInput.melee_pressed.connect(_on_melee)


func _physics_process(delta: float) -> void:
	_melee_timer = maxf(0.0, _melee_timer - delta)
	if _swing > 0.0:
		var before := _swing
		_swing = maxf(0.0, _swing - delta)
		# Test the sweep once, as it passes through the contact frame.
		if before > MELEE_CONTACT and _swing <= MELEE_CONTACT:
			_resolve_melee()
	_animate_body(delta)

	if driving:
		# The car owns our transform while we are in it. Zero the velocity so
		# we do not resume a stale slide on the frame we get out.
		velocity = Vector3.ZERO
		return

	_apply_gravity(delta)
	_apply_movement(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		_coyote = COYOTE_TIME
		# A small downward bias keeps the controller pinned to the floor over
		# seams between collision boxes instead of skipping along them.
		if velocity.y < 0.0:
			velocity.y = -2.0
	else:
		_coyote = maxf(0.0, _coyote - delta)
		velocity.y -= GRAVITY * delta

	_buffered_jump = maxf(0.0, _buffered_jump - delta)
	if _buffered_jump > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_SPEED
		_buffered_jump = 0.0
		_coyote = 0.0


func _apply_movement(delta: float) -> void:
	var stick := PlayerInput.move_axis()
	# Movement is relative to where the CAMERA is looking, which is what makes
	# a third-person controller feel like driving a character rather than a
	# tank. The body then turns to follow, at a limited rate.
	var yaw := _camera.yaw()
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish := (right * stick.x + forward * stick.y).limit_length(1.0)

	var speed := SPRINT_SPEED if (PlayerInput.sprinting() and stick.y > 0.4) else WALK_SPEED
	# You cannot sprint mid-swing.
	if _swing > 0.0:
		speed = WALK_SPEED * 0.45

	var target := wish * speed
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var rate := GROUND_ACCEL if wish.length_squared() > 0.001 else GROUND_DECEL
	if not is_on_floor():
		rate *= AIR_ACCEL_SCALE
	planar = planar.move_toward(target, rate * delta)
	velocity.x = planar.x
	velocity.z = planar.z

	# Turn the body toward the direction of travel. Scaling the rate by the
	# size of the turn stops a 180 from taking half a second.
	if wish.length_squared() > 0.01:
		var want := atan2(-wish.x, -wish.z)
		var diff := wrapf(want - _facing, -PI, PI)
		var scale := 1.0 + absf(diff) / PI * 2.0
		_facing = wrapf(_facing + clampf(diff, -TURN_RATE * scale * delta,
			TURN_RATE * scale * delta), -PI, PI)
	rotation.y = _facing


# ------------------------------------------------------------------ melee

func _on_jump() -> void:
	if not driving:
		_buffered_jump = JUMP_BUFFER


func _on_melee() -> void:
	if driving or _melee_timer > 0.0:
		return
	_melee_timer = MELEE_COOLDOWN
	_swing = MELEE_COOLDOWN * 0.55
	melee_swung.emit()


## Sweep a sphere out in front of David and report what it touches. Nothing in
## the slice takes damage yet — there is no one on the street to hit — so this
## deliberately stops at "report the hit" rather than inventing a damage model
## that has no receiver.
func _resolve_melee() -> void:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, 1.25, 0.0) \
		+ -global_transform.basis.z * MELEE_REACH
	_melee_query.transform = Transform3D(Basis.IDENTITY, origin)
	var hits := space.intersect_shape(_melee_query, 4)
	for hit in hits:
		# Explicit cast: Dictionary.get() returns Variant, and with
		# INFERRING_FROM_VARIANT treated as error, `:=` fails at compile.
		var collider := hit.get("collider") as Node3D
		if collider != null and collider != self:
			melee_hit.emit(collider)
			return


# ---------------------------------------------------------------- body pose
#
# David's body is a handful of primitives (see david.tscn). There is no
# skeleton and no imported animation in this slice: a rig is a large piece of
# work whose quality is judged against how it moves, and there is nothing yet
# for it to move around. What is here is enough to read direction, pace and the
# fact of a swing at third-person distance.

func _animate_body(delta: float) -> void:
	if _body == null:
		return
	# Cast, not an `is` test: an `is` check does not narrow the static type, so
	# the result stays `Node` and `Node.rotation` does not exist — a parse error.
	var arm := _body.get_node_or_null("ArmR") as Node3D
	if arm != null:
		# Swing the right arm through the punch, then settle it back.
		var t := 1.0 - (_swing / maxf(MELEE_COOLDOWN * 0.55, 0.001))
		var throw := sin(clampf(t, 0.0, 1.0) * PI) if _swing > 0.0 else 0.0
		arm.rotation.x = lerpf(arm.rotation.x, -throw * 2.2, 1.0 - exp(-24.0 * delta))

	# A gentle bob keyed to ground speed, so walking reads as walking.
	var planar := Vector3(velocity.x, 0.0, velocity.z).length()
	var phase := Time.get_ticks_msec() * 0.001 * (planar * 1.6)
	_body.position.y = sin(phase * 2.0) * 0.035 * clampf(planar / WALK_SPEED, 0.0, 1.0)


## Called by the car on exit, to hand control back cleanly.
func teleport(to: Transform3D) -> void:
	global_transform = to
	velocity = Vector3.ZERO
	_facing = to.basis.get_euler().y
	rotation.y = _facing

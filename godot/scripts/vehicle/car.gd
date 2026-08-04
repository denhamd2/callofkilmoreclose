## THE CAR — parked at the kerb outside 18 Kilmore Close.
##
## WHY THIS IS NOT A VehicleBody3D. Godot ships a raycast-suspension vehicle
## body, and it is the wrong tool here. It needs suspension, friction and mass
## tuning to stop it rolling or skating; it is timestep-sensitive; and on a slow
## phone, where the physics tick is the first thing to suffer, it is exactly the
## kind of system that goes unstable. This is a KINEMATIC BICYCLE MODEL on a
## CharacterBody3D instead — the same model the prototype used, and for the same
## reasons. It is stable at any timestep, it cannot tunnel through a wall, and
## it gives the heavy, slightly-understeering feel a saloon should have. Getting
## a car that behaves identically on desktop and on a struggling phone is worth
## more in a vertical slice than suspension travel is.
##
## Driving numbers carried over from the prototype's `src/vehicle/index.js`.
##
## THE CAMERA IS NEVER HANDED OVER. There is no second camera rig in this game.
## Driving disables David's controller and moves him to the driver's seat every
## physics step, so the camera he already owns comes along. That means there is
## no rig to keep in sync, no blend between two cameras, and no state the player
## does not already understand — which is why the prototype did it this way too.

class_name Car
extends CharacterBody3D

signal entered
signal exited

const MAX_SPEED := 22.0
const MAX_REVERSE := -6.0
const ACCEL := 9.5
const BRAKE := 18.0
## Quadratic-ish air drag and constant rolling resistance.
const DRAG := 1.15
const ROLL_RESIST := 2.4
## Wheelbase — the bicycle model's only geometric input.
const WHEELBASE := 2.62
const MAX_STEER := 0.52
## Steering authority falls off with speed, or the car spins on the spot at
## 60 km/h. This is the speed at which authority has halved.
const STEER_FALLOFF := 11.0
const STEER_RATE := 3.4
const GRAVITY := 20.6

## How close David must be to get in.
const ENTER_DIST := 3.6
## Where the driver sits, relative to the car.
const SEAT := Vector3(-0.34, 0.62, -0.25)
## Candidate exit points, tried in order, relative to the car.
const EXIT_SPOTS: Array[Vector3] = [
	Vector3(-1.85, 0.1, -0.2),
	Vector3(1.85, 0.1, -0.2),
	Vector3(-1.85, 0.1, 1.6),
	Vector3(0.0, 0.1, -3.2),
]

var driver: DavidController = null
var speed := 0.0

var _steer := 0.0
var _heading := 0.0
var _prompt_shown := false
## Resolved once. `get_nodes_in_group` allocates an array on every call, and
## the prompt check runs every physics tick.
var _player: DavidController = null

@onready var _prompt: Label = get_node_or_null("../HUD/Prompt")


func _ready() -> void:
	_heading = rotation.y
	PlayerInput.interact_pressed.connect(_on_interact)


## Park the car. Use this rather than assigning `global_transform` directly:
## the bicycle model integrates its own `_heading` and overwrites `rotation.y`
## from it every step, so a transform set behind its back is silently thrown
## away the moment the player pulls off.
func place(at: Transform3D) -> void:
	global_transform = at
	_heading = at.basis.get_euler().y
	speed = 0.0
	_steer = 0.0


func _physics_process(delta: float) -> void:
	if driver != null:
		_drive(delta)
	else:
		_coast(delta)
		_update_prompt()


func _drive(delta: float) -> void:
	var stick := PlayerInput.move_axis()
	var throttle := stick.y
	var steer_input := -stick.x

	# Longitudinal. Pushing back while moving forward is the brake, not
	# reverse — reverse only engages once the car has actually stopped.
	if throttle > 0.05:
		speed += ACCEL * throttle * delta
	elif throttle < -0.05:
		if speed > 0.5:
			# Still rolling forward: this is the brake pedal.
			speed -= BRAKE * absf(throttle) * delta
		else:
			# Stopped (or already reversing): back out, slowly.
			speed = maxf(speed - ACCEL * 0.6 * absf(throttle) * delta, MAX_REVERSE)
	if PlayerInput.handbrake():
		speed = move_toward(speed, 0.0, BRAKE * 1.4 * delta)

	# Passive losses: rolling resistance always, drag scaling with speed.
	var loss := ROLL_RESIST + DRAG * absf(speed) * 0.35
	speed = move_toward(speed, 0.0, loss * delta)
	speed = clampf(speed, MAX_REVERSE, MAX_SPEED)

	# Steering authority falls away as speed rises.
	var authority := 1.0 / (1.0 + absf(speed) / STEER_FALLOFF)
	var want := steer_input * MAX_STEER * authority
	_steer = move_toward(_steer, want, STEER_RATE * delta)

	# Kinematic bicycle: yaw rate = v / L * tan(steer).
	if absf(speed) > 0.01:
		_heading = wrapf(_heading + (speed / WHEELBASE) * tan(_steer) * delta,
			-PI, PI)
	rotation.y = _heading

	var fwd := -global_transform.basis.z
	velocity = fwd * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	# Scrub speed on walls only. Floor contacts also appear in the slide list
	# (especially box-on-box edge normals), and treating those as obstacles
	# left the car unable to pull away from the kerb.
	if is_on_wall():
		speed *= 0.55

	_seat_driver()


func _coast(delta: float) -> void:
	speed = move_toward(speed, 0.0, (ROLL_RESIST + 4.0) * delta)
	velocity = -global_transform.basis.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()


func _seat_driver() -> void:
	# Move David with the car. He keeps his own camera, so this is all the
	# handover there is.
	driver.global_transform = global_transform.translated_local(SEAT)


# ------------------------------------------------------------- enter and exit

func _nearest_player() -> DavidController:
	if _player != null:
		return _player
	for p in get_tree().get_nodes_in_group("player"):
		if p is DavidController:
			_player = p
			return _player
	return null


func _update_prompt() -> void:
	if _prompt == null:
		return
	var david := _nearest_player()
	var near := david != null and not david.driving \
		and david.global_position.distance_to(global_position) <= ENTER_DIST
	if near != _prompt_shown:
		_prompt_shown = near
		_prompt.visible = near
		_prompt.text = "Press F  —  Get in"


func _on_interact() -> void:
	if driver != null:
		_exit()
		return
	var david := _nearest_player()
	if david == null or david.driving:
		return
	if david.global_position.distance_to(global_position) > ENTER_DIST:
		return
	_enter(david)


func _enter(david: DavidController) -> void:
	driver = david
	david.driving = true
	# Take the character out of the physics world so he cannot collide with the
	# car he is sitting in.
	david.set_collision_layer_value(2, false)
	david.set_collision_mask_value(1, false)
	_seat_driver()
	# Cast rather than `is`-test: GDScript's analyser does not narrow a type
	# from an `is` check, so a bare `get_node_or_null()` result stays statically
	# `Node` and `Node.set_driving()` does not exist. This is a parse error, not
	# a runtime one — the project will not load with it.
	var cam := david.get_node_or_null("CamYaw") as ThirdPersonCamera
	if cam != null:
		cam.set_driving(true, get_rid())
	if _prompt != null:
		_prompt.visible = false
		_prompt_shown = false
	entered.emit()


func _exit() -> void:
	var david := driver
	driver = null
	speed = 0.0
	_steer = 0.0

	# Put him down at the first exit point with room for him to stand.
	var space := get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.78
	probe.shape = capsule
	probe.collision_mask = 1
	var chosen := global_transform.translated_local(EXIT_SPOTS[0])
	for spot in EXIT_SPOTS:
		var candidate := global_transform.translated_local(spot)
		probe.transform = Transform3D(Basis.IDENTITY,
			candidate.origin + Vector3(0.0, 0.9, 0.0))
		if space.intersect_shape(probe, 1).is_empty():
			chosen = candidate
			break

	david.driving = false
	david.set_collision_layer_value(2, true)
	david.set_collision_mask_value(1, true)
	david.teleport(Transform3D(global_transform.basis, chosen.origin))
	var cam := david.get_node_or_null("CamYaw") as ThirdPersonCamera
	if cam != null:
		cam.set_driving(false)
	exited.emit()

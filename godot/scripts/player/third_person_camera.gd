## THIRD-PERSON CAMERA — the over-the-shoulder boom.
##
## Node layout (see david.tscn); each level does exactly one job, which is what
## keeps the maths out of the code:
##
##   CamYaw       (this script)  yaw only, follows the look input
##    └ SpringArm3D              pitch, and keeps the boom out of walls
##       └ CamOffset             the shoulder offset, in camera space
##          └ Camera3D
##
## The shoulder offset lives BELOW the spring arm on purpose. SpringArm3D
## overwrites the transform of its own direct children every frame — that is
## how it shortens the boom — so an offset applied to a direct child is
## silently discarded. One node of indirection keeps it.
##
## Values carried over from the prototype's THIRD_PERSON block: 3.1 m boom,
## 0.62 m to camera-right so David sits left of frame, 0.22 m probe radius.

class_name ThirdPersonCamera
extends Node3D

const DISTANCE := 3.45
const DRIVE_DISTANCE := 6.2
## Positive is camera-right, so the character sits left of centre.
const SHOULDER := 0.52
const DRIVE_SHOULDER := 0.0
## Height of the pivot above the character's feet.
const PIVOT_HEIGHT := 1.38
const DRIVE_PIVOT_HEIGHT := 1.9
## Sphere radius of the boom's collision probe, and how far it holds off a
## surface it hits so the near plane never clips through.
const PROBE_RADIUS := 0.22
const PROBE_MARGIN := 0.12

const PITCH_MIN := deg_to_rad(-64.0)
const PITCH_MAX := deg_to_rad(38.0)
## Seconds-to-63% for the boom easing between walking and driving framing.
const EASE_TAU := 0.18

var _yaw := 0.0
var _pitch := deg_to_rad(-8.0)
## 0 = on foot, 1 = driving. Eased, so getting into the car pulls the camera
## back smoothly instead of cutting.
var _drive_blend := 0.0
var _driving := false

@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _offset: Node3D = $SpringArm3D/CamOffset


## The pivot is TOP-LEVEL: it follows the character's position but NOT his
## rotation. This is the difference between a third-person camera and a camera
## bolted to the character's head. David turns constantly — to face his
## direction of travel — and if the boom inherited that, every change of
## direction would whip the view around and the player would never be able to
## look where they wanted. Position is copied each frame; orientation is the
## camera's own.
var _follow: Node3D
## The vehicle to orbit while driving, set by `set_driving()`.
var _vehicle: Node3D = null

## How quickly the view swings back behind the car, in seconds. Slow enough that a
## turn does not whip the camera, fast enough that you are looking forward again
## within about a second.
const RECENTRE_TAU := 0.45


func _ready() -> void:
	_follow = get_parent() as Node3D
	top_level = true
	_yaw = global_rotation.y
	var probe := SphereShape3D.new()
	probe.radius = PROBE_RADIUS
	_arm.shape = probe
	_arm.margin = PROBE_MARGIN
	# Collide with world geometry only (layer 1). Without this the boom rams
	# into the player's own capsule and sits permanently at minimum length.
	_arm.collision_mask = 1
	_arm.spring_length = DISTANCE


func _process(delta: float) -> void:
	var look := PlayerInput.consume_look(delta)
	_yaw = wrapf(_yaw - look.x, -PI, PI)
	_pitch = clampf(_pitch - look.y, PITCH_MIN, PITCH_MAX)

	# While driving, swing round behind the car and stay there. The mouse can still
	# nudge the view, but it recentres — otherwise reversing or turning leaves you
	# looking at the side of the car with no idea where you are going.
	if _driving and _vehicle != null:
		# Pogo's longitudinal axis is local +X, and a camera looking along a
		# direction d has yaw atan2(-d.x, -d.z).
		var fwd := _vehicle.global_basis.x
		var behind := atan2(-fwd.x, -fwd.z)
		_yaw = lerp_angle(_yaw, behind, 1.0 - exp(-delta / RECENTRE_TAU))

	var k := 1.0 - exp(-delta / EASE_TAU)
	_drive_blend = lerpf(_drive_blend, 1.0 if _driving else 0.0, k)

	# On foot the pivot rides David. While driving it rides the CAR instead: David is
	# now seated low inside the cabin, so pivoting on him put the boom origin inside
	# the bodywork. Pivoting on the car keeps the view behind the vehicle, which is
	# also what a driving camera should frame.
	var anchor := _follow
	if _drive_blend > 0.001 and _vehicle != null:
		anchor = _vehicle
	if anchor != null:
		var h := lerpf(PIVOT_HEIGHT, DRIVE_PIVOT_HEIGHT, _drive_blend)
		global_position = anchor.global_position + Vector3(0.0, h, 0.0)
	global_rotation = Vector3(0.0, _yaw, 0.0)
	_arm.rotation.x = _pitch
	_arm.spring_length = lerpf(DISTANCE, DRIVE_DISTANCE, _drive_blend)
	_offset.position.x = lerpf(SHOULDER, DRIVE_SHOULDER, _drive_blend)


## Current yaw, in radians. Movement is resolved against this: on foot, "away
## from the camera" is what forward means.
func yaw() -> float:
	return _yaw


## World-space direction the camera is looking (includes pitch).
func aim_direction() -> Vector3:
	var cam := $SpringArm3D/CamOffset/Camera3D as Camera3D
	if cam != null:
		return -cam.global_transform.basis.z.normalized()
	var dir := Vector3(-sin(_yaw), sin(_pitch), -cos(_yaw) * cos(_pitch))
	return dir.normalized()


## Switch between on-foot and driving framing.
##
## `vehicle` is the driven body's RID. The boom must be told to ignore it: the
## pivot sits just above the roof of the car you are inside, so without an
## exclusion the probe hits your own bonnet and pins the camera at minimum
## length for the whole drive.
## `body` is the vehicle node the camera should orbit while driving. Without it the
## pivot stays on David, who sits inside the cabin, and the boom starts inside the
## bodywork.
func set_driving(on: bool, vehicle: RID = RID(), body: Node3D = null) -> void:
	_driving = on
	if on:
		_vehicle = body
		if vehicle.is_valid():
			_arm.add_excluded_object(vehicle)
	else:
		_vehicle = null
		_arm.clear_excluded_objects()

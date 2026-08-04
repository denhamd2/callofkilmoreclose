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

const DISTANCE := 3.1
const DRIVE_DISTANCE := 6.2
## Positive is camera-right, so the character sits left of centre.
const SHOULDER := 0.62
const DRIVE_SHOULDER := 0.0
## Height of the pivot above the character's feet.
const PIVOT_HEIGHT := 1.5
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

	var k := 1.0 - exp(-delta / EASE_TAU)
	_drive_blend = lerpf(_drive_blend, 1.0 if _driving else 0.0, k)

	if _follow != null:
		var h := lerpf(PIVOT_HEIGHT, DRIVE_PIVOT_HEIGHT, _drive_blend)
		global_position = _follow.global_position + Vector3(0.0, h, 0.0)
	global_rotation = Vector3(0.0, _yaw, 0.0)
	_arm.rotation.x = _pitch
	_arm.spring_length = lerpf(DISTANCE, DRIVE_DISTANCE, _drive_blend)
	_offset.position.x = lerpf(SHOULDER, DRIVE_SHOULDER, _drive_blend)


## Current yaw, in radians. Movement is resolved against this: on foot, "away
## from the camera" is what forward means.
func yaw() -> float:
	return _yaw


## Switch between on-foot and driving framing.
##
## `vehicle` is the driven body's RID. The boom must be told to ignore it: the
## pivot sits just above the roof of the car you are inside, so without an
## exclusion the probe hits your own bonnet and pins the camera at minimum
## length for the whole drive.
func set_driving(on: bool, vehicle: RID = RID()) -> void:
	_driving = on
	if on:
		if vehicle.is_valid():
			_arm.add_excluded_object(vehicle)
	else:
		_arm.clear_excluded_objects()

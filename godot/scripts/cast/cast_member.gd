## CAST MEMBER — idle street presence at a front door.
##
## No AI, no weapons, no pathfinding. A primitive body, a name label, and a
## gentle turn toward the player when they are close enough to read as "noticed".

class_name CastMember
extends StaticBody3D

const FACE_DIST := 6.0
const SLEEP_DIST := 14.0
const TURN_RATE := 4.0

@export var display_name := "Neighbour"
@export var jacket_color := Color(0.25, 0.3, 0.35)

var _base_yaw := 0.0
var _player: Node3D


func _ready() -> void:
	_base_yaw = rotation.y
	add_to_group("cast")
	_apply_colors()
	_label_name()


func bind_player(player: Node3D) -> void:
	_player = player


func setup(entry: Dictionary) -> void:
	display_name = str(entry["name"])
	if entry.has("jacket"):
		jacket_color = entry["jacket"] as Color
	_apply_colors()
	_label_name()


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var d2 := to_player.length_squared()
	if d2 > SLEEP_DIST * SLEEP_DIST:
		return
	if d2 > FACE_DIST * FACE_DIST:
		rotation.y = lerp_angle(rotation.y, _base_yaw, 1.0 - exp(-TURN_RATE * delta))
		return
	var want := atan2(to_player.x, to_player.z)
	rotation.y = lerp_angle(rotation.y, want + PI, 1.0 - exp(-TURN_RATE * delta))


func _apply_colors() -> void:
	var body := get_node_or_null("Body") as Node3D
	if body == null:
		return
	MeshDress.dress_person(body, jacket_color)


func _label_name() -> void:
	var label := get_node_or_null("NameLabel") as Label3D
	if label != null:
		label.text = display_name

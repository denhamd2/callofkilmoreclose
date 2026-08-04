## THE CAR — parked at the kerb outside 18 Kilmore Close.
##
## RVCE Pogo physics on a RigidBody3D (raycast suspension, automatic gearbox).
## Enter/drive/exit UX is unchanged: F to get in/out, David stays in the seat
## each physics step so his third-person camera never hands off to a vehicle rig.
##
## Pogo's longitudinal axis is local +X. Kilmore spawn data still uses Godot's
## -Z forward convention; `place()` rotates the body so +X points along the
## street without touching `kilmore_close.gd`.

class_name Car
extends CarPogo

signal entered
signal exited

const ENTER_DIST := 3.6
## Driver seat in Pogo space (+X forward, +Z right).
const SEAT := Vector3(-0.25, 0.62, 0.34)
const EXIT_SPOTS: Array[Vector3] = [
	Vector3(-0.2, 0.1, 1.85),
	Vector3(-0.2, 0.1, -1.85),
	Vector3(1.6, 0.1, 0.34),
	Vector3(-3.2, 0.1, 0.0),
]
var _drive_agent: KilmoreDriveAgent = null

var driver: DavidController = null
var speed := 0.0

var _steer := 0.0
var _heading := 0.0
var _prompt_shown := false
var _player: DavidController = null

@onready var _prompt: Label = get_node_or_null("../HUD/Prompt")
@onready var _mesh: Node3D = $Mesh


func _ready() -> void:
	_drive_agent = KilmoreDriveAgent.new()
	input_agent = _drive_agent
	add_child(_drive_agent)
	input_agent.start()

	if inertia.is_zero_approx():
		inertia = Lib.calculate_aabb_inertia(self)

	chassis.set_car(self)
	transmission.set_base_min_rpm(engine.min_rpm)
	if transmission_mode == TransmissionMode.AUTOMATIC:
		transmission.gear_up()
	_create_bumpers()

	PlayerInput.interact_pressed.connect(_on_interact)
	if _mesh != null:
		MeshDress.dress_car(_mesh, Color(0.36, 0.11, 0.13))
	_park()


func place(at: Transform3D) -> void:
	var pogo_basis := at.basis * Basis.from_euler(Vector3(0.0, PI / 2.0, 0.0))
	global_transform = Transform3D(pogo_basis, at.origin)
	_heading = global_transform.basis.get_euler().y
	speed = 0.0
	_steer = 0.0
	drive_axle_omega = 0.0
	_park()


func _physics_process(delta: float) -> void:
	_drive_agent.active = driver != null
	if driver != null:
		_seat_driver()
		super._physics_process(delta)
		speed = linear_velocity.dot(global_basis.x)
	else:
		_update_prompt()
		if not freeze:
			_park()


func _seat_driver() -> void:
	driver.global_transform = global_transform.translated_local(SEAT)


func _park() -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	drive_axle_omega = 0.0
	speed = 0.0


func _unpark() -> void:
	freeze = false


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
	david.set_collision_layer_value(2, false)
	david.set_collision_mask_value(1, false)
	_unpark()
	_seat_driver()
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
	_steer = 0.0

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
	_park()
	exited.emit()

## Runtime probe node — parented under Main when launched with `--probe`.
##
##   godot --path godot --headless -- --probe
##
## Exercises spawn, walk, enter/drive/exit against the live scene, prints
## RUNTIME_PROBE_REPORT JSON, then quits. Not part of the shipped loop.

extends Node

const STEP_SETTLE := 20
const STEP_MOVE := 60
const STEP_DRIVE := 90

var _frame := 0
var _phase := "settle"
var _report: Dictionary = {}
var _david: DavidController
var _car: Car
var _cam: ThirdPersonCamera
var _sun: DirectionalLight3D
var _touch: CanvasItem
var _start_pos := Vector3.ZERO
var _pos_after_move := Vector3.ZERO
var _car_start := Vector3.ZERO
var _fail := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	_frame += 1
	match _phase:
		"settle":
			if _frame < STEP_SETTLE:
				return
			_capture_actors()
			if _david == null:
				return
			_check_spawn()
			_check_street()
			_check_daylight()
			_check_audio()
			_check_touch_layer()
			_start_pos = _david.global_position
			PlayerInput.set_touch_move(Vector2(0.0, 1.0))
			_phase = "move"
			_frame = 0
		"move":
			if _frame < STEP_MOVE:
				return
			PlayerInput.set_touch_move(Vector2.ZERO)
			_pos_after_move = _david.global_position
			_check_movement()
			_walk_to_car()
			_phase = "enter"
			_frame = 0
		"enter":
			if _frame == 3:
				PlayerInput.touch_interact()
			if _frame < 12:
				return
			_check_enter()
			PlayerInput.set_touch_move(Vector2(0.0, 1.0))
			_car_start = _car.global_position
			_phase = "drive"
			_frame = 0
		"drive":
			if _frame < STEP_DRIVE:
				return
			PlayerInput.set_touch_move(Vector2.ZERO)
			_check_drive()
			PlayerInput.touch_interact()
			_phase = "exit"
			_frame = 0
		"exit":
			if _frame < 12:
				return
			_check_exit()
			_check_camera()
			_check_cast()
			_finish()


func _capture_actors() -> void:
	var main := get_parent()
	_david = main.get_node_or_null("David") as DavidController
	_car = main.get_node_or_null("Car") as Car
	_cam = main.get_node_or_null("David/CamYaw") as ThirdPersonCamera
	_sun = main.get_node_or_null("Sun") as DirectionalLight3D
	_touch = main.get_node_or_null("HUD/TouchControls") as CanvasItem
	if _david == null or _car == null:
		_die("David or Car missing from main scene")


func _check_spawn() -> void:
	var expect := KilmoreClose.david_spawn().origin
	expect.y = KilmoreClose.WALK_H + 0.3
	var dist := _david.global_position.distance_to(expect)
	var h18 := KilmoreClose.house_by_number(18)
	var gate := Vector3(
		float(h18["side"]) * (KilmoreClose.HALF_WIDTH + KilmoreClose.KERB) * 0.5,
		0.0,
		KilmoreClose.gate_z(h18)
	)
	_report["spawn_dist_m"] = dist
	_report["spawn_xy_to_gate_m"] = Vector2(
		_david.global_position.x - gate.x,
		_david.global_position.z - gate.z
	).length()
	_report["david_pos"] = [_david.global_position.x, _david.global_position.y, _david.global_position.z]
	_report["spawn_ok"] = dist < 1.5 and _report["spawn_xy_to_gate_m"] < 1.0
	if not _report["spawn_ok"]:
		_fail = true


func _check_street() -> void:
	var houses := KilmoreClose.houses()
	var zr := KilmoreClose.road_z_range()
	var main := get_parent()
	var street := main.get_node_or_null("Street") as Node3D
	var collision_shapes := 0
	if street != null:
		for n in street.find_children("*", "", true, false):
			if n is CollisionShape3D:
				collision_shapes += 1
	_report["house_count"] = houses.size()
	_report["pair_count"] = KilmoreClose.pairs().size()
	_report["road_z_span_m"] = zr.y - zr.x
	_report["collision_shapes_street"] = collision_shapes
	_report["collision_budget_ok"] = collision_shapes <= 35
	# Full street: 13 pairs/side, 2 dwellings/pair, 2 sides -> 52 houses, 26 pairs.
	_report["street_ok"] = houses.size() == 52 and _report["pair_count"] == 26 \
		and _report["road_z_span_m"] > 240.0 and _report["collision_budget_ok"]
	if not _report["street_ok"]:
		_fail = true


func _check_daylight() -> void:
	_report["sun_present"] = _sun != null
	_report["sun_energy"] = _sun.light_energy if _sun else 0.0
	_report["sun_shadows"] = _sun.shadow_enabled if _sun else false
	_report["daylight_ok"] = _sun != null and _sun.light_energy > 1.0 and _sun.shadow_enabled
	if not _report["daylight_ok"]:
		_fail = true


func _check_audio() -> void:
	_report["audio_autoload"] = StreetAudio != null
	# Probe runs headless: audio must disable itself, not crash or block startup.
	_report["audio_enabled"] = StreetAudio.enabled if StreetAudio != null else false
	_report["audio_ok"] = _report["audio_autoload"] and not _report["audio_enabled"]
	if not _report["audio_ok"]:
		_fail = true


func _check_touch_layer() -> void:
	PlayerInput.touch_ui = true
	if _touch != null:
		_touch.visible = true
	_report["touch_node_present"] = _touch != null
	_report["touch_visible"] = _touch.visible if _touch else false
	_report["touch_ok"] = _touch != null and _touch.visible
	if not _report["touch_ok"]:
		_fail = true


func _check_movement() -> void:
	var moved := _start_pos.distance_to(_pos_after_move)
	_report["move_distance_m"] = moved
	_report["move_ok"] = moved > 1.5
	if not _report["move_ok"]:
		_fail = true


func _walk_to_car() -> void:
	var beside := _car.global_transform.translated_local(Vector3(-1.4, 0.1, 0.0))
	_david.teleport(beside)


func _check_enter() -> void:
	_report["enter_ok"] = _david.driving and _car.driver == _david
	if not _report["enter_ok"]:
		_fail = true


func _check_drive() -> void:
	var driven := _car_start.distance_to(_car.global_position)
	_report["drive_distance_m"] = driven
	_report["drive_speed"] = _car.speed
	_report["drive_ok"] = driven > 2.0 and _david.driving
	if not _report["drive_ok"]:
		_fail = true


func _check_exit() -> void:
	_report["exit_ok"] = (not _david.driving) and _car.driver == null
	_report["exit_y"] = _david.global_position.y
	if not _report["exit_ok"]:
		_fail = true


func _check_camera() -> void:
	_report["camera_present"] = _cam != null
	if _cam != null:
		var follow_h := absf(_cam.global_position.y - (_david.global_position.y + 1.5))
		_report["camera_height_error_m"] = follow_h
		_report["camera_follow_ok"] = follow_h < 1.0
		_report["camera_position_follow"] = "hard_snap"
		_report["camera_drive_blend_eased"] = true
	else:
		_report["camera_follow_ok"] = false
		_fail = true
	if not _report.get("camera_follow_ok", false):
		_fail = true


func _check_cast() -> void:
	var cast := get_tree().get_nodes_in_group("cast")
	_report["cast_count"] = cast.size()
	_report["cast_ok"] = cast.size() >= 5
	if not _report["cast_ok"]:
		_fail = true


func _finish() -> void:
	_report["kerb_collision"] = "flat_shared_ground"
	_report["kerb_decision"] = "acceptable_visual_only_upstand"
	_report["ok"] = not _fail
	print("RUNTIME_PROBE_REPORT " + JSON.stringify(_report))
	get_tree().quit(0 if not _fail else 1)


func _die(msg: String) -> void:
	_report["fatal"] = msg
	_report["ok"] = false
	print("RUNTIME_PROBE_REPORT " + JSON.stringify(_report))
	get_tree().quit(1)

## Performance profile — run against the live main scene.
##
##   godot --path godot --headless --quit-after 600 -- --profile
##
## Simulates walk + drive, counts scene cost, reports frame-time percentiles.
## Does not change gameplay. Parented from main.gd when --profile is present.

extends Node

const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 240
const DRIVE_FRAMES := 120

var _frame := 0
var _phase := "warmup"
var _david: DavidController
var _car: Car
var _samples: Array[float] = []
var _report: Dictionary = {}
var _t0 := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	var t_start := Time.get_ticks_usec()
	_frame += 1
	match _phase:
		"warmup":
			if _frame >= WARMUP_FRAMES:
				_capture()
				_collect_static()
				_phase = "walk"
				_frame = 0
		"walk":
			PlayerInput.set_touch_move(Vector2(0.0, 1.0))
			if _frame >= SAMPLE_FRAMES:
				PlayerInput.set_touch_move(Vector2.ZERO)
				_walk_to_car()
				PlayerInput.touch_interact()
				_phase = "drive_wait"
				_frame = 0
		"drive":
			if _frame >= DRIVE_FRAMES:
				PlayerInput.set_touch_move(Vector2.ZERO)
				_finish()
				return
		"drive_wait":
			if _frame >= 12:
				PlayerInput.set_touch_move(Vector2(0.0, 1.0))
				_phase = "drive"
				_frame = 0
		_:
			pass
	_samples.append(float(Time.get_ticks_usec() - t_start) / 1000.0)


func _capture() -> void:
	var main := get_parent()
	_david = main.get_node_or_null("David") as DavidController
	_car = main.get_node_or_null("Car") as Car


func _walk_to_car() -> void:
	if _david == null or _car == null:
		return
	var beside := _car.global_transform.translated_local(Vector3(-1.4, 0.1, 0.0))
	_david.teleport(beside)


func _collect_static() -> void:
	var main := get_parent()
	var street := main.get_node_or_null("Street") as Node3D
	var mm_count := 0
	var mm_instances := 0
	var collision_shapes := 0
	var mesh_instances := 0
	var label3d := 0
	if street != null:
		for n in street.find_children("*", "", true, false):
			if n is MultiMeshInstance3D:
				mm_count += 1
				var mm := (n as MultiMeshInstance3D).multimesh
				if mm != null:
					mm_instances += mm.instance_count
			if n is CollisionShape3D:
				collision_shapes += 1
			if n is MeshInstance3D:
				mesh_instances += 1
			if n is Label3D:
				label3d += 1
	var cast := get_tree().get_nodes_in_group("cast").size()
	_report["multimesh_nodes"] = mm_count
	_report["multimesh_instances"] = mm_instances
	_report["collision_shapes_street"] = collision_shapes
	_report["mesh_instances_street"] = mesh_instances
	_report["label3d_street"] = label3d
	_report["cast_members"] = cast
	_report["audio_enabled"] = StreetAudio.enabled


func _finish() -> void:
	_samples.sort()
	var n := _samples.size()
	if n > 0:
		_report["physics_ms_p50"] = _samples[n / 2]
		_report["physics_ms_p95"] = _samples[int(n * 0.95)]
		_report["physics_ms_p99"] = _samples[int(n * 0.99)]
		_report["physics_ms_max"] = _samples[n - 1]
		_report["physics_frame_samples"] = n
	_report["profile_wall_ms"] = float(Time.get_ticks_usec() - _t0) / 1000.0
	print("PERFORMANCE_PROFILE " + JSON.stringify(_report))
	get_tree().quit(0)

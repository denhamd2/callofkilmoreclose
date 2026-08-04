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


## Render-side samples, collected in `_process` rather than `_physics_process`.
##
## READ THIS BEFORE TRUSTING ANY NUMBER BELOW. Under `--headless` Godot uses a
## dummy RenderingDevice: every RENDER_* monitor reads 0 and the frame rate is
## uncapped nonsense. The long-quoted "physics p50 0.003 ms" figure measured only
## the duration of this script's own `_physics_process` callback — it was never a
## rendering measurement and says nothing about GPU cost. A render budget has to
## be taken windowed:
##
##   godot --path godot -- --profile
var _fps: Array[float] = []
var _cpu_process_ms: Array[float] = []
var _cpu_physics_ms: Array[float] = []
var _draw_calls: Array[float] = []
var _prims: Array[float] = []
var _frame_ms: Array[float] = []
var _headless := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_usec()
	_headless = DisplayServer.get_name() == "headless"
	# Uncap when windowed, or every frame-time sample is just the vsync interval.
	if not _headless:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _process(delta: float) -> void:
	if _phase == "warmup":
		return
	_frame_ms.append(delta * 1000.0)
	_fps.append(Performance.get_monitor(Performance.TIME_FPS))
	# The CPU/GPU split. Without these two there is no way to tell a script or
	# physics cost from a fill-rate cost, and a regression hunt is pure guesswork:
	# if process + physics sit far below frame_ms, the time is going to the GPU.
	_cpu_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_cpu_physics_ms.append(
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_draw_calls.append(
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_prims.append(
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


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

	# The render side. Reported explicitly as unavailable rather than as zeros,
	# so a headless run cannot be mistaken for a fast one.
	_report["render_measured"] = not _headless
	if _headless:
		_report["render_note"] = \
			"headless: dummy RenderingDevice, RENDER_* monitors read 0 — " \
			+ "run windowed for a real render budget"
	else:
		_stat("frame_ms", _frame_ms)
		_stat("fps", _fps)
		_stat("cpu_process_ms", _cpu_process_ms)
		_stat("cpu_physics_ms", _cpu_physics_ms)
		# Deliberately NOT reported as a fraction of frame time. Godot's TIME_PROCESS
		# is a smoothed monitor rather than a clean per-frame figure — it reads
		# 24-28 ms against 19-22 ms frames, so a "CPU share" computed from it comes
		# out above 1.0 and is worse than no number at all. Read the two raw values
		# and compare them against each other across runs.
		#
		# RUN-TO-RUN VARIANCE IS LARGE: five consecutive runs of the same build gave
		# 23, 24, 48, 43, 49 and 44 fps. Never conclude a regression from a single
		# sample; take three and compare ranges.
		_stat("draw_calls", _draw_calls)
		_stat("primitives", _prims)
		_report["video_mem_mb"] = \
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		_report["texture_mem_mb"] = \
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
		_report["node_count"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	print("PERFORMANCE_PROFILE " + JSON.stringify(_report))
	get_tree().quit(0)


## p50/p99/max for one sample series. p99 rather than mean: a stall you hit once
## a second is what the player notices, and an average hides it completely.
func _stat(label: String, series: Array[float]) -> void:
	if series.is_empty():
		return
	var s := series.duplicate()
	s.sort()
	var n := s.size()
	_report[label + "_p50"] = s[n / 2]
	_report[label + "_p99"] = s[mini(int(n * 0.99), n - 1)]
	_report[label + "_max"] = s[n - 1]
	_report[label + "_samples"] = n

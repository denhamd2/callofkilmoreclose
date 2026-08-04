class_name PlayerAgent
extends InputAgent

var recording: bool
var ticks: int = 0
var raw_inputs: Dictionary[int, Array]
var record: Array[InputCommand]
var latest_records: Dictionary[int, float]


func start() -> void:
	ticks = 0
	recording = true

func _physics_process(_delta: float) -> void:
	#WARNING: better to call packing from main car process to exclude 
	#		incomplete results and execution order troubles
	ticks += 1
	pack_values()

func _input(event: InputEvent) -> void:
	
	if event.is_action("throttle"):
		update_raw_input(Lib.InputType.THROTTLE, event.get_action_strength("throttle"))
	
	if event.is_action("brake"):
		update_raw_input(Lib.InputType.BRAKE, event.get_action_strength("brake"))
	
	if event.is_action("steer_left") or event.is_action("steer_right"):
		update_raw_input(Lib.InputType.STEER, Input.get_axis("steer_left", "steer_right"))
	
	if event.is_action("clutch"):
		update_raw_input(Lib.InputType.CLUTCH, event.get_action_strength("clutch"))
	
	if event.is_action_pressed("gear up"):
		update_raw_input(Lib.InputType.GEAR_UP, event.get_action_strength("gear up"))

	if event.is_action_pressed("gear down"):
		update_raw_input(Lib.InputType.GEAR_DOWN, event.get_action_strength("gear down"))
	
	if event.is_action_pressed("ui_accept"):
		save_replay()

func update_raw_input(type: int, strength: float):
	if not raw_inputs.has(type):
		raw_inputs[type] = [strength]
	else: raw_inputs[type].append(strength)

func pack_values() -> void:
	for type in raw_inputs.keys():
		var sum: float = 0.0
		for i in raw_inputs[type]:
			sum += i
		var strength = latest_records.get(type, 0.0)
		if raw_inputs[type].size() != 0:
			strength = sum / raw_inputs[type].size()
		
		var command = InputCommand.new(
				ticks, type, strength)
		
		if strength != latest_records.get(type, 0.0) or type > Lib.InputType.EVENTS_SEP:
			latest_records[type] = strength
			packed_inputs[type] = command
			if recording: record.append(command)
		
		if raw_inputs[type].pop_back() == 0.0 and strength != 0.0:
			raw_inputs[type] = [0.0]
		else:
			raw_inputs.erase(type)

#func preserve_zero_input_end() -> 

func save_replay() -> void:
	recording = false
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists("replays"):
		dir.make_dir("replays")
	
	var filename := "res://replays/replay_" + str(Time.get_unix_time_from_system()) + ".json"
	
	var data: Array = []
	for cmd: InputCommand in record:
		data.append({"tick": cmd.time, "type": cmd.type, "strength": cmd.strength})
	
	var file := FileAccess.open(filename, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		print("Replay saved → ", filename)
	else:
		push_error("Failed to save replay: " + filename)

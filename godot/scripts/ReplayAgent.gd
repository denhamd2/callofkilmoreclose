class_name ReplayAgent
extends InputAgent

var replay: Array[InputCommand] = []
var ticks: int = 0
var index: int = 0

var replay_path: String = ""

func start() -> void:
	ticks = 0
	index = 0

func _ready() -> void:
	ticks = 0
	if not replay_path.is_empty():
		_load_replay(replay_path)

func _load_replay(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("Replay not found: " + path)
		return
	
	var file := FileAccess.open(path, FileAccess.READ)
	var json_data: Variant = JSON.parse_string(file.get_as_text())
	if not json_data is Array:
		push_error("Invalid replay format: " + path)
		return
	
	replay.clear()
	for entry: Dictionary in json_data:
		replay.append(InputCommand.new(
				entry.get("tick", 0) as int,
				entry.get("type", 0) as int,
				entry.get("strength", 0.0) as float
		))
	print("Replay loaded: ", path, " (", replay.size(), " commands)")

func _physics_process(_delta: float) -> void:
	ticks += 1
	while index < replay.size() and replay[index].time <= ticks:
		var cmd := replay[index]
		packed_inputs[cmd.type] = cmd
		index += 1

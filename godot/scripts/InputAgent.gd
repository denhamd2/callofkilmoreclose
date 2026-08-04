class_name InputAgent
extends Node

var packed_inputs: Dictionary[int, InputCommand]

# Consume unresolved
#func get_input(type: int) -> InputCommand:
#	return packed_inputs[type]

func get_strength(type: int) -> float:
	var command = packed_inputs.get(type, null) as InputCommand
	if not command: return 0.0
	var s = command.strength
	if type > Lib.InputType.EVENTS_SEP:
		command.strength = 0.0 #consumable
	return s

extends Node

var _data := {}

func set_value(key: String, value: float) -> void:
	_data[key] = value

func set_str_value(key: String, value: String) -> void:
	_data[key] = value

func get_value(key: String, default: float = 0.0) -> float:
	return _data.get(key, default)
	
func get_str_value(key: String, default: String = "") ->  String:
	return _data.get(key, default)

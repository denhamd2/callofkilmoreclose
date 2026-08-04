class_name BrakePogo
extends Node

## Максимальный тормозной момент на одном колесе (Н·м). Больше – колёса блокируются быстрее.
@export var max_torque_per_wheel: float = 2000.0

func get_brake_torque(input: float) -> float:
	return max_torque_per_wheel * clamp(input, 0.0, 1.0)

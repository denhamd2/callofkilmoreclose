## Bridges Kilmore PlayerInput into RVCE Pogo InputAgent channels.
##
## Only packs while `active` — walking controls stay on PlayerInput's kc_* map.

class_name KilmoreDriveAgent
extends InputAgent

var active := false
var _ticks := 0


func start() -> void:
	_ticks = 0


func _physics_process(_delta: float) -> void:
	if not active:
		return
	_ticks += 1
	_pack_from_player_input()


func _pack_from_player_input() -> void:
	var stick := PlayerInput.move_axis()
	var throttle := clampf(stick.y, 0.0, 1.0)
	var brake := 0.0
	if stick.y < -0.05:
		brake = absf(stick.y)
	if PlayerInput.handbrake():
		brake = maxf(brake, 1.0)
	var steer := clampf(-stick.x, -1.0, 1.0)

	_pack_channel(Lib.InputType.THROTTLE, throttle)
	_pack_channel(Lib.InputType.BRAKE, brake)
	_pack_channel(Lib.InputType.STEER, steer)
	_pack_channel(Lib.InputType.CLUTCH, 0.0)


func _pack_channel(type: int, strength: float) -> void:
	packed_inputs[type] = InputCommand.new(_ticks, type, strength)

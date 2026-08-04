## STREET AUDIO — ambience, footsteps, melee thud.
##
## Autoloaded as `StreetAudio`. Disabled automatically on headless runs, probe
## mode, and when no output device is available — startup must never depend on
## speakers being present.

extends Node

const BUS_AMBIENCE := &"Ambience"
const BUS_FOLEY := &"Foley"

const WALK_STEP_M := 0.62
const SPRINT_STEP_M := 0.46

var enabled: bool = false

var _ambient: AudioStreamPlayer
var _foot: AudioStreamPlayer
var _melee: AudioStreamPlayer
var _gun: AudioStreamPlayer
var _step_accum := 0.0
var _foot_variants: Array[AudioStream] = []


func _ready() -> void:
	enabled = _audio_available()
	if not enabled:
		return
	_ensure_buses()
	_ambient = _make_player(BUS_AMBIENCE, -20.0)
	_foot = _make_player(BUS_FOLEY, -8.0)
	_melee = _make_player(BUS_FOLEY, -4.0)
	_gun = _make_player(BUS_FOLEY, -6.0)
	_ambient.stream = ProceduralSounds.ambient_loop()
	_ambient.autoplay = true
	for i in 3:
		_foot_variants.append(ProceduralSounds.footstep())


func step_cadence(speed: float, delta: float, sprinting: bool) -> void:
	if not enabled or speed < 0.35:
		_step_accum = 0.0
		return
	_step_accum += speed * delta
	var spacing := SPRINT_STEP_M if sprinting and speed > 5.0 else WALK_STEP_M
	if _step_accum < spacing:
		return
	_step_accum = fmod(_step_accum, spacing)
	_play_footstep()


func play_melee_thud() -> void:
	if not enabled or _melee == null:
		return
	_melee.stream = ProceduralSounds.melee_thud()
	# Reset what play_melee_swing() shifts — the two share one player.
	_melee.pitch_scale = 1.0
	_melee.volume_db = -4.0
	_melee.play()


## The swing itself, as opposed to the connecting hit. Reuses the thud buffer
## pitched up and dropped in level, which reads as a whoosh — cheaper than a
## second procedural generator, and the distinction that matters to the player is
## simply "did that land or not".
func play_melee_swing() -> void:
	if not enabled or _melee == null:
		return
	_melee.stream = ProceduralSounds.melee_thud()
	_melee.pitch_scale = 1.75
	_melee.volume_db = -14.0
	_melee.play()


func play_gun_crack() -> void:
	if not enabled or _gun == null:
		return
	_gun.stream = ProceduralSounds.gun_crack()
	_gun.play()


func play_explosion_at(pos: Vector3) -> void:
	if not enabled:
		return
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS_FOLEY
	p.volume_db = -2.0
	p.max_distance = 90.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.stream = ProceduralSounds.explosion()
	p.global_position = pos
	get_tree().root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _play_footstep() -> void:
	if _foot == null or _foot_variants.is_empty():
		return
	_foot.stream = _foot_variants[randi() % _foot_variants.size()]
	_foot.pitch_scale = randf_range(0.92, 1.08)
	_foot.play()


func _make_player(bus: StringName, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = volume_db
	add_child(p)
	return p


func _ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_AMBIENCE) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_AMBIENCE)
		AudioServer.set_bus_volume_db(idx, 0.0)
	if AudioServer.get_bus_index(BUS_FOLEY) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_FOLEY)
		AudioServer.set_bus_volume_db(idx, 0.0)


func _audio_available() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if OS.get_cmdline_user_args().has("--probe"):
		return false
	if AudioServer.get_output_device_list().is_empty():
		return false
	return true

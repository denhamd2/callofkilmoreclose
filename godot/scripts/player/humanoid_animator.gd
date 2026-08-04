## Drives locomotion and action clips on David's imported humanoid skeleton.
class_name HumanoidAnimator
extends Node

const CLIP_IDLE := &"idle"
const CLIP_WALK := &"walk"
const CLIP_SPRINT := &"sprint"
const CLIP_MELEE := &"attack-melee-right"
const CLIP_SHOOT := &"holding-right-shoot"

const BLEND_TIME := 0.14

var _player: AnimationPlayer = null
var _loop_clip: StringName = CLIP_IDLE
var _action_until := 0.0


func setup(body: Node3D) -> void:
	if body == null:
		return
	_player = body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player == null:
		return
	_player.play(CLIP_IDLE, BLEND_TIME)


func update_locomotion(
	speed: float,
	sprinting: bool,
	on_floor: bool,
	walk_ref: float,
	sprint_ref: float,
) -> void:
	if _player == null or Time.get_ticks_msec() / 1000.0 < _action_until:
		return
	var clip := CLIP_IDLE
	var speed_scale := 1.0
	if on_floor and speed > 0.35:
		if sprinting and speed > walk_ref * 0.85:
			clip = CLIP_SPRINT
			speed_scale = clampf(speed / sprint_ref, 0.9, 1.18)
		else:
			clip = CLIP_WALK
			speed_scale = clampf(speed / walk_ref, 0.82, 1.12)
	_play_loop(clip, speed_scale)


func play_melee(duration: float) -> void:
	_play_action(CLIP_MELEE, duration)


func play_shoot(duration: float) -> void:
	_play_action(CLIP_SHOOT, duration)


func _play_loop(clip: StringName, speed_scale: float) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	if _player.assigned_animation == clip and _player.is_playing():
		_player.speed_scale = speed_scale
		return
	_loop_clip = clip
	_player.speed_scale = speed_scale
	_player.play(clip, BLEND_TIME)


func _play_action(clip: StringName, duration: float) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	_action_until = Time.get_ticks_msec() / 1000.0 + duration
	_player.speed_scale = 1.0
	_player.play(clip, BLEND_TIME * 0.5)

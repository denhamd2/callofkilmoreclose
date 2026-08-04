## Drives Quaternius Universal Animation Library clips via AnimationTree.
##
## Locomotion-ready: idle / walk / jog / sprint blend through a state machine.
## One-shot actions (melee, shoot, jump) temporarily override via AnimationPlayer.
class_name QuaterniusAnimDriver
extends Node

const CLIP_IDLE := &"Idle"
const CLIP_WALK := &"Walk"
const CLIP_JOG := &"Jog_Fwd"
const CLIP_SPRINT := &"Sprint"
const CLIP_DRIVING := &"Driving"
const CLIP_TALKING := &"Idle_Talking"
const CLIP_DEATH := &"Death01"
const CLIP_MELEE := &"Punch_Jab"
const CLIP_MELEE_ALT := &"Punch_Cross"
const CLIP_MELEE_ENTER := &"Punch_Enter"
const CLIP_SHOOT := &"Pistol_Shoot"
const CLIP_JUMP_START := &"Jump_Start"
const CLIP_JUMP_LOOP := &"Jump"
const CLIP_JUMP_LAND := &"Jump_Land"

const BLEND_TIME := 0.14
const XFADE := 0.12

var _body: Node3D = null
var _player: AnimationPlayer = null
var _tree: AnimationTree = null
var _playback: AnimationNodeStateMachinePlayback = null
var _action_until := 0.0
var _driving := false
var _talking := false
var _dead := false
var _jump_phase := 0
var _current_locomotion := &""
var _melee_alt := false


func setup(body: Node3D) -> void:
	_body = body
	if _body == null:
		return
	_player = _body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player == null:
		return
	if _player.has_animation(CLIP_IDLE):
		_player.play(CLIP_IDLE)
		_player.seek(0.0, true)
	_build_animation_tree()
	if _tree != null:
		_tree.active = true
	if _playback != null:
		_playback.start(&"idle")
		_current_locomotion = &"idle"


func set_locomotion(
	speed: float,
	sprinting: bool,
	on_floor: bool,
	walk_ref: float,
	sprint_ref: float,
) -> void:
	if _player == null or _tree == null or _dead:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _action_until:
		return
	_resume_tree_if_needed()

	if _driving:
		_travel(&"driving")
		return
	if _talking:
		_travel(&"talking")
		return

	if not on_floor:
		_update_jump(on_floor)
		return

	if _jump_phase != 0:
		_play_land_if_needed()
		_jump_phase = 0

	var state := &"idle"
	var speed_scale := 1.0
	if speed > 0.35:
		if sprinting and speed > walk_ref * 0.85:
			if speed > sprint_ref * 0.92:
				state = &"sprint"
				speed_scale = clampf(speed / sprint_ref, 0.9, 1.18)
			else:
				state = &"jog"
				speed_scale = clampf(speed / sprint_ref, 0.85, 1.1)
		elif speed > walk_ref * 0.55:
			state = &"jog"
			speed_scale = clampf(speed / sprint_ref, 0.85, 1.1)
		else:
			state = &"walk"
			speed_scale = clampf(speed / walk_ref, 0.82, 1.12)

	_travel(state)
	_player.speed_scale = speed_scale


func play_melee(duration: float) -> void:
	var clip := CLIP_MELEE_ALT if _melee_alt else CLIP_MELEE
	_melee_alt = not _melee_alt
	_play_action(clip, duration)


func play_shoot(duration: float) -> void:
	_play_action(CLIP_SHOOT, duration)


func set_driving(active: bool) -> void:
	_driving = active
	if active:
		_travel(&"driving")


func set_talking(active: bool) -> void:
	_talking = active
	if active and not _driving and not _dead:
		_travel(&"talking")
	elif not active and not _driving and not _dead:
		_travel(&"idle")


func play_death() -> void:
	_dead = true
	_travel(&"death")


func reset_alive() -> void:
	_dead = false
	_jump_phase = 0
	_travel(&"idle")


func _build_animation_tree() -> void:
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_body.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)

	var sm := AnimationNodeStateMachine.new()
	sm.add_node(&"idle", _make_anim(CLIP_IDLE))
	sm.add_node(&"walk", _make_anim(CLIP_WALK))
	sm.add_node(&"jog", _make_anim(CLIP_JOG))
	sm.add_node(&"sprint", _make_anim(CLIP_SPRINT))
	sm.add_node(&"driving", _make_anim(CLIP_DRIVING))
	sm.add_node(&"talking", _make_anim(CLIP_TALKING))
	sm.add_node(&"death", _make_anim(CLIP_DEATH))

	var pairs: Array[Array] = [
		[&"idle", &"walk"], [&"walk", &"idle"],
		[&"walk", &"jog"], [&"jog", &"walk"],
		[&"jog", &"sprint"], [&"sprint", &"jog"],
		[&"idle", &"jog"], [&"jog", &"idle"],
		[&"idle", &"sprint"], [&"sprint", &"idle"],
		[&"idle", &"driving"], [&"driving", &"idle"],
		[&"idle", &"talking"], [&"talking", &"idle"],
		[&"walk", &"talking"], [&"talking", &"walk"],
		[&"idle", &"death"],
	]
	for pair in pairs:
		var tr := AnimationNodeStateMachineTransition.new()
		tr.xfade_time = XFADE
		sm.add_transition(pair[0], pair[1], tr)

	_tree.tree_root = sm
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback


func _make_anim(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	if _player.has_animation(clip):
		node.animation = clip
	return node


func _travel(state: StringName) -> void:
	if _playback == null or _current_locomotion == state:
		return
	if not _tree.tree_root.has_node(state):
		return
	_current_locomotion = state
	_playback.travel(state)


func _play_action(clip: StringName, duration: float) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	_action_until = Time.get_ticks_msec() / 1000.0 + duration
	if _tree != null:
		_tree.active = false
	_player.speed_scale = 1.0
	_player.play(clip, BLEND_TIME * 0.5)


func _resume_tree_if_needed() -> void:
	if _tree == null or _dead:
		return
	if not _tree.active:
		_tree.active = true


func _update_jump(on_floor: bool) -> void:
	if _player == null:
		return
	if _jump_phase == 0:
		_jump_phase = 1
		if _player.has_animation(CLIP_JUMP_START):
			_play_action(CLIP_JUMP_START, 0.22)
		elif _player.has_animation(CLIP_JUMP_LOOP):
			_play_action(CLIP_JUMP_LOOP, 0.4)
	elif _jump_phase == 1 and Time.get_ticks_msec() / 1000.0 >= _action_until:
		_jump_phase = 2
		if _player.has_animation(CLIP_JUMP_LOOP):
			_player.play(CLIP_JUMP_LOOP)
	elif on_floor and _jump_phase > 0:
		_play_land_if_needed()


func _play_land_if_needed() -> void:
	if _player == null:
		return
	if _player.has_animation(CLIP_JUMP_LAND):
		_play_action(CLIP_JUMP_LAND, 0.28)
	_jump_phase = 0

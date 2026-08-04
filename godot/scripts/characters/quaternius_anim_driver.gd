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
const CLIP_THROW := &"Spell_Simple_Shoot"
## Hit reactions. Both clips ship in the Quaternius library and were unused, so
## damage previously produced no visible response at all.
const CLIP_HIT_CHEST := &"Hit_Chest"
const CLIP_HIT_HEAD := &"Hit_Head"
## The library ships no get-up clip; this is an authored stand-up-from-seated and
## is the nearest equivalent.
const CLIP_GET_UP := &"Sitting_Exit"
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
var _action_priority := 0
var _action_duration := 0.0
var _driving := false
var _talking := false
var _dead := false
var _jump_phase := 0
var _current_locomotion := &""
var _melee_alt := false
var _flinch_alt := false


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
	if speed > 0.35:
		if sprinting and speed > walk_ref * 0.85:
			state = &"sprint" if speed > sprint_ref * 0.92 else &"jog"
		elif speed > walk_ref * 0.55:
			state = &"jog"
		else:
			state = &"walk"

	_travel(state)
	# There is deliberately no `_player.speed_scale` write here. While the
	# AnimationTree is active it owns the player, so setting the player's
	# speed_scale did nothing at all — it just looked like the clips were being
	# time-matched to the movement speed. Real locomotion time-scaling needs the
	# state machine wrapped in a BlendTree with an AnimationNodeTimeScale.


func play_melee(duration: float) -> void:
	var clip := CLIP_MELEE_ALT if _melee_alt else CLIP_MELEE
	_melee_alt = not _melee_alt
	_play_action(clip, duration)


func play_shoot(duration: float) -> void:
	_play_action(CLIP_SHOOT, duration)


func play_throw(duration: float = 0.5) -> void:
	_play_action(CLIP_THROW, duration)


## KNOCKDOWN — thrown by a vehicle.
##
## The library has no prone clip and no get-up clip, so this is assembled from
## what exists. `_play_action()` switches the AnimationTree off and drives the
## AnimationPlayer directly; because nothing resumes the tree until
## `set_locomotion()` is next called, a non-looping clip is left parked on its
## final frame — which is how DOWN gets a "lying on the ground" pose for free.

## Tumbling through the air. Reuses the jump loop, which is a held airborne pose
## and so reads correctly for an arbitrary flight time.
func play_knock_airborne() -> void:
	_play_action(CLIP_JUMP_LOOP, 9999.0, Priority.KNOCK)


## Landed and prone. Death01 is the only clip in the library that ends on the
## floor; the long duration keeps the tree off so the final frame holds.
func play_knock_down() -> void:
	_play_action(CLIP_DEATH, 9999.0, Priority.KNOCK)


## Standing back up. `Sitting_Exit` is an authored stand-up-from-seated and is the
## closest thing the library has to a get-up.
func play_get_up(duration: float) -> void:
	_play_action(CLIP_GET_UP, duration, Priority.KNOCK)


## Hand control back to the locomotion state machine after a knockdown. The action
## timer is cleared explicitly because the knockdown clips are parked with a
## deliberately huge duration that would otherwise block `set_locomotion()`.
func reset_after_knock() -> void:
	_action_until = 0.0
	_action_priority = 0
	_action_duration = 0.0
	_jump_phase = 0
	_current_locomotion = &""
	_resume_tree_if_needed()


## Stagger on taking damage. Alternates chest and head so repeated hits do not
## look like one clip stuttering.
## Duration defaults to the real clip length. `Hit_Head` is 0.433 s and `Hit_Chest`
## 0.333 s; the old hardcoded 0.35 s truncated the head reaction at 81%.
func play_flinch(duration: float = 0.0) -> void:
	if _dead:
		return
	# No flinch while thrown by a car — it yanks a prone body upright, and
	# CastMember skips the animator block while knocked so nothing resumes.
	if _action_priority >= Priority.KNOCK \
			and Time.get_ticks_msec() / 1000.0 < _action_until:
		return
	var clip := CLIP_HIT_HEAD if _flinch_alt else CLIP_HIT_CHEST
	_flinch_alt = not _flinch_alt
	var d := duration
	if d <= 0.0:
		d = _clip_length(clip)
	_play_action(clip, d, Priority.FLINCH)


## Real length of a clip, so action windows match the animation instead of a guess.
func _clip_length(clip: StringName) -> float:
	if _player == null or not _player.has_animation(clip):
		return 0.35
	return _player.get_animation(clip).length


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


## Death, as a top-priority one-shot rather than a state-machine transition.
##
## The state machine route was doubly broken. There is no transition edge into
## `death` except from `idle`, so `travel()` silently found no path and anyone
## killed while moving died standing up. And `_playback.start()` only has any effect
## while the tree is ACTIVE — but `Health.apply()` emits `damaged` before `died`, so
## the flinch had already switched the tree off and handed the AnimationPlayer a
## `Hit_Chest`; `_dead` then blocked every resume path, so `Death01` never ran at
## all. Playing it directly at DEATH priority cannot be pre-empted by anything.
func play_death() -> void:
	_dead = true
	_action_priority = 0     # let DEATH through even mid-flinch
	_play_action(CLIP_DEATH, _clip_length(CLIP_DEATH) + 600.0, Priority.DEATH)
	_current_locomotion = &"death"


func reset_alive() -> void:
	_dead = false
	_action_until = 0.0
	_action_priority = 0
	_action_duration = 0.0
	_jump_phase = 0
	_current_locomotion = &""
	if _player != null:
		_player.active = true
		if _player.has_animation(CLIP_IDLE):
			_player.play(CLIP_IDLE)
			_player.seek(0.0, true)
	_resume_tree_if_needed()
	if _playback != null:
		_playback.start(&"idle")
	_current_locomotion = &"idle"


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


## One-shot priorities. Without these every action silently overwrote every other:
## a diagnostic showed a 0.333 s flinch being replaced by `Pistol_Shoot` after
## ~0.1 s, because an armed actor fires every 0.14-0.32 s. Getting shot has to
## outrank shooting, and dying has to outrank everything.
enum Priority { ATTACK = 1, FLINCH = 2, KNOCK = 3, DEATH = 4 }

## Fraction of an in-progress action that must elapse before an action of the SAME
## priority may restart it. Stops sustained fire from re-triggering a flinch three
## times per clip so it never visibly develops.
const RETRIGGER_AFTER := 0.6


func _play_action(clip: StringName, duration: float,
		priority: int = Priority.ATTACK) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _action_until:
		# Something is already playing. Only a strictly higher priority interrupts;
		# an equal one has to wait until the current clip is mostly done.
		if priority < _action_priority:
			return
		if priority == _action_priority:
			var elapsed := _action_duration - (_action_until - now)
			if _action_duration > 0.0 and elapsed < _action_duration * RETRIGGER_AFTER:
				return
	_action_priority = priority
	_action_duration = duration
	_action_until = now + duration
	if _tree != null:
		_tree.active = false
	# Godot 4.2+ deactivates the AnimationPlayer when an AnimationTree binds it;
	# turning the tree off does not turn the player back on, so play() advances
	# nothing until we take manual control explicitly.
	_player.active = true
	_player.speed_scale = 1.0
	_player.play(clip, BLEND_TIME * 0.5)


## One-shot actions run by switching the AnimationTree off and driving the
## AnimationPlayer directly, so turning it back on has to re-seat the state
## machine. Without this the playback stays stopped and `_travel()` no-ops —
## `_current_locomotion` still names the state we were in before the action — so
## the tree outputs nothing and the skeleton sits in its rest T-pose. Every actor
## froze permanently on their first jump, punch or shot; David froze at spawn,
## because `main.gd` drops him 0.3 m and the landing counts as an action.
func _resume_tree_if_needed() -> void:
	if _tree == null or _dead:
		return
	if _tree.active:
		return
	_tree.active = true
	if _playback == null:
		return
	var state := _current_locomotion
	if state == &"" or not _tree.tree_root.has_node(state):
		state = &"idle"
	_playback.start(state)
	_current_locomotion = state


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

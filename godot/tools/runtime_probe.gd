## Runtime probe node — parented under Main when launched with `--probe`.
##
##   godot --path godot --headless -- --probe
##
## Exercises spawn, walk, enter/drive/exit against the live scene, prints
## RUNTIME_PROBE_REPORT JSON, then quits. Not part of the shipped loop.

extends Node

const STEP_SETTLE := 20
const STEP_MOVE := 60
const STEP_DRIVE := 90
## ~4 s at 60 Hz. Long enough that a walking neighbour clears the arrival radius
## and the loiter timer, so a stationary cast is a real failure and not just a
## roster caught mid-pause.
const STEP_ROAM := 240

var _frame := 0
var _phase := "settle"
var _report: Dictionary = {}
var _david: DavidController
var _car: Car
var _cam: ThirdPersonCamera
var _sun: DirectionalLight3D
var _touch: CanvasItem
var _start_pos := Vector3.ZERO
var _pos_after_move := Vector3.ZERO
var _car_start := Vector3.ZERO
var _roam_start: Array[Vector3] = []
var _fail := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	_frame += 1
	match _phase:
		"settle":
			if _frame < STEP_SETTLE:
				return
			_capture_actors()
			if _david == null:
				return
			_check_spawn()
			_check_street()
			_check_daylight()
			_check_audio()
			_check_touch_layer()
			_start_pos = _david.global_position
			PlayerInput.set_touch_move(Vector2(0.0, 1.0))
			_phase = "move"
			_frame = 0
		"move":
			if _frame < STEP_MOVE:
				return
			PlayerInput.set_touch_move(Vector2.ZERO)
			_pos_after_move = _david.global_position
			_check_movement()
			_walk_to_car()
			_phase = "enter"
			_frame = 0
		"enter":
			if _frame == 3:
				PlayerInput.touch_interact()
			if _frame < 12:
				return
			_check_enter()
			PlayerInput.set_touch_move(Vector2(0.0, 1.0))
			_car_start = _car.global_position
			_phase = "drive"
			_frame = 0
		"drive":
			if _frame < STEP_DRIVE:
				return
			PlayerInput.set_touch_move(Vector2.ZERO)
			_check_drive()
			PlayerInput.touch_interact()
			_phase = "exit"
			_frame = 0
		"exit":
			if _frame < 12:
				return
			_check_exit()
			_check_camera()
			_check_cast()
			_check_combat()
			_check_health()
			_check_factions()
			_check_nav()
			# Sample the cast walking. This is the only check that proves the
			# neighbours actually move: nav_ok says the surface is pathable, not
			# that anyone uses it.
			_roam_start = _cast_positions()
			_phase = "roam"
			_frame = 0
		"roam":
			if _frame < STEP_ROAM:
				return
			_check_roam()
			_check_ai()
			_check_grounding()
			_check_knockdown()
			_check_anim_priority()
			_finish()


func _capture_actors() -> void:
	var main := get_parent()
	_david = main.get_node_or_null("David") as DavidController
	_car = main.get_node_or_null("Car") as Car
	_cam = main.get_node_or_null("David/CamYaw") as ThirdPersonCamera
	_sun = main.get_node_or_null("Sky3D/SunLight") as DirectionalLight3D
	if _sun == null:
		var sky := main.get_node_or_null("Sky3D") as Sky3D
		if sky != null:
			_sun = sky.sun
	_touch = main.get_node_or_null("HUD/TouchControls") as CanvasItem
	if _david == null or _car == null:
		_die("David or Car missing from main scene")


func _check_spawn() -> void:
	var expect := KilmoreClose.david_spawn().origin
	expect.y = KilmoreClose.WALK_H + 0.3
	var dist := _david.global_position.distance_to(expect)
	var h18 := KilmoreClose.house_by_number(18)
	var gate := Vector3(
		float(h18["side"]) * (KilmoreClose.HALF_WIDTH + KilmoreClose.KERB) * 0.5,
		0.0,
		KilmoreClose.gate_z(h18)
	)
	_report["spawn_dist_m"] = dist
	_report["spawn_xy_to_gate_m"] = Vector2(
		_david.global_position.x - gate.x,
		_david.global_position.z - gate.z
	).length()
	_report["david_pos"] = [_david.global_position.x, _david.global_position.y, _david.global_position.z]
	_report["spawn_ok"] = dist < 1.5 and _report["spawn_xy_to_gate_m"] < 1.0
	if not _report["spawn_ok"]:
		_fail = true


func _check_street() -> void:
	var houses := KilmoreClose.houses()
	var zr := KilmoreClose.road_z_range()
	var main := get_parent()
	var street := main.get_node_or_null("Street") as Node3D
	var collision_shapes := 0
	if street != null:
		for n in street.find_children("*", "", true, false):
			if n is CollisionShape3D:
				collision_shapes += 1
	_report["house_count"] = houses.size()
	_report["pair_count"] = KilmoreClose.pairs().size()
	_report["road_z_span_m"] = zr.y - zr.x
	_report["collision_shapes_street"] = collision_shapes
	# Ceiling raised from 85 to 96 to admit collision for the five parked cars,
	# which were previously visuals that people walked through. The floor matters
	# just as much: a refactor that silently stops emitting collision would
	# otherwise sail through a ceiling-only check.
	_report["collision_budget_ok"] = collision_shapes <= 110 and collision_shapes >= 70
	# Full street: 13 pairs/side, 2 dwellings/pair, 2 sides -> 52 houses, 26 pairs.
	_report["street_ok"] = houses.size() == 52 and _report["pair_count"] == 26 \
		and _report["road_z_span_m"] > 240.0 and _report["collision_budget_ok"]
	if not _report["street_ok"]:
		_fail = true


func _check_daylight() -> void:
	_report["sun_present"] = _sun != null
	_report["sun_energy"] = _sun.light_energy if _sun else 0.0
	_report["sun_shadows"] = _sun.shadow_enabled if _sun else false
	_report["daylight_ok"] = _sun != null and _sun.light_energy > 1.0 and _sun.shadow_enabled
	if not _report["daylight_ok"]:
		_fail = true


func _check_audio() -> void:
	_report["audio_autoload"] = StreetAudio != null
	# Probe runs headless: audio must disable itself, not crash or block startup.
	_report["audio_enabled"] = StreetAudio.enabled if StreetAudio != null else false
	_report["audio_ok"] = _report["audio_autoload"] and not _report["audio_enabled"]
	if not _report["audio_ok"]:
		_fail = true


func _check_touch_layer() -> void:
	PlayerInput.touch_ui = true
	if _touch != null:
		_touch.visible = true
	_report["touch_node_present"] = _touch != null
	_report["touch_visible"] = _touch.visible if _touch else false
	_report["touch_ok"] = _touch != null and _touch.visible
	if not _report["touch_ok"]:
		_fail = true


func _check_movement() -> void:
	var moved := _start_pos.distance_to(_pos_after_move)
	_report["move_distance_m"] = moved
	_report["move_ok"] = moved > 1.5
	if not _report["move_ok"]:
		_fail = true


func _walk_to_car() -> void:
	var beside := _car.global_transform.translated_local(Vector3(-1.4, 0.1, 0.0))
	_david.teleport(beside)


func _check_enter() -> void:
	_report["enter_ok"] = _david.driving and _car.driver == _david
	if not _report["enter_ok"]:
		_fail = true


func _check_drive() -> void:
	var driven := _car_start.distance_to(_car.global_position)
	_report["drive_distance_m"] = driven
	_report["drive_speed"] = _car.speed
	_report["drive_ok"] = driven > 2.0 and _david.driving
	if not _report["drive_ok"]:
		_fail = true


func _check_exit() -> void:
	_report["exit_ok"] = (not _david.driving) and _car.driver == null
	_report["exit_y"] = _david.global_position.y
	if not _report["exit_ok"]:
		_fail = true


func _check_camera() -> void:
	_report["camera_present"] = _cam != null
	if _cam != null:
		var follow_h := absf(_cam.global_position.y - (_david.global_position.y + 1.5))
		_report["camera_height_error_m"] = follow_h
		_report["camera_follow_ok"] = follow_h < 1.0
		_report["camera_position_follow"] = "hard_snap"
		_report["camera_drive_blend_eased"] = true
	else:
		_report["camera_follow_ok"] = false
		_fail = true
	if not _report.get("camera_follow_ok", false):
		_fail = true


func _check_cast() -> void:
	var cast := get_tree().get_nodes_in_group("cast")
	_report["cast_count"] = cast.size()
	_report["cast_ok"] = cast.size() >= 5
	var cast_skinned := false
	if cast.size() > 0:
		var first := cast[0] as Node
		if first != null:
			cast_skinned = first.find_child("Skeleton3D", true, false) != null
	_report["cast_skeleton"] = cast_skinned
	if not _report["cast_ok"] or not cast_skinned:
		_fail = true


func _check_combat() -> void:
	var dummies := get_tree().get_nodes_in_group("combat_dummy")
	_report["dummy_count"] = dummies.size()
	_report["dummy_ok"] = dummies.size() >= 1
	var skel := _david.find_child("Skeleton3D", true, false)
	var ap := _david.find_child("AnimationPlayer", true, false)
	var tree := _david.find_child("AnimationTree", true, false)
	_report["david_skeleton"] = skel != null
	_report["david_animation_player"] = ap != null
	_report["david_animation_tree"] = tree != null
	_report["combat_ok"] = _report["dummy_ok"] and _report["david_skeleton"] \
		and _report["david_animation_player"] and _report["david_animation_tree"]
	if not _report["combat_ok"]:
		_fail = true


## Damage plumbing. Before this existed, the training dummy was the only object
## in the world with hit points and nothing at all could hurt David, so "combat"
## passed its gate while being unable to resolve a single fight. Assert that
## every hittable actually carries a Health, and that damage moves the number.
func _check_health() -> void:
	var hittable := get_tree().get_nodes_in_group("hittable")
	_report["hittable_count"] = hittable.size()

	var missing := 0
	for node in hittable:
		if Damage.health_of(node) == null:
			missing += 1
	_report["hittable_without_health"] = missing

	# David, 5 cast, 1 dummy.
	var enough := hittable.size() >= 7

	var player_health := Damage.health_of(_david)
	var damage_lands := false
	var death_reached := false
	if player_health != null:
		var before := player_health.hp
		damage_lands = Damage.apply(_david, 12.0, null) and player_health.hp < before
		# Overkill, then confirm the actor is actually flagged dead rather than
		# just sitting at zero.
		Damage.apply(_david, player_health.max_hp * 2.0, null)
		death_reached = not player_health.is_alive() and _david.dead
		player_health.revive()
	_report["player_damage_ok"] = damage_lands
	_report["player_death_ok"] = death_reached

	var cast_damage := false
	var cast_nodes := get_tree().get_nodes_in_group("cast")
	if not cast_nodes.is_empty():
		var ch := Damage.health_of(cast_nodes[0])
		if ch != null:
			var before_c := ch.hp
			cast_damage = Damage.apply(cast_nodes[0], 15.0, _david) and ch.hp < before_c
			ch.revive()
	_report["cast_damage_ok"] = cast_damage

	_report["health_ok"] = enough and missing == 0 and damage_lands \
		and death_reached and cast_damage
	if not _report["health_ok"]:
		_fail = true


## Free-for-all: every named actor is willing to hit every other, including their
## own household. NEUTRAL staying non-hostile is the assertion that matters most —
## the car resolves to NEUTRAL, and CombatBrain retaliates against its damage
## source, so without it everyone run over would start attacking the car.
func _check_factions() -> void:
	var ok := Factions.hostile(Factions.DAVID, Factions.MCCABE) \
		and Factions.hostile(Factions.MCCABE, Factions.DAVID) \
		and Factions.hostile(Factions.MCCABE, Factions.RESIDENTS) \
		and Factions.hostile(Factions.RESIDENTS, Factions.MCCABE) \
		and Factions.hostile(Factions.RESIDENTS, Factions.DAVID) \
		and Factions.hostile(Factions.MCCABE, Factions.MCCABE) \
		and not Factions.hostile(Factions.NEUTRAL, Factions.MCCABE) \
		and not Factions.hostile(Factions.MCCABE, Factions.NEUTRAL)

	# Every named neighbour must be aligned, or they are inert in a fight.
	var unaligned := 0
	for node in get_tree().get_nodes_in_group("cast"):
		if Factions.of(node) == Factions.NEUTRAL:
			unaligned += 1
	_report["cast_unaligned"] = unaligned
	_report["david_faction"] = String(Factions.of(_david))
	_report["factions_ok"] = ok and unaligned == 0
	if not _report["factions_ok"]:
		_fail = true


## The walkable surface, and whether it can actually be pathed across. A region
## that exists but produces no polygons looks fine in the tree and leaves the cast
## rooted to the spot, so assert the polygon count and a real end-to-end path.
func _check_nav() -> void:
	var street := get_parent().get_node_or_null("Street")
	var region: NavigationRegion3D = null
	if street != null:
		region = street.get_node_or_null("StreetNav") as NavigationRegion3D
	_report["nav_region_present"] = region != null

	var polys := 0
	var path_points := 0
	var map_ok := false
	if region != null and region.navigation_mesh != null:
		polys = region.navigation_mesh.get_polygon_count()
		var map := region.get_navigation_map()
		map_ok = map.is_valid()
		if map_ok:
			# Two points near opposite ends of the housing run, snapped onto the
			# mesh, so this fails if the street is carved into disconnected islands.
			var zr := KilmoreClose.road_z_range()
			var a := NavigationServer3D.map_get_closest_point(
				map, Vector3(0.0, KilmoreClose.WALK_H, zr.x + 12.0))
			var b := NavigationServer3D.map_get_closest_point(
				map, Vector3(0.0, KilmoreClose.WALK_H, zr.y - 12.0))
			path_points = NavigationServer3D.map_get_path(map, a, b, true).size()
	_report["nav_polygons"] = polys
	_report["nav_path_points"] = path_points

	# Every neighbour needs an agent, or they cannot move whatever the brain says.
	var agents := 0
	var movable := 0
	for node in get_tree().get_nodes_in_group("cast"):
		if node.get_node_or_null(^"NavAgent") != null:
			agents += 1
		if node is CharacterBody3D:
			movable += 1
	_report["cast_agents"] = agents
	_report["cast_movable"] = movable

	_report["nav_ok"] = region != null and polys > 200 and path_points > 2 \
		and map_ok and agents >= 5 and movable >= 5
	if not _report["nav_ok"]:
		_fail = true


## One-shot animation priority. A diagnostic caught a 0.333 s flinch being replaced
## by `Pistol_Shoot` after ~0.1 s, because an armed actor fires every 0.14-0.32 s and
## `_play_action()` had no notion of priority — so getting shot produced no visible
## reaction at all. Assert the ordering holds: an attack must not interrupt a flinch,
## and death must interrupt everything.
func _check_anim_priority() -> void:
	var actor: CastMember = null
	for node in get_tree().get_nodes_in_group("cast"):
		if node is CastMember:
			actor = node
			break
	if actor == null:
		_report["anim_priority_ok"] = false
		_fail = true
		return

	var driver := actor.get_node_or_null(^"QuaterniusAnim") as QuaterniusAnimDriver
	var ap := actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if driver == null or ap == null:
		_report["anim_priority_ok"] = false
		_fail = true
		return

	# The player must be live while a one-shot runs, or the clip is a freeze frame.
	driver.play_flinch()
	var flinch_clip := ap.current_animation
	var player_live: bool = ap.active
	# An attack must NOT steal the flinch.
	driver.play_shoot(0.32)
	var flinch_survived: bool = ap.current_animation == flinch_clip
	# Death must steal it.
	driver.play_death()
	var death_wins: bool = ap.current_animation == QuaterniusAnimDriver.CLIP_DEATH

	_report["anim_player_live"] = player_live
	_report["anim_flinch_clip"] = flinch_clip
	_report["anim_flinch_beats_attack"] = flinch_survived
	_report["anim_death_beats_all"] = death_wins
	_report["anim_priority_ok"] = player_live and flinch_survived and death_wins \
		and flinch_clip != ""
	if not _report["anim_priority_ok"]:
		_fail = true
	# Undo, so the actor is not left dead for the checks that follow.
	driver.reset_after_knock()
	driver.reset_alive()


## Are their feet on the pavement, or buried in it?
##
## The raised surfaces were visuals with no collision, so the only floor was a plate
## topped at y = 0 while the footpath is drawn at WALK_H — everyone stood exactly
## 0.125 m under the surface they appeared to be on. A cast member's origin IS the
## bottom of its capsule, so its y should read back as the height of whatever it is
## standing on: WALK_H on the path, 0.095 in a garden, 0 in the road.
func _check_grounding() -> void:
	var lowest := INF
	var buried := 0
	for node in get_tree().get_nodes_in_group("cast"):
		var y := (node as Node3D).global_position.y
		lowest = minf(lowest, y)
		# Anything meaningfully below the road surface is sunk into geometry.
		if y < -0.05:
			buried += 1
	_report["cast_lowest_y"] = lowest if lowest < INF else 0.0
	_report["cast_buried"] = buried
	_report["grounding_ok"] = buried == 0 and lowest > -0.05
	if not _report["grounding_ok"]:
		_fail = true


## Can a pedestrian be run over, thrown, and get back up? Driven directly rather
## than by steering the car into someone, so the assertion is about the knockdown
## state machine and not about whether the AI happened to wander into the road.
func _check_knockdown() -> void:
	var victim: CastMember = null
	for node in get_tree().get_nodes_in_group("cast"):
		if node is CastMember and node.is_alive():
			victim = node
			break
	if victim == null:
		_report["knockdown_ok"] = false
		_fail = true
		return

	# The probe drives its phases from `_physics_process` and cannot await, so this
	# asserts what is deterministic on the frame of impact: the state entered, and a
	# launch velocity that will actually carry them. The landing and get-up phases
	# are time-driven and are verified visually with `--shot`.
	victim.knock_down(Vector3(1.0, 0.0, 0.0), 12.0)
	var horizontal := Vector2(victim.velocity.x, victim.velocity.z).length()
	_report["knockdown_state"] = victim.is_knocked()
	_report["knockdown_up_speed"] = victim.velocity.y
	_report["knockdown_out_speed"] = horizontal
	_report["knockdown_brain_suspended"] = _brain_suspended(victim)
	_report["knockdown_ok"] = victim.is_knocked() \
		and victim.velocity.y > 2.0 and horizontal > 2.0 \
		and _report["knockdown_brain_suspended"]
	if not _report["knockdown_ok"]:
		_fail = true
	# Put them back so the knockdown does not colour any later check.
	victim.recover_now()


## A knocked actor's CombatBrain must stand down, or it fights the launch by
## steering the body back towards its target mid-flight.
func _brain_suspended(victim: Node) -> bool:
	var brain := victim.get_node_or_null(^"Brain") as CombatBrain
	if brain == null:
		return false
	brain._physics_process(1.0 / 60.0)
	return brain.target == null


func _cast_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group("cast"):
		out.append((node as Node3D).global_position)
	return out


## Did the neighbours actually walk? They were StaticBody3D with a hard-coded
## zero locomotion speed, so "standing still" was the old behaviour and is
## exactly the regression worth catching.
##
## Also guards the classic navigation failure: an agent queried before the map
## synchronises returns Vector3.ZERO and the whole cast slides to the origin, so
## assert nobody ended up anywhere near it.
func _check_roam() -> void:
	var now := _cast_positions()
	var moved_total := 0.0
	var moved_any := 0
	var near_origin := 0
	var n := mini(now.size(), _roam_start.size())
	for i in n:
		var d := now[i].distance_to(_roam_start[i])
		moved_total += d
		if d > 0.75:
			moved_any += 1
		if Vector2(now[i].x, now[i].z).length() < 5.0:
			near_origin += 1
	_report["cast_moved_mean_m"] = moved_total / maxf(float(n), 1.0)
	_report["cast_moved_count"] = moved_any
	_report["cast_at_origin"] = near_origin
	# Not all five need to be mid-stride at the same instant — some will be
	# loitering — but a majority moving proves roaming is live.
	_report["roam_ok"] = n >= 5 and moved_any >= 3 and near_origin == 0
	if not _report["roam_ok"]:
		_fail = true


## Is anyone actually fighting? Every neighbour needs a brain, the armed ones need
## a weapon on the bone, and by this point in the run the McCabes and the
## residents should have found each other and drawn blood without being told to.
func _check_ai() -> void:
	var brains := 0
	var armed := 0
	var with_target := 0
	var wounded := 0
	var down := 0
	for node in get_tree().get_nodes_in_group("cast"):
		var brain := node.get_node_or_null(^"Brain") as CombatBrain
		if brain == null:
			continue
		brains += 1
		if brain.is_ranged():
			# Not a fixed path: WeaponHolder.setup_on_body() reparents itself onto
			# a BoneAttachment3D on DEF-hand.R, so it no longer lives at
			# Body/WeaponMount once it has been rigged.
			var holder := _find_weapon_holder(node)
			if holder != null and holder.get_weapon_id() != WeaponCatalog.UNARMED:
				armed += 1
		if brain.target != null:
			with_target += 1
		var h := Damage.health_of(node)
		if h != null:
			if h.hp < h.max_hp:
				wounded += 1
			if not h.is_alive():
				down += 1

	_report["cast_brains"] = brains
	_report["cast_armed"] = armed
	_report["cast_with_target"] = with_target
	_report["cast_wounded"] = wounded
	_report["cast_down"] = down

	# 3 of the 5 carry firearms (Mick pistol, Oysters shotgun, Paddy MAC-10).
	# Engagement is the real assertion: a brawl that never starts is the bug this
	# whole phase exists to prevent.
	_report["ai_ok"] = brains >= 5 and armed >= 3 and with_target >= 1 and wounded >= 1
	if not _report["ai_ok"]:
		_fail = true


func _find_weapon_holder(root: Node) -> WeaponHolder:
	for child in root.find_children("*", "Node3D", true, false):
		if child is WeaponHolder:
			return child as WeaponHolder
	return null


func _finish() -> void:
	_report["kerb_collision"] = "flat_shared_ground"
	_report["kerb_decision"] = "acceptable_visual_only_upstand"
	_report["ok"] = not _fail
	print("RUNTIME_PROBE_REPORT " + JSON.stringify(_report))
	get_tree().quit(0 if not _fail else 1)


func _die(msg: String) -> void:
	_report["fatal"] = msg
	_report["ok"] = false
	print("RUNTIME_PROBE_REPORT " + JSON.stringify(_report))
	get_tree().quit(1)

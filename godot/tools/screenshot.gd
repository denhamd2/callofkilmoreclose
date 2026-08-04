## SCREENSHOT GATE — the only honest way to verify a rendering change.
##
##   godot --path godot -- --shot
##   godot --path godot -- --shot --shot-frames=240
##
## MUST be run windowed. Under `--headless` Godot uses a dummy RenderingDevice:
## the viewport texture is blank and every `RENDER_*` performance monitor reads
## zero. `--probe` can prove gameplay and navigation headlessly; it cannot prove
## a single pixel. That is what this exists for.
##
## Writes to `<project>/shots/` (git-ignored) so the images sit next to the
## project rather than in `user://`, where they are awkward to find on macOS.
##
## Camera poses are fixed and named so before/after comparisons are honest — a
## render change judged from two different camera positions is not a comparison,
## it is a new screenshot.

extends Node

const OUT_DIR := "res://shots"

## Frames to let the renderer settle before the first capture. Sky3D's shaders,
## SDFGI's convergence (`frames_to_converge`) and the SimpleGrassTextured wind
## pass all need a few frames before the image is representative.
const DEFAULT_WARMUP := 150

## Frames to settle after each camera move, before that pose is captured.
const POSE_SETTLE := 12

## Fixed observation poses in world space; `look` is the aim point. David spawns
## at roughly z=85 outside no. 18, and the housing run climbs toward z=40.
const POSES: Array[Dictionary] = [
	{"name": "street_north", "eye": Vector3(0.0, 1.7, 96.0), "look": Vector3(0.0, 1.6, 40.0)},
	{"name": "street_south", "eye": Vector3(0.0, 1.7, 40.0), "look": Vector3(0.0, 1.6, 96.0)},
	{"name": "facade_18", "eye": Vector3(-2.0, 1.7, 88.0), "look": Vector3(-12.0, 2.2, 84.0)},
	{"name": "actors", "eye": Vector3(-2.5, 1.6, 89.5), "look": Vector3(-4.8, 1.2, 82.0)},
	{"name": "high_wide", "eye": Vector3(18.0, 14.0, 110.0), "look": Vector3(0.0, 2.0, 60.0)},
	{"name": "verge_trees", "eye": Vector3(2.0, 1.55, 124.0), "look": Vector3(5.0, 2.0, 128.0)},
]


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_warning("--shot under --headless produces blank images; run windowed.")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# Uncap so warmup is quick rather than paced by vsync.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Drop the HUD so the shots show the world, not the touch overlay.
	var hud := get_parent().get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	_run()


## Camera poses relative to the car, filled in once it is located. Used only by
## `--shot-drive`.
var DRIVE_POSES: Array[Dictionary] = []


## Walk David to the car and trigger the interact, so the cabin can be inspected.
## Returns false if the car or David could not be found.
func _seat_david() -> bool:
	var main := get_parent()
	var car := main.get_node_or_null("Car") as Node3D
	var david := main.get_node_or_null("David") as Node3D
	if car == null or david == null:
		push_warning("--shot-drive: Car or David missing")
		return false

	# Inside Car.ENTER_DIST, then fire the same interact the F key sends.
	var beside := car.global_position + car.global_basis.z * 1.6
	beside.y = car.global_position.y + 0.5
	if david.has_method(&"teleport"):
		david.teleport(Transform3D(david.global_transform.basis, beside))
	await get_tree().physics_frame
	PlayerInput.touch_interact()
	for _i in 20:
		await get_tree().physics_frame

	if not bool(david.get(&"driving")):
		push_warning("--shot-drive: David did not enter the car")
		return false

	print("DRIVE_DIAG car_y=%.3f david_y=%.3f delta=%.3f" % [
		car.global_position.y, david.global_position.y,
		david.global_position.y - car.global_position.y])

	# Frame the driver's side, the windscreen, and a wide profile.
	var c := car.global_position
	var fwd := car.global_basis.x       # Pogo forward
	var right := car.global_basis.z     # Pogo right (driver's side, RHD)
	DRIVE_POSES = [
		{"name": "drive_side", "eye": c + right * 3.2 + Vector3(0, 1.5, 0),
			"look": c + Vector3(0, 0.85, 0)},
		{"name": "drive_windscreen", "eye": c + fwd * 3.4 + Vector3(0, 1.9, 0),
			"look": c + Vector3(0, 0.9, 0)},
		{"name": "drive_front_quarter", "eye": c + fwd * 3.0 + right * 2.4 + Vector3(0, 1.7, 0),
			"look": c + Vector3(0, 0.85, 0)},
	]
	return true


## Does a one-shot clip actually ADVANCE, or does it just freeze the pose?
##
## `QuaterniusAnimDriver._play_action()` turns the AnimationTree off and calls
## `_player.play()`. In Godot 4.2+ an AnimationTree deactivates the AnimationPlayer
## it binds, and turning the tree off does not turn the player back on — so `play()`
## may advance nothing. This prints the player's active flag and its playback
## position across several frames, which settles it either way.
func _diagnose_oneshot() -> void:
	var cast := get_tree().get_nodes_in_group("cast")
	if cast.is_empty():
		print("ANIMDIAG no cast")
		return
	var actor: Node = cast[0]
	var driver := actor.get_node_or_null(^"QuaterniusAnim")
	var ap := actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var at := actor.find_child("AnimationTree", true, false) as AnimationTree
	if driver == null or ap == null or at == null:
		print("ANIMDIAG missing driver/player/tree")
		return

	print("ANIMDIAG before: tree_active=%s player_active=%s clip=%s" % [
		at.active, ap.active, ap.current_animation])
	driver.play_flinch(0.4)
	print("ANIMDIAG after play_flinch: tree_active=%s player_active=%s clip=%s pos=%.3f" % [
		at.active, ap.active, ap.current_animation, ap.current_animation_position])
	for i in 3:
		for _f in 6:
			await get_tree().process_frame
		print("ANIMDIAG +%d frames: playing=%s clip=%s pos=%.3f" % [
			(i + 1) * 6, ap.is_playing(), ap.current_animation,
			ap.current_animation_position])


## Park the two McCabes face-to-face and let CombatBrain brawl, then print HP.
## Used to verify fighting animations and damage land in a live windowed run.
func _run_brawl_test() -> void:
	var mick: CastMember = null
	var deco: CastMember = null
	for node in get_tree().get_nodes_in_group("cast"):
		if node is CastMember:
			var cm := node as CastMember
			if cm.display_name == "MickMcCabe":
				mick = cm
			elif cm.display_name == "Deco McCabe":
				deco = cm
	if mick == null or deco == null:
		print("FIGHT_TEST missing McCabes")
		return
	var centre := Vector3(-10.5, 0.425, 85.0)
	mick.global_position = centre + Vector3(-0.9, 0.0, 0.0)
	deco.global_position = centre + Vector3(0.9, 0.0, 0.0)
	mick.look_at(Vector3(deco.global_position.x, mick.global_position.y,
		deco.global_position.z), Vector3.UP)
	deco.look_at(Vector3(mick.global_position.x, deco.global_position.y,
		mick.global_position.z), Vector3.UP)
	var hm := Damage.health_of(mick)
	var hd := Damage.health_of(deco)
	if hm != null:
		hm.revive()
	if hd != null:
		hd.revive()
	var start_m := hm.hp if hm else -1.0
	var start_d := hd.hp if hd else -1.0
	# Let CombatBrain settle on the new positions.
	for _i in 30:
		await get_tree().physics_frame
	for _i in 420:
		await get_tree().physics_frame
	var end_m := hm.hp if hm else -1.0
	var end_d := hd.hp if hd else -1.0
	var wounded := int(end_m < start_m) + int(end_d < start_d)
	print("FIGHT_TEST start_mick=%.0f start_deco=%.0f end_mick=%.0f end_deco=%.0f wounded=%d" % [
		start_m, start_d, end_m, end_d, wounded])
	if wounded < 1:
		push_warning("FIGHT_TEST: no damage dealt — check CombatBrain / Health wiring")


func _run() -> void:
	var warmup := _arg_int("--shot-frames=", DEFAULT_WARMUP)
	for _i in warmup:
		await get_tree().process_frame

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 500.0
	add_child(cam)

	# `--shot-drive` puts David in the driver's seat before capturing, which is the
	# only way to eyeball the cabin: he is only seated while driving, and the
	# headless probe cannot show a pixel.
	var poses := POSES
	if OS.get_cmdline_user_args().has("--shot-drive"):
		if await _seat_david():
			poses = DRIVE_POSES

	if OS.get_cmdline_user_args().has("--shot-anim"):
		await _diagnose_oneshot()

	if OS.get_cmdline_user_args().has("--shot-fight"):
		await _run_brawl_test()

	var written := 0
	for i in poses.size():
		var pose := poses[i]
		cam.global_position = pose["eye"] as Vector3
		cam.look_at(pose["look"] as Vector3, Vector3.UP)
		cam.current = true
		for _s in POSE_SETTLE:
			await get_tree().process_frame
		if await _capture(i, str(pose["name"])):
			written += 1

	print("SHOT_DONE %d/%d" % [written, POSES.size()])
	get_tree().quit(0 if written == POSES.size() else 1)


## Returns true if the PNG was written.
func _capture(index: int, label: String) -> bool:
	# The viewport texture holds the frame that has already been drawn, so sync
	# to the end of a draw before reading it back.
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		push_error("--shot: no viewport texture (headless?)")
		return false
	var img := tex.get_image()
	if img == null:
		push_error("--shot: viewport image unavailable (headless?)")
		return false
	var path := "%s/%02d_%s.png" % [OUT_DIR, index, label]
	var err := img.save_png(path)
	if err != OK:
		push_error("--shot: save_png failed for %s (%d)" % [path, err])
		return false
	print("SHOT %s %dx%d" % [ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])
	return true


func _arg_int(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return int(arg.substr(prefix.length()))
	return fallback

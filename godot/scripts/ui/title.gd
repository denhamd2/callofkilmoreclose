## Title screen — GTA Coolock art with a Start button.
## Gate runs (--probe, --shot, --profile) bypass straight to gameplay.
extends Control

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--probe") or args.has("--shot") or args.has("--profile"):
		get_tree().call_deferred("change_scene_to_packed", MAIN_SCENE)


func _on_start_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().change_scene_to_packed(MAIN_SCENE)

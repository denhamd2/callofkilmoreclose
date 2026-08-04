## Shared throw helper for David and CombatBrain.
class_name GrenadeThrow
extends RefCounted

const _SCENE: PackedScene = preload("res://scenes/combat/grenade.tscn")


static func launch(from: Vector3, to: Vector3, thrower: Node,
		entry: Dictionary) -> void:
	var dir := to - from
	var dist := dir.length()
	if dist < 0.01:
		return
	dir = dir.normalized()
	var speed := clampf(dist * 0.55, 8.0, 14.0)
	var vel := dir * speed + Vector3(0.0, 5.5 + dist * 0.04, 0.0)
	var nade := _SCENE.instantiate() as GrenadeProjectile
	if nade == null or thrower == null:
		return
	var root := thrower.get_tree().current_scene
	if root == null:
		return
	root.add_child(nade)
	nade.global_position = from
	nade.setup(
		vel,
		thrower,
		float(entry.get("fuse_time", 2.4)),
		float(entry.get("blast_damage", 55.0)),
		float(entry.get("blast_radius", 5.5)))

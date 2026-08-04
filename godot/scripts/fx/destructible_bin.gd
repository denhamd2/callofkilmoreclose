## Wheelie bin that flies when struck. Replaces the MultiMesh batch entry.
class_name DestructibleBin
extends RigidBody3D

const KNOCK_IMPULSE := 6.0

@onready var _health: Health = $Health


func _ready() -> void:
	add_to_group("hittable")
	add_to_group("destructible")
	if _health != null:
		_health.damaged.connect(_on_damaged)


func _on_damaged(amount: float, source: Node, _hp: float) -> void:
	var normal := Vector3.UP
	if source is Node3D:
		var src := source as Node3D
		normal = (global_position - src.global_position).normalized()
	DecalPool.project(DecalPool.Kind.BULLET, global_position + Vector3(0.0, 0.4, 0.0), normal)
	var impulse := normal * clampf(amount * 0.12, 2.0, KNOCK_IMPULSE)
	impulse.y += clampf(amount * 0.05, 1.0, 4.0)
	apply_central_impulse(impulse)

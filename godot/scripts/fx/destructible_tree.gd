## Verge tree that falls over when shot. Visual-only for nav; a thin trunk collider
## catches bullets.
class_name DestructibleTree
extends Node3D

@export var fall_time := 0.9

var _fallen := false
var _tween: Tween

@onready var _health: Health = $Health


func _ready() -> void:
	add_to_group("hittable")
	add_to_group("destructible")
	if _health != null:
		_health.damaged.connect(_on_damaged)


func _on_damaged(_amount: float, _source: Node, hp: float) -> void:
	if _fallen:
		return
	var hit_pos := global_position + Vector3(0.0, 1.2, 0.0)
	var normal := Vector3.UP
	if _source is Node3D:
		var src := _source as Node3D
		normal = (global_position - src.global_position)
		normal.y = 0.2
		if normal.length_squared() > 0.01:
			normal = normal.normalized()
	DecalPool.project(DecalPool.Kind.SCORCH, hit_pos, normal)
	if hp <= 0.0:
		_fall()


func _fall() -> void:
	if _fallen:
		return
	_fallen = true
	var collider := get_node_or_null("TrunkCollider") as CollisionObject3D
	if collider != null:
		collider.set_collision_layer_value(1, false)
		collider.set_collision_mask_value(1, false)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "rotation:x", rotation.x - PI * 0.5, fall_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

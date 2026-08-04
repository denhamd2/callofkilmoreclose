## Thrown grenade — ballistic arc, timed fuse, radial blast.
class_name GrenadeProjectile
extends RigidBody3D

const GRAVITY := 20.6

var _fuse := 2.4
var _thrower: Node = null
var _damage := 55.0
var _radius := 5.5
var _armed := false
var _detonated := false


func setup(velocity: Vector3, thrower: Node, fuse: float,
		damage: float, radius: float) -> void:
	_thrower = thrower
	_fuse = fuse
	_damage = damage
	_radius = radius
	linear_velocity = velocity
	gravity_scale = 1.0
	_armed = true


func _physics_process(delta: float) -> void:
	if not _armed or _detonated:
		return
	_fuse -= delta
	if _fuse <= 0.0:
		_detonate()


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	var pos := global_position
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = _radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, pos)
	params.collision_mask = 1 | 2 | 4 | 8
	params.collide_with_areas = false
	var hits := space.intersect_shape(params, 32)
	var victims := 0
	for hit in hits:
		var body := hit.get("collider") as Node3D
		if body == null or body == _thrower:
			continue
		if not body.is_in_group("hittable"):
			continue
		var dist := body.global_position.distance_to(pos)
		var falloff := 1.0 - clampf(dist / _radius, 0.0, 1.0)
		var amount := _damage * falloff
		if amount <= 0.5:
			continue
		if Damage.apply(body, amount, _thrower):
			victims += 1
		if body.has_method(&"knock_down"):
			var dir := body.global_position - pos
			dir.y = 0.0
			if dir.length_squared() < 0.01:
				dir = Vector3.FORWARD
			body.knock_down(dir, 6.0 + falloff * 5.0)
	DecalPool.project(DecalPool.Kind.SCORCH, pos, Vector3.UP)
	StreetAudio.play_explosion_at(pos)
	queue_free()


## Immediate blast for probes and scripted tests.
static func detonate_at(world: World3D, pos: Vector3, thrower: Node,
		damage: float, radius: float) -> int:
	if world == null:
		return 0
	var space := world.direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, pos)
	params.collision_mask = 1 | 2 | 4 | 8
	params.collide_with_areas = false
	var hits := space.intersect_shape(params, 32)
	var victims := 0
	for hit in hits:
		var body := hit.get("collider") as Node3D
		if body == null or body == thrower:
			continue
		if not body.is_in_group("hittable"):
			continue
		var dist := body.global_position.distance_to(pos)
		var falloff := 1.0 - clampf(dist / radius, 0.0, 1.0)
		var amount := damage * falloff
		if amount <= 0.5:
			continue
		if Damage.apply(body, amount, thrower):
			victims += 1
	DecalPool.project(DecalPool.Kind.SCORCH, pos, Vector3.UP)
	return victims

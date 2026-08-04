class_name Lib

enum InputType {
	THROTTLE,
	BRAKE,
	STEER,
	CLUTCH,
	
	EVENTS_SEP, #Separator for event-type inputs
	
	GEAR_UP,
	GEAR_DOWN,
	RESET,
}

static func tails_in_arrays(dict: Dictionary) -> Dictionary:
	for key in dict.keys():
		dict[key] = [dict[key].pop_back()]
	return dict

static func rpm_to_omega(rpm: float) -> float:
	return rpm * PI / 30.0

static func omega_to_rpm(omega: float) -> float:
	return omega * 30.0 / PI

static func kmh_to_ms(kmh: float) -> float:
	return kmh / 3.6

static func ms_to_kmh(ms: float) -> float:
	return ms * 3.6

static func signed_angle_around_axis(a: Vector3, b: Vector3, axis: Vector3) -> float:
	var n = axis.normalized()
	var a_perp = a - a.dot(n) * n
	var b_perp = b - b.dot(n) * n
	var cross = a_perp.cross(b_perp)
	var dot = a_perp.dot(b_perp)
	return atan2(n.dot(cross), dot)

static func calculate_aabb_inertia(body: RigidBody3D) -> Vector3:
	var collision_aabb = calculate_collision_aabb(body)
	if collision_aabb.size.length_squared() < 0.001:
		return Vector3.ZERO
	return calculate_box_inertia(body.mass, collision_aabb.size)

static func calculate_collision_aabb(body: CollisionObject3D) -> AABB:
	var collision_aabb = AABB()
	var has_aabb = false
	for node in body.find_children("*", "CollisionShape3D", true, false):
		var collision_shape = node as CollisionShape3D
		if collision_shape == null or collision_shape.disabled or collision_shape.shape == null:
			continue
		if not is_collision_shape_owned_by(collision_shape, body):
			continue
		var points = get_collision_shape_points(collision_shape.shape)
		if points.is_empty():
			continue
		var shape_transform = body.global_transform.affine_inverse() * collision_shape.global_transform
		for point in points:
			var local_point = shape_transform * point
			if has_aabb:
				collision_aabb = collision_aabb.expand(local_point)
			else:
				collision_aabb = AABB(local_point, Vector3.ZERO)
				has_aabb = true
	return collision_aabb

static func calculate_box_inertia(mass: float, size: Vector3) -> Vector3:
	return mass / 12.0 * Vector3(
			size.y * size.y + size.z * size.z,
			size.x * size.x + size.z * size.z,
			size.x * size.x + size.y * size.y
	)

static func is_collision_shape_owned_by(collision_shape: CollisionShape3D, body: CollisionObject3D) -> bool:
	var current = collision_shape.get_parent()
	while current != null:
		if current is CollisionObject3D:
			return current == body
		current = current.get_parent()
	return false

static func get_collision_shape_points(shape: Shape3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if shape is BoxShape3D:
		return get_aabb_corners((shape as BoxShape3D).size * 0.5)
	if shape is ConvexPolygonShape3D:
		for point in (shape as ConvexPolygonShape3D).points:
			result.append(point)
		return result
	if shape is SphereShape3D:
		return get_aabb_corners(Vector3.ONE * (shape as SphereShape3D).radius)
	if shape is CapsuleShape3D:
		var capsule = shape as CapsuleShape3D
		return get_aabb_corners(Vector3(capsule.radius, capsule.height * 0.5, capsule.radius))
	if shape is CylinderShape3D:
		var cylinder = shape as CylinderShape3D
		return get_aabb_corners(Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius))
	return result

static func get_aabb_corners(extents: Vector3) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				corners.append(Vector3(
						extents.x * x_sign,
						extents.y * y_sign,
						extents.z * z_sign
				))
	return corners

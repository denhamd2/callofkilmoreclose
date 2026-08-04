## THE CAR — parked at the kerb outside 18 Kilmore Close.
##
## RVCE Pogo physics on a RigidBody3D (raycast suspension, automatic gearbox).
## Enter/drive/exit UX is unchanged: F to get in/out, David stays in the seat
## each physics step so his third-person camera never hands off to a vehicle rig.
##
## Pogo's longitudinal axis is local +X. Kilmore spawn data still uses Godot's
## -Z forward convention; `place()` rotates the body so +X points along the
## street without touching `kilmore_close.gd`.

class_name Car
extends CarPogo

signal entered
signal exited

const ENTER_DIST := 3.6

## Height of the sprung body origin above the road when the suspension is at rest,
## measured from a driving run. `main.gd` parks the car here so the visual does not
## jump when the suspension takes over.
const RIDE_HEIGHT := 0.66

## Driver seat in Pogo space (+X forward, +Z right), right-hand drive.
##
## `y` is NEGATIVE because the body origin sits high — roughly at window level once
## the ride height above is applied. The cabin floor is at body-local -0.483
## (`Base-chassis`, visual y 0.175, minus the 0.658 mesh drop), so the driver's feet
## belong just below that. It was +0.62, which put his soles above the roofline: he
## was standing on the car, not sitting in it.
const SEAT := Vector3(-0.22, -0.483, 0.34)

## The mannequin is 1.78 m and the Golf's cabin is about 1.05 m from floor to
## headlining, so a full-size seated David cannot both stand on the cabin floor and
## keep his head under the roof — one end always clips. Shrinking the visual body
## (not the David node itself, which would take the camera rig with it) resolves
## both ends and is imperceptible at this distance.
const DRIVER_SCALE := 0.73

## The glTF has no steering wheel, no seats and no interior of any kind — the whole
## bodyshell including all four door skins is a single mesh named `Roof`. These are
## generated instead. The same limitation is why there is no door-opening
## animation: there is no door mesh to swing.
const WHEEL_POS := Vector3(0.30, 0.02, 0.34)
const WHEEL_RADIUS := 0.17
const SEAT_BACK_POS := Vector3(-0.44, -0.20, 0.34)

## Below this the car is parking, not mowing anyone down (m/s).
const MIN_KNOCK_SPEED := 2.2
## Damage per m/s of impact speed. At ~14 m/s (the probe's drive speed) that is
## ~112 against 160 hp — a heavy hit that is survivable, so they get back up.
const KNOCK_DAMAGE_PER_MS := 8.0
## Car takes damage when it hits the world or a pedestrian (m/s thresholds).
const MIN_CRASH_SPEED := 3.5
const CRASH_DAMAGE_PER_MS := 3.5
const PED_CRASH_DAMAGE_PER_MS := 0.35
const EXIT_SPOTS: Array[Vector3] = [
	Vector3(-0.2, 0.1, 1.85),
	Vector3(-0.2, 0.1, -1.85),
	Vector3(1.6, 0.1, 0.34),
	Vector3(-3.2, 0.1, 0.0),
]
var _drive_agent: KilmoreDriveAgent = null

var driver: DavidController = null
var speed := 0.0

var _steer := 0.0
var _heading := 0.0
var _prompt_shown := false
var _player: DavidController = null
var _paint := Color(0.36, 0.11, 0.13)
var _bloodied := false
var _smoke: GPUParticles3D = null
var _debris_spawned := false
var _crash_cooldown := 0.0

@onready var _health: Health = $Health

@onready var _prompt: Label = get_node_or_null("../HUD/Prompt")
@onready var _mesh: Node3D = $Mesh


func _ready() -> void:
	add_to_group("hittable")
	_drive_agent = KilmoreDriveAgent.new()
	input_agent = _drive_agent
	add_child(_drive_agent)
	input_agent.start()

	if inertia.is_zero_approx():
		inertia = Lib.calculate_aabb_inertia(self)

	chassis.set_car(self)
	transmission.set_base_min_rpm(engine.min_rpm)
	if transmission_mode == TransmissionMode.AUTOMATIC:
		transmission.gear_up()
	_create_bumpers()

	PlayerInput.interact_pressed.connect(_on_interact)
	if _mesh != null:
		MeshDress.dress_car(_mesh, _paint)
	_hide_pogo_wheel_placeholders()
	_build_cabin()
	if _health != null:
		_health.damaged.connect(_on_damaged)
	body_entered.connect(_on_body_entered)
	_park()


func place(at: Transform3D) -> void:
	var pogo_basis := at.basis * Basis.from_euler(Vector3(0.0, PI / 2.0, 0.0))
	global_transform = Transform3D(pogo_basis, at.origin)
	_heading = global_transform.basis.get_euler().y
	speed = 0.0
	_steer = 0.0
	drive_axle_omega = 0.0
	_park()


func _physics_process(delta: float) -> void:
	_crash_cooldown = maxf(0.0, _crash_cooldown - delta)
	_drive_agent.active = driver != null
	if driver != null:
		_seat_driver()
		super._physics_process(delta)
		speed = linear_velocity.dot(global_basis.x)
		_check_pedestrian_impacts()
	else:
		_update_prompt()
		if not freeze:
			_park()


## Run people over.
##
## Polls contacts rather than using `body_entered`, because the car reports contacts
## from five shapes — the authored hull plus the four suspension bumper spheres
## Pogo adds at runtime — and a pedestrian scraping along the flank would fire the
## signal repeatedly. `CastMember.knock_down()` is idempotent while someone is
## already down, so polling is safe.
##
## No collision mask change is needed: the cast mask (15) includes `vehicle`, and
## Godot's broadphase filter is bidirectional, so car/pedestrian pairs already
## generate contacts. The car must NOT be put on layer 1 — its own suspension
## raycasts are mask 1 and are not parent-excluded, so it would drive up itself.
func _check_pedestrian_impacts() -> void:
	if ProfileToggles.has(&"no_contacts"):
		return
	var v := linear_velocity
	# Below a brisk walk this is a nudge, not a knockdown.
	if v.length() < MIN_KNOCK_SPEED:
		return
	for body in get_colliding_bodies():
		var victim := body as Node3D
		if victim == null or not victim.has_method(&"knock_down"):
			continue
		if victim.has_method(&"is_knocked") and victim.is_knocked():
			continue
		# Point velocity, not `linear_velocity`: `center_of_mass` is offset to
		# (0.05, -0.3, 0), so a turning car clips people faster at the corners.
		var impact := get_point_velocity(victim.global_position).length()
		var dir := victim.global_position - global_position
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			dir = global_basis.x
		# Damage scales with how hard they were hit; survivors get back up.
		Damage.apply(victim, impact * KNOCK_DAMAGE_PER_MS, self)
		if _health != null:
			_health.apply(impact * PED_CRASH_DAMAGE_PER_MS, victim)
		victim.knock_down(dir, impact)
		set_bloodied(dir)
		StreetAudio.play_melee_thud()


## Place David in the driver's seat, facing along the car rather than across it.
##
## This used to assign `global_transform` wholesale, which handed David the car's
## basis. Pogo's forward is local +X while the mannequin's forward is -Z, so he sat
## rotated 90° across the cabin. Rotating the car basis by -90° about Y maps his -Z
## onto the car's +X.
func _seat_driver() -> void:
	var seat_basis := global_transform.basis * Basis.from_euler(Vector3(0.0, -PI / 2.0, 0.0))
	driver.global_transform = Transform3D(
		seat_basis, global_transform.translated_local(SEAT).origin)


## Each SuspensionPogo instances RVCE's `wheel.tscn`, whose visual is a black-and-
## white checkered placeholder. The Golf glTF supplies its own wheels, so those
## placeholders just appear as four checkered balls under the car. Hide the meshes
## and keep the suspension nodes themselves, which do the physics.
func _hide_pogo_wheel_placeholders() -> void:
	for wheel in find_children("*", "MeshInstance3D", true, false):
		var mi := wheel as MeshInstance3D
		if mi == null:
			continue
		# Everything under Mesh is the Golf; anything else is Pogo's placeholder.
		if _mesh != null and _mesh.is_ancestor_of(mi):
			continue
		mi.visible = false


## Scale the mannequin only — never the David node, which parents the camera rig.
## Scaling is about David's origin, which is at his feet, so his soles stay on the
## cabin floor and only his height comes down.
func _scale_driver_body(david: Node3D, factor: float) -> void:
	var body := david.get_node_or_null(^"Body") as Node3D
	if body != null:
		body.scale = Vector3.ONE * factor


## Steering wheel and seat back, generated because the model has neither.
func _build_cabin() -> void:
	var wheel := MeshInstance3D.new()
	wheel.name = "SteeringWheel"
	var torus := TorusMesh.new()
	torus.inner_radius = WHEEL_RADIUS * 0.78
	torus.outer_radius = WHEEL_RADIUS
	torus.rings = 24
	torus.ring_segments = 10
	wheel.mesh = torus
	# TorusMesh lies in the XZ plane; stand it up and rake it back like a real
	# column. Pogo's forward is +X, so the wheel's axis has to point along X.
	wheel.transform = Transform3D(
		Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(72.0))), WHEEL_POS)
	wheel.material_override = MeshDress.cabin_trim()
	wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wheel)

	var seat := MeshInstance3D.new()
	seat.name = "SeatBack"
	var box := BoxMesh.new()
	box.size = Vector3(0.10, 0.62, 0.46)
	seat.mesh = box
	seat.position = SEAT_BACK_POS
	seat.material_override = MeshDress.cabin_trim()
	seat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(seat)


func _park() -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	drive_axle_omega = 0.0
	speed = 0.0


func _unpark() -> void:
	freeze = false


func _nearest_player() -> DavidController:
	if _player != null:
		return _player
	for p in get_tree().get_nodes_in_group("player"):
		if p is DavidController:
			_player = p
			return _player
	return null


func _nearest_street() -> StreetBuilder:
	return get_parent().get_node_or_null("Street") as StreetBuilder


func _nearest_slot_index() -> int:
	var david := _nearest_player()
	if david == null:
		return -1
	var street := _nearest_street()
	if street == null:
		return -1
	return street.nearest_open_park_slot(david.global_position, ENTER_DIST)


func _update_prompt() -> void:
	if _prompt == null:
		return
	var david := _nearest_player()
	var near_car := david != null and not david.driving \
		and david.global_position.distance_to(global_position) <= ENTER_DIST
	var slot_i := _nearest_slot_index()
	var near_slot := slot_i >= 0
	var near := near_car or near_slot
	if near != _prompt_shown:
		_prompt_shown = near
		_prompt.visible = near
		if near_slot and not near_car:
			_prompt.text = "Press F  —  Take car"
		else:
			_prompt.text = "Press F  —  Get in"


func _on_interact() -> void:
	if driver != null:
		_exit()
		return
	var david := _nearest_player()
	if david == null or david.driving:
		return
	var slot_i := _nearest_slot_index()
	var street := _nearest_street()
	if slot_i >= 0 and street != null:
		street.claim_park_slot(slot_i)
		place(street.park_slot_place(slot_i))
		_enter(david)
		return
	if david.global_position.distance_to(global_position) > ENTER_DIST:
		return
	_enter(david)


func _enter(david: DavidController) -> void:
	driver = david
	david.driving = true
	david.set_collision_layer_value(2, false)
	david.set_collision_mask_value(1, false)
	_unpark()
	_scale_driver_body(david, DRIVER_SCALE)
	_seat_driver()
	var cam := david.get_node_or_null("CamYaw") as ThirdPersonCamera
	if cam != null:
		cam.set_driving(true, get_rid(), self)
	if _prompt != null:
		_prompt.visible = false
		_prompt_shown = false
	entered.emit()


func _exit() -> void:
	var david := driver
	driver = null
	_steer = 0.0

	var space := get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.78
	probe.shape = capsule
	probe.collision_mask = 1
	var chosen := global_transform.translated_local(EXIT_SPOTS[0])
	for spot in EXIT_SPOTS:
		var candidate := global_transform.translated_local(spot)
		probe.transform = Transform3D(Basis.IDENTITY,
			candidate.origin + Vector3(0.0, 0.9, 0.0))
		if space.intersect_shape(probe, 1).is_empty():
			chosen = candidate
			break

	david.driving = false
	_scale_driver_body(david, 1.0)
	david.set_collision_layer_value(2, true)
	david.set_collision_mask_value(1, true)
	david.teleport(Transform3D(global_transform.basis, chosen.origin))
	var cam := david.get_node_or_null("CamYaw") as ThirdPersonCamera
	if cam != null:
		cam.set_driving(false)
	_park()
	exited.emit()


func _on_body_entered(body: Node) -> void:
	if _health == null or _crash_cooldown > 0.0:
		return
	# Pedestrians are handled in _check_pedestrian_impacts.
	if body != null and body.has_method(&"knock_down"):
		return
	var spd := linear_velocity.length()
	if spd < MIN_CRASH_SPEED:
		return
	_crash_cooldown = 0.25
	var dmg := (spd - MIN_CRASH_SPEED) * CRASH_DAMAGE_PER_MS
	_health.apply(dmg, body)
	_apply_damage_look(_health.hp)
	if _health.hp <= _health.max_hp * 0.45:
		_ensure_smoke()
	_spawn_debris_if_needed()


func take_hit(amount: float, source: Node = null) -> void:
	Damage.apply(self, amount, source)


func _on_damaged(_amount: float, _source: Node, hp: float) -> void:
	_apply_damage_look(hp)
	_spawn_debris_if_needed()
	if hp <= _health.max_hp * 0.45:
		_ensure_smoke()


func _apply_damage_look(hp: float = -1.0) -> void:
	if _mesh == null or _health == null:
		return
	var frac := hp / _health.max_hp if hp >= 0.0 else _health.fraction()
	MeshDress.apply_car_damage(_mesh, _paint, frac)


func set_bloodied(impact_dir: Vector3 = Vector3.ZERO) -> void:
	if _bloodied:
		return
	_bloodied = true
	_apply_damage_look()
	var bonnet := global_transform.translated_local(Vector3(0.9, 0.15, 0.0)).origin
	var normal := global_transform.basis.y
	if impact_dir.length_squared() > 0.01:
		normal = (-impact_dir).normalized()
	DecalPool.project(DecalPool.Kind.BLOOD, bonnet, normal)


func clear_cosmetics() -> void:
	_bloodied = false
	_debris_spawned = false
	if _smoke != null:
		_smoke.emitting = false
	if _mesh != null:
		MeshDress.dress_car(_mesh, _paint)
	if _health != null:
		_health.revive()


func _ensure_smoke() -> void:
	if _smoke != null:
		_smoke.emitting = true
		return
	_smoke = GPUParticles3D.new()
	_smoke.name = "DamageSmoke"
	_smoke.position = Vector3(0.0, 0.35, 0.0)
	_smoke.amount = 24
	_smoke.lifetime = 1.6
	_smoke.emitting = true
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 18.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 1.2
	mat.gravity = Vector3(0.0, 0.6, 0.0)
	_smoke.process_material = mat
	add_child(_smoke)


func _spawn_debris_if_needed() -> void:
	if _debris_spawned or _mesh == null or _health == null:
		return
	if _health.fraction() > 0.35:
		return
	_debris_spawned = true
	for mi in _mesh.find_children("*", "MeshInstance3D", true, false):
		var pl := mi.name.to_lower()
		if "mirror" in pl or "indicator" in pl:
			_spawn_debris_piece(mi)


func _spawn_debris_piece(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	mi.visible = false
	var piece := RigidBody3D.new()
	piece.name = "CarDebris"
	piece.mass = 0.8
	piece.collision_layer = 1
	piece.collision_mask = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mi.get_aabb().size.max(Vector3(0.08, 0.08, 0.08))
	col.shape = box
	piece.add_child(col)
	var copy := MeshInstance3D.new()
	copy.mesh = mi.mesh
	copy.material_override = mi.material_override
	piece.add_child(copy)
	get_parent().add_child(piece)
	piece.global_transform = mi.global_transform
	piece.linear_velocity = linear_velocity * 0.35 + Vector3(
		randf_range(-1.5, 1.5), randf_range(1.0, 3.0), randf_range(-1.5, 1.5))

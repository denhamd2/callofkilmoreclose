## DAVID — the player character.
##
## Third-person CharacterBody3D with Quaternius mannequin animations, melee, and a
## simple raycast pistol. Movement tuning is carried over from the prototype's
## `src/player/tuning.js` (Modern Warfare numbers, metres).

class_name DavidController
extends CharacterBody3D

signal melee_swung
signal melee_hit(target: Node3D)
signal shot_fired
signal shot_hit(target: Node3D)
signal weapon_changed(id: StringName)

enum Loadout {
	UNARMED,
	PISTOL,
	RANGED,
}

const WALK_SPEED := 4.57
const SPRINT_SPEED := 7.01
const GRAVITY := 20.6
const JUMP_APEX := 0.6
const JUMP_SPEED := 4.972
const GROUND_ACCEL := 92.0
const GROUND_DECEL := 52.0
const AIR_ACCEL_SCALE := 0.25
const TURN_RATE := 6.2
const COYOTE_TIME := 0.09
const JUMP_BUFFER := 0.13

const MELEE_REACH := 1.9
const MELEE_RADIUS := 0.55
const MELEE_COOLDOWN := 0.55
const MELEE_DAMAGE := 35.0
const MELEE_CONTACT := 0.14

const FIRE_RANGE := 40.0
const FIRE_COOLDOWN := 0.35
const FIRE_DAMAGE := 25.0

var loadout: Loadout = Loadout.UNARMED
var weapon_id: StringName = WeaponCatalog.UNARMED
var driving: bool = false

var _coyote := 0.0
var _buffered_jump := 0.0
var _melee_timer := 0.0
var _fire_timer := 0.0
var _swing := 0.0
var _facing := 0.0

@onready var _camera: ThirdPersonCamera = $CamYaw
@onready var _body: Node3D = $Body
@onready var _animator: QuaterniusAnimDriver = $QuaterniusAnim
@onready var _muzzle_marker: Marker3D = $MuzzleFlash
@onready var _weapon_holder: WeaponHolder = $Body/WeaponMount

var _melee_query := PhysicsShapeQueryParameters3D.new()
var _melee_shape := SphereShape3D.new()

const _FLASH_TEX: Texture2D = preload("res://assets/generated/muzzle_flash_frame_0.png")
const _SPARK_TEX: Texture2D = preload("res://assets/generated/spark_burst_frame_0.png")


func _ready() -> void:
	_facing = rotation.y
	_melee_shape.radius = MELEE_RADIUS
	_melee_query.shape = _melee_shape
	_melee_query.collide_with_bodies = true
	_melee_query.collide_with_areas = false
	var skip: Array[RID] = [get_rid()]
	_melee_query.exclude = skip
	PlayerInput.jump_pressed.connect(_on_jump)
	PlayerInput.melee_pressed.connect(_on_melee)
	PlayerInput.fire_pressed.connect(_on_fire)
	if _animator != null:
		_animator.setup(_body)
	if _weapon_holder != null:
		_weapon_holder.setup_on_body(_body)
	equip_weapon(WeaponCatalog.UNARMED)


func equip_weapon(id: StringName) -> void:
	if weapon_id == id:
		return
	weapon_id = id
	var entry := WeaponCatalog.get_entry(id)
	loadout = Loadout.UNARMED
	if bool(entry.get("ranged", false)):
		loadout = Loadout.RANGED
	if _weapon_holder != null:
		_weapon_holder.set_weapon(id)
	weapon_changed.emit(id)


func get_fire_damage() -> float:
	return float(WeaponCatalog.get_entry(weapon_id).get("fire_damage", FIRE_DAMAGE))


func get_fire_cooldown() -> float:
	return float(WeaponCatalog.get_entry(weapon_id).get("fire_cooldown", FIRE_COOLDOWN))


func get_fire_range() -> float:
	return float(WeaponCatalog.get_entry(weapon_id).get("fire_range", FIRE_RANGE))


func _physics_process(delta: float) -> void:
	_melee_timer = maxf(0.0, _melee_timer - delta)
	_fire_timer = maxf(0.0, _fire_timer - delta)
	if _swing > 0.0:
		var before := _swing
		_swing = maxf(0.0, _swing - delta)
		if before > MELEE_CONTACT and _swing <= MELEE_CONTACT:
			_resolve_melee()
	_update_animation()

	if driving:
		velocity = Vector3.ZERO
		return

	_apply_gravity(delta)
	_apply_movement(delta)
	move_and_slide()
	if is_on_floor() and not driving:
		var planar := Vector3(velocity.x, 0.0, velocity.z).length()
		var sprinting := PlayerInput.sprinting() and planar > WALK_SPEED * 0.85
		StreetAudio.step_cadence(planar, delta, sprinting)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		_coyote = COYOTE_TIME
		if velocity.y < 0.0:
			velocity.y = -2.0
	else:
		_coyote = maxf(0.0, _coyote - delta)
		velocity.y -= GRAVITY * delta

	_buffered_jump = maxf(0.0, _buffered_jump - delta)
	if _buffered_jump > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_SPEED
		_buffered_jump = 0.0
		_coyote = 0.0


func _apply_movement(delta: float) -> void:
	var stick := PlayerInput.move_axis()
	var yaw := _camera.yaw()
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish := (right * stick.x + forward * stick.y).limit_length(1.0)

	var speed := SPRINT_SPEED if (PlayerInput.sprinting() and stick.y > 0.4) else WALK_SPEED
	if _swing > 0.0:
		speed = WALK_SPEED * 0.45

	var target := wish * speed
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var rate := GROUND_ACCEL if wish.length_squared() > 0.001 else GROUND_DECEL
	if not is_on_floor():
		rate *= AIR_ACCEL_SCALE
	planar = planar.move_toward(target, rate * delta)
	velocity.x = planar.x
	velocity.z = planar.z

	if wish.length_squared() > 0.01:
		var want := atan2(-wish.x, -wish.z)
		var diff := wrapf(want - _facing, -PI, PI)
		var scale := 1.0 + absf(diff) / PI * 2.0
		_facing = wrapf(_facing + clampf(diff, -TURN_RATE * scale * delta,
			TURN_RATE * scale * delta), -PI, PI)
	rotation.y = _facing


func _update_animation() -> void:
	if _animator == null:
		return
	_animator.set_driving(driving)
	if driving:
		return
	var planar := Vector3(velocity.x, 0.0, velocity.z).length()
	var sprinting := PlayerInput.sprinting() and planar > WALK_SPEED * 0.85
	_animator.set_locomotion(planar, sprinting, is_on_floor() and not driving,
		WALK_SPEED, SPRINT_SPEED)


# ------------------------------------------------------------------ melee

func _on_jump() -> void:
	if not driving:
		_buffered_jump = JUMP_BUFFER


func _on_melee() -> void:
	if driving or _melee_timer > 0.0:
		return
	_melee_timer = MELEE_COOLDOWN
	_swing = MELEE_COOLDOWN * 0.55
	melee_swung.emit()
	if _animator != null:
		_animator.play_melee(MELEE_COOLDOWN * 0.55)


func _resolve_melee() -> void:
	var space := get_world_3d().direct_space_state
	var dir := _camera.aim_direction()
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	var origin := global_position + Vector3(0.0, 1.25, 0.0) + dir * MELEE_REACH
	_melee_query.transform = Transform3D(Basis.IDENTITY, origin)
	var hits := space.intersect_shape(_melee_query, 8)
	var fallback: Node3D = null
	for hit in hits:
		var collider := hit.get("collider") as Node3D
		if collider == null or collider == self:
			continue
		if collider.is_in_group("hittable"):
			melee_hit.emit(collider)
			return
		if fallback == null:
			fallback = collider
	if fallback != null:
		melee_hit.emit(fallback)


# ------------------------------------------------------------------ firearm

func _on_fire() -> void:
	if driving or _fire_timer > 0.0 or loadout != Loadout.RANGED:
		return
	_fire_timer = get_fire_cooldown()
	shot_fired.emit()
	_spawn_flash()
	if _animator != null:
		_animator.play_shoot(get_fire_cooldown())
	_resolve_fire()


func _resolve_fire() -> void:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, 1.35, 0.0)
	var dir := _camera.aim_direction()
	if dir.length_squared() < 0.001:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * get_fire_range())
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Node3D
	if collider != null and collider != self:
		_spawn_spark(hit.get("position", origin + dir * FIRE_RANGE))
		shot_hit.emit(collider)


func _spawn_flash() -> void:
	if _muzzle_marker == null:
		return
	var sprite := Sprite3D.new()
	sprite.texture = _FLASH_TEX
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.position = _muzzle_marker.position
	sprite.pixel_size = 0.025
	add_child(sprite)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate:a", 0.0, 0.12)
	tw.tween_callback(sprite.queue_free)


func _spawn_spark(at: Vector3) -> void:
	var sprite := Sprite3D.new()
	sprite.texture = _SPARK_TEX
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.position = to_local(at)
	sprite.pixel_size = 0.02
	add_child(sprite)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate:a", 0.0, 0.28)
	tw.tween_callback(sprite.queue_free)


func teleport(to: Transform3D) -> void:
	global_transform = to
	velocity = Vector3.ZERO
	_facing = to.basis.get_euler().y
	rotation.y = _facing

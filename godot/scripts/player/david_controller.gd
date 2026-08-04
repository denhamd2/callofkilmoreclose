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

## Olive, deliberately outside the five cast jacket tints in data/cast.gd — the
## player is on screen for the whole session and needs to be the readable one.
const JACKET := Color(0.30, 0.31, 0.22)

var loadout: Loadout = Loadout.UNARMED
## Starts empty rather than UNARMED so the first `equip_weapon(UNARMED)` is not
## swallowed by the identity guard — `weapon_changed` never fired at startup, so
## the weapon selector opened out of sync with the actual loadout.
var weapon_id: StringName = &""
var driving: bool = false

## Read by `Factions.of()`. David sides against the McCabes.
var faction: StringName = Factions.DAVID
var dead := false

## Seconds face-down before David is put back on his own doorstep.
const RESPAWN_DELAY := 3.5

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
@onready var _health: Health = $Health

var _melee_query := PhysicsShapeQueryParameters3D.new()
var _melee_shape := SphereShape3D.new()

const _FLASH_TEX: Texture2D = preload("res://assets/generated/muzzle_flash_frame_0.png")
const _SPARK_TEX: Texture2D = preload("res://assets/generated/spark_burst_frame_0.png")


func _ready() -> void:
	_facing = rotation.y
	# The sphere is centred at half reach with a radius to match, so the swept
	# volume runs from the chest out to MELEE_REACH. Previously it was centred
	# *at* full reach, leaving a 1.35 m dead zone directly in front of David —
	# anyone he was standing next to could not be punched at all.
	_melee_shape.radius = MELEE_REACH * 0.5 + MELEE_RADIUS
	_melee_query.shape = _melee_shape
	_melee_query.collide_with_bodies = true
	_melee_query.collide_with_areas = false
	# Was unset, i.e. all 32 layers — so a punch routinely "hit" the ground plate
	# or a boundary wall and reported that back as the target. player | npc only.
	_melee_query.collision_mask = 2 | 4 | 8
	var skip: Array[RID] = [get_rid()]
	_melee_query.exclude = skip
	PlayerInput.jump_pressed.connect(_on_jump)
	PlayerInput.melee_pressed.connect(_on_melee)
	PlayerInput.fire_pressed.connect(_on_fire)
	# David was the one actor never dressed, so he rendered in the raw glTF's
	# orange M_Main / purple M_Joints. The cast and the dummy already do this.
	if _body != null:
		MeshDress.dress_mannequin(_body, JACKET)
	if _animator != null:
		_animator.setup(_body)
	if _weapon_holder != null:
		_weapon_holder.setup_on_body(_body)
	if _health != null:
		_health.died.connect(_on_died)
		_health.revived.connect(_on_revived)
		_health.damaged.connect(_on_damaged)
	PlayerInput.weapon_slot.connect(_on_weapon_slot)
	PlayerInput.weapon_cycle.connect(_on_weapon_cycle)
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

	if dead:
		# Still fall, but no input and no melee — the death clip plays out.
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
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
	if driving or dead or _melee_timer > 0.0:
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
	var chest := global_position + Vector3(0.0, 1.25, 0.0)
	var origin := chest + dir * (MELEE_REACH * 0.5)
	_melee_query.transform = Transform3D(Basis.IDENTITY, origin)
	var hits := space.intersect_shape(_melee_query, 8)
	# Nearest hittable in the forward arc. The old version returned the first
	# result of any kind, including the ground plate and boundary walls, which is
	# why punches "landed" on scenery — and the mask now excludes those anyway.
	var best: Node3D = null
	var best_d := INF
	for hit in hits:
		var collider := hit.get("collider") as Node3D
		if collider == null or collider == self:
			continue
		if not collider.is_in_group("hittable"):
			continue
		var to_target := collider.global_position - chest
		to_target.y = 0.0
		if to_target.length_squared() > 0.0004 \
				and dir.dot(to_target.normalized()) < 0.35:
			continue  # behind or off to the side — the swing is forward-facing
		var d := to_target.length()
		if d < best_d:
			best_d = d
			best = collider
	if best != null:
		var hit_pos := origin + dir * best_d
		DecalPool.project(DecalPool.Kind.BULLET, hit_pos, -dir)
		melee_hit.emit(best)


# ------------------------------------------------------------------ firearm

func _on_fire() -> void:
	if driving or dead:
		return
	var entry := WeaponCatalog.get_entry(weapon_id)
	if bool(entry.get("throwable", false)):
		if _fire_timer > 0.0:
			return
		_fire_timer = float(entry.get("fire_cooldown", 4.5))
		shot_fired.emit()
		if _animator != null:
			_animator.play_throw(0.5)
		var from := global_position + Vector3(0.0, 1.35, 0.0)
		var dir := _camera.aim_direction()
		if dir.length_squared() < 0.001:
			dir = -global_transform.basis.z
		var to := from + dir.normalized() * float(entry.get("fire_range", 18.0))
		GrenadeThrow.launch(from, to, self, entry)
		return
	if _fire_timer > 0.0 or loadout != Loadout.RANGED:
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
	# world | player | npc | vehicle — bullets should stop on walls, so `world`
	# stays in, unlike the melee mask.
	query.collision_mask = 1 | 2 | 4 | 8
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var hit_pos: Vector3 = hit.get("position", origin + dir * get_fire_range())
	var hit_normal: Vector3 = hit.get("normal", -dir)
	_spawn_spark(hit_pos)
	DecalPool.project(DecalPool.Kind.BULLET, hit_pos, hit_normal)
	var collider := hit.get("collider") as Node3D
	if collider != null and collider != self:
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


# ------------------------------------------------------------------ health

func _on_damaged(_amount: float, _source: Node, _hp: float) -> void:
	if _animator != null and not dead:
		_animator.play_flinch()


## Number keys pick a weapon directly; Tab and the mouse wheel cycle. Before
## this the only way to arm David was clicking the on-screen selector while the
## cursor was captured, so the entire ranged half of combat was unreachable.
func _on_weapon_slot(slot: int) -> void:
	if dead or driving:
		return
	var ids := WeaponCatalog.list_ids()
	if slot >= 0 and slot < ids.size():
		equip_weapon(ids[slot])


func _on_weapon_cycle(dir: int) -> void:
	if dead or driving:
		return
	var ids := WeaponCatalog.list_ids()
	if ids.is_empty():
		return
	var at := ids.find(weapon_id)
	if at < 0:
		at = 0
	equip_weapon(ids[wrapi(at + dir, 0, ids.size())])


## Kept so the `has_method("take_hit")` contract in `main.gd` still holds.
func take_hit(amount: float, source: Node = null) -> void:
	if _health != null:
		_health.apply(amount, source)


func is_alive() -> bool:
	return _health == null or _health.is_alive()


func _on_died(_source: Node) -> void:
	dead = true
	velocity = Vector3.ZERO
	if _animator != null:
		_animator.play_death()
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_respawn)


func _respawn() -> void:
	if _health != null:
		_health.revive()


func _on_revived() -> void:
	dead = false
	var spawn := KilmoreClose.david_spawn()
	spawn.origin.y = KilmoreClose.WALK_H + 0.3
	teleport(spawn)
	equip_weapon(WeaponCatalog.UNARMED)
	if _animator != null:
		_animator.reset_alive()


func teleport(to: Transform3D) -> void:
	global_transform = to
	velocity = Vector3.ZERO
	_facing = to.basis.get_euler().y
	rotation.y = _facing

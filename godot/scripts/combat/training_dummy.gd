## Static combat target — Quaternius mannequin, not a cast member.
class_name TrainingDummy
extends StaticBody3D

const RESET_DELAY := 3.0
const DUMMY_TINT := Color(0.95, 0.72, 0.55)

## The dummy is a target, not a combatant — it takes hits from either side.
var faction: StringName = Factions.NEUTRAL

@onready var _status: Label3D = $StatusLabel
@onready var _body: Node3D = $Body
@onready var _reset_timer: Timer = $ResetTimer
@onready var _animator: QuaterniusAnimDriver = $QuaterniusAnim
@onready var _weapon: WeaponHolder = $Body/WeaponMount
@onready var _health: Health = $Health


signal health_changed(current: float, maximum: float)


func _ready() -> void:
	add_to_group("hittable")
	add_to_group("combat_dummy")
	MeshDress.dress_mannequin(_body, DUMMY_TINT)
	if _animator != null:
		_animator.setup(_body)
	if _weapon != null:
		_weapon.setup_on_body(_body)
		_weapon.set_weapon(&"shotgun")
	if _health != null:
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_defeated)
	_refresh_label()
	if _reset_timer != null:
		_reset_timer.timeout.connect(_on_reset)


func take_hit(amount: float, source: Node = null) -> void:
	if _health != null:
		_health.apply(amount, source)


func is_alive() -> bool:
	return _health == null or _health.is_alive()


func _on_damaged(_amount: float, _source: Node, hp: float) -> void:
	_flash()
	_refresh_label()
	health_changed.emit(hp, _max_hp())
	# The dummy is the first thing anyone punches, and it used to react by tinting a
	# floating label and nothing else — so the very first hit in the game looked
	# like it had no effect.
	if _animator != null:
		_animator.play_flinch()


func _max_hp() -> float:
	return _health.max_hp if _health != null else 100.0


func _refresh_label() -> void:
	if _status == null or _health == null:
		return
	_status.text = "TARGET %d" % int(ceilf(_health.hp))


func _flash() -> void:
	if _status != null:
		_status.modulate = Color(1.0, 0.55, 0.35, 1.0)


func _on_defeated(_source: Node) -> void:
	if _status != null:
		_status.text = "DOWN"
		_status.modulate = Color(0.55, 0.55, 0.55, 1.0)
	if _animator != null:
		_animator.play_death()
	if _reset_timer != null:
		_reset_timer.start()


func _on_reset() -> void:
	if _health != null:
		_health.revive()
	_refresh_label()
	health_changed.emit(_max_hp(), _max_hp())
	if _status != null:
		_status.modulate = Color(1.0, 0.82, 0.45, 0.95)
	if _animator != null:
		_animator.reset_alive()
	MeshDress.dress_mannequin(_body, DUMMY_TINT)

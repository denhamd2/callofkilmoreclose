## Static combat target — Quaternius mannequin, not a cast member.
class_name TrainingDummy
extends StaticBody3D

const MAX_HP := 100.0
const RESET_DELAY := 3.0
const DUMMY_TINT := Color(0.95, 0.72, 0.55)

var _hp := MAX_HP

@onready var _status: Label3D = $StatusLabel
@onready var _body: Node3D = $Body
@onready var _reset_timer: Timer = $ResetTimer
@onready var _animator: QuaterniusAnimDriver = $QuaterniusAnim
@onready var _weapon: WeaponHolder = $Body/WeaponMount


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
	_refresh_label()
	if _reset_timer != null:
		_reset_timer.timeout.connect(_on_reset)


func take_hit(amount: float, _source: Node) -> void:
	if _hp <= 0.0:
		return
	_hp = maxf(0.0, _hp - amount)
	_flash()
	_refresh_label()
	health_changed.emit(_hp, MAX_HP)
	if _hp <= 0.0:
		_on_defeated()


func _refresh_label() -> void:
	if _status == null:
		return
	_status.text = "TARGET %d" % int(ceilf(_hp))


func _flash() -> void:
	if _status != null:
		_status.modulate = Color(1.0, 0.55, 0.35, 1.0)


func _on_defeated() -> void:
	if _status != null:
		_status.text = "DOWN"
		_status.modulate = Color(0.55, 0.55, 0.55, 1.0)
	if _animator != null:
		_animator.play_death()
	if _reset_timer != null:
		_reset_timer.start()


func _on_reset() -> void:
	_hp = MAX_HP
	_refresh_label()
	health_changed.emit(_hp, MAX_HP)
	if _status != null:
		_status.modulate = Color(1.0, 0.82, 0.45, 0.95)
	if _animator != null:
		_animator.reset_alive()
	MeshDress.dress_mannequin(_body, DUMMY_TINT)

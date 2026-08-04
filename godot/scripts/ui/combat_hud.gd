## Combat HUD — crosshair reticle, target health bar, and David's own health.
##
## A thin CanvasLayer overlay. Both bars are driven by `Health` nodes rather than
## by the actors themselves, so anything with a `Health` child can be bound here
## without new plumbing.
class_name CombatHUD
extends CanvasLayer

const TARGET_BAR_WIDTH := 192.0
const PLAYER_BAR_WIDTH := 220.0

var _dummy: TrainingDummy
var _dummy_max_hp := 100.0
var _last_hp := 100.0

var _player_health: Health = null

@onready var _bar_bg: ColorRect = $HPBar/Background
@onready var _bar_fill: ColorRect = $HPBar/Fill
@onready var _bar_label: Label = $HPBar/Label

@onready var _player_bg: ColorRect = $PlayerHP/Background
@onready var _player_fill: ColorRect = $PlayerHP/Fill
@onready var _player_label: Label = $PlayerHP/Label


func _ready() -> void:
	# Find the training dummy — there's only one in this slice.
	for node in get_tree().get_nodes_in_group(&"combat_dummy"):
		if node is TrainingDummy:
			_dummy = node
			break
	if _dummy != null:
		_dummy.health_changed.connect(_on_dummy_health_changed)
		var dh := Damage.health_of(_dummy)
		if dh != null:
			_dummy_max_hp = dh.max_hp
			_last_hp = dh.hp
	_update_bar()

	for node in get_tree().get_nodes_in_group(&"player"):
		_player_health = Damage.health_of(node)
		if _player_health != null:
			break
	if _player_health != null:
		_player_health.damaged.connect(_on_player_changed)
		_player_health.revived.connect(_update_player_bar)
	_update_player_bar()


func _on_dummy_health_changed(current: float, maximum: float) -> void:
	if maximum > 0.0:
		_dummy_max_hp = maximum
	_last_hp = current
	_update_bar()


func _update_bar() -> void:
	var show_bar := _dummy != null and _last_hp > 0.0
	_bar_bg.visible = show_bar
	_bar_fill.visible = show_bar
	_bar_label.visible = show_bar
	if not show_bar:
		return
	var ratio := clampf(_last_hp / _dummy_max_hp, 0.0, 1.0)
	_bar_fill.size.x = TARGET_BAR_WIDTH * ratio
	_bar_label.text = "TARGET  %d" % int(ceilf(_last_hp))


func _on_player_changed(_amount: float, _source: Node, _hp: float) -> void:
	_update_player_bar()


func _update_player_bar() -> void:
	var show_bar := _player_health != null
	_player_bg.visible = show_bar
	_player_fill.visible = show_bar
	_player_label.visible = show_bar
	if not show_bar:
		return
	_player_fill.size.x = PLAYER_BAR_WIDTH * clampf(_player_health.fraction(), 0.0, 1.0)
	if _player_health.is_alive():
		_player_label.text = "DAVID  %d" % int(ceilf(_player_health.hp))
	else:
		_player_label.text = "DAVID  DOWN"

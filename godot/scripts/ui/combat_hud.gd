## Combat HUD — crosshair reticle and David's health bar.
##
## A thin CanvasLayer overlay. The bar is driven by David's `Health` child node.
class_name CombatHUD
extends CanvasLayer

const PLAYER_BAR_WIDTH := 220.0

var _player_health: Health = null

@onready var _player_bg: ColorRect = $PlayerHP/Background
@onready var _player_fill: ColorRect = $PlayerHP/Fill
@onready var _player_label: Label = $PlayerHP/Label


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		_player_health = Damage.health_of(node)
		if _player_health != null:
			break
	if _player_health != null:
		_player_health.damaged.connect(_on_player_changed)
		_player_health.revived.connect(_update_player_bar)
	_update_player_bar()


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

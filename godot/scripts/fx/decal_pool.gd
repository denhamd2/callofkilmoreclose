## Fixed ring buffer of pre-allocated Decal nodes for bullet holes, scorch marks
## and blood splashes. Forward+ only; no per-shot allocation.
extends Node

enum Kind { BULLET, SCORCH, BLOOD }

const POOL_SIZE := 64

var _decals: Array[Decal] = []
var _textures: Dictionary = {}
var _tints: Dictionary = {}
var _index := 0


func _ready() -> void:
	_textures[Kind.BULLET] = load(
		"res://assets/generated/hit_impact_frame_0.png") as Texture2D
	_textures[Kind.SCORCH] = load(
		"res://assets/generated/hit_spark_frame_0.png") as Texture2D
	_tints[Kind.BLOOD] = Color(0.55, 0.05, 0.05, 0.9)
	for i in POOL_SIZE:
		var decal := Decal.new()
		decal.name = "Decal_%d" % i
		decal.size = Vector3(0.32, 0.32, 0.32)
		decal.cull_mask = 1
		decal.visible = false
		add_child(decal)
		_decals.append(decal)


func project(kind: Kind, position: Vector3, normal: Vector3) -> void:
	if _decals.is_empty():
		return
	var decal := _decals[_index]
	_index = (_index + 1) % _decals.size()
	var tex: Texture2D = _textures.get(kind, _textures[Kind.BULLET])
	decal.texture_albedo = tex
	decal.modulate = _tints.get(kind, Color.WHITE)
	var n := normal.normalized()
	if n.length_squared() < 0.0001:
		n = Vector3.UP
	var tangent := Vector3.FORWARD
	if absf(n.dot(tangent)) > 0.92:
		tangent = Vector3.RIGHT
	var bitangent := n.cross(tangent).normalized()
	tangent = bitangent.cross(n).normalized()
	var basis := Basis(tangent, n, -bitangent)
	decal.global_transform = Transform3D(basis, position + n * 0.015)
	decal.visible = true

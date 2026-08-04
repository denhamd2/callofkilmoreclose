class_name Wheel
extends RigidBody3D

@onready var wheel_mesh: MeshInstance3D = $MeshInstance3D2
@onready var smoke: GPUParticles3D = $Smoke

var f_pos: Vector3
var f_bas: Basis
var wheel_omega: float = 0.0

var _wheel_angle: float = 0.0

func set_radius(radius: float) -> void:
	wheel_mesh.scale = Vector3.ONE * radius * 2
	#wheel_mesh.scale.y = radius * 2
	#wheel_mesh.scale.z = radius * 2

func set_mirror(mirror: bool) -> void:
	if not mirror: return
	wheel_mesh.scale.x *= -1
	wheel_mesh.scale.z *= -1

func set_pos(pos: Vector3) -> void:
	f_pos = pos

func set_bas(bas: Basis) -> void:
	f_bas = bas

func set_omega(omega: float) -> void:
	wheel_omega = omega

func _integrate_forces(state: PhysicsDirectBodyState3D):
	# too slow
	#state.transform.origin = f_pos
	var local_angular_velocity = Vector3(0.0, 0.0, wheel_omega)
	state.angular_velocity = f_bas * local_angular_velocity
	_wheel_angle += wheel_omega * state.step
	var rotated_basis = f_bas * Basis(Vector3.FORWARD, _wheel_angle)
	state.transform.basis = rotated_basis

func _physics_process(_delta: float) -> void:
	global_position = f_pos

func set_smoke_ratio(ratio: float) -> void:
	smoke.amount_ratio = clamp(ratio, 0, 1) 

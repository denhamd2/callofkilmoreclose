class_name SuspensionPogo
extends Node3D

@export var mirror_wheel: bool = false
@export var to_debug: bool = false

# ------------------------ Внутренние константы ------------------------
const HIGH_STRESS_VEL_THRESHOLD: float = 4.0
const LOAD_SMOOTH_FACTOR: float = 20000.0   # 1/с
const TWO_OVER_PI: float = 2.0 / PI
const LOW_SPEED_THRESHOLD_KMH: float = 15.0
#const FX_SMOOTH_SPEED: float = 10000
#const FY_SMOOTH_SPEED: float = 10000
const F_SMOOTH_MIN: float = 1000
const F_SMOOTH_MAX: float = 10000
const F_SMOOTH_SLOW_MULT: float = 0.5

# ------------------------ Параметры, задаваемые ChassisPogo ------------------------
var is_drive: bool
var is_steer: bool
var wheel_radius: float
var wheel_inertia: float
var rest_length: float
var stiffness: float
var damping_compression: float
var damping_relaxation: float
var static_load: float
var static_omega_threshold: float
var slip_velocity_low: float
var mu_peak: float
var load_power: float
var brake_activation_speed: float
var traction_curve: Curve
var slip_threshold: float
var sliding_friction: float
var lateral_vchar: float
var slip_factor_falloff: float
var max_load_factor: float
var slip_cutoff_threshold: float
var slip_response_rate: float
var lateral_falloff_curve: Curve
var lateral_falloff_speed_curve: Curve
var front_drift_factor_curve: Curve
var front_drift_angle_curve: Curve
var bump_stop_curve: Curve
var use_tanh_lateral: bool = false
var lateral_atan_angle_deg: float = 5.0

# ------------------------ Динамическое состояние ------------------------
var _wheel_omega: float
var _last_length: float
var _upwards_force: Vector3
var _last_Fx: float
var _last_Fy: float
var _last_Vx: float = 0.0
var _last_Vy: float = 0.0
var last_movement_sign: float = 1.0
var _current_slip: float = 0.0
var _last_lateral_factor: float = 1.0
var _current_compression: float = 0.0
var _last_smoothed_load: float

var _smooth_Fx: float = 0.0
var _smooth_Fy: float = 0.0

@onready var raycast: RayCast3D = $RayCast3D
@onready var wheel: Wheel = $Wheel

func configure(config: Dictionary) -> void:
	is_drive = config.get("is_drive", false)
	is_steer = config.get("is_steer", false)
	wheel_radius = config.get("wheel_radius", 0.6)
	wheel_inertia = config.get("wheel_inertia", 10.0)
	rest_length = config.get("rest_length", 0.4)
	stiffness = config.get("stiffness", 30000.0)
	damping_compression = config.get("damping_compression", 2500.0)
	damping_relaxation = config.get("damping_relaxation", 2800.0)
	static_load = config.get("static_load", 800.0)
	static_omega_threshold = config.get("static_omega_threshold", 0.5)
	slip_velocity_low = config.get("slip_velocity_low", 1.0)
	mu_peak = config.get("mu_peak", 1.2)
	load_power = config.get("load_power", 1.5)
	brake_activation_speed = config.get("brake_activation_speed", 0.01)
	traction_curve = config.get("traction_curve")
	slip_threshold = config.get("slip_threshold", 0.3)
	sliding_friction = config.get("sliding_friction", 2.0)
	lateral_vchar = config.get("lateral_vchar", 0.3)
	slip_factor_falloff = config.get("slip_factor_falloff", 0.2)
	max_load_factor = config.get("max_load_factor", 2.5)
	slip_cutoff_threshold = config.get("slip_cutoff_threshold", 0.7)
	slip_response_rate = config.get("slip_response_rate", 2.5)
	lateral_falloff_curve = config.get("lateral_falloff_curve")
	front_drift_factor_curve = config.get("front_drift_factor_curve")
	lateral_falloff_speed_curve = config.get("lateral_falloff_speed_curve")
	front_drift_angle_curve = config.get("front_drift_angle_curve")
	bump_stop_curve = config.get("bump_stop_curve")
	use_tanh_lateral = config.get("use_tanh_lateral", false)
	lateral_atan_angle_deg = config.get("lateral_atan_angle_deg", 5.0)
	
	_apply_initialization()

func _apply_initialization() -> void:
	if raycast:
		raycast.target_position = Vector3(0, -(rest_length + wheel_radius), 0)
	if wheel:
		wheel.set_radius(wheel_radius)
		wheel.set_mirror(mirror_wheel)
	_last_length = rest_length

func get_wheel_omega() -> float:
	return _wheel_omega

func get_last_Fx() -> float:
	return _last_Fx

func get_last_Fy() -> float:
	return _last_Fy

func get_last_Vx() -> float:
	return _last_Vx

func get_last_Vy() -> float:
	return _last_Vy

func get_wheel_radius() -> float:
	return wheel_radius

func get_last_upwards_force() -> float:
	return _upwards_force.length()

func get_static_load() -> float:
	return static_load

func get_last_lateral_factor() -> float:
	return _last_lateral_factor

func get_compression() -> float:
	return _current_compression

## Основной метод, вызываемый из ChassisPogo каждый физический кадр.
func process_physics(delta: float, drive_axle_omega: float, brake_torque: float,
		steer_angle: float, steer_input: float, car: CarPogo,
		rear_slip_angle: float = 0.0, car_speed_kmh: float = 0.0) -> void:
	raycast.force_raycast_update()
	if not raycast.is_colliding():
		_current_slip = 0.0
	update_upwards_force(car)
	_last_smoothed_load = move_toward(_last_smoothed_load, _upwards_force.length(), LOAD_SMOOTH_FACTOR * delta)
	if to_debug and is_drive:
		GuiData.set_value("smooth_load", _last_smoothed_load)
		GuiData.set_value("real_load", _upwards_force.length())
	car.apply_force(_upwards_force, global_position - car.global_position)

	var vel = _get_contact_velocity_components(car) if raycast.is_colliding() else {"Vx": 0.0, "Vy": 0.0}
	var Vx_car = vel.Vx
	var Vy_car = vel.Vy
	var point_speed: float = Lib.ms_to_kmh(Vector2(Vx_car, Vy_car).length())
	#var is_low_vx: bool = abs(Vx_car) < LOW_SPEED_THRESHOLD_KMH
	#var is_low_vy: bool = abs(Vy_car) < LOW_SPEED_THRESHOLD_KMH
	var is_low_speed: bool = point_speed < LOW_SPEED_THRESHOLD_KMH
	var smooth_factor_ratio: float = clamp(point_speed/LOW_SPEED_THRESHOLD_KMH, 0.0, 1.0)
	var smooth_factor: float = lerp(F_SMOOTH_MIN, F_SMOOTH_MAX, smooth_factor_ratio)
	#if is_low_speed != _was_low_speed:
		#_smooth_Fx = _last_Fx
		#_smooth_Fy = _last_Fy
	#_was_low_speed = is_low_speed
	
	if is_steer:
		var cos_s = cos(steer_angle)
		var sin_s = sin(steer_angle)

		var Vx_wheel =  Vx_car * cos_s + Vy_car * sin_s
		var Vy_wheel = -Vx_car * sin_s + Vy_car * cos_s
		
		_last_Vx = Vx_wheel
		_last_Vy = Vy_wheel

		# Тормозная сила
		var Fx = 0.0
		if brake_torque > 0.0 and abs(Vx_wheel) > brake_activation_speed:
			Fx = -sign(Vx_wheel) * brake_torque / wheel_radius
		car.apply_force(Fx * global_basis.x, global_position - car.global_position)

		# Боковая сила
		var Fy = 0.0
		var abs_Vx_wheel = abs(Vx_wheel)
		var slip_angle = atan2(Vy_wheel, abs_Vx_wheel)
		if to_debug:
			GuiData.set_value("slip_angle_front", rad_to_deg(slip_angle))
		var vert_load = _last_smoothed_load
		var static_ref = max(static_load, 1.0)
		var load_factor_raw = pow(vert_load / static_ref, load_power)
		var load_factor = clamp(load_factor_raw, 0.0, max_load_factor)
		var max_Fy = vert_load * mu_peak * load_factor
		
		var loss_factor = 1.0
		if front_drift_angle_curve and Vx_car > 0:
			var abs_angle = abs(rear_slip_angle)
			var base_loss = front_drift_angle_curve.sample(abs_angle)
			var speed_scale = 1.0
			if lateral_falloff_speed_curve:
				speed_scale = lateral_falloff_speed_curve.sample(car_speed_kmh)
			#if sign(rear_slip_angle) != sign(steer_angle):
			#	base_loss *= (1.0 - abs(steer_input) * 0.5)
			loss_factor -= base_loss * speed_scale
			max_Fy *= loss_factor
			if to_debug:
				GuiData.set_value("loss_factor", loss_factor)
		
		if Vx_car < 0:
			max_Fy *= 0.6
		
		if use_tanh_lateral: #or abs(Vx_car) < 1:
			Fy = -max_Fy * tanh(Vy_wheel / lateral_vchar)
		else:
			var slip_angle_norm = slip_angle / deg_to_rad(lateral_atan_angle_deg)
			Fy = -max_Fy * TWO_OVER_PI * atan(slip_angle_norm * PI/2.0)
		
		if sign(rear_slip_angle) == sign(steer_angle) and loss_factor < 0.9:
			Fy *= (1.0 - abs(steer_input) * 1.0)
		
		#_smooth_Fy = Fy
		if is_low_speed:
			_smooth_Fy = _smooth_low_speed_force(_smooth_Fy, Fy, smooth_factor, smooth_factor_ratio)
		
		var applied_Fy = _smooth_Fy if is_low_speed else Fy
		var lateral_dir = -global_basis.x * sin_s + global_basis.z * cos_s
		car.apply_force(applied_Fy * lateral_dir, global_position - car.global_position)
		#DebugDraw3D.draw_arrow_ray(global_position, applied_Fy*global_basis.z, 0.0005, Color.CRIMSON, 0.05)
		
		_wheel_omega = Vx_wheel / wheel_radius
		_last_Fx = Fx
		_last_Fy = applied_Fy
	else:
		_last_Vx = Vx_car
		_last_Vy = Vy_car
		
		var target_slip = _compute_slip(drive_axle_omega if is_drive else _wheel_omega, Vx_car)
		if _upwards_force != Vector3.ZERO:
			wheel.set_smoke_ratio(abs(target_slip)/6.0 - 0.2)
		target_slip = clamp(target_slip, -3.0, 3.0)
		
		_current_slip += (target_slip - _current_slip) * clamp(slip_response_rate * delta, 0.0, 1.0)
		if abs(_current_slip - target_slip) < 0.001:
			_current_slip = target_slip
			GuiData.set_value("current_slip", _current_slip)
		
		var raw_Fx = 0.0
		if is_drive:
			raw_Fx = _compute_longitudinal_force(target_slip)
		
		if to_debug:
			GuiData.set_value("raw_fx", raw_Fx)
		
		var applied_Fx: float
		if is_drive and is_low_speed:
			_smooth_Fx = _smooth_low_speed_force(_smooth_Fx, raw_Fx, smooth_factor, smooth_factor_ratio)
			applied_Fx = _smooth_Fx
		else:
			applied_Fx = raw_Fx
			#if is_drive:
			#	_smooth_Fx = raw_Fx

		car.apply_force(applied_Fx * global_basis.x, global_position - car.global_position)

		# Боковая сила с учётом продольного скольжения
		var Fy = 0.0
		var vert_load = _last_smoothed_load
		var stat_ref = max(static_load, 1.0)
		var rear_load_factor = clamp(pow(vert_load / stat_ref, load_power), 0.0, max_load_factor)
		
		var lateral_factor = lateral_falloff_curve.sample(clamp(abs(_current_slip), 0.0, 3.0)) if lateral_falloff_curve else 1.0
		if lateral_falloff_speed_curve:
			var axle_speed = abs(drive_axle_omega if is_drive else _wheel_omega) * wheel_radius
			var speed_blend = lateral_falloff_speed_curve.sample(Lib.ms_to_kmh(axle_speed))
			lateral_factor = lerp(1.0, lateral_factor, speed_blend)
		_last_lateral_factor = lateral_factor
		
		if Vx_car < 0:
			lateral_factor = 1.0
		var max_Fy = vert_load * mu_peak * rear_load_factor * lateral_factor
		if use_tanh_lateral:# or abs(Vx_car) < 1:
			Fy = -max_Fy * tanh(Vy_car / lateral_vchar)
		else:
			var slip_angle = atan2(Vy_car, abs(Vx_car))
			var slip_angle_norm = slip_angle / deg_to_rad(lateral_atan_angle_deg)
			Fy = -max_Fy * TWO_OVER_PI * atan(slip_angle_norm * PI/2.0)
		
		Fy = clamp(Fy, -max_Fy, max_Fy)
		
		if to_debug: GuiData.set_value("raw_fy", Fy)
		
		var applied_Fy_local: float
		if is_low_speed:
			_smooth_Fy = _smooth_low_speed_force(_smooth_Fy, Fy, smooth_factor, smooth_factor_ratio)
			applied_Fy_local = _smooth_Fy
		else:
			applied_Fy_local = Fy
			#_smooth_Fy = Fy

		car.apply_force(applied_Fy_local * global_basis.z, global_position - car.global_position)
		#DebugDraw3D.draw_arrow_ray(global_position, applied_Fy_local*global_basis.z, 0.0005, Color.CRIMSON, 0.05)
		
		if not is_drive:
			_process_free_wheel_dynamics(delta, applied_Fx, brake_torque)
		
		_last_Fx = applied_Fx
		_last_Fy = applied_Fy_local
		
		if to_debug:
			GuiData.set_value("smooth_fx", _last_Fx)
			GuiData.set_value("smooth_fy", _last_Fy)
		
		#print("low vx: %s, low vy: %s" % [is_low_vx, is_low_vy])
	update_wheel_visual(drive_axle_omega, steer_angle)

func _smooth_low_speed_force(current_force: float, target_force: float,
		smooth_factor: float, smooth_factor_ratio: float) -> float:
	var slow_factor = smooth_factor * F_SMOOTH_SLOW_MULT
	var is_force_growing = abs(target_force) > abs(current_force)
	var grow_factor = lerp(slow_factor, smooth_factor, smooth_factor_ratio)
	var fall_factor = lerp(smooth_factor, slow_factor, smooth_factor_ratio)
	return move_toward(current_force, target_force, grow_factor if is_force_growing else fall_factor)

func update_upwards_force(car: CarPogo) -> void:
	if raycast.is_colliding() and not car.airborne:
		raycast.target_position.y = -(rest_length + wheel_radius)
		var hit_point := raycast.get_collision_point()
		var normal := raycast.get_collision_normal()
		var current_length = hit_point.distance_to(global_position) - wheel_radius
		current_length = clamp(current_length, 0.0, rest_length)
		var compression = rest_length - current_length
		compression *= normal.dot(global_transform.basis.y)
		_current_compression = compression
		var spring_force = compression * stiffness
		var relative_vel = (current_length - _last_length) * Engine.physics_ticks_per_second / Engine.time_scale
		if relative_vel > HIGH_STRESS_VEL_THRESHOLD:
			_last_length = current_length
			_upwards_force = Vector3.ZERO
			return
		var spring_damp_force: float
		if relative_vel < 0:
			spring_damp_force = damping_compression * relative_vel
		else:
			spring_damp_force = damping_relaxation * relative_vel
		var susp_force = spring_force - spring_damp_force
		susp_force = clamp(susp_force, 0.0, INF)
		_last_length = current_length
		_upwards_force = normal * susp_force
	else:
		_last_length = rest_length
		_upwards_force = Vector3.ZERO

## Определяет экстремальные нагрузки (high_stress) и отрыв колёс (airborne).
func is_freaking(car: CarPogo) -> void:
	raycast.force_raycast_update()
	if not raycast.is_colliding():
		car.high_stress = true
		car.airborne = true
		return
	raycast.target_position.y = -(rest_length + wheel_radius)
	var hit_point := raycast.get_collision_point()
	var current_length = hit_point.distance_to(global_position) - wheel_radius
	var relative_vel = (current_length - _last_length) * Engine.physics_ticks_per_second / Engine.time_scale
	if relative_vel < -HIGH_STRESS_VEL_THRESHOLD:
		car.high_stress = true

## Возвращает компоненты скорости точки контакта (Vx – вдоль колеса, Vy – поперёк) в глобальной системе.
func _get_contact_velocity_components(car: CarPogo) -> Dictionary:
	if not raycast.is_colliding():
		return {"Vx": 0.0, "Vy": 0.0}
	var hit_point = raycast.get_collision_point()
	var normal = raycast.get_collision_normal()
	var rel_vel = car.get_point_velocity(hit_point)
	var proj = rel_vel - rel_vel.project(normal)
	return {"Vx": proj.dot(global_basis.x), "Vy": proj.dot(global_basis.z)}

func _compute_slip(omega: float, Vx: float) -> float:
	return (omega * wheel_radius - Vx) / max(abs(Vx), slip_velocity_low)

func _compute_longitudinal_force(slip: float) -> float:
	var clamped_slip = clamp(slip, -3.0, 3.0)
	if to_debug:
		GuiData.set_value("rear_ratio", clamped_slip)
	var n_traction = traction_curve.sample(clamped_slip) if traction_curve else 0.0
	var Fx = _upwards_force.length() * n_traction * sliding_friction
	#car.apply_force(Fx * global_basis.x, global_position - car.global_position)
	return Fx

func _process_free_wheel_dynamics(delta: float, Fx: float, brake_torque: float) -> void:
	var wheel_torque = -Fx * wheel_radius
	var omega_old = _wheel_omega
	if abs(omega_old) < static_omega_threshold and brake_torque > 0.0:
		if abs(wheel_torque) <= brake_torque:
			_wheel_omega = 0.0
			return
		else:
			var net_torque = wheel_torque - sign(wheel_torque) * brake_torque
			_wheel_omega += net_torque * delta / wheel_inertia
	else:
		var signed_brake = -sign(_wheel_omega) * brake_torque
		_wheel_omega += (wheel_torque + signed_brake) * delta / wheel_inertia

	if brake_torque > 0.0 and omega_old * _wheel_omega < 0.0:
		if abs(wheel_torque) <= brake_torque:
			_wheel_omega = 0.0

func update_wheel_visual(drive_axle_omega: float, steer_angle: float) -> void:
	var omega = drive_axle_omega if is_drive else _wheel_omega
	wheel.set_omega(omega)
	if is_steer:
		var up = global_transform.basis.y
		var forward = global_transform.basis.z.rotated(up, clamp(-(steer_angle*4), -PI/4, PI/4))
		var right = up.cross(forward).normalized()
		wheel.set_bas(Basis(right, up, forward))
	else:
		wheel.set_bas(global_transform.basis)
	if raycast.is_colliding():
		var hit_point = raycast.get_collision_point()
		var current_length = hit_point.distance_to(global_position) - wheel_radius
		wheel.set_pos(-global_transform.basis.y * current_length + global_position)
	else:
		wheel.set_pos(-global_transform.basis.y * rest_length + global_position)

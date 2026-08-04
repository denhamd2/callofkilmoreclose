## Static overcast daytime Sky3D preset for Kilmore Close.
extends Sky3D


func _enter_tree() -> void:
	game_time_enabled = false
	editor_time_enabled = false
	pause()
	current_time = 12.0
	sun_energy = 1.08
	sun_shadow_opacity = 0.72
	ambient_energy = 1.38
	sky_contribution = 0.85
	tonemap_exposure = 1.0
	cloud_intensity = 0.55
	if sky != null:
		sky.cumulus_coverage = 0.72
		sky.cumulus_intensity = 0.55
		sky.atm_sun_intensity = 1.0
	if sun != null:
		sun.shadow_enabled = true

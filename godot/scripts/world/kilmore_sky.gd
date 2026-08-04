## Static overcast daytime Sky3D preset for Kilmore Close.
##
## This file is the whole look of the game. `scenes/sky_kilmore.tscn` carries no
## Environment resource and the project sets no default_environment, so Sky3D
## builds the Environment at runtime in `_initialize()` (fired from
## NOTIFICATION_SCENE_INSTANTIATED, i.e. before our `_enter_tree`). Every
## post-processing decision therefore has to be made here, in code, against that
## runtime object rather than authored in the inspector.
##
## Time never advances: one fixed midday sun, no day/night, no weather. A moving
## sun means you can never tell whether a change improved the work or just caught
## better light.
extends Sky3D

## Sun elevation is fixed, so the shadow cascade only has to cover the depth a
## street-level camera can actually resolve. 120 m over four splits keeps the
## 4096 map dense on the near facades instead of spreading it over 275 m of road.
const SHADOW_RANGE := 120.0


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

	# Sky3D draws its own atmospheric fog as a screen-space quad reading
	# DEPTH_TEXTURE (SkyDome's AtmFog shader). Godot's volumetric fog, enabled
	# below, covers the same ground and additionally receives sun shafts and GI,
	# so running both would double the haze.
	fog_enabled = false

	if sky != null:
		sky.cumulus_coverage = 0.72
		sky.cumulus_intensity = 0.55
		sky.atm_sun_intensity = 1.0

	_grade_sun()
	_grade_environment()


func _grade_sun() -> void:
	if sun == null:
		return
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = SHADOW_RANGE
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	# The street is full of thin boxes — 0.06 m wall coping, 0.03 m overhead
	# wires, window mullions. At 4096 the default bias detaches their shadows
	# ("peter-panning"); a low constant bias plus normal bias keeps contact.
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.4
	sun.shadow_transmittance_bias = 0.05


func _grade_environment() -> void:
	var env := environment
	if env == null:
		return

	# AgX rolls highlights off far more gracefully than ACES, which was blowing
	# the pebbledash and the white render to pure white in overcast daylight.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0

	# Contact occlusion. This is what stops the street reading as decals painted
	# on a flat plane: darkening where kerb meets road, bin meets wall, shrub
	# meets soil. Cheap and the single biggest perceptual gain of the switch.
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssao_power = 1.5
	env.ssao_light_affect = 0.1
	env.ssao_ao_channel_affect = 0.0

	# Indirect bounce. Overcast light is almost entirely ambient, so colour
	# bleeding between road, render and grass does most of the atmosphere here.
	env.ssil_enabled = not ProfileToggles.has(&"no_ssil")
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.0
	env.ssil_sharpness = 0.98

	# Damp tarmac and glazing. Phase G turns the window panes transparent and
	# drops tarmac roughness, at which point this starts carrying real weight.
	env.ssr_enabled = true
	env.ssr_max_steps = 32
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Aerial perspective down a 275 m street, and the reason the far end no
	# longer terminates in a hard edge against the sky. Density is deliberately
	# low: at 0.008 over 120 m the mid-street washed out to flat grey and the far
	# houses disappeared, which reads as a bug rather than as weather.
	env.volumetric_fog_enabled = not ProfileToggles.has(&"no_volumetric")
	env.volumetric_fog_density = 0.0022
	env.volumetric_fog_albedo = Color(0.76, 0.79, 0.83)
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_ambient_inject = 0.3

	# SDFGI voxelizes the MultiMesh street on first use (~1–2 fps steady-state plus a
	# cold-start hitch). Kept on for the overcast atmospheric fill; bisect flags
	# live in `profile_toggles.gd` if it needs turning off again.
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.5
	env.sdfgi_energy = 1.0

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 0.95
	env.adjustment_brightness = 1.0

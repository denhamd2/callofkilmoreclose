## Command-line toggles for windowed `--profile` bisects.
##
## Usage (combine with `--profile`):
##   --profile-no-ai        skip cast roaming + CombatBrain
##   --profile-no-sdfgi     disable SDFGI in kilmore_sky
##   --profile-no-contacts  skip car pedestrian impact polling
##   --profile-sight-30     roll SIGHT_RANGE back to 30 m
##   --profile-nav-coarse   nav cell_size 0.25 instead of 0.15
class_name ProfileToggles
extends RefCounted

static var _parsed := false
static var no_ai := false
static var no_sdfgi := false
static var no_contacts := false
static var sight_30 := false
static var nav_coarse := false
static var no_ssil := false
static var no_volumetric := false


static func _parse() -> void:
	if _parsed:
		return
	_parsed = true
	var args := OS.get_cmdline_user_args()
	no_ai = args.has("--profile-no-ai")
	no_sdfgi = args.has("--profile-no-sdfgi")
	no_contacts = args.has("--profile-no-contacts")
	sight_30 = args.has("--profile-sight-30")
	nav_coarse = args.has("--profile-nav-coarse")
	no_volumetric = args.has("--profile-no-volumetric")
	no_ssil = args.has("--profile-no-ssil")


static func has(flag: StringName) -> bool:
	_parse()
	match flag:
		&"no_ai":
			return no_ai
		&"no_sdfgi":
			return no_sdfgi
		&"no_contacts":
			return no_contacts
		&"sight_30":
			return sight_30
		&"nav_coarse":
			return nav_coarse
		&"no_ssil":
			return no_ssil
		&"no_volumetric":
			return no_volumetric
	return false

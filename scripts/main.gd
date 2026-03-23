extends Node3D

@export var cycle_duration := 180.0  # seconds for a full day/night cycle

@onready var terrain: Node3D = $Terrain
@onready var player: CharacterBody3D = $Player
@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var env: WorldEnvironment = $WorldEnvironment
@onready var fog_mesh: MeshInstance3D = $Fog
@onready var water: MeshInstance3D = $Water
@onready var scatter: Node3D = $Scatter

var _time_of_day := 0.25  # Start at sunrise (0=midnight, 0.25=sunrise, 0.5=noon, 0.75=sunset)
var _player_speed_smooth := 0.0

# Gerstner wave parameters — must match water.gdshader exactly
const WAVE_DIRS: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.7, 0.7), Vector2(0.3, 1.0), Vector2(-0.5, 0.8)]
const WAVE_AMPS: Array[float] = [0.35, 0.20, 0.15, 0.10]
const WAVE_FREQS: Array[float] = [0.8, 1.2, 1.8, 2.5]
const WAVE_SPEEDS: Array[float] = [1.0, 1.3, 0.9, 1.5]

var _water_base_y := 0.0
var _game_time := 0.0
var _underwater_blend := 0.0

func _water_height_at(x: float, z: float) -> float:
	var h := _water_base_y
	for i in WAVE_DIRS.size():
		var dir := WAVE_DIRS[i].normalized()
		var phase := WAVE_FREQS[i] * (dir.x * x + dir.y * z) + _game_time * WAVE_SPEEDS[i]
		h += WAVE_AMPS[i] * sin(phase)
	return h

# Day palette
const DAY_SKY_TOP := Color(0.66, 0.85, 0.92)
const DAY_HORIZON := Color(0.91, 0.96, 0.94)
const DAY_FOG := Color(0.75, 0.88, 0.92)
const DAY_SUN := Color(1.0, 0.96, 0.9)
const DAY_SUN_ENERGY := 1.5
const DAY_AMBIENT := 0.5

# Sunset palette
const SUNSET_SKY_TOP := Color(0.4, 0.35, 0.55)
const SUNSET_HORIZON := Color(0.95, 0.6, 0.4)
const SUNSET_FOG := Color(0.90, 0.60, 0.40)
const SUNSET_SUN := Color(1.0, 0.7, 0.4)
const SUNSET_SUN_ENERGY := 0.9

# Night palette
const NIGHT_SKY_TOP := Color(0.08, 0.1, 0.2)
const NIGHT_HORIZON := Color(0.12, 0.15, 0.25)
const NIGHT_FOG := Color(0.06, 0.08, 0.18)
const NIGHT_SUN := Color(0.6, 0.7, 0.9)
const NIGHT_SUN_ENERGY := 0.08
const NIGHT_AMBIENT := 0.06

func _ready() -> void:
	player.global_position = Vector3(0, terrain.get_height_at(0, 0) + 3.0, 0)
	_water_base_y = $Water.global_position.y
	scatter.generate(terrain, $Water.global_position.y)

func _process(delta: float) -> void:
	_time_of_day += delta / cycle_duration
	if _time_of_day > 1.0:
		_time_of_day -= 1.0

	_game_time += delta
	player.water_y = _water_height_at(player.global_position.x, player.global_position.z)

	# Sun rotation — full circle over the cycle
	var sun_angle := _time_of_day * TAU - PI / 2.0
	sun.rotation.x = sun_angle

	# Blend factor: 0 = full night, 1 = full day
	# Day is roughly 0.2–0.8, night is 0.0–0.2 and 0.8–1.0
	var day_factor := 0.0
	var sunset_factor := 0.0

	if _time_of_day > 0.2 and _time_of_day < 0.3:
		# Sunrise
		day_factor = smoothstep(0.2, 0.3, _time_of_day)
		sunset_factor = sin(day_factor * PI)  # Peaks mid-transition
	elif _time_of_day >= 0.3 and _time_of_day <= 0.7:
		# Full day
		day_factor = 1.0
	elif _time_of_day > 0.7 and _time_of_day < 0.8:
		# Sunset
		day_factor = 1.0 - smoothstep(0.7, 0.8, _time_of_day)
		sunset_factor = sin(day_factor * PI)
	else:
		# Night
		day_factor = 0.0

	# Blend sky colors
	var sky_mat: ProceduralSkyMaterial = env.environment.sky.sky_material
	var sky_top := NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, day_factor)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, day_factor)
	# Mix in sunset warmth
	sky_top = sky_top.lerp(SUNSET_SKY_TOP, sunset_factor * 0.6)
	horizon = horizon.lerp(SUNSET_HORIZON, sunset_factor * 0.8)

	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = sky_top

	# Fog
	var fog_color := NIGHT_FOG.lerp(DAY_FOG, day_factor)
	fog_color = fog_color.lerp(SUNSET_FOG, sunset_factor * 0.7)
	env.environment.fog_light_color = fog_color

	# Underwater detection
	var cam_pos: Vector3 = $Player/CameraPivot/Camera3D.global_position
	var cam_water_y: float = _water_height_at(cam_pos.x, cam_pos.z)
	var target_blend := 1.0 if cam_pos.y < cam_water_y else 0.0
	_underwater_blend = lerpf(_underwater_blend, target_blend, 1.0 - exp(-delta * 8.0))

	# Underwater fog/ambient override
	if _underwater_blend > 0.01:
		var underwater_fog := Color(0.05, 0.18, 0.25)
		fog_color = fog_color.lerp(underwater_fog, _underwater_blend)
		env.environment.fog_light_color = fog_color
		env.environment.fog_density = lerpf(0.003, 0.05, _underwater_blend)
		var underwater_ambient := Color(0.15, 0.35, 0.45)
		env.environment.ambient_light_color = Color.WHITE.lerp(underwater_ambient, _underwater_blend)
	else:
		env.environment.fog_density = 0.003
		env.environment.ambient_light_color = Color.WHITE

	# Caustic uniform on terrain shader
	var terrain_mesh: MeshInstance3D = terrain.get_node("MeshInstance3D")
	var terrain_mat: ShaderMaterial = terrain_mesh.material_override
	if terrain_mat:
		terrain_mat.set_shader_parameter("caustic_strength", _underwater_blend)
		terrain_mat.set_shader_parameter("water_y_uniform", _water_base_y)

	# Volumetric fog plane — sync color with environment fog
	var fog_mat: ShaderMaterial = fog_mesh.material_override
	if fog_mat:
		var vol_fog_alpha := lerpf(0.7, 0.6, day_factor)  # Denser at night
		fog_mat.set_shader_parameter("fog_color", Color(fog_color.r, fog_color.g, fog_color.b, vol_fog_alpha))

	# Water shader — player ripples and foam
	var water_mat: ShaderMaterial = water.material_override
	if water_mat:
		water_mat.set_shader_parameter("player_xz", Vector2(player.global_position.x, player.global_position.z))
		var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
		water_mat.set_shader_parameter("player_speed", h_speed)
		# Smooth speed for foam fade-out (~2 second decay)
		_player_speed_smooth = lerpf(_player_speed_smooth, h_speed, 1.0 - exp(-delta * 1.5))
		water_mat.set_shader_parameter("player_speed_smooth", _player_speed_smooth)
		# Day/night tint from fog palette
		water_mat.set_shader_parameter("water_effect_tint", fog_color)

	# Scatter — day/night sync
	scatter.update_day_factor(day_factor)

	# Sun light
	var sun_color := NIGHT_SUN.lerp(DAY_SUN, day_factor)
	sun_color = sun_color.lerp(SUNSET_SUN, sunset_factor * 0.8)
	sun.light_color = sun_color
	sun.light_energy = lerpf(NIGHT_SUN_ENERGY, DAY_SUN_ENERGY, day_factor)

	# Ambient
	env.environment.ambient_light_energy = lerpf(NIGHT_AMBIENT, DAY_AMBIENT, day_factor)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate"):
		var new_seed := randf() * 1000.0
		terrain.set_seed(new_seed)
		player.global_position = Vector3(0, terrain.get_height_at(0, 0) + 3.0, 0)
		player.velocity = Vector3.ZERO
		scatter.regenerate(terrain, $Water.global_position.y)

static func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

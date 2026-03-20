extends Node3D

const GRID_SIZE := 128
const TERRAIN_SIZE := 120.0
const HEIGHT_SCALE := 12.0
const ISLAND_RADIUS := 55.0
const NOISE_SCALE := 0.05

@onready var mesh: MeshInstance3D = $MeshInstance3D

var _collision_body: StaticBody3D
var _current_seed: float = 0.0
var _noise: FastNoiseLite
var _noise2: FastNoiseLite

func _ready() -> void:
	_setup_noise()
	_build_collision()

func set_seed(new_seed: float) -> void:
	_current_seed = new_seed
	mesh.material_override.set_shader_parameter("seed", new_seed)
	_build_collision()

func _setup_noise() -> void:
	# Fixed seed — we mirror the shader's coordinate-offset approach.
	# Shader: pos * noise_scale + vec2(seed, seed)
	# CPU:    wx * NOISE_SCALE + _current_seed
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = 0
	_noise.frequency = 1.0
	_noise2 = FastNoiseLite.new()
	_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise2.seed = 0
	_noise2.frequency = 1.0

func _sample_height(wx: float, wz: float) -> float:
	var px := wx * NOISE_SCALE + _current_seed
	var pz := wz * NOISE_SCALE + _current_seed
	var h := _noise.get_noise_2d(px, pz) * 0.6 \
	       + _noise2.get_noise_2d(px * 2.0 + 43.0, pz * 2.0 + 17.0) * 0.4
	var dist := sqrt(wx * wx + wz * wz) / ISLAND_RADIUS
	var falloff := 1.0 - smoothstep(0.5, 1.0, dist)
	return h * HEIGHT_SCALE * falloff

func _build_collision() -> void:
	if _collision_body:
		_collision_body.queue_free()

	var map_data := PackedFloat32Array()
	map_data.resize((GRID_SIZE + 1) * (GRID_SIZE + 1))
	var half := TERRAIN_SIZE / 2.0
	var step := TERRAIN_SIZE / float(GRID_SIZE)

	for z in range(GRID_SIZE + 1):
		for x in range(GRID_SIZE + 1):
			var wx := -half + x * step
			var wz := -half + z * step
			map_data[z * (GRID_SIZE + 1) + x] = _sample_height(wx, wz)

	var shape := HeightMapShape3D.new()
	shape.map_width = GRID_SIZE + 1
	shape.map_depth = GRID_SIZE + 1
	shape.map_data = map_data

	_collision_body = StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	_collision_body.add_child(col)
	add_child(_collision_body)
	_collision_body.scale = Vector3(TERRAIN_SIZE / float(GRID_SIZE), 1.0, TERRAIN_SIZE / float(GRID_SIZE))

func get_height_at(world_x: float, world_z: float) -> float:
	return _sample_height(world_x, world_z)

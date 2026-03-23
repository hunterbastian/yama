extends Node3D

const ISLAND_RADIUS := 55.0
const MEADOW_RADIUS := 15.0
const TREE_GRID_SPACING := 5.0
const ROCK_GRID_SPACING := 9.0
const JITTER := 2.0
const GRASS_GRID_SPACING := 1.5
const GRASS_JITTER := 0.7

# 4 MMIs for tree parts (trunk + 3 canopy layers) — same transforms, different meshes
@onready var tree_trunk_mmi: MultiMeshInstance3D = $TreeTrunk
@onready var tree_canopy1_mmi: MultiMeshInstance3D = $TreeCanopy1
@onready var tree_canopy2_mmi: MultiMeshInstance3D = $TreeCanopy2
@onready var tree_canopy3_mmi: MultiMeshInstance3D = $TreeCanopy3
@onready var rock_mmi: MultiMeshInstance3D = $RockMesh
@onready var grass_mmi: MultiMeshInstance3D = $GrassMesh

var _tree_mmis: Array[MultiMeshInstance3D]
var _tree_scene: PackedScene
var _rock_scene: PackedScene
var _grass_mesh: PlaneMesh

func _ready() -> void:
	_tree_scene = load("res://scenes/tree.tscn")
	_rock_scene = load("res://scenes/rock.tscn")
	_tree_mmis = [tree_trunk_mmi, tree_canopy1_mmi, tree_canopy2_mmi, tree_canopy3_mmi]
	_grass_mesh = PlaneMesh.new()
	_grass_mesh.size = Vector2(0.06, 0.4)
	_grass_mesh.orientation = PlaneMesh.FACE_Z


func generate(terrain: Node3D, water_y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(terrain.get_seed()) + 100

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = int(terrain.get_seed()) + 200
	noise.frequency = 0.08

	_generate_trees(terrain, water_y, rng, noise)
	_generate_rocks(terrain, water_y, rng, noise)
	_generate_grass(terrain, water_y)


func regenerate(terrain: Node3D, water_y: float) -> void:
	# Free all collision bodies
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	# Clear all MultiMesh instances
	for mmi in _tree_mmis:
		if mmi.multimesh:
			mmi.multimesh.instance_count = 0
	if rock_mmi.multimesh:
		rock_mmi.multimesh.instance_count = 0
	if grass_mmi.multimesh:
		grass_mmi.multimesh.instance_count = 0
	# Wait one frame for queue_free to process, then regenerate
	# Note: this makes regenerate() async — caller does not need to await
	await get_tree().process_frame
	generate(terrain, water_y)


func update_day_factor(day_factor: float) -> void:
	for mmi in _tree_mmis:
		if mmi.material_override:
			mmi.material_override.set_shader_parameter("day_factor", day_factor)
	if rock_mmi.material_override:
		rock_mmi.material_override.set_shader_parameter("day_factor", day_factor)
	if grass_mmi.material_override:
		grass_mmi.material_override.set_shader_parameter("day_factor", day_factor)


func _get_terrain_normal(terrain: Node3D, x: float, z: float) -> Vector3:
	var eps := 0.5
	var hL: float = terrain.get_height_at(x - eps, z)
	var hR: float = terrain.get_height_at(x + eps, z)
	var hD: float = terrain.get_height_at(x, z - eps)
	var hU: float = terrain.get_height_at(x, z + eps)
	return Vector3(hL - hR, 1.0, hD - hU).normalized()


func _generate_trees(terrain: Node3D, water_y: float, rng: RandomNumberGenerator, noise: FastNoiseLite) -> void:
	var transforms: Array[Transform3D] = []
	var half := ISLAND_RADIUS

	var x := -half
	while x < half:
		var z := -half
		while z < half:
			var jx := x + rng.randf_range(-JITTER, JITTER)
			var jz := z + rng.randf_range(-JITTER, JITTER)

			# Noise gate — skip ~40% of candidates for natural clusters
			var n := noise.get_noise_2d(jx * 0.15, jz * 0.15)
			if n < -0.1:
				z += TREE_GRID_SPACING
				continue

			var dist := sqrt(jx * jx + jz * jz)

			# Filter: island edge
			if dist > ISLAND_RADIUS * 0.85:
				z += TREE_GRID_SPACING
				continue

			# Filter: meadow center (trees stay outside meadow + 5 unit buffer)
			if dist < MEADOW_RADIUS + 5.0:
				z += TREE_GRID_SPACING
				continue

			var height: float = terrain.get_height_at(jx, jz)

			# Filter: below water
			if height < water_y:
				z += TREE_GRID_SPACING
				continue

			# Filter: steep slopes
			var normal := _get_terrain_normal(terrain, jx, jz)
			if normal.y < 0.7:
				z += TREE_GRID_SPACING
				continue

			# Size variant based on height
			var scale_val := 1.0
			if height < 3.0:
				scale_val = rng.randf_range(0.6, 0.8)
			elif height < 7.0:
				scale_val = rng.randf_range(1.0, 1.2)
			else:
				scale_val = rng.randf_range(1.4, 1.8)

			var rot_y := rng.randf_range(0.0, TAU)
			var basis := Basis(Vector3.UP, rot_y).scaled(Vector3(scale_val, scale_val, scale_val))
			var origin := Vector3(jx, height, jz)
			transforms.append(Transform3D(basis, origin))

			z += TREE_GRID_SPACING
		x += TREE_GRID_SPACING

	# Write same transforms to all 4 tree part MMIs — each renders a different mesh/material
	var tree_instance := _tree_scene.instantiate()
	var part_index := 0
	for child in tree_instance.get_children():
		if child is MeshInstance3D and part_index < _tree_mmis.size():
			_write_multimesh(_tree_mmis[part_index], child.mesh, child.transform, transforms)
			part_index += 1
	tree_instance.queue_free()

	# Spawn collision bodies
	for t in transforms:
		_spawn_tree_collision(t)


func _generate_rocks(terrain: Node3D, water_y: float, rng: RandomNumberGenerator, noise: FastNoiseLite) -> void:
	var transforms: Array[Transform3D] = []
	var half := ISLAND_RADIUS

	var x := -half
	while x < half:
		var z := -half
		while z < half:
			var jx := x + rng.randf_range(-JITTER, JITTER)
			var jz := z + rng.randf_range(-JITTER, JITTER)

			# Noise gate — different frequency for rocks
			var n := noise.get_noise_2d(jx * 0.25, jz * 0.25)
			if n < 0.1:
				z += ROCK_GRID_SPACING
				continue

			var dist := sqrt(jx * jx + jz * jz)

			# Filter: island edge
			if dist > ISLAND_RADIUS * 0.85:
				z += ROCK_GRID_SPACING
				continue

			# Filter: innermost center only
			if dist < 10.0:
				z += ROCK_GRID_SPACING
				continue

			var height: float = terrain.get_height_at(jx, jz)

			# Filter: below water
			if height < water_y:
				z += ROCK_GRID_SPACING
				continue

			# Filter: very steep slopes
			var normal := _get_terrain_normal(terrain, jx, jz)
			if normal.y < 0.5:
				z += ROCK_GRID_SPACING
				continue

			var scale_val := rng.randf_range(0.3, 1.0)
			var rot_y := rng.randf_range(0.0, TAU)
			# Non-uniform scale for natural look
			var sx := scale_val * rng.randf_range(0.8, 1.2)
			var sy := scale_val * rng.randf_range(0.5, 0.8)
			var sz := scale_val * rng.randf_range(0.8, 1.2)
			var basis := Basis(Vector3.UP, rot_y).scaled(Vector3(sx, sy, sz))
			var origin := Vector3(jx, height, jz)
			transforms.append(Transform3D(basis, origin))

			z += ROCK_GRID_SPACING
		x += ROCK_GRID_SPACING

	var rock_instance := _rock_scene.instantiate()
	for child in rock_instance.get_children():
		if child is MeshInstance3D:
			_write_multimesh(rock_mmi, child.mesh, child.transform, transforms)
			break
	rock_instance.queue_free()

	for t in transforms:
		_spawn_rock_collision(t)


func _generate_grass(terrain: Node3D, water_y: float) -> void:
	var grass_rng := RandomNumberGenerator.new()
	grass_rng.seed = int(terrain.get_seed()) + 300

	var grass_noise := FastNoiseLite.new()
	grass_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grass_noise.seed = int(terrain.get_seed()) + 400
	grass_noise.frequency = 0.12

	var transforms: Array[Transform3D] = []
	var half := ISLAND_RADIUS

	var x := -half
	while x < half:
		var z := -half
		while z < half:
			var jx := x + grass_rng.randf_range(-GRASS_JITTER, GRASS_JITTER)
			var jz := z + grass_rng.randf_range(-GRASS_JITTER, GRASS_JITTER)

			var dist := sqrt(jx * jx + jz * jz)

			# Filter: island edge
			if dist > ISLAND_RADIUS * 0.75:
				z += GRASS_GRID_SPACING
				continue

			# Density thinning beyond meadow
			var noise_threshold := -0.2
			if dist > MEADOW_RADIUS:
				noise_threshold = lerpf(-0.2, 0.3, (dist - MEADOW_RADIUS) / 10.0)

			var n := grass_noise.get_noise_2d(jx * 0.2, jz * 0.2)
			if n < noise_threshold:
				z += GRASS_GRID_SPACING
				continue

			var height: float = terrain.get_height_at(jx, jz)

			# Filter: below water
			if height < water_y:
				z += GRASS_GRID_SPACING
				continue

			# Filter: steep slopes
			var normal := _get_terrain_normal(terrain, jx, jz)
			if normal.y < 0.8:
				z += GRASS_GRID_SPACING
				continue

			# Random scale, rotation, tilt
			var scale_y := grass_rng.randf_range(0.6, 1.6)
			var rot_y := grass_rng.randf_range(0.0, TAU)
			var tilt_x := grass_rng.randf_range(-0.25, 0.25)
			var tilt_z := grass_rng.randf_range(-0.25, 0.25)

			var basis := Basis.IDENTITY
			basis = basis.rotated(Vector3.UP, rot_y)
			basis = basis.rotated(Vector3.RIGHT, tilt_x)
			basis = basis.rotated(Vector3.FORWARD, tilt_z)
			basis = basis.scaled(Vector3(1.0, scale_y, 1.0))

			var origin := Vector3(jx, height, jz)
			transforms.append(Transform3D(basis, origin))

			z += GRASS_GRID_SPACING
		x += GRASS_GRID_SPACING

	# Write to MultiMesh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _grass_mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	grass_mmi.multimesh = mm


func _write_multimesh(mmi: MultiMeshInstance3D, mesh: Mesh, part_offset: Transform3D, transforms: Array[Transform3D]) -> void:
	# Each tree part has a local offset (e.g. canopy1 is at y=1.5). Bake that offset
	# into the per-instance transform so all parts align correctly.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()

	for i in transforms.size():
		# Compose: world placement * local part offset
		mm.set_instance_transform(i, transforms[i] * part_offset)

	mmi.multimesh = mm


func _spawn_tree_collision(t: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.global_transform = Transform3D(Basis.IDENTITY, t.origin)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 2.0
	col.shape = shape
	col.position.y = 1.0
	body.add_child(col)
	add_child(body)


func _spawn_rock_collision(t: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.global_transform = Transform3D(Basis.IDENTITY, t.origin)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	var s := t.basis.get_scale()
	shape.radius = max(s.x, s.z) * 0.5
	col.shape = shape
	body.add_child(col)
	add_child(body)

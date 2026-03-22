# Trees & Rocks Scatter System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scatter 50-80 pine trees and 15-25 accent rocks across the island using noise-based placement, MultiMeshInstance3D rendering, collision bodies, and day/night sync.

**Architecture:** A `scatter.gd` script manages five MultiMeshInstance3D nodes — four for tree parts (trunk, canopy1, canopy2, canopy3) sharing the same transforms, and one for rocks. MultiMesh can only render one mesh type per instance, so multi-part trees require one MMI per part. On generation, the script samples a jittered grid, applies noise + filter masks, collects accepted transforms, writes them to all tree MMIs (same transforms, different meshes/materials), and spawns matching StaticBody3D collision. A shared `foliage.gdshader` provides cel-shading with day/night darkening.

**Tech Stack:** Godot 4.6, GDScript, GLSL spatial shaders, MultiMeshInstance3D, FastNoiseLite, RandomNumberGenerator

**Spec:** `docs/superpowers/specs/2026-03-22-trees-rocks-design.md`

---

## File Map

### Create
| File | Responsibility |
|------|---------------|
| `shaders/foliage.gdshader` | Cel-shaded spatial shader with `base_color` and `day_factor` uniforms |
| `scenes/tree.tscn` | Pine tree mesh: CylinderMesh trunk + 3 ConeMesh canopy layers, foliage shader materials |
| `scenes/rock.tscn` | Rock mesh: SphereMesh with non-uniform scale, foliage shader material |
| `scripts/scatter.gd` | Placement logic, MultiMesh management, collision spawning, day/night update |

### Modify
| File | Changes |
|------|---------|
| `scripts/terrain.gd` | Add `get_seed() -> float` getter (1 line) |
| `scenes/main.tscn` | Add Scatter node with 5 MultiMeshInstance3D children (4 tree parts + 1 rock) |
| `scripts/main.gd` | Add scatter `@onready`, `generate()` call, `update_day_factor()` call, `regenerate()` call |
| `CLAUDE.md` | Document new files and scatter pattern |

---

### Task 1: Foliage Shader

**Files:**
- Create: `shaders/foliage.gdshader`

- [ ] **Step 1: Create the foliage shader**

```glsl
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.45, 0.65, 0.5, 1.0);
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = base_color.rgb;
	ALBEDO *= mix(0.4, 1.0, day_factor);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	// Rim light — matches terrain shader
	float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	rim = smoothstep(0.5, 1.0, rim);
	EMISSION = vec3(0.85, 0.93, 0.95) * rim * 0.3 * day_factor;
}

void light() {
	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float cel = floor(NdotL * 3.0 + 0.5) / 3.0;
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * cel;
}
```

- [ ] **Step 2: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0, no errors

- [ ] **Step 3: Commit**

```bash
git add shaders/foliage.gdshader
git commit -m "feat: cel-shaded foliage shader with day/night darkening"
```

---

### Task 2: Tree PackedScene

**Files:**
- Create: `scenes/tree.tscn`

The tree scene is mesh-data only — a trunk (CylinderMesh) and 3 canopy cones (ConeMesh), each with a ShaderMaterial using the foliage shader. This scene is never instantiated; `scatter.gd` reads the mesh from it.

- [ ] **Step 1: Create `scenes/tree.tscn`**

Write a `.tscn` file with:
- Root `Node3D` named "Tree"
- `MeshInstance3D` "Trunk": CylinderMesh, top_radius=0.12, bottom_radius=0.18, height=1.5. ShaderMaterial with `foliage.gdshader`, `base_color = Color(0.545, 0.42, 0.29, 1)` (trunk brown #8B6B4A)
- `MeshInstance3D` "Canopy1": ConeMesh, radius=1.2, height=1.8, position.y=1.5. ShaderMaterial with `foliage.gdshader`, `base_color = Color(0.3, 0.5, 0.35, 1)` (dark green)
- `MeshInstance3D` "Canopy2": ConeMesh, radius=0.9, height=1.5, position.y=2.5. ShaderMaterial with `foliage.gdshader`, `base_color = Color(0.35, 0.58, 0.4, 1)` (mid green)
- `MeshInstance3D` "Canopy3": ConeMesh, radius=0.6, height=1.2, position.y=3.3. ShaderMaterial with `foliage.gdshader`, `base_color = Color(0.3, 0.5, 0.35, 1)` (dark green)

```
[gd_scene load_steps=8 format=3]

[ext_resource type="Shader" path="res://shaders/foliage.gdshader" id="1"]

[sub_resource type="ShaderMaterial" id="Mat_trunk"]
shader = ExtResource("1")
shader_parameter/base_color = Color(0.545, 0.42, 0.29, 1)
shader_parameter/day_factor = 1.0

[sub_resource type="CylinderMesh" id="Mesh_trunk"]
top_radius = 0.12
bottom_radius = 0.18
height = 1.5

[sub_resource type="ShaderMaterial" id="Mat_canopy_dark"]
shader = ExtResource("1")
shader_parameter/base_color = Color(0.3, 0.5, 0.35, 1)
shader_parameter/day_factor = 1.0

[sub_resource type="ShaderMaterial" id="Mat_canopy_mid"]
shader = ExtResource("1")
shader_parameter/base_color = Color(0.35, 0.58, 0.4, 1)
shader_parameter/day_factor = 1.0

[sub_resource type="ConeMesh" id="Mesh_cone_bottom"]
radius = 1.2
height = 1.8

[sub_resource type="ConeMesh" id="Mesh_cone_mid"]
radius = 0.9
height = 1.5

[sub_resource type="ConeMesh" id="Mesh_cone_top"]
radius = 0.6
height = 1.2

[node name="Tree" type="Node3D"]

[node name="Trunk" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.75, 0)
material_override = SubResource("Mat_trunk")
mesh = SubResource("Mesh_trunk")

[node name="Canopy1" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.5, 0)
material_override = SubResource("Mat_canopy_dark")
mesh = SubResource("Mesh_cone_bottom")

[node name="Canopy2" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, 0)
material_override = SubResource("Mat_canopy_mid")
mesh = SubResource("Mesh_cone_mid")

[node name="Canopy3" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3.3, 0)
material_override = SubResource("Mat_canopy_dark")
mesh = SubResource("Mesh_cone_top")
```

Note: `load_steps` must equal the total sub_resource + ext_resource count + 1. Count: 1 ext_resource + 7 sub_resources = 8. Adjust if Godot complains.

- [ ] **Step 2: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 3: Commit**

```bash
git add scenes/tree.tscn
git commit -m "feat: pine tree PackedScene with 3-layer canopy"
```

---

### Task 3: Rock PackedScene

**Files:**
- Create: `scenes/rock.tscn`

- [ ] **Step 1: Create `scenes/rock.tscn`**

A single SphereMesh with non-uniform scale and the foliage shader in rock grey.

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Shader" path="res://shaders/foliage.gdshader" id="1"]

[sub_resource type="ShaderMaterial" id="Mat_rock"]
shader = ExtResource("1")
shader_parameter/base_color = Color(0.6, 0.6, 0.54, 1)
shader_parameter/day_factor = 1.0

[sub_resource type="SphereMesh" id="Mesh_rock"]
radius = 0.5
height = 1.0

[node name="Rock" type="Node3D"]

[node name="Mesh" type="MeshInstance3D" parent="."]
transform = Transform3D(1.0, 0, 0, 0, 0.6, 0, 0, 0, 0.8, 0, 0, 0)
material_override = SubResource("Mat_rock")
mesh = SubResource("Mesh_rock")
```

- [ ] **Step 2: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 3: Commit**

```bash
git add scenes/rock.tscn
git commit -m "feat: rock PackedScene with squished sphere mesh"
```

---

### Task 4: Terrain get_seed() Getter

**Files:**
- Modify: `scripts/terrain.gd:22` — add `get_seed()` after `set_seed()`

- [ ] **Step 1: Add getter to terrain.gd**

After the `set_seed()` function (line 22-25), add:

```gdscript
func get_seed() -> float:
	return _current_seed
```

- [ ] **Step 2: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 3: Commit**

```bash
git add scripts/terrain.gd
git commit -m "feat: expose terrain seed via get_seed() getter"
```

---

### Task 5: Scatter Script

**Files:**
- Create: `scripts/scatter.gd`

This is the core placement logic. It manages five MultiMeshInstance3D children — four for tree parts (TreeTrunk, TreeCanopy1, TreeCanopy2, TreeCanopy3) sharing the same transforms, and one for rocks (RockMesh). MultiMesh can only render one mesh type per instance, so multi-part trees need one MMI per part.

- [ ] **Step 1: Create `scripts/scatter.gd`**

```gdscript
extends Node3D

const ISLAND_RADIUS := 55.0
const MEADOW_RADIUS := 15.0
const TREE_GRID_SPACING := 5.0
const ROCK_GRID_SPACING := 9.0
const JITTER := 2.0

# 4 MMIs for tree parts (trunk + 3 canopy layers) — same transforms, different meshes
@onready var tree_trunk_mmi: MultiMeshInstance3D = $TreeTrunk
@onready var tree_canopy1_mmi: MultiMeshInstance3D = $TreeCanopy1
@onready var tree_canopy2_mmi: MultiMeshInstance3D = $TreeCanopy2
@onready var tree_canopy3_mmi: MultiMeshInstance3D = $TreeCanopy3
@onready var rock_mmi: MultiMeshInstance3D = $RockMesh

var _tree_mmis: Array[MultiMeshInstance3D]
var _tree_scene: PackedScene
var _rock_scene: PackedScene

func _ready() -> void:
	_tree_scene = load("res://scenes/tree.tscn")
	_rock_scene = load("res://scenes/rock.tscn")
	_tree_mmis = [tree_trunk_mmi, tree_canopy1_mmi, tree_canopy2_mmi, tree_canopy3_mmi]


func generate(terrain: Node3D, water_y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(terrain.get_seed()) + 100

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = int(terrain.get_seed()) + 200
	noise.frequency = 0.08

	_generate_trees(terrain, water_y, rng, noise)
	_generate_rocks(terrain, water_y, rng, noise)


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


func _get_terrain_normal(terrain: Node3D, x: float, z: float) -> Vector3:
	var eps := 0.5
	var hL := terrain.get_height_at(x - eps, z)
	var hR := terrain.get_height_at(x + eps, z)
	var hD := terrain.get_height_at(x, z - eps)
	var hU := terrain.get_height_at(x, z + eps)
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

			var height := terrain.get_height_at(jx, jz)

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

			var height := terrain.get_height_at(jx, jz)

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
```

- [ ] **Step 2: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 3: Commit**

```bash
git add scripts/scatter.gd
git commit -m "feat: scatter system with noise-based tree and rock placement"
```

---

### Task 6: Main Scene Integration

**Files:**
- Modify: `scenes/main.tscn`
- Modify: `scripts/main.gd:5-10` (add @onready), `scripts/main.gd:38-40` (_ready), `scripts/main.gd:106` (_process), `scripts/main.gd:117-121` (_unhandled_input)

- [ ] **Step 1: Add Scatter node to `scenes/main.tscn`**

Add after the Fog node (line 50). The Scatter node has 5 MultiMeshInstance3D children — 4 for tree parts (each with its own material color) and 1 for rocks. Each MMI gets a `material_override` with the foliage shader. The MultiMesh instances start empty; `scatter.gd` populates them at runtime.

Add to ext_resources:
```
[ext_resource type="Script" path="res://scripts/scatter.gd" id="6"]
[ext_resource type="Shader" path="res://shaders/foliage.gdshader" id="7"]
```

Add sub_resources for the 5 materials (trunk brown, dark canopy, mid canopy, dark canopy again, rock grey):
```
[sub_resource type="ShaderMaterial" id="Mat_trunk_multi"]
shader = ExtResource("7")
shader_parameter/base_color = Color(0.545, 0.42, 0.29, 1)
shader_parameter/day_factor = 1.0

[sub_resource type="ShaderMaterial" id="Mat_canopy_dark_multi"]
shader = ExtResource("7")
shader_parameter/base_color = Color(0.3, 0.5, 0.35, 1)
shader_parameter/day_factor = 1.0

[sub_resource type="ShaderMaterial" id="Mat_canopy_mid_multi"]
shader = ExtResource("7")
shader_parameter/base_color = Color(0.35, 0.58, 0.4, 1)
shader_parameter/day_factor = 1.0

[sub_resource type="ShaderMaterial" id="Mat_canopy_dark2_multi"]
shader = ExtResource("7")
shader_parameter/base_color = Color(0.3, 0.5, 0.35, 1)
shader_parameter/day_factor = 1.0

[sub_resource type="ShaderMaterial" id="Mat_rock_multi"]
shader = ExtResource("7")
shader_parameter/base_color = Color(0.6, 0.6, 0.54, 1)
shader_parameter/day_factor = 1.0
```

Add nodes:
```
[node name="Scatter" type="Node3D" parent="."]
script = ExtResource("6")

[node name="TreeTrunk" type="MultiMeshInstance3D" parent="Scatter"]
material_override = SubResource("Mat_trunk_multi")

[node name="TreeCanopy1" type="MultiMeshInstance3D" parent="Scatter"]
material_override = SubResource("Mat_canopy_dark_multi")

[node name="TreeCanopy2" type="MultiMeshInstance3D" parent="Scatter"]
material_override = SubResource("Mat_canopy_mid_multi")

[node name="TreeCanopy3" type="MultiMeshInstance3D" parent="Scatter"]
material_override = SubResource("Mat_canopy_dark2_multi")

[node name="RockMesh" type="MultiMeshInstance3D" parent="Scatter"]
material_override = SubResource("Mat_rock_multi")
```

Update `load_steps` at line 1 from 10 to 17 (added 2 ext_resources + 5 sub_resources).

- [ ] **Step 2: Add scatter references and calls to `main.gd`**

After `@onready var water` (line 10), add:
```gdscript
@onready var scatter: Node3D = $Scatter
```

Inside `_ready()`, after `player.water_y = $Water.global_position.y` (line 40), add at the same indent level (one tab):
```gdscript
	scatter.generate(terrain, $Water.global_position.y)
```

Inside `_process()`, after the water shader block (after line 105), add at the same indent level as the other shader blocks (one tab):
```gdscript
	# Scatter — day/night sync
	scatter.update_day_factor(day_factor)
```

Inside `_unhandled_input()`, after `player.velocity = Vector3.ZERO` (line 121), add at the same indent level (two tabs — inside the `if` block):
```gdscript
		scatter.regenerate(terrain, $Water.global_position.y)
```
Note: `regenerate()` is async (uses `await`) but does not need to be awaited here — the scatter regeneration runs independently after the frame processes.

- [ ] **Step 3: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 4: Commit**

```bash
git add scenes/main.tscn scripts/main.gd
git commit -m "feat: integrate scatter system into main scene"
```

---

### Task 7: CLAUDE.md Updates and Final Polish

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

Add to Scenes section (after fog.tscn line):
```
- `scenes/tree.tscn` — pine tree mesh reference (trunk + 3 cone layers), not instantiated
- `scenes/rock.tscn` — rock mesh reference (squished sphere), not instantiated
```

Add to Scripts section (after terrain.gd):
```
- `scripts/scatter.gd` — noise-based tree/rock placement via MultiMeshInstance3D, collision spawning, day/night sync
```

Add to Shaders section (after character_wet.gdshader):
```
- `shaders/foliage.gdshader` — cel-shaded foliage with day/night darkening, shared by trees and rocks
```

Update main.tscn description to include scatter:
Change `root scene: terrain, player, water, fog, sun, environment` to `root scene: terrain, player, water, fog, scatter (trees/rocks), sun, environment`

Update main.gd description to include scatter sync:
Add `, scatter sync (day/night, regeneration)` to the end

Add to Key patterns:
```
- **Scatter placement**: scatter.gd uses noise masks + terrain filters (height, slope, distance) to place objects. Seed derived from terrain seed for deterministic regeneration. MultiMeshInstance3D for rendering, separate StaticBody3D children for collision
```

- [ ] **Step 2: Verify project loads one final time**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with scatter system architecture"
```

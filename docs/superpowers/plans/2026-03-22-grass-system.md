# Grass System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the meadow and lower slopes with ~3000-4000 swaying grass blades that bend away from the player and sync with day/night.

**Architecture:** A `grass.gdshader` handles wind sway, player push-away, color gradient, and cel-shading in the vertex/fragment shaders. `scatter.gd` is extended with `_generate_grass()` using the same MultiMesh pattern as trees/rocks but with denser placement (1.5-unit grid) and noise-based density thinning. A PlaneMesh (0.06 x 0.4) is constructed inline — no separate scene file. The `GrassMesh` MultiMeshInstance3D node has `visibility_range_end = 40.0` for distance culling.

**Tech Stack:** Godot 4.6, GDScript, GLSL spatial shaders, MultiMeshInstance3D, PlaneMesh

**Spec:** `docs/superpowers/specs/2026-03-22-grass-system-design.md`

---

## File Map

### Create
| File | Responsibility |
|------|---------------|
| `shaders/grass.gdshader` | Wind sway, player push-away, color gradient, cel-shading |

### Modify
| File | Changes |
|------|---------|
| `scripts/scatter.gd` | Add `grass_mmi` ref, inline PlaneMesh, `_generate_grass()`, update `regenerate()` and `update_day_factor()` |
| `scripts/main.gd` | Pass `player_xz` to grass shader each frame |
| `scenes/main.tscn` | Add GrassMesh MMI under Scatter with material + visibility range |
| `CLAUDE.md` | Document grass system |

---

### Task 1: Grass Shader

**Files:**
- Create: `shaders/grass.gdshader`

- [ ] **Step 1: Create the grass shader**

```glsl
shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color = vec3(0.35, 0.70, 0.45);
uniform vec3 tip_color = vec3(0.55, 0.90, 0.65);
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;
uniform vec2 player_xz = vec2(0.0, 0.0);
uniform float wind_strength : hint_range(0.0, 2.0) = 0.8;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway_factor = UV.y;

	// Two overlapping wind frequencies for organic movement
	float wind1 = sin(TIME * 1.5 + world_pos.x * 0.8 + world_pos.z * 0.3) * wind_strength;
	float wind2 = sin(TIME * 2.3 + world_pos.x * 0.3 + world_pos.z * 1.1) * wind_strength * 0.4;
	float wind = (wind1 + wind2) * sway_factor;

	VERTEX.x += wind * 0.15;
	VERTEX.z += wind * 0.08;

	// Player push-away (guard against zero-length)
	vec2 to_player = world_pos.xz - player_xz;
	float dist = length(to_player);
	float push = smoothstep(1.5, 0.3, dist) * sway_factor;
	vec2 push_dir = normalize(to_player + vec2(0.001, 0.001)) * push * 0.4;
	VERTEX.x += push_dir.x;
	VERTEX.z += push_dir.y;
}

void fragment() {
	vec3 col = mix(base_color, tip_color, UV.y);
	col *= mix(0.4, 1.0, day_factor);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	// Rim light matching terrain
	float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	rim = smoothstep(0.5, 1.0, rim);
	EMISSION = vec3(0.85, 0.93, 0.95) * rim * 0.2 * day_factor;
}

void light() {
	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float cel = floor(NdotL * 3.0 + 0.3) / 3.0;
	cel = cel * cel;
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * cel;
}
```

- [ ] **Step 2: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 3: Commit**

```bash
git add shaders/grass.gdshader
git commit -m "feat: grass shader with wind sway, player push-away, cel-shading"
```

---

### Task 2: Scatter — Grass Placement

**Files:**
- Modify: `scripts/scatter.gd`

This extends the existing scatter script with grass generation. Key differences from trees/rocks: denser grid (1.5 units vs 5/9), dedicated RNG seeds, no collision, inline PlaneMesh instead of loaded scene.

- [ ] **Step 1: Add grass MMI reference and constants**

After the existing `@onready var rock_mmi` (line 14), add:
```gdscript
@onready var grass_mmi: MultiMeshInstance3D = $GrassMesh
```

After `const JITTER := 2.0` (line 7), add:
```gdscript
const GRASS_GRID_SPACING := 1.5
const GRASS_JITTER := 0.7
```

After `var _rock_scene: PackedScene` (line 18), add:
```gdscript
var _grass_mesh: PlaneMesh
```

- [ ] **Step 2: Create inline PlaneMesh in _ready()**

At the end of `_ready()` (after the `_tree_mmis` array assignment, line 23), add:
```gdscript
	_grass_mesh = PlaneMesh.new()
	_grass_mesh.size = Vector2(0.06, 0.4)
	_grass_mesh.orientation = PlaneMesh.FACE_Z  # Vertical quad facing camera-ish
```

Note: `PlaneMesh.FACE_Z` makes the quad vertical (facing Z axis) rather than horizontal. This is critical — horizontal grass would be invisible.

- [ ] **Step 3: Add _generate_grass() function**

Add after `_generate_rocks()` (the full function). Uses dedicated RNG and noise seeds (300/400) to avoid coupling with tree/rock order:

```gdscript
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
```

- [ ] **Step 4: Call _generate_grass() from generate()**

At the end of `generate()` (after line 36, `_generate_rocks(...)`), add:
```gdscript
	_generate_grass(terrain, water_y)
```

- [ ] **Step 5: Add grass to regenerate() cleanup**

After `if rock_mmi.multimesh:` block (line 48-49), add:
```gdscript
	if grass_mmi.multimesh:
		grass_mmi.multimesh.instance_count = 0
```

- [ ] **Step 6: Add grass to update_day_factor()**

After the `if rock_mmi.material_override:` block (line 60-61), add:
```gdscript
	if grass_mmi.material_override:
		grass_mmi.material_override.set_shader_parameter("day_factor", day_factor)
```

- [ ] **Step 7: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 8: Commit**

```bash
git add scripts/scatter.gd
git commit -m "feat: grass placement with density thinning and inline PlaneMesh"
```

---

### Task 3: Main Scene Integration

**Files:**
- Modify: `scenes/main.tscn`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Add GrassMesh node to main.tscn**

Read `scenes/main.tscn`. Add a new ShaderMaterial sub_resource and the GrassMesh node.

Add sub_resource (with the other Scatter materials):
```
[sub_resource type="ShaderMaterial" id="Mat_grass_multi"]
shader = ExtResource("7")
shader_parameter/base_color = Color(0.35, 0.70, 0.45, 1)
shader_parameter/tip_color = Color(0.55, 0.90, 0.65, 1)
shader_parameter/day_factor = 1.0
shader_parameter/wind_strength = 0.8
```

Wait — the grass shader is a different file than `foliage.gdshader` (ExtResource "7"). We need a new ext_resource for `grass.gdshader`:

```
[ext_resource type="Shader" path="res://shaders/grass.gdshader" id="8"]
```

Then the material references id="8":
```
[sub_resource type="ShaderMaterial" id="Mat_grass_multi"]
shader = ExtResource("8")
shader_parameter/base_color = Color(0.35, 0.70, 0.45, 1)
shader_parameter/tip_color = Color(0.55, 0.90, 0.65, 1)
shader_parameter/day_factor = 1.0
shader_parameter/wind_strength = 0.8
```

Add the node after the RockMesh node:
```
[node name="GrassMesh" type="MultiMeshInstance3D" parent="Scatter"]
material_override = SubResource("Mat_grass_multi")
visibility_range_end = 40.0
visibility_range_end_margin = 5.0
```

Update `load_steps` (increment by 2: +1 ext_resource + 1 sub_resource).

Note: If Godot has re-saved `main.tscn` with UIDs, the ext_resource format may differ. Match whatever format is currently in the file. The `id` number may also differ — use the next available ID.

- [ ] **Step 2: Add player_xz pass-through in main.gd**

Read `scripts/main.gd`. In `_process()`, after the scatter day_factor call (`scatter.update_day_factor(day_factor)`), add:

```gdscript
	# Grass — player position for push-away
	var grass_mat: ShaderMaterial = scatter.get_node("GrassMesh").material_override
	if grass_mat:
		grass_mat.set_shader_parameter("player_xz", Vector2(player.global_position.x, player.global_position.z))
```

- [ ] **Step 3: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 4: Commit**

```bash
git add scenes/main.tscn scripts/main.gd
git commit -m "feat: integrate grass into main scene with player push-away"
```

---

### Task 4: CLAUDE.md Updates

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

Add to Shaders section (after `foliage.gdshader` line):
```
- `shaders/grass.gdshader` — wind-swaying grass blades with player push-away, cel-shading, day/night
```

Update scatter.gd description — add `, grass placement with density thinning`

Update main.gd description — add `, grass player_xz sync`

Add to Key patterns:
```
- **Grass density**: scatter.gd places grass on a 1.5-unit grid with noise thinning beyond meadow radius. Dense in meadow center, sparse on lower slopes, none on mountains or underwater
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with grass system"
```

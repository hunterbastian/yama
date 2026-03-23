# Grass System — Design Spec

## Goal

Fill the meadow and lower slopes with knee-high swaying grass blades that react to the player and sync with day/night. Optimized for performance with MultiMesh rendering, distance-based LOD, and visibility culling.

## Constraints

- Godot 4.6, GDScript, GLSL spatial shaders
- Must match existing cel-shading and vibrant palette
- Must sync with day/night cycle via `day_factor`
- Player push-away interaction (blades bend from player position)
- Performance target: 3000-5000 blade instances, 60fps
- No collision (grass is visual only — player walks through it)

---

## 1. Grass Blade Mesh

A single grass blade is a thin quad (PlaneMesh, width ~0.06, height ~0.4) constructed inline in `scatter.gd _ready()`. The mesh is double-sided (`render_mode cull_disabled` in shader). No separate scene file — it's a single primitive.

Three height variants via random Y scale at spawn:
- Short: scale 0.6-0.8 (ground cover)
- Medium: scale 1.0-1.2 (standard meadow)
- Tall: scale 1.3-1.6 (occasional tall blades)

Random Y rotation at spawn for variety. Random X/Z tilt (±15 degrees) to break uniformity.

## 2. Grass Shader

`shaders/grass.gdshader` — spatial shader:

```glsl
shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color = vec3(0.35, 0.70, 0.45);
uniform vec3 tip_color = vec3(0.55, 0.90, 0.65);
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;
uniform vec2 player_xz = vec2(0.0, 0.0);
uniform float wind_strength : hint_range(0.0, 2.0) = 0.8;
```

### Wind sway (vertex shader)

Vertex displacement scaled by UV.y (0 at base, 1 at tip) — base stays planted:

```glsl
void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float sway_factor = UV.y;  // 0 at base, 1 at tip

    // Two overlapping wind frequencies for organic movement
    float wind1 = sin(TIME * 1.5 + world_pos.x * 0.8 + world_pos.z * 0.3) * wind_strength;
    float wind2 = sin(TIME * 2.3 + world_pos.x * 0.3 + world_pos.z * 1.1) * wind_strength * 0.4;
    float wind = (wind1 + wind2) * sway_factor;

    VERTEX.x += wind * 0.15;
    VERTEX.z += wind * 0.08;

    // Player push-away (guard against zero-length when player is exactly on blade)
    vec2 to_player = world_pos.xz - player_xz;
    float dist = length(to_player);
    float push = smoothstep(1.5, 0.3, dist) * sway_factor;
    vec2 push_dir = normalize(to_player + vec2(0.001, 0.001)) * push * 0.4;
    VERTEX.x += push_dir.x;
    VERTEX.z += push_dir.y;
}
```

### Fragment (color gradient + cel-shading)

```glsl
void fragment() {
    // Gradient from dark base to light tip
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

## 3. Grass Placement

Extend `scripts/scatter.gd` with a new `_generate_grass()` function and a third MultiMeshInstance3D child (`GrassMesh`).

### Placement algorithm

Denser grid than trees — spacing ~1.5 units with ±0.7 jitter:

1. Sample candidates on a jittered grid (spacing 1.5 units)
2. Apply noise gate for natural patchiness (different noise seed than trees)
3. Filter by:
   - **Below water:** `terrain.get_height_at(x, z) < water_y` — no grass underwater. Uses the base water plane Y (same approach as trees/rocks — blades near the waterline may appear submerged during wave crests, which is acceptable)
   - **Distance from center:** grass is dense in the meadow (radius 15) and thins out to ~25 units from center via noise threshold tightening beyond `MEADOW_RADIUS`
   - **Steep slopes:** `normal.y < 0.8` — no grass on steep terrain (stricter than trees at 0.7)
   - **Island edge:** `dist > island_radius * 0.75` — no grass near the rim
4. For accepted candidates:
   - Query `terrain.get_height_at(x, z)` for Y position
   - Random Y rotation (0 to TAU)
   - Random scale (0.6-1.6 Y, ~1.0 XZ)
   - Random X/Z tilt (±0.25 radians)
   - Write transform to MultiMesh

### Density control

The noise threshold tightens with distance from center to create natural thinning:

```gdscript
var noise_threshold := -0.2  # Base threshold (generous, most candidates pass)
if dist > MEADOW_RADIUS:
    # Thin out beyond meadow — gradually raise threshold
    noise_threshold = lerpf(-0.2, 0.3, (dist - MEADOW_RADIUS) / 10.0)
```

This produces ~3000-4000 blades: dense in the meadow, sparse on lower slopes, none on mountains.

## 4. Performance Optimizations

### MultiMesh visibility range (LOD)

Godot 4's MultiMeshInstance3D supports `visibility_range_end` — blades beyond this distance aren't rendered:

```
GrassMesh.visibility_range_end = 40.0
GrassMesh.visibility_range_end_margin = 5.0
```

This skips rendering grass instances beyond 40 units from camera. The MultiMesh is still a single draw call, but the GPU skips distant instances. The margin creates a smooth fade-out rather than a hard pop.

### Single draw call

MultiMesh renders all ~3000-4000 blades in a single draw call. No per-blade overhead.

### Minimal fragment cost

- Opaque blades (no alpha) — avoids alpha sorting overhead entirely
- Simple gradient color, no texture sampling
- Cel-shading light function is 3 math ops

### Vertex shader efficiency

- Wind uses 2 `sin()` calls per vertex (cheap)
- Player push-away uses 1 `length()` + 1 `smoothstep()` + 1 `normalize()` per vertex
- No matrix multiplications beyond the standard MODEL_MATRIX

## 5. Integration

### scatter.gd changes

Add `@onready var grass_mmi: MultiMeshInstance3D = $GrassMesh` alongside the existing tree/rock MMI references.

In `_ready()`: construct a `PlaneMesh` inline (width 0.06, height 0.4) — no need for a separate scene file since it's a single primitive mesh. Store as `var _grass_mesh: PlaneMesh`.

Add `_generate_grass(terrain, water_y, rng, noise)` called from `generate()` after trees and rocks. Use dedicated RNG/noise seeds to avoid coupling with tree/rock placement order: `rng.seed = int(terrain.get_seed()) + 300`, create a separate `FastNoiseLite` with seed `int(terrain.get_seed()) + 400`.

In `update_day_factor()`, add explicit grass branch (matching existing pattern — not a loop):
```gdscript
if grass_mmi.material_override:
    grass_mmi.material_override.set_shader_parameter("day_factor", day_factor)
```

In `regenerate()`, add to the explicit clear block:
```gdscript
if grass_mmi.multimesh:
    grass_mmi.multimesh.instance_count = 0
```

### main.gd changes

Pass `player_xz` to the grass shader material each frame (same pattern as water shader):
```gdscript
var grass_mat: ShaderMaterial = scatter.get_node("GrassMesh").material_override
if grass_mat:
    grass_mat.set_shader_parameter("player_xz", Vector2(player.global_position.x, player.global_position.z))
```

### main.tscn changes

Add `GrassMesh` MultiMeshInstance3D as child of Scatter node with:
- Material override: ShaderMaterial using `grass.gdshader`
- `visibility_range_end = 40.0`
- `visibility_range_end_margin = 5.0`

## 6. Files Summary

### Create
| File | Responsibility |
|------|---------------|
| `shaders/grass.gdshader` | Grass blade shader: wind sway, player push-away, color gradient, cel-shading |

Note: Grass mesh is a PlaneMesh constructed inline in `scatter.gd _ready()` — no separate scene file needed for a single primitive.

### Modify
| File | Changes |
|------|---------|
| `scripts/scatter.gd` | Add `_generate_grass()`, GrassMesh MMI reference, grass in regeneration |
| `scripts/main.gd` | Pass `player_xz` to grass shader each frame |
| `scenes/main.tscn` | Add GrassMesh MultiMeshInstance3D under Scatter with material + visibility range |
| `CLAUDE.md` | Document grass system |

## 7. Future Upgrade Path

- **Wind system:** Replace hardcoded wind direction with a global `wind_direction` uniform shared across grass, fog, and tree shaders
- **Grass color variation:** Per-instance color via MultiMesh custom data for patches of wildflowers or dried grass
- **Trampling persistence:** Store player trail positions in an array, grass stays bent for N seconds after player passes

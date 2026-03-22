# Trees & Rocks Scatter System — Design Spec

## Goal

Populate yama's island with conical pine trees and small accent rocks using noise-based placement and MultiMeshInstance3D rendering. Objects have collision, sync with day/night, and regenerate with terrain.

## Constraints

- Godot 4.6, GDScript, GLSL spatial shaders
- No imported 3D models — built from primitive meshes (ConeMesh, CylinderMesh, SphereMesh)
- Must match existing cel-shading and Howl's Countryside palette
- Must regenerate when player presses R (terrain seed change)
- Performance target: 50-80 trees + 15-25 rocks rendered via MultiMesh

---

## 1. Tree Mesh

Conical Japanese cedar (sugi) style. Each tree is a PackedScene (`scenes/tree.tscn`) containing:

- **Trunk**: CylinderMesh (radius ~0.15, height ~1.5), brown material (`#8B6B4A`)
- **Canopy**: 2-3 stacked ConeMesh layers with decreasing radius bottom-to-top
  - Bottom cone: radius 1.2, height 1.8
  - Middle cone: radius 0.9, height 1.5 (offset upward)
  - Top cone: radius 0.6, height 1.2 (offset upward)
- **Material**: `shaders/foliage.gdshader` — a spatial shader with cel-shading (3-band quantization matching terrain), rim lighting, and a `day_factor` uniform for night darkening

Three size variants created by scaling the base scene at spawn time:
- Small: scale 0.6-0.8 (young trees, meadow edges)
- Medium: scale 1.0-1.2 (standard)
- Large: scale 1.4-1.8 (old growth, higher elevations)

The tree PackedScene is used as a reference for mesh data only — it is not instantiated at runtime. Collision bodies (StaticBody3D + CylinderShape3D, radius ~0.3, height ~2.0) are constructed in code by `scatter.gd` and added as children of the Scatter node.

## 2. Rock Mesh

Small rounded boulders. Each rock is a PackedScene (`scenes/rock.tscn`) containing:

- **Mesh**: SphereMesh with non-uniform scaling (e.g., scale `(1.0, 0.6, 0.8)`) to look like a natural stone
- **Material**: StandardMaterial3D or foliage shader, using terrain rock color `vec3(0.60, 0.60, 0.54)`, cel-shaded
- **Collision**: StaticBody3D with SphereShape3D

Size variants via random scale at spawn:
- Small: scale 0.3-0.5 (ankle-height pebbles)
- Medium: scale 0.6-1.0 (knee-height boulders)

Random Y-axis rotation at spawn for variety.

## 3. Placement System

A new script `scripts/scatter.gd` attached to a Node3D ("Scatter") in the main scene. Manages two MultiMeshInstance3D children: one for trees, one for rocks.

### Placement algorithm

1. Generate candidate positions on a jittered grid across the island (spacing ~4-6 units for trees, ~8-10 units for rocks)
2. For each candidate, add random jitter (±2 units) to break the grid pattern
3. Evaluate a placement noise function (simplex noise with a different frequency than terrain, using the same seed) to decide spawn vs skip — this creates natural clusters and clearings
4. Reject candidates that fail any filter:
   - **Below water**: `terrain.get_height_at(x, z) < water_y`
   - **Meadow center** (trees only): `distance_from_center < meadow_radius + 5.0` — trees start beyond the meadow with a buffer
   - **Steep slopes** (trees only): terrain normal Y component < 0.7 (too steep for trees to grow). Normal is computed via finite differences: sample `get_height_at` at ±0.5 offsets in X and Z, then `Vector3(hL - hR, 1.0, hD - hU).normalized()` — same approach as terrain shader line 69-74
   - **Island edge**: `distance_from_center > island_radius * 0.85` — nothing near the falloff rim
5. For accepted candidates:
   - Query `terrain.get_height_at(x, z)` for Y position
   - Pick size variant based on height: small (scale 0.6-0.8) below height 3.0, medium (1.0-1.2) at 3.0-7.0, large (1.4-1.8) above 7.0
   - Random Y rotation for visual variety
   - Write transform to MultiMesh
   - Spawn a StaticBody3D at the same position for collision

### Rock placement filters

Rocks use a different noise frequency and relaxed filters:
- Allowed closer to meadow center (`distance > 10.0`) — rocks can appear within the meadow transition zone but not the flat center
- Allowed on moderate slopes (normal Y > 0.5)
- Not allowed below water

### MultiMesh setup

Each MultiMeshInstance3D:
- `transform_format = TRANSFORM_3D`
- Placement collects accepted transforms into an array first, then sets `instance_count` to the array size, then writes all transforms
- Mesh assigned from the tree/rock PackedScene's MeshInstance3D
- Material override with foliage shader

Collision bodies are separate Node3D children of the Scatter node, not part of the MultiMesh. On `regenerate()`, all collision children are freed by iterating `get_children()` and calling `queue_free()` on each StaticBody3D before re-generating.

## 4. Foliage Shader

`shaders/foliage.gdshader` — spatial shader reusing the cel-shading pattern from `terrain.gdshader`:

```
shader_type spatial;

uniform vec4 base_color : source_color;
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    ALBEDO = base_color.rgb;
    // Night darkening
    ALBEDO *= mix(0.4, 1.0, day_factor);
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
    SPECULAR = 0.0;
}

void light() {
    float NdotL = max(dot(NORMAL, LIGHT), 0.0);
    float cel = floor(NdotL * 3.0 + 0.5) / 3.0;
    DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * cel;
}
```

The `day_factor` uniform is updated by `main.gd` each frame (same value already computed for other systems).

## 5. Integration with main.gd

### Existing connections

- `main.gd` already computes `day_factor` (local variable in `_process()`) and manages terrain regeneration
- `terrain.gd` already exposes `get_height_at()` and `set_seed()`. Add a `get_seed() -> float` getter that returns `_current_seed`

### New connections

- `main.gd` gets `@onready var scatter: Node3D = $Scatter`
- In `_process()`, call `scatter.update_day_factor(day_factor)` which sets the `day_factor` shader parameter on both MultiMeshInstance3D material overrides
- In `_unhandled_input()` regeneration block, call `scatter.regenerate(terrain, water_y)` after `terrain.set_seed()`
- In `_ready()`, call `scatter.generate(terrain, water_y)` for initial population

### scatter.gd public API

```gdscript
func generate(terrain: Node3D, water_y: float) -> void
func regenerate(terrain: Node3D, water_y: float) -> void  # clears + generates
func update_day_factor(day_factor: float) -> void  # sets shader uniform on MultiMesh materials
```

`water_y` is `$Water.global_position.y` from main.gd (currently -0.2).

## 6. Regeneration

When R is pressed:
1. `terrain.set_seed(new_seed)` — terrain changes
2. `scatter.regenerate(terrain, water_y)` — clears all MultiMesh instances and collision bodies, re-runs placement with the same seed (derived from terrain seed)
3. Player repositioned above terrain (existing behavior)

The scatter seed is derived from the terrain seed (e.g., `terrain_seed + 100.0`) so the same terrain always produces the same tree layout.

## 7. Files Summary

### Create
- `scenes/tree.tscn` — pine tree PackedScene (trunk + 3 cone layers + collision)
- `scenes/rock.tscn` — rock PackedScene (squished sphere + collision)
- `shaders/foliage.gdshader` — cel-shaded foliage with day/night
- `scripts/scatter.gd` — placement logic, MultiMesh management, collision spawning

### Modify
- `scenes/main.tscn` — add Scatter node with two MultiMeshInstance3D children
- `scripts/main.gd` — scatter reference, day_factor sync, regeneration hook
- `CLAUDE.md` — document new files and scatter pattern

## 8. Future Upgrade Path

- **Grass**: Same scatter system with a third MultiMesh, much higher density, no collision, vertex shader wind animation
- **Biome variation**: Swap tree/rock scenes based on region (cherry blossoms near water, darker pines at peaks)
- **LOD**: At higher object counts, MultiMesh supports visibility ranges for distance-based detail reduction
- **Wind**: Add TIME-based vertex displacement to foliage shader for swaying canopy

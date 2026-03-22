# yama

Ghibli-style island explorer. Procedural floating island with day/night cycle, volumetric fog, and animated water.

## Stack
- Godot 4.6 with GDScript
- GLSL spatial shaders (terrain, water, fog)

## Architecture

### Scenes
- `scenes/main.tscn` — root scene: terrain, player, water, fog, scatter (trees/rocks), sun, environment
- `scenes/player.tscn` — CharacterBody3D with capsule model, walk animation, camera pivot, splash particles, wet shader legs
- `scenes/terrain.tscn` — subdivided PlaneMesh displaced by terrain shader
- `scenes/water.tscn` — transparent water plane with depth-based shore blending
- `scenes/fog.tscn` — 140x140 transparent plane at y=2.0 for volumetric fog
- `scenes/tree.tscn` — pine tree mesh reference (trunk + 3 cone layers), not instantiated
- `scenes/rock.tscn` — rock mesh reference (squished sphere), not instantiated

### Scripts
- `scripts/main.gd` — day/night cycle (palette blending), fog sync, terrain regeneration (R key), water shader sync (ripples, foam, day/night tint), scatter sync (day/night, regeneration)
- `scripts/player.gd` — WASD + sprint + jump, coyote time, apex float, procedural walk animation, wading state (depth tiers, speed scaling, jump disable), splash particles, wet timer
- `scripts/camera.gd` — 3rd person orbit, mouse look, terrain collision avoidance
- `scripts/terrain.gd` — CPU heightmap mirror (must match shader exactly), HeightMapShape3D collision
- `scripts/scatter.gd` — noise-based tree/rock placement via MultiMeshInstance3D, collision spawning, day/night sync

### Shaders
- `shaders/terrain.gdshader` — simplex noise (3 octaves), island falloff, meadow mask, Howl's Countryside palette, cel-shading (3 bands), rim lighting
- `shaders/water.gdshader` — vertex wave displacement, depth-buffer shore blending, metallic/specular, player ripple rings, foam trail with day/night tinting
- `shaders/fog.gdshader` — FBM noise (4 octaves), dual-layer scrolling, height-based density, depth soft edges
- `shaders/character_wet.gdshader` — wet darkening below water line for leg meshes, dry persistence timer
- `shaders/foliage.gdshader` — cel-shaded foliage with day/night darkening, shared by trees and rocks

### Key patterns
- **CPU-GPU heightmap mirror**: terrain.gd `_sample_height()` must match `terrain_height()` in the shader exactly (same octaves, same offsets, same seed approach)
- **Day/night sync**: main.gd drives sun, sky, fog, and volumetric fog colors through palette blending. Any new visual element should sync with `day_factor` and `sunset_factor`
- **Simplex noise shared**: terrain and fog shaders both include the same Ashima Arts simplex implementation. If adding new noise-based shaders, copy the same functions
- **Wading detection**: player.gd compares `global_position.y` against `water_y` (set by main.gd from Water node). When rivers/lakes are added, swap to Area3D volumes — shader uniforms stay the same
- **Scatter placement**: scatter.gd uses noise masks + terrain filters (height, slope, distance) to place objects. Seed derived from terrain seed for deterministic regeneration. MultiMeshInstance3D for rendering, separate StaticBody3D children for collision

## Verification
Open in Godot 4.6 and run from editor. Headless check: `godot --headless --quit` (verifies project loads without errors). No CLI build commands.

## Controls
- WASD: move
- Space: jump
- Shift: sprint
- R: regenerate terrain
- Mouse: camera orbit
- Escape: release mouse

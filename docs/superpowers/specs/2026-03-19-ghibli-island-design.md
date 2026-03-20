# Ghibli Island Explorer — Design Spec

## Summary

A 3D third-person exploration game in Godot 4. The player controls a small character running on a procedural heightmap island with a Studio Ghibli (Howl's Moving Castle) visual style. No enemies, no score — the terrain is the experience. Press R to regenerate a new island.

## Art Direction: Howl's Countryside

Cool, airy, European pastoral. Mint greens and soft blues with white cloud wisps. Crisp air, high meadows, objects fading to cool blue-white distance fog.

- **Palette:** Grass `#8bbf9f` → `#c5e6d0`, Rock `#9a9a8a`, Shore `#e8dcc8`, Sky `#a8d8ea` → `#e8f4f0`, Fog `#d8eaf0`
- **Cel-shading:** 2-3 discrete light bands, not smooth gradients
- **Rim lighting:** Bright edge highlight on terrain silhouettes
- **Painted texture feel:** Noise-based color variation on flat areas
- **Fog:** Cool blue-white, objects fade into tinted horizon

## Systems

### 1. Terrain (Shader-Based)

A `PlaneMesh` subdivided 128x128, displaced by a vertex shader.

- **Noise:** 2 octaves of simplex noise for rolling hills
- **Island falloff:** Radial distance from center multiplied into height — edges slope to sea level
- **Fragment shader:** Blends grass/rock/shore by height and slope (normal dot product)
- **Collision:** Same noise computed on CPU → `HeightMapShape3D` on `StaticBody3D`
- **Seed:** Exposed as shader uniform; changing it regenerates the island

### 2. Character

`CharacterBody3D` with capsule collision shape.

- WASD movement relative to camera facing direction
- Space = jump with coyote time (~0.15s) and apex float (reduced gravity near peak)
- Shift = sprint (1.5x speed)
- Responsive, light feel — quick acceleration, low friction
- Visual: capsule or sphere mesh (placeholder, can be replaced later)

### 3. Camera

Third-person orbit camera.

- Smooth follow with position lag (~0.1s lerp)
- Mouse orbits around character (horizontal unlimited, vertical clamped)
- Stays above terrain via downward raycast
- Default position: slightly above and behind character

### 4. Water

Flat `PlaneMesh` at y=0, larger than island.

- Vertex shader: subtle wave displacement (sin-based)
- Fragment shader: sky-tinted color (`#a8d8ea`), transparency near shore, subtle specular
- No collision — purely visual

### 5. Environment

- **Sky:** Gradient from pale blue to white via `ProceduralSkyMaterial`
- **Sun:** `DirectionalLight3D`, slightly warm, soft shadows
- **Fog:** Godot's built-in fog or shader-based distance fog, cool blue-white
- **Ambient:** Cool-tinted for Howl's Countryside contrast

### 6. Island Regeneration

Press R → new random seed → update shader uniform + rebuild CPU heightmap collision.

## Out of Scope

- Trees/vegetation (future pass)
- Audio
- UI (except maybe seed display)
- Save/load
- Enemies/scoring

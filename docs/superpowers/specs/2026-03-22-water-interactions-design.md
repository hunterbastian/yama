# Water Interactions Design

Ghibli-style wading system for yama. Walk into water, movement slows, shader ripples and foam trail on the water surface, particle splashes from footsteps, character legs darken below the water line.

## Approach

Height comparison against the water plane (Approach A). Player script checks `water_plane_y - player.y` each physics frame. Designed so Area3D water volumes (Approach B) can replace the height check later when rivers/lakes are added — the shader uniforms and particle system stay the same.

## 1. Wading State Detection

`player.gd` computes `water_depth = water_plane_y - global_position.y` each physics frame.

Three depth tiers:
- **Ankle** (0.0-0.3): 0.85x speed, small ripples, light particles
- **Knee** (0.3-0.6): 0.65x speed, larger ripples + foam, more particles
- **Waist** (0.6+): 0.4x speed, big ripples + dense foam, splash particles, jump disabled

Changes to `player.gd`:
- `@export var water_y` set from main.gd
- `_physics_process` multiplies speed by depth-based factor
- Jump disabled at waist depth
- Walk animation slows proportionally
- Exposes `water_depth` and `is_wading` for other systems

## 2. Water Shader Ripples and Foam

### Ripples

Water shader receives `uniform vec2 player_xz` and `uniform float player_speed` from `main.gd`.

- Calculates distance from each fragment to player position
- Draws 2-3 concentric rings expanding outward over time, fading with distance
- Ring intensity scales with `player_speed` (standing still = no ripples)
- Sine waves modulated by time for organic look

### Foam trail

Shader receives `uniform vec2 player_velocity_xz`.

- Behind the player (opposite velocity), draws white foam wake
- Noise-textured using existing simplex noise (not a solid stripe)
- Fades out over ~2 seconds after player stops
- Opacity scales with depth tier

Changes to `water.gdshader`:
- New uniforms: `player_xz`, `player_speed`, `player_velocity_xz`, `ripple_time`
- New `ripple()` function — additive blend on albedo
- New `foam()` function — white noise trail mixed into albedo
- Existing shore blending and wave displacement untouched

Changes to `main.gd`:
- Passes player position/velocity to water shader each frame via `set_shader_parameter()`

## 3. Splash Particles

GPUParticles3D node as child of Player scene. Emits only when `is_wading && horizontal_speed > 0.5`.

Particle behavior:
- Small white-blue droplets
- Emit in ring pattern outward from feet
- Initial velocity: upward (1-2m) + outward, with gravity
- Lifetime: 0.4-0.6 seconds
- Size: 0.03-0.06, fade out over lifetime

Emission rate per depth tier:
- Ankle: 4 particles, low velocity
- Knee: 8 particles, medium velocity
- Waist: 12 particles, higher arcs

Footstep timing syncs with existing `_walk_time` — burst at each foot-down moment when `sin(_walk_time)` crosses zero. Sprint = more frequent, larger particles.

Material: unshaded billboard, soft white-blue matching water palette. No texture needed.

## 4. Character Wet Effect

### Water line darkening

New shader (`shaders/character_wet.gdshader`) applied to character mesh materials.

- Receives `uniform float water_y_world`
- Fragments below `water_y_world` darken albedo by 30% and increase roughness
- No discard/clipping — darkening reads better at 3rd person distance

### Wet persistence

- `_wet_timer` in player.gd counts down from 3.0 seconds after leaving water
- `wet_amount` uniform lerps from 1.0 to 0.0 over the timer
- Wet line recedes downward over time (legs dry bottom-up)

New files:
- `shaders/character_wet.gdshader`

Changes to `player.gd`:
- Manages `_wet_timer`, passes `water_y_world` + `wet_amount` to character shader

## File Summary

| File | Change |
|------|--------|
| `scripts/player.gd` | Wading state, depth tiers, speed scaling, wet timer, particle emission sync |
| `shaders/water.gdshader` | Ripple rings, foam trail (new uniforms + functions) |
| `scripts/main.gd` | Pass player pos/velocity to water shader each frame |
| `shaders/character_wet.gdshader` | New — wet darkening below water line |
| `scenes/player.tscn` | Add GPUParticles3D child node |

## Future Upgrade Path

When rivers/lakes are added at different heights, replace the flat `water_y` check with Area3D volumes that each provide their own water height. The shader uniforms, particle system, and wet effect stay identical — only the detection source changes.

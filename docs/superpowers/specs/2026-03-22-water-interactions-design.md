# Water Interactions Design

Ghibli-style wading system for yama. Walk into water, movement slows, shader ripples and foam trail on the water surface, particle splashes from footsteps, character legs darken below the water line.

Audio is out of scope for this step.

## Approach

Height comparison against the water plane (Approach A). Player script checks `water_y - player.y` each physics frame. Designed so Area3D water volumes (Approach B) can replace the height check later when rivers/lakes are added — the shader uniforms and particle system stay the same.

## 1. Wading State Detection

`player.gd` reads the water plane Y from the Water node's transform (y = -0.2 in water.tscn). Main.gd sets `player.water_y` to the Water node's `global_position.y` in `_ready()`.

Depth formula: `water_depth = water_y - global_position.y`. The player's `global_position` is at foot level (CharacterBody3D origin), so depth is positive when feet are below the water surface. Wave displacement (0.03 amplitude) is intentionally ignored in the CPU check — too small to matter.

Three depth tiers:
- **Ankle** (0.0-0.3): 0.85x speed, small ripples, light particles
- **Knee** (0.3-0.6): 0.65x speed, larger ripples + foam, more particles
- **Waist** (0.6+): 0.4x speed, big ripples + dense foam, splash particles, jump disabled

The wading multiplier stacks with sprint (e.g. waist + sprint = 6.0 * 1.5 * 0.4 = 3.6). Sprinting in water is still faster than walking in water, just slower than dry sprinting.

Changes to `player.gd`:
- `var water_y := 0.0` set by main.gd in `_ready()`
- `_physics_process` multiplies speed by depth-based factor
- Jump disabled at waist depth
- Walk animation slows proportionally
- Exposes `water_depth` and `is_wading` for other systems
- Note: `velocity` is already public on CharacterBody3D, no need to re-expose

## 2. Water Shader Ripples and Foam

### Ripples

Water shader receives `uniform vec2 player_xz` and `uniform float player_speed` from `main.gd` in `_process()` (alongside existing day/night code — sub-frame lag from physics is invisible).

- Calculates distance from each fragment to player position
- Draws 2-3 concentric rings expanding outward over time, fading with distance
- Ring intensity scales with `player_speed` (standing still = no ripples)
- Uses built-in `TIME` for ring expansion — no custom `ripple_time` uniform needed

### Foam trail

Shader receives `uniform float player_speed_smooth` — a smooth-damped version of player speed computed in main.gd (lerp toward actual speed, ~2 second decay to zero). This creates the fade-out effect when the player stops. The foam draws in a radius around the player position, not as a spatial trail — the shader has no memory of previous positions.

- Around the player, draws noise-textured white foam using existing simplex noise
- Foam radius and opacity scale with `player_speed_smooth`
- When player stops, smooth speed decays to zero over ~2 seconds, foam shrinks and fades
- Opacity also scales with depth tier

### Day/night tinting

Foam and ripple colors are tinted by the existing fog_light_color from the environment, so they shift warm at sunset and dim at night. Main.gd passes a `uniform vec4 water_effect_tint` derived from the current fog palette.

Changes to `water.gdshader`:
- New uniforms: `player_xz`, `player_speed`, `player_speed_smooth`, `water_effect_tint`
- New `ripple()` function — additive blend on albedo
- New `foam()` function — noise-textured foam mixed into albedo around player
- Existing shore blending and wave displacement untouched

Changes to `main.gd`:
- In `_process()`, passes player position/velocity/smooth-speed to water shader via `set_shader_parameter()`
- Passes `water_effect_tint` from current fog palette

## 3. Splash Particles

GPUParticles3D node as child of Player scene. Emits only when `is_wading && horizontal_speed > 0.5`.

Emitter Y position is clamped to `water_y` so splashes originate at the water surface, not at the player's submerged feet.

Particle behavior:
- Small white-blue droplets
- Emit in ring pattern outward from water surface
- Initial velocity: upward (1-2m) + outward, with gravity
- Lifetime: 0.4-0.6 seconds
- Size: 0.03-0.06, fade out over lifetime

Emission rate per depth tier:
- Ankle: 4 particles, low velocity
- Knee: 8 particles, medium velocity
- Waist: 12 particles, higher arcs

Footstep timing syncs with existing `_walk_time` — burst at each foot-down moment when `sin(_walk_time)` crosses zero. Sprint = more frequent, larger particles. If the player is wading but briefly not `is_on_floor()` (stepping off an underwater bump), particles pause until grounded again — matches the existing walk animation behavior.

Material: unshaded billboard, soft white-blue matching water palette. No texture needed.

## 4. Character Wet Effect

### Water line darkening

New shader (`shaders/character_wet.gdshader`) replaces the `StandardMaterial3D` on LeftLeg and RightLeg only. Body and Head stay on StandardMaterial3D — they are above the water line at all depth tiers.

The shader must reproduce the existing leg albedo color (0.45, 0.58, 0.52) via a `uniform vec4 base_color` so the dry appearance is identical to the current StandardMaterial3D.

- Receives `uniform float water_y_world` and `uniform float wet_amount`
- Fragments with world Y below `water_y_world` darken albedo by `30% * wet_amount` and increase roughness
- No discard/clipping — darkening reads better at 3rd person distance

### Wet persistence

- `_wet_timer` in player.gd counts down from 3.0 seconds after leaving water
- `wet_amount` uniform lerps from 1.0 to 0.0 over the timer
- Wet line recedes downward over time (legs dry bottom-up)

New files:
- `shaders/character_wet.gdshader`

Changes to `player.gd`:
- Manages `_wet_timer`, passes `water_y_world` + `wet_amount` to leg ShaderMaterials

## File Summary

| File | Change |
|------|--------|
| `scripts/player.gd` | Wading state, depth tiers, speed scaling, wet timer, particle emission sync |
| `shaders/water.gdshader` | Ripple rings, foam (new uniforms + functions, day/night tint) |
| `scripts/main.gd` | Pass player pos/velocity/smooth-speed/tint to water shader, set player.water_y |
| `shaders/character_wet.gdshader` | New — wet darkening below water line, legs only |
| `scenes/player.tscn` | Add GPUParticles3D child, swap leg materials to ShaderMaterial |

## Future Upgrade Path

When rivers/lakes are added at different heights, replace the flat `water_y` check with Area3D volumes that each provide their own water height. The shader uniforms, particle system, and wet effect stay identical — only the detection source changes.

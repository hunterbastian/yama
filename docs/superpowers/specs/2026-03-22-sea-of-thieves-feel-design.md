# Sea of Thieves Feel — Design Spec

## Goal

Shift yama's feel toward Sea of Thieves energy: dramatic ocean water with foam and underwater effects, bouncier character movement with weight and momentum, and vibrant saturated colors with wider contrast.

## Constraints

- Godot 4.6, GDScript, GLSL spatial shaders
- Must preserve existing water interaction systems (ripples, foam trail, splash particles, wading, wet effect)
- Must preserve day/night cycle integration
- No imported assets — all procedural/shader-based
- Performance: water shader is fullscreen on a 300x300 plane, must stay real-time

---

## 1. Water Overhaul

### 1a. Gerstner Waves

Replace the single sine wave (`wave_height = 0.03`) with 4 overlapping Gerstner waves. Gerstner waves produce peaked crests and flat troughs — realistic ocean shape, not a wobbling plane.

Each wave defined by: direction (vec2), amplitude, frequency, steepness (Q factor). Total combined height ~0.8-1.0 units.

```
Wave 1: dir=(1.0, 0.0),  amp=0.35, freq=0.8,  Q=0.4  — primary swell
Wave 2: dir=(0.7, 0.7),  amp=0.20, freq=1.2,  Q=0.3  — cross wave
Wave 3: dir=(0.3, 1.0),  amp=0.15, freq=1.8,  Q=0.3  — detail ripple
Wave 4: dir=(-0.5, 0.8), amp=0.10, freq=2.5,  Q=0.2  — fine detail
```

Gerstner vertex displacement formula per wave:
```glsl
// dir is vec2(world_x_direction, world_z_direction)
// For each wave i:
float phase = freq * dot(dir, vertex.xz) + TIME * speed;
vertex.x += Q * amp * dir.x * cos(phase);
vertex.z += Q * amp * dir.y * cos(phase);  // dir.y maps to world Z
vertex.y += amp * sin(phase);
```

Sum all 4 waves. Recompute normals from the Gerstner analytical normal formula (not finite differences — Gerstner normals have a closed-form solution).

The water mesh (`scenes/water.tscn`) needs higher subdivision to show wave geometry. Set subdivisions to 128x128.

**CPU-side wave height:** `main.gd` needs a `_water_height_at(x: float, z: float) -> float` function that evaluates the same 4 Gerstner waves at a given (x, z) to get the water surface height. The base height is `$Water.global_position.y` (currently -0.2) plus the sum of Gerstner Y displacements.

**Per-frame water_y update:** In `main.gd _process()`, before the water shader block, update `player.water_y` each frame:
```gdscript
player.water_y = _water_height_at(player.global_position.x, player.global_position.z)
```
Remove the one-time assignment from `_ready()`. This ensures wading detection, splash particle positioning (line 117), and wet-effect water line (lines 143-150) in `player.gd` all use the correct dynamic wave height automatically — no changes needed in `player.gd` for those systems since they already read `water_y`.

### 1b. Dynamic Foam

Two foam systems, both in the fragment shader:

**Whitecap foam:** Detect steep wave slopes by checking the dot product of the computed wave normal with UP vector. Where `normal.y < 0.7` (steep crest), blend in white foam. Use `value_noise()` (already in shader) for organic texture. Foam intensity scales with slope steepness via smoothstep.

**Shore foam:** Use the depth buffer distance (already computed for shore blending). Animate foam bands with `sin(depth_distance * freq - TIME * speed)`. Two overlapping bands at different frequencies create a natural advancing/retreating foam line. Foam is white with noise texture modulation.

Both foam types are additive white mixed into ALBEDO with noise for organic breakup.

### 1c. Color Depth Gradient

Replace the current 2-color `mix(water_color, deep_color, water_depth)` with a multi-stop gradient:

```glsl
vec3 shallow = vec3(0.55, 0.85, 0.82);  // turquoise
vec3 mid     = vec3(0.30, 0.65, 0.65);  // teal
vec3 deep    = vec3(0.15, 0.40, 0.50);  // dark teal
vec3 abyss   = vec3(0.08, 0.20, 0.30);  // navy

// Blend through stops based on depth
vec3 col = shallow;
col = mix(col, mid, smoothstep(0.0, 0.3, water_depth));
col = mix(col, deep, smoothstep(0.3, 0.6, water_depth));
col = mix(col, abyss, smoothstep(0.6, 1.0, water_depth));
```

Increase the depth range multiplier from `0.15` to `0.4` so the gradient has more visible range before saturating. Note: `water_depth` is computed from view-space Z distance (`VERTEX.z - view_pos.z`), so the gradient will vary slightly with camera angle. This is acceptable — it matches how Sea of Thieves water looks in practice.

### 1d. Underwater Effects

When the camera position is below the water surface height (evaluated via the same Gerstner function):

**Underwater detection ownership:** `main.gd` owns all environment writes (fog, ambient, sun). Add `var _camera_underwater := false` and `var _underwater_blend := 0.0` to `main.gd`. Each frame in `_process()`, check if the camera node's Y position is below `_water_height_at(camera.x, camera.z)`. Smooth `_underwater_blend` toward 1.0 (underwater) or 0.0 (above) with exponential decay (~0.3 second transition). Then blend fog/ambient values:

```gdscript
# After computing fog_color from day/night palette:
var underwater_fog := Color(0.05, 0.18, 0.25)
var underwater_ambient := Color(0.15, 0.35, 0.45)
fog_color = fog_color.lerp(underwater_fog, _underwater_blend)
env.environment.fog_density = lerpf(0.003, 0.05, _underwater_blend)
# Ambient tint
var ambient_color := Color.WHITE.lerp(underwater_ambient, _underwater_blend)
env.environment.ambient_light_color = ambient_color
```

This avoids the conflict of two scripts writing to the same environment property.

**Caustic light patterns:** Add `uniform float caustic_strength` and `uniform float water_y_uniform` to `terrain.gdshader`. When `caustic_strength > 0`, project animated caustic noise onto terrain surfaces below the water line:
```glsl
if (caustic_strength > 0.0 && v_world_pos.y < water_y_uniform) {
    float caustic = value_noise(v_world_pos.xz * 2.0 + TIME * vec2(0.3, 0.2));
    caustic = pow(caustic, 2.0) * 0.4;
    col += vec3(caustic) * caustic_strength;
}
```
`main.gd` sets both uniforms each frame: `caustic_strength` follows `_underwater_blend`, and `water_y_uniform` is `$Water.global_position.y`. The `value_noise` function must be added to `terrain.gdshader` (copy the existing `hash()` + `value_noise()` from `water.gdshader`).

---

## 2. Bouncier Movement

### 2a. Camera Bob

In `camera.gd`, add a vertical + horizontal bob synced to player's walk time. The bob offset must be computed **before** the camera position lerp (baked into the target position, not added after), otherwise the lerp overwrites it.

Track a smoothed bob value rather than reading `player.walk_time` directly, because `_walk_time` resets to 0.0 on idle (causing a hard snap). Instead, `camera.gd` maintains its own `_bob_time` that increments while the player is moving and decays smoothly to zero when idle:

```gdscript
var _bob_time := 0.0
var _bob_amplitude := 0.0

# In _process():
var target_amp := 0.08 if player.is_sprinting else 0.04 if h_speed > 0.5 else 0.0
_bob_amplitude = lerpf(_bob_amplitude, target_amp, 1.0 - exp(-delta * 8.0))
if h_speed > 0.5:
    _bob_time += delta * (8.0 if player.is_sprinting else 5.0)

var bob_y := sin(_bob_time * 2.0) * _bob_amplitude
var bob_x := sin(_bob_time) * _bob_amplitude * 0.5
# Apply bob to target_pos BEFORE the lerp
```

### 2b. Sprint Camera Sway

Roll tilt while sprinting:

```gdscript
var target_roll := sin(walk_time * 1.0) * deg_to_rad(2.0) if sprinting else 0.0
camera.rotation.z = lerp(camera.rotation.z, target_roll, 8.0 * delta)
```

Subtle ±2 degree oscillation that only activates during sprint.

### 2c. Landing Impact

Track `velocity.y` before `move_and_slide()`. After `move_and_slide()`, if `is_on_floor()` and previous `velocity.y < -threshold`:

```gdscript
var impact_strength := clampf(abs(prev_velocity_y) / 15.0, 0.0, 1.0)
_landing_dip = impact_strength * 0.3  # Camera offset in Y
```

`_landing_dip` recovers via exponential decay: `_landing_dip = lerpf(_landing_dip, 0.0, 1.0 - exp(-delta * 10.0))` (~0.3 second spring-back).

Camera applies: `camera.position.y -= _landing_dip`

### 2d. Momentum Acceleration

Replace linear `move_toward` with exponential ease-in:

```gdscript
# Current (linear):
velocity.x = move_toward(velocity.x, wish_dir.x * speed, acceleration * delta * speed)

# New (exponential ease-in):
var target_vel := wish_dir * speed
var accel_weight := 1.0 - exp(-acceleration * 0.5 * delta)
velocity.x = lerpf(velocity.x, target_vel.x, accel_weight)
velocity.z = lerpf(velocity.z, target_vel.z, accel_weight)
```

Reduce `acceleration` from 12.0 to 8.0 to emphasize the initial sluggishness. Keep `friction` at 10.0 for responsive stopping.

Player needs to expose sprint state for camera.gd to read. Promote the local `sprinting` variable (currently `var sprinting := ...` inside `_physics_process()`) to an instance variable:
```gdscript
var is_sprinting := false  # set each frame in _physics_process, read by camera.gd
```
In `_physics_process()`, replace `var sprinting := Input.is_action_pressed("sprint")` with `is_sprinting = Input.is_action_pressed("sprint")`, and update all references from `sprinting` to `is_sprinting` within the function.

---

## 3. Vibrant Colors

### 3a. Terrain Palette Saturation Boost

In `terrain.gdshader` fragment():
```glsl
// Current → New
vec3 shore      = vec3(0.93, 0.84, 0.72);  // was (0.91, 0.86, 0.78) — warmer sand
vec3 grass_low  = vec3(0.45, 0.82, 0.55);  // was (0.55, 0.75, 0.62) — richer green
vec3 grass_high = vec3(0.72, 0.95, 0.78);  // was (0.77, 0.90, 0.82) — brighter highlight
vec3 rock       = vec3(0.55, 0.55, 0.48);  // was (0.60, 0.60, 0.54) — slightly deeper
```

### 3b. Wider Cel-Shading Contrast

In `terrain.gdshader` light():
```glsl
// Current: uniform 3-band
float cel = floor(NdotL * 3.0 + 0.5) / 3.0;

// New: wider contrast — darker shadows, same highlights
float cel = floor(NdotL * 3.0 + 0.3) / 3.0;
cel = cel * cel;  // Push shadows darker (squared curve)
```

The `+ 0.3` (down from `+ 0.5`) shifts the shadow band threshold so more surface area falls into shadow. The `cel * cel` squares the result so shadows are darker while highlights stay bright.

### 3c. Sun and Fog Energy

In `main.gd`:
```gdscript
# Current → New
const DAY_SUN_ENERGY := 1.5    # was 1.2 — brighter day
const NIGHT_SUN_ENERGY := 0.08  # was 0.15 — darker night
const DAY_AMBIENT := 0.5        # was 0.4 — more fill light
const NIGHT_AMBIENT := 0.06     # was 0.1 — darker nights

# Fog saturation boost
const DAY_FOG := Color(0.75, 0.88, 0.92)    # was (0.85, 0.92, 0.94) — more blue
const SUNSET_FOG := Color(0.90, 0.60, 0.40)  # was (0.85, 0.65, 0.5) — more orange
const NIGHT_FOG := Color(0.06, 0.08, 0.18)   # was (0.1, 0.12, 0.2) — deeper night
```

### 3d. Foliage Shader Saturation

Update the `material_override` `shader_parameter/base_color` values on the MultiMeshInstance3D nodes in `main.tscn` (the foliage shader has a single `base_color` uniform — per-instance colors live in the scene material overrides, not in the shader file itself):
- Canopy dark: `Color(0.25, 0.55, 0.30, 1)` (was 0.3, 0.5, 0.35)
- Canopy mid: `Color(0.30, 0.65, 0.38, 1)` (was 0.35, 0.58, 0.4)
- Rock: `Color(0.55, 0.55, 0.48, 1)` (was 0.6, 0.6, 0.54)

---

## 4. Files Summary

### Modify
| File | Changes |
|------|---------|
| `shaders/water.gdshader` | Gerstner waves, whitecap foam, shore foam, depth gradient |
| `scenes/water.tscn` | Increase mesh subdivisions to 128x128 |
| `scripts/main.gd` | CPU Gerstner function `_water_height_at()`, per-frame `player.water_y` update, underwater detection + fog/ambient/caustic blending, color constant updates |
| `scripts/player.gd` | Dynamic water height, expose walk_time/sprinting, momentum acceleration |
| `scripts/camera.gd` | Camera bob, sprint sway, landing impact |
| `shaders/terrain.gdshader` | Palette boost, cel-shading contrast, caustic pattern, `water_y_uniform` + `caustic_strength` uniforms, add `hash()` + `value_noise()` functions |
| `scenes/main.tscn` | Update foliage material colors |
| `CLAUDE.md` | Document changes |

### No new files needed

---

## 5. Integration Notes

- Existing water interaction systems (ripples, foam trail, splash particles, wading speed, wet effect) all continue to work. The `player_xz`, `player_speed`, `player_speed_smooth`, `water_effect_tint` uniforms stay in the water shader.
- `water_y` changes from a one-time constant to a per-frame function evaluation. `main.gd` calls `_water_height_at(x, z)` each frame and writes to `player.water_y`. The Gerstner parameters must match the shader exactly (CPU-GPU mirror, same pattern as terrain heightmap).
- Camera bob tracks its own `_bob_time` independent of `player._walk_time` to avoid snapping on idle. It reads `player.is_sprinting` (exposed as an instance variable).
- Underwater detection and all environment overrides (fog, ambient, caustic) live in `main.gd` to avoid conflicts with the day/night cycle writes. `camera.gd` only handles camera bob/sway/landing — no environment property writes.
- Splash particles, wading detection, and wet-effect all read `player.water_y` which is now updated per-frame — no changes needed in those systems.

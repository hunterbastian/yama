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
Wave 4: dir(-0.5, 0.8),  amp=0.10, freq=2.5,  Q=0.2  — fine detail
```

Gerstner vertex displacement formula per wave:
```glsl
// For each wave i:
float phase = freq * dot(dir, vertex.xz) + TIME * speed;
vertex.x += Q * amp * dir.x * cos(phase);
vertex.z += Q * amp * dir.y * cos(phase);
vertex.y += amp * sin(phase);
```

Sum all 4 waves. Recompute normals from the Gerstner analytical normal formula (not finite differences — Gerstner normals have a closed-form solution).

The water mesh (`scenes/water.tscn`) needs higher subdivision to show wave geometry. Increase from current subdivisions to 128x128.

**CPU-side wave height:** `main.gd` needs a GDScript function that evaluates the same 4 Gerstner waves at a given (x, z) to get the water surface height at the player's position. This replaces the flat `water_y` constant. Player wading detection uses `water_height_at(player.x, player.z)` instead of `water_y`.

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

Increase the depth range multiplier from `0.15` to `0.4` so the gradient has more visible range before saturating.

### 1d. Underwater Effects

When the camera position is below the water surface height (evaluated via the same Gerstner function):

**Fog override:** `camera.gd` detects `camera.global_position.y < water_height_at(camera.x, camera.z)`. When underwater, override environment fog:
- Fog color → `Color(0.05, 0.18, 0.25)` (deep blue-green)
- Fog density → `0.05` (much denser, ~16x current, reduced visibility)
- These values lerp back to normal over 0.3 seconds when surfacing

**Color tint:** Apply underwater tint by shifting the environment ambient light color to blue-green `Color(0.15, 0.35, 0.45)` and reducing ambient energy.

**Caustic light patterns:** Add a `uniform float caustic_strength` to `terrain.gdshader`. When > 0, project animated caustic noise onto terrain surfaces below `water_y`:
```glsl
if (caustic_strength > 0.0 && v_world_pos.y < water_y_uniform) {
    float caustic = value_noise(v_world_pos.xz * 2.0 + TIME * vec2(0.3, 0.2));
    caustic = pow(caustic, 2.0) * 0.4; // Sharpen and brighten
    col += vec3(caustic) * caustic_strength;
}
```
`main.gd` sets `caustic_strength` to 1.0 when camera is underwater, 0.0 otherwise (with smooth transition).

---

## 2. Bouncier Movement

### 2a. Camera Bob

In `camera.gd`, add a vertical + horizontal bob synced to `player._walk_time`:

```gdscript
var bob_y := sin(walk_time * 2.0) * bob_amplitude
var bob_x := sin(walk_time) * bob_amplitude * 0.5
camera.position.y += bob_y
camera.position.x += bob_x
```

- Walk bob amplitude: `0.04`
- Sprint bob amplitude: `0.08`
- Idle: smoothly lerp bob back to zero

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

Player needs to expose `_walk_time` and `sprinting` state for camera.gd to read:
```gdscript
var walk_time: float:  # read by camera.gd
    get: return _walk_time
var is_sprinting := false  # set each frame, read by camera.gd
```

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

Update `foliage.gdshader` base_color defaults and the material overrides in `main.tscn` to match the new richer palette:
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
| `scripts/main.gd` | CPU Gerstner function, dynamic water_y, caustic/underwater uniforms, color constant updates |
| `scripts/player.gd` | Dynamic water height, expose walk_time/sprinting, momentum acceleration |
| `scripts/camera.gd` | Camera bob, sprint sway, landing impact, underwater detection + fog override |
| `shaders/terrain.gdshader` | Palette boost, cel-shading contrast, caustic pattern, water_y uniform |
| `shaders/foliage.gdshader` | Update default base_color |
| `scenes/main.tscn` | Update foliage material colors |
| `CLAUDE.md` | Document changes |

### No new files needed

---

## 5. Integration Notes

- Existing water interaction systems (ripples, foam trail, splash particles, wading speed, wet effect) all continue to work. The `player_xz`, `player_speed`, `player_speed_smooth`, `water_effect_tint` uniforms stay in the water shader.
- `water_y` changes from a constant to a per-frame function evaluation. `main.gd` calls a new `_water_height_at(x, z)` function that sums the 4 Gerstner waves. This must match the shader exactly (CPU-GPU mirror, same pattern as terrain).
- Camera bob reads `player.walk_time` and `player.is_sprinting` — these are exposed as properties on player.gd.
- Underwater detection lives in `camera.gd` since it depends on camera position, not player position.

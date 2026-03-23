# Sea of Thieves Feel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shift yama's feel toward Sea of Thieves: Gerstner ocean waves with foam and underwater effects, bouncier movement with camera bob and momentum, and vibrant saturated colors with wider contrast.

**Architecture:** Three independent systems — water shader overhaul (Gerstner waves, foam, depth gradient, underwater), movement feel (camera bob, sway, landing dip, momentum), and color palette boost (terrain/fog/sun constants). Water changes also touch `main.gd` (CPU wave mirror, underwater detection) and `terrain.gdshader` (caustics). Movement changes touch `player.gd` (momentum, expose sprinting) and `camera.gd` (bob, sway, landing). Colors are constant swaps in existing files.

**Tech Stack:** Godot 4.6, GDScript, GLSL spatial shaders

**Spec:** `docs/superpowers/specs/2026-03-22-sea-of-thieves-feel-design.md`

---

## File Map

### Modify
| File | Changes |
|------|---------|
| `shaders/water.gdshader` | Gerstner waves (vertex), whitecap foam, shore foam, depth gradient (fragment) |
| `scenes/water.tscn` | Subdivisions 64→128, remove old wave uniforms |
| `scripts/main.gd` | `_water_height_at()`, per-frame water_y, underwater blend, caustic uniform, color constants |
| `scripts/player.gd` | Momentum acceleration, expose `is_sprinting`, landing velocity tracking |
| `scripts/camera.gd` | Camera bob, sprint sway, landing impact dip |
| `shaders/terrain.gdshader` | Palette boost, cel-shading contrast, caustic uniforms + `hash()`/`value_noise()` |
| `scenes/main.tscn` | Foliage material color updates |
| `CLAUDE.md` | Document changes |

---

### Task 1: Vibrant Colors — Terrain Palette & Cel-Shading

**Files:**
- Modify: `shaders/terrain.gdshader:78-116` (fragment + light functions)

Start with colors because they're the simplest and most visually immediate.

- [ ] **Step 1: Update terrain palette colors**

In `shaders/terrain.gdshader`, replace the fragment() color definitions (lines 84-87):

```glsl
// Old:
vec3 shore = vec3(0.91, 0.86, 0.78);
vec3 grass_low = vec3(0.55, 0.75, 0.62);
vec3 grass_high = vec3(0.77, 0.90, 0.82);
vec3 rock = vec3(0.60, 0.60, 0.54);

// New:
vec3 shore = vec3(0.93, 0.84, 0.72);
vec3 grass_low = vec3(0.45, 0.82, 0.55);
vec3 grass_high = vec3(0.72, 0.95, 0.78);
vec3 rock = vec3(0.55, 0.55, 0.48);
```

- [ ] **Step 2: Widen cel-shading contrast**

In `shaders/terrain.gdshader`, replace the light() function (lines 111-116):

```glsl
void light() {
	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float cel = floor(NdotL * 3.0 + 0.3) / 3.0;
	cel = cel * cel;
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * cel;
}
```

The `+ 0.3` (was `+ 0.5`) shifts more surface into shadow. `cel * cel` makes shadows darker while keeping highlights bright.

- [ ] **Step 3: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 4: Commit**

```bash
git add shaders/terrain.gdshader
git commit -m "feat: vibrant terrain palette with wider cel-shading contrast"
```

---

### Task 2: Vibrant Colors — Sun, Fog, and Foliage

**Files:**
- Modify: `scripts/main.gd:16-36` (color constants)
- Modify: `scenes/main.tscn` (foliage material overrides)

- [ ] **Step 1: Update sun and fog constants in main.gd**

Replace the following constants:

```gdscript
# Old → New
const DAY_SUN_ENERGY := 1.5    # was 1.2
const NIGHT_SUN_ENERGY := 0.08  # was 0.15
const DAY_AMBIENT := 0.5        # was 0.4
const NIGHT_AMBIENT := 0.06     # was 0.1
const DAY_FOG := Color(0.75, 0.88, 0.92)    # was (0.85, 0.92, 0.94)
const SUNSET_FOG := Color(0.90, 0.60, 0.40)  # was (0.85, 0.65, 0.5)
const NIGHT_FOG := Color(0.06, 0.08, 0.18)   # was (0.1, 0.12, 0.2)
```

- [ ] **Step 2: Update foliage material colors in main.tscn**

Read `scenes/main.tscn`. Find the ShaderMaterial sub_resources and update `shader_parameter/base_color`:

- `Mat_canopy_dark_multi`: `Color(0.25, 0.55, 0.30, 1)` (was 0.3, 0.5, 0.35)
- `Mat_canopy_mid_multi`: `Color(0.30, 0.65, 0.38, 1)` (was 0.35, 0.58, 0.4)
- `Mat_canopy_dark2_multi`: `Color(0.25, 0.55, 0.30, 1)` (was 0.3, 0.5, 0.35)
- `Mat_rock_multi`: `Color(0.55, 0.55, 0.48, 1)` (was 0.6, 0.6, 0.54)

Note: `main.tscn` may have been re-saved by Godot with UIDs and `unique_id` attributes. Work with whatever format the file is currently in.

- [ ] **Step 3: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 4: Commit**

```bash
git add scripts/main.gd scenes/main.tscn
git commit -m "feat: vibrant sun/fog energy and foliage saturation boost"
```

---

### Task 3: Gerstner Waves — Water Shader

**Files:**
- Modify: `shaders/water.gdshader:1-23` (uniforms + vertex function)
- Modify: `scenes/water.tscn` (subdivisions)

This is the biggest shader change. Replace the entire vertex function with Gerstner wave computation.

- [ ] **Step 1: Update water.tscn subdivisions**

In `scenes/water.tscn`, change:
```
subdivide_width = 64
subdivide_depth = 64
```
To:
```
subdivide_width = 128
subdivide_depth = 128
```

Also remove the `wave_speed` and `wave_height` shader parameters from the ShaderMaterial — they're replaced by hardcoded Gerstner wave parameters in the shader.

- [ ] **Step 2: Rewrite the water shader vertex function**

Replace the entire vertex() function and uniforms section in `shaders/water.gdshader`. Remove `wave_speed` and `wave_height` uniforms. Add the Gerstner wave implementation:

```glsl
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D depth_texture : hint_depth_texture;
uniform vec2 player_xz;
uniform float player_speed : hint_range(0.0, 20.0) = 0.0;
uniform float player_speed_smooth : hint_range(0.0, 20.0) = 0.0;
uniform vec4 water_effect_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Gerstner wave parameters — must match CPU _water_height_at() exactly
const int WAVE_COUNT = 4;
const vec2 WAVE_DIR[4] = {vec2(1.0, 0.0), vec2(0.7, 0.7), vec2(0.3, 1.0), vec2(-0.5, 0.8)};
const float WAVE_AMP[4] = {0.35, 0.20, 0.15, 0.10};
const float WAVE_FREQ[4] = {0.8, 1.2, 1.8, 2.5};
const float WAVE_Q[4] = {0.4, 0.3, 0.3, 0.2};
const float WAVE_SPEED[4] = {1.0, 1.3, 0.9, 1.5};

varying vec3 v_wave_normal;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 displaced = world_pos;
	vec3 wave_normal = vec3(0.0, 1.0, 0.0);

	for (int i = 0; i < WAVE_COUNT; i++) {
		vec2 dir = normalize(WAVE_DIR[i]);
		float phase = WAVE_FREQ[i] * dot(dir, world_pos.xz) + TIME * WAVE_SPEED[i];
		float c = cos(phase);
		float s = sin(phase);

		// Gerstner displacement
		displaced.x += WAVE_Q[i] * WAVE_AMP[i] * dir.x * c;
		displaced.z += WAVE_Q[i] * WAVE_AMP[i] * dir.y * c;
		displaced.y += WAVE_AMP[i] * s;

		// Analytical Gerstner normal
		wave_normal.x -= dir.x * WAVE_FREQ[i] * WAVE_AMP[i] * c;
		wave_normal.z -= dir.y * WAVE_FREQ[i] * WAVE_AMP[i] * c;
		wave_normal.y -= WAVE_Q[i] * WAVE_FREQ[i] * WAVE_AMP[i] * s;
	}

	// Apply displacement in local space
	VERTEX = (inverse(MODEL_MATRIX) * vec4(displaced, 1.0)).xyz;
	NORMAL = normalize(wave_normal);
	v_wave_normal = wave_normal;
}
```

- [ ] **Step 3: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 4: Commit**

```bash
git add shaders/water.gdshader scenes/water.tscn
git commit -m "feat: Gerstner wave system with 4 overlapping ocean waves"
```

---

### Task 4: Water Foam & Depth Gradient

**Files:**
- Modify: `shaders/water.gdshader:62-83` (fragment function)

- [ ] **Step 1: Replace the fragment function**

Rewrite `fragment()` in `shaders/water.gdshader` with the new depth gradient, whitecap foam, and shore foam. Keep existing ripple/foam/tint code intact:

```glsl
void fragment() {
	// Shore blending via depth buffer
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz /= view_pos.w;
	float water_depth = clamp((VERTEX.z - view_pos.z) * 0.4, 0.0, 1.0);

	// Multi-stop depth gradient
	vec3 shallow = vec3(0.55, 0.85, 0.82);
	vec3 mid     = vec3(0.30, 0.65, 0.65);
	vec3 deep    = vec3(0.15, 0.40, 0.50);
	vec3 abyss   = vec3(0.08, 0.20, 0.30);

	vec3 col = shallow;
	col = mix(col, mid, smoothstep(0.0, 0.3, water_depth));
	col = mix(col, deep, smoothstep(0.3, 0.6, water_depth));
	col = mix(col, abyss, smoothstep(0.6, 1.0, water_depth));

	ALBEDO = col;

	// Whitecap foam — where wave surface is steep
	float slope = 1.0 - v_wave_normal.y;
	float whitecap = smoothstep(0.3, 0.6, slope) * value_noise(
		(INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz * 3.0 + TIME * 0.5);
	ALBEDO += vec3(whitecap * 0.6);

	// Shore foam — animated bands near shore
	float shore_dist = 1.0 - water_depth;  // 1.0 at shore, 0.0 deep
	float foam_band1 = smoothstep(0.6, 0.8, shore_dist) *
		(0.5 + 0.5 * sin(shore_dist * 20.0 - TIME * 2.0));
	float foam_band2 = smoothstep(0.7, 0.9, shore_dist) *
		(0.5 + 0.5 * sin(shore_dist * 15.0 - TIME * 1.5 + 1.0));
	float shore_foam = max(foam_band1, foam_band2) *
		value_noise((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz * 5.0);
	ALBEDO += vec3(shore_foam * 0.5);

	// Player ripple rings (preserved from existing)
	vec3 world_pos_frag = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ripple_val = ripple(world_pos_frag.xz);
	ALBEDO += vec3(ripple_val * 0.15);

	// Player foam (preserved from existing)
	float foam_val = foam(world_pos_frag.xz);
	ALBEDO += water_effect_tint.rgb * foam_val * 0.3;

	// Day/night tint (preserved from existing)
	ALBEDO = mix(ALBEDO, ALBEDO * water_effect_tint.rgb, 0.2);

	ALPHA = mix(0.8, 0.95, water_depth);
	METALLIC = 0.1;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
}
```

- [ ] **Step 2: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 3: Commit**

```bash
git add shaders/water.gdshader
git commit -m "feat: whitecap foam, shore foam, and depth color gradient"
```

---

### Task 5: CPU Wave Mirror & Dynamic water_y

**Files:**
- Modify: `scripts/main.gd:38-40` (_ready), add `_water_height_at()`, modify `_process()` lines 95-105

- [ ] **Step 1: Add `_water_height_at()` function to main.gd**

Add this function before the `_ready()` function. It mirrors the shader's Gerstner wave computation exactly — same parameters, same formula:

```gdscript
# Gerstner wave parameters — must match water.gdshader exactly
const WAVE_DIRS: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.7, 0.7), Vector2(0.3, 1.0), Vector2(-0.5, 0.8)]
const WAVE_AMPS: Array[float] = [0.35, 0.20, 0.15, 0.10]
const WAVE_FREQS: Array[float] = [0.8, 1.2, 1.8, 2.5]
const WAVE_SPEEDS: Array[float] = [1.0, 1.3, 0.9, 1.5]

var _water_base_y := 0.0
var _game_time := 0.0

func _water_height_at(x: float, z: float) -> float:
	var h := _water_base_y
	for i in WAVE_DIRS.size():
		var dir := WAVE_DIRS[i].normalized()
		var phase := WAVE_FREQS[i] * (dir.x * x + dir.y * z) + _game_time * WAVE_SPEEDS[i]
		h += WAVE_AMPS[i] * sin(phase)
	return h
```

- [ ] **Step 2: Update `_ready()` to store water base Y**

Replace `player.water_y = $Water.global_position.y` with:
```gdscript
	_water_base_y = $Water.global_position.y
```

- [ ] **Step 3: Update `_process()` for dynamic water_y**

At the top of `_process()`, after `_time_of_day` update, add:
```gdscript
	_game_time += delta
	player.water_y = _water_height_at(player.global_position.x, player.global_position.z)
```

- [ ] **Step 4: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 5: Commit**

```bash
git add scripts/main.gd
git commit -m "feat: CPU Gerstner wave mirror with per-frame water_y"
```

---

### Task 6: Underwater Effects

**Files:**
- Modify: `scripts/main.gd` (underwater blend + caustic uniforms)
- Modify: `shaders/terrain.gdshader` (caustic pattern + hash/value_noise functions)

- [ ] **Step 1: Add underwater detection to main.gd**

Add instance variables after the existing ones:
```gdscript
var _underwater_blend := 0.0
```

In `_process()`, after the fog section (after `env.environment.fog_light_color = fog_color`), add the underwater blend block. This must access the camera node — add `@onready var camera_pivot: Node3D = $Player/CameraPivot` if not already present, and get the Camera3D:

```gdscript
	# Underwater detection
	var cam_pos := $Player/CameraPivot/Camera3D.global_position
	var cam_water_y := _water_height_at(cam_pos.x, cam_pos.z)
	var target_blend := 1.0 if cam_pos.y < cam_water_y else 0.0
	_underwater_blend = lerpf(_underwater_blend, target_blend, 1.0 - exp(-delta * 8.0))

	# Underwater fog/ambient override (blends with day/night values computed above)
	if _underwater_blend > 0.01:
		var underwater_fog := Color(0.05, 0.18, 0.25)
		fog_color = fog_color.lerp(underwater_fog, _underwater_blend)
		env.environment.fog_light_color = fog_color
		env.environment.fog_density = lerpf(0.003, 0.05, _underwater_blend)
		var underwater_ambient := Color(0.15, 0.35, 0.45)
		env.environment.ambient_light_color = Color.WHITE.lerp(underwater_ambient, _underwater_blend)
	else:
		env.environment.fog_density = 0.003
		env.environment.ambient_light_color = Color.WHITE

	# Caustic uniform on terrain shader
	var terrain_mat: ShaderMaterial = terrain.mesh.material_override
	if terrain_mat:
		terrain_mat.set_shader_parameter("caustic_strength", _underwater_blend)
		terrain_mat.set_shader_parameter("water_y_uniform", _water_base_y)
```

- [ ] **Step 2: Add caustic pattern to terrain.gdshader**

Add two new uniforms after the existing ones (after line 8):
```glsl
uniform float caustic_strength : hint_range(0.0, 1.0) = 0.0;
uniform float water_y_uniform = -10.0;
```

Add `hash()` and `value_noise()` functions (copy from `water.gdshader`) before the `terrain_height()` function:
```glsl
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
```

In `fragment()`, after the painted variation block (after line 101, `col += vec3(variation...)`), add caustic application:
```glsl
	// Underwater caustics
	if (caustic_strength > 0.0 && v_world_pos.y < water_y_uniform) {
		float caustic = value_noise(v_world_pos.xz * 2.0 + TIME * vec2(0.3, 0.2));
		caustic = pow(caustic, 2.0) * 0.4;
		col += vec3(caustic) * caustic_strength;
	}
```

- [ ] **Step 3: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 4: Commit**

```bash
git add scripts/main.gd shaders/terrain.gdshader
git commit -m "feat: underwater fog override and terrain caustic patterns"
```

---

### Task 7: Bouncier Movement — Player Momentum & Sprint Exposure

**Files:**
- Modify: `scripts/player.gd:3-9` (constants), `scripts/player.gd:42-84` (movement block)

- [ ] **Step 1: Promote sprinting to instance variable**

Add after the existing instance variables (after `const WET_DRY_TIME := 3.0`, line 36):
```gdscript
var is_sprinting := false
var _prev_velocity_y := 0.0
```

- [ ] **Step 2: Update acceleration constant**

Change line 7:
```gdscript
@export var acceleration := 8.0  # was 12.0 — slower ramp-up for momentum feel
```

- [ ] **Step 3: Replace movement code**

In `_physics_process()`, replace the sprinting local and speed calculation (lines 59-60):
```gdscript
	# Old:
	var sprinting := Input.is_action_pressed("sprint")
	var speed := move_speed * (sprint_multiplier if sprinting else 1.0)

	# New:
	is_sprinting = Input.is_action_pressed("sprint")
	var speed := move_speed * (sprint_multiplier if is_sprinting else 1.0)
```

Replace the horizontal movement block (lines 76-84):
```gdscript
	# --- Horizontal movement (exponential ease-in for momentum) ---
	var target_vel := wish_dir * speed
	if wish_dir.length() > 0.0:
		var accel_weight := 1.0 - exp(-acceleration * 0.5 * delta)
		velocity.x = lerpf(velocity.x, target_vel.x, accel_weight)
		velocity.z = lerpf(velocity.z, target_vel.z, accel_weight)
		# Rotate model to face movement direction
		var target_angle := atan2(wish_dir.x, wish_dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta * move_speed)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta * move_speed)
```

- [ ] **Step 4: Track pre-move velocity for landing detection**

Before `move_and_slide()` (line 99), add:
```gdscript
	_prev_velocity_y = velocity.y
```

- [ ] **Step 5: Update all remaining `sprinting` references to `is_sprinting`**

In the walk animation section (line 104):
```gdscript
		var anim_speed := 8.0 if is_sprinting else 5.0
```

- [ ] **Step 6: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 7: Commit**

```bash
git add scripts/player.gd
git commit -m "feat: momentum acceleration and exposed sprint state"
```

---

### Task 8: Camera Bob, Sprint Sway & Landing Impact

**Files:**
- Modify: `scripts/camera.gd` (add bob, sway, landing dip)

- [ ] **Step 1: Add bob/sway/landing variables and update _process()**

Read the current `scripts/camera.gd`. Add instance variables and modify `_process()`. The player is accessed via the parent — `camera.gd` is on `$Player/CameraPivot`, so the player is `get_parent()`.

Add variables after `_pitch` (after line 11):
```gdscript
var _bob_time := 0.0
var _bob_amplitude := 0.0
var _landing_dip := 0.0
```

Rewrite `_process()` to include bob, sway, and landing:

```gdscript
func _process(delta: float) -> void:
	rotation.y = _yaw

	# Get player state
	var player := get_parent() as CharacterBody3D
	var h_speed := Vector2(player.velocity.x, player.velocity.z).length()

	# Camera bob — own timer to avoid snap on idle
	var target_amp := 0.08 if player.is_sprinting else 0.04 if h_speed > 0.5 else 0.0
	_bob_amplitude = lerpf(_bob_amplitude, target_amp, 1.0 - exp(-delta * 8.0))
	if h_speed > 0.5 and player.is_on_floor():
		_bob_time += delta * (8.0 if player.is_sprinting else 5.0)
	var bob_y := sin(_bob_time * 2.0) * _bob_amplitude
	var bob_x := sin(_bob_time) * _bob_amplitude * 0.5

	# Landing impact dip
	if player.is_on_floor() and player._prev_velocity_y < -3.0:
		var impact := clampf(absf(player._prev_velocity_y) / 15.0, 0.0, 1.0)
		_landing_dip = impact * 0.3
	_landing_dip = lerpf(_landing_dip, 0.0, 1.0 - exp(-delta * 10.0))

	# Sprint sway (roll)
	var target_roll := sin(_bob_time) * deg_to_rad(2.0) if player.is_sprinting and h_speed > 0.5 else 0.0
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, 8.0 * delta)

	# Camera position with bob and landing dip
	var offset := Vector3(bob_x, height + bob_y - _landing_dip, distance)
	offset = offset.rotated(Vector3.RIGHT, -_pitch)
	var target_pos := offset
	camera.position = camera.position.lerp(target_pos, follow_speed * delta)

	# Terrain avoidance — keep camera above ground
	var space_state := get_world_3d().direct_space_state
	if space_state:
		var cam_global := camera.global_position
		var query := PhysicsRayQueryParameters3D.create(
			cam_global + Vector3.UP * 10.0, cam_global + Vector3.DOWN * 10.0)
		var result := space_state.intersect_ray(query)
		if result and cam_global.y < result.position.y + 1.0:
			camera.global_position.y = result.position.y + 1.0

	camera.look_at(global_position, Vector3.UP)
```

- [ ] **Step 2: Verify project loads**

Run: `cd /Users/hunterbastian/Desktop/Code/games/active/yama && godot --headless --quit`
Expected: Exit code 0

- [ ] **Step 3: Commit**

```bash
git add scripts/camera.gd
git commit -m "feat: camera bob, sprint sway, and landing impact dip"
```

---

### Task 9: CLAUDE.md Updates

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

Update water.gdshader description:
Change `vertex wave displacement, depth-buffer shore blending, metallic/specular, player ripple rings, foam trail with day/night tinting`
To: `4 Gerstner ocean waves, whitecap + shore foam, multi-stop depth gradient, player ripple rings, foam trail with day/night tinting`

Update main.gd description — add `, CPU wave mirror, underwater detection`

Update terrain.gdshader description — add `, underwater caustic patterns`

Update Key patterns — add:
```
- **CPU-GPU wave mirror**: main.gd `_water_height_at()` must match `water.gdshader` Gerstner parameters exactly (same dirs, amps, freqs, speeds). Updates `player.water_y` per-frame for dynamic wading
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with Sea of Thieves feel changes"
```

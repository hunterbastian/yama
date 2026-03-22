# Water Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Ghibli-style wading to yama — walk into water, slow down, see ripples/foam, splash particles, and wet leg darkening.

**Architecture:** Height comparison against the water plane (y = -0.2). Player script computes depth each physics frame and drives speed scaling, shader uniforms, particle emission, and wet effect. All water visuals sync with the day/night cycle.

**Tech Stack:** Godot 4.6, GDScript, GLSL spatial shaders, GPUParticles3D

**Spec:** `docs/superpowers/specs/2026-03-22-water-interactions-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/player.gd` | Modify | Wading state, depth tiers, speed scaling, wet timer, particle burst sync |
| `scripts/main.gd` | Modify | Set player.water_y, pass player data to water shader, smooth speed, day/night tint |
| `shaders/water.gdshader` | Modify | Ripple rings + foam around player position |
| `shaders/character_wet.gdshader` | Create | Wet darkening below water line for leg meshes |
| `scenes/player.tscn` | Modify | Add GPUParticles3D node, swap leg materials to ShaderMaterial |

---

### Task 1: Wading State Detection

**Files:**
- Modify: `scripts/player.gd` (lines 1-9 exports, lines 27-71 physics process)
- Modify: `scripts/main.gd` (line 37 `_ready()`)

- [ ] **Step 1: Add wading variables to player.gd**

At the top of `player.gd`, after the existing exports (line 9), add:

```gdscript
# Wading
var water_y := 0.0
var water_depth := 0.0
var is_wading := false
const ANKLE_DEPTH := 0.3
const KNEE_DEPTH := 0.6
```

- [ ] **Step 2: Add wading speed multiplier to _physics_process**

In `_physics_process`, after the line `var speed := move_speed * (sprint_multiplier if sprinting else 1.0)` (line 45), add:

```gdscript
	# Wading slowdown
	water_depth = water_y - global_position.y
	is_wading = water_depth > 0.0
	if is_wading:
		var wade_mult := 1.0
		if water_depth > KNEE_DEPTH:
			wade_mult = 0.4
		elif water_depth > ANKLE_DEPTH:
			wade_mult = 0.65
		else:
			wade_mult = 0.85
		speed *= wade_mult
```

- [ ] **Step 3: Disable jump at waist depth**

In the jump section (line 67), change the jump condition from:

```gdscript
	if Input.is_action_just_pressed("jump") and _coyote_timer > 0.0:
```

to:

```gdscript
	if Input.is_action_just_pressed("jump") and _coyote_timer > 0.0 and water_depth < KNEE_DEPTH:
```

- [ ] **Step 4: Set water_y from main.gd**

In `main.gd` `_ready()` (line 36), after the player position line, add:

```gdscript
	player.water_y = $Water.global_position.y
```

The Water node is at y = -0.2 (from `water.tscn` line 19).

- [ ] **Step 5: Verify in Godot editor**

Run: `godot --headless --quit` from the project root to verify no parse errors.

Open in Godot editor and run. Walk into the ocean — player should visibly slow down at different depths. Jump should be disabled when waist-deep.

- [ ] **Step 6: Commit**

```bash
git add scripts/player.gd scripts/main.gd
git commit -m "feat: wading state detection with depth-based speed scaling"
```

---

### Task 2: Water Shader Ripples

**Files:**
- Modify: `shaders/water.gdshader` (add uniforms + ripple function)
- Modify: `scripts/main.gd` (pass player position/speed to water shader)

- [ ] **Step 1: Add ripple uniforms to water.gdshader**

After the existing uniforms (line 8), add:

```glsl
uniform vec2 player_xz;
uniform float player_speed : hint_range(0.0, 20.0) = 0.0;
```

- [ ] **Step 2: Write ripple function**

Before `void fragment()` (line 21), add:

```glsl
float ripple(vec2 frag_xz) {
	float dist = length(frag_xz - player_xz);
	// 3 expanding rings using TIME
	float ring1 = sin((dist - TIME * 2.0) * 8.0) * exp(-dist * 0.5);
	float ring2 = sin((dist - TIME * 2.5) * 6.0) * exp(-dist * 0.6);
	float ring3 = sin((dist - TIME * 1.5) * 10.0) * exp(-dist * 0.7);
	float rings = (ring1 + ring2 + ring3) * 0.33;
	// Fade with distance from player, scale with speed
	float fade = exp(-dist * 0.3) * clamp(player_speed * 0.15, 0.0, 1.0);
	return rings * fade;
}
```

- [ ] **Step 3: Apply ripple in fragment shader**

In `void fragment()`, after the existing `ALBEDO = mix(...)` line (line 28), add:

```glsl
	// Player ripple rings
	vec3 world_pos_frag = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ripple_val = ripple(world_pos_frag.xz);
	ALBEDO += vec3(ripple_val * 0.15);
```

- [ ] **Step 4: Pass player data from main.gd**

In `main.gd`, add an `@onready` reference after the existing ones (line 9):

```gdscript
@onready var water: MeshInstance3D = $Water
```

In `_process()`, after the volumetric fog `if fog_mat:` block closes (after the `fog_mat.set_shader_parameter` line), and before the Sun light section (`# Sun light`), add:

```gdscript
	# Water shader — player ripples
	var water_mat: ShaderMaterial = water.material_override
	if water_mat:
		water_mat.set_shader_parameter("player_xz", Vector2(player.global_position.x, player.global_position.z))
		var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
		water_mat.set_shader_parameter("player_speed", h_speed)
```

- [ ] **Step 5: Verify**

Run: `godot --headless --quit` to check for parse errors.

Open in Godot and run. Walk near water — concentric rings should radiate from player position. Standing still = no ripples.

- [ ] **Step 6: Commit**

```bash
git add shaders/water.gdshader scripts/main.gd
git commit -m "feat: water shader ripple rings around player"
```

---

### Task 3: Water Shader Foam

**Files:**
- Modify: `shaders/water.gdshader` (add foam function + day/night tint)
- Modify: `scripts/main.gd` (add smooth speed + tint uniforms)

- [ ] **Step 1: Add foam uniforms to water.gdshader**

After the `player_speed` uniform added in Task 2, add:

```glsl
uniform float player_speed_smooth : hint_range(0.0, 20.0) = 0.0;
uniform vec4 water_effect_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
```

- [ ] **Step 2: Write foam function**

The spec says "existing simplex noise" but the water shader does not include simplex. Rather than copying the full Ashima Arts implementation (60+ lines), we use cheaper value noise — visually equivalent for foam texture at a fraction of the cost. Add before `void fragment()`:

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

float foam(vec2 frag_xz) {
	float dist = length(frag_xz - player_xz);
	// Foam radius shrinks as speed decays
	float radius = player_speed_smooth * 0.3;
	float foam_mask = smoothstep(radius, radius * 0.3, dist);
	// Noise texture so it looks organic
	float noise = value_noise(frag_xz * 3.0 + TIME * 0.2);
	return foam_mask * noise * clamp(player_speed_smooth * 0.2, 0.0, 1.0);
}
```

- [ ] **Step 3: Apply foam and tint in fragment shader**

After the ripple line added in Task 2 (`ALBEDO += vec3(ripple_val * 0.15)`), add:

```glsl
	// Player foam
	float foam_val = foam(world_pos_frag.xz);
	ALBEDO += water_effect_tint.rgb * foam_val * 0.3;
	// Tint ripples by day/night too
	ALBEDO = mix(ALBEDO, ALBEDO * water_effect_tint.rgb, 0.2);
```

- [ ] **Step 4: Add smooth speed and tint to main.gd**

In `main.gd`, add a new variable after the `_time_of_day` declaration (line 11):

```gdscript
var _player_speed_smooth := 0.0
```

In `_process()`, in the water shader section added in Task 2, expand it to:

```gdscript
	# Water shader — player ripples and foam
	var water_mat: ShaderMaterial = water.material_override
	if water_mat:
		water_mat.set_shader_parameter("player_xz", Vector2(player.global_position.x, player.global_position.z))
		var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
		water_mat.set_shader_parameter("player_speed", h_speed)
		# Smooth speed for foam fade-out (~2 second decay)
		_player_speed_smooth = lerpf(_player_speed_smooth, h_speed, 1.0 - exp(-delta * 1.5))
		water_mat.set_shader_parameter("player_speed_smooth", _player_speed_smooth)
		# Day/night tint from fog palette
		water_mat.set_shader_parameter("water_effect_tint", fog_color)
```

Note: `fog_color` is the variable already computed on line 82-83 of main.gd for the day/night cycle.

- [ ] **Step 5: Verify**

Run `godot --headless --quit`. Open in Godot and run. Walk in water — foam should appear around the player, fade out ~2 seconds after stopping. At sunset, foam should shift warm.

- [ ] **Step 6: Commit**

```bash
git add shaders/water.gdshader scripts/main.gd
git commit -m "feat: water foam trail with day/night tinting"
```

---

### Task 4: Splash Particles

**Files:**
- Modify: `scenes/player.tscn` (add GPUParticles3D node)
- Modify: `scripts/player.gd` (particle emission sync)

- [ ] **Step 1: Add GPUParticles3D to player.tscn**

Add a new sub_resource for the particle material and a GPUParticles3D node. At the top of `player.tscn`, increment `load_steps` from 9 to 11. After the existing sub_resources, add:

```
[sub_resource type="ParticleProcessMaterial" id="SplashProcess"]
direction = Vector3(0, 1, 0)
spread = 60.0
initial_velocity_min = 2.0
initial_velocity_max = 4.0
gravity = Vector3(0, -10, 0)
scale_min = 0.15
scale_max = 0.3

[sub_resource type="StandardMaterial3D" id="SplashDraw"]
transparency = 1
shading_mode = 0
albedo_color = Color(0.75, 0.88, 0.95, 0.8)
billboard_mode = 3
```

Add the node after the CameraPivot node:

```
[node name="SplashParticles" type="GPUParticles3D" parent="."]
emitting = false
amount = 12
lifetime = 0.5
one_shot = true
explosiveness = 1.0
process_material = SubResource("SplashProcess")
draw_pass_1 = SubResource("Mesh_head")
material_override = SubResource("SplashDraw")
```

Note: reusing `Mesh_head` (SphereMesh, radius 0.22) as the particle draw pass. At 0.15-0.3 scale the droplets are 0.033-0.066 units — visible at third-person camera distance.

- [ ] **Step 2: Add particle references and burst logic to player.gd**

Add an `@onready` reference after the existing ones (line 23):

```gdscript
@onready var splash_particles: GPUParticles3D = $SplashParticles
```

Add a tracking variable after `_walk_time` (line 25):

```gdscript
var _prev_walk_sin := 0.0
```

- [ ] **Step 3: Add footstep burst emission**

In `_physics_process`, inside the walk animation block (the `if h_speed > 0.5 and is_on_floor():` branch), after the `body.position.y = 0.45 + abs(...)` line, add:

```gdscript
		# Splash particles — burst on footstep (sin crosses zero)
		if is_wading:
			var walk_sin := sin(_walk_time)
			if (_prev_walk_sin < 0.0 and walk_sin >= 0.0) or (_prev_walk_sin > 0.0 and walk_sin <= 0.0):
				splash_particles.global_position = Vector3(
					global_position.x, water_y, global_position.z)
				# Scale particle count by depth
				var amount := 4
				if water_depth > KNEE_DEPTH:
					amount = 12
				elif water_depth > ANKLE_DEPTH:
					amount = 8
				splash_particles.amount = amount
				splash_particles.restart()
				splash_particles.emitting = true
			_prev_walk_sin = walk_sin
```

In the `else` branch (idle/return), after `_walk_time = 0.0`, add:

```gdscript
		_prev_walk_sin = 0.0
```

This prevents a phantom splash burst when re-entering water movement (without the reset, `_walk_time` restarts at 0 but `_prev_walk_sin` retains its old value, causing a false zero-crossing).

Note: line numbers in `player.gd` will have shifted from Task 1's edits. Reference the code content (`body.position.y = 0.45 + abs(...)`) rather than original line numbers.

- [ ] **Step 4: Verify**

Run `godot --headless --quit`. Open in Godot and run. Walk into water — small white-blue droplets should burst upward from the water surface at each footstep. Deeper water = more particles.

- [ ] **Step 5: Commit**

```bash
git add scenes/player.tscn scripts/player.gd
git commit -m "feat: splash particles on water footsteps"
```

---

### Task 5: Character Wet Effect

**Files:**
- Create: `shaders/character_wet.gdshader`
- Modify: `scenes/player.tscn` (swap leg materials)
- Modify: `scripts/player.gd` (wet timer, shader uniforms)

- [ ] **Step 1: Create character_wet.gdshader**

Create `shaders/character_wet.gdshader`:

```glsl
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.45, 0.58, 0.52, 1.0);
uniform float water_y_world = -10.0;
uniform float wet_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = base_color.rgb;

	// Darken fragments below water line
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float below_water = smoothstep(water_y_world + 0.05, water_y_world - 0.05, world_pos.y);
	float wet = below_water * wet_amount;

	ALBEDO *= mix(1.0, 0.7, wet);
	ROUGHNESS = mix(0.8, 1.0, wet);
}
```

Default `water_y_world = -10.0` ensures no darkening when not actively wading.

- [ ] **Step 2: Swap leg materials in player.tscn**

In `player.tscn`, add a new ext_resource for the wet shader. After the existing ext_resources (line 4), add:

```
[ext_resource type="Shader" path="res://shaders/character_wet.gdshader" id="3"]
```

Replace the `Mat_legs` sub_resource (lines 16-17) from:

```
[sub_resource type="StandardMaterial3D" id="Mat_legs"]
albedo_color = Color(0.45, 0.58, 0.52, 1.0)
```

to:

```
[sub_resource type="ShaderMaterial" id="Mat_legs"]
shader = ExtResource("3")
shader_parameter/base_color = Color(0.45, 0.58, 0.52, 1.0)
shader_parameter/water_y_world = -10.0
shader_parameter/wet_amount = 0.0
```

Update `load_steps` from 11 to 12 (adding the shader ext_resource).

- [ ] **Step 3: Add wet timer logic to player.gd**

Add variables after `_prev_walk_sin`:

```gdscript
var _wet_timer := 0.0
const WET_DRY_TIME := 3.0
```

In `_physics_process`, after the splash particles section, add:

```gdscript
	# Wet effect
	if is_wading:
		_wet_timer = WET_DRY_TIME
	elif _wet_timer > 0.0:
		_wet_timer -= delta

	var wet_amount := clampf(_wet_timer / WET_DRY_TIME, 0.0, 1.0)
	var leg_mat_l: ShaderMaterial = left_leg.get_surface_override_material(0)
	var leg_mat_r: ShaderMaterial = right_leg.get_surface_override_material(0)
	if leg_mat_l:
		leg_mat_l.set_shader_parameter("water_y_world", water_y if is_wading else water_y - (WET_DRY_TIME - _wet_timer) * 0.3)
		leg_mat_l.set_shader_parameter("wet_amount", wet_amount)
	if leg_mat_r:
		leg_mat_r.set_shader_parameter("water_y_world", water_y if is_wading else water_y - (WET_DRY_TIME - _wet_timer) * 0.3)
		leg_mat_r.set_shader_parameter("wet_amount", wet_amount)
```

The `water_y - elapsed * 0.3` makes the wet line recede downward as the legs dry.

- [ ] **Step 4: Verify**

Run `godot --headless --quit`. Open in Godot and run. Walk into water — legs should darken below the water surface. Walk out — the darkening should fade over 3 seconds, receding downward.

- [ ] **Step 5: Commit**

```bash
git add shaders/character_wet.gdshader scenes/player.tscn scripts/player.gd
git commit -m "feat: wet darkening on character legs with dry timer"
```

---

### Task 6: Final Integration and Polish

**Files:**
- Review: all modified files
- Modify: `CLAUDE.md` (update shader/script descriptions)

- [ ] **Step 1: Full playtest checklist**

Open in Godot and verify each behavior:
1. Walk into water at different depths — speed scales correctly (ankle/knee/waist)
2. Jump works at ankle/knee, disabled at waist
3. Ripple rings appear around player, scale with speed, disappear when standing still
4. Foam appears when moving in water, fades ~2 seconds after stopping
5. Splash particles burst at footsteps, more particles in deeper water, emit from water surface
6. Legs darken below water line when wading
7. Wet effect persists 3 seconds after leaving water, recedes downward
8. Sprint in water is still faster than walk in water but slower than dry sprint
9. Day/night cycle still works — foam/ripples tint warm at sunset, dim at night
10. Fog shader still works correctly
11. Terrain regeneration (R key) still works — player repositions above terrain

- [ ] **Step 2: Update CLAUDE.md**

In `CLAUDE.md`, update the Scripts and Shaders sections to document new behavior:

Add to the `scripts/player.gd` description:
```
, wading state (depth tiers, speed scaling, jump disable), splash particles, wet timer
```

Add to the `shaders/water.gdshader` description:
```
, player ripple rings, foam trail with day/night tinting
```

Add new entry:
```
- `shaders/character_wet.gdshader` — wet darkening below water line for leg meshes, dry persistence timer
```

Add to Key patterns:
```
- **Wading detection**: player.gd compares `global_position.y` against `water_y` (set by main.gd from Water node). When rivers/lakes are added, swap to Area3D volumes — shader uniforms stay the same
```

- [ ] **Step 3: Final commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with water interaction systems"
```

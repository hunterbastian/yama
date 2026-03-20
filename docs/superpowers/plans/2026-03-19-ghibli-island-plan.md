# Ghibli Island Explorer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a third-person exploration game on a procedural heightmap island with Howl's Countryside Ghibli aesthetics in Godot 4.

**Architecture:** Shader-based terrain (vertex displacement on PlaneMesh) with CPU-mirrored heightmap for collision. CharacterBody3D with orbit camera. All rendering uses custom shaders for the cel-shaded Ghibli look.

**Tech Stack:** Godot 4.6, GDScript, GLSL shaders (Godot Shading Language)

**Mode:** Pair programming — tasks marked 🎮 have sections for the user to write.

---

## File Structure

```
project.godot                    # Project config, input map, window settings
scenes/
  main.tscn                      # Root scene — assembles everything
  terrain.tscn                   # Terrain MeshInstance3D + StaticBody3D
  player.tscn                    # CharacterBody3D + camera rig
  water.tscn                     # Water plane
scripts/
  main.gd                        # Scene assembly, input routing (R to regenerate)
  terrain.gd                     # CPU heightmap generation, collision rebuild
  player.gd                      # Character movement, jump, sprint
  camera.gd                      # Third-person orbit camera
shaders/
  terrain.gdshader               # Vertex displacement + cel-shaded fragment
  water.gdshader                 # Wave displacement + translucent fragment
```

---

### Task 1: Project Skeleton

**Files:**
- Create: `project.godot`
- Create: `scenes/main.tscn`
- Create: `scripts/main.gd`

- [ ] **Step 1: Initialize Godot project**

Create `project.godot` with window size 1280x720, GLES3/Forward+, project name "Ghibli Island".

```ini
; Engine configuration file — project.godot
config_version=5

[application]
config/name="Ghibli Island"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.4", "Forward Plus")

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"

[input]
move_forward={ "deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":119)] }
move_back={ "deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":115)] }
move_left={ "deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":97)] }
move_right={ "deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":100)] }
jump={ "deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":32)] }
sprint={ "deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194325,"key_label":0,"unicode":0)] }
regenerate={ "deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":82,"key_label":0,"unicode":114)] }
```

- [ ] **Step 2: Create minimal main scene and script**

`scripts/main.gd`:
```gdscript
extends Node3D
```

`scenes/main.tscn` — a Node3D root with the script attached. Just enough to open in Godot.

- [ ] **Step 3: Verify project opens**

Run: `godot --headless --quit 2>&1`
Expected: Clean exit, no errors.

- [ ] **Step 4: Commit**

```bash
git add project.godot scenes/ scripts/
git commit -m "feat: project skeleton with input map"
```

---

### Task 2: Terrain Shader 🎮

**Files:**
- Create: `shaders/terrain.gdshader`
- Create: `scenes/terrain.tscn`
- Create: `scripts/terrain.gd`

- [ ] **Step 1: Write the terrain vertex shader**

`shaders/terrain.gdshader` — vertex displacement with 2-octave simplex noise, radial island falloff:

```glsl
shader_type spatial;

uniform float seed : hint_range(0.0, 1000.0) = 0.0;
uniform float height_scale : hint_range(0.0, 30.0) = 12.0;
uniform float noise_scale : hint_range(0.01, 0.2) = 0.05;
uniform float island_radius : hint_range(10.0, 100.0) = 55.0;

// Simplex noise functions go here (Godot doesn't have built-in shader noise)
// We'll use a standard 2D simplex implementation

varying float v_height;
varying vec3 v_world_normal;

// --- snoise2 implementation (standard simplex) ---
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289_2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }

float snoise(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                       -0.577350269189626, 0.024390243902439);
    vec2 i = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289_2(i);
    vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
    vec3 x_ = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x_) - 0.5;
    vec3 ox = floor(x_ + 0.5);
    vec3 a0 = x_ - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    vec3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

float terrain_height(vec2 pos) {
    // Seed offsets sample position — CPU code must mirror this exactly
    vec2 p = pos * noise_scale + vec2(seed, seed);
    float h = snoise(p) * 0.6 + snoise(p * 2.0 + vec2(43.0, 17.0)) * 0.4;

    // Island falloff — distance from center fades to 0
    float dist = length(pos) / island_radius;
    float falloff = 1.0 - smoothstep(0.5, 1.0, dist);

    return h * height_scale * falloff;
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float h = terrain_height(world_pos.xz);
    VERTEX.y += h;
    v_height = h;

    // Compute normal from finite differences
    float eps = 0.5;
    float hL = terrain_height(world_pos.xz + vec2(-eps, 0.0));
    float hR = terrain_height(world_pos.xz + vec2(eps, 0.0));
    float hD = terrain_height(world_pos.xz + vec2(0.0, -eps));
    float hU = terrain_height(world_pos.xz + vec2(0.0, eps));
    NORMAL = normalize(vec3(hL - hR, 2.0 * eps, hD - hU));
    v_world_normal = NORMAL;
}

void fragment() {
    // --- YOUR TURN: Howl's Countryside palette blending ---
    // Blend grass/rock/shore based on v_height and slope (v_world_normal.y)
    // Add cel-shading bands and color noise variation
    // See Step 2 below
    ALBEDO = vec3(0.55, 0.75, 0.62); // placeholder mint green
}
```

- [ ] **Step 2: 🎮 Write the fragment shader (your turn)**

This is the creative part — the Howl's Countryside palette. In `terrain.gdshader`, replace the placeholder `fragment()` with color blending logic:

**Your inputs:**
- `v_height` — terrain height at this pixel (0 = sea level, ~12 = peaks)
- `v_world_normal.y` — slope steepness (1.0 = flat, 0.0 = vertical cliff)

**Palette to implement:**
- Shore (`v_height < 1.0`): `vec3(0.91, 0.86, 0.78)` — sandy warm
- Grass (flat areas): `vec3(0.55, 0.75, 0.62)` → `vec3(0.77, 0.90, 0.82)` — mint gradient by height
- Rock (steep, `normal.y < 0.7`): `vec3(0.60, 0.60, 0.54)` — grey stone

**Techniques to try:**
- `mix()` between colors using `smoothstep()` on height/slope
- Add `snoise(world_pos.xz * 0.3) * 0.05` to each color channel for painted variation
- Cel-shading: quantize the light dot product into 2-3 steps

- [ ] **Step 3: Create terrain scene**

`scenes/terrain.tscn` — MeshInstance3D with PlaneMesh (128x128 subdivisions, size 120x120), ShaderMaterial pointing to `terrain.gdshader`.

`scripts/terrain.gd` — holds reference to shader, exposes `set_seed()`:
```gdscript
extends Node3D

@onready var mesh: MeshInstance3D = $MeshInstance3D

func set_seed(new_seed: float) -> void:
    mesh.material_override.set_shader_parameter("seed", new_seed)
```

- [ ] **Step 4: Add terrain to main scene, verify visually**

Add terrain as a child scene in `scenes/main.tscn` and update `scripts/main.gd`:
```gdscript
extends Node3D

@onready var terrain: Node3D = $Terrain

func _ready() -> void:
    pass
```

The terrain scene node should be named "Terrain" in main.tscn. MeshInstance3D must be at origin (position 0,0,0) — the shader uses MODEL_MATRIX for world-space noise sampling.

Run: `godot --headless --quit 2>&1`
Expected: Clean compilation.

- [ ] **Step 5: Commit**

```bash
git add shaders/ scenes/ scripts/
git commit -m "feat: terrain shader with vertex displacement"
```

---

### Task 3: Terrain Collision

**Files:**
- Modify: `scripts/terrain.gd`

- [ ] **Step 1: Generate CPU-side heightmap**

Add to `scripts/terrain.gd` — a function that mirrors the shader's noise on CPU using Godot's `FastNoiseLite`:

```gdscript
const GRID_SIZE := 128
const TERRAIN_SIZE := 120.0
const HEIGHT_SCALE := 12.0
const ISLAND_RADIUS := 55.0
const NOISE_SCALE := 0.05

var _collision_body: StaticBody3D
var _current_seed: float = 0.0
# Noise instances reused across calls — created once, shared by _build_collision() and get_height_at()
var _noise: FastNoiseLite
var _noise2: FastNoiseLite

func _ready() -> void:
    _setup_noise()
    _build_collision()

func set_seed(new_seed: float) -> void:
    _current_seed = new_seed
    mesh.material_override.set_shader_parameter("seed", new_seed)
    _build_collision()

func _setup_noise() -> void:
    # Fixed seed — we mirror the shader's coordinate-offset approach, not permutation seeding.
    # The shader does: pos * noise_scale + vec2(seed, seed)
    # We do the same: noise.get_noise_2d(wx * NOISE_SCALE + seed, wz * NOISE_SCALE + seed)
    _noise = FastNoiseLite.new()
    _noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    _noise.seed = 0
    _noise.frequency = 1.0  # We apply NOISE_SCALE manually to match shader
    _noise2 = FastNoiseLite.new()
    _noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
    _noise2.seed = 0
    _noise2.frequency = 1.0

func _sample_height(wx: float, wz: float) -> float:
    # Mirror shader: vec2 p = pos * noise_scale + vec2(seed, seed)
    var px := wx * NOISE_SCALE + _current_seed
    var pz := wz * NOISE_SCALE + _current_seed
    # Mirror shader: snoise(p) * 0.6 + snoise(p * 2.0 + vec2(43, 17)) * 0.4
    var h := _noise.get_noise_2d(px, pz) * 0.6 \
           + _noise2.get_noise_2d(px * 2.0 + 43.0, pz * 2.0 + 17.0) * 0.4
    var dist := sqrt(wx * wx + wz * wz) / ISLAND_RADIUS
    var falloff := 1.0 - smoothstep(0.5, 1.0, dist)
    return h * HEIGHT_SCALE * falloff

func _build_collision() -> void:
    if _collision_body:
        _collision_body.queue_free()

    var map_data := PackedFloat32Array()
    map_data.resize((GRID_SIZE + 1) * (GRID_SIZE + 1))
    var half := TERRAIN_SIZE / 2.0
    var step := TERRAIN_SIZE / float(GRID_SIZE)

    for z in range(GRID_SIZE + 1):
        for x in range(GRID_SIZE + 1):
            var wx := -half + x * step
            var wz := -half + z * step
            map_data[z * (GRID_SIZE + 1) + x] = _sample_height(wx, wz)

    var shape := HeightMapShape3D.new()
    shape.map_width = GRID_SIZE + 1
    shape.map_depth = GRID_SIZE + 1
    shape.map_data = map_data

    _collision_body = StaticBody3D.new()
    var col := CollisionShape3D.new()
    col.shape = shape
    _collision_body.add_child(col)
    add_child(_collision_body)

    # Scale collision to match visual mesh
    _collision_body.scale = Vector3(TERRAIN_SIZE / float(GRID_SIZE), 1.0, TERRAIN_SIZE / float(GRID_SIZE))

func get_height_at(world_x: float, world_z: float) -> float:
    return _sample_height(world_x, world_z)
```

- [ ] **Step 2: Verify collision works**

Run: `godot --headless --quit 2>&1`
Expected: No errors. Collision body created.

- [ ] **Step 3: Commit**

```bash
git add scripts/terrain.gd
git commit -m "feat: CPU heightmap collision mirroring shader"
```

---

### Task 4: Character Controller 🎮

**Files:**
- Create: `scenes/player.tscn`
- Create: `scripts/player.gd`
- Create: `scripts/camera.gd`

- [ ] **Step 1: Create player scene**

`scenes/player.tscn` — CharacterBody3D with:
- CapsuleShape3D collision (radius 0.3, height 1.0)
- MeshInstance3D with CapsuleMesh (same dimensions, mint-white material)
- Node3D "CameraPivot" as child (camera attaches here)

- [ ] **Step 2: 🎮 Write the character movement (your turn)**

`scripts/player.gd` — the core movement feel. This is where your taste matters.

**Skeleton provided:**
```gdscript
extends CharacterBody3D

@export var move_speed := 6.0
@export var sprint_multiplier := 1.5
@export var jump_velocity := 8.0
@export var gravity := 20.0
@export var acceleration := 12.0
@export var friction := 10.0

# Coyote time — forgiveness window after walking off an edge
var _coyote_timer := 0.0
const COYOTE_TIME := 0.15

# Apex float — reduced gravity near jump peak for a floaty feel
const APEX_THRESHOLD := 2.0
const APEX_GRAVITY_MULT := 0.4

@onready var camera_pivot: Node3D = $CameraPivot

func _physics_process(delta: float) -> void:
    # YOUR CODE HERE:
    # 1. Get input direction (move_forward/back/left/right)
    # 2. Transform it relative to camera_pivot's Y rotation
    # 3. Apply acceleration toward input direction, friction when no input
    # 4. Handle gravity with apex float (reduce gravity when abs(velocity.y) < APEX_THRESHOLD)
    # 5. Handle jump with coyote time
    # 6. Handle sprint
    # 7. Call move_and_slide()
    pass
```

**Design decisions for you:**
- How snappy should acceleration feel? (high = responsive, low = weighty)
- Should the character rotate to face movement direction? How fast?
- Any visual feedback? (tilt during sprint, squash on land)

- [ ] **Step 3: Write the orbit camera**

`scripts/camera.gd`:
```gdscript
extends Node3D

@export var distance := 5.0
@export var height := 2.0
@export var mouse_sensitivity := 0.003
@export var follow_speed := 8.0
@export var min_pitch := -30.0
@export var max_pitch := 60.0

var _yaw := 0.0
var _pitch := deg_to_rad(15.0)  # Stored in radians — mouse input is also radians

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        _yaw -= event.relative.x * mouse_sensitivity
        _pitch -= event.relative.y * mouse_sensitivity
        _pitch = clampf(_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
    rotation.y = _yaw
    var offset := Vector3(0, height, distance)
    offset = offset.rotated(Vector3.RIGHT, -_pitch)
    var target_pos := offset
    camera.position = camera.position.lerp(target_pos, follow_speed * delta)

    # Terrain avoidance — raycast down from camera to keep above ground
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

- [ ] **Step 4: Add player to main scene**

Add player as a child scene in `scenes/main.tscn` named "Player". Update `scripts/main.gd`:
```gdscript
extends Node3D

@onready var terrain: Node3D = $Terrain
@onready var player: CharacterBody3D = $Player

func _ready() -> void:
    # Spawn player above terrain center
    player.global_position = Vector3(0, terrain.get_height_at(0, 0) + 3.0, 0)
```

- [ ] **Step 5: Verify — character stands on terrain**

Run: `godot --headless --quit 2>&1`
Expected: Clean compilation. Open in editor to test movement.

- [ ] **Step 6: Commit**

```bash
git add scenes/player.tscn scripts/player.gd scripts/camera.gd
git commit -m "feat: character controller with orbit camera"
```

---

### Task 5: Water Plane

**Files:**
- Create: `shaders/water.gdshader`
- Create: `scenes/water.tscn`

- [ ] **Step 1: Write water shader**

`shaders/water.gdshader`:
```glsl
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 water_color : source_color = vec4(0.66, 0.85, 0.92, 0.8);
uniform vec4 deep_color : source_color = vec4(0.35, 0.55, 0.70, 0.95);
uniform sampler2D depth_texture : hint_depth_texture;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.4;
uniform float wave_height : hint_range(0.0, 1.0) = 0.15;

void vertex() {
    float wave = sin(VERTEX.x * 0.5 + TIME * wave_speed) * cos(VERTEX.z * 0.3 + TIME * wave_speed * 0.7);
    VERTEX.y += wave * wave_height;
    // Recompute normal for wave
    float eps = 0.5;
    float hL = sin((VERTEX.x - eps) * 0.5 + TIME * wave_speed) * cos(VERTEX.z * 0.3 + TIME * wave_speed * 0.7) * wave_height;
    float hR = sin((VERTEX.x + eps) * 0.5 + TIME * wave_speed) * cos(VERTEX.z * 0.3 + TIME * wave_speed * 0.7) * wave_height;
    float hD = sin(VERTEX.x * 0.5 + TIME * wave_speed) * cos((VERTEX.z - eps) * 0.3 + TIME * wave_speed * 0.7) * wave_height;
    float hU = sin(VERTEX.x * 0.5 + TIME * wave_speed) * cos((VERTEX.z + eps) * 0.3 + TIME * wave_speed * 0.7) * wave_height;
    NORMAL = normalize(vec3(hL - hR, 2.0 * eps, hD - hU));
}

void fragment() {
    // Depth-based shore blending using Godot 4 Forward+ depth texture
    float depth_raw = texture(depth_texture, SCREEN_UV).r;
    vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
    vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
    view_pos.xyz /= view_pos.w;
    // Compare scene depth vs water surface depth (both in view space)
    float water_depth = clamp((VERTEX.z - view_pos.z) * 0.15, 0.0, 1.0);
    ALBEDO = mix(water_color.rgb, deep_color.rgb, water_depth);
    ALPHA = mix(water_color.a, deep_color.a, water_depth);
    METALLIC = 0.1;
    ROUGHNESS = 0.05;
    SPECULAR = 0.8;
}
```

- [ ] **Step 2: Create water scene**

`scenes/water.tscn` — MeshInstance3D with PlaneMesh (size 300x300, subdivisions 64x64), ShaderMaterial with `water.gdshader`. Position at y = -0.2 (slightly below terrain sea level).

- [ ] **Step 3: Add to main scene, verify**

Run: `godot --headless --quit 2>&1`
Expected: Clean compilation.

- [ ] **Step 4: Commit**

```bash
git add shaders/water.gdshader scenes/water.tscn
git commit -m "feat: animated water plane with wave shader"
```

---

### Task 6: Environment — Sky, Fog, Lighting

**Files:**
- Modify: `scenes/main.tscn`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Set up environment in main scene**

Add to `scripts/main.gd` or directly in scene:
- `WorldEnvironment` with:
  - `ProceduralSkyMaterial` — top color `#a8d8ea`, horizon `#e8f4f0`, ground `#c5e6d0`
  - Fog enabled — color `#d8eaf0`, density 0.003, height fog with falloff
  - Ambient light from sky, energy 0.4
  - Tonemap: Filmic
- `DirectionalLight3D`:
  - Rotation: 45° down, 30° to side (golden-hour-ish angle)
  - Color: slightly warm `#fff5e6`
  - Shadow enabled, soft shadows
  - Energy: 1.2

- [ ] **Step 2: Verify the look**

Run: `godot --headless --quit 2>&1`
Expected: Clean compilation. Open in editor — terrain should have fog depth, sky gradient, directional shadows.

- [ ] **Step 3: Commit**

```bash
git add scenes/main.tscn scripts/main.gd
git commit -m "feat: Howl's Countryside environment — sky, fog, lighting"
```

---

### Task 7: Island Regeneration

**Files:**
- Modify: `scripts/main.gd`

- [ ] **Step 1: Wire R key to regenerate**

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("regenerate"):
        var new_seed := randf() * 1000.0
        terrain.set_seed(new_seed)
        # Reposition player above terrain center
        player.global_position = Vector3(0, terrain.get_height_at(0, 0) + 3.0, 0)
        player.velocity = Vector3.ZERO
```

- [ ] **Step 2: Verify — press R, new island appears**

Run: `godot --headless --quit 2>&1`
Expected: Clean compilation. Manual test: press R in running game.

- [ ] **Step 3: Commit**

```bash
git add scripts/main.gd
git commit -m "feat: R key regenerates island with new seed"
```

---

### Task 8: Cel-Shading Polish Pass

**Files:**
- Modify: `shaders/terrain.gdshader`
- Modify: `shaders/water.gdshader`

- [ ] **Step 1: Add cel-shading via light() function**

Add a `light()` function to `terrain.gdshader` — this uses the actual DirectionalLight3D rather than a hardcoded direction:
```glsl
void light() {
    // Cel-shading: quantize NdotL into 3 discrete bands
    float NdotL = max(dot(NORMAL, LIGHT), 0.0);  // Clamp — negative = back-facing, no light
    float cel = floor(NdotL * 3.0 + 0.5) / 3.0;
    DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * cel;
}
```

- [ ] **Step 2: Add rim lighting in fragment()**

Add rim light calculation to the existing `fragment()` function:
```glsl
// In fragment(), after ALBEDO is set:
// Rim light — bright edge on silhouettes facing away from camera
float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
rim = smoothstep(0.5, 1.0, rim);
EMISSION = vec3(0.85, 0.93, 0.95) * rim * 0.3;
```

Note: Use `EMISSION` for rim light, not `ALBEDO +=`. EMISSION bypasses the `light()` function and glows independently — which is the correct behavior for a rim highlight.

- [ ] **Step 3: Verify the Ghibli look**

Open in editor. Terrain should have visible light banding and bright rim edges. Adjust band count and rim intensity to taste.

- [ ] **Step 4: Commit**

```bash
git add shaders/
git commit -m "feat: cel-shading and rim lighting — Ghibli polish"
```

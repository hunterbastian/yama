extends CharacterBody3D

@export var move_speed := 6.0
@export var sprint_multiplier := 1.5
@export var jump_velocity := 8.0
@export var gravity := 20.0
@export var acceleration := 8.0
@export var friction := 10.0
@export var rotation_speed := 10.0

# Wading
var water_y := 0.0
var water_depth := 0.0
var is_wading := false
const ANKLE_DEPTH := 0.3
const KNEE_DEPTH := 0.6

# Coyote time — forgiveness window after walking off an edge
var _coyote_timer := 0.0
const COYOTE_TIME := 0.15

# Apex float — reduced gravity near jump peak for a floaty feel
const APEX_THRESHOLD := 2.0
const APEX_GRAVITY_MULT := 0.4

@onready var camera_pivot: Node3D = $CameraPivot
@onready var model: Node3D = $CharacterModel
@onready var left_leg: MeshInstance3D = $CharacterModel/LeftLeg
@onready var right_leg: MeshInstance3D = $CharacterModel/RightLeg
@onready var body: MeshInstance3D = $CharacterModel/Body
@onready var splash_particles: GPUParticles3D = $SplashParticles

var _walk_time := 0.0
var _prev_walk_sin := 0.0
var _wet_timer := 0.0
const WET_DRY_TIME := 3.0

var is_sprinting := false
var _prev_velocity_y := 0.0

func _ready() -> void:
	left_leg.set_surface_override_material(0, left_leg.get_surface_override_material(0).duplicate())
	right_leg.set_surface_override_material(0, right_leg.get_surface_override_material(0).duplicate())

func _physics_process(delta: float) -> void:
	# --- Input ---
	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	)

	# Camera-relative direction
	var cam_basis := camera_pivot.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()

	var wish_dir := (forward * -input_dir.y + right * input_dir.x).normalized() if input_dir.length() > 0.1 else Vector3.ZERO
	is_sprinting = Input.is_action_pressed("sprint")
	var speed := move_speed * (sprint_multiplier if is_sprinting else 1.0)

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

	# --- Gravity with apex float ---
	if not is_on_floor():
		var grav_mult := APEX_GRAVITY_MULT if absf(velocity.y) < APEX_THRESHOLD else 1.0
		velocity.y -= gravity * grav_mult * delta
		_coyote_timer -= delta
	else:
		_coyote_timer = COYOTE_TIME

	# --- Jump with coyote time ---
	if Input.is_action_just_pressed("jump") and _coyote_timer > 0.0 and water_depth < KNEE_DEPTH:
		velocity.y = jump_velocity
		_coyote_timer = 0.0

	_prev_velocity_y = velocity.y
	move_and_slide()

	# --- Walk animation ---
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if h_speed > 0.5 and is_on_floor():
		var anim_speed := 8.0 if is_sprinting else 5.0
		_walk_time += delta * anim_speed
		var swing := sin(_walk_time) * 0.4
		# Legs swing forward/backward
		left_leg.rotation.x = swing
		right_leg.rotation.x = -swing
		# Subtle body bob
		body.position.y = 0.45 + abs(sin(_walk_time * 2.0)) * 0.03
		# Splash particles — burst on footstep (sin crosses zero)
		var walk_sin := sin(_walk_time)
		if is_wading:
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
	else:
		# Return to idle
		_walk_time = 0.0
		_prev_walk_sin = 0.0
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, 8.0 * delta)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, 8.0 * delta)
		body.position.y = lerp(body.position.y, 0.45, 8.0 * delta)

	# Wet effect
	if is_wading:
		_wet_timer = WET_DRY_TIME
	elif _wet_timer > 0.0:
		_wet_timer -= delta

	var wet_amount := clampf(_wet_timer / WET_DRY_TIME, 0.0, 1.0)
	var effective_water_y := water_y if is_wading else water_y - (WET_DRY_TIME - _wet_timer) * 0.3
	var leg_mat_l: ShaderMaterial = left_leg.get_surface_override_material(0)
	var leg_mat_r: ShaderMaterial = right_leg.get_surface_override_material(0)
	if leg_mat_l:
		leg_mat_l.set_shader_parameter("water_y_world", effective_water_y)
		leg_mat_l.set_shader_parameter("wet_amount", wet_amount)
	if leg_mat_r:
		leg_mat_r.set_shader_parameter("water_y_world", effective_water_y)
		leg_mat_r.set_shader_parameter("wet_amount", wet_amount)

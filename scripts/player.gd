extends CharacterBody3D

@export var move_speed := 6.0
@export var sprint_multiplier := 1.5
@export var jump_velocity := 8.0
@export var gravity := 20.0
@export var acceleration := 12.0
@export var friction := 10.0
@export var rotation_speed := 10.0

# Coyote time — forgiveness window after walking off an edge
var _coyote_timer := 0.0
const COYOTE_TIME := 0.15

# Apex float — reduced gravity near jump peak for a floaty feel
const APEX_THRESHOLD := 2.0
const APEX_GRAVITY_MULT := 0.4

@onready var camera_pivot: Node3D = $CameraPivot
@onready var mesh: MeshInstance3D = $MeshInstance3D

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
	var sprinting := Input.is_action_pressed("sprint")
	var speed := move_speed * (sprint_multiplier if sprinting else 1.0)

	# --- Horizontal movement ---
	if wish_dir.length() > 0.0:
		velocity.x = move_toward(velocity.x, wish_dir.x * speed, acceleration * delta * speed)
		velocity.z = move_toward(velocity.z, wish_dir.z * speed, acceleration * delta * speed)
		# Rotate character to face movement direction
		var target_angle := atan2(wish_dir.x, wish_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta * speed)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta * speed)

	# --- Gravity with apex float ---
	if not is_on_floor():
		var grav_mult := APEX_GRAVITY_MULT if absf(velocity.y) < APEX_THRESHOLD else 1.0
		velocity.y -= gravity * grav_mult * delta
		_coyote_timer -= delta
	else:
		_coyote_timer = COYOTE_TIME

	# --- Jump with coyote time ---
	if Input.is_action_just_pressed("jump") and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_coyote_timer = 0.0

	move_and_slide()

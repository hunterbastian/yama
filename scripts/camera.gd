extends Node3D

@export var distance := 5.0
@export var height := 2.0
@export var mouse_sensitivity := 0.003
@export var follow_speed := 8.0
@export var min_pitch := -30.0
@export var max_pitch := 60.0

var _yaw := 0.0
var _pitch := deg_to_rad(15.0)
var _bob_time := 0.0
var _bob_amplitude := 0.0
var _landing_dip := 0.0
var first_person := false

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
	if event.is_action_pressed("toggle_camera"):
		first_person = not first_person
		var player := get_parent() as CharacterBody3D
		# Hide/show character model
		var model := player.get_node("CharacterModel")
		if model:
			model.visible = not first_person

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

	# Camera position — first person vs third person
	var target_dist := 0.0 if first_person else distance
	var target_height := 0.8 if first_person else height

	var offset := Vector3(bob_x, target_height + bob_y - _landing_dip, target_dist)
	offset = offset.rotated(Vector3.RIGHT, -_pitch)
	var target_pos := offset
	camera.position = camera.position.lerp(target_pos, follow_speed * delta)

	# Terrain avoidance — only in third person
	if not first_person:
		var space_state := get_world_3d().direct_space_state
		if space_state:
			var cam_global := camera.global_position
			var query := PhysicsRayQueryParameters3D.create(
				cam_global + Vector3.UP * 10.0, cam_global + Vector3.DOWN * 10.0)
			var result := space_state.intersect_ray(query)
			if result and cam_global.y < result.position.y + 1.0:
				camera.global_position.y = result.position.y + 1.0

	# Look direction — first person looks forward, third person looks at player
	if first_person:
		camera.rotation.x = _pitch
		# Don't use look_at in first person — pitch is set directly
	else:
		camera.look_at(global_position, Vector3.UP)

extends Node3D

@export var distance := 5.0
@export var height := 2.0
@export var mouse_sensitivity := 0.003
@export var follow_speed := 8.0
@export var min_pitch := -30.0
@export var max_pitch := 60.0

var _yaw := 0.0
var _pitch := deg_to_rad(15.0)

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

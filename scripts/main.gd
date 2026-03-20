extends Node3D

@onready var terrain: Node3D = $Terrain
@onready var player: CharacterBody3D = $Player

func _ready() -> void:
	player.global_position = Vector3(0, terrain.get_height_at(0, 0) + 3.0, 0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate"):
		var new_seed := randf() * 1000.0
		terrain.set_seed(new_seed)
		player.global_position = Vector3(0, terrain.get_height_at(0, 0) + 3.0, 0)
		player.velocity = Vector3.ZERO

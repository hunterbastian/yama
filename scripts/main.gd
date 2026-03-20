extends Node3D

@onready var terrain: Node3D = $Terrain
@onready var player: CharacterBody3D = $Player

func _ready() -> void:
	player.global_position = Vector3(0, terrain.get_height_at(0, 0) + 3.0, 0)

extends Node3D

@onready var mesh: MeshInstance3D = $MeshInstance3D

func set_seed(new_seed: float) -> void:
	mesh.material_override.set_shader_parameter("seed", new_seed)

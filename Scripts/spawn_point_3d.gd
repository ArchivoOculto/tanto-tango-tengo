extends WarpTarget3D
class_name SpawnPoint3D

## Punto de destino nombrado, usado por WarpZone3D en modo EXTERNAL_SCENE.
## Hereda 'camera_zone' de WarpTarget3D: asignalo si este punto cae dentro
## de una CameraZone3D de la escena destino (lo habitual).

@export var spawn_id: StringName = &"default"


func _enter_tree() -> void:
	add_to_group("spawn_point")

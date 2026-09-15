extends Marker3D
class_name SpawnPoint3D

## Punto de destino nombrado. Colocá uno en cada escena a la que el jugador
## pueda llegar mediante un WarpZone3D en modo EXTERNAL_SCENE. El 'spawn_id'
## es lo único que conecta un WarpZone3D con su destino real: así ninguna
## escena necesita conocer a la otra directamente.

@export var spawn_id: StringName = &"default"


func _enter_tree() -> void:
	add_to_group("spawn_point")

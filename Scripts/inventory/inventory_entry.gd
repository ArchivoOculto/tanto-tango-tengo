extends RefCounted
class_name InventoryEntry

## Un ítem dentro del inventario, junto con lo necesario para mostrarlo y para devolverlo al mundo.

var item: ItemData
## InteractableObject del que salió (para poder soltarlo de nuevo en el mundo). Puede ser null.
var source: Node
## Clon visual (desconectado del árbol) para la vista previa 3D, y su volumen.
var template: Node3D
var bounds: AABB = AABB()


func _init(p_item: ItemData = null, p_source: Node = null, p_template: Node3D = null, p_bounds: AABB = AABB()) -> void:
	item = p_item
	source = p_source
	template = p_template
	bounds = p_bounds


## Libera el clon visual. Se llama al quitar la entrada o al reiniciar.
func dispose() -> void:
	if is_instance_valid(template):
		template.free()
	template = null

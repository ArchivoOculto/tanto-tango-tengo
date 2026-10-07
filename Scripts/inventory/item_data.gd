extends Resource
class_name ItemData

## Definición de un ítem del inventario.
##
## Se crea como recurso desde el editor (clic derecho en el FileSystem > Create New > Resource >
## ItemData) y se asigna en el campo "Item" de un InteractableObject para que ese objeto se pueda
## guardar. Las acciones que dependen de un ítem (ObjectAction.required_item) apuntan al mismo recurso.
##
## Para un ítem con lógica propia, crear un script que herede de ItemData y agregarle variables:
## el inventario y los menús lo tratan igual que a uno común.

## Identificador único del ítem (ej: &"cassette"). Es lo que se compara para saber si "tengo" el ítem.
@export var id: StringName = &""
## Nombre que se muestra en la lista del inventario.
@export var display_name: String = ""
## Texto que se muestra debajo de la vista previa.
@export_multiline var description: String = ""

@export_group("Vista previa")
## Para ítems 2D: imagen que se muestra en el inventario (como los cuadros). Si está asignada,
## tiene prioridad sobre la vista previa 3D.
@export var preview_texture: Texture2D
## Para ítems 3D: escena opcional con las mallas a mostrar. Si queda vacía, se usa un clon del
## objeto del mundo en el momento de guardarlo (lo más cómodo).
@export var preview_scene: PackedScene

@export_group("Características propias")
## Datos libres del ítem (ej: {"tape_id": 1}). Se leen con get_property_or().
@export var properties: Dictionary = {}


## Nombre para mostrar: el 'display_name' o, si está vacío, el id.
func get_label() -> String:
	return display_name if display_name != "" else String(id)


func get_property_or(key: StringName, default: Variant = null) -> Variant:
	return properties.get(key, default)


## Dos referencias son "el mismo ítem" si comparten id (o son el mismo recurso, si no tienen id).
func is_same_as(other: ItemData) -> bool:
	if other == null:
		return false
	if other == self:
		return true
	return id != &"" and id == other.id

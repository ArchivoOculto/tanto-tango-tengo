extends Resource
class_name ObjectAction

## Una acción extra del menú de un InteractableObject (ej: "reproducir cinta").
##
## Se agrega en el campo "Actions" del InteractableObject. Si tiene 'required_item', la acción
## solo aparece (se "desbloquea") cuando el jugador lleva ese ítem en el inventario.
## Al activarla, el objeto emite InteractableObject.action_triggered(action, ítem_consumido) y
## quien escuche esa señal programa el efecto.

## Identificador que usa el código para reconocer la acción (ej: &"play_tape").
@export var id: StringName = &""
## Texto de la fila del menú.
@export var label: String = "acción"
## Acción del Input Map que la activa: object_action (□), object_action_2 (✕) u object_save (△).
@export var input_action: StringName = &"object_action"
## Frame del ícono en la animación "buttons": 0 △, 1 □, 2 ○, 3 ✕, 4 L1, 5 L2, 6 R1, 7 R2.
@export_range(0, 11) var icon_frame: int = 1

@export_group("Requisitos")
## Si se asigna, la acción solo está disponible mientras el jugador tenga este ítem.
@export var required_item: ItemData
## Alternativa a 'required_item': acepta CUALQUIER ítem de esta categoría (ej: &"cassette", ver
## ItemData.get_category). Si 'required_item' está asignado, este campo se ignora.
@export var required_item_category: StringName = &""
## Con 'required_item_category': si el jugador tiene más de un ítem válido, al activar la acción se abre
## un submenú del inventario (solo con esos ítems) para elegir cuál usar. Se confirma con el mismo botón.
@export var choose_item: bool = true
## Con 'choose_item': abrir el submenú aunque haya un único ítem válido.
@export var always_choose: bool = false
## Título del submenú de selección (ej: "elegir cinta").
@export var picker_title: String = "elegir ítem"
## Si es true, al activarla el ítem requerido sale del inventario.
@export var consume_required_item: bool = false
## Si es true, la fila aparece atenuada y bloqueada mientras falta el ítem. Si es false, directamente no aparece.
@export var show_when_locked: bool = false

@export_group("Comportamiento")
## Cierra el menú del objeto al activar la acción.
@export var close_menu_on_trigger: bool = true


## ¿Este ítem sirve para esta acción?
func accepts(item: ItemData) -> bool:
	if item == null:
		return false
	if required_item != null:
		return item.is_same_as(required_item)
	if required_item_category != &"":
		return item.get_category() == required_item_category
	return true


## ¿La acción necesita que el jugador lleve algún ítem?
func needs_item() -> bool:
	return required_item != null or required_item_category != &""

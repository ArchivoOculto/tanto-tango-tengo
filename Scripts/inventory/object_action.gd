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
## Si es true, al activarla el ítem requerido sale del inventario.
@export var consume_required_item: bool = false
## Si es true, la fila aparece atenuada y bloqueada mientras falta el ítem. Si es false, directamente no aparece.
@export var show_when_locked: bool = false

@export_group("Comportamiento")
## Cierra el menú del objeto al activar la acción.
@export var close_menu_on_trigger: bool = true

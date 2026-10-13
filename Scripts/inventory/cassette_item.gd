extends ItemData
class_name CassetteItem

## Un cassette: lleva una canción ('track') y recuerda en qué punto quedó.
##
## El punto de reproducción NO se guarda en este recurso (Godot lo comparte y lo cachea entre
## recargas del nivel, así que "recordaría" la partida anterior) sino en el estado del objeto
## físico (InventoryEntry.state), que se reinicia solo con el nivel.
##
## En el inventario ofrece "rebobinar" (solo al comienzo) cuando la cinta ya se reprodujo.

## Clave del punto de reproducción (en segundos) dentro de InventoryEntry.state.
const STATE_POSITION: StringName = &"tape_position"
## Por debajo de esto la cinta se considera "al comienzo" (no hay nada que rebobinar).
const MIN_REWIND_SECONDS: float = 0.5

@export_group("Cinta")
## La canción grabada. La reproduce la radio.
@export var track: AudioStream

var _rewind_action: ObjectAction


## Punto (en segundos) donde quedó la cinta, 0 si nunca se reprodujo.
func get_position(entry: InventoryEntry) -> float:
	if entry == null:
		return 0.0
	return float(entry.state.get(STATE_POSITION, 0.0))


func set_position(entry: InventoryEntry, seconds: float) -> void:
	if entry != null:
		entry.state[STATE_POSITION] = maxf(seconds, 0.0)


func get_inventory_actions(entry: InventoryEntry) -> Array[ObjectAction]:
	var actions: Array[ObjectAction] = []
	if get_position(entry) > MIN_REWIND_SECONDS:
		if _rewind_action == null:
			_rewind_action = ObjectAction.new()
			_rewind_action.id = &"rewind"
			_rewind_action.label = "rebobinar"
			_rewind_action.input_action = &"object_action"
			_rewind_action.icon_frame = 1 # □
		actions.append(_rewind_action)
	return actions


func do_inventory_action(entry: InventoryEntry, action: ObjectAction) -> void:
	if action != null and action.id == &"rewind":
		set_position(entry, 0.0)


func get_detail_text(entry: InventoryEntry) -> String:
	var text: String = description
	var position: float = get_position(entry)
	if position > MIN_REWIND_SECONDS:
		text += "\n\nReproducida hasta %d:%02d." % [int(position) / 60, int(position) % 60]
	return text

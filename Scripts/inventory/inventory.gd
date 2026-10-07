extends Node

## Autoload "Inventory": la lista de ítems que lleva el jugador y la apertura del menú.
##
## Es un autoload, así que sobrevive a las recargas de escena: al reiniciar el juego hay que llamar
## a reset() (lo hace Level00Manager).
##
## Los ítems se identifican por ItemData.id. Casi todos los métodos aceptan un ItemData o un id.

signal item_added(entry: InventoryEntry)
signal item_removed(entry: InventoryEntry)
## Cualquier cambio en la lista (alta, baja o reinicio).
signal changed
signal menu_opened
signal menu_closed

const MENU_SCENE: PackedScene = preload("res://Scenes/inventory_menu.tscn")

var _entries: Array[InventoryEntry] = []
var _menu: InventoryMenu


func _ready() -> void:
	_menu = MENU_SCENE.instantiate() as InventoryMenu
	add_child(_menu)
	_menu.opened.connect(func(): menu_opened.emit())
	_menu.closed.connect(func(): menu_closed.emit())


## true mientras el menú del inventario está abierto.
var menu_open: bool:
	get:
		return is_instance_valid(_menu) and _menu.is_open


# ---------------------------------------------------------------- LISTA

## Agrega un ítem. 'source' es el InteractableObject del que salió (para poder devolverlo al mundo);
## 'template' y 'bounds' son su clon visual para la vista previa 3D (el inventario pasa a ser su dueño).
func add_item(item: ItemData, source: Node = null, template: Node3D = null, bounds: AABB = AABB()) -> InventoryEntry:
	if item == null:
		push_warning("Inventory.add_item: ítem vacío.")
		return null
	var entry := InventoryEntry.new(item, source, template, bounds)
	_entries.append(entry)
	item_added.emit(entry)
	changed.emit()
	return entry


## Quita el primer ítem que coincida y devuelve su entrada (null si no lo tenía). Libera el clon visual:
## si el ítem vuelve al inventario más adelante se arma uno nuevo.
func remove_item(item: Variant) -> InventoryEntry:
	var index: int = _find_index(item)
	if index < 0:
		return null
	var entry: InventoryEntry = _entries[index]
	_entries.remove_at(index)
	entry.dispose()
	item_removed.emit(entry)
	changed.emit()
	return entry


func has_item(item: Variant) -> bool:
	return _find_index(item) >= 0


func get_entry(item: Variant) -> InventoryEntry:
	var index: int = _find_index(item)
	return _entries[index] if index >= 0 else null


func get_entries() -> Array[InventoryEntry]:
	return _entries


func count() -> int:
	return _entries.size()


## Vacía el inventario y cierra el menú (reinicio del juego).
func reset() -> void:
	if is_instance_valid(_menu):
		_menu.close()
	for entry in _entries:
		entry.dispose()
	_entries.clear()
	changed.emit()


func _find_index(item: Variant) -> int:
	for i in _entries.size():
		var candidate: ItemData = _entries[i].item
		if item is ItemData:
			if candidate.is_same_as(item):
				return i
		elif (item is StringName or item is String) and candidate.id == StringName(item):
			return i
	return -1


# ---------------------------------------------------------------- MENÚ

func open_menu() -> bool:
	return is_instance_valid(_menu) and _menu.open()


func close_menu() -> void:
	if is_instance_valid(_menu):
		_menu.close()

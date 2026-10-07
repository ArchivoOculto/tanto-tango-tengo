extends CanvasLayer
class_name InventoryMenu

## Menú del inventario: la lista de ítems a la izquierda y, en el centro, la vista previa del
## ítem seleccionado.
##  - Ítems 3D: el mismo visor que el menú de los objetos (se rota con el stick derecho).
##  - Ítems 2D (ItemData.preview_texture): la imagen, como en los cuadros.
##
## Lo instancia el autoload Inventory, así existe en cualquier nivel sin agregarlo a mano.
## Se abre y cierra con la acción "inventory" (SELECT / I / Tab). Con ○ ("interact") también se cierra.
## La lista se recorre con "inventory_up" / "inventory_down" (cruceta o W/S).
## Mientras está abierto el jugador queda congelado (PlayerControlLock).

signal opened
signal closed

const COLOR_SELECTED: Color = Color(1.0, 0.9, 0.2) ## el mismo amarillo del outline de los objetos
const COLOR_NORMAL: Color = Color(1.0, 1.0, 1.0, 0.7)

var is_open: bool = false

var viewer: ObjectViewer
var _selected: int = 0
var _frozen_player: Node = null
var _rows: Array[Label] = []

@onready var _list: VBoxContainer = %ItemList
@onready var _preview: Control = %Preview
@onready var _image_2d: TextureRect = %Image2D
@onready var _view_3d: TextureRect = %View3D
@onready var _sub_viewport: SubViewport = %SubViewport
@onready var _camera: Camera3D = %ViewCamera
@onready var _pivot: Node3D = %ObjectPivot
@onready var _name_label: Label = %ItemName
@onready var _description_label: Label = %ItemDescription
@onready var _empty_label: Label = %EmptyLabel
@onready var _close_hint: Label = %CloseHint
@onready var _rotate_hint: Label = %RotateHint
@onready var _nav_hint: Label = %NavHint


func _ready() -> void:
	visible = false

	viewer = ObjectViewer.new()
	viewer.name = "ObjectViewer"
	add_child(viewer)
	viewer.setup(_sub_viewport, _camera, _pivot, _view_3d)

	ButtonPrompt.setup_row(_close_hint, _close_hint.get_node("Icon"), "cerrar", 2)
	ButtonPrompt.setup_row(_rotate_hint, _rotate_hint.get_node("Icon"), "rotar objeto", 8)


func _exit_tree() -> void:
	if is_open:
		is_open = false
		PlayerControlLock.release(_frozen_player)
		_frozen_player = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
		return

	if not is_open:
		return

	if event.is_action_pressed("interact"):
		close()
	elif event.is_action_pressed("inventory_down", true):
		_move_selection(1)
	elif event.is_action_pressed("inventory_up", true):
		_move_selection(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if is_open and _view_3d.visible:
		viewer.rotate_with_stick(delta)


# ---------------------------------------------------------------- ABRIR / CERRAR

## Condiciones para abrirlo: no se abre sobre otro menú, en pleno modo fusil, en una cinemática ni
## con el jugador bloqueado (intro, final del juego).
func can_open() -> bool:
	if is_open:
		return false
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.can_process() or not player.is_physics_processing():
		return false # bloqueado por el juego o congelado por otro menú
	if CameraDirector.is_first_person() or CameraDirector.has_forced_zone():
		return false
	if InteractionFocus.has_open_menu():
		return false
	return true


func open() -> bool:
	if not can_open():
		return false
	_frozen_player = get_tree().get_first_node_in_group("player")
	PlayerControlLock.freeze(_frozen_player)

	is_open = true
	visible = true
	if not Inventory.changed.is_connected(_refresh):
		Inventory.changed.connect(_refresh)
	_refresh()
	opened.emit()
	return true


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	viewer.set_active(false)
	viewer.clear()
	if Inventory.changed.is_connected(_refresh):
		Inventory.changed.disconnect(_refresh)

	# Siempre se devuelve el control al jugador que se congeló (ver PlayerControlLock)
	var player: Node = _frozen_player
	_frozen_player = null
	PlayerControlLock.release(player)
	closed.emit()


# ---------------------------------------------------------------- LISTA Y VISTA PREVIA

func get_selected_index() -> int:
	return _selected


func _move_selection(step: int) -> void:
	var count: int = Inventory.count()
	if count == 0:
		return
	_selected = posmod(_selected + step, count)
	_refresh()


## Reconstruye la lista y la vista previa a partir del Inventory.
func _refresh() -> void:
	var entries: Array[InventoryEntry] = Inventory.get_entries()
	_selected = clampi(_selected, 0, maxi(entries.size() - 1, 0))

	for row in _rows:
		row.queue_free()
	_rows.clear()

	for i in entries.size():
		var row := Label.new()
		row.text = ("▸ " if i == _selected else "   ") + entries[i].item.get_label()
		row.add_theme_font_size_override("font_size", 23)
		row.add_theme_constant_override("outline_size", 10)
		row.add_theme_color_override("font_color", COLOR_SELECTED if i == _selected else COLOR_NORMAL)
		_list.add_child(row)
		_rows.append(row)

	var has_items: bool = not entries.is_empty()
	_empty_label.visible = not has_items
	_preview.visible = has_items
	_name_label.visible = has_items
	_description_label.visible = has_items
	_nav_hint.visible = entries.size() > 1

	if has_items:
		_show_preview(entries[_selected])
	else:
		_clear_preview()


func _show_preview(entry: InventoryEntry) -> void:
	_name_label.text = entry.item.get_label()
	_description_label.text = entry.item.description

	var shown_3d: bool = false
	if entry.item.preview_texture != null:
		_image_2d.texture = entry.item.preview_texture
		_image_2d.visible = true
	else:
		_image_2d.visible = false
		if entry.template != null:
			viewer.show_template(entry.template, entry.bounds)
			shown_3d = true
		elif entry.item.preview_scene != null:
			shown_3d = viewer.show_scene(entry.item.preview_scene)

	_view_3d.visible = shown_3d
	viewer.set_active(shown_3d)
	if not shown_3d:
		viewer.clear()
	_rotate_hint.visible = shown_3d


func _clear_preview() -> void:
	_image_2d.visible = false
	_view_3d.visible = false
	_rotate_hint.visible = false
	viewer.set_active(false)
	viewer.clear()

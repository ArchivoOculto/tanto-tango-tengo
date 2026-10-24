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
## Cada ítem puede ofrecer acciones propias (ItemData.get_inventory_actions), por ejemplo "rebobinar"
## en un cassette: aparecen como filas con su botón mientras ese ítem está seleccionado.
## Mientras está abierto el jugador queda congelado (PlayerControlLock).
##
## MODO SELECTOR (open_picker): el mismo menú, pero con solo los ítems que pasan un filtro (ej: los
## cassettes que se pueden poner en la radio). Se elige con ↑/↓ y se confirma con el botón que se pida
## (□ para "reproducir cinta"); ○ cancela. Lo usan las ObjectAction con 'required_item_category'.

signal opened
signal closed

const COLOR_SELECTED: Color = Color(1.0, 0.9, 0.2) ## el mismo amarillo del outline de los objetos
const COLOR_NORMAL: Color = Color(1.0, 1.0, 1.0, 0.7)

# Pistas de botones bajo el visor (posiciones relativas al centro de la pantalla base de 845 x 480)
const HINT_STEP: float = 25.0 ## separación entre pistas
const MIN_HINT_STEP: float = 20.0 ## separación mínima si hay tantas que no entrarían
const HINT_BOTTOM_LIMIT: float = 238.0 ## borde inferior máximo de la última pista (la pantalla llega a 240)
const NAV_HINT_LEFT: float = -382.0 ## x de "↑ ↓ elegir": alineado con la lista de ítems (x = 40 en pantalla)
const NAV_HINT_TOP: float = 212.0 ## y de "↑ ↓ elegir": bajo la lista (y = 452 en pantalla)

var is_open: bool = false

var viewer: ObjectViewer
var _selected: int = 0
var _frozen_player: Node = null
var _rows: Array[Control] = []
var _action_rows: Array[Label] = [] ## Filas de las acciones del ítem seleccionado
var _current_actions: Array[ObjectAction] = []
var _current_entry: InventoryEntry
var _hint_label: Label ## pista en amarillo bajo la descripción (ver ItemData.get_hint_text)

# Modo selector
var _picker_active: bool = false
var _picker_filter: Callable
var _picker_confirm_action: StringName = &""
var _picker_on_picked: Callable
var _picker_on_cancelled: Callable
var _picker_confirm_row: Label

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
var _zoom_hint: Label ## "(L2)(R2) zoom": copia de la pista de rotar, se arma en código
@onready var _nav_hint: Label = %NavHint
@onready var _title_label: Label = $Root/Title


func _ready() -> void:
	visible = false

	viewer = ObjectViewer.new()
	viewer.name = "ObjectViewer"
	add_child(viewer)
	viewer.setup(_sub_viewport, _camera, _pivot, _view_3d)
	_setup_text_column()

	ButtonPrompt.setup_row(_close_hint, _close_hint.get_node("Icon"), "cerrar", InputGlyph.for_action(&"interact"))
	ButtonPrompt.setup_row(_rotate_hint, _rotate_hint.get_node("Icon"), "rotar objeto", InputGlyph.stick_right())
	_build_zoom_hint()


## Pista de zoom de la vista previa 3D: copia la de rotar (mismo estilo) con dos íconos, y la acompaña en visibilidad.
func _build_zoom_hint() -> void:
	_zoom_hint = _rotate_hint.duplicate() as Label
	_zoom_hint.name = "ZoomHint"
	var icon_a: AnimatedSprite2D = _zoom_hint.get_node("Icon") as AnimatedSprite2D
	var icon_b: AnimatedSprite2D = icon_a.duplicate() as AnimatedSprite2D
	_zoom_hint.add_child(icon_b)
	_rotate_hint.get_parent().add_child(_zoom_hint)
	ButtonPrompt.setup_row_icons(_zoom_hint, [icon_a, icon_b], "zoom", InputGlyph.zoom())
	_zoom_hint.visible = false


## Nombre, descripción y pista pasan a UNA columna que fluye, en el mismo lugar y con el ancho que tenía el
## nombre. Así un título largo pasa a dos líneas (antes se cortaba contra el borde de la pantalla) y la
## descripción y la pista siempre quedan justo debajo, sin pisarse, sin importar cuántas líneas ocupen.
func _setup_text_column() -> void:
	var parent: Node = _name_label.get_parent()
	var box := VBoxContainer.new()
	box.name = "TextColumn"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", MenuInfoPanel.TEXT_SEPARATION)
	box.position = _name_label.position
	box.size = Vector2(_name_label.size.x, 0.0)
	parent.add_child(box)
	parent.move_child(box, _name_label.get_index())
	for label: Label in [_name_label, _description_label]:
		label.reparent(box, false)
		label.custom_minimum_size = Vector2.ZERO # que mida lo que ocupa el texto, no un alto fijo
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label = MenuInfoPanel.make_hint_label(_description_label)
	box.add_child(_hint_label)


func _exit_tree() -> void:
	if is_open:
		is_open = false
		PlayerControlLock.release(_frozen_player)
		_frozen_player = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if is_open:
			close() # en modo selector, cerrar = cancelar
		else:
			open()
		get_viewport().set_input_as_handled()
		return

	if not is_open:
		return

	# Rueda del mouse: acerca / aleja la vista previa 3D
	if event is InputEventMouseButton and _view_3d.visible and viewer.handle_wheel_event(event as InputEventMouseButton):
		get_viewport().set_input_as_handled()
		return

	if _picker_active and _current_entry != null and event.is_action_pressed(_picker_confirm_action):
		_confirm_picker()
	elif event.is_action_pressed("interact"):
		close()
	elif event.is_action_pressed("inventory_down", true):
		_move_selection(1)
	elif event.is_action_pressed("inventory_up", true):
		_move_selection(-1)
	elif not _trigger_item_action(event):
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if is_open and _view_3d.visible:
		viewer.rotate_with_stick(delta)
		viewer.update_zoom(delta)


# ---------------------------------------------------------------- ABRIR / CERRAR

## Condiciones para abrirlo: no se abre sobre otro menú, en pleno modo fusil, en una cinemática ni
## con el jugador bloqueado (intro, final del juego).
## 'from_pause': el menú de pausa ya validó todo y el árbol está en pausa (el jugador "no puede procesar"
## y las cámaras forzadas no importan), así que solo se exige que no esté ya abierto.
func can_open(from_pause: bool = false) -> bool:
	if is_open:
		return false
	if from_pause:
		return true
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.can_process() or not player.is_physics_processing():
		return false # bloqueado por el juego o congelado por otro menú
	if CameraDirector.is_first_person() or CameraDirector.has_forced_zone():
		return false
	if InteractionFocus.has_open_menu():
		return false
	return true


func open(from_pause: bool = false) -> bool:
	if not can_open(from_pause):
		return false
	_set_picker_mode(false)
	_frozen_player = get_tree().get_first_node_in_group("player")
	PlayerControlLock.freeze(_frozen_player)

	is_open = true
	visible = true
	if not Inventory.changed.is_connected(_refresh):
		Inventory.changed.connect(_refresh)
	_refresh()
	_play_open_animation()
	opened.emit()
	return true


## Abre el inventario filtrado para elegir un ítem (ver Inventory.open_picker).
func open_picker(filter: Callable, title: String, confirm_label: String, confirm_action: StringName,
		confirm_icon_frame: int, on_picked: Callable, on_cancelled: Callable = Callable()) -> bool:
	if not can_open():
		return false
	if Inventory.get_entries_where(filter).is_empty():
		return false
	_picker_filter = filter
	_picker_confirm_action = confirm_action
	_picker_on_picked = on_picked
	_picker_on_cancelled = on_cancelled
	_selected = 0
	_set_picker_mode(true, title, confirm_label, confirm_icon_frame)

	_frozen_player = get_tree().get_first_node_in_group("player")
	PlayerControlLock.freeze(_frozen_player)
	is_open = true
	visible = true
	if not Inventory.changed.is_connected(_refresh):
		Inventory.changed.connect(_refresh)
	_refresh()
	_play_open_animation()
	opened.emit()
	return true


func _set_picker_mode(active: bool, title: String = "", confirm_label: String = "", confirm_icon_frame: int = 1) -> void:
	_picker_active = active
	if is_instance_valid(_picker_confirm_row):
		_picker_confirm_row.queue_free()
		_picker_confirm_row = null
	if active:
		_title_label.text = title
		ButtonPrompt.setup_row(_close_hint, _close_hint.get_node("Icon"), "cancelar", InputGlyph.for_action(&"interact"))
		_picker_confirm_row = _close_hint.duplicate() as Label
		_picker_confirm_row.name = "PickerConfirm"
		_close_hint.get_parent().add_child(_picker_confirm_row)
		ButtonPrompt.setup_row(_picker_confirm_row, _picker_confirm_row.get_node("Icon"), confirm_label,
				InputGlyph.for_action(_picker_confirm_action, confirm_icon_frame))
	else:
		_title_label.text = "inventario"
		ButtonPrompt.setup_row(_close_hint, _close_hint.get_node("Icon"), "cerrar", InputGlyph.for_action(&"interact"))
		_picker_filter = Callable()
		_picker_on_picked = Callable()
		_picker_on_cancelled = Callable()


func _confirm_picker() -> void:
	var entry: InventoryEntry = _current_entry
	var on_picked: Callable = _picker_on_picked
	_picker_active = false # ya no cuenta como cancelación al cerrar
	close()
	_set_picker_mode(false)
	if on_picked.is_valid():
		on_picked.call(entry)


## 'silent' = cierre forzado (ej: el jugador recibe daño): en modo selector no avisa la cancelación,
## así quien lo abrió no vuelve a abrir su propio menú encima.
func close(silent: bool = false) -> void:
	if not is_open:
		return
	var cancelled: Callable = _picker_on_cancelled if _picker_active and not silent else Callable()
	var was_picker: bool = _picker_active
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
	if was_picker:
		_set_picker_mode(false)
		if cancelled.is_valid():
			cancelled.call()


# ---------------------------------------------------------------- GAME JUICE

## Al abrirse, el contenido (todo menos el fondo oscuro) crece un poco con rebote.
func _play_open_animation() -> void:
	UiJuice.pop_in_children($Root, [&"Dim"])


## Al cambiar de ítem: la fila elegida "salta" y la vista previa pega un saltito con rebote.
func _play_select_animation() -> void:
	if _selected >= 0 and _selected < _rows.size():
		UiJuice.pop(_rows[_selected], 0.12, Vector2(0.0, 0.5))
	if _preview.visible:
		UiJuice.hop(_preview, 8.0)
		UiJuice.pop(_preview, -0.1)


# ---------------------------------------------------------------- LISTA Y VISTA PREVIA

func get_selected_index() -> int:
	return _selected


## Entradas que se listan: todas, o solo las que pasan el filtro en modo selector.
func _visible_entries() -> Array[InventoryEntry]:
	if _picker_active and _picker_filter.is_valid():
		return Inventory.get_entries_where(_picker_filter)
	return Inventory.get_entries()


func _move_selection(step: int) -> void:
	var count: int = _visible_entries().size()
	if count == 0:
		return
	_selected = posmod(_selected + step, count)
	_refresh()
	_play_select_animation()


func _make_row_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_color", color)
	return label


## Reconstruye la lista y la vista previa a partir del Inventory.
func _refresh() -> void:
	var entries: Array[InventoryEntry] = _visible_entries()
	_selected = clampi(_selected, 0, maxi(entries.size() - 1, 0))

	for row in _rows:
		row.queue_free()
	_rows.clear()

	for i in entries.size():
		# Flecha + nombre en dos etiquetas: si el nombre es largo pasa a otra línea (en vez de pisar la vista previa)
		# y esa segunda línea queda alineada con el nombre, no debajo de la flecha.
		var color: Color = COLOR_SELECTED if i == _selected else COLOR_NORMAL
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var marker := _make_row_label("▸ " if i == _selected else "", color)
		marker.autowrap_mode = TextServer.AUTOWRAP_OFF
		marker.size_flags_vertical = Control.SIZE_SHRINK_BEGIN # una línea de alto, arriba: apunta a la primera línea del nombre
		marker.custom_minimum_size.x = ButtonPrompt.text_width(marker, "▸ ") # mismo hueco con o sin flecha
		var title := _make_row_label(entries[i].item.get_label(), color)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(marker)
		row.add_child(title)
		_list.add_child(row)
		_rows.append(row)

	var has_items: bool = not entries.is_empty()
	_empty_label.visible = not has_items
	_preview.visible = has_items
	_name_label.visible = has_items
	_description_label.visible = has_items
	_nav_hint.visible = entries.size() > 1

	_current_entry = entries[_selected] if has_items else null
	_rebuild_action_rows()
	if _picker_active and not has_items:
		close() # no queda nada que elegir

	if has_items:
		_show_preview(entries[_selected])
	else:
		_clear_preview()
	_layout_hints()


## Filas de las acciones que ofrece el ítem seleccionado (ej: "rebobinar"), con el mismo estilo que "cerrar".
func _rebuild_action_rows() -> void:
	for row in _action_rows:
		row.queue_free()
	_action_rows.clear()
	_current_actions.clear()
	if _current_entry == null or _picker_active:
		return
	for action in _current_entry.item.get_inventory_actions(_current_entry):
		var row: Label = _close_hint.duplicate() as Label
		row.name = "Action_" + String(action.id)
		_close_hint.get_parent().add_child(row)
		ButtonPrompt.setup_row(row, row.get_node("Icon"), action.label,
				InputGlyph.for_action(action.input_action, action.icon_frame))
		_action_rows.append(row)
		_current_actions.append(action)


## Apila las pistas de botones de abajo: cerrar, acciones del ítem, rotar (si es 3D) y la ayuda de navegación.
func _layout_hints() -> void:
	var ordered: Array[Label] = [_close_hint]
	if is_instance_valid(_picker_confirm_row):
		ordered.append(_picker_confirm_row)
	ordered.append_array(_action_rows)
	if _rotate_hint.visible:
		ordered.append(_rotate_hint)
	_zoom_hint.visible = _rotate_hint.visible # el zoom va con la rotación: solo para objetos 3D
	if _zoom_hint.visible:
		ordered.append(_zoom_hint)
	var y: float = _close_hint.offset_top
	# Con muchas filas la última no puede salirse de la pantalla: se juntan un poco, sin bajar de MIN_HINT_STEP
	var step: float = HINT_STEP
	if ordered.size() > 1:
		var last_height: float = ordered[-1].offset_bottom - ordered[-1].offset_top
		step = minf(step, maxf((HINT_BOTTOM_LIMIT - last_height - y) / float(ordered.size() - 1), MIN_HINT_STEP))
	for row in ordered:
		var height: float = row.offset_bottom - row.offset_top
		row.offset_top = y
		row.offset_bottom = y + height
		y += step
	# "↑ ↓ elegir" va bajo la lista de ítems (el hueco bajo el visor ya lo ocupan las pistas de arriba)
	_nav_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_nav_hint.offset_left = NAV_HINT_LEFT
	_nav_hint.offset_right = NAV_HINT_LEFT + 250.0
	_nav_hint.offset_top = NAV_HINT_TOP
	_nav_hint.offset_bottom = NAV_HINT_TOP + 28.0


func _trigger_item_action(event: InputEvent) -> bool:
	if _current_entry == null:
		return false
	for action in _current_actions:
		if event.is_action_pressed(action.input_action):
			_current_entry.item.do_inventory_action(_current_entry, action)
			_refresh() # el estado cambió (ej: la cinta ya no necesita rebobinarse)
			return true
	return false


func _show_preview(entry: InventoryEntry) -> void:
	_name_label.text = entry.item.get_label()
	_description_label.text = entry.item.get_detail_text(entry)
	var hint: String = entry.item.get_hint_text(entry)
	_hint_label.text = hint
	_hint_label.visible = hint != ""

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
	_hint_label.visible = false
	_image_2d.visible = false
	_view_3d.visible = false
	_rotate_hint.visible = false
	viewer.set_active(false)
	viewer.clear()

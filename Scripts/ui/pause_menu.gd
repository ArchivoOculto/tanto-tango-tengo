extends MenuBase
class_name PauseMenu

## Menú de pausa. Estéticamente igual al menú principal (comparte MenuBase): botones a la izquierda y recuadro
## de opciones / controles a la derecha.
##
##   continuar partida · inventario · opciones · controles · salir al menú principal
##
## Se abre con la acción "pause" (Esc / Start) y pausa TODO el juego (get_tree().paused). Esc / Start / ○
## cierran el panel abierto y, si no hay ninguno, continúan la partida.
##
## USO EN UN NIVEL: PauseMenu.create_in(nodo) lo crea dentro de su propia capa (127: sobre las barras 4:3 y
## debajo del fundido a negro). Level00Manager ya lo hace. "salir al menú principal" no cambia de escena
## por sí solo: emite main_menu_requested y el nivel decide (fundido, reinicio de autoloads, cambio).
##
## No se puede abrir si el jugador está bloqueado (intro, final), con otro menú abierto ni si 'enabled' es false.

signal resumed
signal main_menu_requested

const SCENE_PATH: String = "res://Scenes/ui/pause_menu.tscn"
const LAYER: int = 127

## Permite apagar la pausa (ej: durante el final del nivel).
var enabled: bool = true
var is_open: bool = false

@onready var _continue_button: Button = %ContinueButton
@onready var _inventory_button: Button = %InventoryButton
@onready var _main_menu_button: Button = %MainMenuButton

var _busy: bool = false
var _inventory_open: bool = false ## El inventario se abrió desde esta pausa (el menú queda oculto detrás)
var _mouse_mode_before: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


## Crea el menú de pausa en su propia capa, siempre activa aunque el juego esté en pausa.
static func create_in(parent: Node) -> PauseMenu:
	var layer := CanvasLayer.new()
	layer.name = "PauseLayer"
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(layer)
	var menu := (load(SCENE_PATH) as PackedScene).instantiate() as PauseMenu
	layer.add_child(menu)
	return menu


func _ready() -> void:
	visible = false
	_setup_menu([_continue_button, _inventory_button, _options_button, _controls_button, _main_menu_button])

	_continue_button.pressed.connect(close)
	_inventory_button.pressed.connect(_on_inventory_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	Inventory.menu_closed.connect(_on_inventory_closed)


func _exit_tree() -> void:
	if is_open and is_inside_tree():
		get_tree().paused = false # nunca dejar el juego trabado en pausa
		Audio.set_menu_muffle(&"pause", false)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	var wants_back: bool = event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")
	if not is_open:
		if event.is_action_pressed(&"pause") and _can_open():
			open()
			get_viewport().set_input_as_handled()
		return
	if not wants_back:
		return
	if _inventory_open:
		Inventory.close_menu() # vuelve a esta pausa (ver _on_inventory_closed)
	elif not _close_open_panel():
		close()
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- ABRIR / CERRAR

func _can_open() -> bool:
	if not enabled or is_open or get_tree().paused:
		return false
	if Inventory.menu_open or InteractionFocus.has_open_menu():
		return false
	# Un jugador bloqueado por el juego (intro, final) no puede pausar
	var player: Node = get_tree().get_first_node_in_group("player")
	return player != null and player.can_process()


func open() -> void:
	if not _can_open():
		return
	is_open = true
	_mouse_mode_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	Audio.set_menu_muffle(&"pause", true)
	_show_panel(InfoPanel.NONE)
	visible = true
	UiJuice.pop_in_children(self, [&"Dim"]) # el fondo no se anima: dejaría ver los bordes
	_continue_button.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_inventory_open = false
	visible = false
	get_tree().paused = false
	Audio.set_menu_muffle(&"pause", false)
	Input.mouse_mode = _mouse_mode_before
	# El botón que confirmó "continuar" no debe contar como un ataque o salto al volver al juego
	GameplayInput.consume_held_actions()
	resumed.emit()


# ---------------------------------------------------------------- BOTONES

func _on_inventory_pressed() -> void:
	if Inventory.open_menu(true):
		_inventory_open = true
		visible = false


func _on_inventory_closed() -> void:
	if not _inventory_open:
		return
	_inventory_open = false
	if is_open:
		visible = true
		_inventory_button.grab_focus()


func _on_main_menu_pressed() -> void:
	if _busy:
		return
	_busy = true
	for button: Button in [_continue_button, _inventory_button, _options_button, _controls_button, _main_menu_button]:
		button.disabled = true
	main_menu_requested.emit()

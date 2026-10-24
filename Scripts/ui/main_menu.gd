extends MenuBase
class_name MainMenu

## Pantalla de inicio (escena principal del juego): nueva partida, opciones, controles y salir.
## Los paneles de opciones y controles, y el estilo, vienen de MenuBase (los comparte con el menú de pausa).
##
##  - "nueva partida" pierde la señal del tubo CRT (glitch) y carga el nivel (terrain.tscn).
##  - "salir" apaga el tubo como un televisor viejo y cierra el juego (no aparece en la versión web).
##  Ambos efectos los hace ScreenFX; con el filtro CRT apagado en opciones son un fundido a negro común.
##
## Se maneja con teclado, mando o mouse. ○ / escape cierra el panel abierto.

## Nivel que arranca "nueva partida".
const GAME_SCENE: String = "res://Scenes/levels/terrain.tscn"

@export var fade_in_duration: float = 1.2
@export var fade_out_duration: float = 0.8 ## Duración del apagado al salir
## Duración del glitch de "nueva partida".
@export var new_game_glitch_duration: float = 0.9

@onready var _new_game_button: Button = %NewGameButton
@onready var _quit_button: Button = %QuitButton

var _busy: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_quit_button.visible = not OS.has_feature("web")
	_setup_menu([_new_game_button, _options_button, _controls_button, _quit_button])

	_new_game_button.pressed.connect(_on_new_game_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)

	_new_game_button.grab_focus()
	WarpManager.fade_in(fade_in_duration) # viene del negro (final del nivel)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed("ui_cancel") and _close_open_panel():
		get_viewport().set_input_as_handled()


func _on_new_game_pressed() -> void:
	if _begin_exit():
		await ScreenFX.glitch_out(new_game_glitch_duration)
		get_tree().change_scene_to_file(GAME_SCENE)
		# El cambio de escena ocurre al final del cuadro: se espera un instante para devolver el tubo a su estado
		# normal. El nivel arranca en negro (WarpManager), así que no se ve.
		ScreenFX.power_on(0.0, 0.3)


func _on_quit_pressed() -> void:
	if _begin_exit():
		await ScreenFX.power_off(fade_out_duration)
		get_tree().quit()


## Bloquea los botones mientras dura el fundido de salida. false si ya se estaba saliendo.
func _begin_exit() -> bool:
	if _busy:
		return false
	_busy = true
	for button: Button in [_new_game_button, _options_button, _controls_button, _quit_button]:
		button.disabled = true
	return true

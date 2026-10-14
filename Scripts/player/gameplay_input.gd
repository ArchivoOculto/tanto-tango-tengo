extends RefCounted
class_name GameplayInput

## Lectura de botones de juego (salto, ataque, disparo) que respeta a los menús.
##
## El problema que resuelve: un mismo botón puede ser a la vez una acción de menú y una de juego
## (□ es "reproducir cinta" en el menú de la radio y "atacar" en el juego). Al activar la acción el
## menú se cierra y le devuelve el control al jugador EN ESE MISMO FRAME, donde el botón todavía
## figura como "recién presionado": el jugador atacaba (o saltaba) sin querer.
##
## Solución: cuando un menú devuelve el control (PlayerControlLock.release), los botones de juego
## que siguen apretados quedan "consumidos". just_pressed() devuelve false para ellos hasta que se
## suelten una vez; la siguiente pulsación vale normalmente.
##
## Todo código de juego que quiera detectar una pulsación debe usar GameplayInput.just_pressed()
## en vez de Input.is_action_just_pressed().

## Acciones de juego que un menú puede dejar apretadas al cerrarse.
const GAMEPLAY_ACTIONS: Array[StringName] = [&"attack", &"jump", &"rifle_shoot", &"rifle_toggle"]

static var _consumed: Dictionary = {}


## Marca como "consumidas" las acciones de juego que están apretadas ahora mismo.
static func consume_held_actions() -> void:
	for action in GAMEPLAY_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			_consumed[action] = true


## Igual que Input.is_action_just_pressed(), salvo que ignora una pulsación consumida por un menú.
static func just_pressed(action: StringName) -> bool:
	if _consumed.has(action):
		if Input.is_action_pressed(action):
			return false
		_consumed.erase(action) # se soltó: vuelve a valer
	return Input.is_action_just_pressed(action)


static func reset() -> void:
	_consumed.clear()

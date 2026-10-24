class_name InputGlyph
extends RefCounted

## Cómo se muestra un botón o tecla en la UI. Un "glifo" es un Dictionary:
##
##   { "pad": frame del ícono en la hoja de botones del mando (-1 = sin ícono), "key": texto de teclado y mouse }
##
## Los glifos se arman a partir del Input Map, así siempre reflejan los controles reales. Con un mando se muestra
## el ícono (PS2 por omisión); con teclado y mouse, la tecla entre corchetes (ver ButtonPrompt y InputDevice, que
## decide cuál de los dos usar según el último dispositivo que dio una orden).

## Botón del mando (índice de Godot) -> cuadro de la hoja de íconos (Resources/ui/ui_buttons_frames.tres).
## 0 △  1 □  2 ○  3 ✕  4 L1  5 L2  6 R1  7 R2  8 stick der.  9 stick izq.  10 select  11 start
const PAD_BUTTON_FRAMES: Dictionary = {0: 3, 1: 2, 2: 1, 3: 0, 4: 10, 6: 11, 9: 4, 10: 6}
## Eje del mando -> cuadro: sticks (0-1 izquierdo, 2-3 derecho) y gatillos (4 = L2, 5 = R2).
const PAD_AXIS_FRAMES: Dictionary = {0: 9, 1: 9, 2: 8, 3: 8, 4: 5, 5: 7}
const FRAME_STICK_R: int = 8
const FRAME_STICK_L: int = 9

const MOUSE_NAMES: Dictionary = {1: "clic izq.", 2: "clic der.", 3: "clic medio", 4: "rueda ↑", 5: "rueda ↓"}
const KEY_NAMES: Dictionary = {
	"Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Space": "espacio", "Escape": "esc",
	"Enter": "enter", "Kp Enter": "enter", "Tab": "tab", "Shift": "shift", "Ctrl": "ctrl", "Alt": "alt",
}

const MOVE_ACTIONS: Array[StringName] = [&"move_forward", &"move_left", &"move_back", &"move_right"]
## Acciones de juego, en orden de prioridad, para adivinar qué tecla corresponde a un ícono suelto (for_pad_frame).
const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"jump", &"attack", &"interact", &"rifle_toggle", &"rifle_shoot", &"object_save", &"inventory", &"pause",
]


static func make(pad: int, key: String) -> Dictionary:
	return {"pad": pad, "key": key}


## Glifo de una acción del Input Map. 'pad_override' fuerza el ícono del mando (ej: ObjectAction.icon_frame).
static func for_action(action: StringName, pad_override: int = -1) -> Dictionary:
	var pad: int = pad_override if pad_override >= 0 else pad_frame(action)
	return make(pad, key_text(action))


## Glifo de varias acciones que hacen lo mismo (ej: las cuatro de moverse): las teclas se juntan en un texto.
static func for_actions(actions: Array, pad: int) -> Dictionary:
	var keys: Array[String] = []
	for action in actions:
		var text: String = key_text(action)
		if text != "" and not keys.has(text):
			keys.append(text)
	return make(pad, " ".join(keys))


static func stick_left() -> Dictionary:
	return for_actions(MOVE_ACTIONS, FRAME_STICK_L)


static func stick_right() -> Dictionary:
	return make(FRAME_STICK_R, "flechas")


static func zoom_out() -> Dictionary:
	return for_action(&"image_zoom_out") # L2 / Q


static func zoom_in() -> Dictionary:
	return for_action(&"image_zoom_in") # R2 / E


## Los dos glifos del zoom, en el orden en que se muestran: alejar, acercar.
static func zoom() -> Array:
	return [zoom_out(), zoom_in()]


## Glifo para un ícono de mando suelto: busca qué acción de juego lo usa para saber su tecla. Sirve a los carteles
## de tutorial, que solo conocen el ícono. Si ninguna lo usa, el glifo queda sin tecla (se ve siempre el ícono).
static func for_pad_frame(frame: int) -> Dictionary:
	if frame == FRAME_STICK_L:
		return stick_left()
	if frame == FRAME_STICK_R:
		return stick_right()
	for action in GAMEPLAY_ACTIONS:
		if pad_frame(action) == frame:
			return make(frame, key_text(action))
	return make(frame, "")


## Cuadro del primer botón o eje del mando que tiene la acción (-1 si no tiene).
static func pad_frame(action: StringName) -> int:
	if not InputMap.has_action(action):
		return -1
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			var frame: int = PAD_BUTTON_FRAMES.get((event as InputEventJoypadButton).button_index, -1)
			if frame >= 0:
				return frame
		elif event is InputEventJoypadMotion:
			var axis_frame: int = PAD_AXIS_FRAMES.get((event as InputEventJoypadMotion).axis, -1)
			if axis_frame >= 0:
				return axis_frame
	return -1


## Texto de la primera tecla de la acción o, si no tiene, de su primer botón del mouse ("" si no tiene ninguno).
static func key_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	var mouse_text: String = ""
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var text: String = key_label(event as InputEventKey)
			if text != "":
				return text
		elif event is InputEventMouseButton and mouse_text == "":
			mouse_text = MOUSE_NAMES.get((event as InputEventMouseButton).button_index, "")
	return mouse_text


static func key_label(event: InputEventKey) -> String:
	var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	var text: String = OS.get_keycode_string(code)
	return KEY_NAMES.get(text, text)


## "[E]": cómo se escribe una tecla dentro de un texto.
static func markup(glyph: Dictionary) -> String:
	var key: String = glyph.get("key", "")
	return "[%s]" % (key if key != "" else "?")

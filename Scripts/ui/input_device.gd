extends Node

## Autoload "InputDevice": recuerda con qué dispositivo dio el jugador la última orden (mando o teclado y mouse)
## y avisa cuando cambia, para que las pistas de botones muestren los íconos del mando o las teclas que
## corresponden. Arranca en mando (íconos PS2), que es lo que se ve hasta que el jugador toca otra cosa.
##
##  - ButtonPrompt (filas de los menús y del HUD) se refresca solo con la señal 'changed'.
##  - Carteles de tutorial: todo Label3D cuyo nombre empiece con "tutorial" (o que esté en el grupo
##    "input_prompt") con un AnimatedSprite3D hijo se adapta solo, sin tocar la escena:
##      * con mando se ve el texto tal cual y el ícono;
##      * con teclado el hueco "(     )" se reemplaza por la tecla, "[E]", y el ícono se oculta. "palanca izq (     )"
##        pasa a "[W A S D]" (la palabra "palanca" no tiene sentido con teclado).
##    La tecla sale del ícono (ver InputGlyph.for_pad_frame). Si un cartel necesita otro texto con teclado, se le
##    pone el metadato "keyboard_text".

signal changed(gamepad: bool)

const AXIS_THRESHOLD: float = 0.5 ## un stick o gatillo solo cuenta si pasa de acá (así el "drift" no cambia nada)
const MOUSE_MOVE_THRESHOLD: float = 3.0 ## píxeles de un movimiento de mouse para contar como "usando el mouse"
const TUTORIAL_PREFIX: String = "tutorial"
const TUTORIAL_GROUP: StringName = &"input_prompt"
## En la hoja de los carteles de tutorial los íconos nuevos empiezan en el cuadro 10 (△ □ ○ ✕ L1 L2 R1 R2 stick-der stick-izq).
const TUTORIAL_FRAME_BASE: int = 10
const META_TEXT: StringName = &"_input_device_text"
const META_SPRITE: StringName = &"_input_device_sprite"
const META_FRAME: StringName = &"_input_device_frame"

var using_gamepad: bool = true

var _tutorials: Array = [] # Label3D
var _blank_regex: RegEx


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # también con el juego en pausa
	# "palanca izq/der" (opcional) + el hueco del ícono
	_blank_regex = RegEx.create_from_string("(?i)(?:palanca\\s+(?:izq|der)\\w*\\s*)?\\(\\s+\\)")
	get_tree().node_added.connect(_on_node_added)


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		if event.pressed:
			set_gamepad(false)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= MOUSE_MOVE_THRESHOLD:
			set_gamepad(false)
	elif event is InputEventJoypadButton:
		if event.pressed:
			set_gamepad(true)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= AXIS_THRESHOLD:
			set_gamepad(true)


func set_gamepad(value: bool) -> void:
	if value == using_gamepad:
		return
	using_gamepad = value
	_refresh_tutorials()
	changed.emit(value)


# ---------------------------------------------------------------- CARTELES DE TUTORIAL

func _on_node_added(node: Node) -> void:
	if node is Label3D and (node.name.to_lower().begins_with(TUTORIAL_PREFIX) or node.is_in_group(TUTORIAL_GROUP)):
		_register_tutorial.call_deferred(node) # sus hijos entran después que él


func _register_tutorial(label: Label3D) -> void:
	if not is_instance_valid(label) or not label.is_inside_tree() or _tutorials.has(label):
		return
	var sprites: Array[Node] = label.find_children("*", "AnimatedSprite3D", false, false)
	if sprites.is_empty():
		return
	var sprite: AnimatedSprite3D = sprites[0] as AnimatedSprite3D
	label.set_meta(META_TEXT, label.text)
	label.set_meta(META_SPRITE, sprite)
	label.set_meta(META_FRAME, sprite.frame)
	_tutorials.append(label)
	label.tree_exiting.connect(func() -> void: _tutorials.erase(label))
	_apply_tutorial(label)


func _refresh_tutorials() -> void:
	for label in _tutorials:
		if is_instance_valid(label):
			_apply_tutorial(label)


func _apply_tutorial(label: Label3D) -> void:
	var original: String = label.get_meta(META_TEXT)
	var sprite: AnimatedSprite3D = label.get_meta(META_SPRITE)
	var glyph: Dictionary = InputGlyph.for_pad_frame(_ui_frame(label.get_meta(META_FRAME)))
	var keyboard_text: String = ""
	if label.has_meta("keyboard_text"):
		keyboard_text = str(label.get_meta("keyboard_text"))
	elif glyph.key != "":
		keyboard_text = _blank_regex.sub(original, InputGlyph.markup(glyph))

	if using_gamepad or keyboard_text == "":
		label.text = original
		sprite.visible = true
	else:
		label.text = keyboard_text
		sprite.visible = false


## Cuadro de la hoja de los carteles -> cuadro de la hoja de los menús (ver InputGlyph).
func _ui_frame(tutorial_frame: int) -> int:
	if tutorial_frame >= TUTORIAL_FRAME_BASE:
		return tutorial_frame - TUTORIAL_FRAME_BASE
	return {8: 10, 9: 11}.get(tutorial_frame, tutorial_frame) # los primeros diez: …, select, start

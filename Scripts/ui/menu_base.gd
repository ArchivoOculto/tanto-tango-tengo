extends Control
class_name MenuBase

## Base de los menús con lista de botones a la izquierda y recuadro de información a la derecha: el menú
## principal (MainMenu) y el menú de pausa (PauseMenu). Pone en un solo lugar lo que comparten:
##
##  - Estética del inventario: fondo oscuro, títulos en minúsculas con borde, botones grises translúcidos
##    (el seleccionado más claro con una barra a la izquierda).
##  - "opciones" y "controles" solo MUESTRAN u OCULTAN su información en el recuadro (apretar el mismo
##    botón otra vez la oculta; apretar el otro cambia de panel). ○ / escape cierra el panel abierto.
##  - Opciones: un slider de volumen por bus (ver AudioBuses.OPTION_SLIDERS; sumar un bus ahí suma su
##    slider solo) y pantalla completa. Los guarda GameSettings.
##  - Controles: tabla acción / teclado y mouse / mando, leída del Input Map (siempre refleja los
##    controles reales), con los íconos de botón de los carteles de tutorial.
##
## La escena del menú debe tener estos nodos con nombre único (%): OptionsButton, ControlsButton, RightPanel,
## OptionsPanel, ControlsPanel, Sliders, FullscreenCheck y Grid (ver Scenes/ui/main_menu.tscn). Quien herede
## llama a _setup_menu() desde su _ready() pasándole todos sus botones.

const BUTTON_FRAMES: SpriteFrames = preload("res://Resources/ui/ui_buttons_frames.tres")

enum InfoPanel { NONE, OPTIONS, CONTROLS }

## [texto, acciones (teclado y mouse), ícono del stick (-1 = ninguno), texto extra de teclado]
const CONTROL_ROWS: Array = [
	["moverse", ["move_forward", "move_left", "move_back", "move_right"], 9, ""],
	["saltar / sacar cassette", ["jump", "object_action_2"], -1, ""],
	["atacar / reproducir cinta", ["attack", "object_action"], -1, ""],
	["interactuar / cerrar menú", ["interact"], -1, ""],
	["guardar objeto", ["object_save"], -1, ""],
	["apuntar (mantener)", ["rifle_toggle"], -1, ""],
	["disparar", ["rifle_shoot"], -1, ""],
	["mirar / rotar objeto", ["aim_left", "aim_right", "aim_up", "aim_down"], 8, "mouse"],
	["inventario", ["inventory"], -1, ""],
	["pausa", ["pause"], -1, ""],
]

## Botón del mando (índice de Godot) -> cuadro del atlas de íconos (Resources/ui/ui_buttons_frames.tres).
## 0 △  1 □  2 ○  3 ✕  4 L1  5 L2  6 R1  7 R2  8 stick der.  9 stick izq.  10 select  11 start
const PAD_FRAMES: Dictionary = {0: 3, 1: 2, 2: 1, 3: 0, 4: 10, 6: 11, 9: 4, 10: 6}
const MOUSE_NAMES: Dictionary = {1: "clic izq.", 2: "clic der.", 3: "clic medio"}
const KEY_NAMES: Dictionary = {
	"Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Space": "espacio", "Escape": "esc",
}

@onready var _options_button: Button = %OptionsButton
@onready var _controls_button: Button = %ControlsButton
@onready var _right_panel: Control = %RightPanel
@onready var _options_panel: Control = %OptionsPanel
@onready var _controls_panel: Control = %ControlsPanel
@onready var _sliders_box: VBoxContainer = %Sliders
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _controls_grid: GridContainer = %Grid

var _current_panel: InfoPanel = InfoPanel.NONE
var _sliders: Array[HSlider] = []
var _selected_style: StyleBoxFlat


## Estilo, paneles y conexiones comunes. 'buttons' = todos los botones de la lista (para darles estilo).
func _setup_menu(buttons: Array[Button]) -> void:
	_style_widgets(buttons)
	_build_sliders()
	_build_controls_grid()
	_fullscreen_check.set_pressed_no_signal(GameSettings.is_fullscreen())

	_options_button.pressed.connect(_toggle_panel.bind(InfoPanel.OPTIONS))
	_controls_button.pressed.connect(_toggle_panel.bind(InfoPanel.CONTROLS))
	_fullscreen_check.toggled.connect(GameSettings.set_fullscreen)


# ---------------------------------------------------------------- PANELES

## Apretar el botón del panel abierto lo oculta; apretar el del otro cambia de panel.
func _toggle_panel(panel: InfoPanel) -> void:
	_show_panel(InfoPanel.NONE if _current_panel == panel else panel)


func _show_panel(panel: InfoPanel) -> void:
	_current_panel = panel
	_right_panel.visible = panel != InfoPanel.NONE
	_options_panel.visible = panel == InfoPanel.OPTIONS
	_controls_panel.visible = panel == InfoPanel.CONTROLS
	# Con mando o teclado las opciones se ajustan desde el primer slider
	if panel == InfoPanel.OPTIONS and not _sliders.is_empty():
		_sliders[0].grab_focus()


## Si hay un panel abierto lo cierra y devuelve el foco a su botón. true = había uno abierto.
func _close_open_panel() -> bool:
	if _current_panel == InfoPanel.NONE:
		return false
	var came_from: Button = _options_button if _current_panel == InfoPanel.OPTIONS else _controls_button
	_show_panel(InfoPanel.NONE)
	came_from.grab_focus()
	return true


# ---------------------------------------------------------------- OPCIONES

## Un slider por cada bus de AudioBuses.OPTION_SLIDERS.
func _build_sliders() -> void:
	for entry: Array in AudioBuses.OPTION_SLIDERS:
		var bus: StringName = entry[0]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		_sliders_box.add_child(row)

		var name_label := _make_label(entry[1], 18, 110)
		row.add_child(name_label)

		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(200, 24)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.add_theme_stylebox_override("focus", _selected_style)
		slider.set_value_no_signal(GameSettings.get_volume(bus))
		row.add_child(slider)

		var value_label := _make_label("%d%%" % roundi(slider.value * 100.0), 16, 50)
		row.add_child(value_label)

		slider.value_changed.connect(func(value: float) -> void:
			GameSettings.set_volume(bus, value)
			value_label.text = "%d%%" % roundi(value * 100.0)
		)
		_sliders.append(slider)


# ---------------------------------------------------------------- CONTROLES

## Arma la tabla acción / teclado y mouse / mando leyendo el Input Map, así siempre refleja los controles reales.
func _build_controls_grid() -> void:
	for header in ["acción", "teclado y mouse", "mando"]:
		var label := _make_label(header, 14, 0)
		label.modulate = Color(1, 1, 1, 0.55)
		_controls_grid.add_child(label)

	for row: Array in CONTROL_ROWS:
		var keys: Array[String] = []
		var pad_frames: Array[int] = []
		for action: String in row[1]:
			for event in InputMap.action_get_events(action):
				if event is InputEventKey:
					var key_text: String = _key_text(event as InputEventKey)
					if key_text != "" and not keys.has(key_text):
						keys.append(key_text)
				elif event is InputEventMouseButton:
					var mouse_text: String = MOUSE_NAMES.get((event as InputEventMouseButton).button_index, "")
					if mouse_text != "" and not keys.has(mouse_text):
						keys.append(mouse_text)
				elif event is InputEventJoypadButton:
					var frame: int = PAD_FRAMES.get((event as InputEventJoypadButton).button_index, -1)
					if frame >= 0 and not pad_frames.has(frame):
						pad_frames.append(frame)
		var stick_frame: int = row[2]
		if stick_frame >= 0:
			pad_frames = [stick_frame] # el movimiento / la mirada van con el stick, no con la cruceta
		if row[3] != "":
			keys.append(row[3])

		_controls_grid.add_child(_make_label(row[0], 14, 130))
		_controls_grid.add_child(_make_label(" ".join(keys), 14, 150))
		_controls_grid.add_child(_make_icon_strip(pad_frames))


func _key_text(event: InputEventKey) -> String:
	var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	var text: String = OS.get_keycode_string(code)
	return KEY_NAMES.get(text, text)


## Fila de íconos de botón (los mismos del atlas de los carteles de tutorial).
func _make_icon_strip(frames: Array[int]) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 0)
	for frame in frames:
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(24, 22)
		var icon := AnimatedSprite2D.new()
		icon.sprite_frames = BUTTON_FRAMES
		icon.animation = &"buttons"
		icon.frame = frame
		icon.scale = Vector2(0.6, 0.6)
		icon.position = Vector2(12, 11)
		cell.add_child(icon)
		strip.add_child(cell)
	return strip


func _make_label(text: String, font_size: int, min_width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 8)
	return label


# ---------------------------------------------------------------- ESTILO

## Botones como las filas del inventario: gris translúcido, y el seleccionado más claro con una barra a la izquierda.
func _style_widgets(buttons: Array[Button]) -> void:
	var normal := _flat_style(Color(0.09, 0.09, 0.09, 0.37), 0)
	_selected_style = _flat_style(Color(0.3, 0.3, 0.3, 0.6), 3)
	for button: Button in buttons:
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", _selected_style)
		button.add_theme_stylebox_override("focus", _selected_style)
		button.add_theme_stylebox_override("pressed", _selected_style)
		button.add_theme_stylebox_override("disabled", normal)
		button.add_theme_font_size_override("font_size", 22)
		button.add_theme_constant_override("outline_size", 8)
		button.add_theme_color_override("font_outline_color", Color.BLACK)
		button.custom_minimum_size = Vector2(0, 38)
	_fullscreen_check.add_theme_stylebox_override("focus", _selected_style)


func _flat_style(color: Color, left_bar: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = left_bar
	style.border_color = Color(1, 1, 1, 0.9)
	style.content_margin_left = 14.0 + left_bar
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style

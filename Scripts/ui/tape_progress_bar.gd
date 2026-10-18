extends CanvasLayer
class_name TapeProgressBar

## Barra de carga al centro inferior de la pantalla: avanza mientras suena el cassette correcto.
## La crea y la maneja Level00Manager. Capa 127: por encima de las barras 4:3 (126) y por debajo del
## fundido a negro (128). Estética del inventario: fondo gris translúcido, texto en minúsculas con borde.

## PLAYING: suena la cinta correcta. PAUSED: la barra quieta (cinta afuera, otra cinta o canción terminada).
## TAPE_JUMPED: un golpe hizo saltar la cinta de la radio (texto rojo).
enum State { PLAYING, PAUSED, TAPE_JUMPED }

const COLOR_JUMPED: Color = Color(1.0, 0.25, 0.25)
const BAR_SIZE: Vector2 = Vector2(260.0, 10.0)
const BOTTOM_MARGIN: float = 22.0
const PADDING: float = 3.0

var _root: Control
var _fill: ColorRect
var _label: Label
var _fade_tween: Tween
var _ratio: float = 0.0


func _init() -> void:
	layer = 127
	visible = false


func _ready() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var box := Control.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -BAR_SIZE.x * 0.5 - PADDING
	box.offset_right = BAR_SIZE.x * 0.5 + PADDING
	box.offset_bottom = -BOTTOM_MARGIN
	box.offset_top = -BOTTOM_MARGIN - BAR_SIZE.y - PADDING * 2.0
	_root.add_child(box)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color(0.09, 0.09, 0.09, 0.55)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(background)

	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.color = Color(1, 1, 1, 0.85)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.position = Vector2(PADDING, PADDING)
	_fill.size = Vector2(0.0, BAR_SIZE.y)
	box.add_child(_fill)

	_label = Label.new()
	_label.name = "Label"
	_label.text = "reproduciendo"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.offset_left = -BAR_SIZE.x * 0.5
	_label.offset_right = BAR_SIZE.x * 0.5
	_label.offset_top = -24.0
	_label.offset_bottom = -2.0
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_constant_override("outline_size", 8)
	box.add_child(_label)

	_root.modulate.a = 0.0


## 0.0 a 1.0.
func set_progress(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	if is_instance_valid(_fill):
		_fill.size.x = BAR_SIZE.x * _ratio


## Cambia el texto, el color y la opacidad según el estado.
func set_state(state: State) -> void:
	if not is_instance_valid(_label):
		return
	match state:
		State.PLAYING:
			_label.text = "reproduciendo"
		State.PAUSED:
			_label.text = "en pausa"
		State.TAPE_JUMPED:
			_label.text = "saltó la cinta"
	if state == State.TAPE_JUMPED:
		_label.add_theme_color_override("font_color", COLOR_JUMPED)
	else:
		_label.remove_theme_color_override("font_color")
	_fill.color.a = 0.85 if state == State.PLAYING else 0.45


## Aparece con un fade (cada vez que suena el cassette correcto).
func show_bar() -> void:
	if visible and is_instance_valid(_root) and _root.modulate.a >= 1.0:
		return
	visible = true
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", 1.0, 0.6)


## Se apaga con un fade (el jugador guardó el cassette en el inventario). Vuelve con show_bar().
func hide_bar() -> void:
	if not visible or not is_instance_valid(_root):
		return
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", 0.0, 0.3)
	_fade_tween.tween_callback(func() -> void: visible = false)


func _kill_fade() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

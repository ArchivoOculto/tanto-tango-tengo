extends RefCounted
class_name ButtonPrompt

## Filas de menú con el formato "(     ) texto": el ícono de botón (AnimatedSprite2D, animación
## "buttons") se coloca sobre el hueco entre paréntesis. Se calcula midiendo la fuente, así sirve
## para cualquier texto (las acciones de los objetos son datos y su texto no se conoce de antemano).

const BLANK: String = "     "


static func make_text(text: String) -> String:
	return "(%s) %s" % [BLANK, text]


static func text_width(label: Label, text: String) -> float:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Configura una fila de anchura propia, centrada en 'center_x' (anchors al centro).
static func setup_row(label: Label, icon: AnimatedSprite2D, text: String, frame: int, center_x: float = -20.0) -> void:
	label.text = make_text(text)
	var full: float = text_width(label, label.text)
	var width: float = ceilf(full) + 4.0
	label.offset_left = center_x - width * 0.5
	label.offset_right = center_x + width * 0.5
	place_icon(label, icon, frame)


## Centra el ícono sobre el hueco "(     )" de un Label ya dimensionado.
static func place_icon(label: Label, icon: AnimatedSprite2D, frame: int) -> void:
	var full: float = text_width(label, label.text)
	var prefix: float = text_width(label, "(")
	var blank: float = text_width(label, BLANK)
	var width: float = label.offset_right - label.offset_left
	icon.frame = frame
	icon.position.x = (width - full) * 0.5 + prefix + blank * 0.5

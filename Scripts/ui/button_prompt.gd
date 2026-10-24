extends RefCounted
class_name ButtonPrompt

## Filas de menú con el formato "(     ) texto": el ícono de botón (AnimatedSprite2D, animación
## "buttons") se coloca sobre el hueco entre paréntesis. Se calcula midiendo la fuente, así sirve
## para cualquier texto (las acciones de los objetos son datos y su texto no se conoce de antemano).

const BLANK: String = "     "
const ICON_FRAMES: SpriteFrames = preload("res://Resources/ui/ui_buttons_frames.tres")

## Frames de la hoja de íconos (Assets/2D/UI_PS2_Buttons.png).
const FRAME_TRIANGLE: int = 0
const FRAME_SQUARE: int = 1
const FRAME_CIRCLE: int = 2
const FRAME_CROSS: int = 3
const FRAME_L1: int = 4
const FRAME_L2: int = 5
const FRAME_R1: int = 6
const FRAME_R2: int = 7
const FRAME_STICK_R: int = 8
const FRAME_STICK_L: int = 9


## Arma por código una fila "(ícono)(ícono) texto" con el mismo aspecto que las de los menús (tamaño 21, contorno 10,
## íconos al 80 %), para HUD que no viven en una escena. Queda centrada en 'center_x' y en y = 0, con anclas al centro:
## el llamador solo mueve offset_top / offset_bottom para ubicarla.
static func make_row(text: String, frames: Array[int], center_x: float = 0.0, font_size: int = 21, outline_size: int = 10) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", outline_size)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_top = -15.0
	label.offset_bottom = 15.0
	var icons: Array[AnimatedSprite2D] = []
	for i in frames.size():
		var icon := AnimatedSprite2D.new()
		icon.sprite_frames = ICON_FRAMES
		icon.animation = &"buttons"
		icon.scale = Vector2(0.8, 0.8)
		icon.position.y = 18.0
		label.add_child(icon)
		icons.append(icon)
	setup_row_icons(label, icons, text, frames, center_x)
	return label


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


## Como make_text pero con varios huecos seguidos: "(     )(     ) texto" (ej: dos gatillos para un mismo gesto).
static func make_text_multi(text: String, count: int) -> String:
	var slots: String = ""
	for i in count:
		slots += "(%s)" % BLANK
	return "%s %s" % [slots, text]


## Igual que setup_row pero con varios íconos en la misma fila ('icons' y 'frames' van en el mismo orden).
static func setup_row_icons(label: Label, icons: Array[AnimatedSprite2D], text: String, frames: Array[int], center_x: float = -20.0) -> void:
	label.text = make_text_multi(text, icons.size())
	var full: float = text_width(label, label.text)
	var width: float = ceilf(full) + 4.0
	label.offset_left = center_x - width * 0.5
	label.offset_right = center_x + width * 0.5
	var prefix: float = text_width(label, "(")
	var blank: float = text_width(label, BLANK)
	var slot: float = text_width(label, "(%s)" % BLANK)
	for i in icons.size():
		icons[i].frame = frames[i]
		icons[i].position.x = (width - full) * 0.5 + slot * i + prefix + blank * 0.5

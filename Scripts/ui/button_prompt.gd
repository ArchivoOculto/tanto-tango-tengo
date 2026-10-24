extends RefCounted
class_name ButtonPrompt

## Filas de menú con botones: "(ícono) texto" con un mando, "[tecla] texto" con teclado y mouse.
##
## Con un mando, el ícono de botón (AnimatedSprite2D, animación "buttons") se coloca sobre el hueco entre
## paréntesis "(     )" del texto. Se calcula midiendo la fuente, así sirve para cualquier texto (las acciones de
## los objetos son datos y su texto no se conoce de antemano). Con teclado y mouse el hueco se reemplaza por la
## tecla entre corchetes y los íconos se ocultan.
##
## Cada fila queda registrada y se rearma sola cuando InputDevice avisa que cambió el dispositivo (ver InputGlyph
## para cómo se arman los glifos). Uso:
##
##   ButtonPrompt.setup_row(label, icon, "cerrar", InputGlyph.for_action(&"interact"))
##   ButtonPrompt.setup_row_icons(label, [icon_a, icon_b], "zoom", InputGlyph.zoom())

const BLANK: String = "     "
const ICON_FRAMES: SpriteFrames = preload("res://Resources/ui/ui_buttons_frames.tres")
const META_SPEC: StringName = &"_button_prompt_spec"

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

static var _rows: Array = [] # Label: las filas vivas (se purgan las liberadas al refrescar)
static var _hooked: bool = false


static func make_text(text: String) -> String:
	return "(%s) %s" % [BLANK, text]


## Como make_text pero con varios huecos seguidos: "(     )(     ) texto" (ej: dos gatillos para un mismo gesto).
static func make_text_multi(text: String, count: int) -> String:
	var slots: String = ""
	for i in count:
		slots += "(%s)" % BLANK
	return "%s %s" % [slots, text]


static func text_width(label: Label, text: String) -> float:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Configura una fila de anchura propia, centrada en 'center_x' (anchors al centro), con un solo botón.
static func setup_row(label: Label, icon: AnimatedSprite2D, text: String, glyph: Dictionary, center_x: float = -20.0) -> void:
	setup_row_icons(label, [icon], text, [glyph], center_x)


## Igual que setup_row pero con varios botones en la misma fila ('icons' y 'glyphs' van en el mismo orden).
static func setup_row_icons(label: Label, icons: Array[AnimatedSprite2D], text: String, glyphs: Array, center_x: float = -20.0) -> void:
	label.set_meta(META_SPEC, {"icons": icons, "text": text, "glyphs": glyphs, "center_x": center_x})
	if not _rows.has(label):
		_rows.append(label)
	_hook()
	_apply(label)


## Arma por código una fila con el mismo aspecto que las de los menús (tamaño 21, contorno 10, íconos al 80 %), para
## HUD que no viven en una escena. Queda centrada en 'center_x' y en y = 0, con anclas al centro: el llamador solo
## mueve offset_top / offset_bottom para ubicarla.
static func make_row(text: String, glyphs: Array, center_x: float = 0.0, font_size: int = 21, outline_size: int = 10) -> Label:
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
	for i in glyphs.size():
		var icon := AnimatedSprite2D.new()
		icon.sprite_frames = ICON_FRAMES
		icon.animation = &"buttons"
		icon.scale = Vector2(0.8, 0.8)
		icon.position.y = 18.0
		label.add_child(icon)
		icons.append(icon)
	setup_row_icons(label, icons, text, glyphs, center_x)
	return label


## Ancho de la fila tal como está armada ahora (cambia al cambiar de dispositivo).
static func row_width(label: Label) -> float:
	return label.offset_right - label.offset_left


# ---------------------------------------------------------------- INTERNO

static func _hook() -> void:
	if _hooked:
		return
	_hooked = true
	InputDevice.changed.connect(_on_device_changed)


static func _on_device_changed(_gamepad: bool) -> void:
	var alive: Array = []
	for row in _rows:
		if is_instance_valid(row):
			alive.append(row)
			_apply(row as Label)
	_rows = alive


static func _apply(label: Label) -> void:
	var spec: Dictionary = label.get_meta(META_SPEC)
	var icons: Array = spec.icons
	var glyphs: Array = spec.glyphs
	var text: String = spec.text
	var center_x: float = spec.center_x

	# Con mando: íconos, salvo que alguno no tenga botón en el mando (entonces se escribe todo como texto)
	var show_icons: bool = InputDevice.using_gamepad
	for glyph: Dictionary in glyphs:
		if glyph.pad < 0:
			show_icons = false

	for icon: AnimatedSprite2D in icons:
		icon.visible = show_icons

	if show_icons:
		label.text = make_text_multi(text, icons.size())
		var full: float = text_width(label, label.text)
		var width: float = ceilf(full) + 4.0
		label.offset_left = center_x - width * 0.5
		label.offset_right = center_x + width * 0.5
		var prefix: float = text_width(label, "(")
		var blank: float = text_width(label, BLANK)
		var slot: float = text_width(label, "(%s)" % BLANK)
		for i in icons.size():
			var icon: AnimatedSprite2D = icons[i]
			icon.frame = glyphs[i].pad
			icon.position.x = (width - full) * 0.5 + slot * i + prefix + blank * 0.5
	else:
		var keys: Array[String] = []
		for glyph: Dictionary in glyphs:
			keys.append(InputGlyph.markup(glyph))
		label.text = "%s %s" % [" ".join(keys), text]
		var key_width: float = ceilf(text_width(label, label.text)) + 4.0
		label.offset_left = center_x - key_width * 0.5
		label.offset_right = center_x + key_width * 0.5

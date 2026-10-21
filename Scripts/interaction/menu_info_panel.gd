extends Control
class_name MenuInfoPanel

## Fondo oscuro + nombre + descripción para los menús de InteractableObject e InteractablePicture.
##
## DISPOSICIÓN: el texto va a la IZQUIERDA y el visor (el objeto 3D o la imagen) a la DERECHA. El panel
## mueve solo el texto; el visor se corre con MenuInfoPanel.shift_viewer(), que cada interactuable llama
## una vez sobre su "ObjectOnScreen"/"SpriteOnScreen" (esos nodos están anclados al centro de la pantalla y
## llevan adentro el fondo, el objeto y las pistas de botones: se mueven todos juntos).
##
## Se crea por código y cuelga del CanvasLayer del menú, por DETRÁS del visor. Las posiciones del nombre y
## la descripción son relativas al centro de la pantalla.
##
## PISTA (opcional): una línea extra en amarillo al final de la descripción, con la misma tipografía
## (ver ItemData.get_hint_text). El inventario la muestra igual (make_hint_label).

const DIM_COLOR: Color = Color(0, 0, 0, 0.55) ## el mismo oscurecido del inventario
## Color de la pista: el mismo amarillo del outline de los objetos y de la selección del inventario.
const HINT_COLOR: Color = Color(1.0, 0.9, 0.2)

## Cuánto se corre el visor hacia la derecha respecto del centro de la pantalla (px).
const VIEWER_SHIFT_X: float = 165.0

# Columna de texto, a la izquierda (relativa al centro de la pantalla; la imagen base mide 845 x 480).
# Queda DENTRO del área visible con las barras 4:3 (que tapan los ~102 px de cada costado): empieza en x = 112,
# así los márgenes quedan casi simétricos (112 a la izquierda del texto, 133 a la derecha del visor).
# Su borde derecho (112 + 330 = 442) deja ~20 px hasta el borde izquierdo del visor (462).
# Arriba queda alineada con el borde superior del visor (-125).
const TEXT_OFFSET: Vector2 = Vector2(-310.5, -125.0)
const TEXT_SIZE: Vector2 = Vector2(330.0, 250.0)
const TEXT_SEPARATION: int = 10 ## espacio entre nombre, descripción y pista

var _name_label: Label
var _description_label: Label
var _hint_label: Label


## Crea el panel como PRIMER hijo de 'canvas' (queda detrás del resto de la UI). Empieza oculto.
static func create(canvas: CanvasLayer) -> MenuInfoPanel:
	var panel := MenuInfoPanel.new()
	panel.name = "MenuInfoPanel"
	panel.visible = false
	canvas.add_child(panel)
	canvas.move_child(panel, 0)
	return panel


## Corre el visor ('ObjectOnScreen' o 'SpriteOnScreen') a la derecha de la pantalla. Es seguro llamarlo más
## de una vez sobre el mismo nodo: solo lo corre la primera.
static func shift_viewer(viewer_root: Control) -> void:
	if viewer_root == null or viewer_root.has_meta(&"viewer_shifted"):
		return
	viewer_root.set_meta(&"viewer_shifted", true)
	viewer_root.offset_left += VIEWER_SHIFT_X
	viewer_root.offset_right += VIEWER_SHIFT_X


## Etiqueta de pista: copia el tamaño de letra, el contorno y la transparencia de 'like' (la descripción),
## y solo cambia el color a amarillo.
static func make_hint_label(like: Label) -> Label:
	var hint := Label.new()
	hint.name = "ItemHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.autowrap_mode = like.autowrap_mode
	hint.modulate = like.modulate
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", like.get_theme_font_size("font_size"))
	hint.add_theme_constant_override("outline_size", like.get_theme_constant("outline_size"))
	hint.add_theme_color_override("font_color", HINT_COLOR)
	hint.visible = false
	return hint


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Nombre, descripción y pista van en una sola columna que fluye: un título largo pasa a dos líneas sin
	# pisar la descripción, y la pista queda justo debajo del texto sin importar cuántas líneas ocupe.
	var text_box := VBoxContainer.new()
	text_box.name = "TextBox"
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.set_anchors_preset(Control.PRESET_CENTER)
	text_box.offset_left = TEXT_OFFSET.x
	text_box.offset_top = TEXT_OFFSET.y
	text_box.offset_right = TEXT_OFFSET.x + TEXT_SIZE.x
	text_box.offset_bottom = TEXT_OFFSET.y + TEXT_SIZE.y
	text_box.add_theme_constant_override("separation", TEXT_SEPARATION)
	add_child(text_box)

	_name_label = Label.new()
	_name_label.name = "ItemName"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_font_size_override("font_size", 28)
	_name_label.add_theme_constant_override("outline_size", 12)
	text_box.add_child(_name_label)

	_description_label = Label.new()
	_description_label.name = "ItemDescription"
	_description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_description_label.modulate = Color(1, 1, 1, 0.85)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description_label.add_theme_font_size_override("font_size", 17)
	_description_label.add_theme_constant_override("outline_size", 8)
	text_box.add_child(_description_label)

	_hint_label = make_hint_label(_description_label)
	text_box.add_child(_hint_label)


## Texto del nombre, la descripción y la pista. Vacío = esa parte no se muestra.
func set_info(item_name: String, description: String, hint: String = "") -> void:
	_name_label.text = item_name
	_name_label.visible = item_name != ""
	_description_label.text = description
	_description_label.visible = description != ""
	_hint_label.text = hint
	_hint_label.visible = hint != ""


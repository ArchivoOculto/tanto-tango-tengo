extends Control
class_name MenuInfoPanel

## Fondo oscuro + nombre + descripción para los menús de InteractableObject e InteractablePicture,
## con la misma apariencia y posición que el inventario (ver Scenes/ui/inventory_menu.tscn).
##
## Se crea por código y cuelga del CanvasLayer del menú, por DETRÁS de ObjectOnScreen/SpriteOnScreen
## (que están centrados). Las posiciones del nombre y la descripción son relativas al centro de la
## pantalla, igual que la vista previa del inventario, así quedan a la derecha del objeto.

const DIM_COLOR: Color = Color(0, 0, 0, 0.55) ## el mismo oscurecido del inventario
const NAME_OFFSET: Vector2 = Vector2(167.5, -110.0) ## respecto del centro de la pantalla
const NAME_SIZE: Vector2 = Vector2(230.0, 44.0)
const DESC_OFFSET: Vector2 = Vector2(167.5, -60.0)
const DESC_SIZE: Vector2 = Vector2(195.0, 160.0)

var _name_label: Label
var _description_label: Label


## Crea el panel como PRIMER hijo de 'canvas' (queda detrás del resto de la UI). Empieza oculto.
static func create(canvas: CanvasLayer) -> MenuInfoPanel:
	var panel := MenuInfoPanel.new()
	panel.name = "MenuInfoPanel"
	panel.visible = false
	canvas.add_child(panel)
	canvas.move_child(panel, 0)
	return panel


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_name_label = _make_label("ItemName", NAME_OFFSET, NAME_SIZE, 28, 12)
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_description_label = _make_label("ItemDescription", DESC_OFFSET, DESC_SIZE, 17, 8)
	_description_label.modulate = Color(1, 1, 1, 0.85)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Texto del nombre y la descripción. Vacío = esa parte no se muestra.
func set_info(item_name: String, description: String) -> void:
	_name_label.text = item_name
	_name_label.visible = item_name != ""
	_description_label.text = description
	_description_label.visible = description != ""


func _make_label(label_name: String, offset: Vector2, label_size: Vector2, font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_left = offset.x
	label.offset_top = offset.y
	label.offset_right = offset.x + label_size.x
	label.offset_bottom = offset.y + label_size.y
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", outline)
	add_child(label)
	return label

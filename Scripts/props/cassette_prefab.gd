extends Node3D
class_name CassettePrefab

## Cassette reutilizable (escena Scenes/props/Cassette_Prefab.tscn). Se instancia una vez por cassette, en
## cualquier nivel, y cada instancia se personaliza desde el Inspector:
##
##  - 'track':        la canción que suena en la radio.
##  - 'title':        el nombre que se ve en el inventario y en el menú del objeto.
##  - 'description':  el texto que acompaña al nombre.
##  - 'cover_texture': (opcional) la arte de la tapa. Si queda vacía se usa la textura placeholder del modelo.
##
## Al iniciarse, arma el CassetteItem (el ítem del inventario) con esos datos y se lo asigna al
## InteractableObject. Cada instancia tiene su propio 'item_id', por lo que el inventario distingue varios
## cassettes aunque se parezcan.
##
## Si ya existe un recurso CassetteItem armado a mano, se puede asignar en 'item_override' y se usa tal cual
## (en ese caso 'track', 'title' y 'description' se ignoran).
##
## TEXTURA DE LA TAPA: 'cover_texture' reemplaza el albedo de la superficie 'cover_surface' del modelo, así
## que debe respetar el mismo mapeo UV que Assets/3D/Cassette/cassette.png (se puede pintar encima de esa
## imagen). Sin textura asignada no se toca el material.

@export_group("Cassette")
## La canción grabada.
@export var track: AudioStream
## Nombre del cassette (inventario y menú del objeto).
@export var title: String = "Cassette"
@export_multiline var description: String = "Una cinta magnética sin etiqueta. Quizás haya algo grabado."
## Identificador único del ítem. Vacío = se genera uno propio a partir de la ruta del nodo en el nivel.
@export var item_id: StringName = &""
## Género de la canción: el nivel sortea uno y solo el cassette de ese género lo termina.
@export var genre: CassetteItem.Genre = CassetteItem.Genre.NONE
## Opcional: un CassetteItem armado a mano que reemplaza a los datos de arriba.
@export var item_override: CassetteItem

@export_group("Apariencia")
## Arte de la tapa. Vacío = textura placeholder del modelo.
@export var cover_texture: Texture2D
## Superficie de la malla a la que se aplica 'cover_texture'.
@export var cover_surface: int = 0

@export_group("Nodos")
## El InteractableObject del cassette. Vacío = se busca entre sus hijos.
@export var interactable: InteractableObject

var item: CassetteItem


func _ready() -> void:
	if interactable == null:
		var found: Array[Node] = find_children("*", "InteractableObject", true, false)
		if not found.is_empty():
			interactable = found[0] as InteractableObject
	if interactable == null:
		push_warning("CassettePrefab '%s': no se encontró un InteractableObject." % name)
		return

	item = item_override if item_override != null else _build_item()
	interactable.item = item
	_apply_cover()


## Cambia la tapa en tiempo de ejecución (null = vuelve al placeholder).
func set_cover(texture: Texture2D) -> void:
	cover_texture = texture
	_apply_cover()


func _build_item() -> CassetteItem:
	var data := CassetteItem.new()
	data.id = item_id if item_id != &"" else StringName("cassette_%d" % absi(str(get_path()).hash()))
	data.display_name = title
	data.description = description
	data.track = track
	data.genre = genre
	return data


func _apply_cover() -> void:
	if cover_texture == null:
		return # sin tapa propia: queda el placeholder del modelo
	for found in find_children("*", "MeshInstance3D", true, false):
		if interactable and interactable.is_ancestor_of(found):
			continue
		var mesh_instance := found as MeshInstance3D
		if mesh_instance.mesh == null or cover_surface >= mesh_instance.mesh.get_surface_count():
			continue
		var base_material := mesh_instance.get_active_material(cover_surface) as StandardMaterial3D
		var cover_material: StandardMaterial3D = base_material.duplicate() if base_material else StandardMaterial3D.new()
		cover_material.albedo_texture = cover_texture
		mesh_instance.set_surface_override_material(cover_surface, cover_material)

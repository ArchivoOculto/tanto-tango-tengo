extends Node
class_name ContextVisibility

## Muestra u oculta su nodo PADRE (o 'target') según el contexto de juego. Sirve para carteles de
## tutorial, pistas de botones o cualquier cosa que solo tenga sentido en cierto momento.
##
## Uso: agregar este nodo como HIJO del cartel y elegir 'context'. El cartel no necesita script
## propio y el mismo componente sirve para nodos 2D (Control, Label, Sprite2D...) y 3D (Label3D,
## Sprite3D, MeshInstance3D...), con un fundido suave.
##
## Para sumar un contexto nuevo: agregar un valor al enum y un caso en _is_context_active().
## Se alimenta de señales de autoloads (CameraDirector, Inventory...), así que no hace falta
## buscar al jugador ni a ningún controlador.

enum Context {
	RIFLE_MODE, ## Visible mientras el modo fusil (primera persona) está activo.
	INVENTORY_OPEN, ## Visible mientras el inventario está abierto.
}

@export var context: Context = Context.RIFLE_MODE
## Nodo a mostrar/ocultar. Vacío = el padre.
@export var target: Node
@export_range(0.0, 3.0, 0.05, "suffix:s") var fade_duration: float = 0.25

var _tween: Tween
var _shown: bool = false


func _ready() -> void:
	if target == null:
		target = get_parent()
	CameraDirector.first_person_changed.connect(func(_active: bool): _update(true))
	Inventory.menu_opened.connect(func(): _update(true))
	Inventory.menu_closed.connect(func(): _update(true))
	_update(false) # estado inicial: sin fundido


func _is_context_active() -> bool:
	match context:
		Context.RIFLE_MODE:
			return CameraDirector.is_first_person()
		Context.INVENTORY_OPEN:
			return Inventory.menu_open
	return false


func _update(animate: bool) -> void:
	var should_show: bool = _is_context_active()
	if should_show == _shown and animate:
		return
	_shown = should_show
	_apply(should_show, animate and fade_duration > 0.0)


func _apply(show_target: bool, animate: bool) -> void:
	if target == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()

	var fade_nodes: Array[Node] = _fade_nodes()
	var from_alpha: float = 0.0 if show_target else 1.0
	var to_alpha: float = 1.0 if show_target else 0.0

	if show_target:
		_set_visible(true)
	if not animate:
		_set_alpha(fade_nodes, to_alpha)
		if not show_target:
			_set_visible(false)
		return

	_set_alpha(fade_nodes, _current_alpha(fade_nodes, from_alpha))
	_tween = create_tween()
	_tween.tween_method(func(alpha: float): _set_alpha(fade_nodes, alpha), _current_alpha(fade_nodes, from_alpha), to_alpha, fade_duration)
	if not show_target:
		_tween.tween_callback(func(): _set_visible(false))


func _set_visible(value: bool) -> void:
	if "visible" in target:
		target.visible = value


## Nodos a los que se les aplica el fundido: el propio objetivo y, en 3D, todos sus descendientes con
## 'transparency' (Label3D, Sprite3D, AnimatedSprite3D...), que no heredan la transparencia del padre.
func _fade_nodes() -> Array[Node]:
	var nodes: Array[Node] = [target]
	if target is Node3D:
		for child in target.find_children("*", "GeometryInstance3D", true, false):
			nodes.append(child)
	return nodes


func _set_alpha(nodes: Array[Node], alpha: float) -> void:
	for node in nodes:
		if node is CanvasItem:
			var color: Color = (node as CanvasItem).modulate
			color.a = alpha
			(node as CanvasItem).modulate = color
		elif node is GeometryInstance3D:
			(node as GeometryInstance3D).transparency = 1.0 - alpha


func _current_alpha(nodes: Array[Node], fallback: float) -> float:
	var node: Node = nodes[0]
	if node is CanvasItem:
		return (node as CanvasItem).modulate.a
	if node is GeometryInstance3D:
		return 1.0 - (node as GeometryInstance3D).transparency
	return fallback

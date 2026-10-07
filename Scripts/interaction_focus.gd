extends RefCounted
class_name InteractionFocus

## Arbitra entre varias zonas de interacción que contienen al jugador a la vez (por ejemplo, la
## radio y el cassette que acaba de saltar de ella).
##
## - Solo el objeto MÁS CERCANO al jugador recibe el foco: es el único que se resalta, muestra su
##   aviso y responde a "interact".
## - Mientras hay un menú abierto, solo ese menú tiene el foco: ningún otro puede abrirse encima.
##
## Los candidatos deben tener get_focus_position() -> Vector3.

static var _candidates: Array = []
static var _inspecting: Node = null


static func register(node: Node) -> void:
	if node not in _candidates:
		_candidates.append(node)


static func unregister(node: Node) -> void:
	_candidates.erase(node)
	if _inspecting == node:
		_inspecting = null


static func begin_inspection(node: Node) -> void:
	_inspecting = node


static func end_inspection(node: Node) -> void:
	if _inspecting == node:
		_inspecting = null


## ¿Hay algún menú de objeto/cuadro abierto?
static func has_open_menu() -> bool:
	return is_instance_valid(_inspecting)


static func is_focused(node: Node, player: Node3D) -> bool:
	if is_instance_valid(_inspecting):
		return _inspecting == node
	_candidates = _candidates.filter(func(c): return is_instance_valid(c))
	if node not in _candidates:
		return false
	if _candidates.size() == 1 or not is_instance_valid(player):
		return true
	var best: Node = null
	var best_distance: float = INF
	for candidate in _candidates:
		var distance: float = player.global_position.distance_squared_to(candidate.get_focus_position())
		if distance < best_distance - 0.000001:
			best_distance = distance
			best = candidate
	return best == node


## Vuelve al estado inicial (reinicio del juego).
static func reset() -> void:
	_candidates.clear()
	_inspecting = null

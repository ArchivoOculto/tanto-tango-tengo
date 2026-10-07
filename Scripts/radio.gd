extends Node3D
class_name Radio

## La radio del puzzle final. Va en el nodo que tiene la colisión (el StaticBody3D de la radio), porque
## la guitarra y el fusil buscan take_hit() subiendo desde el cuerpo que golpean.
##
##  - Se puede INSPECCIONAR con su InteractableObject, pero no guardar (no tiene 'item').
##  - Su InteractableObject debe tener una ObjectAction (id "play_tape") con 'required_item' = el
##    cassette y 'consume_required_item' = true. Al activarla (□) el cassette sale del inventario,
##    queda "dentro" de la radio y se emite tape_play_started: ahí se programa lo que sigue.
##  - Al GOLPEARLA se sacude (como los farolitos). Si tiene una cinta adentro, el cassette salta
##    de la radio, aterriza cerca y se puede volver a agarrar (se emite tape_ejected).
##
## IMPORTANTE: para que la guitarra la detecte, el StaticBody3D necesita estar en la capa 4 o 8
## (collision_layer = 9 conserva la capa 1 de "mundo" y suma la 8 de "props").

## Se activó "reproducir cinta": el cassette ya está dentro de la radio. Conectar acá la lógica propia.
signal tape_play_started(item: ItemData)
## El cassette saltó de la radio y volvió al mundo.
signal tape_ejected(item: ItemData)
## La radio recibió un golpe (con o sin cinta).
signal hit_received

enum State { IDLE, PLAYING_TAPE }

@export var interactable: InteractableObject ## El menú de la radio. Vacío = se busca entre sus hijos.
@export var visual: Node3D ## Nodo que se sacude. Vacío = el primer hijo 3D que tenga una malla.
@export var play_tape_action_id: StringName = &"play_tape"

@export_group("Sacudida")
@export var shake_duration: float = 0.35
@export var shake_strength: float = 0.08 ## Ángulo máximo en radianes

@export_group("Cassette")
## Dónde aparece el cassette al salir de la radio. Vacío = 'eject_offset' respecto de la radio.
@export var eject_point: Marker3D
## Dónde aterriza. Vacío = 'landing_offset' respecto de la radio.
@export var landing_point: Marker3D
@export var eject_offset: Vector3 = Vector3(0.0, 0.1, 0.0)
@export var landing_offset: Vector3 = Vector3(0.0, 0.0, 0.3)
@export var eject_delay: float = 0.12 ## Pausa entre el golpe y la expulsión
@export var hop_height: float = 0.4
@export var hop_duration: float = 0.55

var state: State = State.IDLE
var _inserted: InventoryEntry = null
var _shake_tween: Tween
var _rest_rotation: Vector3
var _eject_pending: bool = false


func _ready() -> void:
	if interactable == null:
		var found: Array[Node] = find_children("*", "InteractableObject", true, false)
		if not found.is_empty():
			interactable = found[0] as InteractableObject
	if interactable:
		interactable.action_triggered.connect(_on_action_triggered)
	else:
		push_warning("Radio: no se encontró un InteractableObject; no se podrá reproducir la cinta.")

	if visual == null:
		for child in get_children():
			var has_mesh: bool = child is MeshInstance3D or (child is Node3D and not (child is CollisionShape3D) \
					and not child.find_children("*", "MeshInstance3D", true, false).is_empty())
			if has_mesh:
				visual = child as Node3D
				break
	if visual:
		_rest_rotation = visual.rotation
	else:
		push_warning("Radio: no se encontró qué nodo sacudir (asignar 'visual').")


func is_playing_tape() -> bool:
	return state == State.PLAYING_TAPE


# ---------------------------------------------------------------- GOLPES

## Lo llaman WeaponHitbox (guitarra) y RifleController (fusil).
func take_hit(_damage: float = 0.0) -> void:
	hit_received.emit()
	_play_shake()
	if state == State.PLAYING_TAPE and not _eject_pending:
		_eject_pending = true
		get_tree().create_timer(eject_delay).timeout.connect(_eject_tape)


## Mismo movimiento que la sacudida de los farolitos: un vaivén que se amortigua y vuelve a la
## pose de reposo. Si llega otro golpe en pleno movimiento, se reinicia desde el reposo.
func _play_shake() -> void:
	if visual == null:
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	visual.rotation = _rest_rotation

	var step: float = shake_duration / 4.0
	var x1: float = randf_range(-shake_strength, shake_strength)
	var z1: float = randf_range(-shake_strength, shake_strength)
	var x2: float = -x1 * randf_range(0.3, 0.6)
	var z2: float = -z1 * randf_range(0.3, 0.6)

	_shake_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shake_tween.tween_property(visual, "rotation:x", _rest_rotation.x + x1, step)
	_shake_tween.parallel().tween_property(visual, "rotation:z", _rest_rotation.z + z1, step)
	_shake_tween.tween_property(visual, "rotation:x", _rest_rotation.x + x2, step)
	_shake_tween.parallel().tween_property(visual, "rotation:z", _rest_rotation.z + z2, step)
	_shake_tween.tween_property(visual, "rotation:x", _rest_rotation.x, step)
	_shake_tween.parallel().tween_property(visual, "rotation:z", _rest_rotation.z, step)
	_shake_tween.tween_property(visual, "rotation", _rest_rotation, step * 0.5)


# ---------------------------------------------------------------- CINTA

func _on_action_triggered(action: ObjectAction, consumed: InventoryEntry) -> void:
	if action == null or action.id != play_tape_action_id or state == State.PLAYING_TAPE:
		return
	if consumed == null:
		push_warning("Radio: la acción '%s' debe tener 'consume_required_item' activado para poder expulsar el cassette después." % play_tape_action_id)
	_inserted = consumed
	state = State.PLAYING_TAPE
	tape_play_started.emit(consumed.item if consumed else action.required_item)


func _eject_tape() -> void:
	_eject_pending = false
	if state != State.PLAYING_TAPE:
		return
	var entry: InventoryEntry = _inserted
	_inserted = null
	state = State.IDLE

	var source: InteractableObject = entry.source as InteractableObject if entry else null
	if is_instance_valid(source):
		source.drop_to_world(_eject_position(), _landing_position(), hop_height, hop_duration)
	tape_ejected.emit(entry.item if entry else null)


func _eject_position() -> Vector3:
	if is_instance_valid(eject_point):
		return eject_point.global_position
	return _local_to_world(eject_offset)


func _landing_position() -> Vector3:
	if is_instance_valid(landing_point):
		return landing_point.global_position
	return _local_to_world(landing_offset)


## Desplazamiento en el espacio de la radio, sin heredar la escala del modelo.
func _local_to_world(offset: Vector3) -> Vector3:
	var origin: Node3D = visual if visual else self
	return origin.global_position + origin.global_basis.orthonormalized() * offset

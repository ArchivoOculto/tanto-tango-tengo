extends Node3D
class_name Radio

## La radio del puzzle final. Va en el nodo que tiene la colisión (el StaticBody3D de la radio), porque
## la guitarra y el fusil buscan take_hit() subiendo desde el cuerpo que golpean.
##
##  - Se puede INSPECCIONAR con su InteractableObject, pero no guardar (no tiene 'item').
##  - Su InteractableObject debe tener una ObjectAction (id "play_tape") con 'required_item' = el
##    cassette y 'consume_required_item' = true. Al activarla (□) el cassette sale del inventario,
##    queda "dentro" de la radio y empieza a sonar su canción DESDE LA RADIO (audio 3D posicional).
##  - Al GOLPEARLA se sacude (como los farolitos). Si tiene una cinta adentro, el cassette salta de la
##    radio, aterriza cerca y se puede volver a agarrar. La radio se calla y el cassette RECUERDA en
##    qué punto de la canción quedó: al volver a colocarlo, sigue desde ahí.
##  - Mientras suena, la radio "baila": se mece sobre el eje Z al ritmo de la música.
##  - Mientras suena, con su menú abierto, rotar el objeto con el stick derecho altera levemente la
##    velocidad de reproducción (y por lo tanto el pitch), como si el stick fuera una palanca de la radio.
##  - Mientras suena, el menú ofrece "sacar cassette": la cinta vuelve directo al inventario.
##  - Con varios cassettes en el inventario, "reproducir cinta" abre un submenú para elegir cuál
##    (la acción debe usar 'required_item_category' = "cassette", ver ObjectAction).
##  - Cuando la canción termina se emite tape_finished (Level00Manager lo usa para cerrar el juego).
##
## La canción sale del cassette (CassetteItem.track). Si el ítem no es un CassetteItem se usa
## 'fallback_track'.
##
## IMPORTANTE: para que la guitarra la detecte, el StaticBody3D necesita estar en la capa 4 o 8
## (collision_layer = 9 conserva la capa 1 de "mundo" y suma la 8 de "props").

## Se activó "reproducir cinta": el cassette ya está dentro de la radio y empieza a sonar.
signal tape_play_started(item: ItemData)
## El cassette saltó de la radio y volvió al mundo (la canción queda en pausa en ese punto).
signal tape_ejected(item: ItemData)
## La canción llegó a su fin.
signal tape_finished(item: ItemData)
## La radio recibió un golpe (con o sin cinta).
signal hit_received

enum State { IDLE, PLAYING_TAPE, TAPE_FINISHED }

@export var interactable: InteractableObject ## El menú de la radio. Vacío = se busca entre sus hijos.
@export var visual: Node3D ## Nodo que se sacude. Vacío = el primer hijo 3D que tenga una malla.
@export var play_tape_action_id: StringName = &"play_tape"

@export_group("Reproducción")
## Canción de respaldo si el ítem insertado no es un CassetteItem.
@export var fallback_track: AudioStream
@export var volume_db: float = 0.0
## Distancia (m) a la que la canción se oye a volumen pleno; más lejos se atenúa. El mundo es chico: valores bajos.
@export var unit_size: float = 3.0
## Distancia máxima a la que se oye (0 = sin límite).
@export var max_distance: float = 0.0

@export_group("Baile")
@export var dance_enabled: bool = true
## Ángulo máximo del vaivén sobre el eje Z (grados, a cada lado).
@export_range(0.0, 20.0, 0.1, "suffix:°") var dance_angle_degrees: float = 3.0
## Segundos que tarda en ir de un extremo al otro (un compás). Menor = más rápido.
@export_range(0.05, 3.0, 0.01, "suffix:s") var dance_half_period: float = 0.35

@export_group("Pitch con el stick")
## Cuánto puede variar la velocidad de reproducción (0.12 = ±12%) con el stick al máximo.
@export_range(0.0, 0.5, 0.01) var pitch_wobble_range: float = 0.12
## Qué tan rápido sigue el pitch al stick (y vuelve a 1.0 al soltarlo).
@export var pitch_smoothing: float = 8.0

@export_group("Sacar cassette")
## Id de la acción del menú que devuelve el cassette al inventario (se agrega sola al menú de la radio).
@export var eject_to_inventory_action_id: StringName = &"eject_to_inventory"
@export var eject_to_inventory_label: String = "sacar cassette"

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
var _player: AudioStreamPlayer3D
var _shake_tween: Tween
var _rest_rotation: Vector3
var _eject_pending: bool = false
var _dance_tween: Tween
var _settle_tween: Tween
var _menu_open: bool = false
var _eject_action: ObjectAction


func _ready() -> void:
	if interactable == null:
		var found: Array[Node] = find_children("*", "InteractableObject", true, false)
		if not found.is_empty():
			interactable = found[0] as InteractableObject
	if interactable:
		interactable.action_triggered.connect(_on_action_triggered)
		interactable.opened.connect(func(): _menu_open = true)
		interactable.closed.connect(func(): _menu_open = false)
		interactable.action_filter = _is_action_available
		_eject_action = ObjectAction.new()
		_eject_action.id = eject_to_inventory_action_id
		_eject_action.label = eject_to_inventory_label
		_eject_action.input_action = &"object_action_2" # ✕
		_eject_action.icon_frame = 3
		interactable.add_action(_eject_action)
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

	# La canción suena DESDE la radio (audio posicional), no como un sonido global
	_player = AudioStreamPlayer3D.new()
	_player.name = "TapePlayer"
	_player.volume_db = volume_db
	_player.unit_size = unit_size
	_player.max_distance = max_distance
	(visual if visual else self).add_child(_player)
	_player.finished.connect(_on_track_finished)


func _process(delta: float) -> void:
	if _player == null:
		return
	# Con el menú abierto y la cinta sonando, el stick derecho (el mismo que rota el objeto) "toca" el pitch
	var target: float = 1.0
	if _menu_open and state == State.PLAYING_TAPE and _player.playing:
		var stick: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		target = 1.0 + clampf(stick.x - stick.y * 0.5, -1.0, 1.0) * pitch_wobble_range
	if is_equal_approx(_player.pitch_scale, target):
		return
	var weight: float = 1.0 - exp(-pitch_smoothing * delta)
	_player.pitch_scale = maxf(lerpf(_player.pitch_scale, target, weight), 0.05)
	if absf(_player.pitch_scale - target) < 0.001:
		_player.pitch_scale = target


## Qué acciones del menú de la radio están disponibles ahora.
func _is_action_available(action: ObjectAction) -> bool:
	if action == null:
		return false
	if action.id == play_tape_action_id:
		return not has_tape() # con una cinta adentro no se puede meter otra
	if action.id == eject_to_inventory_action_id:
		return state == State.PLAYING_TAPE
	return true


func is_playing_tape() -> bool:
	return state == State.PLAYING_TAPE


## true si hay un cassette dentro de la radio (sonando o terminado).
func has_tape() -> bool:
	return _inserted != null


# ---------------------------------------------------------------- GOLPES

## Lo llaman WeaponHitbox (guitarra) y RifleController (fusil).
func take_hit(_damage: float = 0.0) -> void:
	hit_received.emit()
	_play_shake()
	if has_tape() and not _eject_pending:
		_eject_pending = true
		get_tree().create_timer(eject_delay).timeout.connect(_eject_tape)


## Mismo movimiento que la sacudida de los farolitos: un vaivén que se amortigua y vuelve a la
## pose de reposo. Si llega otro golpe en pleno movimiento, se reinicia desde el reposo.
func _play_shake() -> void:
	if visual == null:
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_kill_dance()
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
	_shake_tween.finished.connect(_resume_dance_if_playing)


# ---------------------------------------------------------------- BAILE

## La radio se mece sobre el eje Z (de +ángulo a -ángulo) mientras suena la cinta.
func _start_dance() -> void:
	_kill_dance()
	if not dance_enabled or visual == null or dance_angle_degrees <= 0.0:
		return
	var angle: float = deg_to_rad(dance_angle_degrees)
	_dance_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_dance_tween.tween_property(visual, "rotation:z", _rest_rotation.z + angle, dance_half_period)
	_dance_tween.tween_property(visual, "rotation:z", _rest_rotation.z - angle, dance_half_period)


## Corta el baile y vuelve suavemente a la pose de reposo.
func _stop_dance() -> void:
	var was_dancing: bool = _dance_tween != null and _dance_tween.is_valid()
	_kill_dance()
	if not was_dancing or visual == null:
		return
	if _settle_tween and _settle_tween.is_valid():
		_settle_tween.kill()
	_settle_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_settle_tween.tween_property(visual, "rotation", _rest_rotation, 0.15)


func _kill_dance() -> void:
	if _dance_tween and _dance_tween.is_valid():
		_dance_tween.kill()
	_dance_tween = null
	if _settle_tween and _settle_tween.is_valid():
		_settle_tween.kill()


func _resume_dance_if_playing() -> void:
	if state == State.PLAYING_TAPE and _player and _player.playing:
		_start_dance()


# ---------------------------------------------------------------- CINTA

func _on_action_triggered(action: ObjectAction, consumed: InventoryEntry) -> void:
	if action != null and action.id == eject_to_inventory_action_id:
		_eject_to_inventory()
		return
	if action == null or action.id != play_tape_action_id or has_tape():
		return
	if consumed == null:
		push_warning("Radio: la acción '%s' debe tener 'consume_required_item' activado para poder expulsar el cassette después." % play_tape_action_id)
		return
	_inserted = consumed
	state = State.PLAYING_TAPE
	_start_playback()
	_resume_dance_if_playing()
	tape_play_started.emit(consumed.item)


## Empieza a sonar la canción del cassette, desde el punto donde quedó (0 si nunca se reprodujo).
func _start_playback() -> void:
	var track: AudioStream = _track_of(_inserted.item)
	if track == null:
		push_warning("Radio: el cassette no tiene canción (asignar 'track' en el CassetteItem o 'fallback_track' en la radio).")
		return
	var from: float = float(_inserted.state.get(CassetteItem.STATE_POSITION, 0.0))
	if from >= track.get_length() - 0.05:
		from = 0.0 # estaba prácticamente al final: se vuelve a empezar
	_player.stream = track
	_player.pitch_scale = 1.0
	_player.play(from)


## Detiene la canción y devuelve el punto (en segundos) donde estaba.
func _stop_playback() -> float:
	if _player == null or not _player.playing:
		return 0.0
	var length: float = _player.stream.get_length() if _player.stream else 0.0
	var played: float = _player.get_playback_position() + AudioServer.get_time_since_last_mix()
	_player.stop()
	_player.pitch_scale = 1.0
	return clampf(played, 0.0, length)


func _track_of(item: ItemData) -> AudioStream:
	if item is CassetteItem and (item as CassetteItem).track != null:
		return (item as CassetteItem).track
	return fallback_track


func _on_track_finished() -> void:
	if state != State.PLAYING_TAPE or _inserted == null:
		return
	state = State.TAPE_FINISHED
	_stop_dance()
	_player.pitch_scale = 1.0
	_inserted.state[CassetteItem.STATE_POSITION] = 0.0 # terminó: si se vuelve a poner, arranca de cero
	tape_finished.emit(_inserted.item)


func _eject_tape() -> void:
	_eject_pending = false
	if _inserted == null:
		return
	var entry: InventoryEntry = _inserted
	_inserted = null

	# El cassette recuerda hasta dónde se reprodujo (si ya había terminado, vuelve a empezar de cero)
	var played: float = _stop_playback() if state == State.PLAYING_TAPE else 0.0
	entry.state[CassetteItem.STATE_POSITION] = played
	state = State.IDLE
	_stop_dance()

	var source: InteractableObject = entry.source as InteractableObject
	if is_instance_valid(source):
		source.drop_to_world(_eject_position(), _landing_position(), hop_height, hop_duration)
	tape_ejected.emit(entry.item)


## Saca el cassette (desde el menú de la radio) y lo guarda directo en el inventario del jugador.
func _eject_to_inventory() -> void:
	if _inserted == null:
		return
	var entry: InventoryEntry = _inserted
	_inserted = null

	var played: float = _stop_playback() if state == State.PLAYING_TAPE else 0.0
	entry.state[CassetteItem.STATE_POSITION] = played # el cassette recuerda dónde quedó
	state = State.IDLE
	_stop_dance()

	var source: InteractableObject = entry.source as InteractableObject
	var stored: bool = is_instance_valid(source) and source.store_in_inventory_now()
	if not stored and is_instance_valid(source):
		# Sin posibilidad de guardarlo (no debería pasar): que al menos salte al mundo
		source.drop_to_world(_eject_position(), _landing_position(), hop_height, hop_duration)
	tape_ejected.emit(entry.item)


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

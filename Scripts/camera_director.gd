extends Node

## Autoload (Project Settings > Autoload, nombre "CameraDirector").
##
## Decide qué CameraZone3D está activa y quién controla la vista:
##  - Zonas físicas: el jugador entra/sale de su Area3D. Si hay varias a la vez
##    gana la de mayor 'zone_priority'; en un empate, la que entró primero.
##  - Zonas forzadas (cinemáticas/puzzles): una pila que ignora la prioridad de
##    las zonas físicas. Ver force_zone() / release_zone().
##  - Primera persona (modo fusil): una Camera3D externa toma la vista. Las
##    zonas siguen registrándose por debajo, así que al salir la GameCamera
##    retoma exactamente la zona que corresponda.
##  - Formato 4:3: es el único que decide si hay que mostrar las barras negras
##    (zona con 'force_4_3' o modo fusil) y lo anuncia con letterbox_changed.

signal zone_changed(previous_zone: CameraZone3D, new_zone: CameraZone3D)
## Se emite cada vez que alguien fuerza una zona (cinemática/puzzle), aunque esa
## zona ya fuera la actual. El modo fusil escucha esto para cederle el paso.
signal zone_forced(zone: CameraZone3D)
## Se emite al entrar/salir del modo primera persona (fusil).
signal first_person_changed(active: bool)
## Única fuente de verdad para las barras 4:3 (la consume LetterboxController).
signal letterbox_changed(active: bool, duration: float)

## Cámara de primera persona que tiene el control ahora mismo (null = modo normal).
var first_person_camera: Camera3D = null

var current_zone: CameraZone3D = null
var _active_zones: Array[CameraZone3D] = []   # zonas físicas (Area3D con el jugador adentro)
var _forced_zones: Array[CameraZone3D] = []   # pila de forzados manuales (cinemáticas/puzzles)

var _letterbox_active: bool = false
var _letterbox_duration: float = 0.6          # duración con la que se activó; se reutiliza al desactivar
var _fp_letterbox: bool = false
var _fp_letterbox_duration: float = 0.6


func register_zone_enter(zone: CameraZone3D) -> void:
	if zone not in _active_zones:
		_active_zones.append(zone)
	_recompute_current_zone()


func register_zone_exit(zone: CameraZone3D) -> void:
	_active_zones.erase(zone)
	_recompute_current_zone()


## Fuerza la cámara a 'zone' sin importar la prioridad de ninguna zona física.
## Pensado para eventos/cinemáticas: un puzzle resuelto, un farol que abre una
## puerta, etc.
##
## Es una pila: si dos sistemas distintos fuerzan casi al mismo tiempo, gana el
## último que lo pidió de forma determinística. Al liberar, se vuelve al
## forzado anterior si todavía queda uno activo, o a la zona física si no queda
## ninguno.
##
## Una cinemática SIEMPRE tiene prioridad sobre el modo fusil: el modo fusil se
## cierra solo al recibir zone_forced y no deja volver a entrar mientras haya
## alguna zona forzada.
func force_zone(zone: CameraZone3D) -> void:
	if zone == null or zone in _forced_zones:
		return
	_forced_zones.append(zone)
	zone_forced.emit(zone)
	_recompute_current_zone()


## Retira 'zone' de la pila de forzados.
func release_zone(zone: CameraZone3D) -> void:
	_forced_zones.erase(zone)
	_recompute_current_zone()


## true mientras haya una cinemática/puzzle forzando la cámara.
func has_forced_zone() -> bool:
	return not _forced_zones.is_empty()


## Descarta cualquier zona activa Y cualquier forzado previo, dejando 'zone'
## como la única/actual. Pensado para warps: el destino queda "dentro" de su
## CameraZone3D de forma inmediata, sin esperar al frame de detección física
## y sin que compita con nada que haya quedado forzado de antes.
func reset_to_zone(zone: CameraZone3D) -> void:
	_active_zones.clear()
	_forced_zones.clear()
	if zone:
		_active_zones.append(zone)
	_set_current_zone(zone)


## Vuelve al estado de arranque. Es un autoload: sobrevive a los cambios y recargas de
## escena, así que sin esto quedarían zonas ya liberadas en las listas (y la cámara
## fallaría en la segunda partida). Se llama al reiniciar el juego y al empezar el nivel.
func reset() -> void:
	var was_first_person: bool = first_person_camera != null
	var previous: CameraZone3D = current_zone if is_instance_valid(current_zone) else null

	_active_zones.clear()
	_forced_zones.clear()
	first_person_camera = null
	_fp_letterbox = false
	current_zone = null

	if previous != null:
		zone_changed.emit(previous, null)
	if _letterbox_active:
		_letterbox_active = false
		letterbox_changed.emit(false, 0.0) # barras fuera al instante
	if was_first_person:
		first_person_changed.emit(false)


# ---------------------------------------------------------------- PRIMERA PERSONA

## Entrega el control de la vista a 'cam' (cámara en primera persona).
## Si 'letterbox' es true, también pide las barras 4:3 desde este momento.
func enter_first_person(cam: Camera3D, letterbox: bool = true, letterbox_duration: float = 0.6) -> void:
	if cam == null:
		return
	first_person_camera = cam
	cam.make_current()
	_fp_letterbox = letterbox
	_fp_letterbox_duration = letterbox_duration
	_refresh_letterbox()
	first_person_changed.emit(true)


## Activa/desactiva solo las barras 4:3 del modo fusil, sin soltar la cámara.
## Sirve para retraerlas al EMPEZAR la salida, mientras la cámara todavía vuelve.
func set_first_person_letterbox(enabled: bool, duration: float = 0.6) -> void:
	if first_person_camera == null:
		return
	_fp_letterbox = enabled
	_fp_letterbox_duration = duration
	_refresh_letterbox()


## Devuelve la vista a la GameCamera (cámaras semifijas por zonas).
func exit_first_person() -> void:
	if first_person_camera == null:
		return
	first_person_camera = null
	_fp_letterbox = false
	var game_cam: Camera3D = get_tree().get_first_node_in_group("game_camera")
	if is_instance_valid(game_cam):
		game_cam.make_current()
	_refresh_letterbox()
	first_person_changed.emit(false)


func is_first_person() -> bool:
	return first_person_camera != null


# ---------------------------------------------------------------- INTERNO

func _recompute_current_zone() -> void:
	if not _forced_zones.is_empty():
		_set_current_zone(_forced_zones.back())
		return

	var best: CameraZone3D = null
	for zone in _active_zones:
		if best == null or zone.zone_priority > best.zone_priority:
			best = zone
	_set_current_zone(best)


func _set_current_zone(zone: CameraZone3D) -> void:
	if zone == current_zone:
		return
	var previous: CameraZone3D = current_zone
	current_zone = zone
	zone_changed.emit(previous, zone)
	_refresh_letterbox()


## Recalcula si corresponden las barras 4:3 y avisa SOLO cuando cambia.
## Con varias fuentes (zona y modo fusil) las barras se quedan mientras
## alguna las pida.
func _refresh_letterbox() -> void:
	var zone_wants: bool = is_instance_valid(current_zone) and current_zone.force_4_3
	var wanted: bool = _fp_letterbox or zone_wants

	# Duración de la fuente que manda ahora. Se recuerda para reutilizarla al
	# apagar (al desactivar se usa la de quien las tenía activas).
	var duration: float = _letterbox_duration
	if _fp_letterbox:
		duration = _fp_letterbox_duration
	elif zone_wants:
		duration = current_zone.aspect_transition_duration

	if wanted == _letterbox_active:
		if wanted:
			_letterbox_duration = duration
		return

	_letterbox_active = wanted
	_letterbox_duration = duration
	letterbox_changed.emit(wanted, duration)

extends Node

## Autoload (Project Settings > Autoload, nombre "CameraDirector").

signal zone_changed(previous_zone: CameraZone3D, new_zone: CameraZone3D)
## Se emite al entrar/salir del modo primera persona (fusil).
signal first_person_changed(active: bool)

## Cámara de primera persona que tiene el control ahora mismo (null = modo normal).
var first_person_camera: Camera3D = null

var current_zone: CameraZone3D = null
var _active_zones: Array[CameraZone3D] = []   # zonas físicas (Area3D con el jugador adentro)
var _forced_zones: Array[CameraZone3D] = []   # pila de forzados manuales (cinemáticas/puzzles)


func register_zone_enter(zone: CameraZone3D) -> void:
	if zone not in _active_zones:
		_active_zones.append(zone)
	_recompute_current_zone()


func register_zone_exit(zone: CameraZone3D) -> void:
	_active_zones.erase(zone)
	_recompute_current_zone()


## Fuerza la cámara a 'zone' sin importar la prioridad de ninguna zona física
## y SIN tocar la prioridad de nadie (a diferencia de la versión anterior).
## Pensado para eventos/cinemáticas: un puzzle resuelto, un farol que abre
## una puerta, etc.
##
## Es una pila: si dos sistemas distintos fuerzan casi al mismo tiempo (ej.
## el mismo farol dispara dos triggers independientes), gana el último que
## lo pidió de forma determinística — ya no es una moneda al aire por empate
## de prioridad. Al liberar, se vuelve al forzado anterior si todavía queda
## uno activo, o a la zona física si no queda ninguno.
func force_zone(zone: CameraZone3D) -> void:
	if zone == null or zone in _forced_zones:
		return
	_forced_zones.append(zone)
	_recompute_current_zone()


## Retira 'zone' de la pila de forzados.
func release_zone(zone: CameraZone3D) -> void:
	_forced_zones.erase(zone)
	_recompute_current_zone()


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


## Entrega el control de la vista a 'cam' (cámara en primera persona).
## Las CameraZone3D siguen registrándose por debajo, así que al salir la
## GameCamera retoma exactamente la zona que corresponda.
func enter_first_person(cam: Camera3D) -> void:
	if cam == null or first_person_camera == cam:
		return
	first_person_camera = cam
	cam.make_current()
	first_person_changed.emit(true)


## Devuelve la vista a la GameCamera (cámaras semifijas por zonas).
func exit_first_person() -> void:
	if first_person_camera == null:
		return
	first_person_camera = null
	var game_cam: Camera3D = get_tree().get_first_node_in_group("game_camera")
	if is_instance_valid(game_cam):
		game_cam.make_current()
	first_person_changed.emit(false)


func is_first_person() -> bool:
	return first_person_camera != null


func _recompute_current_zone() -> void:
	if not _forced_zones.is_empty():
		_set_current_zone(_forced_zones.back())
		return

	var best: CameraZone3D = null
	for zone in _active_zones:
		if best == null or zone.priority > best.priority:
			best = zone
	_set_current_zone(best)


func _set_current_zone(zone: CameraZone3D) -> void:
	if zone == current_zone:
		return
	var previous: CameraZone3D = current_zone
	current_zone = zone
	zone_changed.emit(previous, zone)

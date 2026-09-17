extends Node

## Autoload (Project Settings > Autoload, nombre "CameraDirector").

signal zone_changed(previous_zone: CameraZone3D, new_zone: CameraZone3D)

var current_zone: CameraZone3D = null
var _active_zones: Array[CameraZone3D] = []


func register_zone_enter(zone: CameraZone3D) -> void:
	if not is_instance_valid(zone) or zone.is_queued_for_deletion():
		return
	if zone not in _active_zones:
		_active_zones.append(zone)
	_recompute_current_zone()


func register_zone_exit(zone: CameraZone3D) -> void:
	if not is_instance_valid(zone):
		return
	_active_zones.erase(zone)
	_recompute_current_zone()


## Forzar manualmente una zona de cámara (ej. para eventos/cinemáticas)
func force_zone(zone: CameraZone3D) -> void:
	if not is_instance_valid(zone) or zone.is_queued_for_deletion():
		return
	if zone not in _active_zones:
		_active_zones.append(zone)
	_recompute_current_zone()


## Retirar la zona forzada para volver a la cámara del jugador/área normal
func release_zone(zone: CameraZone3D) -> void:
	if not is_instance_valid(zone):
		return
	_active_zones.erase(zone)
	_recompute_current_zone()


## Descarta cualquier zona activa previa y deja 'zone' como la única/actual.
## Pensado para warps: el destino queda "dentro" de su CameraZone3D de forma
## inmediata, sin esperar al frame de detección física y sin competir en
## prioridad con zonas de las que el jugador acaba de desaparecer.
func reset_to_zone(zone: CameraZone3D) -> void:
	_active_zones.clear()
	if is_instance_valid(zone) and not zone.is_queued_for_deletion():
		_active_zones.append(zone)
		_set_current_zone(zone)
	else:
		_set_current_zone(null)


func _recompute_current_zone() -> void:
	# Purga las zonas de la escena anterior que fueron liberadas de la memoria
	_active_zones = _active_zones.filter(
		func(z): return is_instance_valid(z) and not z.is_queued_for_deletion()
	)

	var best: CameraZone3D = null
	for zone in _active_zones:
		if best == null or zone.priority > best.priority:
			best = zone
	_set_current_zone(best)


func _set_current_zone(zone: CameraZone3D) -> void:
	if zone == current_zone:
		return
	# Si current_zone ya fue liberado, enviamos null como valor previo
	var previous: CameraZone3D = current_zone if is_instance_valid(current_zone) else null
	current_zone = zone
	zone_changed.emit(previous, zone)
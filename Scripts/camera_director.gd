extends Node

## Autoload (Project Settings > Autoload, nombre "CameraDirector").

var current_zone: CameraZone3D = null
var _active_zones: Array[CameraZone3D] = []


func register_zone_enter(zone: CameraZone3D) -> void:
	if zone not in _active_zones:
		_active_zones.append(zone)
	_recompute_current_zone()


func register_zone_exit(zone: CameraZone3D) -> void:
	_active_zones.erase(zone)
	_recompute_current_zone()


## Forzar manualmente una zona de cámara (ej. para eventos/cinemáticas)
func force_zone(zone: CameraZone3D) -> void:
	if zone not in _active_zones:
		_active_zones.append(zone)
	_recompute_current_zone()


## Retirar la zona forzada para volver a la cámara del jugador/área normal
func release_zone(zone: CameraZone3D) -> void:
	_active_zones.erase(zone)
	_recompute_current_zone()


func _recompute_current_zone() -> void:
	var best: CameraZone3D = null
	for zone in _active_zones:
		if best == null or zone.priority > best.priority:
			best = zone
	current_zone = best
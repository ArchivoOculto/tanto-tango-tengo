extends Node
class_name FarolitoPuzzleTrigger

@export_group("Referencias")
@export var farolito: Farolito
@export var target_cam_zone: CameraZone3D
@export var door: Door

@export_group("Comportamiento de Cámara")
@export var is_permanent_camera: bool = false
@export var display_duration: float = 3.0
@export var forced_priority: int = 999

@export_subgroup("Override de Velocidad")
@export var override_camera_speed: bool = false
@export var custom_smoothing: float = 0.2

@export_group("Tiempos de Acción")
## Tiempo en segundos que espera la puerta para actuar tras cambiar la cámara
@export var door_action_delay: float = 0.4

var _original_priority: int
var _original_smoothing: float
var _is_camera_focused: bool = false


func _ready() -> void:
	if farolito:
		farolito.toggled.connect(_on_farolito_toggled)


func _on_farolito_toggled(is_on: bool) -> void:
	if is_on:
		_execute_open_trigger()
	else:
		_execute_close_trigger()


func _execute_open_trigger() -> void:
	# 1. Mover cámara hacia la puerta
	if target_cam_zone:
		_original_priority = target_cam_zone.priority
		_original_smoothing = target_cam_zone.follow_smoothing
		
		if override_camera_speed:
			target_cam_zone.follow_smoothing = custom_smoothing

		target_cam_zone.priority = forced_priority
		CameraDirector.force_zone(target_cam_zone)
		_is_camera_focused = true

	# 2. Esperar delay de apertura
	if door_action_delay > 0.0:
		await get_tree().create_timer(door_action_delay).timeout

	# Verificar si el farol sigue encendido antes de abrir (por si lo apagaron volando)
	if farolito and not farolito.is_on:
		return

	# 3. Abrir la puerta
	if door:
		door.open()

	# 4. Manejo de duración si NO es permanente
	if target_cam_zone and _is_camera_focused:
		if not is_permanent_camera:
			await get_tree().create_timer(display_duration).timeout
			if _is_camera_focused:
				_restore_camera_zone()
		else:
			if not target_cam_zone.body_exited.is_connected(_on_zone_body_exited):
				target_cam_zone.body_exited.connect(_on_zone_body_exited)


func _execute_close_trigger() -> void:
	# 1. Si la cámara aún estaba enfocando la puerta por el evento, devolverla inmediatamente al jugador
	if _is_camera_focused:
		_restore_camera_zone()

	# 2. Cerrar la puerta rápidamente
	if door:
		door.close()


func _on_zone_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		if target_cam_zone and target_cam_zone.body_exited.is_connected(_on_zone_body_exited):
			target_cam_zone.body_exited.disconnect(_on_zone_body_exited)
		
		_restore_camera_zone()


func _restore_camera_zone() -> void:
	if target_cam_zone and _is_camera_focused:
		_is_camera_focused = false
		CameraDirector.release_zone(target_cam_zone)
		target_cam_zone.priority = _original_priority
		target_cam_zone.follow_smoothing = _original_smoothing
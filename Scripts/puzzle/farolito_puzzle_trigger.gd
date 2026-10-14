extends Node
class_name FarolitoPuzzleTrigger

@export_group("Referencias")
@export var farolito: Farolito
@export var target_cam_zone: CameraZone3D
@export var door: Door

@export_group("Comportamiento de Cámara")
@export var is_permanent_camera: bool = false
@export var display_duration: float = 3.0

@export_subgroup("Override de Velocidad")
@export var override_camera_speed: bool = false
@export var custom_smoothing: float = 0.2

@export_group("Tiempos de Acción")
## Tiempo en segundos que espera la puerta para actuar tras cambiar la cámara
@export var door_action_delay: float = 0.4

var _original_smoothing: float
var _is_camera_focused: bool = false

# Se incrementa en cada toggle. Permite que una ejecución vieja que sigue
# esperando un timer detecte que quedó obsoleta (porque el farol se volvió a
# tocar mientras tanto) y no pise el estado de la ejecución más nueva.
var _request_id: int = 0


func _ready() -> void:
	if farolito:
		farolito.toggled.connect(_on_farolito_toggled)

	if target_cam_zone:
		_original_smoothing = target_cam_zone.follow_smoothing


func _on_farolito_toggled(is_on: bool) -> void:
	_request_id += 1
	if is_on:
		_execute_open_trigger(_request_id)
	else:
		_execute_close_trigger()


func _execute_open_trigger(my_id: int) -> void:
	_focus_camera()

	if door_action_delay > 0.0:
		await get_tree().create_timer(door_action_delay).timeout

	# Una interacción más nueva ya tomó el control mientras esperábamos
	if my_id != _request_id:
		return

	# El farol pudo haberse apagado de nuevo durante la espera
	if farolito and farolito.current_state != Farolito.State.ON:
		_restore_camera_zone()
		return

	if door:
		door.open()

	if not _is_camera_focused:
		return

	if is_permanent_camera:
		if not target_cam_zone.body_exited.is_connected(_on_zone_body_exited):
			target_cam_zone.body_exited.connect(_on_zone_body_exited)
		return

	await get_tree().create_timer(display_duration).timeout
	if my_id != _request_id:
		return
	_restore_camera_zone()


func _execute_close_trigger() -> void:
	_restore_camera_zone()

	if door:
		door.close()


func _focus_camera() -> void:
	if not target_cam_zone or _is_camera_focused:
		return

	_is_camera_focused = true

	if override_camera_speed:
		target_cam_zone.follow_smoothing = custom_smoothing

	CameraDirector.force_zone(target_cam_zone)


func _on_zone_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		if target_cam_zone and target_cam_zone.body_exited.is_connected(_on_zone_body_exited):
			target_cam_zone.body_exited.disconnect(_on_zone_body_exited)

		_restore_camera_zone()


func _restore_camera_zone() -> void:
	if not target_cam_zone or not _is_camera_focused:
		return

	_is_camera_focused = false
	CameraDirector.release_zone(target_cam_zone)
	target_cam_zone.follow_smoothing = _original_smoothing

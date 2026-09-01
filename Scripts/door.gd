extends AnimatableBody3D
class_name Door

## Ángulo relativo en grados sobre el eje Y para abrir la puerta
@export var open_angle_y: float = 90.0

## Tiempo en segundos que tarda en ABRIR
@export var open_duration: float = 1.2

## Tiempo en segundos que tarda en CERRAR (más rápido para dar peso/urgencia)
@export var close_duration: float = 0.4

## Sonido opcional al abrir/cerrar
@export var open_sound: AudioStreamPlayer3D
@export var close_sound: AudioStreamPlayer3D

var is_open: bool = false
var _initial_rotation_y: float
var _active_tween: Tween


func _ready() -> void:
	_initial_rotation_y = rotation.y


func open() -> void:
	if is_open:
		return
	is_open = true
	
	if open_sound:
		open_sound.play()

	if _active_tween and _active_tween.is_running():
		_active_tween.kill()

	var target_y: float = _initial_rotation_y + deg_to_rad(open_angle_y)
	
	_active_tween = create_tween()
	_active_tween.tween_property(self, "rotation:y", target_y, open_duration)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)


func close() -> void:
	if not is_open:
		return
	is_open = false
	
	if close_sound:
		close_sound.play()

	if _active_tween and _active_tween.is_running():
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.tween_property(self, "rotation:y", _initial_rotation_y, close_duration)\
		.set_trans(Tween.TRANS_BOUNCE if close_duration > 0.6 else Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
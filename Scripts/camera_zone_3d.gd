extends Area3D
class_name CameraZone3D

@export var camera_anchor: Node3D
@export var follow_smoothing: float = 2.0

@export_group("Formato 4:3")
@export var force_4_3: bool = false ## Si es true, mientras esta zona esté activa la pantalla se recorta a 4:3 con barras negras (ver LetterboxController)
@export var aspect_transition_duration: float = 0.6 ## Duración de la animación de las barras al entrar/salir de esta zona


func _ready() -> void:
	# Asegura que el Area3D detecte objetos en la Capa 2 (Player)
	collision_mask = 2
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not is_inside_tree() or not is_instance_valid(body) or body.is_queued_for_deletion():
		return

	if body.is_in_group("player"):
		CameraDirector.register_zone_enter(self)


func _on_body_exited(body: Node3D) -> void:
	if not is_inside_tree() or not is_instance_valid(body) or body.is_queued_for_deletion():
		return

	if body.is_in_group("player"):
		CameraDirector.register_zone_exit(self)
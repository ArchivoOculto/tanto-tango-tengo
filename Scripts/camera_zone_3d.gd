extends Area3D
class_name CameraZone3D

@export var camera_anchor: Node3D
@export var follow_smoothing: float = 2.0


func _ready() -> void:
	# Asegura que el Area3D detecte objetos en la Capa 2 (Player)
	collision_mask = 2
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		CameraDirector.register_zone_enter(self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		CameraDirector.register_zone_exit(self)
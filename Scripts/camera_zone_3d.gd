extends Area3D
class_name CameraZone3D

## Volumen que define un "plano de camara" al estilo God of War clasico:
## al entrar el jugador, la GameCamera se mueve hacia camera_anchor y lo
## empieza a encuadrar desde ahi. Encadena varias de estas a lo largo de
## un pasillo para simular una camara que "viaja" con el jugador, o pone
## una sola grande y alta en un salon para el efecto de vista aerea.
##
## Requiere un CollisionShape3D hijo (el volumen del trigger) y que su
## collision_mask incluya la capa del Player.

@export var camera_anchor: Node3D
@export var follow_smoothing: float = 2.0  ## mas alto = la camara llega mas rapido al anchor


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		CameraDirector.register_zone_enter(self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		CameraDirector.register_zone_exit(self)

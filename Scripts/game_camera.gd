extends Camera3D
class_name GameCamera

## La camara real de juego. NO la mueve el jugador: se reubica sola segun
## que CameraZone3D este activa (via CameraDirector), y mientras tanto
## sigue encuadrando al jugador desde donde este parada. Va suelta en la
## escena, no colgada del Player.

@export var look_ahead: float = 1.5     ## cuanto "adelanta" la mira sobre el jugador al correr
@export var look_height: float = 1.0    ## altura del punto de mira sobre los pies del jugador

@onready var player: Node3D = get_tree().get_first_node_in_group("player")


func _ready() -> void:
	current = true


func _process(delta: float) -> void:
	if player == null:
		return

	var zone: CameraZone3D = CameraDirector.current_zone
	if zone and zone.camera_anchor:
		global_position = global_position.lerp(zone.camera_anchor.global_position, zone.follow_smoothing * delta)

	var horizontal_velocity: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var look_target: Vector3 = player.global_position + Vector3.UP * look_height

	if horizontal_velocity.length() > 0.1:
		look_target += horizontal_velocity.normalized() * min(horizontal_velocity.length() * 0.15, look_ahead)

	if global_position.distance_to(look_target) > 0.01:
		look_at(look_target, Vector3.UP)

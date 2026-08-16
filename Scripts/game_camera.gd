extends Camera3D
class_name GameCamera

## La camara real de juego. No la mueve el jugador: se reubica sola segun
## que CameraZone3D este activa (via CameraDirector), y mientras tanto
## sigue encuadrando al jugador desde donde este parada.
##
## Las distancias NO son numeros fijos: se calculan como proporcion de la
## altura real del personaje (player.get_body_height()), asi que si
## cambias el tamaño del Player esto se reajusta solo, sin tocar nada aca.

@export var look_ahead: float = 0.35

@export_group("Proporciones (fraccion de la altura del personaje)")
@export var look_height_ratio: float = 0.55     ## donde apunta la mira: 0.55 = mas o menos el pecho
@export var min_distance_ratio: float = 1.0     ## nunca mas cerca que 1x la altura del personaje
@export var collision_margin_ratio: float = 0.2 ## margen al esquivar paredes, como fraccion de la altura

@export_group("Colision de camara")
@export var collision_mask: int = 1  ## capas que bloquean la camara (terreno, paredes, props)

@onready var player: Node3D = get_tree().get_first_node_in_group("player")

var _player_height: float = 1.8


func _ready() -> void:
	current = true
	if player and player.has_method("get_body_height"):
		_player_height = player.get_body_height()


func _process(delta: float) -> void:
	if player == null:
		return

	var look_height: float = _player_height * look_height_ratio
	var min_distance: float = _player_height * min_distance_ratio
	var collision_margin: float = _player_height * collision_margin_ratio

	var zone: CameraZone3D = CameraDirector.current_zone
	var desired_position: Vector3 = global_position
	if zone and zone.camera_anchor:
		desired_position = global_position.lerp(zone.camera_anchor.global_position, zone.follow_smoothing * delta)

	var horizontal_velocity: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var look_target: Vector3 = player.global_position + Vector3.UP * look_height
	if horizontal_velocity.length() > 0.1:
		look_target += horizontal_velocity.normalized() * min(horizontal_velocity.length() * 0.15, look_ahead)

	desired_position = _avoid_scenery(look_target, desired_position, collision_margin)
	desired_position = _enforce_min_distance(look_target, desired_position, min_distance)

	global_position = desired_position

	if global_position.distance_to(look_target) > 0.01:
		look_at(look_target, Vector3.UP)


func _avoid_scenery(from: Vector3, to: Vector3, margin: float) -> Vector3:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = collision_mask
	if player is CollisionObject3D:
		query.exclude = [player.get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return to

	var direction: Vector3 = (from - to).normalized()
	return result.position + direction * margin


func _enforce_min_distance(from: Vector3, to: Vector3, min_dist: float) -> Vector3:
	if from.distance_to(to) < min_dist:
		var direction: Vector3 = to - from
		direction = direction.normalized() if direction.length() > 0.01 else Vector3.BACK
		return from + direction * min_dist
	return to
extends Camera3D
class_name GameCamera

## Cámara del juego. Modos:
## 1. Tercera Persona: Sigue suavemente la espalda del personaje.
## 2. Cámara Fija: Se desplaza hacia el anchor de la CameraZone3D activa.

@export var look_ahead: float = 0.35

@export_group("Modo 3ra Persona")
@export var default_distance: float = 0.33      ## Distancia detrás del jugador
@export var default_height: float = 0.25        ## Altura sobre el suelo
@export var default_smoothing: float = 1.0       ## Velocidad de suavizado en 3ra persona

@export_group("Proporciones (fracción de la altura del personaje)")
@export var look_height_ratio: float = 0.55     ## Punto al que apunta la mira (pecho/cabeza)
@export var min_distance_ratio: float = 0.1     ## Distancia mínima reducida para evitar tirones
@export var collision_margin_ratio: float = 0.05 ## Margen de colisión fino

@export_group("Colisión de cámara")
@export var collision_mask: int = 1  ## Capas del terreno/paredes

@onready var player: Node3D = get_tree().get_first_node_in_group("player")

var _player_height: float = 1.8
var _current_look_target: Vector3 = Vector3.ZERO


func _ready() -> void:
	current = true
	if player and player.has_method("get_body_height"):
		_player_height = player.get_body_height()
	if player:
		_current_look_target = player.global_position + Vector3.UP * (_player_height * look_height_ratio)


func _process(delta: float) -> void:
	if player == null:
		return

	var look_height: float = _player_height * look_height_ratio
	var min_distance: float = _player_height * min_distance_ratio
	var collision_margin: float = _player_height * collision_margin_ratio

	# 1. Calcular el punto hacia donde debe mirar la cámara
	var target_look: Vector3 = player.global_position + Vector3.UP * look_height
	
	var horizontal_velocity: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if horizontal_velocity.length() > 0.1:
		target_look += horizontal_velocity.normalized() * min(horizontal_velocity.length() * 0.15, look_ahead)

	# Suavizamos el punto de mira para evitar tirones de rotación bruscos
	_current_look_target = _current_look_target.lerp(target_look, 10.0 * delta)

	var zone: CameraZone3D = CameraDirector.current_zone
	var target_position: Vector3

	if zone and zone.camera_anchor:
		# MODO 1: Cámara fija guiada por la zona actual
		target_position = zone.camera_anchor.global_position
		global_position = global_position.lerp(target_position, zone.follow_smoothing * delta)
	else:
		# MODO 2: 3ra Persona basada en la orientación del Visuals (evita loops vectoriales)
		var visuals_node: Node3D = player.get_node_or_null("Visuals")
		var facing_basis: Basis = visuals_node.global_transform.basis if visuals_node else player.global_transform.basis
		
		# Calculamos la posición deseada detrás del modelo visual actual
		var player_back: Vector3 = facing_basis.z.normalized()
		target_position = player.global_position + Vector3.UP * default_height + player_back * default_distance
		
		global_position = global_position.lerp(target_position, default_smoothing * delta)

	# 2. Resguardo de geometrías
	var desired_position: Vector3 = _avoid_scenery(_current_look_target, global_position, collision_margin)
	desired_position = _enforce_min_distance(_current_look_target, desired_position, min_distance)

	global_position = desired_position

	# 3. Orientar la cámara asegurando que no haya distancia cero
	if global_position.distance_to(_current_look_target) > 0.01:
		look_at(_current_look_target, Vector3.UP)


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
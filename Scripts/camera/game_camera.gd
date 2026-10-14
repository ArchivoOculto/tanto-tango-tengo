extends Camera3D
class_name GameCamera

## Cámara del juego (Cámaras Fijas).
## Se desplaza hacia el anchor de la CameraZone3D activa. 
## Al salir de todas las zonas, retiene la posición del último anchor conocido.

@export var look_ahead: float = 0.35
@export var default_smoothing: float = 3.0 ## Suavizado al transicionar si no hay zona activa

@export_group("Proporciones (fracción de la altura del personaje)")
@export var look_height_ratio: float = 0.55
@export var min_distance_ratio: float = 0.1
@export var collision_margin_ratio: float = 0.05

@export_group("Colisión de cámara")
@export var collision_mask: int = 1

@onready var player: Node3D = get_tree().get_first_node_in_group("player")

var _player_height: float = 1.8
var _current_look_target: Vector3 = Vector3.ZERO
var _last_known_anchor_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	current = true
	add_to_group("game_camera") # permite que WarpManager la encuentre para hacer snap_to_zone()

	if player and player.has_method("get_body_height"):
		_player_height = player.get_body_height()
	
	if player:
		_current_look_target = player.global_position + Vector3.UP * (_player_height * look_height_ratio)
		# Inicializamos la posición en el lugar de origen de la cámara
		_last_known_anchor_pos = global_position


func _process(delta: float) -> void:
	if player == null:
		return

	var min_distance: float = _player_height * min_distance_ratio
	var collision_margin: float = _player_height * collision_margin_ratio

	# --- 1. LÓGICA DE MIRA (A dónde apunta la cámara) ---
	var zone: CameraZone3D = CameraDirector.current_zone
	var target_look: Vector3

	if zone and is_instance_valid(zone.look_target):
		target_look = zone.look_target.global_position
	else:
		var look_height: float = _player_height * look_height_ratio
		target_look = player.global_position + Vector3.UP * look_height
		
		var horizontal_velocity: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
		if horizontal_velocity.length() > 0.1:
			target_look += horizontal_velocity.normalized() * min(horizontal_velocity.length() * 0.15, look_ahead)

	_current_look_target = _current_look_target.lerp(target_look, 10.0 * delta)

	# --- 2. LÓGICA DE POSICIÓN (Dónde se ubica la cámara) ---
	var target_position: Vector3
	var current_smoothing: float = default_smoothing

	if zone and is_instance_valid(zone.camera_anchor):
		# Hay una zona activa: vamos hacia su anchor y guardamos la posición
		target_position = zone.camera_anchor.global_position
		current_smoothing = zone.follow_smoothing
		_last_known_anchor_pos = target_position
	else:
		# No hay zona activa: nos quedamos en el último anchor válido
		target_position = _last_known_anchor_pos

	global_position = global_position.lerp(target_position, current_smoothing * delta)

	# --- 3. LÓGICA DE COLISIONES ---
	var desired_position: Vector3 = _avoid_scenery(_current_look_target, global_position, collision_margin)
	desired_position = _enforce_min_distance(_current_look_target, desired_position, min_distance)

	global_position = desired_position

	# --- 4. ORIENTACIÓN ---
	if global_position.distance_to(_current_look_target) > 0.01:
		look_at(_current_look_target, Vector3.UP)


## Coloca la cámara de forma INSTANTÁNEA en el anchor de 'zone', sin el
## smoothing normal de seguimiento, y actualiza el punto de mira acorde a la
## posición actual del jugador. Pensado para usarse justo después de un warp,
## mientras la pantalla sigue en negro, para que el fade-in revele la cámara
## ya asentada en su lugar final (sin que se la vea deslizar hasta ahí).
func snap_to_zone(zone: CameraZone3D) -> void:
	if zone == null or not is_instance_valid(zone.camera_anchor):
		return

	var target_position: Vector3 = zone.camera_anchor.global_position
	_last_known_anchor_pos = target_position
	global_position = target_position

	if player:
		var look_height: float = _player_height * look_height_ratio
		_current_look_target = player.global_position + Vector3.UP * look_height

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
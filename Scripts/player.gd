extends CharacterBody3D
class_name Player

## Movimiento relativo a la camara ACTIVA en cada momento (GameCamera),
## que en este juego no la controla el jugador: la mueve el CameraDirector
## segun la CameraZone3D en la que este. El personaje siempre rota hacia
## donde camina, nunca hacia donde "mira" la camara (porque nada define
## eso desde el input).

@export_group("Movimiento")
@export var move_speed: float = 2.5
@export var acceleration: float = 3.0
@export var friction: float = 7.0
@export var rotation_speed: float = 6.0

@export_group("Salto y gravedad")
@export var jump_velocity: float = 2.5
@export var gravity_multiplier: float = 1.0

@onready var visuals: Node3D = $Visuals

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_movement(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta


func _handle_jump() -> void:
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity


func _handle_movement(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Direccion relativa a la camara activa en este instante segun el
	# CameraDirector (no a un rig fijo colgado del jugador).
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cam_basis: Basis = cam.global_transform.basis if cam else global_transform.basis
	var forward: Vector3 = -cam_basis.z
	var right: Vector3 = cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var move_dir: Vector3 = forward * -input_dir.y + right * input_dir.x

	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
		var target_velocity: Vector3 = move_dir * move_speed
		velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
		_rotate_visuals_towards(move_dir, delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, friction * delta)
		velocity.z = lerp(velocity.z, 0.0, friction * delta)


func _rotate_visuals_towards(direction: Vector3, delta: float) -> void:
	var target_angle: float = atan2(direction.x, direction.z)
	visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)

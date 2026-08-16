extends CharacterBody3D
class_name Player

## Movimiento relativo a la camara ACTIVA en cada momento (GameCamera),
## que en este juego no la controla el jugador: la mueve el CameraDirector
## segun la CameraZone3D en la que este. El personaje siempre rota hacia
## donde camina, nunca hacia donde "mira" la camara (porque nada define
## eso desde el input).

@export_group("Movimiento")
@export var move_speed: float = 2.0
@export var acceleration: float = 3.0
@export var friction: float = 10.0
@export var rotation_speed: float = 3.0

@export_group("Salto y gravedad")
@export var jump_velocity: float = 2.5
@export var gravity_multiplier: float = 1.0

@onready var visuals: Node3D = $Visuals

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _enter_tree() -> void:
	# _enter_tree corre de arriba hacia abajo apenas el nodo entra al arbol,
	# ANTES de que empiece la pasada de _ready() de toda la escena. Por eso
	# va aca y no en _ready(): asi GameCamera (u otro script que busque
	# el grupo "player" en su propio _ready) siempre lo encuentra, sin
	# importar el orden de los nodos hermanos en la escena.
	add_to_group("player")


## Altura del personaje leida directamente de su CapsuleShape3D. Busca el
## nodo en el momento (no cachea con @onready) para poder llamarse desde
## el _ready() de OTRO nodo (como la camara) sin importar el orden en que
## arrancan los scripts — el CollisionShape3D y su Shape3D ya existen con
## sus valores del .tscn apenas el nodo entra al arbol, aunque su propio
## _ready() todavia no haya corrido.
func get_body_height() -> float:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if col and col.shape is CapsuleShape3D:
		return col.shape.height
	return 1.8  # fallback razonable si el shape no esta listo o no es capsula


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

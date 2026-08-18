extends CharacterBody3D
class_name Enemy

@export_group("Stats")
@export var max_health: float = 100.0
@export var move_speed: float = 1.5

@export_group("Wander AI")
@export var wander_radius: float = 4.0      ## Radio máximo alrededor del spawn para caminar
@export var min_wait_time: float = 2.0      ## Tiempo mínimo esperando en un sitio
@export var max_wait_time: float = 5.0      ## Tiempo máximo esperando en un sitio

@export_group("Knockback & Gravity")
@export var friction: float = 8.0           ## Fricción para frenar el empujón horizontal
@export var gravity_multiplier: float = 1.0

var current_health: float
var spawn_position: Vector3
var target_position: Vector3
var is_wandering: bool = false
var wait_timer: float = 0.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var mesh: MeshInstance3D = $MeshInstance3D
var mesh_material: StandardMaterial3D


func _ready() -> void:
	current_health = max_health
	spawn_position = global_position
	target_position = spawn_position

	# Preparamos un material único para que este enemigo no comparta el color con otras instancias
	if mesh:
		var base_mat: Material = mesh.get_surface_override_material(0)
		if not base_mat:
			base_mat = mesh.mesh.surface_get_material(0) if mesh.mesh else null

		if base_mat:
			mesh_material = base_mat.duplicate() as StandardMaterial3D
		else:
			mesh_material = StandardMaterial3D.new()
			mesh_material.albedo_color = Color.GREEN

		mesh.set_surface_override_material(0, mesh_material)

	_pick_new_wander_target()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_wander(delta)
	_apply_friction(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta


func _apply_friction(delta: float) -> void:
	# Frena paulatinamente el impulso horizontal (Knockback) cuando no se está desplazando intencionadamente
	if not is_wandering:
		velocity.x = lerp(velocity.x, 0.0, friction * delta)
		velocity.z = lerp(velocity.z, 0.0, friction * delta)


func _handle_wander(delta: float) -> void:
	if is_wandering:
		var dir: Vector3 = (target_position - global_position)
		dir.y = 0.0

		if dir.length() < 0.2:
			# Llegó al destino
			is_wandering = false
			velocity.x = 0.0
			velocity.z = 0.0
			wait_timer = randf_range(min_wait_time, max_wait_time)
		else:
			dir = dir.normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
			_rotate_towards(dir, delta)
	else:
		wait_timer -= delta
		if wait_timer <= 0.0:
			_pick_new_wander_target()


func _pick_new_wander_target() -> void:
	var random_offset: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.5, wander_radius)
	target_position = spawn_position + Vector3(random_offset.x, 0.0, random_offset.y)
	is_wandering = true


func _rotate_towards(direction: Vector3, delta: float) -> void:
	if direction.length() > 0.01:
		var target_angle: float = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 5.0 * delta)


func take_damage(amount: float, knockback_force: Vector3 = Vector3.ZERO) -> void:
	current_health -= amount

	# Aplicar Knockback si viene con fuerza
	if knockback_force != Vector3.ZERO:
		velocity += knockback_force

	_flash_red()

	if current_health <= 0:
		die()


func _flash_red() -> void:
	if mesh_material:
		mesh_material.albedo_color = Color.RED
		get_tree().create_timer(0.12).timeout.connect(func():
			if is_instance_valid(mesh_material):
				mesh_material.albedo_color = Color.GREEN
		)


func die() -> void:
	queue_free()
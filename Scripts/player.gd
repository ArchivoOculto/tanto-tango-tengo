extends CharacterBody3D
class_name Player

## Movimiento del personaje y coordinación de controladores.

@export_group("Movimiento")
@export var move_speed: float = 2.0
@export var acceleration: float = 3.0
@export var friction: float = 10.0
@export var rotation_speed: float = 3.0
@export var push_force: float = 1.5 ## Fuerza aplicada a objetos RigidBody3D al empujarlos

@export_group("Stats & Daño")
@export var max_health: float = 100.0
@export var flash_duration: float = 0.15 ## Duración del destello rojo
@export var invulnerability_duration: float = 0.8 ## Tiempo de invulnerabilidad tras ser golpeado

@export_group("Velocidad de Acciones")
@export var attack_move_speed_multiplier: float = 0.3

@export_group("Salto y Gravedad")
@export var jump_velocity: float = 2.5
@export var gravity_multiplier: float = 1.0
@export var max_jumps: int = 2

@onready var visuals: Node3D = $Visuals
@onready var combat_controller: CombatController = $CombatController
@onready var anim_controller: PlayerAnimationController = $AnimationController

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var jump_count: int = 0
var current_health: float
var is_invulnerable: bool = false

# Materiales para el efecto rojo
var player_materials: Array[StandardMaterial3D] = []
var original_albedo_colors: Array[Color] = []


func _enter_tree() -> void:
	add_to_group("player")


func _ready() -> void:
	current_health = max_health
	_setup_materials()


func get_body_height() -> float:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if col and col.shape is CapsuleShape3D:
		return col.shape.height
	return 1.8


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_movement(delta)
	move_and_slide()
	_handle_rigid_push()

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if anim_controller:
		anim_controller.update_locomotion(is_on_floor(), horizontal_speed)


func take_damage(amount: float, knockback_impulse: Vector3 = Vector3.ZERO) -> void:
	if is_invulnerable:
		return

	current_health -= amount

	# Aplicar empuje
	if knockback_impulse != Vector3.ZERO:
		velocity = knockback_impulse

	# Cancelar acciones en curso
	if combat_controller:
		combat_controller.interrupt_actions()

	_flash_red()
	_start_invulnerability()


# --- EFECTO DE DESTELLO ROJO ---
func _flash_red() -> void:
	for i in range(player_materials.size()):
		var mat = player_materials[i]
		if is_instance_valid(mat):
			var orig_col = original_albedo_colors[i]
			mat.albedo_color = Color(1.0, 0.1, 0.1, orig_col.a)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.0, 0.0)

	get_tree().create_timer(flash_duration).timeout.connect(func():
		for i in range(player_materials.size()):
			var mat = player_materials[i]
			if is_instance_valid(mat):
				mat.albedo_color = original_albedo_colors[i]
				mat.emission_enabled = false
	)


func _start_invulnerability() -> void:
	is_invulnerable = true
	
	# Efecto de parpadeo de visibilidad durante la invulnerabilidad
	var tween = create_tween()
	var loops = int(invulnerability_duration / 0.1)
	for i in range(loops):
		tween.tween_property(visuals, "visible", false, 0.05)
		tween.tween_property(visuals, "visible", true, 0.05)
		
	tween.finished.connect(func():
		if is_instance_valid(visuals):
			visuals.visible = true
		is_invulnerable = false
	)


# --- BUSQUEDA Y CONFIGURACIÓN AUTOMÁTICA DE MATERIALES ---
func _setup_materials() -> void:
	player_materials.clear()
	original_albedo_colors.clear()
	
	# Busca todos los MeshInstance3D dentro del modelo visual
	var mesh_nodes = visuals.find_children("*", "MeshInstance3D", true, false)
	
	for mesh_node in mesh_nodes:
		if mesh_node is MeshInstance3D:
			for surface_idx in range(mesh_node.get_surface_override_material_count()):
				var base_mat = mesh_node.get_surface_override_material(surface_idx)
				
				if not base_mat and mesh_node.mesh and mesh_node.mesh.get_surface_count() > surface_idx:
					base_mat = mesh_node.mesh.surface_get_material(surface_idx)
				
				if base_mat is StandardMaterial3D:
					var dup_mat = base_mat.duplicate() as StandardMaterial3D
					mesh_node.set_surface_override_material(surface_idx, dup_mat)
					player_materials.append(dup_mat)
					original_albedo_colors.append(dup_mat.albedo_color)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta
	else:
		jump_count = 0


func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump"):
		if is_on_floor() or jump_count < max_jumps:
			velocity.y = jump_velocity
			jump_count += 1
			
			if combat_controller:
				combat_controller.interrupt_actions()
			
			if anim_controller:
				anim_controller.play_jump()


func _handle_movement(delta: float) -> void:
	var current_speed_mult: float = 1.0
	if combat_controller and combat_controller.is_attacking():
		current_speed_mult = attack_move_speed_multiplier

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

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
		var target_velocity: Vector3 = move_dir * (move_speed * current_speed_mult)
		velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
		_rotate_visuals_towards(move_dir, delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, friction * delta)
		velocity.z = lerp(velocity.z, 0.0, friction * delta)


func _rotate_visuals_towards(direction: Vector3, delta: float) -> void:
	if visuals:
		var target_angle: float = atan2(direction.x, direction.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)


func _handle_rigid_push() -> void:
	for i in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = collision.get_collider()

		if collider is RigidBody3D:
			if collider.freeze:
				continue

			var push_dir: Vector3 = -collision.get_normal()
			push_dir.y = 0.0

			var impulse: Vector3 = push_dir * push_force
			collider.apply_impulse(impulse, collision.get_position() - collider.global_position)
extends CharacterBody3D
class_name Enemy

@export_group("Stats")
@export var max_health: float = 100.0
@export var move_speed: float = 1.5
@export var retreat_speed: float = 4.0        ## Velocidad a la que se aleja del jugador al ser golpeado

@export_group("Wander AI")
@export var wander_radius: float = 10.0      ## Radio máximo alrededor del spawn para caminar
@export var min_wait_time: float = 1.0       ## Tiempo mínimo esperando en un sitio
@export var max_wait_time: float = 3.0       ## Tiempo máximo esperando en un sitio

@export_group("Knockback & Duraciones")
@export var friction: float = 8.0            ## Fricción para frenar el empujón horizontal
@export var gravity_multiplier: float = 1.0
@export var retreat_duration: float = 0.8    ## Tiempo en segundos que se aleja tras recibir daño
@export var flash_duration: float = 0.15     ## Duración del destello rojo

# Nombres de las animaciones
const ANIM_IDLE = "1A_BTA_8"
const ANIM_WALK = "1ASPO1_1"
const ANIM_ATTACK = "1ASP00_1"
const ANIM_HURT = "1A_BTA_12"

var current_health: float
var spawn_position: Vector3
var target_position: Vector3
var is_wandering: bool = false
var wait_timer: float = 0.0

var is_retreating: bool = false
var retreat_timer: float = 0.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Nodos de referencia basados en enemy.tscn y enemy_visual.tscn
@onready var visuals: Node3D = $Visuals
@onready var animation_player: AnimationPlayer = $Visuals/AnimationPlayer
@onready var mesh_instance: MeshInstance3D = $Visuals/Mesh/Skeleton3D/Mesh

var enemy_material: StandardMaterial3D
var original_albedo_color: Color = Color.WHITE


func _ready() -> void:
	current_health = max_health
	spawn_position = global_position
	target_position = spawn_position

	_setup_material()
	_play_anim(ANIM_IDLE)
	_pick_new_wander_target()


func _setup_material() -> void:
	if mesh_instance:
		# Intentar obtener el material desde el override o desde el mesh base
		var base_mat: Material = mesh_instance.get_surface_override_material(0)
		if not base_mat and mesh_instance.mesh and mesh_instance.mesh.get_surface_count() > 0:
			base_mat = mesh_instance.mesh.surface_get_material(0)

		if base_mat is StandardMaterial3D:
			enemy_material = base_mat.duplicate() as StandardMaterial3D
		else:
			# Si no era StandardMaterial3D o venía vacío, creamos uno compatible
			enemy_material = StandardMaterial3D.new()
			if base_mat and base_mat.has_method("get_texture"):
				enemy_material.albedo_texture = base_mat.get_texture(StandardMaterial3D.TEXTURE_ALBEDO)

		# Asignamos el material duplicado como override único
		mesh_instance.set_surface_override_material(0, enemy_material)
		enemy_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		original_albedo_color = enemy_material.albedo_color


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)

	if is_retreating:
		_handle_retreat(delta)
	else:
		_handle_wander(delta)

	_apply_friction(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta


func _apply_friction(delta: float) -> void:
	# Frena la velocidad de impulso/knockback progresivamente
	if not is_wandering:
		velocity.x = lerp(velocity.x, 0.0, friction * delta)
		velocity.z = lerp(velocity.z, 0.0, friction * delta)


func _handle_wander(delta: float) -> void:
	if is_wandering:
		var dir: Vector3 = (target_position - global_position)
		dir.y = 0.0

		if dir.length() < 0.3:
			is_wandering = false
			velocity.x = 0.0
			velocity.z = 0.0
			_play_anim(ANIM_IDLE)
			wait_timer = randf_range(min_wait_time, max_wait_time)
		else:
			dir = dir.normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
			_rotate_visuals(dir, delta)
			_play_anim(ANIM_WALK)
	else:
		wait_timer -= delta
		if wait_timer <= 0.0:
			_pick_new_wander_target()


func _pick_new_wander_target() -> void:
	var random_offset: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(1.0, wander_radius)
	target_position = spawn_position + Vector3(random_offset.x, 0.0, random_offset.y)
	is_wandering = true


func _handle_retreat(delta: float) -> void:
	retreat_timer -= delta

	if retreat_timer <= 0.0:
		is_retreating = false
		_play_anim(ANIM_IDLE)


## Firma compatible exactamente con WeaponHitbox: take_damage(damage, final_knockback)
func take_damage(amount: float, knockback_force: Vector3 = Vector3.ZERO) -> void:
	current_health -= amount

	# Se aplica la fuerza calculada por el WeaponHitbox
	if knockback_force != Vector3.ZERO:
		velocity = knockback_force

	# Reproducir animación de daño y destello
	_play_anim(ANIM_HURT)
	_flash_red()

	if current_health <= 0:
		die()
	else:
		_start_retreat()


func _start_retreat() -> void:
	is_wandering = false
	is_retreating = true
	retreat_timer = retreat_duration


func _flash_red() -> void:
	if enemy_material:
		# Cambiamos albedo a rojo y activamos emisión para asegurar que se note el destello
		var red_with_alpha := Color(1.0, 0.1, 0.1, original_albedo_color.a)
		enemy_material.albedo_color = red_with_alpha
		enemy_material.emission_enabled = true
		enemy_material.emission = Color(1.0, 0.0, 0.0)

		get_tree().create_timer(flash_duration).timeout.connect(func():
			if is_instance_valid(enemy_material):
				enemy_material.albedo_color = original_albedo_color
				enemy_material.emission_enabled = false
		)


func _rotate_visuals(direction: Vector3, delta: float) -> void:
	if visuals and direction.length() > 0.01:
		var target_angle: float = atan2(direction.x, direction.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 6.0 * delta)


func _play_anim(anim_name: String) -> void:
	if animation_player and animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name)


func die() -> void:
	queue_free()
class_name Enemy
extends CharacterBody3D

# --- ESTADOS ---
enum State { WANDER, CHASE, ATTACK, FLEE, COOLDOWN, DEAD, ATTACK_OBJECT }

## ATTACK_OBJECT: cuando suena la música correcta (ver Level00Manager) los enemigos dejan de patrullar y van
## a golpear un objeto (la radio) para hacer saltar el cassette. Se activa con command_attack_object() y se
## apaga con release_object_target(). Mientras tanto ignoran al jugador (ver ignore_player_in_attack_object).

@export_group("IA & Detección")
@export var detection_radius: float = 1.0     ## Distancia dentro del territorio para empezar a perseguir
@export var attack_range: float = 0.5         ## Distancia para activar el ataque
@export var attack_cooldown: float = 2.0      ## Tiempo de espera entre ataques

@export_group("Atacar objeto (radio)")
@export var object_attack_range: float = 0.7  ## Distancia al objeto para empezar a golpearlo
@export var object_attack_cooldown: float = 1.5  ## Pausa entre golpes al objeto
## OBJETO que ataca este enemigo en ATTACK_OBJECT. Vacío = el que indica el nivel (Level00Manager.enemy_attack_target,
## por defecto la radio). Si se asigna acá, tiene prioridad sobre el del nivel.
@export var attack_object_target: Node3D
## En ATTACK_OBJECT el objetivo PRINCIPAL es el objeto: se ignora al jugador por completo (no lo persiguen
## ni lo atacan). Desactivar para que lo defiendan cuando el jugador se les acerca.
@export var ignore_player_in_attack_object: bool = true

@export_group("Stats & Velocidades")
@export var max_health: float = 100.0
@export var base_speed: float = 1.5           ## Velocidad base de movimiento
@export var attack_damage: float = 10.0       ## Daño que inflige al jugador
@export var knockback_force: float = 4.0      ## Fuerza con la que empuja al jugador

@export_subgroup("Multiplicadores de Velocidad")
@export var chase_speed_mult: float = 2.33    ## Multiplica base_speed para perseguir
@export var flee_speed_mult: float = 2.66     ## Multiplica base_speed para huir
@export var retreat_speed_mult: float = 2.66  ## Multiplica base_speed para retroceder tras daño

@export_group("Wander AI")
@export var wander_radius: float = 10.0
@export var min_wait_time: float = 1.0
@export var max_wait_time: float = 3.0

@export_group("Knockback & Duraciones")
@export var friction: float = 8.0
@export var gravity_multiplier: float = 1.0
@export var retreat_duration: float = 0.8
@export var flash_duration: float = 0.15

# --- CONSTANTES DE ANIMACIÓN ---
const ANIM_IDLE = "1A_BTA_8"
const ANIM_WALK = "1ASPO1_1"
const ANIM_ATTACK = "1ASP00_1"
const ANIM_HURT = "1A_BTA_12"

# --- PROPIEDADES CALCULADAS DE VELOCIDAD ---
var chase_speed: float:
	get: return base_speed * chase_speed_mult

var flee_speed: float:
	get: return base_speed * flee_speed_mult

var retreat_speed: float:
	get: return base_speed * retreat_speed_mult

# --- REFERENCIAS INTERNAS Y NODOS ---
@onready var visuals: Node3D = $Visuals
@onready var animation_player: AnimationPlayer = $Visuals/AnimationPlayer
@onready var mesh_instance: MeshInstance3D = $Visuals/Mesh/Skeleton3D/Mesh
@onready var attack_area: Area3D = $AttackArea
@onready var attack_mesh: MeshInstance3D = $AttackArea/MeshInstance3D

# --- VARIABLES DE ESTADO ---
var current_state: State = State.WANDER
var current_health: float
var spawn_position: Vector3
var target_position: Vector3
var is_wandering: bool = false
var wait_timer: float = 0.0

var cooldown_timer: float = 0.0
var flee_timer: float = 0.0

var is_retreating: bool = false
var retreat_timer: float = 0.0

var zone_area: Area3D = null
var current_target_player: Node3D = null

var object_target: Node3D = null ## Objeto a atacar (null = comportamiento normal)
var _striking_object: bool = false
var _nav_path: PackedVector3Array = PackedVector3Array()
var _nav_path_index: int = 0
var _nav_refresh_timer: float = 0.0
var _object_attack_timer: float = 0.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var enemy_material: StandardMaterial3D
var original_albedo_color: Color = Color.WHITE

# Material, Tween y Escala Base para la esfera de ataque
var attack_mesh_material: StandardMaterial3D
var attack_tween: Tween
var original_attack_mesh_scale: Vector3 = Vector3.ONE
@export var base_attack_color: Color = Color(1.0, 0.0, 0.0, 1.0) ## Color RGB puro del ataque
@export var initial_scale_ratio: float = 0.1 ## Tamaño inicial (10% del tamaño total)


func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health
	spawn_position = global_position
	target_position = spawn_position

	_setup_attack_mesh_material()
	_setup_material()
	_play_anim(ANIM_IDLE)
	_pick_new_wander_target()

	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	_apply_gravity(delta)

	if is_retreating:
		_handle_retreat(delta)
	else:
		_process_state_machine(delta)

	_apply_friction(delta)
	move_and_slide()


# --- MÁQUINA DE ESTADOS E INTELIGENCIA TERRITORIAL ---
func _process_state_machine(delta: float) -> void:
	var is_player_in_territory: bool = zone_area != null and zone_area.get("is_player_inside") == true
	var player_ref: Node3D = zone_area.get("player_ref") if is_player_in_territory else null

	var dist_to_player: float = global_position.distance_to(player_ref.global_position) if player_ref else INF

	match current_state:
		State.WANDER:
			_handle_wander(delta)
			if is_player_in_territory and dist_to_player <= detection_radius and cooldown_timer <= 0.0:
				current_state = State.CHASE

		State.CHASE:
			if not is_player_in_territory or dist_to_player > detection_radius * 1.5:
				current_state = State.WANDER
				return

			var dir = (player_ref.global_position - global_position)
			dir.y = 0.0
			var move_dir = dir.normalized()
			
			velocity.x = move_dir.x * chase_speed
			velocity.z = move_dir.z * chase_speed
			_rotate_visuals(move_dir, delta)
			_play_anim(ANIM_WALK)

			if dist_to_player <= attack_range:
				_start_attack(player_ref)

		State.ATTACK:
			velocity.x = 0.0
			velocity.z = 0.0

		State.ATTACK_OBJECT:
			_process_attack_object(delta, player_ref, dist_to_player)

		State.FLEE:
			flee_timer -= delta
			if player_ref:
				var flee_dir = (global_position - player_ref.global_position)
				flee_dir.y = 0.0
				flee_dir = flee_dir.normalized()

				velocity.x = flee_dir.x * flee_speed
				velocity.z = flee_dir.z * flee_speed
				_rotate_visuals(flee_dir, delta)
				_play_anim(ANIM_WALK)
			else:
				_play_anim(ANIM_IDLE)

			if flee_timer <= 0.0 or not is_player_in_territory:
				current_state = State.COOLDOWN
				cooldown_timer = attack_cooldown

		State.COOLDOWN:
			cooldown_timer -= delta
			_handle_wander(delta)
			
			if cooldown_timer <= 0.0:
				if is_instance_valid(object_target):
					current_state = State.ATTACK_OBJECT # la música correcta sigue sonando: de vuelta a la radio
				elif is_player_in_territory and dist_to_player <= detection_radius:
					current_state = State.CHASE
				else:
					current_state = State.WANDER


func _start_attack(player_ref: Node3D) -> void:
	current_state = State.ATTACK
	current_target_player = player_ref
	
	if is_instance_valid(player_ref):
		var attack_dir = (player_ref.global_position - global_position)
		attack_dir.y = 0.0
		_rotate_visuals(attack_dir.normalized(), 1.0)

	_begin_attack_telegraph()


## Animación de ataque + esfera roja que crece (la misma para golpear al jugador o a un objeto).
func _begin_attack_telegraph() -> void:
	_play_anim(ANIM_ATTACK)

	# --- ANIMACIÓN DE INTENSIDAD, ALPHA Y ESCALA ---
	if attack_mesh_material and animation_player and animation_player.has_animation(ANIM_ATTACK):
		var anim_length = animation_player.get_animation(ANIM_ATTACK).length
		
		if attack_tween and attack_tween.is_valid():
			attack_tween.kill()

		# 1. Estado inicial: Intensidad y Alpha en 0, y Escala reducida
		_update_attack_intensity_and_alpha(0.0, 0.0)
		if is_instance_valid(attack_mesh):
			attack_mesh.scale = original_attack_mesh_scale * initial_scale_ratio
			attack_mesh.visible = true

		# 2. Creamos el Tween en paralelo para animar Color y Escala a la vez
		attack_tween = create_tween().set_parallel(true)
		
		# Anima Intensidad y Alpha mediante método
		attack_tween.tween_method(
			func(progress: float):
				_update_attack_intensity_and_alpha(progress, progress),
			0.0,
			1.0,
			anim_length
		)
		
		# Anima la Escala directamente desde el valor inicial hasta el original
		if is_instance_valid(attack_mesh):
			attack_tween.tween_property(
				attack_mesh,
				"scale",
				original_attack_mesh_scale,
				anim_length
			)

func _update_attack_intensity_and_alpha(intensity: float, alpha: float) -> void:
	if attack_mesh_material:
		# Multiplica el color base dinámico (definido en el inspector o material) por la intensidad
		var final_color := Color(
			base_attack_color.r * intensity,
			base_attack_color.g * intensity,
			base_attack_color.b * intensity,
			alpha
		)
		attack_mesh_material.albedo_color = final_color


# Señal emitida al completar la animación de ataque (último frame)
func _on_animation_finished(anim_name: String) -> void:
	if anim_name == ANIM_ATTACK and current_state == State.ATTACK_OBJECT and _striking_object:
		_finish_object_strike()
		return
	if anim_name == ANIM_ATTACK and current_state == State.ATTACK:
		if is_instance_valid(current_target_player):
			_try_hit_player(current_target_player)

		_stop_attack_tween()

		current_state = State.FLEE
		flee_timer = 1.2
		current_target_player = null
		_play_anim(ANIM_WALK)


# --- ATACAR UN OBJETO (LA RADIO) ---

## Ordena atacar 'target' (se llama con group "enemies" desde Level00Manager).
func command_attack_object(target: Node3D) -> void:
	var chosen: Node3D = attack_object_target if is_instance_valid(attack_object_target) else target
	if current_state == State.DEAD or not is_instance_valid(chosen):
		return
	object_target = chosen
	_striking_object = false
	_object_attack_timer = randf_range(0.0, 0.6) # que no golpeen todos a la vez
	_nav_path = PackedVector3Array()
	_nav_refresh_timer = randf_range(0.0, 0.3) # escalonado: no calculan todos el camino en el mismo cuadro
	is_wandering = false
	_stop_attack_tween()
	current_state = State.ATTACK_OBJECT


## Vuelve al comportamiento normal (patrulla).
func release_object_target() -> void:
	object_target = null
	_striking_object = false
	if current_state == State.DEAD:
		return
	_stop_attack_tween()
	if current_state == State.ATTACK_OBJECT:
		current_state = State.WANDER
		is_wandering = false
		wait_timer = 0.0


func _process_attack_object(delta: float, player_ref: Node3D, dist_to_player: float) -> void:
	if not is_instance_valid(object_target):
		release_object_target()
		return

	# Golpeando: quieto hasta que termine la animación (_finish_object_strike)
	if _striking_object:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Por defecto el jugador se ignora: el objetivo principal es el objeto
	if not ignore_player_in_attack_object and player_ref and dist_to_player <= attack_range:
		_start_attack(player_ref)
		return

	_object_attack_timer -= delta
	var to_object: Vector3 = object_target.global_position - global_position
	to_object.y = 0.0
	if to_object.length() <= object_attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		_rotate_visuals(to_object.normalized(), delta * 2.0)
		_play_anim(ANIM_IDLE)
		if _object_attack_timer <= 0.0:
			_striking_object = true
			_begin_attack_telegraph()
	else:
		var move_dir: Vector3 = _direction_toward_object(delta, to_object)
		velocity.x = move_dir.x * chase_speed
		velocity.z = move_dir.z * chase_speed
		_rotate_visuals(move_dir, delta)
		_play_anim(ANIM_WALK)


## Dirección hacia el objeto rodeando obstáculos (alambrados) con la malla de navegación; sin malla o
## sin camino, va en línea recta.
func _direction_toward_object(delta: float, straight: Vector3) -> Vector3:
	_nav_refresh_timer -= delta
	if _nav_refresh_timer <= 0.0:
		_nav_refresh_timer = 0.3
		_nav_path = RuntimeNavigation.find_path(get_world_3d(), global_position, object_target.global_position)
		_nav_path_index = 0

	# Primer punto del camino que todavía no alcanzó (en el plano)
	while _nav_path_index < _nav_path.size():
		var step: Vector3 = _nav_path[_nav_path_index] - global_position
		step.y = 0.0
		if step.length() > 0.12:
			return step.normalized()
		_nav_path_index += 1
	return straight.normalized()


func _find_hit_receiver(from: Node) -> Node:
	var node: Node = from
	while node:
		if node.has_method("take_hit") or node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null


func _finish_object_strike() -> void:
	_striking_object = false
	_stop_attack_tween()
	_object_attack_timer = object_attack_cooldown
	if is_instance_valid(object_target):
		var to_object: Vector3 = object_target.global_position - global_position
		to_object.y = 0.0
		if to_object.length() <= object_attack_range * 1.8:
			# Igual que la guitarra y el fusil: sube por el árbol hasta el nodo que sabe recibir el golpe
			# (la radio lo recibe en RadioShit, aunque el objetivo sea su malla "Radio"). No hace falta
			# ninguna hitbox: el golpe es una llamada directa a take_hit() / take_damage().
			var receiver: Node = _find_hit_receiver(object_target)
			if receiver:
				if receiver.has_method("take_hit"):
					receiver.take_hit(attack_damage)
				else:
					receiver.take_damage(attack_damage)
	_play_anim(ANIM_IDLE)


func _try_hit_player(player_ref: Node3D) -> void:
	var hit_bodies = attack_area.get_overlapping_bodies() if is_instance_valid(attack_area) else []
	
	if player_ref in hit_bodies or global_position.distance_to(player_ref.global_position) <= attack_range * 1.8:
		var push_dir = (player_ref.global_position - global_position)
		push_dir.y = 0.15
		push_dir = push_dir.normalized()
		
		var impulse = push_dir * knockback_force
		
		if player_ref.has_method("take_damage"):
			player_ref.take_damage(attack_damage, impulse)


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
			velocity.x = dir.x * base_speed
			velocity.z = dir.z * base_speed
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


# --- SISTEMA DE DAÑO Y RETROCESO ---
func take_damage(amount: float, knockback_impulse: Vector3 = Vector3.ZERO) -> void:
	if current_state == State.DEAD:
		return

	current_health -= amount
	current_target_player = null
	_striking_object = false

	_stop_attack_tween()

	if knockback_impulse != Vector3.ZERO:
		velocity = knockback_impulse

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
	
	current_state = State.COOLDOWN
	cooldown_timer = attack_cooldown


func _handle_retreat(delta: float) -> void:
	retreat_timer -= delta
	if retreat_timer <= 0.0:
		is_retreating = false
		_play_anim(ANIM_IDLE)


# --- FÍSICAS Y VISUALES ---
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta


func _apply_friction(delta: float) -> void:
	if current_state != State.CHASE and current_state != State.FLEE and current_state != State.ATTACK_OBJECT and not is_wandering:
		velocity.x = lerp(velocity.x, 0.0, friction * delta)
		velocity.z = lerp(velocity.z, 0.0, friction * delta)


func _rotate_visuals(direction: Vector3, delta: float) -> void:
	if visuals and direction.length() > 0.01:
		var target_angle: float = atan2(direction.x, direction.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 6.0 * delta)


func _flash_red() -> void:
	if enemy_material:
		var red_with_alpha := Color(1.0, 0.1, 0.1, original_albedo_color.a)
		enemy_material.albedo_color = red_with_alpha
		enemy_material.emission_enabled = true
		enemy_material.emission = Color(1.0, 0.0, 0.0)

		get_tree().create_timer(flash_duration).timeout.connect(func():
			if is_instance_valid(enemy_material):
				enemy_material.albedo_color = original_albedo_color
				enemy_material.emission_enabled = false
		)


# --- SETUP DE MATERIALES DE LA ESFERA DE ATAQUE ---
func _setup_attack_mesh_material() -> void:
	if is_instance_valid(attack_mesh):
		attack_mesh.visible = false
		original_attack_mesh_scale = attack_mesh.scale
		
		var base_mat = attack_mesh.get_surface_override_material(0)
		if not base_mat and attack_mesh.mesh and attack_mesh.mesh.get_surface_count() > 0:
			base_mat = attack_mesh.mesh.surface_get_material(0)

		if base_mat is StandardMaterial3D:
			attack_mesh_material = base_mat.duplicate() as StandardMaterial3D
			# Tomamos el color que ya tenga el material si no se configuró uno personalizado
			if base_attack_color == Color(1.0, 0.0, 0.0, 1.0) and attack_mesh_material.albedo_color != Color.WHITE:
				base_attack_color = attack_mesh_material.albedo_color
		else:
			attack_mesh_material = StandardMaterial3D.new()

		attack_mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		attack_mesh.set_surface_override_material(0, attack_mesh_material)
		_update_attack_intensity_and_alpha(0.0, 0.0)


func _stop_attack_tween() -> void:
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()
	
	if is_instance_valid(attack_mesh):
		attack_mesh.visible = false
		attack_mesh.scale = original_attack_mesh_scale

	_update_attack_intensity_and_alpha(0.0, 0.0)


func _setup_material() -> void:
	if mesh_instance:
		var base_mat: Material = mesh_instance.get_surface_override_material(0)
		if not base_mat and mesh_instance.mesh and mesh_instance.mesh.get_surface_count() > 0:
			base_mat = mesh_instance.mesh.surface_get_material(0)

		if base_mat is StandardMaterial3D:
			enemy_material = base_mat.duplicate() as StandardMaterial3D
		else:
			enemy_material = StandardMaterial3D.new()
			if base_mat and base_mat.has_method("get_texture"):
				enemy_material.albedo_texture = base_mat.get_texture(StandardMaterial3D.TEXTURE_ALBEDO)

		mesh_instance.set_surface_override_material(0, enemy_material)
		enemy_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		original_albedo_color = enemy_material.albedo_color


func _play_anim(anim_name: String) -> void:
	if animation_player and animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name)


func die() -> void:
	_stop_attack_tween()
	current_state = State.DEAD
	queue_free()
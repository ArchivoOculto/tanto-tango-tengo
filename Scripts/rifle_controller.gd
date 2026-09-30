extends Node
class_name RifleController

## Modo fusil en primera persona.
##
## Al activarlo:
##  - el jugador queda fijo en su lugar (sin movimiento ni combate cuerpo a cuerpo),
##  - CameraDirector le cede la vista a una Camera3D ubicada en la cabeza,
##  - aparece una mirilla en el centro de la pantalla,
##  - el stick derecho (acciones aim_*) mueve la puntería,
##  - "rifle_shoot" dispara un rayo desde el centro de la cámara.
##
## Va como hijo directo del Player (ver Scenes/player.tscn).

signal rifle_mode_entered
signal rifle_mode_exited
## Útil para conectar sonido, partículas, marcas de impacto, munición, etc.
signal shot_fired(hit_position: Vector3, collider: Object)

@export_group("Activación")
@export var hold_to_aim: bool = false ## true = mantener el botón; false = un toque entra, otro toque sale

@export_group("Puntería")
@export var aim_speed_degrees: float = 100.0 ## Velocidad con el stick al máximo (grados/seg)
@export_range(1.0, 3.0, 0.1) var aim_response_curve: float = 2.0 ## 1 = lineal; más alto = más fino cerca del centro
@export_range(10.0, 89.0) var pitch_limit_degrees: float = 70.0
@export_range(0.0, 180.0) var yaw_limit_degrees: float = 0.0 ## 0 = giro libre; si no, máximo a cada lado desde donde empezó
@export var invert_y: bool = false
@export var field_of_view: float = 65.0

@export_group("Cámara")
## Hueso/anclaje de la cabeza (BoneAttachment3D "Face" del modelo).
@export var eye_anchor_path: NodePath = ^"../Visuals/Armature/Skeleton3D/Face"
## Ajuste fino de la posición del ojo, en unidades de mundo, respecto al anclaje.
## Se aplica en los ejes de la cámara (x = derecha, y = arriba, z = hacia atrás).
@export var eye_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var camera_near: float = 0.01 ## El personaje es pequeño: near bajo para no recortar la escena
@export var hide_head_props: bool = true ## Oculta calavera/pucho mientras se apunta
@export var hide_guitar: bool = true

@export_group("Disparo")
@export var damage: float = 34.0
@export var fire_cooldown: float = 0.45
@export var max_range: float = 60.0
## Capas que el disparo puede golpear: 1 World, 3 Enemies, 4 Props (bits 1 + 4 + 8).
@export_flags_3d_physics var hit_mask: int = 13
@export var knockback_strength: float = 3.0
@export var knockback_upward: float = 1.0

@export_group("Mirilla")
@export var reticle_color: Color = Color(1, 1, 1, 0.95)
@export var reticle_outline_color: Color = Color(0, 0, 0, 0.8)
@export var reticle_radius: float = 7.0
@export var reticle_gap: float = 3.0
@export var reticle_tick_length: float = 5.0

var _player: Player
var _camera: Camera3D
var _eye_anchor: Node3D
var _reticle_layer: CanvasLayer
var _reticle: Control

var _active: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _yaw_center: float = 0.0
var _cooldown_left: float = 0.0
var _reticle_kick: float = 0.0 ## 0..1, se anima al disparar

# Estado previo que hay que restaurar al salir
var _prev_face_visible: bool = true
var _prev_guitar_visible: bool = true
var _prev_combat_processing: bool = true


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_warning("RifleController: debe ser hijo directo del Player.")
		set_process(false)
		set_process_unhandled_input(false)
		return

	_eye_anchor = get_node_or_null(eye_anchor_path) as Node3D
	if _eye_anchor == null:
		push_warning("RifleController: no se encontró el anclaje de la cabeza en '%s'. Se usará la posición del jugador." % eye_anchor_path)

	_build_camera()
	_build_reticle()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rifle_toggle"):
		if _active:
			if not hold_to_aim:
				exit_rifle_mode()
		else:
			enter_rifle_mode()
	elif hold_to_aim and _active and event.is_action_released("rifle_toggle"):
		exit_rifle_mode()


func _process(delta: float) -> void:
	if not _active:
		return

	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_update_aim(delta)
	_update_camera_transform()

	if Input.is_action_just_pressed("rifle_shoot"):
		_try_fire()

	if _reticle_kick > 0.0:
		_reticle_kick = maxf(_reticle_kick - delta * 6.0, 0.0)
		_reticle.queue_redraw()


# ---------------------------------------------------------------- ENTRAR / SALIR

func can_enter() -> bool:
	if _active or _player == null:
		return false
	# No entrar si otro sistema (ej. inspeccionar un cuadro) frenó al jugador,
	# ni en pleno salto/caída.
	if not _player.is_physics_processing() or not _player.is_on_floor():
		return false
	if CameraDirector.is_first_person():
		return false
	return true


func enter_rifle_mode() -> void:
	if not can_enter():
		return
	_active = true

	# --- Congelar al jugador (mismo patrón que interactable_picture.gd) ---
	_player.velocity = Vector3.ZERO
	if _player.combat_controller:
		_player.combat_controller.interrupt_actions()
		_prev_combat_processing = _player.combat_controller.is_processing()
		_player.combat_controller.set_process(false)
	if _player.anim_controller:
		_player.anim_controller.update_locomotion(true, 0.0)
	_player.set_physics_process(false)

	# --- Apariencia en primera persona ---
	if _eye_anchor and hide_head_props:
		_prev_face_visible = _eye_anchor.visible
		_eye_anchor.visible = false
	var guitar: Node3D = _get_guitar()
	if guitar and hide_guitar:
		_prev_guitar_visible = guitar.visible
		guitar.visible = false

	# --- Puntería inicial: hacia donde mira el personaje ---
	var facing: Vector3 = _player.visuals.global_transform.basis.z # el modelo mira hacia +Z local
	_yaw = atan2(facing.x, facing.z)
	_yaw_center = _yaw
	_pitch = 0.0
	_cooldown_left = 0.0
	_update_camera_transform()

	_reticle_layer.visible = true
	CameraDirector.enter_first_person(_camera)
	rifle_mode_entered.emit()


func exit_rifle_mode() -> void:
	if not _active:
		return
	_active = false

	_reticle_layer.visible = false
	CameraDirector.exit_first_person()

	# El cuerpo queda mirando hacia donde se estaba apuntando
	if is_instance_valid(_player):
		_set_body_yaw(_yaw)

	if _eye_anchor and hide_head_props:
		_eye_anchor.visible = _prev_face_visible
	var guitar: Node3D = _get_guitar()
	if guitar and hide_guitar:
		guitar.visible = _prev_guitar_visible

	if is_instance_valid(_player):
		_player.set_physics_process(true)
		if _player.combat_controller:
			_player.combat_controller.set_process(_prev_combat_processing)

	rifle_mode_exited.emit()


func is_active() -> bool:
	return _active


func _exit_tree() -> void:
	# Por si el jugador se libera (cambio de escena / warp) con el modo activo.
	if _active:
		_active = false
		CameraDirector.exit_first_person()


# ---------------------------------------------------------------- PUNTERÍA

func _update_aim(delta: float) -> void:
	# Get_vector ya aplica la zona muerta configurada en cada acción.
	var stick: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick == Vector2.ZERO:
		return

	# Curva de respuesta: da precisión fina cerca del centro sin perder velocidad al tope.
	var strength: float = pow(stick.length(), aim_response_curve)
	var dir: Vector2 = stick.normalized() * strength
	var step: float = deg_to_rad(aim_speed_degrees) * delta

	_yaw -= dir.x * step # stick a la derecha => la mirada gira a la derecha
	_pitch += dir.y * step * (1.0 if invert_y else -1.0)

	var pitch_limit: float = deg_to_rad(pitch_limit_degrees)
	_pitch = clampf(_pitch, -pitch_limit, pitch_limit)

	if yaw_limit_degrees > 0.0:
		var yaw_limit: float = deg_to_rad(yaw_limit_degrees)
		_yaw = _yaw_center + clampf(wrapf(_yaw - _yaw_center, -PI, PI), -yaw_limit, yaw_limit)


func _aim_direction() -> Vector3:
	return Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)
	).normalized()


func _update_camera_transform() -> void:
	var eye_pos: Vector3 = _player.global_position + Vector3.UP * (_player.get_body_height() * 0.5)
	if is_instance_valid(_eye_anchor):
		eye_pos = _eye_anchor.global_position

	var aim_basis: Basis = Basis.looking_at(_aim_direction(), Vector3.UP)
	_camera.global_transform = Transform3D(aim_basis, eye_pos + aim_basis * eye_offset)

	# El cuerpo acompaña el giro horizontal (se ve al salir del modo y en sombras/reflejos)
	_set_body_yaw(_yaw)


# ---------------------------------------------------------------- DISPARO

func _try_fire() -> void:
	if _cooldown_left > 0.0:
		return
	_cooldown_left = fire_cooldown
	_reticle_kick = 1.0
	_reticle.queue_redraw()

	var origin: Vector3 = _camera.global_position
	var direction: Vector3 = -_camera.global_basis.z
	var end: Vector3 = origin + direction * max_range

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = hit_mask
	query.exclude = [_player.get_rid()]

	var result: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		shot_fired.emit(end, null)
		return

	var collider: Object = result.collider
	_apply_hit(collider, direction)
	shot_fired.emit(result.position, collider)


## Sube por el árbol hasta encontrar quien sepa recibir daño, igual que WeaponHitbox.
func _apply_hit(collider: Object, direction: Vector3) -> void:
	var target: Node = collider as Node
	while target and not target.has_method("take_hit") and not target.has_method("take_damage"):
		target = target.get_parent()
	if target == null or target.is_in_group("player"):
		return

	if target.has_method("take_hit"):
		target.take_hit(damage)

	if target.has_method("take_damage"):
		var flat: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
		var knockback: Vector3 = flat * knockback_strength + Vector3.UP * knockback_upward
		target.take_damage(damage, knockback)


## Orienta el modelo hacia 'yaw' (mundo). Usa rotación local, igual que Player._rotate_visuals_towards,
## para no tocar la escala del modelo.
func _set_body_yaw(yaw: float) -> void:
	if _player.visuals:
		_player.visuals.rotation.y = yaw - _player.global_rotation.y


# ---------------------------------------------------------------- SETUP INTERNO

func _get_guitar() -> Node3D:
	return _player.get_node_or_null("Visuals/Armature/Skeleton3D/righthand_grip") as Node3D


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "RifleCamera"
	_camera.top_level = true # se posiciona en coordenadas de mundo, sin heredar la escala del modelo
	_camera.fov = field_of_view
	_camera.near = camera_near
	add_child(_camera)


func _build_reticle() -> void:
	_reticle_layer = CanvasLayer.new()
	_reticle_layer.layer = 100 # sobre la UI de juego, bajo las barras 4:3 (127) y el fundido (128)
	_reticle_layer.visible = false
	add_child(_reticle_layer)

	_reticle = Control.new()
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(_draw_reticle)
	_reticle_layer.add_child(_reticle)


func _draw_reticle() -> void:
	var center: Vector2 = _reticle.size * 0.5
	var spread: float = _reticle_kick * 4.0 # la mirilla "salta" un poco al disparar
	var radius: float = reticle_radius + spread
	var gap: float = reticle_gap + spread
	var tick: float = reticle_tick_length

	# Contorno oscuro primero (para que se lea sobre fondos claros), luego el trazo claro.
	for pass_index in 2:
		var color: Color = reticle_outline_color if pass_index == 0 else reticle_color
		var width: float = 3.0 if pass_index == 0 else 1.0
		_reticle.draw_arc(center, radius, 0.0, TAU, 32, color, width, false)
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_reticle.draw_line(center + dir * (radius + gap), center + dir * (radius + gap + tick), color, width)

	_reticle.draw_circle(center, 1.5, reticle_outline_color)
	_reticle.draw_circle(center, 0.8, reticle_color)

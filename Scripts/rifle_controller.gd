extends Node
class_name RifleController

## Modo fusil en primera persona.
##
## Flujo (máquina de estados):
##   IDLE --(rifle_toggle)--> ENTERING --(cámara anclada)--> AIMING --(soltar/tocar)--> EXITING --> IDLE
##
## ENTERING: el jugador se congela, empieza la pose "player_guitar" (se mantiene mientras
##           dure todo el modo), aparecen las barras 4:3 y la cámara se desliza con suavizado
##           desde donde estaba la GameCamera hasta anclarse en la cabeza.
## AIMING:   la cámara sigue a la cabeza, aparece la mirilla y el stick derecho (aim_*)
##           mueve la puntería. "rifle_shoot" dispara un rayo desde el centro de la cámara.
## EXITING:  las barras se retraen y la cámara vuelve deslizándose (duración fija) hasta la
##           GameCamera; recién ahí el jugador recupera el control.
##
## Las cinemáticas tienen prioridad: si CameraDirector.force_zone() se llama (puerta,
## alcantarilla...), el modo fusil se cierra solo con una salida rápida, y no se puede
## volver a entrar hasta que la cinemática termine.
##
## Va como hijo directo del Player (ver Scenes/player.tscn).

## Empieza la transición de entrada (la cámara todavía viaja hacia la cabeza).
signal rifle_mode_entered
## La cámara ya está anclada en la cabeza: desde acá se puede apuntar y disparar.
signal rifle_aim_ready
## La vista ya volvió a la GameCamera y el jugador recuperó el control.
signal rifle_mode_exited
## Útil para conectar sonido, partículas, marcas de impacto, munición, etc.
signal shot_fired(hit_position: Vector3, collider: Object)

enum State { IDLE, ENTERING, AIMING, EXITING }

@export_group("Activación")
@export var hold_to_aim: bool = true ## true = mantener el botón; false = un toque entra, otro toque sale

@export_group("Transición de cámara")
## Entrada: qué tan rápido se desliza la cámara hacia la cabeza (mayor = más rápido).
## Mismo estilo de suavizado que follow_smoothing de las zonas.
@export var enter_smoothing: float = 6.0
## Entrada: distancia (unidades de mundo) y ángulo a partir de los cuales la cámara se considera "llegada".
@export var arrive_distance: float = 0.02
@export_range(0.1, 10.0) var arrive_angle_degrees: float = 1.5
## Entrada: red de seguridad; si por algo no llega, se ancla igual pasado este tiempo (segundos).
@export var max_transition_time: float = 1.5
## Salida: duración fija del regreso a la GameCamera (llega siempre exacta, aunque la GameCamera siga moviéndose).
@export var exit_duration: float = 0.5
## Salida forzada por una cinemática: más corta para que el plano de la cinemática se vea a tiempo.
@export var cutscene_exit_duration: float = 0.2

@export_group("Formato 4:3")
@export var use_4_3: bool = true ## Recorta la pantalla a 4:3 con barras negras mientras dure el modo
@export var letterbox_duration: float = 0.6

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
@export var hide_head_props: bool = true ## Oculta calavera/pucho una vez que la cámara está en la cabeza

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
@export var reticle_fade_time: float = 0.2

var _player: Player
var _camera: Camera3D
var _eye_anchor: Node3D
var _reticle_layer: CanvasLayer
var _reticle: Control
var _reticle_tween: Tween

var _state: State = State.IDLE
var _yaw: float = 0.0
var _pitch: float = 0.0
var _yaw_center: float = 0.0
var _cooldown_left: float = 0.0
var _reticle_kick: float = 0.0 ## 0..1, se anima al disparar
var _transition_time: float = 0.0
var _exit_duration_now: float = 0.5
var _exit_from: Transform3D
var _exit_fov_from: float = 65.0

# Estado previo que hay que restaurar al salir
var _head_props_hidden: bool = false
var _prev_face_visible: bool = true
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
	CameraDirector.zone_forced.connect(_on_zone_forced)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rifle_toggle"):
		if _state == State.IDLE or _state == State.EXITING:
			enter_rifle_mode()
		elif not hold_to_aim:
			exit_rifle_mode()
	elif hold_to_aim and event.is_action_released("rifle_toggle"):
		if _state == State.ENTERING or _state == State.AIMING:
			exit_rifle_mode()


func _process(delta: float) -> void:
	match _state:
		State.ENTERING:
			_process_entering(delta)
		State.AIMING:
			_process_aiming(delta)
		State.EXITING:
			_process_exiting(delta)


# ---------------------------------------------------------------- ESTADO PÚBLICO

func is_active() -> bool:
	return _state != State.IDLE


func is_aiming() -> bool:
	return _state == State.AIMING


func can_enter() -> bool:
	if _state != State.IDLE or _player == null:
		return false
	# No entrar si otro sistema (ej. inspeccionar un cuadro) frenó al jugador,
	# ni en pleno salto/caída, ni durante una cinemática (tiene prioridad).
	if not _player.is_physics_processing() or not _player.is_on_floor():
		return false
	if CameraDirector.is_first_person() or CameraDirector.has_forced_zone():
		return false
	return true


# ---------------------------------------------------------------- ENTRAR

func enter_rifle_mode() -> void:
	# Re-entrada mientras todavía está volviendo: se retoma desde donde está la cámara.
	if _state == State.EXITING:
		if CameraDirector.has_forced_zone():
			return
		_state = State.ENTERING
		_transition_time = 0.0
		_player.anim_controller.enter_rifle_pose()
		CameraDirector.set_first_person_letterbox(use_4_3, letterbox_duration)
		return

	if not can_enter():
		return

	_freeze_player()

	# Puntería inicial: hacia donde mira el personaje
	var facing: Vector3 = _player.visuals.global_transform.basis.z # el modelo mira hacia +Z local
	_yaw = atan2(facing.x, facing.z)
	_yaw_center = _yaw
	_pitch = 0.0
	_cooldown_left = 0.0
	_transition_time = 0.0

	# La cámara del fusil arranca exactamente donde está la GameCamera (sin salto)
	var game_cam: Camera3D = _get_game_camera()
	if game_cam:
		_camera.global_transform = game_cam.global_transform.orthonormalized()
		_camera.fov = game_cam.fov
	else:
		_camera.global_transform = _head_transform()
		_camera.fov = field_of_view

	_state = State.ENTERING
	_player.anim_controller.enter_rifle_pose() # "player_guitar" durante todo el modo
	CameraDirector.enter_first_person(_camera, use_4_3, letterbox_duration)
	rifle_mode_entered.emit()


func _process_entering(delta: float) -> void:
	_transition_time += delta
	var target: Transform3D = _head_transform()
	_blend_camera_toward(target, field_of_view, enter_smoothing, delta)

	if _camera_arrived(target, field_of_view) or _transition_time >= max_transition_time:
		_finish_enter(target)


func _finish_enter(target: Transform3D) -> void:
	_state = State.AIMING
	_camera.global_transform = target
	_camera.fov = field_of_view
	_hide_head_props()
	_show_reticle()
	rifle_aim_ready.emit()


# ---------------------------------------------------------------- APUNTAR

func _process_aiming(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_update_aim(delta)
	_camera.global_transform = _head_transform()
	_set_body_yaw(_yaw) # el cuerpo acompaña el giro horizontal

	if Input.is_action_just_pressed("rifle_shoot"):
		_try_fire()

	if _reticle_kick > 0.0:
		_reticle_kick = maxf(_reticle_kick - delta * 6.0, 0.0)
		_reticle.queue_redraw()


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


## Dónde tiene que estar la cámara cuando está anclada en la cabeza.
func _head_transform() -> Transform3D:
	var eye_pos: Vector3 = _player.global_position + Vector3.UP * (_player.get_body_height() * 0.5)
	if is_instance_valid(_eye_anchor):
		eye_pos = _eye_anchor.global_position

	var aim_basis: Basis = Basis.looking_at(_aim_direction(), Vector3.UP)
	return Transform3D(aim_basis, eye_pos + aim_basis * eye_offset)


# ---------------------------------------------------------------- SALIR

## 'fast' = salida forzada por una cinemática (más corta).
func exit_rifle_mode(fast: bool = false) -> void:
	if _state == State.IDLE:
		return

	if _state == State.EXITING:
		if fast and _exit_duration_now > cutscene_exit_duration:
			_begin_exit_blend(cutscene_exit_duration) # re-parte desde donde está, sin saltos
		return

	_state = State.EXITING
	_begin_exit_blend(cutscene_exit_duration if fast else exit_duration)

	# Todo lo visual se suelta al empezar la salida; el control del jugador, al terminar.
	_hide_reticle()
	_restore_head_props()
	_player.anim_controller.exit_rifle_pose()
	CameraDirector.set_first_person_letterbox(false, letterbox_duration)


func _begin_exit_blend(duration: float) -> void:
	_transition_time = 0.0
	_exit_duration_now = maxf(duration, 0.01)
	_exit_from = _camera.global_transform
	_exit_fov_from = _camera.fov


func _process_exiting(delta: float) -> void:
	_transition_time += delta
	var game_cam: Camera3D = _get_game_camera()
	if game_cam == null:
		_finish_exit()
		return

	# Progreso con desaceleración (mismo aire que el suavizado de entrada) que llega a 1
	# exacto en 'duration'. El objetivo es la GameCamera EN VIVO: sigue moviéndose hacia
	# su zona (o hacia la cinemática) mientras volvemos, y al llegar no hay salto.
	var t: float = clampf(_transition_time / _exit_duration_now, 0.0, 1.0)
	var weight: float = 1.0 - pow(1.0 - t, 3.0)

	var target: Transform3D = game_cam.global_transform.orthonormalized()
	var blended_rot: Quaternion = _exit_from.basis.get_rotation_quaternion().slerp(
		target.basis.get_rotation_quaternion(), weight)
	_camera.global_transform = Transform3D(Basis(blended_rot), _exit_from.origin.lerp(target.origin, weight))
	_camera.fov = lerpf(_exit_fov_from, game_cam.fov, weight)

	if t >= 1.0:
		_finish_exit()


func _finish_exit() -> void:
	_state = State.IDLE
	CameraDirector.exit_first_person()

	if is_instance_valid(_player):
		_player.set_physics_process(true)
		if _player.combat_controller:
			_player.combat_controller.set_process(_prev_combat_processing)

	rifle_mode_exited.emit()


func _on_zone_forced(_zone: CameraZone3D) -> void:
	# Una cinemática (puerta, alcantarilla...) manda: cerramos el modo fusil para que se vea.
	if _state != State.IDLE:
		exit_rifle_mode(true)


func _exit_tree() -> void:
	# Por si el jugador se libera (cambio de escena / warp) con el modo activo.
	if _state != State.IDLE:
		_state = State.IDLE
		CameraDirector.exit_first_person()


# ---------------------------------------------------------------- CÁMARA

## ENTRADA: acerca la cámara a 'target' con suavizado exponencial (independiente del framerate).
func _blend_camera_toward(target: Transform3D, target_fov: float, smoothing: float, delta: float) -> void:
	var weight: float = 1.0 - exp(-smoothing * delta)
	var current: Transform3D = _camera.global_transform
	var blended_rot: Quaternion = current.basis.get_rotation_quaternion().slerp(
		target.basis.get_rotation_quaternion(), weight)
	_camera.global_transform = Transform3D(Basis(blended_rot), current.origin.lerp(target.origin, weight))
	_camera.fov = lerpf(_camera.fov, target_fov, weight)


func _camera_arrived(target: Transform3D, target_fov: float) -> bool:
	var current: Transform3D = _camera.global_transform
	if current.origin.distance_to(target.origin) > arrive_distance:
		return false
	var angle: float = current.basis.get_rotation_quaternion().angle_to(target.basis.get_rotation_quaternion())
	return angle <= deg_to_rad(arrive_angle_degrees) and absf(_camera.fov - target_fov) < 0.5


func _get_game_camera() -> Camera3D:
	return get_tree().get_first_node_in_group("game_camera") as Camera3D


# ---------------------------------------------------------------- JUGADOR / APARIENCIA

func _freeze_player() -> void:
	_player.velocity = Vector3.ZERO
	if _player.combat_controller:
		_player.combat_controller.interrupt_actions()
		_prev_combat_processing = _player.combat_controller.is_processing()
		_player.combat_controller.set_process(false)
	_player.set_physics_process(false)


func _hide_head_props() -> void:
	if _eye_anchor and hide_head_props and not _head_props_hidden:
		_prev_face_visible = _eye_anchor.visible
		_eye_anchor.visible = false
		_head_props_hidden = true


func _restore_head_props() -> void:
	if _eye_anchor and _head_props_hidden:
		_eye_anchor.visible = _prev_face_visible
		_head_props_hidden = false


## Orienta el modelo hacia 'yaw' (mundo). Usa rotación local, igual que Player._rotate_visuals_towards,
## para no tocar la escala del modelo.
func _set_body_yaw(yaw: float) -> void:
	if _player.visuals:
		_player.visuals.rotation.y = yaw - _player.global_rotation.y


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


# ---------------------------------------------------------------- SETUP INTERNO

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "RifleCamera"
	_camera.top_level = true # se posiciona en coordenadas de mundo, sin heredar la escala del modelo
	_camera.fov = field_of_view
	_camera.near = camera_near
	add_child(_camera)


func _build_reticle() -> void:
	_reticle_layer = CanvasLayer.new()
	_reticle_layer.layer = 100 # sobre la UI de juego, bajo las barras 4:3 (126), el inventario (127) y el fundido (128)
	_reticle_layer.visible = false
	add_child(_reticle_layer)

	_reticle = Control.new()
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(_draw_reticle)
	_reticle_layer.add_child(_reticle)


func _show_reticle() -> void:
	if _reticle_tween and _reticle_tween.is_valid():
		_reticle_tween.kill()
	_reticle.modulate.a = 0.0
	_reticle_layer.visible = true
	_reticle_tween = create_tween()
	_reticle_tween.tween_property(_reticle, "modulate:a", 1.0, reticle_fade_time)


func _hide_reticle() -> void:
	if _reticle_tween and _reticle_tween.is_valid():
		_reticle_tween.kill()
	_reticle_layer.visible = false


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

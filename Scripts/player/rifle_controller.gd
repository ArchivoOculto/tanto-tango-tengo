extends Node
class_name RifleController

## Modo fusil en primera persona.
##
## Flujo (máquina de estados):
##   IDLE --(rifle_toggle)--> ENTERING --(cámara anclada)--> AIMING --(soltar/tocar)--> EXITING --> IDLE
##
## ENTERING: el jugador se congela, empieza la pose "player_guitar" (se mantiene mientras
##           dure todo el modo), aparecen las barras 4:3 y la cámara viaja en DOS fases:
##             1. ORBITA alrededor del jugador (sin atravesarlo) hasta quedar justo detrás de su espalda.
##                Se evita así el "TP" aparente cuando el jugador mira directo hacia el anchor de la
##                GameCamera (la cámara quedaría delante y cruzaría el cuerpo de un salto).
##                Si la cámara ya está detrás del jugador, esta fase se salta.
##             2. Desde la espalda se desliza con suavizado hasta anclarse en la cabeza (acá sí
##                "atraviesa" el cuerpo, ya que entra al ojo).
## AIMING:   la cámara sigue a la cabeza, aparece la mirilla y el stick derecho (aim_*)
##           mueve la puntería. "rifle_shoot" dispara un rayo desde el centro de la cámara.
## EXITING:  las barras se retraen y la cámara vuelve deslizándose (duración fija) hasta la
##           GameCamera; recién ahí el jugador recupera el control.
##
## Las cinemáticas tienen prioridad: si CameraDirector.force_zone() se llama (puerta,
## alcantarilla...), el modo fusil se cierra solo con una salida rápida, y no se puede
## volver a entrar hasta que la cinemática termine.
##
## Va como hijo directo del Player (ver Scenes/characters/player.tscn).

## Empieza la transición de entrada (la cámara todavía viaja hacia la cabeza).
signal rifle_mode_entered
## La cámara ya está anclada en la cabeza: desde acá se puede apuntar y disparar.
signal rifle_aim_ready
## La vista ya volvió a la GameCamera y el jugador recuperó el control.
signal rifle_mode_exited
## Útil para conectar sonido, partículas, marcas de impacto, munición, etc.
signal shot_fired(hit_position: Vector3, collider: Object)

enum State { IDLE, ENTERING, AIMING, EXITING }

# UI del zoom (posiciones relativas al centro de la pantalla base de 845 x 480; las barras 4:3 tapan ~102 px por lado)
const HINT_ROW_Y: float = 205.0 ## centro de la pista "(L2)(R2) zoom": abajo, con ~20 px de aire
const ZOOM_LABEL_Y: float = 36.0 ## centro de la lectura "x2.5": justo bajo la mirilla
const HINT_SHOW_TIME: float = 4.0 ## las pistas se ven a pleno este tiempo (s) al entrar al modo fusil
const HINT_USE_TIME: float = 1.5 ## y este tiempo después de cada uso del zoom
const HINT_IDLE_ALPHA: float = 0.4 ## transparencia de las pistas cuando no se usan
const HINT_FADE_SPEED: float = 2.5 ## cambio de transparencia por segundo

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
@export var max_transition_time: float = 2.5
## Entrada, fase 1: primero la cámara orbita hasta la espalda del jugador y recién ahí va a la cabeza.
@export var orbit_behind: bool = true
## Duración de la órbita si hay que dar media vuelta (180°); para giros menores es proporcionalmente más corta.
@export var orbit_duration: float = 0.55
## A qué distancia queda detrás del jugador antes de entrar a la cabeza (fracción de la altura del personaje).
@export var behind_distance_ratio: float = 1.4
## Altura sobre la cabeza durante la órbita (fracción de la altura del personaje).
@export var behind_height_ratio: float = 0.15
## Si la cámara ya está dentro de este ángulo respecto de la espalda del jugador, no hace falta orbitar.
@export_range(0.0, 90.0) var orbit_skip_angle_degrees: float = 12.0
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
## Apuntar con el mouse: grados de giro por píxel de movimiento (0 = desactivado). El mouse se captura
## mientras se apunta (y se libera al salir del modo fusil).
@export_range(0.0, 1.0, 0.01) var mouse_sensitivity_degrees: float = 0.12
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

@export_group("Zoom")
## Permite acercar la mira, como un sniper: gatillos R2 (acercar) y L2 (alejar), teclas E / Q o rueda del mouse.
## Con zoom la mira gira más lento (proporcional al aumento) para poder apuntar con precisión.
@export var allow_zoom: bool = true
## Zoom máximo (1 = sin acercar).
@export_range(1.0, 8.0, 0.1, "suffix:x") var max_zoom: float = 3.0
## Con gatillo o tecla: cambio de zoom por segundo (logarítmico: se siente parejo a cualquier zoom).
@export var zoom_rate: float = 1.6
## Factor por cada muesca de la rueda del mouse.
@export var zoom_wheel_step: float = 1.25
## Qué tan rápido el zoom real alcanza al pedido (1/s).
@export var zoom_smooth: float = 14.0

@export_group("Impacto (game juice)")
## Temblor al disparar: impulso de velocidad (rad/s) que se le da a un resorte de la cámara. El resorte lo
## devuelve solo a su sitio (mismo tipo de resorte que GameCamera). Cabeceo hacia arriba, y guiñada y
## balanceo al azar para que no sea siempre igual. 0 = sin temblor.
@export var shake_pitch_kick: float = 1.1
@export var shake_yaw_kick: float = 0.4
@export var shake_roll_kick: float = 0.5
## Qué tan rápido vuelve a su sitio (s). Menos = temblor más seco.
@export var shake_smooth_time: float = 0.14
## Hit-stop al acertarle a algo que reacciona (enemigo, farolito, radio, calaveras...): el juego casi se
## congela este tiempo (segundos REALES). 0 = sin hit-stop.
@export var hit_stop_duration: float = 0.07
## Velocidad del juego durante el hit-stop (1 = normal, 0 = congelado del todo).
@export_range(0.0, 1.0, 0.01) var hit_stop_time_scale: float = 0.05

@export_group("Mirilla")
@export var reticle_color: Color = Color(1, 1, 1, 0.95)
@export var reticle_outline_color: Color = Color(0, 0, 0, 0.8)
@export var reticle_radius: float = 7.0
@export var reticle_gap: float = 3.0
@export var reticle_tick_length: float = 5.0
@export var reticle_fade_time: float = 0.2
## Color al que se enciende la mirilla (y engorda) cuando el disparo acierta a algo que reacciona.
@export var reticle_hit_color: Color = Color(1.0, 0.85, 0.3, 1.0)

var _player: Player
var _camera: Camera3D
var _eye_anchor: Node3D
var _reticle_layer: CanvasLayer
var _reticle: Control
var _reticle_tween: Tween

var _state: State = State.IDLE
var _mouse_delta: Vector2 = Vector2.ZERO
var _mouse_mode_before: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _mouse_captured: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _yaw_center: float = 0.0
var _cooldown_left: float = 0.0
var _reticle_kick: float = 0.0 ## 0..1, se anima al disparar
var _zoom: float = 1.0 ## zoom actual (suavizado)
var _zoom_target: float = 1.0 ## zoom pedido
var _hint_root: Control ## pistas de botones (solo en modo fusil)
var _zoom_label: Label ## lectura del aumento ("x2.5") bajo la mirilla
var _zoom_label_text: String = ""
var _hint_timer: float = 0.0 ## mientras > 0 las pistas se ven a pleno; después quedan tenues
var _hint_alpha: float = 0.0
var _reticle_hit: float = 0.0 ## 0..1, se enciende al acertar
var _shake: GameCamera.Spring = GameCamera.Spring.new() ## desvío de la cámara (cabeceo, guiñada, balanceo) en rad
var _hit_stop_token: int = 0
var _hit_stop_active: bool = false
var _transition_time: float = 0.0
var _exit_duration_now: float = 0.5
var _exit_from: Transform3D
var _exit_fov_from: float = 65.0

# Entrada: fase de órbita
enum EnterPhase { ORBIT, APPROACH }
var _enter_phase: EnterPhase = EnterPhase.APPROACH
var _orbit_time: float = 0.0
var _orbit_total: float = 0.0
var _orbit_from_angle: float = 0.0
var _orbit_delta: float = 0.0
var _orbit_from_radius: float = 0.0
var _orbit_from_height: float = 0.0
var _orbit_from_rot: Quaternion = Quaternion.IDENTITY

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
	if event is InputEventMouseMotion:
		if _state == State.AIMING and mouse_sensitivity_degrees > 0.0:
			_mouse_delta += (event as InputEventMouseMotion).relative
		return
	# Rueda del mouse: acerca / aleja la mira
	if event is InputEventMouseButton and event.pressed and _state == State.AIMING and allow_zoom:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = minf(_zoom_target * zoom_wheel_step, max_zoom)
			_hint_timer = HINT_USE_TIME
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = maxf(_zoom_target / zoom_wheel_step, 1.0)
			_hint_timer = HINT_USE_TIME
			get_viewport().set_input_as_handled()
			return
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
		_begin_enter_transition()
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
	_begin_enter_transition()
	_player.anim_controller.enter_rifle_pose() # "player_guitar" durante todo el modo
	CameraDirector.enter_first_person(_camera, use_4_3, letterbox_duration)
	rifle_mode_entered.emit()


func _process_entering(delta: float) -> void:
	_transition_time += delta
	var target: Transform3D = _head_transform()

	if _enter_phase == EnterPhase.ORBIT:
		_process_orbit(delta)
		if _transition_time >= max_transition_time:
			_finish_enter(target) # red de seguridad
		return

	_blend_camera_toward(target, field_of_view, enter_smoothing, delta)

	if _camera_arrived(target, field_of_view) or _transition_time >= max_transition_time:
		_finish_enter(target)


## Decide cómo empieza el viaje de la cámara: orbitando hasta la espalda del jugador (si la cámara
## está del costado o de frente) o directo a la cabeza (si ya está detrás).
func _begin_enter_transition() -> void:
	_enter_phase = EnterPhase.APPROACH
	if not orbit_behind:
		return

	var body_height: float = _player.get_body_height()
	var offset: Vector3 = _camera.global_position - _head_position()
	var flat: Vector3 = Vector3(offset.x, 0.0, offset.z)
	if flat.length() < body_height * 0.15:
		return # la cámara ya está pegada a la cabeza

	var behind_angle: float = _yaw + PI # la espalda es el lado opuesto a hacia donde mira
	var from_angle: float = atan2(flat.x, flat.z)
	var delta_angle: float = angle_difference(from_angle, behind_angle) # por el camino más corto
	if absf(delta_angle) <= deg_to_rad(orbit_skip_angle_degrees):
		return

	_enter_phase = EnterPhase.ORBIT
	_orbit_time = 0.0
	_orbit_total = maxf(orbit_duration * clampf(absf(delta_angle) / PI, 0.35, 1.0), 0.05)
	_orbit_from_angle = from_angle
	_orbit_delta = delta_angle
	_orbit_from_radius = flat.length()
	_orbit_from_height = offset.y
	_orbit_from_rot = _camera.global_basis.get_rotation_quaternion()


## Fase 1: la cámara gira alrededor de la cabeza del jugador hasta su espalda. El radio nunca baja de un
## mínimo, así que NUNCA atraviesa el cuerpo; siempre mira a la cabeza.
func _process_orbit(delta: float) -> void:
	_orbit_time += delta
	var t: float = clampf(_orbit_time / _orbit_total, 0.0, 1.0)
	var weight: float = t * t * (3.0 - 2.0 * t) # smoothstep

	var body_height: float = _player.get_body_height()
	var head: Vector3 = _head_position()
	var angle: float = _orbit_from_angle + _orbit_delta * weight
	var radius: float = maxf(lerpf(_orbit_from_radius, body_height * behind_distance_ratio, weight), body_height * 0.4)
	var height: float = lerpf(_orbit_from_height, body_height * behind_height_ratio, weight)

	var cam_pos: Vector3 = head + Vector3(sin(angle) * radius, height, cos(angle) * radius)

	var look_rot: Quaternion = Basis.looking_at(head - cam_pos, Vector3.UP).get_rotation_quaternion()
	_camera.global_transform = Transform3D(Basis(_orbit_from_rot.slerp(look_rot, weight)), cam_pos)

	if t >= 1.0:
		_enter_phase = EnterPhase.APPROACH # ya está en la espalda: ahora sí, hacia la cabeza


func _finish_enter(target: Transform3D) -> void:
	_state = State.AIMING
	_camera.global_transform = target
	_camera.fov = field_of_view
	_zoom = 1.0
	_zoom_target = 1.0
	_shake.reset(Vector3.ZERO)
	_hide_head_props()
	_show_reticle()
	_capture_mouse()
	rifle_aim_ready.emit()


# ---------------------------------------------------------------- APUNTAR

func _process_aiming(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_update_zoom(delta) # antes de apuntar: la sensibilidad depende del zoom
	_update_aim(delta)
	_camera.global_transform = _head_transform()
	_set_body_yaw(_yaw) # el cuerpo acompaña el giro horizontal

	if GameplayInput.just_pressed(&"rifle_shoot"):
		_try_fire()

	if _reticle_kick > 0.0 or _reticle_hit > 0.0:
		_reticle_kick = maxf(_reticle_kick - delta * 6.0, 0.0)
		_reticle_hit = maxf(_reticle_hit - delta * 4.0, 0.0)
		_reticle.queue_redraw()

	_apply_shake(delta) # al final: el disparo de arriba usó la cámara limpia, sin el temblor del anterior
	_update_zoom_hud(delta)


## El mouse apunta mientras se mantiene el modo fusil: se captura para poder girar sin límite de pantalla.
func _capture_mouse() -> void:
	if mouse_sensitivity_degrees <= 0.0 or _mouse_captured:
		return
	_mouse_mode_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true
	_mouse_delta = Vector2.ZERO


func _release_mouse() -> void:
	_mouse_delta = Vector2.ZERO
	if _mouse_captured:
		Input.mouse_mode = _mouse_mode_before
		_mouse_captured = false


## Gira la mirada: 'right' y 'down' en radianes (positivo = hacia la derecha / hacia abajo).
func _rotate_aim(right: float, down: float) -> void:
	_yaw -= right # a la derecha => la mirada gira a la derecha
	_pitch += down * (1.0 if invert_y else -1.0)

	var pitch_limit: float = deg_to_rad(pitch_limit_degrees)
	_pitch = clampf(_pitch, -pitch_limit, pitch_limit)

	if yaw_limit_degrees > 0.0:
		var yaw_limit: float = deg_to_rad(yaw_limit_degrees)
		_yaw = _yaw_center + clampf(wrapf(_yaw - _yaw_center, -PI, PI), -yaw_limit, yaw_limit)


func _update_aim(delta: float) -> void:
	# Mouse: movimiento acumulado desde el último cuadro
	if _mouse_delta != Vector2.ZERO:
		var per_pixel: float = deg_to_rad(mouse_sensitivity_degrees) / _zoom
		_rotate_aim(_mouse_delta.x * per_pixel, _mouse_delta.y * per_pixel)
		_mouse_delta = Vector2.ZERO

	# Get_vector ya aplica la zona muerta configurada en cada acción.
	var stick: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick == Vector2.ZERO:
		return

	# Curva de respuesta: da precisión fina cerca del centro sin perder velocidad al tope.
	var strength: float = pow(stick.length(), aim_response_curve)
	var dir: Vector2 = stick.normalized() * strength
	var step: float = deg_to_rad(aim_speed_degrees) * delta / _zoom # con zoom, la mira gira más lento

	_rotate_aim(dir.x * step, dir.y * step)


func _aim_direction() -> Vector3:
	return Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)
	).normalized()


## Posición de la cabeza (el ojo), en coordenadas de mundo.
func _head_position() -> Vector3:
	if is_instance_valid(_eye_anchor):
		return _eye_anchor.global_position
	return _player.global_position + Vector3.UP * (_player.get_body_height() * 0.5)


## Dónde tiene que estar la cámara cuando está anclada en la cabeza.
func _head_transform() -> Transform3D:
	var eye_pos: Vector3 = _head_position()
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
	_release_mouse()
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
	_release_mouse()
	_end_hit_stop() # nunca dejar el juego en cámara lenta
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
	_kick_camera()

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
	if _apply_hit(collider, direction):
		_on_hit_confirmed()
	shot_fired.emit(result.position, collider)


## Sube por el árbol hasta encontrar quien sepa recibir daño, igual que WeaponHitbox.
## Devuelve true si el disparo le dio a algo que reacciona (una pared no cuenta).
func _apply_hit(collider: Object, direction: Vector3) -> bool:
	var target: Node = collider as Node
	while target and not target.has_method("take_hit") and not target.has_method("take_damage"):
		target = target.get_parent()
	if target == null or target.is_in_group("player"):
		return false

	if target.has_method("take_hit"):
		target.take_hit(damage)

	if target.has_method("take_damage"):
		var flat: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
		var knockback: Vector3 = flat * knockback_strength + Vector3.UP * knockback_upward
		target.take_damage(damage, knockback)
	return true


# ---------------------------------------------------------------- ZOOM

## Zoom de la mira: gatillos (R2 acerca, L2 aleja; acciones image_zoom_in / image_zoom_out, también E / Q) o
## rueda del mouse. Cierra el campo visual (FOV): con zoom Z se ve 1/Z del ancho, de ahí la tangente.
func _update_zoom(delta: float) -> void:
	if not allow_zoom:
		return
	var zoom_input: float = Input.get_action_strength("image_zoom_in") - Input.get_action_strength("image_zoom_out")
	if zoom_input != 0.0:
		_zoom_target = clampf(_zoom_target * exp(zoom_input * zoom_rate * delta), 1.0, max_zoom)
		_hint_timer = HINT_USE_TIME
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-zoom_smooth * delta))
	if absf(_zoom - _zoom_target) < 0.001:
		_zoom = _zoom_target
	_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(field_of_view) * 0.5) / _zoom))


## Pistas de botones: a pleno al entrar y mientras se usa el zoom, tenues el resto del tiempo. La lectura del
## aumento ("x2.5") solo se ve con zoom.
func _update_zoom_hud(delta: float) -> void:
	if _hint_root == null:
		return
	_hint_timer = maxf(_hint_timer - delta, 0.0)
	var target: float = 1.0 if _hint_timer > 0.0 else HINT_IDLE_ALPHA
	_hint_alpha = move_toward(_hint_alpha, target, delta * HINT_FADE_SPEED)
	_hint_root.modulate.a = _hint_alpha

	var zoomed: bool = _zoom > 1.02
	_zoom_label.visible = zoomed
	if zoomed:
		var text: String = "x%.1f" % _zoom
		if text != _zoom_label_text:
			_zoom_label_text = text
			_zoom_label.text = text


# ---------------------------------------------------------------- GAME JUICE

## Temblor del disparo: un empujón de velocidad al resorte; _apply_shake lo mueve y lo devuelve a su sitio.
func _kick_camera() -> void:
	# Con zoom el mismo giro se ve más grande en pantalla: el temblor se atenúa (raíz del aumento)
	_shake.velocity += Vector3(
		shake_pitch_kick,
		randf_range(-1.0, 1.0) * shake_yaw_kick,
		randf_range(-1.0, 1.0) * shake_roll_kick) / sqrt(_zoom)


## Gira la cámara (ya colocada en la cabeza) según el desvío del resorte.
func _apply_shake(delta: float) -> void:
	_shake.step(Vector3.ZERO, shake_smooth_time, delta)
	if _shake.position.length_squared() > 0.0000001:
		_camera.global_basis = _camera.global_basis * Basis.from_euler(_shake.position)


func _on_hit_confirmed() -> void:
	_reticle_hit = 1.0
	_reticle.queue_redraw()
	_hit_stop()


## Casi congela el juego un instante. El temporizador ignora la escala de tiempo (si no, la cámara lenta se
## alargaría a sí misma). Va conectado, no con await, para que no falle si el nodo se libera a mitad.
func _hit_stop() -> void:
	if hit_stop_duration <= 0.0:
		return
	_hit_stop_token += 1
	_hit_stop_active = true
	Engine.time_scale = hit_stop_time_scale
	get_tree().create_timer(hit_stop_duration, true, false, true).timeout.connect(
			_on_hit_stop_timeout.bind(_hit_stop_token))


func _on_hit_stop_timeout(token: int) -> void:
	if token == _hit_stop_token: # si hubo otro impacto mientras tanto, él se encarga de terminar
		_end_hit_stop()


func _end_hit_stop() -> void:
	if _hit_stop_active:
		_hit_stop_active = false
		Engine.time_scale = 1.0


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
	_build_hints()


## Pista "(L2)(R2) zoom" abajo y lectura del aumento bajo la mirilla. Cuelgan de la capa de la mirilla: aparecen y
## desaparecen con ella, por debajo de las barras 4:3 y con el mismo estilo que las filas de los menús.
func _build_hints() -> void:
	if not allow_zoom:
		return
	_hint_root = Control.new()
	_hint_root.name = "Hints"
	_hint_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hint_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle_layer.add_child(_hint_root)

	var zoom_row: Label = ButtonPrompt.make_row("zoom", [ButtonPrompt.FRAME_L2, ButtonPrompt.FRAME_R2])
	zoom_row.name = "ZoomHint"
	zoom_row.offset_top = HINT_ROW_Y - 15.0
	zoom_row.offset_bottom = HINT_ROW_Y + 15.0
	_hint_root.add_child(zoom_row)

	_zoom_label = Label.new()
	_zoom_label.name = "ZoomReadout"
	_zoom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_label.set_anchors_preset(Control.PRESET_CENTER)
	_zoom_label.offset_left = -40.0
	_zoom_label.offset_right = 40.0
	_zoom_label.offset_top = ZOOM_LABEL_Y - 12.0
	_zoom_label.offset_bottom = ZOOM_LABEL_Y + 12.0
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_zoom_label.add_theme_font_size_override("font_size", 17)
	_zoom_label.add_theme_constant_override("outline_size", 8)
	_zoom_label.add_theme_color_override("font_color", MenuInfoPanel.HINT_COLOR)
	_zoom_label.visible = false
	_hint_root.add_child(_zoom_label)


func _show_reticle() -> void:
	if _reticle_tween and _reticle_tween.is_valid():
		_reticle_tween.kill()
	_reticle.modulate.a = 0.0
	_hint_timer = HINT_SHOW_TIME
	_hint_alpha = 0.0
	if _hint_root:
		_hint_root.modulate.a = 0.0
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
	var tick: float = reticle_tick_length * (1.0 + _reticle_hit * 0.6) # al acertar: más brillante y más gruesa
	var line_color: Color = reticle_color.lerp(reticle_hit_color, _reticle_hit)

	# Contorno oscuro primero (para que se lea sobre fondos claros), luego el trazo claro.
	for pass_index in 2:
		var color: Color = reticle_outline_color if pass_index == 0 else line_color
		var width: float = (3.0 if pass_index == 0 else 1.0) + _reticle_hit
		_reticle.draw_arc(center, radius, 0.0, TAU, 32, color, width, false)
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_reticle.draw_line(center + dir * (radius + gap), center + dir * (radius + gap + tick), color, width)

	_reticle.draw_circle(center, 1.5, reticle_outline_color)
	_reticle.draw_circle(center, 0.8, line_color)

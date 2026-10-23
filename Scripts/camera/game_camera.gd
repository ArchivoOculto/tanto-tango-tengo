extends Camera3D
class_name GameCamera

## Cámara del juego (cámaras semifijas por zonas).
## Se desplaza hacia el anchor de la CameraZone3D activa. Al salir de todas las zonas, retiene la posición
## del último anchor conocido.
##
## PENSADA PARA NO MAREAR:
##
##  - ZONA MUERTA: con la cámara ya asentada en su anchor, NO sigue cada paso del jugador. Mientras el
##    jugador esté cerca del centro de la imagen la cámara no gira; solo si se aleja más que la zona
##    muerta (un porcentaje de la mitad de la pantalla) la cámara gira lo justo para volver a enfocarlo,
##    con suavidad. Saltar o caminar en el lugar no mueve la cámara.
##  - NUNCA ATRAVIESA AL JUGADOR: la cámara respeta un radio alrededor del cuerpo del jugador. Si el viaje
##    al nuevo anchor pasaría por él, lo ORBITA (resbala por el costado), igual que al entrar al modo fusil.
##    También se aparta si el jugador camina hacia la cámara.
##  - VIAJE EN DOS RESORTES: el viaje entre anchors pasa por dos resortes amortiguados en cascada. Así la
##    aceleración también arranca en cero (sin tirón inicial: antes pasaba de 0 a ~3,5 m/s en 0,2 s) y el
##    final es igual de suave. No depende de los cuadros por segundo y hay una velocidad máxima de viaje.
##  - SIN COLISIONES CON EL DECORADO: la cámara ignora por completo paredes, alambrados y cualquier otra
##    geometría; prefiere clipearse adentro de algo antes que dar tirones. Lo único que respeta es el
##    cuerpo del jugador (ver arriba), que es una cuenta geométrica y no usa la física.
##  - SIN SALTOS DE MIRADA: no hay anticipación por velocidad (look-ahead) que mueva la cámara al arrancar
##    o frenar, y el foco nunca se "teletransporta" al cambiar de anchor.
##  - REENFOQUE AL CAMBIAR DE ANCHOR: al pasar a una zona con otro anchor, el foco pasa suavemente al torso del
##    jugador y se queda CLAVADO ahí (jugador exactamente en el centro) hasta que la cámara termina de llegar al
##    anchor nuevo; recién entonces vuelve la zona muerta. No se aplica a zonas con 'look_target' ni forzadas.
##  - JUGADOR SIEMPRE EN CUADRO: la zona muerta se mide en PANTALLA (a la profundidad real del jugador, no a la del
##    foco) y sobre el cuerpo real (cápsula de colisión: pies, torso y cabeza), descontando las barras 4:3. Además hay
##    un margen duro ('frame_margin'): si el cuerpo lo pasa, la cámara gira al instante. Se desactiva solo en
##    cinemáticas (zonas forzadas).
##  - ENEMIGOS: la cámara los ignora por completo, igual que al decorado: prefiere clipearse antes que moverse.

@export var default_smoothing: float = 3.0 ## Suavizado del viaje si no hay zona activa (con zona, manda su 'follow_smoothing')

@export_group("Zona muerta (seguimiento de la mirada)")
## Mitad del ancho de la zona muerta, como fracción de la mitad de la pantalla (0 = sigue siempre, 1 = nunca gira).
@export_range(0.0, 1.0, 0.01) var deadzone_horizontal: float = 0.25
## Mitad del alto de la zona muerta, como fracción de la mitad de la pantalla.
@export_range(0.0, 1.0, 0.01) var deadzone_vertical: float = 0.3
## Qué tan rápido gira la cámara para recuperar al jugador cuando sale de la zona muerta (1/s).
@export_range(0.5, 20.0, 0.1) var deadzone_follow_speed: float = 3.0
## Qué tan rápido gira hacia el 'look_target' de una zona (1/s).
@export_range(0.5, 20.0, 0.1) var look_target_speed: float = 4.0

@export_group("Encuadre garantizado")
## Fracción de la mitad de la pantalla VISIBLE dentro de la cual el cuerpo del jugador (pies, torso y cabeza) se ve
## SIEMPRE. Pasado ese margen la cámara gira al instante. Debe ser mayor que la zona muerta.
@export_range(0.5, 1.0, 0.01) var frame_margin: float = 0.85
## Cuánto se acelera el giro de la zona muerta a medida que el jugador se acerca al margen duro (0 = no se acelera).
@export_range(0.0, 20.0, 0.1) var edge_catch_up_boost: float = 5.0
## Si es true, las zonas con 'look_target' también garantizan al jugador en cuadro (la cámara mira lo más cerca
## posible del objetivo sin perderlo). Las zonas forzadas (cinemáticas) nunca lo garantizan.
@export var keep_player_framed_on_look_target: bool = true

@export_group("Reenfoque al cambiar de anchor")
## Al cambiar de anchor, centra al jugador en pantalla hasta que la cámara llega; después vuelve la zona muerta.
@export var recenter_on_anchor_change: bool = true
## Cuánto tarda el foco en pasar de donde estaba al centro del jugador (s). El paso es suave: arranca y termina sin brusquedad.
@export_range(0.1, 3.0, 0.05, "suffix:s") var recenter_blend_time: float = 0.7
## Tope de duración del reenfoque (s), por si la cámara nunca llegara a asentarse en el anchor.
@export_range(1.0, 20.0, 0.5, "suffix:s") var recenter_max_duration: float = 6.0

@export_group("Viaje entre anchors")
## Velocidad máxima de la cámara al viajar (m/s). 0 = sin límite.
@export_range(0.0, 50.0, 0.1, "suffix:m/s") var max_travel_speed: float = 6.0
## El viaje usa dos resortes en cascada y cada uno toma este porcentaje del tiempo de la zona ('follow_smoothing').
## Más chico = arranque más seco y viaje más corto; más grande = arranque más suave y viaje más largo.
@export_range(0.2, 1.0, 0.05) var travel_stage_scale: float = 0.6
## Radio alrededor del cuerpo del jugador que la cámara no invade (fracción de su altura).
@export_range(0.0, 2.0, 0.05) var player_clearance_ratio: float = 0.6
## Radio mínimo, aunque el anchor esté pegado al jugador o este camine hacia la cámara (fracción de su altura).
@export_range(0.0, 1.0, 0.05) var player_min_clearance_ratio: float = 0.2

@export_group("Proporciones (fracción de la altura del personaje)")
@export var look_height_ratio: float = 0.55

@onready var player: Node3D = get_tree().get_first_node_in_group("player")

const MAX_FRAME_DELTA: float = 0.1 ## tope al delta: un tirón de rendimiento no debe hacer saltar la cámara
const LETTERBOX_ASPECT: float = 4.0 / 3.0 ## mismo valor que LetterboxController.TARGET_ASPECT
const NEAR_DEPTH: float = 0.05 ## por debajo de esta profundidad un punto se considera "pegado/detrás" de la cámara
const MIN_FOCUS_DISTANCE: float = 0.1
const FRAME_GUARD_ITERATIONS: int = 4
const ANCHOR_SAME_DISTANCE: float = 0.05 ## dos anchors más cerca que esto cuentan como el mismo (no hay reenfoque)
const RECENTER_ARRIVE_DISTANCE: float = 0.05 ## a esta distancia del anchor la cámara se considera "llegada"
const RECENTER_ARRIVE_SPEED: float = 0.02 ## ...o si va más lento que esto (m/s), aunque algo la mantenga apartada

var _player_height: float = 1.8
var _focus: Vector3 = Vector3.ZERO ## punto al que apunta la cámara (suavizado)
var _lead: Spring = Spring.new() ## 1.er resorte: va hacia el anchor (con velocidad máxima)
var _follow: Spring = Spring.new() ## 2.º resorte: la cámara va hacia el 1.º (de acá sale la posición real)
var _last_known_anchor_pos: Vector3 = Vector3.ZERO

var _tracked_zone_id: int = 0 ## zona del cuadro anterior (para detectar el cambio de anchor)
var _recentering: bool = false
var _recenter_time: float = 0.0
var _recenter_start_focus: Vector3 = Vector3.ZERO

var _player_shape: CollisionShape3D ## cápsula de colisión del jugador (define dónde están sus pies y su cabeza)
var _player_body: BodyCapsule = BodyCapsule.new() ## cápsula del jugador, recalculada en cada cuadro


## Resorte críticamente amortiguado (arranca y frena suave, sin rebotar ni depender del framerate).
class Spring:
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO

	func reset(at: Vector3) -> void:
		position = at
		velocity = Vector3.ZERO

	## Avanza un paso hacia 'target'. 'max_speed' > 0 limita cuánto puede "adelantarse" al destino.
	func step(target: Vector3, smooth_time: float, delta: float, max_speed: float = 0.0) -> void:
		smooth_time = maxf(smooth_time, 0.0001)
		var omega: float = 2.0 / smooth_time
		var x: float = omega * delta
		var decay: float = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)

		var change: Vector3 = position - target
		if max_speed > 0.0:
			change = change.limit_length(max_speed * smooth_time)
		var limited_target: Vector3 = position - change

		var temp: Vector3 = (velocity + omega * change) * delta
		velocity = (velocity - omega * temp) * decay
		var output: Vector3 = limited_target + (change + temp) * decay

		# Sin sobrepasar el destino
		if (target - position).dot(output - target) > 0.0:
			output = target
			velocity = Vector3.ZERO
		position = output


## Extremos de una cápsula de colisión en el mundo. 'feet' y 'head' son los puntos más bajo y más alto.
class BodyCapsule:
	var feet: Vector3 = Vector3.ZERO
	var head: Vector3 = Vector3.ZERO
	var radius: float = 0.0



func _ready() -> void:
	current = true
	add_to_group("game_camera") # permite que WarpManager la encuentre para hacer snap_to_zone()

	if player:
		if player.has_method("get_body_height"):
			_player_height = player.get_body_height()
		_player_shape = player.get_node_or_null("CollisionShape3D") as CollisionShape3D
		_refresh_player_body()

	_lead.reset(global_position)
	_follow.reset(global_position)
	_last_known_anchor_pos = global_position
	if player:
		_focus = _player_focus_point()


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	delta = minf(delta, MAX_FRAME_DELTA)
	_refresh_player_body()

	var zone: CameraZone3D = CameraDirector.current_zone

	# El orden importa: primero se decide DÓNDE está la cámara y recién después A DÓNDE mira. Así la zona muerta
	# y el encuadre se miden con la posición final de este cuadro (antes se medía con la del cuadro anterior).

	# Cambio de zona: se detecta ANTES de actualizar el último anchor conocido, para comparar contra el anterior
	var zone_id: int = zone.get_instance_id() if zone != null else 0
	if zone_id != _tracked_zone_id:
		_tracked_zone_id = zone_id
		_on_zone_changed(zone)

	# --- 1. POSICIÓN (dos resortes en cascada hacia el anchor) ---
	var target_position: Vector3
	var smoothing: float = default_smoothing
	if zone and is_instance_valid(zone.camera_anchor):
		target_position = zone.camera_anchor.global_position
		smoothing = zone.follow_smoothing
		_last_known_anchor_pos = target_position
	else:
		target_position = _last_known_anchor_pos

	var stage_time: float = 0.75 / maxf(smoothing, 0.1) * travel_stage_scale
	_lead.step(target_position, stage_time, delta, max_travel_speed)
	_follow.step(_lead.position, stage_time, delta)

	# --- 2. NO ATRAVESAR AL JUGADOR (lo orbita) ---
	_follow.position = _keep_out_of_player(_follow.position, target_position, delta)

	# --- 3. APLICAR POSICIÓN (sin colisiones con el decorado ni los enemigos: se clipea antes que dar tirones) ---
	global_position = _follow.position

	# --- 4. FOCO (a dónde apunta la cámara) ---
	var has_look_target: bool = zone != null and is_instance_valid(zone.look_target)
	if has_look_target:
		# Zona con objetivo fijo: gira suavemente hacia él
		var rate: float = 1.0 - exp(-look_target_speed * delta)
		_focus = _focus.lerp(zone.look_target.global_position, rate)
	elif _recentering:
		_update_recenter(delta, target_position)
	else:
		_follow_player_with_deadzone(delta)

	# --- 5. ENCUADRE GARANTIZADO (el jugador nunca queda fuera de cuadro) ---
	if _should_guard_frame(has_look_target):
		_keep_player_in_frame()

	# --- 6. ORIENTACIÓN ---
	_look_at_focus()


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
	_lead.reset(target_position)
	_follow.reset(target_position)
	global_position = target_position
	_tracked_zone_id = zone.get_instance_id()
	_recentering = false # el warp ya deja al jugador en el centro: no hace falta reenfocar

	var has_look_target: bool = is_instance_valid(zone.look_target)
	if player:
		_refresh_player_body()
		_focus = zone.look_target.global_position if has_look_target else _player_focus_point()
		if _should_guard_frame(has_look_target):
			_keep_player_in_frame()
	_look_at_focus()


# ---------------------------------------------------------------- JUGADOR / ENEMIGOS (cápsulas)

## Extremos de la cápsula de colisión de 'shape_node' en el mundo (null si no es una cápsula).
## OJO: el origen de un CharacterBody3D NO es necesariamente sus pies. En este proyecto la cápsula del
## jugador está centrada en el origen, así que los pies y la cabeza se sacan de la cápsula, no del origen.
func _capsule_of(shape_node: CollisionShape3D) -> BodyCapsule:
	var capsule_shape: CapsuleShape3D = shape_node.shape as CapsuleShape3D
	if capsule_shape == null:
		return null
	var xf: Transform3D = shape_node.global_transform
	var axis: Vector3 = xf.basis.y.normalized()
	var half_height: float = capsule_shape.height * 0.5 * xf.basis.y.length()

	var result: BodyCapsule = BodyCapsule.new()
	result.feet = xf.origin - axis * half_height
	result.head = xf.origin + axis * half_height
	result.radius = capsule_shape.radius * maxf(xf.basis.x.length(), xf.basis.z.length())
	return result


## Recalcula dónde están los pies y la cabeza del jugador en este cuadro.
func _refresh_player_body() -> void:
	if is_instance_valid(_player_shape):
		var capsule: BodyCapsule = _capsule_of(_player_shape)
		if capsule != null:
			_player_body = capsule
			_player_height = capsule.feet.distance_to(capsule.head)
			return
	# Sin cápsula: se asume que el origen del jugador está en los pies
	var fallback: BodyCapsule = BodyCapsule.new()
	fallback.feet = player.global_position
	fallback.head = fallback.feet + Vector3.UP * _player_height
	_player_body = fallback


# ---------------------------------------------------------------- PANTALLA

## Tangentes de la mitad del campo de visión: x = horizontal, y = vertical (respeta 'keep_aspect').
func _half_fov_tangents() -> Vector2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	var t: float = tan(deg_to_rad(fov) * 0.5)
	if keep_aspect == Camera3D.KEEP_HEIGHT:
		return Vector2(t * aspect, t)
	return Vector2(t, t / aspect)


## Mitad de la imagen que REALMENTE se ve, en coordenadas de pantalla (1 = borde de la pantalla completa).
## Con las barras 4:3 puestas, parte de la imagen queda tapada y no cuenta como "en cuadro".
func _visible_half_extents() -> Vector2:
	var extents: Vector2 = Vector2.ONE
	if CameraDirector.is_letterbox_active():
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
		if aspect > LETTERBOX_ASPECT:
			extents.x = LETTERBOX_ASPECT / aspect
		else:
			extents.y = aspect / LETTERBOX_ASPECT
	return extents


## Dónde cae 'point' en la pantalla si la cámara tuviera la transformación 'view'.
## x, y: -1..1 sobre la pantalla completa (0 = centro). z: profundidad delante de la cámara (<= 0: detrás).
func _to_screen(point: Vector3, view: Transform3D, tangents: Vector2) -> Vector3:
	var local: Vector3 = view.affine_inverse() * point
	var depth: float = -local.z
	var safe_depth: float = maxf(depth, NEAR_DEPTH)
	return Vector3(local.x / (safe_depth * tangents.x), local.y / (safe_depth * tangents.y), depth)


## Transformación que tendrá la cámara al mirar a '_focus' desde su posición actual.
func _view_transform() -> Transform3D:
	var direction: Vector3 = _focus - global_position
	if direction.length() <= 0.01:
		return global_transform
	return Transform3D(Basis.looking_at(direction.normalized(), _pick_up(direction)), global_position)


## Casi vertical: UP no sirve de referencia (la cámara daría un giro brusco).
func _pick_up(direction: Vector3) -> Vector3:
	if absf(direction.normalized().dot(Vector3.UP)) > 0.98:
		return global_transform.basis.y
	return Vector3.UP


## Desplaza el foco en el plano de la imagen. 'screen_shift' va en unidades de pantalla (como _to_screen),
## así que mueve al jugador esa cantidad en pantalla sin importar a qué profundidad esté.
func _shift_focus(view: Transform3D, screen_shift: Vector2, tangents: Vector2) -> void:
	var distance: float = maxf(_focus.distance_to(global_position), MIN_FOCUS_DISTANCE)
	_focus += view.basis.x * (screen_shift.x * distance * tangents.x)
	_focus += view.basis.y * (screen_shift.y * distance * tangents.y)


# ---------------------------------------------------------------- REENFOQUE

## Se llama una vez al pasar a otra zona (o a ninguna).
func _on_zone_changed(zone: CameraZone3D) -> void:
	if zone == null:
		return # sin zona la cámara sigue yendo al último anchor: si había un reenfoque en curso, continúa
	if is_instance_valid(zone.look_target):
		_recentering = false # esta zona mira a un objetivo, no al jugador
		return
	if not recenter_on_anchor_change or CameraDirector.has_forced_zone():
		return # las cinemáticas (zonas forzadas) deciden su propio encuadre
	if not is_instance_valid(zone.camera_anchor):
		return
	if zone.camera_anchor.global_position.distance_to(_last_known_anchor_pos) < ANCHOR_SAME_DISTANCE:
		return # mismo anchor: la cámara no se mueve, no hay nada que reenfocar
	_recentering = true
	_recenter_time = 0.0
	_recenter_start_focus = _focus # si ya había uno en curso, el nuevo parte desde donde está mirando ahora


## Mientras dura el reenfoque el foco ES el torso del jugador (centrado exacto): primero se acerca con una curva
## suave (sin saltos de giro) y después lo sigue pegado hasta que la cámara llega al anchor. Al terminar el foco ya
## está en el jugador, así que la zona muerta retoma desde el centro sin ningún salto.
func _update_recenter(delta: float, anchor_position: Vector3) -> void:
	_recenter_time += delta
	var t: float = clampf(_recenter_time / maxf(recenter_blend_time, 0.01), 0.0, 1.0)
	var weight: float = t * t * (3.0 - 2.0 * t) # smoothstep: velocidad de giro cero al arrancar y al llegar
	_focus = _recenter_start_focus.lerp(_player_focus_point(), weight)

	if t < 1.0:
		return
	# El jugador ya está centrado: se termina cuando la cámara llegó (o se agotó el tope)
	var lead_arrived: bool = _lead.position.distance_to(anchor_position) < RECENTER_ARRIVE_DISTANCE
	var follow_arrived: bool = _follow.position.distance_to(_lead.position) < RECENTER_ARRIVE_DISTANCE \
		or _follow.velocity.length() < RECENTER_ARRIVE_SPEED
	if (lead_arrived and follow_arrived) or _recenter_time >= recenter_max_duration:
		_recentering = false


# ---------------------------------------------------------------- FOCO

## Punto del jugador al que se apunta (a la altura del torso, entre sus pies y su cabeza).
func _player_focus_point() -> Vector3:
	return _player_body.feet.lerp(_player_body.head, look_height_ratio)


## El foco se queda quieto mientras el jugador esté dentro de la zona muerta (rectángulo centrado en la
## imagen visible); al salir, el foco se desplaza justo lo necesario para recuperarlo. Todo se mide en
## PANTALLA, a la profundidad real del jugador: con el anchor pegado a él, un paso pequeño es enorme en
## pantalla y eso se tiene en cuenta (antes se medía en el plano del foco y el jugador podía salirse de cuadro).
func _follow_player_with_deadzone(delta: float) -> void:
	var view: Transform3D = _view_transform()
	var tangents: Vector2 = _half_fov_tangents()
	var visible_extents: Vector2 = _visible_half_extents()

	var s: Vector3 = _to_screen(_player_focus_point(), view, tangents)
	if s.z <= NEAR_DEPTH:
		return # pegado o detrás de la cámara: lo resuelve _keep_player_in_frame()

	var limit: Vector2 = Vector2(deadzone_horizontal, deadzone_vertical) * visible_extents
	var excess: Vector2 = Vector2(
		s.x - clampf(s.x, -limit.x, limit.x),
		s.y - clampf(s.y, -limit.y, limit.y))
	if excess == Vector2.ZERO:
		return # dentro de la zona muerta: la cámara no se mueve

	# Cuanto más cerca del margen duro, más rápido gira (evita llegar al borde con el giro todavía lento)
	var hard_limit: Vector2 = Vector2(frame_margin, frame_margin) * visible_extents
	var edge: float = clampf(maxf(absf(s.x) / hard_limit.x, absf(s.y) / hard_limit.y), 0.0, 1.0)
	var speed: float = deadzone_follow_speed * (1.0 + edge_catch_up_boost * edge * edge * edge)
	var catch_up: float = 1.0 - exp(-speed * delta)
	_shift_focus(view, excess * catch_up, tangents)


## ¿Corresponde garantizar al jugador en cuadro? Nunca en cinemáticas (zonas forzadas), donde el
## jugador puede quedar fuera de cuadro a propósito.
func _should_guard_frame(has_look_target: bool) -> bool:
	if CameraDirector.has_forced_zone():
		return false
	if has_look_target and not keep_player_framed_on_look_target:
		return false
	return true


## Red de seguridad: si pies, torso o cabeza del jugador pasan el margen duro, gira el foco AL INSTANTE
## lo justo para devolverlos. Va después de la zona muerta y del 'look_target', así que gana siempre.
func _keep_player_in_frame() -> void:
	var tangents: Vector2 = _half_fov_tangents()
	var limit: Vector2 = Vector2(frame_margin, frame_margin) * _visible_half_extents()
	var points: Array[Vector3] = [_player_body.feet, _player_focus_point(), _player_body.head]

	# La corrección en el plano del foco es una aproximación: se repite unas pocas veces hasta que converge.
	for _i in FRAME_GUARD_ITERATIONS:
		var view: Transform3D = _view_transform()
		var worst_positive: Vector2 = Vector2.ZERO
		var worst_negative: Vector2 = Vector2.ZERO
		var lost: bool = false

		for point in points:
			var s: Vector3 = _to_screen(point, view, tangents)
			if s.z <= NEAR_DEPTH:
				lost = true
				break
			var excess: Vector2 = Vector2(
				s.x - clampf(s.x, -limit.x, limit.x),
				s.y - clampf(s.y, -limit.y, limit.y))
			worst_positive = Vector2(maxf(worst_positive.x, excess.x), maxf(worst_positive.y, excess.y))
			worst_negative = Vector2(minf(worst_negative.x, excess.x), minf(worst_negative.y, excess.y))

		if lost:
			# El jugador quedó pegado o detrás de la cámara: apuntar directo a él
			_focus = _player_focus_point()
			continue

		# Si se pasan por lados opuestos (cuerpo más grande que el cuadro) se suman y el cuerpo queda centrado
		var shift: Vector2 = worst_positive + worst_negative
		if shift.length_squared() < 0.000001:
			break
		_shift_focus(view, shift, tangents)


func _look_at_focus() -> void:
	var direction: Vector3 = _focus - global_position
	if direction.length() <= 0.01:
		return
	look_at(_focus, _pick_up(direction))


# ---------------------------------------------------------------- MOVIMIENTO

# ---------------------------------------------------------------- NO ATRAVESAR

## Distancia mínima a la que el cuerpo del jugador entra entero en el cuadro (con el margen duro).
func _framing_distance() -> float:
	var half_body: float = _player_body.feet.distance_to(_player_body.head) * 0.5
	var tangents: Vector2 = _half_fov_tangents()
	var visible_extents: Vector2 = _visible_half_extents()
	return half_body / maxf(frame_margin * tangents.y * visible_extents.y, 0.01)


## Mantiene a la cámara fuera de una "cápsula de respeto" alrededor del jugador. Si el camino al anchor
## pasa por el cuerpo, la saca hacia afuera y la hace resbalar por el costado: lo orbita.
func _keep_out_of_player(pos: Vector3, anchor: Vector3, delta: float) -> Vector3:
	var feet: Vector3 = _player_body.feet
	var head: Vector3 = _player_body.head
	var radius: float = _player_height * player_clearance_ratio

	# Si el anchor mismo está cerca del cuerpo, se le exige menos, pero nunca menos que el radio mínimo.
	# El radio mínimo también garantiza que el cuerpo entero entre en el cuadro (un jugador chico y una
	# cámara pegada a él no caben en pantalla, por mucho que se gire).
	var anchor_gap: float = anchor.distance_to(Geometry3D.get_closest_point_to_segment(anchor, feet, head))
	var min_radius: float = maxf(_player_height * player_min_clearance_ratio, _framing_distance())
	radius = clampf(anchor_gap * 0.85, min_radius, maxf(radius, min_radius))
	if radius <= 0.001:
		return pos

	return _push_out_of_capsule(pos, anchor, delta, feet, head, radius)


## Si 'pos' cae dentro del segmento a-b engrosado en 'radius', lo saca hacia afuera y lo hace resbalar
## hacia el anchor por el costado (orbita el cuerpo en vez de quedarse pegado).
func _push_out_of_capsule(pos: Vector3, anchor: Vector3, delta: float, seg_a: Vector3, seg_b: Vector3, radius: float) -> Vector3:
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(pos, seg_a, seg_b)
	var offset: Vector3 = pos - closest
	var distance: float = offset.length()
	if distance >= radius:
		return pos

	var outward: Vector3 = offset / distance if distance > 0.0001 else (anchor - closest).normalized()
	if outward.length_squared() < 0.5:
		outward = Vector3.BACK # cámara y anchor justo sobre el eje del cuerpo: cualquier salida sirve
	var pushed: Vector3 = closest + outward * radius

	# Resbalar hacia el anchor por el costado; si está justo detrás del cuerpo, elegir un costado
	var to_anchor: Vector3 = anchor - pushed
	var tangent: Vector3 = to_anchor - outward * to_anchor.dot(outward)
	if tangent.length() < radius * 0.3:
		tangent = outward.cross(Vector3.UP)
		if tangent.length() < 0.001:
			tangent = outward.cross(Vector3.RIGHT)
		pushed += tangent.normalized() * radius * 1.5 * delta
	else:
		pushed += tangent.normalized() * radius * 0.5 * delta

	# Sin velocidad hacia adentro del cuerpo
	var inward_speed: float = _follow.velocity.dot(-outward)
	if inward_speed > 0.0:
		_follow.velocity += outward * inward_speed
	return pushed

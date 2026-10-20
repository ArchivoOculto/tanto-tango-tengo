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
##  - RESORTE AMORTIGUADO: el viaje entre anchors arranca y frena con suavidad (sin tirón inicial) y no
##    depende de los cuadros por segundo. Hay una velocidad máxima de viaje.
##  - SIN COLISIONES CON EL DECORADO: la cámara ignora por completo paredes, alambrados y cualquier otra
##    geometría; prefiere clipearse adentro de algo antes que dar tirones. Lo único que respeta es el
##    cuerpo del jugador (ver arriba), que es una cuenta geométrica y no usa la física.
##  - SIN SALTOS DE MIRADA: no hay anticipación por velocidad (look-ahead) que mueva la cámara al arrancar
##    o frenar, y el foco nunca se "teletransporta" al cambiar de anchor.

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

@export_group("Viaje entre anchors")
## Velocidad máxima de la cámara al viajar (m/s). 0 = sin límite.
@export_range(0.0, 50.0, 0.1, "suffix:m/s") var max_travel_speed: float = 6.0
## Radio alrededor del cuerpo del jugador que la cámara no invade (fracción de su altura).
@export_range(0.0, 2.0, 0.05) var player_clearance_ratio: float = 0.6
## Radio mínimo, aunque el anchor esté pegado al jugador o este camine hacia la cámara (fracción de su altura).
@export_range(0.0, 1.0, 0.05) var player_min_clearance_ratio: float = 0.2

@export_group("Proporciones (fracción de la altura del personaje)")
@export var look_height_ratio: float = 0.55

@onready var player: Node3D = get_tree().get_first_node_in_group("player")

const MAX_FRAME_DELTA: float = 0.1 ## tope al delta: un tirón de rendimiento no debe hacer saltar la cámara

var _player_height: float = 1.8
var _focus: Vector3 = Vector3.ZERO ## punto al que apunta la cámara (suavizado)
var _position: Vector3 = Vector3.ZERO ## posición suavizada del resorte
var _velocity: Vector3 = Vector3.ZERO ## velocidad del resorte
var _last_known_anchor_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	current = true
	add_to_group("game_camera") # permite que WarpManager la encuentre para hacer snap_to_zone()

	if player and player.has_method("get_body_height"):
		_player_height = player.get_body_height()

	_position = global_position
	_last_known_anchor_pos = global_position
	if player:
		_focus = _player_focus_point()


func _process(delta: float) -> void:
	if player == null:
		return
	delta = minf(delta, MAX_FRAME_DELTA)

	var zone: CameraZone3D = CameraDirector.current_zone

	# --- 1. FOCO (a dónde apunta la cámara) ---
	if zone and is_instance_valid(zone.look_target):
		# Zona con objetivo fijo: gira suavemente hacia él
		var rate: float = 1.0 - exp(-look_target_speed * delta)
		_focus = _focus.lerp(zone.look_target.global_position, rate)
	else:
		_follow_player_with_deadzone(delta)

	# --- 2. POSICIÓN (resorte amortiguado hacia el anchor) ---
	var target_position: Vector3
	var smoothing: float = default_smoothing
	if zone and is_instance_valid(zone.camera_anchor):
		target_position = zone.camera_anchor.global_position
		smoothing = zone.follow_smoothing
		_last_known_anchor_pos = target_position
	else:
		target_position = _last_known_anchor_pos

	_position = _smooth_damp(_position, target_position, 0.75 / maxf(smoothing, 0.1), delta)

	# --- 3. NO ATRAVESAR AL JUGADOR (lo orbita) ---
	_position = _keep_out_of_player(_position, target_position, delta)

	# --- 4. APLICAR POSICIÓN (sin colisiones con el decorado: se clipea antes que dar tirones) ---
	global_position = _position

	# --- 5. ORIENTACIÓN ---
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
	_position = target_position
	_velocity = Vector3.ZERO
	global_position = target_position

	if player:
		_focus = zone.look_target.global_position if is_instance_valid(zone.look_target) else _player_focus_point()
	_look_at_focus()


# ---------------------------------------------------------------- FOCO

## Punto del jugador al que se apunta (a la altura del torso).
func _player_focus_point() -> Vector3:
	return player.global_position + Vector3.UP * (_player_height * look_height_ratio)


## El foco se queda quieto mientras el jugador esté dentro de la zona muerta (rectángulo centrado en la
## imagen, medido en la pantalla); al salir, el foco se desplaza justo lo necesario para recuperarlo.
func _follow_player_with_deadzone(delta: float) -> void:
	var cam_basis: Basis = global_transform.basis
	var to_player: Vector3 = _player_focus_point() - _focus

	# Tamaño visible a la distancia del foco (fov vertical)
	var distance: float = maxf(_focus.distance_to(global_position), 0.1)
	var half_height: float = distance * tan(deg_to_rad(fov) * 0.5)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var half_width: float = half_height * (viewport_size.x / maxf(viewport_size.y, 1.0))

	var limit_x: float = half_width * deadzone_horizontal
	var limit_y: float = half_height * deadzone_vertical
	var lateral: float = to_player.dot(cam_basis.x)
	var vertical: float = to_player.dot(cam_basis.y)
	var excess_x: float = lateral - clampf(lateral, -limit_x, limit_x)
	var excess_y: float = vertical - clampf(vertical, -limit_y, limit_y)
	if excess_x == 0.0 and excess_y == 0.0:
		return # dentro de la zona muerta: la cámara no se mueve

	var catch_up: float = 1.0 - exp(-deadzone_follow_speed * delta)
	_focus += (cam_basis.x * excess_x + cam_basis.y * excess_y) * catch_up


func _look_at_focus() -> void:
	var direction: Vector3 = _focus - global_position
	if direction.length() <= 0.01:
		return
	# Casi vertical: UP no sirve de referencia (la cámara daría un giro brusco)
	var up: Vector3 = Vector3.UP
	if absf(direction.normalized().dot(Vector3.UP)) > 0.98:
		up = global_transform.basis.y
	look_at(_focus, up)


# ---------------------------------------------------------------- MOVIMIENTO

## Resorte críticamente amortiguado (arranca y frena suave, sin rebotar ni depender del framerate).
func _smooth_damp(current: Vector3, target: Vector3, smooth_time: float, delta: float) -> Vector3:
	smooth_time = maxf(smooth_time, 0.0001)
	var omega: float = 2.0 / smooth_time
	var x: float = omega * delta
	var decay: float = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)

	var change: Vector3 = current - target
	if max_travel_speed > 0.0:
		change = change.limit_length(max_travel_speed * smooth_time)
	var limited_target: Vector3 = current - change

	var temp: Vector3 = (_velocity + omega * change) * delta
	_velocity = (_velocity - omega * temp) * decay
	var output: Vector3 = limited_target + (change + temp) * decay

	# Sin sobrepasar el destino
	if (target - current).dot(output - target) > 0.0:
		output = target
		_velocity = Vector3.ZERO
	return output


## Mantiene a la cámara fuera de una "cápsula de respeto" alrededor del jugador. Si el camino al anchor
## pasa por el cuerpo, la saca hacia afuera y la hace resbalar por el costado: lo orbita.
func _keep_out_of_player(pos: Vector3, anchor: Vector3, delta: float) -> Vector3:
	var feet: Vector3 = player.global_position
	var head: Vector3 = feet + Vector3.UP * _player_height
	var radius: float = _player_height * player_clearance_ratio

	# Si el anchor mismo está cerca del cuerpo, se le exige menos, pero nunca menos que el radio mínimo
	var anchor_gap: float = anchor.distance_to(Geometry3D.get_closest_point_to_segment(anchor, feet, head))
	var min_radius: float = minf(_player_height * player_min_clearance_ratio, radius)
	radius = clampf(anchor_gap * 0.85, min_radius, radius)
	if radius <= 0.001:
		return pos

	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(pos, feet, head)
	var offset: Vector3 = pos - closest
	var distance: float = offset.length()
	if distance >= radius:
		return pos

	var outward: Vector3 = offset / distance if distance > 0.0001 else (anchor - closest).normalized()
	var pushed: Vector3 = closest + outward * radius

	# Resbalar hacia el anchor por el costado; si está justo detrás del jugador, elegir un costado
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
	var inward_speed: float = _velocity.dot(-outward)
	if inward_speed > 0.0:
		_velocity += outward * inward_speed
	return pushed

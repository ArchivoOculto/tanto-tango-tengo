extends Node
class_name Level00Manager

## Director del nivel 0. Va como hijo de la raíz de terrain.tscn.
##
## INICIO / REINICIO (cada vez que se carga el nivel):
##   1. Pantalla en negro (se oye la lluvia, que ya suena sola desde la escena).
##   2. Pasan 'intro_black_duration' segundos con el jugador SIN controles.
##   3. Empieza el fade in: en ese instante el jugador recupera los controles.
##
## FINAL:
##   La primera vez que el jugador abre la imagen 'end_picture' suena 'end_theme' de forma
##   GLOBAL (AudioStreamPlayer normal, no posicional). Cuando termina la canción, toda la
##   pantalla se funde a negro y el juego se reinicia por completo.
##
## El fundido usa el de WarpManager (capa 128, por encima de las barras 4:3 y de toda la UI),
## así el negro es continuo entre el final y el nuevo arranque.

## Empieza el fade in del arranque (el jugador ya tiene los controles).
signal intro_fade_started
## El tema final empezó a sonar.
signal end_theme_started
## La pantalla ya está en negro y justo se va a reiniciar el juego.
signal restart_requested

@export_group("Inicio / Reinicio")
## Desactivar para probar el nivel en el editor sin esperar la intro.
@export var play_intro: bool = true
## Segundos con la pantalla en negro (solo lluvia) antes de que empiece el fade in.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var intro_black_duration: float = 3.0
## Duración del fade in que revela la pantalla.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var intro_fade_in_duration: float = 4.0

@export_group("Final")
## La InteractablePicture de 'EndPicture': al abrirla por primera vez suena el tema final.
@export var end_picture: InteractablePicture
@export var end_theme: AudioStream = preload("res://Assets/Audio/garua_endtheme.mp3")
@export var end_theme_bus: StringName = &"Master"
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var end_theme_volume_db: float = 0.0
## Duración del fade out a negro cuando termina la canción.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var end_fade_out_duration: float = 2.5
## Escena a cargar al reiniciar. Vacío = recarga este mismo nivel (arranca con la intro).
## Para volver a la pantalla de título, asignar TitleScreen.tscn.
@export var restart_scene: PackedScene

var _player: Player
var _end_player: AudioStreamPlayer
var _prev_player_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _end_started: bool = false
var _ending: bool = false


func _ready() -> void:
	# Estado limpio de los autoloads (sobreviven a las recargas de escena)
	CameraDirector.reset()

	_player = get_tree().get_first_node_in_group("player") as Player
	_connect_end_picture()

	if play_intro:
		_run_intro()
	else:
		WarpManager.fade_in(0.0) # por si quedó negro de un reinicio anterior


# ---------------------------------------------------------------- INICIO

func _run_intro() -> void:
	WarpManager.fade_out(0.0) # negro inmediato, antes del primer frame
	_set_player_locked(true)

	# El primer frame después de cargar el nivel arrastra todo el tiempo de carga como si
	# fuera "tiempo transcurrido". Esperamos un par de frames antes de empezar a contar para
	# que el negro dure exactamente lo configurado, sin importar qué tan lenta sea la carga.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return

	# Se cuenta con el reloj real (no con deltas de frame): el motor suaviza los deltas y,
	# justo después de una carga pesada, pueden desviarse del tiempo que el jugador percibe.
	var hold_start_ms: int = Time.get_ticks_msec()
	var hold_ms: int = int(intro_black_duration * 1000.0)
	while Time.get_ticks_msec() - hold_start_ms < hold_ms:
		await get_tree().process_frame
		if not is_inside_tree():
			return

	# El jugador recupera los controles justo cuando empieza a revelarse la pantalla
	_set_player_locked(false)
	intro_fade_started.emit()
	await WarpManager.fade_in(intro_fade_in_duration)


# ---------------------------------------------------------------- FINAL

func _connect_end_picture() -> void:
	if end_picture == null:
		push_warning("Level00Manager: 'end_picture' no está asignada; no sonará el tema final.")
		return
	end_picture.opened.connect(_on_end_picture_opened, CONNECT_ONE_SHOT)


func _on_end_picture_opened() -> void:
	if _end_started:
		return
	_end_started = true

	var stream: AudioStream = end_theme
	if stream == null:
		push_warning("Level00Manager: 'end_theme' vacío.")
		return
	# Si el import lo dejó en bucle, 'finished' nunca saltaría y el juego no terminaría.
	if "loop" in stream and stream.loop:
		stream = stream.duplicate()
		stream.loop = false

	# AudioStreamPlayer (no 3D): suena igual en todo el nivel, sin posición ni atenuación.
	_end_player = AudioStreamPlayer.new()
	_end_player.name = "EndThemePlayer"
	_end_player.stream = stream
	_end_player.bus = end_theme_bus
	_end_player.volume_db = end_theme_volume_db
	_end_player.finished.connect(_on_end_theme_finished)
	add_child(_end_player)
	_end_player.play()
	end_theme_started.emit()

	# Red de seguridad: si por algún motivo 'finished' no llegara (ej. sin dispositivo de
	# audio), igual cerramos el juego en vez de quedar trabados en la pantalla final.
	get_tree().create_timer(stream.get_length() + 1.0).timeout.connect(_on_end_theme_finished)


func _on_end_theme_finished() -> void:
	if _ending:
		return
	_ending = true

	_set_player_locked(true)
	await WarpManager.fade_out(end_fade_out_duration)
	if not is_inside_tree():
		return
	_restart_game()


func _restart_game() -> void:
	restart_requested.emit()
	CameraDirector.reset() # zonas/forzados/modo fusil/barras 4:3 fuera antes de recargar
	if restart_scene:
		get_tree().change_scene_to_packed(restart_scene)
	else:
		get_tree().reload_current_scene()


# ---------------------------------------------------------------- JUGADOR

## Bloqueo total del jugador. PROCESS_MODE_DISABLED corta _process, _physics_process y las
## entradas de él y de todos sus hijos (movimiento, combate, modo fusil, animaciones), y a
## diferencia de set_physics_process() ningún otro sistema puede reactivarlo por accidente
## (por ejemplo, al cerrar un cuadro que se estaba inspeccionando).
func _set_player_locked(locked: bool) -> void:
	if not is_instance_valid(_player):
		return

	if locked:
		if _player.process_mode == Node.PROCESS_MODE_DISABLED:
			return
		_prev_player_process_mode = _player.process_mode
		# Que quede quieto y en idle, no congelado a mitad de un paso
		_player.velocity = Vector3.ZERO
		var anim: PlayerAnimationController = _player.anim_controller
		if anim and not anim.is_rifle_pose_active():
			anim.update_locomotion(true, 0.0)
		_player.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_player.process_mode = _prev_player_process_mode

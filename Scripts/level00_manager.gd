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
##   Cuando el cassette termina de sonar en la radio (Radio.tape_finished), toda la pantalla se
##   funde a negro y el juego se reinicia por completo.
##
## El fundido usa el de WarpManager (capa 128, por encima de las barras 4:3 y de toda la UI),
## así el negro es continuo entre el final y el nuevo arranque.

## Empieza el fade in del arranque (el jugador ya tiene los controles).
signal intro_fade_started
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
## La radio del puzzle: cuando termina la canción del cassette, el juego se cierra y se reinicia.
@export var radio: Radio
## Duración del fade out a negro cuando termina la canción.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var end_fade_out_duration: float = 2.5
## Escena a cargar al reiniciar. Vacío = recarga este mismo nivel (arranca con la intro).
## Para volver a la pantalla de título, asignar TitleScreen.tscn.
@export var restart_scene: PackedScene

var _player: Player
var _prev_player_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _ending: bool = false


func _ready() -> void:
	# Estado limpio de los autoloads (sobreviven a las recargas de escena)
	CameraDirector.reset()
	Inventory.reset()
	InteractionFocus.reset()
	GameplayInput.reset()

	_player = get_tree().get_first_node_in_group("player") as Player
	_connect_radio()

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

func _connect_radio() -> void:
	if radio == null:
		push_warning("Level00Manager: 'radio' no está asignada; el juego no terminará al acabar la canción.")
		return
	radio.tape_finished.connect(func(_item: ItemData): _begin_ending())


## Cierre del juego: bloquea al jugador, funde a negro y reinicia.
func _begin_ending() -> void:
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
	Inventory.reset() # el inventario no sobrevive al reinicio
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

extends Node
class_name Level00Manager

## Director del nivel 0. Va como hijo de la raíz de terrain.tscn.
##
## INICIO / REINICIO (cada vez que se carga el nivel):
##   1. Pantalla en negro (se oye la lluvia). Se SORTEA el género de la noche (Tango, Folklore o Rock)
##      y aparece el mensaje "Esta noche quiero escuchar un ...".
##   2. Pasan 'intro_black_duration' segundos con el jugador SIN controles; entonces el mensaje se apaga.
##   3. Recién cuando el mensaje ya no está empieza el fade in al juego: el jugador recupera los controles.
##
## OBJETIVO:
##   El cassette cuyo 'genre' (ver CassetteItem / CassettePrefab) coincide con el sorteado es la llave del
##   nivel. Al ponerlo en la radio aparece una barra de carga al centro inferior que avanza MIENTRAS suena
##   (si la cinta sale de la radio, la barra se frena y retoma al volver a ponerla; si un golpe la hace saltar
##   dice "saltó la cinta" en rojo; si el jugador guarda el cassette en el inventario, la barra se oculta hasta
##   que lo vuelva a reproducir). Al completarse
##   'progress_duration' segundos de música correcta, el nivel termina: fundido a negro y pantalla de inicio.
##
## ENEMIGOS:
##   Mientras suena la música correcta, todos los enemigos pasan al estado ATTACK_OBJECT: van a golpear la
##   radio para hacer saltar el cassette. Además, cada 'enemy_respawn_delay' segundos, si quedan
##   'respawn_max_alive' enemigos o menos, hay una chance de que reaparezcan de 1 a 3 en un punto cualquiera
##   del Area3D de su EnemyPatrolZone.
##
## PAUSA: crea el menú de pausa (PauseMenu): Esc / Start. "salir al menú principal" vuelve al inicio.
##
## El fundido usa el de WarpManager (capa 128, por encima de las barras 4:3 y de toda la UI).

## Empieza el fade in del arranque (el jugador ya tiene los controles).
signal intro_fade_started
## Se sorteó el género de esta partida.
signal target_genre_chosen(genre: CassetteItem.Genre)
## El progreso de la barra cambió (0.0 a 1.0).
signal progress_changed(ratio: float)
## La barra se completó: empieza el final del nivel.
signal level_completed
## La pantalla ya está en negro y justo se va a cambiar de escena.
signal restart_requested

## Pantalla de inicio: a donde se vuelve al completar el nivel.
const MAIN_MENU_SCENE: String = "res://Scenes/ui/main_menu.tscn"
const GENRE_MESSAGES: Dictionary = {
	CassetteItem.Genre.TANGO: "Esta noche quiero escuchar un [i]Tango[/i]",
	CassetteItem.Genre.FOLKLORE: "Esta noche quiero escuchar [i]Folklore[/i]",
	CassetteItem.Genre.ROCK: "Esta noche quiero escuchar un [i]Rock[/i]",
}

## Duración del fade a negro al salir al menú principal desde la pausa.
const PAUSE_EXIT_FADE: float = 0.8

enum ForcedGenre { RANDOM, TANGO, FOLKLORE, ROCK }

@export_group("Inicio / Reinicio")
## Desactivar para probar el nivel en el editor sin esperar la intro.
@export var play_intro: bool = true
## Segundos con la pantalla en negro y el mensaje a la vista, contados desde el inicio de la intro. Pasado
## ese tiempo el mensaje se apaga, y recién cuando desapareció empieza el fade in.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var intro_black_duration: float = 3.0
## Duración del fade in que revela la pantalla.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var intro_fade_in_duration: float = 4.0
## Duración del fade out del mensaje (el fade in al juego espera a que termine).
@export_range(0.0, 10.0, 0.1, "suffix:s") var message_fade_out_duration: float = 1.5

@export_group("Objetivo")
## La radio del puzzle.
@export var radio: Radio
## RANDOM = se sortea en cada partida. Cualquier otro valor lo fuerza (útil para probar).
@export var forced_genre: ForcedGenre = ForcedGenre.RANDOM
## Segundos de música correcta que hay que completar para terminar el nivel (la barra de carga).
@export_range(1.0, 600.0, 1.0, "or_greater", "suffix:s") var progress_duration: float = 90.0

@export_group("Enemigos")
## OBJETO que atacan los enemigos en el estado ATTACK_OBJECT. Vacío = la radio. (Cada enemigo puede tener
## además su propio 'attack_object_target', que tiene prioridad.)
@export var enemy_attack_target: Node3D
## Nodo que contiene a los enemigos del nivel (sus posiciones iniciales son los puntos de reaparición).
@export var enemies_root: Node3D
## Territorio de los enemigos: reaparecen en un punto cualquiera de su Area3D. Vacío = se busca una
## EnemyPatrolZone entre los hijos de 'enemies_root'.
@export var patrol_zone: EnemyPatrolZone
## Escena de los enemigos que reaparecen. Vacío = la misma de los enemigos que ya están en el nivel.
@export var enemy_scene: PackedScene
## Escala de los enemigos que reaparecen (los del nivel están a 0.3).
@export_range(0.05, 2.0, 0.05) var enemy_spawn_scale: float = 0.3
## Cada cuántos segundos, con la música correcta sonando, se evalúa si reaparecen enemigos.
@export_range(1.0, 120.0, 0.5, "or_greater", "suffix:s") var enemy_respawn_delay: float = 12.0
## Probabilidad (0 a 1) de que reaparezcan enemigos en cada evaluación.
@export_range(0.0, 1.0, 0.05) var enemy_respawn_chance: float = 0.6
## Solo reaparecen si quedan este número de enemigos vivos, o menos.
@export var respawn_max_alive: int = 2
@export var respawn_min_count: int = 1
@export var respawn_max_count: int = 3
## No reaparecen más cerca que esto del jugador (se reintenta con otro punto de la zona).
@export_range(0.0, 20.0, 0.1, "suffix:m") var respawn_min_player_distance: float = 2.0

@export_group("Pausa")
## Crea el menú de pausa (Esc / Start) en este nivel.
@export var pause_enabled: bool = true

@export_group("Final")
## Texto que aparece sobre el negro al completar el nivel.
@export var ending_message: String = "Esta noche pude escuchar lo que quería, gracias."
## Segundos que se queda el texto en pantalla.
@export_range(0.0, 20.0, 0.1, "suffix:s") var ending_message_hold: float = 4.0
## Duración del fundido de aparición / desaparición del texto.
@export_range(0.0, 10.0, 0.1, "suffix:s") var ending_message_fade: float = 1.5
## Duración del fade out a negro al completar el nivel.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var end_fade_out_duration: float = 2.5
## Escena a cargar al terminar. Vacío = la pantalla de inicio (Scenes/ui/main_menu.tscn).
@export var restart_scene: PackedScene

var target_genre: CassetteItem.Genre = CassetteItem.Genre.TANGO
var progress_seconds: float = 0.0

var _player: Player
var _prev_player_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _ending: bool = false
var _correct_playing: bool = false
var _respawn_timer: float = 0.0
var _pause_menu: PauseMenu
var _message_tween: Tween
var _progress_bar: TapeProgressBar
var _message_layer: CanvasLayer
var _message_label: RichTextLabel


func _ready() -> void:
	# Estado limpio de los autoloads (sobreviven a las recargas de escena)
	CameraDirector.reset()
	Inventory.reset()
	InteractionFocus.reset()
	GameplayInput.reset()

	_player = get_tree().get_first_node_in_group("player") as Player
	_choose_target_genre()
	_setup_enemy_respawn()
	_build_progress_bar()
	_connect_radio()
	_build_pause_menu()

	if play_intro:
		_run_intro()
	else:
		WarpManager.fade_in(0.0) # por si quedó negro de un reinicio anterior


func _process(delta: float) -> void:
	if _ending or not is_instance_valid(radio) or not _correct_playing:
		return

	if radio.is_playing_tape():
		progress_seconds = minf(progress_seconds + delta, progress_duration)
		var ratio: float = progress_seconds / progress_duration
		_progress_bar.set_progress(ratio)
		progress_changed.emit(ratio)
		if progress_seconds >= progress_duration:
			level_completed.emit()
			_begin_ending()
			return

	# Reaparición de enemigos mientras suena la música correcta
	_respawn_timer += delta
	if _respawn_timer >= enemy_respawn_delay:
		_respawn_timer = 0.0
		_try_respawn_enemies()


## Género elegido en esta partida.
func get_target_genre() -> CassetteItem.Genre:
	return target_genre


## ¿Este ítem es la llave del nivel?
func is_correct_item(item: ItemData) -> bool:
	return item is CassetteItem and (item as CassetteItem).genre == target_genre


# ---------------------------------------------------------------- INICIO

func _choose_target_genre() -> void:
	match forced_genre:
		ForcedGenre.TANGO:
			target_genre = CassetteItem.Genre.TANGO
		ForcedGenre.FOLKLORE:
			target_genre = CassetteItem.Genre.FOLKLORE
		ForcedGenre.ROCK:
			target_genre = CassetteItem.Genre.ROCK
		_:
			target_genre = [CassetteItem.Genre.TANGO, CassetteItem.Genre.FOLKLORE,
					CassetteItem.Genre.ROCK].pick_random()
	target_genre_chosen.emit(target_genre)


func _run_intro() -> void:
	WarpManager.fade_out(0.0) # negro inmediato, antes del primer frame
	_set_player_locked(true)
	_show_genre_message()

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

	# El mensaje se apaga por completo ANTES de que empiece a revelarse el juego
	await _hide_genre_message()
	if not is_inside_tree():
		return

	# El jugador recupera los controles justo cuando empieza a revelarse la pantalla
	_set_player_locked(false)
	intro_fade_started.emit()
	await WarpManager.fade_in(intro_fade_in_duration)


## "Esta noche quiero escuchar un _Tango_": aparece sobre el negro (capa 129, por encima del fundido).
func _show_genre_message() -> void:
	_message_label = _make_message_label(GENRE_MESSAGES.get(target_genre, ""))
	_message_layer = _message_label.get_parent() as CanvasLayer
	_message_label.modulate.a = 0.0
	_message_tween = create_tween()
	_message_tween.tween_property(_message_label, "modulate:a", 1.0, 1.0).set_delay(0.5)


## Texto centrado (acepta BBCode: [i]cursiva[/i]) en la capa 129, por encima del fundido a negro.
func _make_message_label(bbcode_text: String) -> RichTextLabel:
	var layer := CanvasLayer.new()
	layer.layer = 129
	add_child(layer)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_left = -330.0
	label.offset_right = 330.0
	label.offset_top = -20.0
	label.offset_bottom = 20.0
	label.add_theme_font_size_override("normal_font_size", 26)
	label.add_theme_font_size_override("italics_font_size", 26)
	label.add_theme_constant_override("outline_size", 10)
	label.text = "[center]%s[/center]" % bbcode_text
	layer.add_child(label)
	return label


## Apaga el mensaje con un fade out y espera a que termine (libera su capa).
func _hide_genre_message() -> void:
	if not is_instance_valid(_message_label):
		return
	if _message_tween and _message_tween.is_valid():
		_message_tween.kill() # por si el fade in del mensaje todavía no terminó
	_message_tween = create_tween()
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, message_fade_out_duration)
	await _message_tween.finished
	if is_instance_valid(_message_layer):
		_message_layer.queue_free()


# ---------------------------------------------------------------- OBJETIVO

func _build_progress_bar() -> void:
	_progress_bar = TapeProgressBar.new()
	_progress_bar.name = "TapeProgressBar"
	add_child(_progress_bar)


func _connect_radio() -> void:
	if radio == null:
		push_warning("Level00Manager: 'radio' no está asignada; el nivel no se puede completar.")
		return
	radio.tape_play_started.connect(_on_tape_play_started)
	radio.tape_ejected.connect(_on_tape_stopped)
	radio.tape_finished.connect(_on_tape_finished)
	radio.tape_jumped.connect(_on_tape_jumped)
	Inventory.item_added.connect(_on_inventory_item_added)


func _on_tape_play_started(item: ItemData) -> void:
	if is_correct_item(item):
		_set_correct_playing(true)
	else:
		_progress_bar.set_state(TapeProgressBar.State.PAUSED) # suena otra cinta: la barra queda quieta


## Un golpe (del jugador o de un enemigo) hizo saltar la cinta de la radio.
func _on_tape_jumped(item: ItemData) -> void:
	if is_correct_item(item):
		_progress_bar.set_state(TapeProgressBar.State.TAPE_JUMPED)


func _on_tape_finished(item: ItemData) -> void:
	_on_tape_stopped(item)
	if is_correct_item(item):
		_progress_bar.set_state(TapeProgressBar.State.PAUSED)


## El jugador guardó el cassette correcto en el inventario (sacándolo de la radio o juntándolo del suelo):
## la barra se oculta hasta que lo vuelva a reproducir.
func _on_inventory_item_added(entry: InventoryEntry) -> void:
	if entry != null and is_correct_item(entry.item):
		_progress_bar.hide_bar()


func _on_tape_stopped(_item: ItemData) -> void:
	if _correct_playing:
		_set_correct_playing(false)


## La música correcta empieza o deja de sonar: muestra la barra y (des)activa el ataque de los enemigos.
func _set_correct_playing(playing: bool) -> void:
	_correct_playing = playing
	_respawn_timer = 0.0
	if playing:
		_progress_bar.show_bar()
		_progress_bar.set_state(TapeProgressBar.State.PLAYING)
		_progress_bar.set_progress(progress_seconds / progress_duration)
		get_tree().call_group("enemies", "command_attack_object", _attack_target())
	else:
		get_tree().call_group("enemies", "release_object_target")


# ---------------------------------------------------------------- ENEMIGOS

## Prepara la reaparición: el territorio (EnemyPatrolZone) y la escena de los enemigos, tomados de los
## que ya están en el nivel si no se asignaron a mano.
func _setup_enemy_respawn() -> void:
	if enemies_root == null:
		enemies_root = get_parent().get_node_or_null("Enemies") as Node3D
	if enemies_root == null:
		return
	for child in enemies_root.get_children():
		if patrol_zone == null and child is EnemyPatrolZone:
			patrol_zone = child as EnemyPatrolZone
		elif enemy_scene == null and child is Enemy and child.scene_file_path != "":
			enemy_scene = load(child.scene_file_path) as PackedScene


func _alive_enemy_count() -> int:
	var count: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy and not enemy.is_queued_for_deletion() and enemy.current_state != Enemy.State.DEAD:
			count += 1
	return count


## Con la música correcta sonando y pocos enemigos vivos, hay una chance de que reaparezcan 1 a 3.
func _try_respawn_enemies() -> void:
	if enemy_scene == null or patrol_zone == null or enemies_root == null:
		return
	if _alive_enemy_count() > respawn_max_alive:
		return
	if randf() > enemy_respawn_chance:
		return

	var spawn_count: int = randi_range(maxi(respawn_min_count, 1), maxi(respawn_max_count, respawn_min_count))
	for i in spawn_count:
		_spawn_enemy_at(_pick_spawn_point())


## Punto al azar dentro de la zona de patrulla, lejos del jugador (se reintenta unas veces; si no hay
## lugar, se usa el último).
func _pick_spawn_point() -> Vector3:
	var point: Vector3 = patrol_zone.get_random_point()
	if not is_instance_valid(_player):
		return point
	for attempt in 8:
		if point.distance_to(_player.global_position) >= respawn_min_player_distance:
			break
		point = patrol_zone.get_random_point()
	return point


## Qué objeto atacan los enemigos: el asignado en 'enemy_attack_target' o, si no hay, la radio (su malla,
## que es donde la ve el jugador). Sirve también para los enemigos que reaparecen, que salen de la escena
## original sin las asignaciones hechas a mano en cada enemigo del nivel.
func _attack_target() -> Node3D:
	if is_instance_valid(enemy_attack_target):
		return enemy_attack_target
	if is_instance_valid(radio) and is_instance_valid(radio.visual):
		return radio.visual
	return radio


func _spawn_enemy_at(point: Vector3) -> void:
	var enemy := enemy_scene.instantiate() as Enemy
	# Posición antes de entrar al árbol: así el enemigo ya nace con su punto de partida correcto
	enemy.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * enemy_spawn_scale),
			enemies_root.to_local(point + Vector3.UP * 0.05))
	enemy.zone_area = patrol_zone
	enemies_root.add_child(enemy)
	if _correct_playing and is_instance_valid(_attack_target()):
		enemy.command_attack_object(_attack_target())


# ---------------------------------------------------------------- FINAL

## Cierre del nivel: bloquea al jugador, funde a negro y vuelve a la pantalla de inicio.
func _begin_ending() -> void:
	if _ending:
		return
	_ending = true
	if is_instance_valid(_pause_menu):
		_pause_menu.enabled = false
	get_tree().call_group("enemies", "release_object_target")

	_set_player_locked(true)
	if is_instance_valid(radio):
		radio.fade_out_music(end_fade_out_duration) # la música se apaga junto con la imagen
	await WarpManager.fade_out(end_fade_out_duration)
	if not is_inside_tree():
		return

	# Sobre el negro aparece el texto de cierre, se queda un rato y se apaga
	if ending_message != "":
		var label: RichTextLabel = _make_message_label(ending_message)
		label.modulate.a = 0.0
		var tween: Tween = create_tween()
		tween.tween_property(label, "modulate:a", 1.0, ending_message_fade)
		tween.tween_interval(ending_message_hold)
		tween.tween_property(label, "modulate:a", 0.0, ending_message_fade)
		await tween.finished
		if not is_inside_tree():
			return
	_leave_level()


func _leave_level(force_main_menu: bool = false) -> void:
	restart_requested.emit()
	CameraDirector.reset() # zonas/forzados/modo fusil/barras 4:3 fuera antes de cambiar de escena
	Inventory.reset() # el inventario no sobrevive al nivel
	if restart_scene and not force_main_menu:
		get_tree().change_scene_to_packed(restart_scene)
	else:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# ---------------------------------------------------------------- PAUSA

func _build_pause_menu() -> void:
	if not pause_enabled:
		return
	_pause_menu = PauseMenu.create_in(self)
	_pause_menu.main_menu_requested.connect(_on_pause_main_menu_requested)


## "salir al menú principal" desde la pausa: fundido a negro y de vuelta a la pantalla de inicio.
func _on_pause_main_menu_requested() -> void:
	if _ending:
		return
	_ending = true
	await WarpManager.fade_out(PAUSE_EXIT_FADE) # WarpManager sigue activo con el juego en pausa
	if not is_inside_tree():
		return
	get_tree().paused = false # la escena nueva no puede nacer en pausa
	_leave_level(true)


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

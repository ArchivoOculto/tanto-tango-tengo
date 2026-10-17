extends Node
class_name Level00Manager

## Director del nivel 0. Va como hijo de la raíz de terrain.tscn.
##
## INICIO / REINICIO (cada vez que se carga el nivel):
##   1. Pantalla en negro (se oye la lluvia). Se SORTEA el género de la noche (Tango, Folklore o Rock)
##      y aparece el mensaje "Esta noche quiero escuchar un ...".
##   2. Pasan 'intro_black_duration' segundos con el jugador SIN controles.
##   3. Empieza el fade in: el jugador recupera los controles y el mensaje se apaga solo.
##
## OBJETIVO:
##   El cassette cuyo 'genre' (ver CassetteItem / CassettePrefab) coincide con el sorteado es la llave del
##   nivel. Al ponerlo en la radio aparece una barra de carga al centro inferior que avanza MIENTRAS suena
##   (si la cinta sale de la radio, la barra se frena y retoma al volver a ponerla). Al completarse
##   'progress_duration' segundos de música correcta, el nivel termina: fundido a negro y pantalla de inicio.
##
## ENEMIGOS:
##   Mientras suena la música correcta, todos los enemigos pasan al estado ATTACK_OBJECT: van a golpear la
##   radio para hacer saltar el cassette. Además, cada 'enemy_respawn_delay' segundos, si quedan
##   'respawn_max_alive' enemigos o menos, hay una chance de que reaparezcan de 1 a 3 en cualquiera de las
##   posiciones originales.
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

enum ForcedGenre { RANDOM, TANGO, FOLKLORE, ROCK }

@export_group("Inicio / Reinicio")
## Desactivar para probar el nivel en el editor sin esperar la intro.
@export var play_intro: bool = true
## Segundos con la pantalla en negro (solo lluvia) antes de que empiece el fade in.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var intro_black_duration: float = 3.0
## Duración del fade in que revela la pantalla.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var intro_fade_in_duration: float = 4.0
## Cuánto sigue visible el mensaje una vez que empieza el fade in, antes de apagarse.
@export_range(0.0, 10.0, 0.1, "suffix:s") var message_hold_after_fade: float = 2.5
## Duración del fade out del mensaje.
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
## Puntos de reaparición EXTRA (Marker3D), además de las posiciones originales de los enemigos. Útiles para
## que reaparezcan del lado de la radio si el sector original no tiene paso hasta ella.
@export var extra_spawn_points: Array[Marker3D] = []
## Margen (m) alrededor de los enemigos y la radio donde se genera la navegación.
@export_range(0.0, 20.0, 0.5, "suffix:m") var nav_bake_margin: float = 4.0
## Cada cuántos segundos, con la música correcta sonando, se evalúa si reaparecen enemigos.
@export_range(1.0, 120.0, 0.5, "or_greater", "suffix:s") var enemy_respawn_delay: float = 12.0
## Probabilidad (0 a 1) de que reaparezcan enemigos en cada evaluación.
@export_range(0.0, 1.0, 0.05) var enemy_respawn_chance: float = 0.6
## Solo reaparecen si quedan este número de enemigos vivos, o menos.
@export var respawn_max_alive: int = 2
@export var respawn_min_count: int = 1
@export var respawn_max_count: int = 3
## No reaparecen más cerca que esto del jugador (si hay otras posiciones disponibles).
@export_range(0.0, 20.0, 0.1, "suffix:m") var respawn_min_player_distance: float = 2.0

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
var _enemy_scene: PackedScene
var _enemy_spawn_transforms: Array[Transform3D] = []
var _navigation: RuntimeNavigation
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
	_collect_enemy_spawns()
	_build_progress_bar()
	_build_navigation()
	_connect_radio()

	if play_intro:
		_run_intro()
	else:
		WarpManager.fade_in(0.0) # por si quedó negro de un reinicio anterior


func _process(delta: float) -> void:
	if _ending or not is_instance_valid(radio):
		return

	var playing_correct: bool = _correct_playing and radio.is_playing_tape()
	if is_instance_valid(_progress_bar):
		_progress_bar.set_paused(not playing_correct)
	if not _correct_playing:
		return

	if playing_correct:
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

	# El jugador recupera los controles justo cuando empieza a revelarse la pantalla
	_set_player_locked(false)
	intro_fade_started.emit()
	_hide_genre_message_later()
	await WarpManager.fade_in(intro_fade_in_duration)


## "Esta noche quiero escuchar un _Tango_": aparece sobre el negro (capa 129, por encima del fundido).
func _show_genre_message() -> void:
	_message_label = _make_message_label(GENRE_MESSAGES.get(target_genre, ""))
	_message_layer = _message_label.get_parent() as CanvasLayer
	_message_label.modulate.a = 0.0
	create_tween().tween_property(_message_label, "modulate:a", 1.0, 1.0).set_delay(0.5)


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


func _hide_genre_message_later() -> void:
	if not is_instance_valid(_message_label):
		return
	var tween: Tween = create_tween()
	tween.tween_interval(message_hold_after_fade)
	tween.tween_property(_message_label, "modulate:a", 0.0, message_fade_out_duration)
	tween.finished.connect(func():
		if is_instance_valid(_message_layer):
			_message_layer.queue_free()
	)


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
	radio.tape_finished.connect(_on_tape_stopped)


func _on_tape_play_started(item: ItemData) -> void:
	if is_correct_item(item):
		_set_correct_playing(true)


func _on_tape_stopped(_item: ItemData) -> void:
	if _correct_playing:
		_set_correct_playing(false)


## La música correcta empieza o deja de sonar: muestra la barra y (des)activa el ataque de los enemigos.
func _set_correct_playing(playing: bool) -> void:
	_correct_playing = playing
	_respawn_timer = 0.0
	if playing:
		_progress_bar.show_bar()
		_progress_bar.set_progress(progress_seconds / progress_duration)
		get_tree().call_group("enemies", "command_attack_object", _attack_target())
	else:
		get_tree().call_group("enemies", "release_object_target")


# ---------------------------------------------------------------- ENEMIGOS

## Malla de navegación para que los enemigos rodeen los alambrados camino a la radio. Se hornea en un
## hilo aparte alrededor de la zona de los enemigos y la radio.
func _build_navigation() -> void:
	if not is_instance_valid(radio) or _enemy_spawn_transforms.is_empty():
		return
	var min_point: Vector3 = radio.global_position
	var max_point: Vector3 = radio.global_position
	for t in _enemy_spawn_transforms:
		min_point = min_point.min(t.origin)
		max_point = max_point.max(t.origin)
	var bounds := AABB(min_point, max_point - min_point).grow(nav_bake_margin)
	bounds.position.y = min_point.y - 1.0
	bounds.size.y = 4.0

	_navigation = RuntimeNavigation.new()
	_navigation.name = "RuntimeNavigation"
	get_parent().add_child.call_deferred(_navigation)
	_bake_navigation_later.call_deferred(bounds)


func _bake_navigation_later(bounds: AABB) -> void:
	await get_tree().process_frame
	if is_instance_valid(_navigation) and _navigation.is_inside_tree():
		_navigation.bake_area(get_parent(), bounds)


func _collect_enemy_spawns() -> void:
	for marker in extra_spawn_points:
		if is_instance_valid(marker):
			_enemy_spawn_transforms.append(marker.global_transform)
	if enemies_root == null:
		enemies_root = get_parent().get_node_or_null("Enemies") as Node3D
	if enemies_root == null:
		return
	for child in enemies_root.get_children():
		if child is Enemy:
			_enemy_spawn_transforms.append((child as Enemy).global_transform)
			if _enemy_scene == null and (child as Enemy).scene_file_path != "":
				_enemy_scene = load((child as Enemy).scene_file_path) as PackedScene


func _alive_enemy_count() -> int:
	var count: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy and not enemy.is_queued_for_deletion() and enemy.current_state != Enemy.State.DEAD:
			count += 1
	return count


## Con la música correcta sonando y pocos enemigos vivos, hay una chance de que reaparezcan 1 a 3.
func _try_respawn_enemies() -> void:
	if _enemy_scene == null or _enemy_spawn_transforms.is_empty() or enemies_root == null:
		return
	if _alive_enemy_count() > respawn_max_alive:
		return
	if randf() > enemy_respawn_chance:
		return

	var spawn_count: int = randi_range(maxi(respawn_min_count, 1), maxi(respawn_max_count, respawn_min_count))
	for i in spawn_count:
		_spawn_enemy_at(_pick_spawn_transform())


func _pick_spawn_transform() -> Transform3D:
	var candidates: Array[Transform3D] = []
	for t in _enemy_spawn_transforms:
		if not is_instance_valid(_player) or t.origin.distance_to(_player.global_position) >= respawn_min_player_distance:
			candidates.append(t)
	if candidates.is_empty():
		candidates = _enemy_spawn_transforms
	return candidates.pick_random()


## Qué objeto atacan los enemigos: el asignado en 'enemy_attack_target' o, si no hay, la radio.
func _attack_target() -> Node3D:
	return enemy_attack_target if is_instance_valid(enemy_attack_target) else radio


func _spawn_enemy_at(spawn_transform: Transform3D) -> void:
	var enemy := _enemy_scene.instantiate() as Enemy
	enemies_root.add_child(enemy)
	enemy.global_transform = spawn_transform
	enemy.spawn_position = spawn_transform.origin
	if _correct_playing and is_instance_valid(_attack_target()):
		enemy.command_attack_object(_attack_target())


# ---------------------------------------------------------------- FINAL

## Cierre del nivel: bloquea al jugador, funde a negro y vuelve a la pantalla de inicio.
func _begin_ending() -> void:
	if _ending:
		return
	_ending = true
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


func _leave_level() -> void:
	restart_requested.emit()
	CameraDirector.reset() # zonas/forzados/modo fusil/barras 4:3 fuera antes de cambiar de escena
	Inventory.reset() # el inventario no sobrevive al nivel
	if restart_scene:
		get_tree().change_scene_to_packed(restart_scene)
	else:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


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

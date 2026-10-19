extends Node

## Autoload "Audio": la ÚNICA puerta de entrada para reproducir sonidos del juego.
##
##     Audio.play(SoundIds.UI_MENU_CONFIRM)                         # sonido plano (UI, avisos)
##     Audio.play_at(SoundIds.PLAYER_LAND, global_position)         # sonido 3D en un punto del mundo
##     Audio.play_on(SoundIds.FAROLITO_BUZZ_LOOP, self)             # 3D que sigue a un nodo
##     var handle := Audio.play(SoundIds.AMB_RAIN_LOOP); handle.stop(2.0)   # loops: se detienen con el handle
##     Audio.play_music(SoundIds.MUS_MENU_THEME, 1.5)               # música con crossfade
##
## POR QUÉ ASÍ (resumen, detalle en Docs/sistema_de_audio.md):
##  - Código y audio quedan separados: los programadores nombran EVENTOS (SoundIds); el equipo de sonido
##    llena cada evento (Resources/audio/events/*.tres) con archivos, volumen, pitch y variaciones.
##  - Rendimiento para PCs modestas: un pool fijo de reproductores reutilizables (cero instanciar nodos en
##    pleno juego), límite de voces por evento y cooldown anti-spam.
##  - Robusto: un evento inexistente avisa UNA vez y no rompe; uno vacío simplemente no suena.
##  - Los eventos se descubren solos al iniciar (carpeta Resources/audio/events/), sin lista central que
##    genere conflictos al trabajar en equipo.

const EVENTS_DIR: String = "res://Resources/audio/events/"
const POOL_SIZE_2D: int = 12
const POOL_SIZE_3D: int = 20
const SILENT_DB: float = -60.0

## Muestra en la consola cada sonido que se dispara (útil para depurar qué suena y cuándo).
@export var debug_log: bool = false

## Una "voz": un reproductor del pool y lo que está sonando en él.
class Voice extends RefCounted:
	var player: Node
	var is_3d: bool = false
	var event: SoundEvent
	var generation: int = 0
	var active: bool = false
	var started_msec: int = 0
	var follow: Node3D
	var fade_tween: Tween

var _events: Dictionary = {} # StringName -> SoundEvent
var _voices_2d: Array[Voice] = []
var _voices_3d: Array[Voice] = []
var _last_played_msec: Dictionary = {} # StringName -> int
var _last_variation: Dictionary = {} # StringName -> int
var _warned_missing: Dictionary = {} # StringName -> true

var _music_players: Array[AudioStreamPlayer] = []
var _music_index: int = 0
var _music_tween: Tween
var _music_id: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # los sonidos de menú/pausa suenan con el juego en pausa
	_build_pools()
	_music_players = [_make_music_player(), _make_music_player()]
	load_events()


func _process(_delta: float) -> void:
	# Solo las voces 3D que siguen a un nodo necesitan actualizarse
	for voice in _voices_3d:
		if voice.active and is_instance_valid(voice.follow):
			(voice.player as AudioStreamPlayer3D).global_position = voice.follow.global_position


# ---------------------------------------------------------------- API

## Sonido plano (no posicional): UI, avisos, música corta, ambiente sin lugar.
func play(id: StringName, volume_offset_db: float = 0.0) -> SoundHandle:
	return _play(id, false, Vector3.ZERO, null, volume_offset_db)


## Sonido 3D en un punto fijo del mundo.
func play_at(id: StringName, position: Vector3, volume_offset_db: float = 0.0) -> SoundHandle:
	return _play(id, true, position, null, volume_offset_db)


## Sonido 3D que sigue a 'node' mientras suena (un enemigo, una farola, la radio).
func play_on(id: StringName, node: Node3D, volume_offset_db: float = 0.0) -> SoundHandle:
	if not is_instance_valid(node):
		return null
	return _play(id, true, node.global_position, node, volume_offset_db)


## Detiene todas las voces de un evento.
func stop(id: StringName, fade_time: float = 0.0) -> void:
	for voice in _voices_2d + _voices_3d:
		if voice.active and voice.event and _event_id(voice.event) == id:
			_stop_voice(voice, fade_time)


## Detiene todos los sonidos (opcionalmente solo los de un bus, ver AudioBuses).
func stop_all(bus: StringName = &"", fade_time: float = 0.0) -> void:
	for voice in _voices_2d + _voices_3d:
		if voice.active and (bus == &"" or StringName(voice.event.bus) == bus):
			_stop_voice(voice, fade_time)


func is_playing(id: StringName) -> bool:
	for voice in _voices_2d + _voices_3d:
		if voice.active and voice.event and _event_id(voice.event) == id:
			return true
	return false


func has_event(id: StringName) -> bool:
	return _events.has(id)


## Registra un evento por código (para pruebas o contenido generado). Los de la carpeta se cargan solos.
func register_event(event: SoundEvent, id: StringName = &"") -> void:
	var key: StringName = id if id != &"" else _event_id(event)
	if key == &"":
		push_warning("Audio: se intentó registrar un SoundEvent sin id.")
		return
	_events[key] = event


## Música con crossfade. Usa un evento (su primer stream o uno al azar) y el bus del evento.
func play_music(id: StringName, fade_time: float = 1.0) -> void:
	if id == _music_id and _music_players[_music_index].playing:
		return
	var event: SoundEvent = _get_event(id)
	if event == null or event.streams.is_empty():
		return
	_music_id = id

	var old_player: AudioStreamPlayer = _music_players[_music_index]
	_music_index = (_music_index + 1) % 2
	var new_player: AudioStreamPlayer = _music_players[_music_index]

	new_player.stream = event.streams.pick_random()
	new_player.bus = event.bus
	new_player.pitch_scale = event.pitch
	new_player.volume_db = SILENT_DB
	new_player.play()

	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(new_player, "volume_db", event.volume_db, maxf(fade_time, 0.01))
	if old_player.playing:
		_music_tween.tween_property(old_player, "volume_db", SILENT_DB, maxf(fade_time, 0.01))
		_music_tween.chain().tween_callback(old_player.stop)


func stop_music(fade_time: float = 1.0) -> void:
	_music_id = &""
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	for player in _music_players:
		if player.playing:
			_music_tween.tween_property(player, "volume_db", SILENT_DB, maxf(fade_time, 0.01))
	_music_tween.chain().tween_callback(func() -> void:
		for player in _music_players:
			player.stop()
	)


# ---------------------------------------------------------------- CARGA DE EVENTOS

## Descubre todos los SoundEvent de Resources/audio/events/ (incluye subcarpetas). Se llama sola al iniciar.
func load_events() -> void:
	_events.clear()
	_scan_directory(EVENTS_DIR)
	if debug_log:
		print("Audio: %d eventos cargados." % _events.size())


func _scan_directory(path: String) -> void:
	for entry in ResourceLoader.list_directory(path):
		if entry.ends_with("/"):
			_scan_directory(path.path_join(entry))
			continue
		if not (entry.ends_with(".tres") or entry.ends_with(".res")):
			continue
		var event := ResourceLoader.load(path.path_join(entry)) as SoundEvent
		if event == null:
			continue
		var key: StringName = event.id if event.id != &"" else StringName(entry.get_basename())
		if _events.has(key):
			push_warning("Audio: id de evento repetido '%s' (%s)." % [key, path.path_join(entry)])
		_events[key] = event


func _event_id(event: SoundEvent) -> StringName:
	if event.id != &"":
		return event.id
	for key: StringName in _events:
		if _events[key] == event:
			return key
	return &""


func _get_event(id: StringName) -> SoundEvent:
	var event: SoundEvent = _events.get(id)
	if event == null and not _warned_missing.has(id):
		_warned_missing[id] = true
		push_warning("Audio: no existe el evento de sonido '%s' (crearlo en %s)." % [id, EVENTS_DIR])
	return event


# ---------------------------------------------------------------- REPRODUCCIÓN

func _play(id: StringName, positional: bool, position: Vector3, follow: Node3D, offset_db: float) -> SoundHandle:
	var event: SoundEvent = _get_event(id)
	if event == null:
		return null
	if event.streams.is_empty():
		if debug_log:
			print("Audio: '%s' sin audio asignado (evento vacío)." % id)
		return null

	# Cooldown anti-spam
	var now: int = Time.get_ticks_msec()
	if event.cooldown > 0.0 and now - int(_last_played_msec.get(id, -1000000)) < int(event.cooldown * 1000.0):
		return null
	_last_played_msec[id] = now

	# Tope de voces de este evento: se corta la más vieja
	if event.max_voices > 0:
		_enforce_voice_limit(event, id)

	var use_3d: bool = event.spatial and positional
	var voice: Voice = _acquire_voice(use_3d)
	if voice == null:
		return null

	voice.event = event
	voice.active = true
	voice.generation += 1
	voice.started_msec = now
	voice.follow = follow
	if voice.fade_tween and voice.fade_tween.is_valid():
		voice.fade_tween.kill()

	var volume: float = event.volume_db + offset_db + randf_range(-event.volume_variation_db, event.volume_variation_db)
	var pitch_value: float = maxf(event.pitch * (1.0 + randf_range(-event.pitch_variation, event.pitch_variation)), 0.05)
	var stream: AudioStream = _pick_stream(event, id)

	if use_3d:
		var player := voice.player as AudioStreamPlayer3D
		player.stream = stream
		player.bus = event.bus
		player.volume_db = volume
		player.pitch_scale = pitch_value
		player.max_distance = event.max_distance
		player.unit_size = event.unit_size
		player.global_position = position
		player.play()
	else:
		var player := voice.player as AudioStreamPlayer
		player.stream = stream
		player.bus = event.bus
		player.volume_db = volume
		player.pitch_scale = pitch_value
		player.play()

	if debug_log:
		print("Audio: ▶ %s (%s, %.1f dB)" % [id, "3D" if use_3d else "2D", volume])
	return SoundHandle.new(self, voice, voice.generation)


func _pick_stream(event: SoundEvent, id: StringName) -> AudioStream:
	var count: int = event.streams.size()
	var index: int = randi() % count
	if count > 1 and event.avoid_repeat and index == int(_last_variation.get(id, -1)):
		index = (index + 1 + randi() % (count - 1)) % count
	_last_variation[id] = index
	return event.streams[index]


func _enforce_voice_limit(event: SoundEvent, id: StringName) -> void:
	var playing: Array[Voice] = []
	for voice in _voices_2d + _voices_3d:
		if voice.active and voice.event == event:
			playing.append(voice)
	if playing.size() < event.max_voices:
		return
	playing.sort_custom(func(a: Voice, b: Voice) -> bool: return a.started_msec < b.started_msec)
	_stop_voice(playing[0], 0.0)


## Voz libre del pool; si no queda ninguna, roba la más vieja que no sea un loop.
func _acquire_voice(use_3d: bool) -> Voice:
	var pool: Array[Voice] = _voices_3d if use_3d else _voices_2d
	var oldest: Voice = null
	for voice in pool:
		if not voice.active:
			return voice
		if not voice.event.loop and (oldest == null or voice.started_msec < oldest.started_msec):
			oldest = voice
	if oldest != null:
		_stop_voice(oldest, 0.0)
	return oldest


func _stop_voice(voice: Voice, fade_time: float) -> void:
	if not voice.active:
		return
	if fade_time <= 0.0:
		_release_voice(voice)
		return
	if voice.fade_tween and voice.fade_tween.is_valid():
		voice.fade_tween.kill()
	var generation: int = voice.generation
	voice.fade_tween = create_tween()
	voice.fade_tween.tween_property(voice.player, "volume_db", SILENT_DB, fade_time)
	voice.fade_tween.tween_callback(func() -> void:
		if voice.generation == generation:
			_release_voice(voice)
	)


func _release_voice(voice: Voice) -> void:
	voice.active = false
	voice.follow = null
	voice.generation += 1 # invalida los handles viejos
	(voice.player as Node).call("stop")


func _on_voice_finished(voice: Voice) -> void:
	if not voice.active:
		return
	# Los loops vuelven a empezar (con otra variación si hay varias)
	if voice.event.loop and not voice.event.streams.is_empty():
		var stream: AudioStream = _pick_stream(voice.event, _event_id(voice.event))
		voice.player.set("stream", stream)
		voice.player.call("play")
		return
	voice.active = false
	voice.follow = null
	voice.generation += 1


# Usados por SoundHandle
func voice_is_active(voice: Voice, generation: int) -> bool:
	return voice.active and voice.generation == generation


func voice_stop(voice: Voice, generation: int, fade_time: float) -> void:
	if voice.generation == generation:
		_stop_voice(voice, fade_time)


# ---------------------------------------------------------------- POOLS

func _build_pools() -> void:
	for i in POOL_SIZE_2D:
		var player := AudioStreamPlayer.new()
		player.name = "Voice2D_%d" % i
		add_child(player)
		_voices_2d.append(_make_voice(player, false))
	for i in POOL_SIZE_3D:
		var player := AudioStreamPlayer3D.new()
		player.name = "Voice3D_%d" % i
		add_child(player)
		_voices_3d.append(_make_voice(player, true))


func _make_voice(player: Node, is_3d: bool) -> Voice:
	var voice := Voice.new()
	voice.player = player
	voice.is_3d = is_3d
	player.finished.connect(_on_voice_finished.bind(voice))
	return voice


func _make_music_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = "Music_%d" % _music_players.size()
	player.bus = AudioBuses.MUSIC
	add_child(player)
	return player

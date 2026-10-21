extends Node

## Autoload "Audio": la ÚNICA puerta de entrada para reproducir sonidos del juego.
##
##     Audio.play(SoundIds.UI_MENU_CONFIRM)                         # sonido plano (UI, avisos)
##     Audio.play_at(SoundIds.PLAYER_LAND, global_position)         # sonido 3D en un punto del mundo
##     Audio.play_on(SoundIds.FAROLITO_BUZZ_LOOP, self)             # 3D que sigue a un nodo
##     var handle := Audio.play(SoundIds.AMB_RAIN_LOOP); handle.stop(2.0)   # loops: se detienen con el handle
##     Audio.play_music(SoundIds.MUS_MENU_THEME, 1.5)               # música con crossfade
##     Audio.play_stream_on(SoundIds.RADIO_TAPE_MUSIC, track, node, 12.0)   # audio que no es del evento (ver abajo)
##
## AUDIO DINÁMICO: algunos sonidos no tienen un archivo fijo: la canción de la radio depende del cassette
## puesto. Para eso están los play_stream_*: el EVENTO define cómo suena (bus, volumen, 3D, atenuación) y quien
## llama aporta el audio. El handle devuelto permite saber en qué punto está (get_position), cambiarle el
## pitch (set_pitch_scale) y enterarse de cuándo termina (signal finished).
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

# LLUVIA EN INTERIORES: al entrar a un interior (zona 4:3, ver CameraDirector.indoor_changed) la lluvia se aleja
# (baja de volumen) y se apaga el agudo (pasa-bajos), como oída a través de paredes y techo. Valores para tocar:
const RAIN_INDOOR_VOLUME_DB: float = -10.0 ## cuánto baja la lluvia dentro (dB)
const RAIN_INDOOR_CUTOFF_HZ: float = 1100.0 ## frecuencia de corte dentro (más baja = más amortiguada)
const RAIN_OPEN_CUTOFF_HZ: float = 20500.0 ## corte al aire libre (el máximo del filtro: no se nota)
const RAIN_MIN_FADE: float = 0.4 ## duración mínima del cambio (s), así nunca es un corte seco

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
	var base_pitch: float = 1.0
	var handle_ref: WeakRef

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

var _rain_bus: int = -1
var _rain_filter: AudioEffectLowPassFilter
var _rain_muffle: float = 0.0 ## 0 = al aire libre, 1 = lluvia de interior
var _rain_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # los sonidos de menú/pausa suenan con el juego en pausa
	_build_pools()
	_music_players = [_make_music_player(), _make_music_player()]
	load_events()
	_setup_rain_bus()
	CameraDirector.indoor_changed.connect(_on_indoor_changed)


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


## Como play_on(), pero con el audio que aporta quien llama (la canción de un cassette). El evento define
## bus, volumen, 3D y atenuación; 'start_at' = punto (s) desde donde empezar.
func play_stream_on(id: StringName, stream: AudioStream, node: Node3D, start_at: float = 0.0,
		volume_offset_db: float = 0.0) -> SoundHandle:
	if not is_instance_valid(node):
		return null
	return _play(id, true, node.global_position, node, volume_offset_db, stream, start_at)


## Como play_at(), con audio aportado por quien llama.
func play_stream_at(id: StringName, stream: AudioStream, position: Vector3, start_at: float = 0.0,
		volume_offset_db: float = 0.0) -> SoundHandle:
	return _play(id, true, position, null, volume_offset_db, stream, start_at)


## Como play(), con audio aportado por quien llama.
func play_stream(id: StringName, stream: AudioStream, start_at: float = 0.0, volume_offset_db: float = 0.0) -> SoundHandle:
	return _play(id, false, Vector3.ZERO, null, volume_offset_db, stream, start_at)


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


# ---------------------------------------------------------------- LLUVIA EN INTERIORES

## Pasa la lluvia a "interior" (alejada y filtrada) o al aire libre, con un fundido de 'duration' segundos
## (mínimo RAIN_MIN_FADE; 0 = al instante). Lo dispara solo el CameraDirector al entrar/salir de un interior,
## pero se puede llamar a mano (ej: una escena que transcurre adentro sin zona 4:3).
func set_indoor_mix(indoor: bool, duration: float = 0.8) -> void:
	if _rain_tween and _rain_tween.is_valid():
		_rain_tween.kill()
	var target: float = 1.0 if indoor else 0.0
	if duration <= 0.0:
		_apply_rain_muffle(target)
		return
	_rain_tween = create_tween()
	_rain_tween.tween_method(_apply_rain_muffle, _rain_muffle, target, maxf(duration, RAIN_MIN_FADE))


func _on_indoor_changed(active: bool, duration: float) -> void:
	set_indoor_mix(active, duration)


func _setup_rain_bus() -> void:
	_rain_bus = AudioServer.get_bus_index(AudioBuses.RAIN)
	if _rain_bus < 0:
		push_warning("Audio: falta el bus 'Rain' en el layout de buses; la lluvia no se filtrará en interiores.")
		return
	_rain_filter = AudioServer.get_bus_effect(_rain_bus, 0) as AudioEffectLowPassFilter
	if _rain_filter == null:
		push_warning("Audio: el bus 'Rain' debe tener un AudioEffectLowPassFilter como primer efecto.")
	_apply_rain_muffle(0.0)


## 'amount': 0 = aire libre, 1 = interior. El corte se mueve en escala logarítmica (así suena parejo).
func _apply_rain_muffle(amount: float) -> void:
	_rain_muffle = amount
	if _rain_bus < 0:
		return
	AudioServer.set_bus_volume_db(_rain_bus, lerpf(0.0, RAIN_INDOOR_VOLUME_DB, amount))
	if _rain_filter != null:
		# Al aire libre el filtro se apaga del todo: la lluvia suena exactamente igual que sin él
		AudioServer.set_bus_effect_enabled(_rain_bus, 0, amount > 0.001)
		_rain_filter.cutoff_hz = exp(lerpf(log(RAIN_OPEN_CUTOFF_HZ), log(RAIN_INDOOR_CUTOFF_HZ), amount))


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

func _play(id: StringName, positional: bool, position: Vector3, follow: Node3D, offset_db: float,
		stream_override: AudioStream = null, start_at: float = 0.0) -> SoundHandle:
	var event: SoundEvent = _get_event(id)
	if event == null:
		return null
	if event.streams.is_empty() and stream_override == null:
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
	var stream: AudioStream = stream_override if stream_override != null else _pick_stream(event, id)
	if event.loop:
		_ensure_looping(stream)

	# Recorte: empezar en un punto al azar y/o cortar a los N segundos
	var cut_after: float = 0.0
	if event.cut_after_max > 0.0 or event.cut_after_min > 0.0:
		cut_after = randf_range(minf(event.cut_after_min, event.cut_after_max), maxf(event.cut_after_min, event.cut_after_max))
	var start_position: float = start_at
	if event.random_start and stream_override == null:
		start_position = randf_range(0.0, maxf(0.0, stream.get_length() - cut_after))
	voice.base_pitch = pitch_value

	if use_3d:
		var player := voice.player as AudioStreamPlayer3D
		player.stream = stream
		player.bus = event.bus
		player.volume_db = volume
		player.pitch_scale = pitch_value
		player.max_distance = event.max_distance
		player.unit_size = event.unit_size
		player.attenuation_model = event.attenuation as AudioStreamPlayer3D.AttenuationModel
		player.global_position = position
		player.play(start_position)
	else:
		var player := voice.player as AudioStreamPlayer
		player.stream = stream
		player.bus = event.bus
		player.volume_db = volume
		player.pitch_scale = pitch_value
		player.play(start_position)

	if cut_after > 0.0:
		var generation: int = voice.generation
		get_tree().create_timer(cut_after, true).timeout.connect(func() -> void:
			if voice.active and voice.generation == generation:
				_release_voice(voice)
		)

	if debug_log:
		print("Audio: ▶ %s (%s, %.1f dB)" % [id, "3D" if use_3d else "2D", volume])
	var handle := SoundHandle.new(self, voice, voice.generation)
	voice.handle_ref = weakref(handle)
	return handle


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
	var handle: SoundHandle = voice.handle_ref.get_ref() as SoundHandle if voice.handle_ref else null
	voice.active = false
	voice.follow = null
	voice.generation += 1
	if handle:
		handle.finished.emit() # terminó solo (no por stop())


## Para loops: si el audio no repite por sí mismo, se lo marca para que lo haga (sin el corte de volver a empezar a mano).
func _ensure_looping(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


# Usados por SoundHandle
func voice_is_active(voice: Voice, generation: int) -> bool:
	return voice.active and voice.generation == generation


func voice_stop(voice: Voice, generation: int, fade_time: float) -> void:
	if voice.generation == generation:
		_stop_voice(voice, fade_time)


func voice_get_position(voice: Voice, generation: int) -> float:
	if not voice_is_active(voice, generation):
		return 0.0
	var player: Node = voice.player
	return float(player.call("get_playback_position")) + AudioServer.get_time_since_last_mix()


func voice_get_length(voice: Voice, generation: int) -> float:
	if not voice_is_active(voice, generation):
		return 0.0
	var stream: AudioStream = voice.player.get("stream") as AudioStream
	return stream.get_length() if stream else 0.0


func voice_set_pitch(voice: Voice, generation: int, multiplier: float) -> void:
	if voice_is_active(voice, generation):
		voice.player.set("pitch_scale", maxf(voice.base_pitch * multiplier, 0.05))


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

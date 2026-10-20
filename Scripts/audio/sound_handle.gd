extends RefCounted
class_name SoundHandle

## Control sobre UNA reproducción puntual (lo devuelven Audio.play(), play_at(), play_on() y play_stream_*).
## Sirve para detener sonidos largos o en loop, y para consultarlos y ajustarlos mientras suenan (la
## canción de la radio, por ejemplo). Es seguro usarlo aunque el sonido ya haya terminado: si la voz fue
## reutilizada para otro sonido, el handle no la toca.

## El sonido terminó SOLO (llegó al final). No se emite si se lo detuvo con stop() ni si se cortó por
## límite de voces o por 'Cut After'.
signal finished

var _manager: Node
var _voice: RefCounted
var _generation: int = 0


func _init(manager: Node, voice: RefCounted, generation: int) -> void:
	_manager = manager
	_voice = voice
	_generation = generation


## ¿Sigue sonando este disparo?
func is_playing() -> bool:
	return is_instance_valid(_manager) and _manager.voice_is_active(_voice, _generation)


## Lo detiene, con un fundido opcional (segundos). No emite 'finished'.
func stop(fade_time: float = 0.0) -> void:
	if is_instance_valid(_manager):
		_manager.voice_stop(_voice, _generation, fade_time)


## Punto actual de reproducción, en segundos (0 si ya no suena).
func get_position() -> float:
	return _manager.voice_get_position(_voice, _generation) if is_instance_valid(_manager) else 0.0


## Duración total del audio que está sonando, en segundos (0 si ya no suena).
func get_length() -> float:
	return _manager.voice_get_length(_voice, _generation) if is_instance_valid(_manager) else 0.0


## Cambia la velocidad/tono mientras suena. 'multiplier' se aplica sobre el pitch del evento (1.0 = normal).
func set_pitch_scale(multiplier: float) -> void:
	if is_instance_valid(_manager):
		_manager.voice_set_pitch(_voice, _generation, multiplier)

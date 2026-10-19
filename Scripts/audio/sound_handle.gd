extends RefCounted
class_name SoundHandle

## Control sobre UNA reproducción puntual (lo devuelven Audio.play(), play_at() y play_on()).
## Sirve para detener sonidos largos o en loop. Es seguro usarlo aunque el sonido ya haya terminado:
## si la voz fue reutilizada para otro sonido, el handle no la toca.

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


## Lo detiene, con un fundido opcional (segundos).
func stop(fade_time: float = 0.0) -> void:
	if is_instance_valid(_manager):
		_manager.voice_stop(_voice, _generation, fade_time)

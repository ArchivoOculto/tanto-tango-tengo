extends Node3D
class_name SoundEmitter

## Componente para ubicar un sonido directamente en una ESCENA, sin escribir código: un zumbido en una
## farola, el goteo de una alcantarilla, el viento en una zona. Se pone como hijo del objeto y se elige el
## 'event_id' (el mismo id que usaría el código, ver SoundIds). Suena a través de Audio, así que respeta
## buses, variaciones y límites de voces como cualquier otro sonido.
##
## Con 'autoplay' arranca al entrar a la escena; el resto del tiempo se maneja con play() y stop().

@export var event_id: StringName = &""
## Reproducir automáticamente al entrar al árbol (para ambientes y loops).
@export var autoplay: bool = false
## true = el sonido sigue a este nodo si se mueve; false = queda en el punto donde empezó.
@export var follow_node: bool = true

var _handle: SoundHandle


func _ready() -> void:
	if autoplay:
		play()


func _exit_tree() -> void:
	stop(0.0)


func play() -> void:
	if event_id == &"":
		push_warning("SoundEmitter '%s': falta el event_id." % name)
		return
	stop(0.0)
	_handle = Audio.play_on(event_id, self) if follow_node else Audio.play_at(event_id, global_position)


func stop(fade_time: float = 0.0) -> void:
	if _handle != null:
		_handle.stop(fade_time)
		_handle = null


func is_playing() -> bool:
	return _handle != null and _handle.is_playing()

extends Resource
class_name SoundEvent

## Un EVENTO DE SONIDO: la "ficha" de un sonido del juego. El código nunca nombra archivos de audio, solo
## el id del evento (ver SoundIds y AudioManager): "reproducí player_jump". Qué suena de verdad (los .wav,
## el volumen, el pitch) se decide acá, en este recurso, sin tocar código.
##
## Cada evento es un archivo .tres en Resources/audio/events/<categoria>/<id>.tres. El gestor los carga
## solos al iniciar: para sumar un sonido NO hay que registrarlo en ningún lado.
##
## Un evento sin 'streams' es válido: no suena (queda pendiente de recibir su audio) y no da error.
## Ver Docs/sistema_de_audio.md.

## Identificador. Vacío = el nombre del archivo sin extensión (lo normal). Es lo que se usa en el código.
@export var id: StringName = &""
## Los audios. Con más de uno se elige uno al azar en cada disparo (variaciones: evita el efecto
## "ametralladora" de oír siempre la misma pisada).
@export var streams: Array[AudioStream] = []

@export_group("Mezcla")
## Bus por el que sale (ver AudioBuses). Los sliders de Opciones controlan Master, Music y SFX
## (Ambience, UI y Reverb cuelgan de SFX).
@export_enum("SFX", "UI", "Ambience", "Music", "Reverb") var bus: String = "SFX"
@export_range(-40.0, 12.0, 0.1, "suffix:dB") var volume_db: float = 0.0
## Variación aleatoria de volumen en cada disparo (± dB).
@export_range(0.0, 12.0, 0.1, "suffix:dB") var volume_variation_db: float = 0.0
@export_range(0.1, 4.0, 0.01) var pitch: float = 1.0
## Variación aleatoria del pitch en cada disparo (± fracción: 0.05 = ±5%).
@export_range(0.0, 0.5, 0.01) var pitch_variation: float = 0.0

@export_group("Reproducción")
## true = sonido 3D (se oye según la distancia al oído). Requiere reproducirse con Audio.play_at() o play_on();
## con Audio.play() suena plano.
@export var spatial: bool = false
## Distancia (m) a partir de la cual deja de oírse (0 = sin límite). Solo sonidos 3D.
@export_range(0.0, 200.0, 0.5, "suffix:m") var max_distance: float = 12.0
## Cuánto tarda en atenuarse con la distancia (más chico = se apaga antes). Solo sonidos 3D.
@export_range(0.05, 20.0, 0.05) var unit_size: float = 1.0
## Curva con que baja el volumen al alejarse. Solo sonidos 3D.
@export_enum("Inverse", "Inverse square", "Logarithmic", "Disabled") var attenuation: int = 0
## Empezar en un punto AL AZAR del audio (en vez de desde el principio). Sirve para tomar "pedacitos" de un
## audio largo, como el parpadeo de la lámpara. Se combina con 'Cut After'.
@export var random_start: bool = false
## Cortar el sonido a los N segundos (se elige un valor al azar entre mínimo y máximo). 0 = que suene hasta el final.
@export_range(0.0, 30.0, 0.01, "suffix:s") var cut_after_min: float = 0.0
@export_range(0.0, 30.0, 0.01, "suffix:s") var cut_after_max: float = 0.0
## Se repite hasta que alguien lo detenga (ambientes, zumbidos). Usar el handle que devuelve Audio.play*().
@export var loop: bool = false
## Máximo de voces simultáneas de ESTE evento; al pasarse se corta la más vieja. 0 = sin límite.
@export_range(0, 32) var max_voices: int = 4
## Tiempo mínimo (s) entre dos disparos: evita que muchos disparos casi simultáneos sumen volumen.
@export_range(0.0, 5.0, 0.01, "suffix:s") var cooldown: float = 0.0
## No repite la misma variación dos veces seguidas (si hay más de una).
@export var avoid_repeat: bool = true

@export_group("Documentación")
## Para qué sirve y cuándo suena. Lo ve quien lo abre en el editor.
@export_multiline var description: String = ""

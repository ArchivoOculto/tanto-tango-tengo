extends RefCounted
class_name AudioBuses

## Nombres de los buses de audio del juego (Resources/audio/default_bus_layout.tres).
## Usarlos en código en vez de strings sueltos: AudioBuses.MUSIC, AudioBuses.SFX...
##
## Jerarquía (cada bus envía a su padre):
##
##   Master
##   ├── Music      música y canciones (la radio, temas del juego)
##   └── SFX        efectos de sonido
##       ├── Ambience   ambiente continuo (lluvia, viento, zumbidos)
##       ├── UI         sonidos de menús e interfaz
##       └── Reverb     efectos que necesitan reverberación (farolas)
##
## Los sliders de Opciones controlan Master, Music y SFX; como Ambience, UI y Reverb cuelgan de SFX,
## el slider de SFX los escala a todos. Para sumar un bus (ej: Voice): agregarlo en el layout, una
## constante acá y, si hace falta, un slider en el menú de opciones.

const MASTER: StringName = &"Master"
const MUSIC: StringName = &"Music"
const SFX: StringName = &"SFX"
const AMBIENCE: StringName = &"Ambience"
const UI: StringName = &"UI"
const REVERB: StringName = &"Reverb"

## Buses con slider de volumen en Opciones, en orden: [bus, texto del menú].
const OPTION_SLIDERS: Array = [
	[&"Master", "general"],
	[&"Music", "música"],
	[&"SFX", "efectos"],
]

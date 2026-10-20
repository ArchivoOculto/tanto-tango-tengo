# Sistema de audio — Tanto Tango Tengo

Guía para trabajar el sonido en equipo. Resumen: **el código pide un evento por nombre, y el equipo de sonido
decide qué suena en ese evento**. Nadie toca el trabajo del otro.

```
 Programación                        Sonido
 ────────────                        ──────
 Audio.play(SoundIds.PLAYER_JUMP) →  Resources/audio/events/player/player_jump.tres
                                      ├─ streams:  player_jump_01.wav, _02.wav, _03.wav
                                      ├─ bus, volumen, pitch, variaciones
                                      └─ 3D o plano, límite de voces, cooldown
```

## Los cuatro conceptos

| Pieza | Qué es | Dónde |
|---|---|---|
| **Buses** | Mezcla: `Master → Music, SFX → (Ambience, UI, Reverb)`. Los sliders de Opciones controlan Master, Music y SFX. | `Resources/audio/default_bus_layout.tres`, `AudioBuses` |
| **SoundEvent** | La "ficha" de un sonido: audios, bus, volumen, pitch, 3D, loop, límite de voces. Es un archivo `.tres`. | `Resources/audio/events/<categoria>/<id>.tres` |
| **SoundIds** | Constantes con los ids (`SoundIds.PLAYER_JUMP`). Evitan errores de tipeo. | `Scripts/audio/sound_ids.gd` |
| **Audio** | Autoload que reproduce: pool de reproductores, variaciones, cooldown, límite de voces. | `Scripts/audio/audio_manager.gd` |

Más `SoundEmitter` (nodo para poner un sonido directo en una escena) y `SoundHandle` (control de un sonido en curso).

## Para PROGRAMACIÓN: reproducir un sonido

```gdscript
Audio.play(SoundIds.UI_MENU_CONFIRM)                    # plano: UI, avisos
Audio.play_at(SoundIds.PLAYER_LAND, global_position)    # 3D en un punto fijo
Audio.play_on(SoundIds.ENEMY_HURT, self)                # 3D que sigue a un nodo

var buzz := Audio.play_on(SoundIds.FAROLITO_BUZZ_LOOP, self)   # loops: guardar el handle...
buzz.stop(0.5)                                                 # ...y detenerlo (fade de 0.5 s)

Audio.play_music(SoundIds.MUS_MENU_THEME, 1.5)          # música con crossfade
Audio.stop_all(AudioBuses.UI)                           # cortar todo un bus
```

Reglas:
1. **Nunca** poner un `AudioStreamPlayer` suelto ni cargar un `.wav` desde código. Todo pasa por `Audio`.
2. Se puede llamar a un evento **antes** de que exista el audio: si el `.tres` está vacío, no suena y no da error.
3. Un id que no existe avisa UNA vez en la consola (`Audio: no existe el evento…`) y no rompe nada.
4. Sonido que se repite mucho (pisadas, UI): no hace falta controlarlo en código. El evento ya limita voces
   (`max_voices`) y tiene `cooldown`.
5. Para un sonido fijo en una escena (zumbido, goteo, viento) usar el nodo **`SoundEmitter`** con `event_id` y `autoplay`.
6. Depurar: `Audio.debug_log = true` imprime cada sonido que se dispara.

## Para SONIDO: entregar un sonido

1. Mirar `Docs/lista_de_sonidos.txt`: cada sonido tiene su **ID**, los **nombres de archivo** esperados, formato,
   carpeta y cuándo suena.
2. Exportar los archivos con ese nombre (`player_jump_01.wav`, `player_jump_02.wav`…) a la carpeta indicada
   (`Assets/Audio/SFX/player/`).
3. En Godot, abrir el evento (`Resources/audio/events/player/player_jump.tres`) y **arrastrar los archivos al campo
   `Streams`**.
4. Ajustar en el mismo evento: `Volume Db`, `Pitch Variation`, etc. Probar el juego. Listo; no hay que avisar a programación.

Para crear un sonido NUEVO (que no esté en la lista): ver "Agregar un sonido nuevo".

### Formatos
- Efectos cortos: `.wav` PCM 16 bit, 44.1 kHz. Loops, ambientes y música: `.ogg`.
- Sonidos 3D (`Spatial` activado): **mono**. Los planos (UI) pueden ser estéreo.
- Loops: activar **Loop Mode: Forward** en la pestaña Import de Godot y marcar `Loop` en el evento.

## Agregar un sonido nuevo (5 pasos)

1. **Nombre**: `<categoria>_<objeto>_<accion>` en minúsculas, inglés (`enemy_charge`). Archivos: `enemy_charge_01.wav`…
2. **Evento**: en Godot, clic derecho en `Resources/audio/events/<categoria>/` → *Create New → Resource → SoundEvent*,
   guardarlo como `enemy_charge.tres`. Se carga solo: no hay que registrarlo en ningún lado.
3. **Constante**: agregar `const ENEMY_CHARGE: StringName = &"enemy_charge"` en `sound_ids.gd`.
4. **Llamada**: en el script donde ocurre la acción, `Audio.play_on(SoundIds.ENEMY_CHARGE, self)`.
5. **Lista**: sumarlo a `Docs/lista_de_sonidos.txt` para que el resto del equipo lo vea.

## Estructura de carpetas

```
Assets/Audio/
├── SFX/<categoria>/    player, enemy, farolito, radio, cassette, object, door, puzzle, level
├── UI/                 menús e interfaz
├── Ambience/           ambientes en loop
└── Music/              música y canciones de los cassettes
Resources/audio/
├── default_bus_layout.tres
└── events/<categoria>/<id>.tres
Scripts/audio/          audio_manager, sound_event, sound_handle, sound_emitter, sound_ids
```

## Qué decide cada campo del SoundEvent

| Campo | Para qué |
|---|---|
| `Streams` | Los audios. Con varios, elige uno al azar cada vez (sin repetir el anterior). |
| `Bus` | SFX, UI, Ambience, Music o Reverb. Define qué slider lo controla. |
| `Volume Db` / `Volume Variation Db` | Volumen base y cuánto varía al azar. |
| `Pitch` / `Pitch Variation` | Tono base y variación (0.05 = ±5%): hace que repetidos suenen distinto. |
| `Spatial`, `Max Distance`, `Unit Size`, `Attenuation` | Sonido 3D: a qué distancia se apaga (0 = nunca), qué tan rápido y con qué curva. |
| `Random Start`, `Cut After Min/Max` | Tomar un "pedacito": empezar en un punto al azar de un audio largo y/o cortarlo a los N segundos (el parpadeo de las farolas, el golpe). |
| `Loop` | Se repite hasta que se detenga con el handle. |
| `Max Voices` | Cuántas copias del mismo evento pueden sonar a la vez (corta la más vieja). |
| `Cooldown` | Tiempo mínimo entre disparos. Anti-spam. |
| `Description` | Documentación: para qué es y desde dónde se dispara. |

## Rendimiento (PCs modestas)

- **Pool fijo**: 12 reproductores planos y 20 3D creados una sola vez al iniciar; no se instancian nodos mientras se juega.
- **Límites**: voces por evento y cooldown evitan decenas de sonidos superpuestos.
- Si el pool se agota, se corta el sonido no-loop más viejo (nunca se acumulan nodos).
- Los loops largos y la música van en `.ogg` (streaming); los efectos cortos en `.wav` (sin costo de decodificar).
- Cuidado con los `.wav` largos: pesan mucho en memoria. Todo lo de más de ~3 s, a `.ogg`.

## Audio dinámico (cuando el audio no es fijo)

Algunos sonidos no tienen un archivo propio: la canción de la radio depende del cassette puesto. Para eso:

```gdscript
var music := Audio.play_stream_on(SoundIds.RADIO_TAPE_MUSIC, track, visual_node, start_at_seconds)
music.finished.connect(_on_track_finished)   # terminó SOLO (no si se la detuvo con stop())
music.get_position()                         # en qué segundo va (para recordarlo en el cassette)
music.set_pitch_scale(1.1)                   # velocidad/tono en vivo (se multiplica por el pitch del evento)
music.stop(0.5)                              # fundido hasta el silencio
```

El **evento** (`radio_tape_music`) define cómo suena (bus Music, volumen, 3D desde la radio, atenuación) y quien
llama aporta el audio. Así la mezcla sigue en manos de sonido aunque el archivo sea dinámico.

## Estado de la migración

| Sonido | Antes | Ahora |
|---|---|---|
| Lluvia | `AudioStreamPlayer3D` en el nivel | `SoundEmitter` "RainSound" (autoplay) + evento `amb_rain_loop` |
| Canción del cassette | `AudioStreamPlayer3D` dentro de la radio | `Audio.play_stream_on()` + evento `radio_tape_music` |
| Parpadeo de farola | reproductor propio + exports en cada farola | evento `farolito_flicker` (Random Start + Cut After) |
| Golpe de farola | reproductor propio + exports en cada farola | evento `farolito_hit` (pitch ±5%, corte 0.33–0.55 s) |

Los valores de volumen, atenuación, pitch y recortes que tenían quedaron copiados en cada evento. Ya no se
ajustan en las escenas sino en `Resources/audio/events/`.

## Qué falta hacer (programación)

**Conectar las llamadas** del resto de los sonidos en los scripts. La columna "Se dispara" de
`lista_de_sonidos.txt` indica archivo y función de cada una.

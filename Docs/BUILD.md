# Builds de beta: Web (itch.io) y Windows

Guía rápida para exportar y repartir el juego. Los números son de la exportación `release` con Godot 4.7.

| Build | Archivos | Descarga real |
|---|---|---|
| **Web** (solo `WebLevel`) | `index.pck` 9.8 MB + `index.wasm` 37.7 MB | **~18 MB** (gzip) / ~16 MB (brotli); zip para itch: 18 MB |
| **Windows** | un solo `.exe` con el `.pck` embebido: 140 MB | zip: 62 MB |

Tiempo de la **primera** carga web (después el navegador la guarda en caché): ~6 s a 25 Mbps, ~15 s a 10 Mbps.
El `.wasm` es el motor y no se puede achicar sin compilar una plantilla propia: 8–10 MB de la descarga son suyos.

## Una vez

1. Godot **4.7** y sus plantillas de exportación: `Editor > Manage Export Templates > Download and Install`.
2. Los presets `Web` y `Windows` ya están en `export_presets.cfg`. Exportan a `build/` (ignorada por git).

## Exportar

Desde el editor: `Project > Export…`, elegir el preset y **Export Project** (desmarcar "Export With Debug").

Por consola (sirve para scripts o CI):

```
godot --headless --export-release "Web"     build/web/index.html
godot --headless --export-release "Windows" build/windows/TantoTangoTengo.exe
```

## Web en itch.io

1. Comprimir **el contenido** de `build/web/` (que `index.html` quede en la raíz del zip, no dentro de una carpeta).
2. Nuevo proyecto en itch.io: *Kind of project* = **HTML**; subir el zip y marcar **"This file will be played in the browser"**.
3. *Embed options*: tamaño manual **845 x 480**, **Fullscreen button** activado, *Mobile friendly* desactivado.
   No hace falta activar *SharedArrayBuffer*: la exportación es de un solo hilo (`thread_support=false`) y no necesita cabeceras especiales.
4. Para un grupo cerrado: *Visibility & access* = **Restricted** (con contraseña o por usuarios) o **Draft** (URL secreta).
5. Alternativa por consola, con [butler](https://itch.io/docs/butler/): `butler push build/web usuario/juego:web`.

Funciona en Chrome, Edge y Firefox de escritorio. **No** está pensada para celulares (las texturas se exportan solo para escritorio).

## Windows

Comprimir `TantoTangoTengo.exe` en un zip y repartirlo (o `butler push build/windows usuario/juego:windows`).
El `.exe` no está firmado: Windows SmartScreen va a avisar. Para abrirlo: **Más información > Ejecutar de todas formas**.

Si la tarjeta gráfica no soporta D3D12, el juego prueba solo con Vulkan y después con OpenGL (el modo de la web).

## La build web contiene solo `WebLevel`

El preset `Web` exporta **únicamente** `Scenes/levels/WebLevel.tscn` y lo que usa (`export_filter="scenes"`), y el ajuste
`application/run/main_scene.web` hace que la web arranque directo en esa escena (en PC sigue arrancando el menú principal).
No entran `terrain.tscn`, el menú principal, las otras canciones ni la lluvia de 5.9 MB: la web usa audio propio más liviano
(`Assets/Audio/Web/`: lluvia mono 2.2 MB y la canción del cassette en Ogg, 3 MB).

Este modo tiene una trampa: **Godot no sigue solo todas las dependencias**. Hay que declarar a mano lo que no está en una escena:

| Qué | Dónde se declara en el preset |
|---|---|
| Escenas (y todo lo que usan) | `export_files` |
| Todos los scripts, shaders, el layout de buses y los eventos de audio con sus sonidos | `include_filter` |

Si falta algo el juego arranca roto en la web (por ejemplo, `Could not find type...` o sonidos mudos). Por eso hay un verificador:

```
godot --headless --script res://tools/check_web_export.gd
```

Calcula qué entra al `.pck` y avisa si algo necesita un archivo que quedó afuera, con la línea exacta a agregar al preset.
**Córrelo siempre que sumes un sonido a un evento de audio, un `preload` nuevo en un autoload o una escena nueva que use la web.**

## Web vs PC: qué cambia

La web usa el renderer **Compatibility** (OpenGL), que no tiene tres cosas que el nivel usa en PC. `RenderProfile`
(autoload) las reemplaza solo, sin tocar las escenas:

| En PC (Forward+) | En web / Compatibility |
|---|---|
| Niebla volumétrica y conos de luz de los farolitos | No existe: queda la niebla de profundidad, oscurecida para que la noche se vea parecida |
| Lluvia con estelas (`trail_enabled`) | Rayitas alineadas con la velocidad de cada gota (en `WebLevel` ya están hechas en la escena) |
| `FogVolume` | Se ocultan |

Los **conos de luz** de los farolitos son lo único que no se reemplaza: la web se ve algo más plana. En la consola aparecen
tres avisos esperables (`Volumetric fog is only available…`, `…does not support particle trails`, `shader type fog…`).

## Antes de repartir la beta

- Jugar una vez cada build entera en una máquina que no sea la de desarrollo.
- Pedir a los testers que, si algo falla, manden captura + el log: en Windows
  `%APPDATA%\Godot\app_userdata\TantoTangoTengo\logs\godot.log`; en web, la consola del navegador (F12).
- `WebLevel` todavía no tiene menú de pausa (Esc), así que en la web no se puede apagar el filtro CRT ni cambiar el volumen.

## Cómo se optimizó `WebLevel`

Medido con el mismo procedimiento antes y después (renderer Compatibility, GL por software: sirve para comparar, no como FPS reales):
**~300 ms → ~115 ms por cuadro, 45 → 25 draw calls, 7.4 mil → 4 mil triángulos.**

- **Sin cielo procedural:** fondo de color y luz ambiente de color (calibrada contra el cielo: error medio de 1.9/255).
- **Luz direccional apagada:** aportaba ~1 % (color 0.0126) y le costaba cuatro pasadas de sombras al renderer.
- **Lluvia nativa para Compatibility:** rayitas en vez de estelas, 100 partículas.
- **Filtro CRT más liviano:** con la aberración cromática base en 0 (solo en Compatibility) y sin efectos activos hace una lectura de pantalla por píxel en vez de cuatro.
- **Audio web:** ver arriba.

## Audio maestro

`Sources/` es ignorada por Godot (`.gdignore`): ahí viven los archivos sin comprimir que no se exportan.
`Sources/Audio/rain_sound.wav` es el maestro de la lluvia; el juego usa `Assets/Audio/rain_sound.ogg` (Vorbis calidad 4, 128 kbps),
que pesa 5.9 MB contra los 14 MB de la versión WAV comprimida con QOA. Para regenerarlo:

```
ffmpeg -i Sources/Audio/rain_sound.wav -c:a libvorbis -q:a 4 Assets/Audio/rain_sound.ogg
```

El audio de la versión web (solo lo usa `WebLevel`) se regenera así:

```
ffmpeg -i Sources/Audio/rain_sound.wav -af "pan=mono|c0=0.5*c0+0.5*c1" -ar 32000 -c:a libvorbis -q:a 0 Assets/Audio/Web/rain_sound_web.ogg
ffmpeg -i "Assets/Audio/Cassette tracks/metrovias.mp3" -c:a libvorbis -q:a 3 Assets/Audio/Web/metrovias_web.ogg
```

La lluvia web es mono porque suena desde un emisor 3D (que de todos modos la mezcla a mono). El evento `amb_rain_loop_web`
es la versión web de `amb_rain_loop`: el preset excluye la de PC para no empaquetar los 5.9 MB.

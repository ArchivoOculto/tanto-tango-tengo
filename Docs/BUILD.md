# Builds de beta: Web (itch.io) y Windows

Guía rápida para exportar y repartir el juego. Los números son de la exportación `release` con Godot 4.7.

| Build | Archivos | Descarga real |
|---|---|---|
| **Web** | `index.pck` 29.9 MB + `index.wasm` 37.7 MB | **~36 MB** (gzip) / ~34 MB (brotli); zip para itch: 36 MB |
| **Windows** | un solo `.exe` con el `.pck` embebido: 140 MB | zip: 62 MB |

Tiempo de la **primera** carga web (después el navegador la guarda en caché): ~12 s a 25 Mbps, ~30 s a 10 Mbps.

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

## Web vs PC: qué cambia

La web usa el renderer **Compatibility** (OpenGL), que no tiene tres cosas que el nivel usa en PC. `RenderProfile`
(autoload) las reemplaza solo, sin tocar las escenas:

| En PC (Forward+) | En web / Compatibility |
|---|---|
| Niebla volumétrica y conos de luz de los farolitos | No existe: queda la niebla de profundidad, oscurecida para que la noche se vea parecida |
| Lluvia con estelas (`trail_enabled`) | Rayitas alineadas con la velocidad de cada gota |
| `FogVolume` | Se ocultan |

Los **conos de luz** de los farolitos son lo único que no se reemplaza: la web se ve algo más plana. En la consola aparecen
tres avisos esperables (`Volumetric fog is only available…`, `…does not support particle trails`, `shader type fog…`).

## Antes de repartir la beta

- Jugar una vez cada build entera en una máquina que no sea la de desarrollo.
- Pedir a los testers que, si algo falla, manden captura + el log: en Windows
  `%APPDATA%\Godot\app_userdata\TantoTangoTengo\logs\godot.log`; en web, la consola del navegador (F12).
- Si alguien tiene lag en la web, probar apagar **filtro crt** en Opciones (es lo más caro de la imagen).

## Audio maestro

`Sources/` es ignorada por Godot (`.gdignore`): ahí viven los archivos sin comprimir que no se exportan.
`Sources/Audio/rain_sound.wav` es el maestro de la lluvia; el juego usa `Assets/Audio/rain_sound.ogg` (Vorbis calidad 4, 128 kbps),
que pesa 5.9 MB contra los 14 MB de la versión WAV comprimida con QOA. Para regenerarlo:

```
ffmpeg -i Sources/Audio/rain_sound.wav -c:a libvorbis -q:a 4 Assets/Audio/rain_sound.ogg
```

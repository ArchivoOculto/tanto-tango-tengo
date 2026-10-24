extends CanvasLayer

## Autoload "ScreenFX": filtro CRT a pantalla completa (shader Assets/Shaders/crt_screen.gdshader).
##
##  - Se prende y apaga con GameSettings (opción "filtro crt").
##  - CAPA: el filtro lee todo lo que se dibuja en capas MENORES que la suya, así que va por debajo de la UI
##    de juego (10, avisos de objetos), la mirilla (100), las barras 4:3 (126), el inventario y la pausa (127),
##    el fundido (128) y los mensajes (129): todo eso se ve nítido. Solo se filtran el mundo 3D y los Control
##    sueltos de la capa 0 (por ejemplo, el menú principal).
##  - BARRAS 4:3: al activarse (CameraDirector.letterbox_changed) la "ventana" del tubo se anima hasta la
##    imagen 4:3 con la misma curva y duración que las barras (ver LetterboxController), así la curvatura y la
##    viñeta se calculan sobre lo que se ve y no sobre la pantalla entera.
##  - PULSO: warp_pulse() distorsiona el filtro un instante (lo usan los warps).
##  - APAGADO: power_off() apaga el tubo como un televisor viejo (la imagen se aplasta en una línea, la línea en un
##    punto) y power_on() lo enciende al revés. GLITCH: glitch_out() pierde la señal (bandas que se desgarran, color
##    que se separa, nieve) y deja la pantalla en negro. Si el filtro CRT está apagado en opciones, los tres caen a un
##    fundido a negro común (WarpManager.fade_out), porque sin filtro no hay tubo que apagar.
##  - DAÑO: damage_flash() enciende una viñeta roja en los bordes y separa los colores un instante. La viñeta se
##    dibuja en su propia capa (VIGNETTE_LAYER), así se ve también con el filtro apagado.
##
## Debe ir DESPUÉS de CameraDirector y GameSettings en la lista de autoloads.

const FILTER_LAYER: int = 5
const SHADER: Shader = preload("res://Assets/Shaders/crt_screen.gdshader")
const TARGET_ASPECT: float = 4.0 / 3.0 ## mismo valor que LetterboxController.TARGET_ASPECT
const FULL_RECT: Vector4 = Vector4(0.0, 0.0, 1.0, 1.0)
const MIN_PULSE_TIME: float = 0.25
const VIGNETTE_LAYER: int = 6 ## encima del filtro y debajo de la UI de juego (10)
const VIGNETTE_SHADER: Shader = preload("res://Assets/Shaders/damage_vignette.gdshader")
const DAMAGE_ATTACK: float = 0.06 ## s que tarda en llegar al máximo
const DAMAGE_DECAY: float = 0.7 ## s que tarda la viñeta en apagarse
const DAMAGE_CHROMA_PX: float = 6.0 ## separación de color máxima al recibir un golpe (px)
const DAMAGE_CHROMA_DECAY: float = 0.4

var _rect: ColorRect
var _material: ShaderMaterial
var _view_rect: Vector4 = FULL_RECT
var _rect_tween: Tween
var _pulse_tween: Tween
var _power_tween: Tween
var _damage_tween: Tween
var _chroma_tween: Tween
var _vignette_rect: ColorRect
var _vignette_material: ShaderMaterial
var _blackout: bool = false ## el tubo quedó apagado a propósito (power_off / glitch_out) hasta el próximo power_on


func _ready() -> void:
	layer = FILTER_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS # los warps y el pulso también corren con el juego en pausa

	_material = ShaderMaterial.new()
	_material.shader = SHADER

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # no le roba clics a la UI
	_rect.material = _material
	add_child(_rect)

	_build_vignette()
	_set_view_rect(_rect_for(CameraDirector.is_letterbox_active()))
	CameraDirector.letterbox_changed.connect(_on_letterbox_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)

	GameSettings.crt_filter_changed.connect(_apply_enabled)
	_apply_enabled(GameSettings.is_crt_filter())


## Distorsiona el filtro: sube mientras la pantalla se funde a negro y baja, más lento, al revelar el destino.
## 'fade_duration' es el fundido del warp (WarpZone3D.fade_duration).
func warp_pulse(fade_duration: float) -> void:
	if not _rect.visible:
		return # filtro apagado: nada que animar
	var rise: float = maxf(fade_duration, MIN_PULSE_TIME)
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_method(_set_pulse, 0.0, 1.0, rise).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_pulse_tween.tween_method(_set_pulse, 1.0, 0.0, rise * 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Apaga el tubo como un televisor viejo: la imagen se aplasta en una línea brillante, la línea se encoge hasta un
## punto y el punto se apaga. Termina en negro y ahí se queda (ver power_on). Se puede esperar con await.
func power_off(duration: float = 0.7) -> void:
	if not _rect.visible:
		await WarpManager.fade_out(duration)
		return
	_blackout = true
	_kill(_power_tween)
	_power_tween = create_tween()
	_power_tween.tween_method(_set_power, 1.0, 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _power_tween.finished


## Pierde la señal: el glitch crece hasta el máximo y se corta a negro (que ahí se queda, ver power_on).
## Se puede esperar con await.
func glitch_out(duration: float = 0.9) -> void:
	if not _rect.visible:
		await WarpManager.fade_out(duration)
		return
	_blackout = true
	_kill(_power_tween)
	_power_tween = create_tween()
	_power_tween.tween_method(_set_glitch, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_power_tween.tween_callback(func() -> void:
		_set_power(0.0) # corte a negro
		_set_glitch(0.0))
	await _power_tween.finished


## Enciende el tubo desde el negro (el apagado al revés: un punto, una línea, la imagen). 'delay' espera ese
## tiempo antes de empezar (en tiempo real); sirve para dejar que termine un cambio de escena. Sin parámetros
## distintos de cero solo devuelve el tubo a su estado normal.
func power_on(duration: float = 0.6, delay: float = 0.0) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay, true, false, true).timeout
	_blackout = false
	_kill(_power_tween)
	if duration <= 0.0 or not _rect.visible:
		_set_power(1.0)
		_set_glitch(0.0)
		return
	_set_glitch(0.0)
	_power_tween = create_tween()
	_power_tween.tween_method(_set_power, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _power_tween.finished


## Golpe al jugador: viñeta roja en los bordes (también con el filtro apagado) y un pico de aberración cromática.
## 'strength' va de 0 a 1.
func damage_flash(strength: float = 1.0) -> void:
	strength = clampf(strength, 0.0, 1.0)
	# viñeta: sube de golpe y se apaga más despacio
	_kill(_damage_tween)
	_damage_tween = create_tween()
	_damage_tween.tween_method(_set_damage_vignette, 0.0, strength, DAMAGE_ATTACK) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_damage_tween.tween_method(_set_damage_vignette, strength, 0.0, DAMAGE_DECAY) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# separación de color: llega de golpe y baja rápido (tween aparte, para que corra a la vez)
	_kill(_chroma_tween)
	_chroma_tween = create_tween()
	_chroma_tween.tween_method(_set_chroma_boost, DAMAGE_CHROMA_PX * strength, 0.0, DAMAGE_CHROMA_DECAY) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _apply_enabled(enabled: bool) -> void:
	_rect.visible = enabled # apagado, no se lee la pantalla: cero costo
	if enabled and not _blackout:
		_set_power(1.0) # por si quedó a medias de un efecto


func _kill(tween: Tween) -> void:
	if tween and tween.is_valid():
		tween.kill()


func _set_power(amount: float) -> void:
	_material.set_shader_parameter("power", amount)


func _set_glitch(amount: float) -> void:
	_material.set_shader_parameter("glitch", amount)


func _set_chroma_boost(px: float) -> void:
	_material.set_shader_parameter("chroma_boost", px)


func _set_damage_vignette(amount: float) -> void:
	_vignette_material.set_shader_parameter("intensity", amount)


## Capa propia de la viñeta de daño: por encima del filtro CRT, por debajo de la UI de juego.
func _build_vignette() -> void:
	var vignette_layer := CanvasLayer.new()
	vignette_layer.name = "DamageVignette"
	vignette_layer.layer = VIGNETTE_LAYER
	add_child(vignette_layer)

	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = VIGNETTE_SHADER

	_vignette_rect = ColorRect.new()
	_vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.material = _vignette_material
	vignette_layer.add_child(_vignette_rect)


func _set_pulse(amount: float) -> void:
	_material.set_shader_parameter("pulse", amount)


# ---------------------------------------------------------------- VENTANA 4:3

func _on_letterbox_changed(active: bool, duration: float) -> void:
	if _rect_tween and _rect_tween.is_valid():
		_rect_tween.kill()
	var target: Vector4 = _rect_for(active)
	if duration <= 0.0:
		_set_view_rect(target)
		return
	# Misma curva que LetterboxController._animate_bars para que el borde de la ventana siga al de la barra.
	_rect_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_rect_tween.tween_method(_set_view_rect, _view_rect, target, duration)


func _on_viewport_resized() -> void:
	if _rect_tween and _rect_tween.is_valid():
		_rect_tween.kill()
	_set_view_rect(_rect_for(CameraDirector.is_letterbox_active()))


func _set_view_rect(rect: Vector4) -> void:
	_view_rect = rect
	_material.set_shader_parameter("view_rect", rect)
	_vignette_material.set_shader_parameter("view_rect", rect)


## Ventana (x, y, ancho, alto, en UV de pantalla) de la imagen visible: toda la pantalla, o el 4:3 centrado.
func _rect_for(letterbox: bool) -> Vector4:
	if not letterbox:
		return FULL_RECT
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return FULL_RECT
	var aspect: float = size.x / size.y
	if is_equal_approx(aspect, TARGET_ASPECT):
		return FULL_RECT # ya es 4:3, no hay barras
	if aspect > TARGET_ASPECT:
		var width: float = TARGET_ASPECT / aspect # pillarbox: barras a los costados
		return Vector4((1.0 - width) * 0.5, 0.0, width, 1.0)
	var height: float = aspect / TARGET_ASPECT # letterbox: barras arriba y abajo
	return Vector4(0.0, (1.0 - height) * 0.5, 1.0, height)

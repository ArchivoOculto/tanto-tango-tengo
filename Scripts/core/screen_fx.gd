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
##
## Debe ir DESPUÉS de CameraDirector y GameSettings en la lista de autoloads.

const FILTER_LAYER: int = 5
const SHADER: Shader = preload("res://Assets/Shaders/crt_screen.gdshader")
const TARGET_ASPECT: float = 4.0 / 3.0 ## mismo valor que LetterboxController.TARGET_ASPECT
const FULL_RECT: Vector4 = Vector4(0.0, 0.0, 1.0, 1.0)
const MIN_PULSE_TIME: float = 0.25

var _rect: ColorRect
var _material: ShaderMaterial
var _view_rect: Vector4 = FULL_RECT
var _rect_tween: Tween
var _pulse_tween: Tween


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


func _apply_enabled(enabled: bool) -> void:
	_rect.visible = enabled # apagado, no se lee la pantalla: cero costo


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

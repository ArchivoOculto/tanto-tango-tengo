extends Node

## Autoload (Project Settings > Autoload, nombre "LetterboxController").
##
## Escucha CameraDirector.zone_changed y anima barras negras que recortan la
## pantalla a una relación de aspecto 4:3 cuando la CameraZone3D activa tiene
## 'force_4_3 = true'. Al pasar de una zona 4:3 a una que no lo es, anima la
## transición inversa.
##
## Las barras CRECEN desde el borde de la pantalla hacia el centro (o se
## retraen desde el centro hacia el borde) — no se deslizan desde afuera de
## la pantalla. Detecta en tiempo real si corresponde pillarbox (barras
## verticales, lo normal en monitores 16:9) o letterbox (barras horizontales),
## según la resolución real, y se recalcula sola si la ventana cambia de
## tamaño mientras está activa.

const TARGET_ASPECT: float = 4.0 / 3.0

@export var default_transition_duration: float = 0.6 ## Se usa solo si la zona relevante no tiene su propio 'aspect_transition_duration'
@export var bar_color: Color = Color.BLACK

var _is_active: bool = false
var _tween: Tween

var _bar_left: ColorRect
var _bar_right: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect


func _ready() -> void:
	_build_bars()
	CameraDirector.zone_changed.connect(_on_zone_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_zone_changed(previous_zone: CameraZone3D, new_zone: CameraZone3D) -> void:
	var should_be_active: bool = new_zone != null and new_zone.force_4_3
	if should_be_active == _is_active:
		return

	_is_active = should_be_active

	# Al activar usamos la duración de la zona nueva; al desactivar, la de la
	# zona que se está abandonando (puede haber sido liberada por un cambio
	# de escena, por eso el chequeo de validez).
	var relevant_zone: CameraZone3D = new_zone if should_be_active else previous_zone
	var duration: float = default_transition_duration
	if is_instance_valid(relevant_zone):
		duration = relevant_zone.aspect_transition_duration

	_animate_bars(_is_active, duration)


func _on_viewport_resized() -> void:
	if _is_active:
		_animate_bars(true, 0.0) # recalcula tamaños al instante, sin re-animar


func _animate_bars(active: bool, duration: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return

	var current_aspect: float = viewport_size.x / viewport_size.y
	if is_equal_approx(current_aspect, TARGET_ASPECT):
		return # la pantalla ya es 4:3, no hacen falta barras

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_OUT)

	if current_aspect > TARGET_ASPECT:
		# Pantalla más ancha que 4:3 -> pillarbox (barras verticales)
		var bar_width: float = (viewport_size.x - TARGET_ASPECT * viewport_size.y) * 0.5
		_tween.tween_property(_bar_left, "offset_right", bar_width if active else 0.0, duration)
		_tween.tween_property(_bar_right, "offset_left", -bar_width if active else 0.0, duration)
	else:
		# Pantalla más angosta que 4:3 -> letterbox (barras horizontales)
		var bar_height: float = (viewport_size.y - viewport_size.x / TARGET_ASPECT) * 0.5
		_tween.tween_property(_bar_top, "offset_bottom", bar_height if active else 0.0, duration)
		_tween.tween_property(_bar_bottom, "offset_top", -bar_height if active else 0.0, duration)


# --- SETUP INTERNO ---
func _build_bars() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 127 # justo debajo del fundido de WarpManager (128)
	add_child(layer)

	_bar_left = _make_bar(Control.PRESET_LEFT_WIDE)
	_bar_left.offset_right = 0.0
	layer.add_child(_bar_left)

	_bar_right = _make_bar(Control.PRESET_RIGHT_WIDE)
	_bar_right.offset_left = 0.0
	layer.add_child(_bar_right)

	_bar_top = _make_bar(Control.PRESET_TOP_WIDE)
	_bar_top.offset_bottom = 0.0
	layer.add_child(_bar_top)

	_bar_bottom = _make_bar(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.offset_top = 0.0
	layer.add_child(_bar_bottom)


func _make_bar(preset: Control.LayoutPreset) -> ColorRect:
	var bar: ColorRect = ColorRect.new()
	bar.color = bar_color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(preset)
	return bar

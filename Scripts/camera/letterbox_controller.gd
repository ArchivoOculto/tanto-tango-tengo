extends Node

## Autoload (Project Settings > Autoload, nombre "LetterboxController").
##
## Escucha CameraDirector.letterbox_changed y anima barras negras que recortan
## la pantalla a una relación de aspecto 4:3. CameraDirector decide cuándo
## corresponde (zona activa con 'force_4_3 = true' o modo fusil activo); este
## script solo las dibuja.
##
## Las barras CRECEN desde el borde de la pantalla hacia el centro (o se
## retraen desde el centro hacia el borde) — no se deslizan desde afuera de
## la pantalla. Detecta en tiempo real si corresponde pillarbox (barras
## verticales, lo normal en monitores 16:9) o letterbox (barras horizontales),
## según la resolución real, y se recalcula sola si la ventana cambia de
## tamaño mientras está activa.

const TARGET_ASPECT: float = 4.0 / 3.0

@export var bar_color: Color = Color.BLACK

var _is_active: bool = false
var _tween: Tween

var _bar_left: ColorRect
var _bar_right: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect


func _ready() -> void:
	_build_bars()
	CameraDirector.letterbox_changed.connect(_on_letterbox_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_letterbox_changed(active: bool, duration: float) -> void:
	_is_active = active
	_animate_bars(active, duration)


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
	layer.layer = 126 # bajo el inventario (127) y el fundido de WarpManager (128); sobre la UI de juego
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

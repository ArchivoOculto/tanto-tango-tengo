extends Node3D
class_name InteractablePicture

## Se emite al abrir la imagen (empieza la inspección).
signal opened
## Se emite al cerrarla.
signal closed

## Nombre que se muestra en el menú al abrir la imagen (como en el inventario).
@export var display_name: String = ""
## Descripción que se muestra bajo el nombre.
@export_multiline var description: String = ""

@export var area_3d: Area3D ## Asignar manualmente o dejar vacío para auto-detectar
@export var outline_color: Color = Color(1.0, 0.9, 0.2, 1.0) ## Color del borde al acercarse
@export var outline_width: float = 3.0 ## Grosor del borde en píxeles

@export_group("Zoom y recorrido")
## Permite acercar la imagen y recorrerla mientras se inspecciona. Zoom: gatillos R2/L2, teclas E/Q o rueda del mouse.
## Recorrer: stick, flechas o arrastrar con el mouse (igual que rotar un objeto).
@export var allow_zoom: bool = true
## Zoom máximo (1 = la imagen entera, sin acercar).
@export_range(1.0, 8.0, 0.1, "suffix:x") var max_zoom: float = 4.0

@onready var sprite_on_screen: Control = get_node_or_null("SpriteOnScreen") ## Imagen a pantalla, visible solo mientras se inspecciona
@onready var sprite_closed: Control = get_node_or_null("SpriteClosed") ## Aviso para abrir, visible solo al estar cerca y sin inspeccionar

var sprite_3d: Sprite3D
var sprite_2d: Sprite2D
var animation_player: AnimationPlayer
var _is_player_inside: bool = false
var _is_inspecting: bool = false
var _player_ref: Node = null ## Jugador dentro del Area3D (se anula al salir)
var _frozen_player: Node = null ## Jugador congelado por la inspección abierta (se libera SIEMPRE al cerrar)
var _outline_material: ShaderMaterial = null
var _canvas: CanvasLayer = null
var _info_panel: MenuInfoPanel = null
var _highlighted: bool = false

var _background: Control ## ventana de la imagen: recorta el contenido cuando hay zoom
var _sprite_center: Vector2 ## posición del Sprite2D con la imagen centrada en la ventana
var _zoom: float = 1.0 ## zoom actual (suavizado)
var _zoom_target: float = 1.0 ## zoom pedido
var _view: Vector2 = Vector2.ZERO ## punto de la imagen (px, desde su centro) que está en el centro de la ventana
var _sprite_scale: float = 1.0 ## escala final del Sprite2D (zoom x respiración)
var _pan_row: Label ## pista "recorrer": solo se ve con la imagen acercada


func _ready() -> void:
	# 1. Obtener Sprite3D padre
	sprite_3d = get_parent() as Sprite3D
	if not sprite_3d:
		push_warning("InteractablePicture: Debe ser hijo de un Sprite3D.")
		return

	# 2. Buscar Area3D automáticamente entre los hermanos si no se asignó
	if not area_3d:
		area_3d = sprite_3d.get_node_or_null("Area3D") as Area3D
		if not area_3d:
			var found_areas: Array[Node] = sprite_3d.find_children("*", "Area3D", true, false)
			if not found_areas.is_empty():
				area_3d = found_areas[0] as Area3D

	if area_3d:
		area_3d.body_entered.connect(_on_body_entered)
		area_3d.body_exited.connect(_on_body_exited)
	else:
		push_warning("InteractablePicture: No se encontró Area3D bajo " + sprite_3d.name)

	# 3. Configurar UI y CanvasLayer (las dos UI comparten el mismo CanvasLayer)
	if sprite_on_screen:
		sprite_2d = sprite_on_screen.find_child("Sprite2D", true, false) as Sprite2D
		animation_player = sprite_on_screen.find_child("AnimationPlayer", true, false) as AnimationPlayer

	for ui_control in [sprite_on_screen, sprite_closed]:
		if ui_control and not (ui_control.get_parent() is CanvasLayer):
			ui_control.reparent(_get_canvas())

	if sprite_on_screen:
		_setup_zoom()
		sprite_on_screen.visible = false
		MenuInfoPanel.shift_viewer(sprite_on_screen) # la imagen a la derecha, el texto a la izquierda
		_info_panel = MenuInfoPanel.create(_get_canvas()) # fondo + nombre + descripción
	_refresh_visuals()

	# 4. Inicializar Shader de Outline
	_init_outline_material()
	_sync_texture_from_parent()


func _exit_tree() -> void:
	InteractionFocus.unregister(self)
	# Si el cuadro desaparece con el menú abierto (queue_free, cambio de escena...), el jugador no
	# puede quedar congelado.
	if _is_inspecting:
		_is_inspecting = false
		_release_player()


func _process(delta: float) -> void:
	if _is_inspecting:
		_update_zoom(delta)
	if _is_player_inside or _highlighted:
		_refresh_visuals() # el foco puede pasar a otro objeto cercano, o el modo fusil/inventario puede abrirse


func _unhandled_input(event: InputEvent) -> void:
	if CameraDirector.is_first_person() or Inventory.menu_open:
		return # modo fusil o inventario abiertos: no inspeccionar (al cerrar reactivarían el movimiento)
	if event.is_action_pressed("interact"):
		if _is_inspecting:
			_close_inspection()
			get_viewport().set_input_as_handled()
		elif _is_player_inside and is_instance_valid(_player_ref) and InteractionFocus.is_focused(self, _player_ref):
			_open_inspection()
			get_viewport().set_input_as_handled()
		return

	if not (_is_inspecting and _can_zoom()):
		return
	# Mouse: la rueda acerca/aleja y arrastrar con el botón izquierdo recorre la imagen
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = minf(_zoom_target * ZOOM_WHEEL_STEP, max_zoom)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = maxf(_zoom_target / ZOOM_WHEEL_STEP, 1.0)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and _zoom > ZOOM_EPSILON:
		# La imagen acompaña al cursor (de ahí el signo): 'relative' viene en px de pantalla y la ventana está escalada
		_view -= event.relative / (_sprite_scale * _background.scale.x)


## Posición que usa InteractionFocus para decidir cuál es el objeto más cercano al jugador.
func get_focus_position() -> Vector3:
	return sprite_3d.global_position if is_instance_valid(sprite_3d) else global_position


func _open_inspection() -> void:
	_sync_texture_from_parent()
	_reset_zoom()
	_is_inspecting = true
	InteractionFocus.begin_inspection(self)
	if sprite_on_screen:
		sprite_on_screen.visible = true
	if _info_panel:
		_get_canvas().layer = MENU_CANVAS_LAYER
		_info_panel.set_info(display_name, description)
		_info_panel.visible = true
	_refresh_visuals() # "SpriteClosed" y outline se ocultan, "SpriteOnScreen" se muestra

	if animation_player and animation_player.has_animation("floating"):
		animation_player.play("floating")

	_frozen_player = _player_ref
	PlayerControlLock.freeze(_frozen_player)

	opened.emit()


func _close_inspection() -> void:
	_is_inspecting = false
	InteractionFocus.end_inspection(self)
	if sprite_on_screen:
		sprite_on_screen.visible = false
	if _info_panel:
		_info_panel.visible = false
	_get_canvas().layer = IDLE_CANVAS_LAYER

	if animation_player:
		animation_player.stop()
	_reset_zoom()

	_release_player() # siempre, esté o no el jugador dentro del área
	_refresh_visuals() # vuelve el aviso y el outline si el jugador sigue en la zona

	closed.emit()


## ¿El menú de esta imagen está abierto?
func is_inspecting() -> bool:
	return _is_inspecting


## Cierra la imagen si está abierta (ej: el jugador recibe daño). Devuelve el control al jugador.
func close_menu() -> void:
	if _is_inspecting:
		_close_inspection()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name.to_lower().begins_with("player"):
		_is_player_inside = true
		_player_ref = body
		InteractionFocus.register(self)
		_refresh_visuals()


func _on_body_exited(body: Node3D) -> void:
	if body == _player_ref:
		_is_player_inside = false
		_player_ref = null
		InteractionFocus.unregister(self)
		_refresh_visuals()


## Outline y aviso ("SpriteClosed"): solo si el jugador está dentro del área, la imagen no está
## abierta, el objeto tiene el foco (es el más cercano) y no hay nada abierto encima (modo fusil o inventario).
func _refresh_visuals() -> void:
	var show_prompt: bool = _is_player_inside and not _is_inspecting \
		and not CameraDirector.is_first_person() and not Inventory.menu_open \
		and is_instance_valid(_player_ref) and InteractionFocus.is_focused(self, _player_ref)
	if sprite_closed:
		sprite_closed.visible = show_prompt
	if show_prompt != _highlighted:
		_highlighted = show_prompt
		if show_prompt:
			_show_outline()
		else:
			_hide_outline()


## Devuelve el control SIEMPRE: no depende de si el jugador sigue dentro del Area3D. Se usa la
## referencia propia _frozen_player porque _player_ref se anula al salir del área.
func _release_player() -> void:
	var player: Node = _frozen_player
	_frozen_player = null
	PlayerControlLock.release(player)


## Capa del menú abierto: por ENCIMA de las barras 4:3 (126, LetterboxController) para que no tapen el
## texto, y a la par del inventario (127), que nunca está abierto al mismo tiempo.
const ZOOM_RATE: float = 1.6 ## con gatillo o tecla: cambio de zoom por segundo (logarítmico: se siente parejo a cualquier zoom)
const ZOOM_WHEEL_STEP: float = 1.25 ## factor por cada muesca de la rueda del mouse
const ZOOM_SMOOTH: float = 14.0 ## qué tan rápido el zoom real alcanza al pedido (1/s)
const PAN_SPEED: float = 170.0 ## velocidad de recorrido a pleno stick, en PANTALLA (px/s): igual de rápido a cualquier zoom
const ZOOM_EPSILON: float = 1.01 ## por debajo de esto la imagen se considera sin acercar (no se recorre y vuelve al centro)
const HINT_ROW_STEP: float = 25.0 ## separación vertical entre las pistas de botones bajo la imagen
const BREATH_MIN: float = 0.95 ## la "respiración" de la animación 'floating': la escala va de 0.95 a 1.0 cada 6 s
const BREATH_HALF_PERIOD: float = 3.0

const MENU_CANVAS_LAYER: int = 127
const IDLE_CANVAS_LAYER: int = 10 ## avisos y resaltado con el menú cerrado: debajo de las barras


func _get_canvas() -> CanvasLayer:
	if _canvas == null:
		_canvas = CanvasLayer.new()
		_canvas.layer = 10
		add_child(_canvas)
	return _canvas


# ---------------------------------------------------------------- ZOOM Y RECORRIDO

func _can_zoom() -> bool:
	return allow_zoom and sprite_2d != null and _background != null


## Prepara el zoom: toma el control de la escala del Sprite2D (la animación 'floating' la hacía "respirar"
## y pisaría el zoom), y agrega bajo la imagen las pistas de zoom y recorrido.
func _setup_zoom() -> void:
	_background = sprite_on_screen.find_child("Background", true, false) as Control
	if not _can_zoom():
		return
	_sprite_center = sprite_2d.position

	if animation_player:
		var floating: Animation = animation_player.get_animation("floating")
		if floating:
			for i in floating.get_track_count():
				if floating.track_get_path(i) == NodePath(".:scale"):
					floating.track_set_enabled(i, false) # la respiración la hace _breathing() (mismo movimiento)

	var close_row: Label = sprite_on_screen.get_node_or_null("Label") as Label
	if close_row == null:
		return
	var close_icon: AnimatedSprite2D = close_row.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if close_icon == null:
		return

	# Fila "(L2)(R2) zoom"
	var zoom_row: Label = close_row.duplicate() as Label
	zoom_row.name = "ZoomRow"
	sprite_on_screen.add_child(zoom_row)
	var zoom_icon_a: AnimatedSprite2D = zoom_row.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var zoom_icon_b: AnimatedSprite2D = zoom_icon_a.duplicate() as AnimatedSprite2D
	zoom_row.add_child(zoom_icon_b)
	zoom_row.offset_top += HINT_ROW_STEP
	zoom_row.offset_bottom += HINT_ROW_STEP
	ButtonPrompt.setup_row_icons(zoom_row, [zoom_icon_a, zoom_icon_b], "zoom", [5, 7], 0.0)

	# Fila "(R) recorrer" (solo visible con la imagen acercada)
	_pan_row = close_row.duplicate() as Label
	_pan_row.name = "PanRow"
	sprite_on_screen.add_child(_pan_row)
	var pan_icon: AnimatedSprite2D = _pan_row.get_node("AnimatedSprite2D") as AnimatedSprite2D
	_pan_row.offset_top += HINT_ROW_STEP * 2.0
	_pan_row.offset_bottom += HINT_ROW_STEP * 2.0
	ButtonPrompt.setup_row(_pan_row, pan_icon, "recorrer", 8, 0.0)
	_pan_row.visible = false


## Vuelve a la imagen entera, centrada y con la respiración de siempre.
func _reset_zoom() -> void:
	_zoom = 1.0
	_zoom_target = 1.0
	_view = Vector2.ZERO
	_sprite_scale = 1.0
	if _can_zoom():
		sprite_2d.scale = Vector2.ONE
		sprite_2d.position = _sprite_center
		_background.clip_contents = false
		if _pan_row:
			_pan_row.visible = false


## La "respiración" de la animación 'floating' (escala 0.95 <-> 1.0, onda triangular de 6 s), en fase con ella.
func _breathing() -> float:
	if animation_player == null:
		return 1.0
	var phase: float = fmod(animation_player.current_animation_position, BREATH_HALF_PERIOD * 2.0) / BREATH_HALF_PERIOD
	return BREATH_MIN + (1.0 - BREATH_MIN) * (1.0 - absf(phase - 1.0))


func _update_zoom(delta: float) -> void:
	if not _can_zoom():
		return
	# Zoom: logarítmico, así acercar y alejar se sienten iguales. La rueda del mouse mueve '_zoom_target' por evento.
	var zoom_input: float = Input.get_action_strength("image_zoom_in") - Input.get_action_strength("image_zoom_out")
	if zoom_input != 0.0:
		_zoom_target = clampf(_zoom_target * exp(zoom_input * ZOOM_RATE * delta), 1.0, max_zoom)
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-ZOOM_SMOOTH * delta))
	if absf(_zoom - _zoom_target) < 0.001:
		_zoom = _zoom_target

	# La respiración se apaga a medida que se acerca (si no, la vista se movería sola al recorrer)
	var breath: float = lerpf(_breathing(), 1.0, clampf((_zoom - 1.0) / 0.2, 0.0, 1.0))
	_sprite_scale = _zoom * breath

	# Recorrer: stick (o flechas). La velocidad en pantalla es la misma a cualquier zoom.
	var pan: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if pan != Vector2.ZERO and _zoom > ZOOM_EPSILON:
		_view += pan * PAN_SPEED * delta / _sprite_scale
	if _zoom <= ZOOM_EPSILON:
		_view *= exp(-8.0 * delta) # sin acercar, la imagen vuelve sola al centro

	# La vista nunca sale de la imagen: no se ve nada fuera de sus bordes
	if sprite_2d.texture:
		var limit: Vector2 = (sprite_2d.texture.get_size() * 0.5 - _background.size * 0.5 / _sprite_scale).max(Vector2.ZERO)
		_view = _view.clamp(-limit, limit)

	sprite_2d.scale = Vector2.ONE * _sprite_scale
	sprite_2d.position = _sprite_center - _view * _sprite_scale
	# Recortar a la ventana solo cuando hay zoom: sin acercar la imagen se ve entera, como siempre
	_background.clip_contents = _zoom > 1.001
	if _pan_row:
		_pan_row.visible = _zoom > ZOOM_EPSILON + 0.01


func _sync_texture_from_parent() -> void:
	if not sprite_3d or not sprite_3d.texture:
		return
	if sprite_2d:
		sprite_2d.texture = sprite_3d.texture
	if _outline_material:
		_outline_material.set_shader_parameter("tex", sprite_3d.texture)


func _show_outline() -> void:
	if sprite_3d and sprite_3d.texture:
		_sync_texture_from_parent()
		if _outline_material:
			_outline_material.set_shader_parameter("outline_color", outline_color)
			_outline_material.set_shader_parameter("width", outline_width)
		sprite_3d.material_override = _outline_material


func _hide_outline() -> void:
	if sprite_3d:
		sprite_3d.material_override = null


func _init_outline_material() -> void:
	var shader := Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode unshaded, depth_draw_always, cull_disabled;

	uniform sampler2D tex : source_color, filter_linear_mipmap;
	uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
	uniform float width : hint_range(0.0, 10.0) = 2.5;

	void fragment() {
		vec4 col = texture(tex, UV);
		if (col.a < 0.1) {
			vec2 size = vec2(textureSize(tex, 0));
			vec2 px = width / size;
			float a = 0.0;
			a += texture(tex, UV + vec2(px.x, 0.0)).a;
			a += texture(tex, UV + vec2(-px.x, 0.0)).a;
			a += texture(tex, UV + vec2(0.0, px.y)).a;
			a += texture(tex, UV + vec2(0.0, -px.y)).a;
			if (a > 0.05) {
				ALBEDO = outline_color.rgb;
				ALPHA = 1.0;
			} else {
				discard;
			}
		} else {
			ALBEDO = col.rgb;
			ALPHA = col.a;
		}
	}
	"""
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = shader
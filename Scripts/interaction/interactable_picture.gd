extends Node3D
class_name InteractablePicture

## Se emite al abrir la imagen (empieza la inspección).
signal opened
## Se emite al cerrarla.
signal closed

@export var area_3d: Area3D ## Asignar manualmente o dejar vacío para auto-detectar
@export var outline_color: Color = Color(1.0, 0.9, 0.2, 1.0) ## Color del borde al acercarse
@export var outline_width: float = 3.0 ## Grosor del borde en píxeles

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
var _highlighted: bool = false


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
		sprite_on_screen.visible = false
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


func _process(_delta: float) -> void:
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


## Posición que usa InteractionFocus para decidir cuál es el objeto más cercano al jugador.
func get_focus_position() -> Vector3:
	return sprite_3d.global_position if is_instance_valid(sprite_3d) else global_position


func _open_inspection() -> void:
	_sync_texture_from_parent()
	_is_inspecting = true
	InteractionFocus.begin_inspection(self)
	if sprite_on_screen:
		sprite_on_screen.visible = true
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

	if animation_player:
		animation_player.stop()

	_release_player() # siempre, esté o no el jugador dentro del área
	_refresh_visuals() # vuelve el aviso y el outline si el jugador sigue en la zona

	closed.emit()


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


func _get_canvas() -> CanvasLayer:
	if _canvas == null:
		_canvas = CanvasLayer.new()
		_canvas.layer = 10
		add_child(_canvas)
	return _canvas


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
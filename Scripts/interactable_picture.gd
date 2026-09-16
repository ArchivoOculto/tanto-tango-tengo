extends Node3D
class_name InteractablePicture

@export var area_3d: Area3D ## Asignar manualmente o dejar vacío para auto-detectar
@export var outline_color: Color = Color(1.0, 0.9, 0.2, 1.0) ## Color del borde al acercarse
@export var outline_width: float = 3.0 ## Grosor del borde en píxeles

@onready var sprite_on_screen: Control = get_node_or_null("SpriteOnScreen")

var sprite_3d: Sprite3D
var sprite_2d: Sprite2D
var animation_player: AnimationPlayer
var _is_player_inside: bool = false
var _is_inspecting: bool = false
var _player_ref: Node = null
var _outline_material: ShaderMaterial = null


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

	# 3. Configurar UI y CanvasLayer
	if sprite_on_screen:
		sprite_2d = sprite_on_screen.find_child("Sprite2D", true, false) as Sprite2D
		animation_player = sprite_on_screen.find_child("AnimationPlayer", true, false) as AnimationPlayer

		if not (sprite_on_screen.get_parent() is CanvasLayer):
			var canvas := CanvasLayer.new()
			canvas.layer = 10
			add_child(canvas)
			sprite_on_screen.reparent(canvas)

		sprite_on_screen.visible = false

	# 4. Inicializar Shader de Outline
	_init_outline_material()
	_sync_texture_from_parent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _is_inspecting:
			_close_inspection()
			get_viewport().set_input_as_handled()
		elif _is_player_inside and is_instance_valid(_player_ref):
			_open_inspection()
			get_viewport().set_input_as_handled()


func _open_inspection() -> void:
	_sync_texture_from_parent()
	_is_inspecting = true
	if sprite_on_screen:
		sprite_on_screen.visible = true
	_hide_outline()

	if animation_player and animation_player.has_animation("floating"):
		animation_player.play("floating")

	if _player_ref:
		if "velocity" in _player_ref:
			_player_ref.velocity = Vector3.ZERO
		if "anim_controller" in _player_ref and _player_ref.anim_controller:
			_player_ref.anim_controller.update_locomotion(_player_ref.is_on_floor(), 0.0)
		_player_ref.set_physics_process(false)
		if "combat_controller" in _player_ref and _player_ref.combat_controller:
			_player_ref.combat_controller.interrupt_actions()
			_player_ref.combat_controller.set_process(false)


func _close_inspection() -> void:
	_is_inspecting = false
	if sprite_on_screen:
		sprite_on_screen.visible = false

	if animation_player:
		animation_player.stop()

	if is_instance_valid(_player_ref):
		_player_ref.set_physics_process(true)
		if "combat_controller" in _player_ref and _player_ref.combat_controller:
			_player_ref.combat_controller.set_process(true)

	if _is_player_inside:
		_show_outline()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name.to_lower().begins_with("player"):
		_is_player_inside = true
		_player_ref = body
		if not _is_inspecting:
			_show_outline()


func _on_body_exited(body: Node3D) -> void:
	if body == _player_ref:
		_is_player_inside = false
		_player_ref = null
		_hide_outline()


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
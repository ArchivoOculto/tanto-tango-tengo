extends Node3D
class_name InteractableObject

## Versión para objetos 3D de InteractablePicture.
##
## Uso: agregar la escena interactable_object.tscn como HIJA del objeto 3D (el "objeto" es el
## padre directo: un MeshInstance3D, o cualquier nodo que contenga mallas) y agregar a mano un
## Area3D con su CollisionShape3D que delimite dónde el jugador puede interactuar.
##
##  - Con el jugador dentro del Area3D: el objeto se resalta con un contorno amarillo y aparece
##    "ObjectClosed" (el aviso de interacción).
##  - Con "interact": se congela al jugador, se oculta "ObjectClosed", aparece "ObjectOnScreen" y
##    el objeto se CLONA dentro de su SubViewport. Con el stick derecho (acciones aim_*) se lo
##    rota en cualquier eje; siempre queda fijo en posición, girando sobre su centro.
##  - Con "interact" de nuevo: se cierra, se libera el clon y el jugador recupera el control.
##
## El clon solo copia las mallas visibles (MeshInstance3D, MultiMeshInstance3D, Sprite3D,
## Label3D): sin scripts, colisiones ni hijos de lógica.

## Se emite al abrir el visor (empieza la inspección).
signal opened
## Se emite al cerrarlo.
signal closed

@export_group("Zona de interacción")
@export var area_3d: Area3D ## Asignar manualmente o dejar vacío para auto-detectar un Area3D bajo el objeto

@export_group("Outline")
@export var outline_color: Color = Color(1.0, 0.9, 0.2, 1.0) ## Color del borde al acercarse
@export_range(0.0, 10.0, 0.1, "suffix:px") var outline_width: float = 3.0 ## Grosor del borde en píxeles de pantalla

@export_group("Visor 3D")
## Velocidad de rotación con el stick al máximo (grados/seg).
@export var rotation_speed_degrees: float = 140.0
## 1 = lineal; más alto = más fino cerca del centro del stick.
@export_range(1.0, 3.0, 0.1) var rotation_response_curve: float = 1.5
@export var invert_y: bool = false
## Escala y centra el clon para que entre en el visor aunque se lo rote (sin importar el tamaño real).
@export var auto_fit: bool = true
## Qué parte del campo visual de la cámara ocupa el objeto como máximo (0.1 a 1.0).
@export_range(0.1, 1.0, 0.05) var fit_fraction: float = 0.9
## Multiplicador extra de tamaño (1 = sin cambio).
@export var scale_multiplier: float = 1.0
@export var viewer_light_energy: float = 1.3
@export var viewer_ambient_color: Color = Color(1.0, 1.0, 1.0)
@export var viewer_ambient_energy: float = 0.55

@onready var object_on_screen: Control = get_node_or_null("ObjectOnScreen") ## Visor, visible solo mientras se inspecciona
@onready var object_closed: Control = get_node_or_null("ObjectClosed") ## Aviso para abrir, visible solo al estar cerca y sin inspeccionar

var animation_player: AnimationPlayer

var _source: Node3D ## El objeto 3D que se resalta y se clona (el padre directo)
var _sub_viewport: SubViewport
var _view_camera: Camera3D
var _pivot: Node3D
var _holder: Node3D ## Raíz del clon; cuelga de _pivot
var _bounds: AABB
var _has_bounds: bool = false

var _is_player_inside: bool = false
var _is_inspecting: bool = false
var _player_ref: Node = null
var _canvas: CanvasLayer = null
var _outline_material: ShaderMaterial = null
var _outlined: Dictionary = {} ## MeshInstance3D -> material_overlay que tenía antes del outline


func _ready() -> void:
	# 1. El objeto es el padre directo
	_source = get_parent() as Node3D
	if _source == null:
		push_warning("InteractableObject: debe ser hijo de un nodo 3D (el objeto a inspeccionar).")
		return

	# 2. Buscar el Area3D automáticamente bajo el objeto si no se asignó
	if not area_3d:
		area_3d = _source.get_node_or_null("Area3D") as Area3D
		if not area_3d:
			for found in _source.find_children("*", "Area3D", true, false):
				if not is_ancestor_of(found):
					area_3d = found as Area3D
					break

	if area_3d:
		area_3d.body_entered.connect(_on_body_entered)
		area_3d.body_exited.connect(_on_body_exited)
	else:
		push_warning("InteractableObject: no se encontró un Area3D bajo " + _source.name + ". Agregá uno con su CollisionShape3D.")

	# 3. UI: las dos comparten el mismo CanvasLayer (se dibujan a pantalla)
	if object_on_screen:
		animation_player = object_on_screen.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_sub_viewport = object_on_screen.find_child("SubViewport", true, false) as SubViewport
		_view_camera = object_on_screen.find_child("SubView Camera", true, false) as Camera3D
		_pivot = object_on_screen.find_child("ObjectPivot", true, false) as Node3D

	for ui_control in [object_on_screen, object_closed]:
		if ui_control and not (ui_control.get_parent() is CanvasLayer):
			ui_control.reparent(_get_canvas())

	if object_on_screen:
		object_on_screen.visible = false
	_refresh_prompt()
	_setup_viewer()

	# El aviso se esconde mientras el modo fusil está activo (ahí no se puede interactuar)
	CameraDirector.first_person_changed.connect(func(_active: bool): _refresh_prompt())

	# 4. Material del contorno
	_init_outline_material()


func _exit_tree() -> void:
	_hide_outline()


func _process(delta: float) -> void:
	if _is_inspecting:
		_rotate_with_stick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if CameraDirector.is_first_person():
		return # modo fusil activo: no inspeccionar (al cerrar reactivaría el movimiento del jugador)
	if event.is_action_pressed("interact"):
		if _is_inspecting:
			_close_inspection()
			get_viewport().set_input_as_handled()
		elif _is_player_inside and is_instance_valid(_player_ref):
			_open_inspection()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- ABRIR / CERRAR

func _open_inspection() -> void:
	_hide_outline() # antes de clonar, para que el clon no herede el contorno
	_is_inspecting = true

	_build_clone()
	if _pivot:
		_pivot.transform.basis = Basis.IDENTITY # siempre se empieza viendo el objeto "de frente"
	if _sub_viewport:
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _view_camera:
		_view_camera.make_current()

	if object_on_screen:
		object_on_screen.visible = true
	_refresh_prompt() # "ObjectClosed" se oculta, "ObjectOnScreen" se muestra

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

	opened.emit()


func _close_inspection() -> void:
	_is_inspecting = false
	if object_on_screen:
		object_on_screen.visible = false
	if _sub_viewport:
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_clear_clone()
	_refresh_prompt() # vuelve "ObjectClosed" si el jugador sigue en la zona

	if animation_player:
		animation_player.stop()

	if is_instance_valid(_player_ref):
		_player_ref.set_physics_process(true)
		if "combat_controller" in _player_ref and _player_ref.combat_controller:
			_player_ref.combat_controller.set_process(true)

	if _is_player_inside:
		_show_outline()

	closed.emit()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name.to_lower().begins_with("player"):
		_is_player_inside = true
		_player_ref = body
		if not _is_inspecting:
			_show_outline()
		_refresh_prompt()


func _on_body_exited(body: Node3D) -> void:
	if body == _player_ref:
		_is_player_inside = false
		_player_ref = null
		_hide_outline()
		_refresh_prompt()


## "ObjectClosed" (aviso de interacción): visible solo si el jugador está dentro del área,
## el visor no está abierto y no hay modo fusil activo.
func _refresh_prompt() -> void:
	if object_closed:
		object_closed.visible = _is_player_inside and not _is_inspecting and not CameraDirector.is_first_person()


func _get_canvas() -> CanvasLayer:
	if _canvas == null:
		_canvas = CanvasLayer.new()
		_canvas.layer = 10
		add_child(_canvas)
	return _canvas


# ---------------------------------------------------------------- VISOR 3D

func _setup_viewer() -> void:
	if _sub_viewport == null or _view_camera == null or _pivot == null:
		push_warning("InteractableObject: faltan SubViewport, 'SubView Camera' u ObjectPivot dentro de ObjectOnScreen.")
		return

	# Mundo propio: sin esto el visor mostraría el nivel entero y el clon se iluminaría con sus luces.
	_sub_viewport.own_world_3d = true
	_sub_viewport.transparent_bg = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED # solo renderiza mientras se inspecciona

	# Textura ligada directamente al viewport (no depende de rutas, sobrevive a los reparent)
	var texture_rect: TextureRect = object_on_screen.find_child("TextureRect", true, false) as TextureRect
	if texture_rect:
		texture_rect.texture = _sub_viewport.get_texture()

	# Iluminación propia del visor
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = viewer_ambient_color
	environment.ambient_light_energy = viewer_ambient_energy
	_view_camera.environment = environment

	var light := DirectionalLight3D.new()
	light.name = "ViewerLight"
	light.light_energy = viewer_light_energy
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	_sub_viewport.add_child(light)


## Rotación libre con el stick derecho. Se compone en los ejes de la CÁMARA (no del objeto),
## así "derecha" siempre gira hacia la derecha sin importar cómo haya quedado el objeto.
func _rotate_with_stick(delta: float) -> void:
	if _pivot == null:
		return
	var stick: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick == Vector2.ZERO:
		return

	var strength: float = pow(stick.length(), rotation_response_curve)
	var dir: Vector2 = stick.normalized() * strength
	var step: float = deg_to_rad(rotation_speed_degrees) * delta

	var yaw: float = dir.x * step # stick a la derecha => la cara frontal gira hacia la derecha
	var pitch: float = dir.y * step * (-1.0 if invert_y else 1.0) # stick arriba => la cara frontal sube

	var rotation_step: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	_pivot.transform.basis = (rotation_step * _pivot.transform.basis).orthonormalized()


func _build_clone() -> void:
	_clear_clone()
	if _pivot == null or _source == null:
		return

	_holder = Node3D.new()
	_holder.name = "ObjectClone"
	_has_bounds = false

	# El propio objeto, si es una malla, va con transform identidad (se muestra "en reposo",
	# sin su posición/rotación/escala en el mundo)
	if _is_cloneable_visual(_source):
		var root_copy: Node3D = _duplicate_visual(_source)
		root_copy.transform = Transform3D.IDENTITY
		_holder.add_child(root_copy)
		_grow_bounds(_source, Transform3D.IDENTITY)

	_clone_children(_source, _holder, Transform3D.IDENTITY)
	_pivot.add_child(_holder)
	_fit_clone()


func _clear_clone() -> void:
	if is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null
	_has_bounds = false


## Recorre el árbol del objeto y replica su jerarquía: las mallas se copian, el resto se
## reemplaza por un Node3D vacío para conservar las transformaciones relativas.
func _clone_children(src: Node, dst_parent: Node3D, accumulated: Transform3D) -> void:
	for child in src.get_children():
		if child == self or not (child is Node3D):
			continue # ni a sí mismo (recursión) ni lo que no sea 3D (UI, audio, etc.)
		var node: Node3D = child as Node3D
		if not node.visible:
			continue

		var node_transform: Transform3D = accumulated * node.transform
		var copy: Node3D
		if _is_cloneable_visual(node):
			copy = _duplicate_visual(node)
			_grow_bounds(node, node_transform)
		else:
			copy = Node3D.new()
		copy.transform = node.transform
		dst_parent.add_child(copy)
		_clone_children(node, copy, node_transform)


func _is_cloneable_visual(node: Node) -> bool:
	return node is MeshInstance3D or node is MultiMeshInstance3D or node is Sprite3D or node is Label3D


## Copia solo el nodo: sin scripts, señales ni grupos (flags = 0) y sin hijos.
func _duplicate_visual(node: Node3D) -> Node3D:
	var copy: Node3D = node.duplicate(0) as Node3D
	for grandchild in copy.get_children():
		copy.remove_child(grandchild)
		grandchild.free()
	return copy


func _grow_bounds(node: Node, node_transform: Transform3D) -> void:
	var local_aabb: AABB = (node as VisualInstance3D).get_aabb()
	if local_aabb.size == Vector3.ZERO:
		return
	var world_aabb: AABB = node_transform * local_aabb
	if _has_bounds:
		_bounds = _bounds.merge(world_aabb)
	else:
		_bounds = world_aabb
		_has_bounds = true


## Centra el clon sobre el pivote (para que gire sobre su centro y quede fijo) y, si
## auto_fit está activo, lo escala para que ni siquiera la punta más lejana se salga del visor.
func _fit_clone() -> void:
	if not _has_bounds or _holder == null:
		push_warning("InteractableObject: no se encontraron mallas para clonar bajo " + _source.name + ".")
		return

	var center: Vector3 = _bounds.get_center()
	var radius: float = _bounds.size.length() * 0.5 # esfera que contiene a la caja: rote como rote, entra

	var fit_scale: float = scale_multiplier
	if auto_fit and radius > 0.0001 and _view_camera:
		var distance: float = _view_camera.transform.origin.distance_to(_pivot.transform.origin)
		var half_fov: float = deg_to_rad(_view_camera.fov) * 0.5
		var target_radius: float = distance * sin(half_fov * fit_fraction)
		fit_scale = (target_radius / radius) * scale_multiplier

	_holder.scale = Vector3.ONE * fit_scale
	_holder.position = -center * fit_scale


# ---------------------------------------------------------------- OUTLINE

func _outline_targets() -> Array[MeshInstance3D]:
	var targets: Array[MeshInstance3D] = []
	if _source is MeshInstance3D:
		targets.append(_source as MeshInstance3D)
	if _source:
		for found in _source.find_children("*", "MeshInstance3D", true, false):
			if not is_ancestor_of(found):
				targets.append(found as MeshInstance3D)
	return targets


func _show_outline() -> void:
	if _outline_material == null:
		return
	_outline_material.set_shader_parameter("outline_color", outline_color)
	_outline_material.set_shader_parameter("width", outline_width)
	for mesh in _outline_targets():
		if not _outlined.has(mesh):
			_outlined[mesh] = mesh.material_overlay # se restaura tal cual al salir
		mesh.material_overlay = _outline_material


func _hide_outline() -> void:
	for mesh in _outlined.keys():
		if is_instance_valid(mesh):
			(mesh as MeshInstance3D).material_overlay = _outlined[mesh]
	_outlined.clear()


## Contorno por "casco invertido": se dibuja de nuevo la malla, inflada a lo largo de sus
## normales y mostrando solo las caras traseras, de modo que solo asoma el borde. El grosor se
## calcula en espacio de pantalla, así se ve igual de ancho cerca o lejos de la cámara.
func _init_outline_material() -> void:
	var shader := Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

	uniform vec4 outline_color : source_color = vec4(1.0, 0.9, 0.2, 1.0);
	uniform float width : hint_range(0.0, 10.0) = 3.0;

	void vertex() {
		vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
		vec3 view_normal = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
		vec2 direction = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
		if (length(direction) > 0.0001) {
			direction = normalize(direction);
		}
		clip.xy += direction * width * clip.w * 2.0 / VIEWPORT_SIZE;
		POSITION = clip;
	}

	void fragment() {
		ALBEDO = outline_color.rgb;
	}
	"""
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = shader

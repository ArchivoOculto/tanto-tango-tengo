extends Node3D
class_name InteractableObject

## Versión para objetos 3D de InteractablePicture.
##
## Uso: agregar la escena interactable_object.tscn como HIJA del objeto 3D (el "objeto" es el
## padre directo: un MeshInstance3D, o cualquier nodo que contenga mallas) y agregar a mano un
## Area3D con su CollisionShape3D (collision_layer = 0, collision_mask = 2) que delimite dónde el
## jugador puede interactuar.
##
##  - Con el jugador dentro del Area3D: el objeto se resalta con un contorno y aparece
##    "ObjectClosed" (el aviso de interacción).
##  - Con "interact" (○): se congela al jugador, se oculta "ObjectClosed", aparece "ObjectOnScreen" y
##    el objeto se CLONA dentro de su SubViewport. Con el stick derecho se lo rota en cualquier
##    eje; siempre queda fijo en posición, girando sobre su centro.
##  - Con "interact" de nuevo: se cierra, se libera el clon y el jugador recupera el control.
##
## INVENTARIO Y ACCIONES (todo se configura desde el Inspector):
##  - 'item': si se asigna, el menú muestra "guardar" (△, acción object_save). Al usarlo el objeto
##    sale del mundo y pasa al Inventory. Si queda vacío (ej: la radio), el objeto NO se puede guardar.
##  - 'actions': filas extra del menú. Una acción con 'required_item' solo aparece cuando el
##    jugador lleva ese ítem. Al activarla se emite action_triggered; quien la escuche programa el efecto.
##
## El clon solo copia las mallas visibles (MeshInstance3D, MultiMeshInstance3D, Sprite3D,
## Label3D): sin scripts, colisiones ni hijos de lógica.

## Se emite al abrir el visor (empieza la inspección).
signal opened
## Se emite al cerrarlo.
signal closed
## El objeto salió del mundo y entró al inventario.
signal stored(item: ItemData)
## El objeto volvió al mundo (ver drop_to_world) y se puede volver a agarrar.
signal dropped(item: ItemData)
## Se activó una acción del menú. 'consumed' es la entrada del inventario que la acción consumió
## (null si no consume nada).
signal action_triggered(action: ObjectAction, consumed: InventoryEntry)

@export_group("Zona de interacción")
@export var area_3d: Area3D ## Asignar manualmente o dejar vacío para auto-detectar un Area3D bajo el objeto

@export_group("Inventario")
## Si se asigna, el objeto se puede GUARDAR en el inventario. Vacío = solo se inspecciona.
@export var item: ItemData
## Radio (en metros) de la zona de interacción que se crea cuando el objeto vuelve al mundo.
@export var drop_area_radius: float = 0.3

@export_group("Acciones del menú")
## Filas extra del menú. Las que requieren un ítem se desbloquean al tenerlo en el inventario.
@export var actions: Array[ObjectAction] = []

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
var viewer: ObjectViewer

## false = el objeto ignora al jugador (sin aviso, sin outline, sin menú). Lo usa el guardado
## (el objeto ya no está en el mundo) y el vuelo de vuelta al mundo.
var interaction_enabled: bool = true:
	set(value):
		interaction_enabled = value
		if not value and _is_inspecting:
			_close_inspection()
		_sync_focus_registration()
		if is_node_ready():
			_refresh_visuals()

var _source: Node3D ## El objeto 3D que se resalta y se clona (el padre directo)
var _is_player_inside: bool = false
var _is_inspecting: bool = false
var _player_ref: Node = null ## Jugador dentro del Area3D (se anula al salir)
var _frozen_player: Node = null ## Jugador congelado por la inspección abierta (se libera SIEMPRE al cerrar)
var _canvas: CanvasLayer = null
var _outline_material: ShaderMaterial = null
var _outlined: Dictionary = {} ## MeshInstance3D -> material_overlay que tenía antes del outline
var _highlighted: bool = false
var _drop_area: Area3D = null
var _drop_tween: Tween = null

# Filas del menú
const ROW_STEP_DEFAULT: float = 25.0
var _ui_menu: Control
var _close_row: Label
var _save_row: Label
var _rotate_row: Label
var _action_rows: Array[Label] = [] ## Una fila por cada elemento de 'actions' (mismo orden)
var _available_actions: Array[ObjectAction] = [] ## Acciones desbloqueadas en el menú abierto


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
		bind_area(area_3d)
	else:
		push_warning("InteractableObject: no se encontró un Area3D bajo " + _source.name + ". Agregá uno con su CollisionShape3D.")

	# 3. UI: las dos comparten el mismo CanvasLayer (se dibujan a pantalla)
	var sub_viewport: SubViewport
	var view_camera: Camera3D
	var pivot: Node3D
	var texture_rect: TextureRect
	if object_on_screen:
		animation_player = object_on_screen.find_child("AnimationPlayer", true, false) as AnimationPlayer
		sub_viewport = object_on_screen.find_child("SubViewport", true, false) as SubViewport
		view_camera = object_on_screen.find_child("SubView Camera", true, false) as Camera3D
		pivot = object_on_screen.find_child("ObjectPivot", true, false) as Node3D
		texture_rect = object_on_screen.find_child("TextureRect", true, false) as TextureRect
		_ui_menu = object_on_screen.find_child("UI Menu", true, false) as Control

	for ui_control in [object_on_screen, object_closed]:
		if ui_control and not (ui_control.get_parent() is CanvasLayer):
			ui_control.reparent(_get_canvas())

	if object_on_screen:
		object_on_screen.visible = false

	# 4. Visor 3D compartido
	viewer = ObjectViewer.new()
	viewer.name = "ObjectViewer"
	viewer.rotation_speed_degrees = rotation_speed_degrees
	viewer.rotation_response_curve = rotation_response_curve
	viewer.invert_y = invert_y
	viewer.auto_fit = auto_fit
	viewer.fit_fraction = fit_fraction
	viewer.scale_multiplier = scale_multiplier
	viewer.light_energy = viewer_light_energy
	viewer.ambient_color = viewer_ambient_color
	viewer.ambient_energy = viewer_ambient_energy
	add_child(viewer)
	if not viewer.setup(sub_viewport, view_camera, pivot, texture_rect):
		push_warning("InteractableObject: faltan SubViewport, 'SubView Camera' u ObjectPivot dentro de ObjectOnScreen.")

	# 5. Filas del menú
	_setup_menu_rows()

	# 6. Material del contorno
	_init_outline_material()
	_refresh_visuals()


func _exit_tree() -> void:
	_hide_outline()
	InteractionFocus.unregister(self)
	# Si el objeto desaparece con el menú abierto (queue_free, cambio de escena...), el jugador no
	# puede quedar congelado.
	if _is_inspecting:
		_is_inspecting = false
		_release_player()


func _process(delta: float) -> void:
	if _is_inspecting:
		viewer.rotate_with_stick(delta)
	elif _is_player_inside or _highlighted:
		_refresh_visuals() # el foco puede pasar a otro objeto cercano, o el modo fusil/inventario puede abrirse


func _unhandled_input(event: InputEvent) -> void:
	if not interaction_enabled or CameraDirector.is_first_person() or Inventory.menu_open:
		return # modo fusil o inventario abiertos: no inspeccionar (al cerrar reactivarían el movimiento)

	if _is_inspecting:
		if _handle_menu_input(event):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and _can_open():
		_open_inspection()
		get_viewport().set_input_as_handled()


## Posición que usa InteractionFocus para decidir cuál es el objeto más cercano al jugador.
func get_focus_position() -> Vector3:
	return _source.global_position if is_instance_valid(_source) else global_position


func _can_open() -> bool:
	return interaction_enabled and _is_player_inside and is_instance_valid(_player_ref) \
		and InteractionFocus.is_focused(self, _player_ref)


# ---------------------------------------------------------------- ZONA DE INTERACCIÓN

## Cambia la zona de interacción por 'new_area' (la anterior deja de contar).
func bind_area(new_area: Area3D) -> void:
	if is_instance_valid(area_3d):
		if area_3d.body_entered.is_connected(_on_body_entered):
			area_3d.body_entered.disconnect(_on_body_entered)
		if area_3d.body_exited.is_connected(_on_body_exited):
			area_3d.body_exited.disconnect(_on_body_exited)
	area_3d = new_area
	_is_player_inside = false
	_player_ref = null
	_sync_focus_registration()
	if is_instance_valid(area_3d):
		area_3d.body_entered.connect(_on_body_entered)
		area_3d.body_exited.connect(_on_body_exited)
	if is_node_ready():
		_refresh_visuals()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name.to_lower().begins_with("player"):
		_is_player_inside = true
		_player_ref = body
		_sync_focus_registration()
		_refresh_visuals()


func _on_body_exited(body: Node3D) -> void:
	if body == _player_ref:
		_is_player_inside = false
		_player_ref = null
		_sync_focus_registration()
		_refresh_visuals()


## Participa del arbitraje de foco si y solo si está activo y el jugador está dentro de su zona. Un
## objeto desactivado (ej: el cassette guardado) no puede "ganar" por cercanía y tapar a otro de la
## misma zona (ej: la radio).
func _sync_focus_registration() -> void:
	if interaction_enabled and _is_player_inside:
		InteractionFocus.register(self)
	else:
		InteractionFocus.unregister(self)


## Outline y aviso ("ObjectClosed"): solo si el objeto está activo, el jugador está dentro del área,
## tiene el foco (es el más cercano) y no hay nada abierto encima (visor, modo fusil o inventario).
func _refresh_visuals() -> void:
	var show_prompt: bool = interaction_enabled and _is_player_inside and not _is_inspecting \
		and not CameraDirector.is_first_person() and not Inventory.menu_open \
		and is_instance_valid(_player_ref) and InteractionFocus.is_focused(self, _player_ref)
	if object_closed:
		object_closed.visible = show_prompt
	if show_prompt != _highlighted:
		_highlighted = show_prompt
		if show_prompt:
			_show_outline()
		else:
			_hide_outline()


func _get_canvas() -> CanvasLayer:
	if _canvas == null:
		_canvas = CanvasLayer.new()
		_canvas.layer = 10
		add_child(_canvas)
	return _canvas


# ---------------------------------------------------------------- ABRIR / CERRAR

func _open_inspection() -> void:
	_is_inspecting = true
	InteractionFocus.begin_inspection(self)
	_refresh_visuals() # quita outline y aviso

	if viewer.is_ready_to_show():
		viewer.show_source(_source, self) # clona el objeto en el visor
		viewer.set_active(true)
	if object_on_screen:
		object_on_screen.visible = true
	_rebuild_menu_rows()

	if animation_player and animation_player.has_animation("floating"):
		animation_player.play("floating")

	_frozen_player = _player_ref
	PlayerControlLock.freeze(_frozen_player)
	opened.emit()


func _close_inspection() -> void:
	_is_inspecting = false
	InteractionFocus.end_inspection(self)
	if object_on_screen:
		object_on_screen.visible = false
	viewer.set_active(false)
	viewer.clear()

	if animation_player:
		animation_player.stop()

	_release_player() # siempre, esté o no el jugador dentro del área
	_refresh_visuals() # vuelve el aviso si el jugador sigue en la zona
	closed.emit()


## Devuelve el control SIEMPRE: no depende de si el jugador sigue dentro del Area3D. Se usa la
## referencia propia _frozen_player porque _player_ref se anula al salir del área.
func _release_player() -> void:
	var player: Node = _frozen_player
	_frozen_player = null
	PlayerControlLock.release(player)


# ---------------------------------------------------------------- FILAS DEL MENÚ

func _setup_menu_rows() -> void:
	if _ui_menu == null:
		return
	_close_row = _ui_menu.get_node_or_null("CloseText") as Label
	_save_row = _ui_menu.get_node_or_null("GuardarText") as Label
	_rotate_row = _ui_menu.get_node_or_null("RotateText") as Label

	# Una fila por acción, clonando el estilo de "GuardarText" (mismo tamaño, contorno y marco de botón)
	_action_rows.clear()
	if _save_row == null and not actions.is_empty():
		push_warning("InteractableObject: falta 'GuardarText' en UI Menu, se usa como modelo de las filas de acciones.")
	for action in actions:
		var row: Label = null
		if _save_row and action:
			row = _save_row.duplicate() as Label
			row.name = "Action_" + String(action.id)
			var icon := row.get_child(0) as AnimatedSprite2D
			ButtonPrompt.setup_row(row, icon, action.label, action.icon_frame)
			row.visible = false
			_ui_menu.add_child(row)
		_action_rows.append(row)


## Acomoda las filas visibles una debajo de otra: cerrar, guardar, acciones desbloqueadas, rotar.
func _rebuild_menu_rows() -> void:
	if _ui_menu == null:
		return
	_available_actions.clear()

	var ordered: Array[Label] = []
	if _close_row:
		ordered.append(_close_row)

	if _save_row:
		_save_row.visible = item != null
		if item != null:
			ordered.append(_save_row)

	for i in actions.size():
		var action: ObjectAction = actions[i]
		var row: Label = _action_rows[i] if i < _action_rows.size() else null
		if action == null or row == null:
			continue
		var unlocked: bool = action.required_item == null or Inventory.has_item(action.required_item)
		row.visible = unlocked or action.show_when_locked
		row.modulate = Color(1, 1, 1, 1.0 if unlocked else 0.4)
		if unlocked:
			_available_actions.append(action)
		if row.visible:
			ordered.append(row)

	if _rotate_row:
		_rotate_row.visible = viewer.is_ready_to_show()
		if _rotate_row.visible:
			ordered.append(_rotate_row)

	var top: float = _close_row.offset_top if _close_row else 109.0
	var step: float = ROW_STEP_DEFAULT
	if _close_row and _save_row:
		step = absf(_save_row.offset_top - _close_row.offset_top)
		if step < 1.0:
			step = ROW_STEP_DEFAULT
	for row in ordered:
		var height: float = row.offset_bottom - row.offset_top
		row.offset_top = top
		row.offset_bottom = top + height
		top += step


func _handle_menu_input(event: InputEvent) -> bool:
	if event.is_action_pressed("interact"):
		_close_inspection()
		return true
	if item != null and event.is_action_pressed("object_save"):
		_store_in_inventory()
		return true
	for action in _available_actions:
		if event.is_action_pressed(action.input_action):
			_trigger_action(action)
			return true
	return false


func _trigger_action(action: ObjectAction) -> void:
	var consumed: InventoryEntry = null
	if action.required_item != null:
		if not Inventory.has_item(action.required_item):
			return
		if action.consume_required_item:
			consumed = Inventory.remove_item(action.required_item)
	if action.close_menu_on_trigger and _is_inspecting:
		_close_inspection()
	action_triggered.emit(action, consumed)


# ---------------------------------------------------------------- INVENTARIO

## Guarda el objeto: sale del mundo y entra al Inventory. Se usa desde el menú (△).
func _store_in_inventory() -> void:
	if item == null:
		return

	# Plantilla para la vista previa 3D del inventario: la del ítem si define una escena, y si no,
	# el clon que ya está armado en el visor.
	var template: Dictionary
	if item.preview_scene != null:
		var instance: Node = item.preview_scene.instantiate()
		if instance is Node3D:
			template = ObjectViewer.build_template(instance as Node3D)
		instance.free()
	if template.is_empty():
		template = viewer.take_template()
	var template_node: Node3D = template.node if template.get("valid", false) else null
	var bounds: AABB = template.bounds if template.get("valid", false) else AABB()

	var entry: InventoryEntry = Inventory.add_item(item, self, template_node, bounds)
	if entry == null:
		return

	_close_inspection()
	_source.visible = false # ya no está en el mundo
	interaction_enabled = false
	stored.emit(item)


## Devuelve el objeto al mundo con un salto desde 'from_position' hasta 'to_position' y le crea una
## zona de interacción nueva donde aterriza, para poder volver a agarrarlo. (La zona original puede
## estar lejos: el objeto no tiene por qué volver al mismo lugar.)
func drop_to_world(from_position: Vector3, to_position: Vector3, hop_height: float = 0.2, duration: float = 0.5) -> void:
	if not is_instance_valid(_source):
		return
	interaction_enabled = false
	_source.visible = true
	_source.global_position = from_position

	if _drop_tween and _drop_tween.is_valid():
		_drop_tween.kill()
	_drop_tween = _source.create_tween()
	# Un salto principal y, al aterrizar, un rebote chico
	_drop_tween.tween_method(func(u: float):
		if not is_instance_valid(_source):
			return
		var position: Vector3
		if u < 0.7:
			var t: float = u / 0.7
			position = from_position.lerp(to_position, t) + Vector3.UP * hop_height * 4.0 * t * (1.0 - t)
		else:
			var t2: float = (u - 0.7) / 0.3
			position = to_position + Vector3.UP * hop_height * 0.3 * 4.0 * t2 * (1.0 - t2)
		_source.global_position = position
	, 0.0, 1.0, duration)
	_drop_tween.tween_callback(func():
		_spawn_drop_area(to_position)
		interaction_enabled = true
		dropped.emit(item)
	)


func _spawn_drop_area(world_position: Vector3) -> void:
	if is_instance_valid(_drop_area):
		_drop_area.queue_free()
	var area := Area3D.new()
	area.name = "DropArea"
	area.top_level = true # sin heredir la escala/rotación del objeto
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = drop_area_radius
	shape_node.shape = sphere
	area.add_child(shape_node)
	_source.add_child(area)
	area.global_position = world_position
	_drop_area = area
	bind_area(area)


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

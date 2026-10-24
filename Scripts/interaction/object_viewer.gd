extends Node
class_name ObjectViewer

## Visor 3D para inspeccionar un objeto: lo muestra dentro de un SubViewport con mundo propio y
## luz propia, lo encuadra solo y lo deja rotar con el stick derecho.
##
## Lo comparten el menú de los InteractableObject y el inventario. Funciona con "plantillas": un
## clon visual desconectado del árbol (solo mallas, sin scripts ni colisiones) más su volumen.
## Una plantilla se arma una vez (build_template) y se puede mostrar las veces que haga falta
## (show_template), incluso después de que el objeto original haya salido del mundo.
##
## El clon copia MeshInstance3D, MultiMeshInstance3D, Sprite3D y Label3D visibles.

var rotation_speed_degrees: float = 140.0 ## Velocidad con el stick al máximo (grados/seg)
var rotation_response_curve: float = 1.5 ## 1 = lineal; más alto = más fino cerca del centro
var invert_y: bool = false
var allow_zoom: bool = true ## Permite acercar el objeto (ver update_zoom)
var max_zoom: float = 3.0 ## Zoom máximo (1 = encuadre normal)
var zoom_rate: float = 1.6 ## Con gatillo o tecla: cambio de zoom por segundo (logarítmico: se siente parejo a cualquier zoom)
var zoom_wheel_step: float = 1.25 ## Factor por cada muesca de la rueda del mouse
var zoom_smooth: float = 14.0 ## Qué tan rápido el zoom real alcanza al pedido (1/s)
var drag_degrees_per_pixel: float = 0.45 ## Giro con el mouse: grados por píxel arrastrado
var auto_fit: bool = true ## Escala y centra el clon para que entre aunque se lo rote
var fit_fraction: float = 0.9 ## Cuánto del campo visual puede ocupar como máximo (0.1 a 1.0)
var scale_multiplier: float = 1.0
var light_energy: float = 1.3
var ambient_color: Color = Color(1.0, 1.0, 1.0)
var ambient_energy: float = 0.55

var viewport: SubViewport
var camera: Camera3D
var pivot: Node3D ## Se rota este nodo; el objeto cuelga de él ya centrado

var _stage: Node3D ## Clon que se está mostrando (cuelga de pivot)
var _current_template: Node3D ## Plantilla armada por show_source(), todavía en poder del visor
var _current_bounds: AABB = AABB()
var _ready_ok: bool = false
var _fitted_radius: float = 0.0
var _base_fov: float = 0.0 ## FOV de la cámara sin zoom (el encuadre se calcula con este)
var _zoom: float = 1.0
var _zoom_target: float = 1.0


## Prepara el SubViewport: mundo propio (sin esto el visor mostraría el nivel entero y el clon se
## iluminaría con sus luces), fondo transparente, luz y ambiente propios. Sin render hasta set_active().
func setup(p_viewport: SubViewport, p_camera: Camera3D, p_pivot: Node3D, texture_rect: TextureRect = null) -> bool:
	if p_viewport == null or p_camera == null or p_pivot == null:
		return false
	viewport = p_viewport
	camera = p_camera
	pivot = p_pivot
	_base_fov = camera.fov

	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	# Textura ligada directamente al viewport (no depende de rutas, sobrevive a los reparent)
	if texture_rect:
		texture_rect.texture = viewport.get_texture()

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy
	camera.environment = environment

	var light := DirectionalLight3D.new()
	light.name = "ViewerLight"
	light.light_energy = light_energy
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	viewport.add_child(light)

	_ready_ok = true
	return true


func _exit_tree() -> void:
	clear() # la plantilla armada está desconectada del árbol: no se libera sola


func is_ready_to_show() -> bool:
	return _ready_ok


## El visor solo renderiza mientras está activo (no gasta nada cuando el menú está cerrado).
func set_active(active: bool) -> void:
	if not _ready_ok:
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if active:
		camera.make_current()


# ---------------------------------------------------------------- MOSTRAR

## Muestra un clon de una plantilla ya armada (la plantilla no se modifica ni se consume).
func show_template(template: Node3D, bounds: AABB) -> void:
	if not _ready_ok or template == null:
		return
	reset_zoom() # el encuadre se calcula con el FOV sin zoom
	_free_stage()
	_stage = Node3D.new()
	_stage.name = "ObjectClone"
	_stage.add_child(template.duplicate(0))
	pivot.add_child(_stage)
	pivot.transform.basis = Basis.IDENTITY # se empieza viendo el objeto "de frente"
	_fit(bounds)


## Arma una plantilla a partir de un objeto del mundo y la muestra. El visor se queda con la
## plantilla hasta que se la pida con take_template() o se llame a clear().
func show_source(source: Node3D, exclude: Node = null) -> bool:
	_free_current_template()
	var built: Dictionary = build_template(source, exclude)
	if not built.valid:
		push_warning("ObjectViewer: no se encontraron mallas para clonar bajo " + str(source.name) + ".")
		(built.node as Node).free()
		return false
	_current_template = built.node
	_current_bounds = built.bounds
	show_template(_current_template, _current_bounds)
	return true


## Muestra una escena de vista previa (la instancia, arma la plantilla y la descarta).
func show_scene(scene: PackedScene) -> bool:
	if scene == null:
		return false
	var instance: Node = scene.instantiate()
	if not (instance is Node3D):
		instance.free()
		push_warning("ObjectViewer: la escena de vista previa debe tener un Node3D como raíz.")
		return false
	var ok: bool = show_source(instance as Node3D)
	instance.free()
	return ok


## Entrega la plantilla armada por show_source() a quien la pide (ej: el inventario), que pasa a
## ser su dueño y debe liberarla.
func take_template() -> Dictionary:
	if _current_template == null:
		return {"node": null, "bounds": AABB(), "valid": false}
	var result: Dictionary = {"node": _current_template, "bounds": _current_bounds, "valid": true}
	_current_template = null
	return result


func clear() -> void:
	reset_zoom()
	_free_stage()
	_free_current_template()


func _free_stage() -> void:
	if is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null


func _free_current_template() -> void:
	if is_instance_valid(_current_template):
		_current_template.free()
	_current_template = null


# ---------------------------------------------------------------- ZOOM

## Zoom del visor. No escala ni mueve el objeto (la rotación lo re-ortonormaliza y el encuadre depende de su
## tamaño): cierra el campo visual de la cámara, que es lo que hace una lente. Se pide con los gatillos
## (acciones image_zoom_in / image_zoom_out: R2 / L2, o las teclas E / Q) y con la rueda del mouse
## (handle_wheel_event). Con zoom la rotación se hace más lenta, para poder girar con precisión.
## Llamar cada cuadro mientras el visor está abierto.
func update_zoom(delta: float) -> void:
	if not _ready_ok or not allow_zoom or _base_fov <= 0.0:
		return
	var zoom_input: float = Input.get_action_strength("image_zoom_in") - Input.get_action_strength("image_zoom_out")
	if zoom_input != 0.0:
		_zoom_target = clampf(_zoom_target * exp(zoom_input * zoom_rate * delta), 1.0, max_zoom)
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-zoom_smooth * delta))
	if absf(_zoom - _zoom_target) < 0.001:
		_zoom = _zoom_target
	_apply_zoom()


## Rueda del mouse: acerca o aleja. Devuelve true si el evento se usó.
func handle_wheel_event(event: InputEventMouseButton) -> bool:
	if not allow_zoom or not event.pressed:
		return false
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_target = minf(_zoom_target * zoom_wheel_step, max_zoom)
		return true
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_target = maxf(_zoom_target / zoom_wheel_step, 1.0)
		return true
	return false


func reset_zoom() -> void:
	_zoom = 1.0
	_zoom_target = 1.0
	if camera and _base_fov > 0.0:
		camera.fov = _base_fov


func get_zoom() -> float:
	return _zoom


func _apply_zoom() -> void:
	# Con zoom Z se ve 1/Z del ancho de la escena: de ahí la tangente (el FOV no es lineal con el aumento)
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_base_fov) * 0.5) / _zoom))


## Rotación más lenta cuanto más zoom (a 4x gira la mitad de rápido).
func _zoom_damping() -> float:
	return 1.0 / sqrt(_zoom)


# ---------------------------------------------------------------- ROTACIÓN

func reset_rotation() -> void:
	if pivot:
		pivot.transform.basis = Basis.IDENTITY


## Rotación libre con el stick derecho. Se compone en los ejes de la CÁMARA (no del objeto), así
## "derecha" siempre gira hacia la derecha sin importar cómo haya quedado el objeto.
func rotate_with_stick(delta: float) -> void:
	if pivot == null:
		return
	var stick: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick == Vector2.ZERO:
		return

	var strength: float = pow(stick.length(), rotation_response_curve)
	var dir: Vector2 = stick.normalized() * strength
	var step: float = deg_to_rad(rotation_speed_degrees) * delta * _zoom_damping()

	var yaw: float = dir.x * step # stick a la derecha => la cara frontal gira hacia la derecha
	var pitch: float = dir.y * step * (-1.0 if invert_y else 1.0) # stick arriba => la cara frontal sube

	var rotation_step: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	pivot.transform.basis = (rotation_step * pivot.transform.basis).orthonormalized()


## Rotación arrastrando el mouse (botón izquierdo), con los mismos ejes de cámara que el stick.
func rotate_by_drag(relative: Vector2) -> void:
	if pivot == null or relative == Vector2.ZERO:
		return
	var per_pixel: float = deg_to_rad(drag_degrees_per_pixel) * _zoom_damping()
	var yaw: float = relative.x * per_pixel
	var pitch: float = relative.y * per_pixel * (-1.0 if invert_y else 1.0)
	var rotation_step: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	pivot.transform.basis = (rotation_step * pivot.transform.basis).orthonormalized()


# ---------------------------------------------------------------- ENCUADRE

## Centra el clon sobre el pivote (para que gire sobre su centro y quede fijo) y, si auto_fit está
## activo, lo escala para que ni siquiera la punta más lejana se salga del visor.
func _fit(bounds: AABB) -> void:
	if _stage == null:
		return
	var center: Vector3 = bounds.get_center()
	var radius: float = bounds.size.length() * 0.5 # esfera que contiene a la caja: rote como rote, entra

	var fit_scale: float = scale_multiplier
	if auto_fit and radius > 0.0001:
		var distance: float = camera.transform.origin.distance_to(pivot.transform.origin)
		var half_fov: float = deg_to_rad(_base_fov if _base_fov > 0.0 else camera.fov) * 0.5
		var target_radius: float = distance * sin(half_fov * fit_fraction)
		fit_scale = (target_radius / radius) * scale_multiplier

	_stage.scale = Vector3.ONE * fit_scale
	_stage.position = -center * fit_scale
	_fitted_radius = radius * fit_scale


## Radio (en unidades del visor) que ocupa el objeto mostrado. Útil para pruebas.
func get_fitted_radius() -> float:
	return _fitted_radius


# ---------------------------------------------------------------- CLONADO

## Arma una plantilla (clon visual desconectado del árbol) de 'source' y de sus descendientes.
## 'exclude' es un nodo a ignorar (típicamente el propio InteractableObject, para no clonarse a sí
## mismo). Devuelve {"node": Node3D, "bounds": AABB, "valid": bool}; 'valid' es false si no hay mallas.
## El llamador es dueño de "node" y debe liberarlo.
static func build_template(source: Node3D, exclude: Node = null) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "Template"
	var state: Dictionary = {"bounds": AABB(), "has": false}

	# El propio objeto, si es una malla, va con transform identidad (se muestra "en reposo",
	# sin su posición/rotación/escala en el mundo)
	if _is_cloneable_visual(source):
		var root_copy: Node3D = _duplicate_visual(source)
		root_copy.transform = Transform3D.IDENTITY
		holder.add_child(root_copy)
		_grow_bounds(state, source, Transform3D.IDENTITY)

	_clone_children(source, holder, Transform3D.IDENTITY, exclude, state)
	return {"node": holder, "bounds": state.bounds, "valid": state.has}


## Replica la jerarquía del objeto: las mallas se copian y el resto se reemplaza por un Node3D
## vacío, para conservar las transformaciones relativas.
static func _clone_children(src: Node, dst_parent: Node3D, accumulated: Transform3D, exclude: Node, state: Dictionary) -> void:
	for child in src.get_children():
		if child == exclude or not (child is Node3D):
			continue # ni al excluido (recursión) ni lo que no sea 3D (UI, audio, etc.)
		var node: Node3D = child as Node3D
		if not node.visible:
			continue

		var node_transform: Transform3D = accumulated * node.transform
		var copy: Node3D
		if _is_cloneable_visual(node):
			copy = _duplicate_visual(node)
			_grow_bounds(state, node, node_transform)
		else:
			copy = Node3D.new()
		copy.transform = node.transform
		dst_parent.add_child(copy)
		_clone_children(node, copy, node_transform, exclude, state)


static func _is_cloneable_visual(node: Node) -> bool:
	return node is MeshInstance3D or node is MultiMeshInstance3D or node is Sprite3D or node is Label3D


## Copia solo el nodo: sin scripts, señales ni grupos (flags = 0) y sin hijos.
static func _duplicate_visual(node: Node3D) -> Node3D:
	var copy: Node3D = node.duplicate(0) as Node3D
	for grandchild in copy.get_children():
		copy.remove_child(grandchild)
		grandchild.free()
	return copy


static func _grow_bounds(state: Dictionary, node: Node, node_transform: Transform3D) -> void:
	var local_aabb: AABB = (node as VisualInstance3D).get_aabb()
	if local_aabb.size == Vector3.ZERO:
		return
	var world_aabb: AABB = node_transform * local_aabb
	if state.has:
		state.bounds = (state.bounds as AABB).merge(world_aabb)
	else:
		state.bounds = world_aabb
		state.has = true

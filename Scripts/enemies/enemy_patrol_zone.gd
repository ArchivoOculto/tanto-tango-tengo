class_name EnemyPatrolZone
extends Area3D

## Territorio de los enemigos. Su Area3D (CollisionShape3D) define:
##  - por dónde pueden moverse: los enemigos de la zona nunca salen de ella (ver Enemy._keep_inside_zone),
##  - dónde pueden REAPARECER: en cualquier punto de la zona (ver get_random_point), no en posiciones fijas,
##  - cuándo detectan al jugador (is_player_inside / player_ref).

## Capas físicas que cuentan como piso al buscar dónde apoyar un enemigo que reaparece (1 = el decorado).
@export_flags_3d_physics var floor_mask: int = 1

var is_player_inside: bool = false
var player_ref: Node3D = null

var _shape_nodes: Array[CollisionShape3D] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Asignación segura diferida para evitar race-conditions con el árbol de nodos
	_assign_initial_enemies.call_deferred()


func _assign_initial_enemies() -> void:
	await get_tree().physics_frame
	
	# Detectar cualquier enemigo posicionado dentro de esta zona
	for body in get_overlapping_bodies():
		if body is Enemy and body.zone_area == null:
			body.zone_area = self


## ¿El punto (mundo) está dentro de la zona? Se mide en planta (XZ): la altura no cuenta.
func contains_point(world_point: Vector3) -> bool:
	for shape_node in _shapes():
		if AreaShapes.contains_xz(shape_node, world_point):
			return true
	return false


## Punto al azar DENTRO de la zona, apoyado en el piso (mundo). Se tira un rayo desde arriba de la zona
## hacia abajo; si no encuentra piso, usa la altura central de la zona.
func get_random_point() -> Vector3:
	var shape_node: CollisionShape3D = AreaShapes.pick_weighted(_shapes())
	if shape_node == null:
		return global_position
	var top: Vector3 = AreaShapes.random_top_point(shape_node)
	var bottom: Vector3 = top + Vector3.DOWN * (AreaShapes.height_of(shape_node) + 1.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(top, bottom, floor_mask)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
	return Vector3(top.x, shape_node.global_position.y, top.z)


func _shapes() -> Array[CollisionShape3D]:
	if _shape_nodes.is_empty():
		_shape_nodes = AreaShapes.shapes_of(self)
	return _shape_nodes


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		is_player_inside = true
		player_ref = body
	elif body is Enemy and body.zone_area == null:
		body.zone_area = self


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		is_player_inside = false
		player_ref = null

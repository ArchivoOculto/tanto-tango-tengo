extends RefCounted
class_name AreaShapes

## Utilidades para consultar la FORMA de un Area3D (sus CollisionShape3D hijos). Las usan la zona de
## patrulla de los enemigos (EnemyPatrolZone: "¿está adentro?" y "un punto al azar") y la radio
## (Radio: "el punto de su zona de golpes más cercano a un enemigo").
##
## Soporta BoxShape3D y SphereShape3D (y Cylinder/Capsule solo como círculo en planta). Los puntos y las
## pruebas "en planta" (XZ) están pensados para zonas apoyadas en el piso, giradas a lo sumo sobre Y.


## CollisionShape3D activos (hijos directos) del área.
static func shapes_of(area: Area3D) -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	if not is_instance_valid(area):
		return result
	for child in area.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node != null and not shape_node.disabled and shape_node.shape != null:
			result.append(shape_node)
	return result


## ¿El punto (mundo) cae dentro de la planta (XZ) de la forma? Ignora la altura: un enemigo parado en el
## piso cuenta como "adentro" aunque la zona esté más arriba o más abajo.
static func contains_xz(shape_node: CollisionShape3D, world_point: Vector3) -> bool:
	var local: Vector3 = shape_node.global_transform.affine_inverse() * world_point
	var box := shape_node.shape as BoxShape3D
	if box != null:
		return absf(local.x) <= box.size.x * 0.5 and absf(local.z) <= box.size.z * 0.5
	var radius: float = _radius_of(shape_node.shape)
	if radius > 0.0:
		return Vector2(local.x, local.z).length() <= radius
	return false


## Punto al azar sobre la CARA SUPERIOR de la forma (mundo), repartido parejo en planta. Desde ahí se puede
## tirar un rayo hacia abajo para encontrar el piso.
static func random_top_point(shape_node: CollisionShape3D) -> Vector3:
	var shape: Shape3D = shape_node.shape
	var local := Vector3.ZERO
	var box := shape as BoxShape3D
	if box != null:
		local = Vector3(randf_range(-0.5, 0.5) * box.size.x, box.size.y * 0.5, randf_range(-0.5, 0.5) * box.size.z)
	else:
		var offset: Vector2 = Vector2.from_angle(randf() * TAU) * _radius_of(shape) * sqrt(randf())
		local = Vector3(offset.x, _half_height_of(shape), offset.y)
	return shape_node.global_transform * local


## Alto total de la forma en el mundo (con la escala del nodo).
static func height_of(shape_node: CollisionShape3D) -> float:
	return _half_height_of(shape_node.shape) * 2.0 * absf(shape_node.global_transform.basis.get_scale().y)


## Elige una forma con probabilidad proporcional a su superficie en planta (para repartir parejo entre varias).
static func pick_weighted(shape_nodes: Array[CollisionShape3D]) -> CollisionShape3D:
	if shape_nodes.is_empty():
		return null
	var total: float = 0.0
	for shape_node in shape_nodes:
		total += _footprint_area(shape_node)
	if total <= 0.0:
		return shape_nodes[0]
	var roll: float = randf() * total
	for shape_node in shape_nodes:
		roll -= _footprint_area(shape_node)
		if roll <= 0.0:
			return shape_node
	return shape_nodes[shape_nodes.size() - 1]


## Punto de la forma (mundo) más cercano a 'world_point'. Si el punto está adentro, lo devuelve tal cual.
## Con formas que no sabe medir, devuelve el centro.
static func closest_point(shape_node: CollisionShape3D, world_point: Vector3) -> Vector3:
	var transform: Transform3D = shape_node.global_transform
	var local: Vector3 = transform.affine_inverse() * world_point
	var box := shape_node.shape as BoxShape3D
	if box != null:
		var half: Vector3 = box.size * 0.5
		return transform * local.clamp(-half, half)
	var sphere := shape_node.shape as SphereShape3D
	if sphere != null:
		if local.length() > sphere.radius:
			local = local.normalized() * sphere.radius
		return transform * local
	return shape_node.global_position


static func _footprint_area(shape_node: CollisionShape3D) -> float:
	var scale: Vector3 = shape_node.global_transform.basis.get_scale().abs()
	var box := shape_node.shape as BoxShape3D
	if box != null:
		return box.size.x * scale.x * box.size.z * scale.z
	var radius: float = _radius_of(shape_node.shape)
	return PI * radius * radius * scale.x * scale.z


static func _radius_of(shape: Shape3D) -> float:
	var sphere := shape as SphereShape3D
	if sphere != null:
		return sphere.radius
	var cylinder := shape as CylinderShape3D
	if cylinder != null:
		return cylinder.radius
	var capsule := shape as CapsuleShape3D
	if capsule != null:
		return capsule.radius
	return 0.0


static func _half_height_of(shape: Shape3D) -> float:
	var box := shape as BoxShape3D
	if box != null:
		return box.size.y * 0.5
	var sphere := shape as SphereShape3D
	if sphere != null:
		return sphere.radius
	var cylinder := shape as CylinderShape3D
	if cylinder != null:
		return cylinder.height * 0.5
	var capsule := shape as CapsuleShape3D
	if capsule != null:
		return capsule.height * 0.5
	return 0.0

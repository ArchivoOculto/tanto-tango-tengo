extends NavigationRegion3D
class_name RuntimeNavigation

## Malla de navegación para que los enemigos rodeen alambrados y paredes camino a la radio (estado
## ATTACK_OBJECT).
##
## RENDIMIENTO: en el juego NO se hornea nada. Se usa una malla ya horneada
## (Resources/navigation/level0_navmesh.tres), así que el costo en ejecución es solo cargar un recurso
## chico y consultar caminos (unos pocos por segundo). Hornear en tiempo de ejecución obliga a leer
## mallas de la GPU y es lo que el motor desaconseja.
##
## Para volver a hornearla (si cambia el decorado): en el Level00Manager activar 'rebake_navigation_now',
## correr el nivel UNA vez desde el editor (se guarda sola en el .tres) y desactivarlo.

signal baked

@export_group("Geometría")
## Capas físicas que cuentan como obstáculo/suelo (1 = el decorado).
@export_flags_3d_physics var collision_mask: int = 1

@export_group("Agente (el enemigo)")
@export var agent_radius: float = 0.15
@export var agent_height: float = 0.4
@export var agent_max_climb: float = 0.1
@export var cell_size: float = 0.1

var is_ready: bool = false

## Si no está vacío (y se corre desde el editor), la malla horneada se guarda en este archivo.
var save_path: String = ""


## Hornea alrededor de 'bounds' (coordenadas de mundo), parseando las colisiones bajo 'source_root'.
func bake_area(source_root: Node, bounds: AABB) -> void:
	var map: RID = get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, cell_size)
	NavigationServer3D.map_set_cell_height(map, cell_size)

	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_mesh.geometry_collision_mask = collision_mask
	nav_mesh.cell_size = cell_size
	nav_mesh.cell_height = cell_size
	nav_mesh.agent_radius = agent_radius
	nav_mesh.agent_height = agent_height
	nav_mesh.agent_max_climb = agent_max_climb
	nav_mesh.agent_max_slope = 50.0
	nav_mesh.filter_baking_aabb = bounds

	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, source_root)
	NavigationServer3D.bake_from_source_geometry_data_async(nav_mesh, source, func():
		navigation_mesh = nav_mesh
		is_ready = true
		if save_path != "" and OS.has_feature("editor"):
			var error: Error = ResourceSaver.save(nav_mesh, save_path)
			print("RuntimeNavigation: malla guardada en %s (%s)" % [save_path, error_string(error)])
		baked.emit()
	)


## Usa una malla ya horneada (sin costo de horneado). Hay que llamarlo con el nodo ya en el árbol.
func use_prebaked(nav_mesh: NavigationMesh) -> void:
	var map: RID = get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nav_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map, nav_mesh.cell_height)
	navigation_mesh = nav_mesh
	is_ready = true
	baked.emit()


## Camino (puntos de mundo) de 'from' a 'to' por la malla; vacío si todavía no se horneó o no hay camino.
static func find_path(world: World3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var map: RID = world.navigation_map
	if NavigationServer3D.map_get_regions(map).is_empty():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map, from, to, true)

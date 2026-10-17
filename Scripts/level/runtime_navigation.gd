extends NavigationRegion3D
class_name RuntimeNavigation

## Genera en tiempo de ejecución una malla de navegación a partir de las colisiones estáticas del nivel,
## para que los enemigos puedan rodear alambrados y paredes (el estado ATTACK_OBJECT los manda a la radio,
## que está del otro lado del corral). No hace falta hornear nada en el editor.
##
## Solo se hornea una zona (filter_aabb), no todo el nivel, para que sea rápido. La hornea Level00Manager
## al iniciar, en un hilo aparte (no traba el juego).

signal baked

@export_group("Geometría")
## Capas físicas que cuentan como obstáculo/suelo (1 = el decorado).
@export_flags_3d_physics var collision_mask: int = 1

@export_group("Agente (el enemigo)")
@export var agent_radius: float = 0.15
@export var agent_height: float = 0.4
@export var agent_max_climb: float = 0.1
@export var cell_size: float = 0.05

var is_ready: bool = false


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
		baked.emit()
	)


## Camino (puntos de mundo) de 'from' a 'to' por la malla; vacío si todavía no se horneó o no hay camino.
static func find_path(world: World3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var map: RID = world.navigation_map
	if NavigationServer3D.map_get_regions(map).is_empty():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map, from, to, true)

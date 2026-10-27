extends Node

## Autoload "RenderProfile": adapta la escena cuando el juego corre con el renderer Compatibility (OpenGL), que es el
## único que existe en la versión WEB y el de reserva en PC sin Vulkan ni D3D12 (project.godot ya cae solo a él).
## Con Forward+ (el normal en PC) no hace nada.
##
## El renderer Compatibility no soporta tres cosas que el nivel usa, y esto las reemplaza sin tocar las escenas:
##
##  - Niebla volumétrica (y FogVolume): se apaga. Lo que queda es la niebla de profundidad común, que con el color por
##    defecto (gris azulado claro) vuelve pálido todo lo lejano: se oscurece (FOG_COLOR) para que la noche se vea como
##    en PC. Los números salen de comparar capturas de los dos renderers del mismo punto del nivel.
##  - Estelas de partículas (trail_enabled), con las que se dibuja la lluvia: se reemplazan por rayitas alineadas con la
##    velocidad de cada gota (una QuadMesh fina que mira a la cámara).
##
## Las escenas se adaptan al entrar al árbol; la mutación vive solo en memoria (no modifica ningún archivo).

const COMPATIBILITY: String = "gl_compatibility"
const FOG_COLOR: Color = Color(0.035, 0.04, 0.055)
const FOG_DENSITY: float = 0.02
const RAIN_STREAK_SIZE: Vector2 = Vector2(0.012, 0.35) ## ancho x largo (m) de cada gota
const RAIN_ALPHA_BOOST: float = 2.0 ## las gotas de PC son muy tenues (4 % de opacidad); sin la estela suavizada necesitan algo más

var active: bool = false


func _ready() -> void:
	active = RenderingServer.get_current_rendering_method() == COMPATIBILITY
	if not active:
		return
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_adapt_environment.call_deferred(node) # el resto de la escena todavía se está armando
	elif node is GPUParticles3D:
		_adapt_particles.call_deferred(node)
	elif node is FogVolume:
		(node as FogVolume).visible = false # no existen en Compatibility


func _adapt_environment(world_environment: WorldEnvironment) -> void:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment
	environment.volumetric_fog_enabled = false
	if environment.fog_enabled:
		environment.fog_light_color = FOG_COLOR
		environment.fog_density = FOG_DENSITY


## Lluvia sin estelas: la malla de cinta (RibbonTrailMesh) pasa a una rayita alineada con la velocidad.
func _adapt_particles(particles: GPUParticles3D) -> void:
	if not is_instance_valid(particles) or not particles.trail_enabled:
		return
	particles.trail_enabled = false

	var streak := QuadMesh.new()
	streak.size = RAIN_STREAK_SIZE
	var source_material: Material = null
	if particles.draw_pass_1 is RibbonTrailMesh:
		source_material = (particles.draw_pass_1 as RibbonTrailMesh).material
	elif particles.draw_pass_1 is TubeTrailMesh:
		source_material = (particles.draw_pass_1 as TubeTrailMesh).material
	var material: BaseMaterial3D = source_material.duplicate() as BaseMaterial3D if source_material is BaseMaterial3D else StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.albedo_color.a = minf(material.albedo_color.a * RAIN_ALPHA_BOOST, 1.0)
	streak.material = material
	particles.draw_pass_1 = streak

	if particles.process_material is ParticleProcessMaterial:
		var process_material: ParticleProcessMaterial = (particles.process_material as ParticleProcessMaterial).duplicate()
		process_material.particle_flag_align_y = true
		particles.process_material = process_material

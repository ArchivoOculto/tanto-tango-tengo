extends Node3D
class_name Farolito

signal toggled(is_on: bool)

@export_group("Estado Inicial")
@export var is_on: bool = true ## Determina si la farola arranca encendida o apagada

@export_group("Sacudida")
@export var shake_duration: float = 0.35
@export var shake_strength: float = 0.15

@export_group("Efecto Strobo")
@export var strobo_flashes: int = 4
@export var strobo_speed: float = 0.04

@export_group("Aleatoriedad (%)")
@export_range(0.0, 1.0) var variance_factor: float = 0.75 ## Porcentaje de variación aleatoria (+/- 75%)

@export_group("Interacciones / Eventos")
## Puedes asignarle un Callable por código para ejecutar eventos personalizados al ser golpeada.
## Ej: farol.on_hit_callback = func(farol_state): mi_camzone_manager.forzar_camara(...)
@export var on_hit_callback: Callable

@onready var light: SpotLight3D = $SpotLight3D
@onready var mesh: MeshInstance3D = $Light_LampPost_Posters_LOD0

var _is_shaking: bool = false
var _original_rotation: Vector3
var _off_material: StandardMaterial3D


func _ready() -> void:
	if mesh:
		_original_rotation = mesh.rotation

	_off_material = StandardMaterial3D.new()
	_off_material.albedo_color = Color.BLACK
	_off_material.metallic = 0.1
	_off_material.roughness = 0.8

	# Aplicar el estado inicial configurado desde el Inspector
	if light:
		light.visible = is_on
	_set_mesh_on_state(is_on)


func take_hit(_damage: float = 0.0) -> void:
	is_on = not is_on
	toggled.emit(is_on)

	# Ejecutar el callback de interacción personalizada si fue asignado
	if on_hit_callback.is_valid():
		on_hit_callback.call(is_on)

	# Randomizamos los parámetros en el instante exacto del impacto
	var current_shake_duration: float = shake_duration * randf_range(1.0 - variance_factor, 1.0 + variance_factor)
	var current_shake_strength: float = shake_strength * randf_range(1.0 - variance_factor, 1.0 + variance_factor)
	var current_strobo_speed: float = strobo_speed * randf_range(1.0 - variance_factor, 1.0 + variance_factor)

	# Variación de flashes (+/- destellos)
	var flash_variation: int = int(round(strobo_flashes * variance_factor))
	var current_flashes: int = max(1, strobo_flashes + randi_range(-flash_variation, flash_variation))

	_play_strobo_effect(current_flashes, current_strobo_speed)
	_play_shake_animation(current_shake_duration, current_shake_strength)


func _play_strobo_effect(flashes: int, speed: float) -> void:
	if not light:
		return

	var tween: Tween = create_tween()

	for i in range(flashes):
		tween.tween_callback(func():
			# Alternar visibilidad de la luz
			light.visible = not light.visible
			# Sincronizar el material con el estado actual de la luz
			_set_mesh_on_state(light.visible)
		)
		
		# Variación micro-aleatoria cuadro a cuadro dentro del mismo parpadeo
		var micro_speed: float = speed * randf_range(0.8, 1.2)
		tween.tween_interval(micro_speed)

	# Asegurar estado final correcto al terminar la animación
	tween.finished.connect(func():
		light.visible = is_on
		_set_mesh_on_state(is_on)
	)


func _set_mesh_on_state(is_light_on: bool) -> void:
	if not mesh:
		return

	if is_light_on:
		mesh.material_override = null
	else:
		mesh.material_override = _off_material


func _play_shake_animation(duration: float, strength: float) -> void:
	if not mesh or _is_shaking:
		return

	_is_shaking = true
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var step_time: float = duration / 4.0

	# Genera rotaciones asimétricas para que la inclinación cambie cada vez
	var rot_x1: float = randf_range(-strength, strength)
	var rot_z1: float = randf_range(-strength, strength)
	var rot_x2: float = -rot_x1 * randf_range(0.3, 0.6)
	var rot_z2: float = -rot_z1 * randf_range(0.3, 0.6)

	tween.tween_property(mesh, "rotation:x", _original_rotation.x + rot_x1, step_time)
	tween.parallel().tween_property(mesh, "rotation:z", _original_rotation.z + rot_z1, step_time)

	tween.tween_property(mesh, "rotation:x", _original_rotation.x + rot_x2, step_time)
	tween.parallel().tween_property(mesh, "rotation:z", _original_rotation.z + rot_z2, step_time)

	tween.tween_property(mesh, "rotation", _original_rotation, step_time)
	tween.finished.connect(func(): _is_shaking = false)
	
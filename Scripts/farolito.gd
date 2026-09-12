extends Node3D
class_name Farolito

signal toggled(is_on: bool)

enum State { FLICKERING, ON, OFF }

@export_group("Estado Inicial")
@export var initial_state: State = State.ON ## ON = Interruptor común (ON/OFF). FLICKERING = Farol de puzzle (FLICKERING/ON).

@export_group("Efecto Titilante (Ambiental)")
@export var min_flicker_pause: float = 0.4 ## Pausa mínima apagada entre chispazos
@export var max_flicker_pause: float = 1.8 ## Pausa máxima apagada entre chispazos

@export_group("Sacudida")
@export var shake_duration: float = 0.35
@export var shake_strength: float = 0.15

@export_group("Efecto Strobo")
@export var strobo_flashes: int = 4
@export var strobo_speed: float = 0.04

@export_group("Aleatoriedad (%)")
@export_range(0.0, 1.0) var variance_factor: float = 0.75 ## Porcentaje de variación aleatoria (+/- 75%)

@export_group("Interacciones / Eventos")
@export var on_hit_callback: Callable

@onready var light: SpotLight3D = $SpotLight3D
@onready var mesh: MeshInstance3D = $Light_LampPost_Posters_LOD0

var current_state: State
var _is_shaking: bool = false
var _original_rotation: Vector3
var _off_material: StandardMaterial3D

var _flicker_tween: Tween
var _hit_strobo_tween: Tween

# Getter para mantener compatibilidad total con FarolitoPuzzleTrigger y otros scripts
var is_on: bool:
	get: return current_state == State.ON


func _ready() -> void:
	if mesh:
		_original_rotation = mesh.rotation

	_off_material = StandardMaterial3D.new()
	_off_material.albedo_color = Color.BLACK
	_off_material.metallic = 0.1
	_off_material.roughness = 0.8

	current_state = initial_state
	_apply_current_state()


func take_hit(_damage: float = 0.0) -> void:
	_kill_flicker_tween()

	# --- LÓGICA DE TRANSICIÓN SEGÚN DISEÑO ---
	if initial_state == State.FLICKERING:
		# Faroles de puzzle: solo alternan entre FLICKERING y ON
		if current_state == State.FLICKERING:
			current_state = State.ON
		else:
			current_state = State.FLICKERING
	else:
		# Faroles normales (ON u OFF inicial): solo alternan entre ON y OFF
		if current_state == State.ON:
			current_state = State.OFF
		else:
			current_state = State.ON

	var is_active: bool = (current_state == State.ON)
	toggled.emit(is_active)

	if on_hit_callback.is_valid():
		on_hit_callback.call(is_active)

	# Variación aleatoria del impacto
	var current_shake_duration: float = shake_duration * randf_range(1.0 - variance_factor, 1.0 + variance_factor)
	var current_shake_strength: float = shake_strength * randf_range(1.0 - variance_factor, 1.0 + variance_factor)
	var current_strobo_speed: float = strobo_speed * randf_range(1.0 - variance_factor, 1.0 + variance_factor)

	var flash_variation: int = int(round(strobo_flashes * variance_factor))
	var current_flashes: int = max(1, strobo_flashes + randi_range(-flash_variation, flash_variation))

	_play_hit_strobo_effect(current_flashes, current_strobo_speed)
	_play_shake_animation(current_shake_duration, current_shake_strength)


func _apply_current_state() -> void:
	_kill_flicker_tween()

	match current_state:
		State.ON:
			_set_light_and_mesh(true)
		State.OFF:
			_set_light_and_mesh(false)
		State.FLICKERING:
			_trigger_next_flicker_step()


# --- BUCLE AMBIENTAL ALEATORIO (RECURSIVO) ---
func _trigger_next_flicker_step() -> void:
	if current_state != State.FLICKERING:
		return

	_kill_flicker_tween()
	_flicker_tween = create_tween()

	var flash_variation: int = int(round(strobo_flashes * variance_factor))
	var current_flashes: int = max(1, strobo_flashes + randi_range(-flash_variation, flash_variation))
	var current_strobo_speed: float = strobo_speed * randf_range(1.0 - variance_factor, 1.0 + variance_factor)

	# 1. Ráfaga de chispazos
	for i in range(current_flashes):
		_flicker_tween.tween_callback(func():
			_set_light_and_mesh(not light.visible)
		)
		var micro_speed: float = current_strobo_speed * randf_range(0.8, 1.2)
		_flicker_tween.tween_interval(micro_speed)

	# 2. Queda apagada al terminar la ráfaga
	_flicker_tween.tween_callback(func():
		_set_light_and_mesh(false)
	)

	# 3. Pausa aleatoria corta entre ráfagas
	var random_pause: float = randf_range(min_flicker_pause, max_flicker_pause)
	_flicker_tween.tween_interval(random_pause)
	_flicker_tween.finished.connect(_trigger_next_flicker_step)


# --- EFECTO VISUAL AL GOLPEAR ---
func _play_hit_strobo_effect(flashes: int, speed: float) -> void:
	if _hit_strobo_tween and _hit_strobo_tween.is_valid():
		_hit_strobo_tween.kill()

	_hit_strobo_tween = create_tween()

	for i in range(flashes):
		_hit_strobo_tween.tween_callback(func():
			_set_light_and_mesh(not light.visible)
		)
		var micro_speed: float = speed * randf_range(0.8, 1.2)
		_hit_strobo_tween.tween_interval(micro_speed)

	_hit_strobo_tween.finished.connect(func():
		if current_state == State.FLICKERING:
			_trigger_next_flicker_step()
		else:
			_apply_current_state()
	)


func _set_light_and_mesh(is_light_on: bool) -> void:
	if light:
		light.visible = is_light_on

	if mesh:
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


func _kill_flicker_tween() -> void:
	if _flicker_tween and _flicker_tween.is_valid():
		_flicker_tween.kill()
extends Node

## Autoload (Project Settings > Autoload, nombre "WarpManager").
## Responsable de:
##  1) el fundido a negro compartido por todos los warps (local y externo),
##  2) el cambio de escena para los warps externos,
##  3) ubicar al jugador en el SpawnPoint3D correspondiente tras cargar, y
##  4) sincronizar la GameCamera con la CameraZone3D del destino de forma
##     instantánea, para que no se vea el smoothing normal de seguimiento.

@export var fade_color: Color = Color.BLACK

var _pending_spawn_id: StringName = &""
var _fade_rect: ColorRect


func _ready() -> void:
	_build_fade_layer()


# --- REUBICACIÓN DEL JUGADOR (compartida por warp local y externo) ---

## Mueve al jugador a 'target_transform' y, si se indica 'camera_zone',
## fuerza a la GameCamera a asentarse ahí de forma inmediata (sin
## smoothing), en vez de esperar a que la detección física de la Area3D
## la alcance un frame después con un desplazamiento visible.
func relocate_player(player: Node3D, target_transform: Transform3D, camera_zone: CameraZone3D = null) -> void:
	player.global_transform = target_transform
	if player is CharacterBody3D:
		player.velocity = Vector3.ZERO

	if camera_zone == null:
		push_warning("WarpManager: relocate_player() sin 'camera_zone' — la cámara puede deslizarse visiblemente tras el warp.")
		return

	CameraDirector.reset_to_zone(camera_zone)

	var cam: GameCamera = get_tree().get_first_node_in_group("game_camera")
	if is_instance_valid(cam):
		cam.snap_to_zone(camera_zone)


# --- WARP EXTERNO (cambio de escena) ---
func warp_to_scene(scene: PackedScene, spawn_id: StringName, fade_duration: float = 0.3) -> void:
	if scene == null:
		push_error("WarpManager: 'scene' es null, no se puede warpear.")
		return

	_pending_spawn_id = spawn_id

	await fade_out(fade_duration)
	get_tree().change_scene_to_packed(scene)

	# El reemplazo real del árbol ocurre en tiempo diferido (idle time).
	# Esperamos dos frames para asegurarnos de que la nueva escena y su
	# jugador ya están listos antes de intentar ubicarlo.
	await get_tree().process_frame
	await get_tree().process_frame

	_place_player_at_pending_spawn()
	await fade_in(fade_duration)


func _place_player_at_pending_spawn() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		push_warning("WarpManager: no hay ningún nodo en el grupo 'player' en la escena cargada.")
		return

	var spawn_point: SpawnPoint3D = _find_spawn_point(_pending_spawn_id)
	if spawn_point == null:
		push_warning("WarpManager: no se encontró un SpawnPoint3D con id '%s'." % _pending_spawn_id)
		return

	relocate_player(player, spawn_point.global_transform, spawn_point.camera_zone)


func _find_spawn_point(spawn_id: StringName) -> SpawnPoint3D:
	for node in get_tree().get_nodes_in_group("spawn_point"):
		if node is SpawnPoint3D and node.spawn_id == spawn_id:
			return node
	return null


# --- FUNDIDO (lo usan tanto los warps locales como los externos) ---
func fade_out(duration: float) -> void:
	if duration <= 0.0:
		_fade_rect.modulate.a = 1.0
		return
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, duration)
	await tween.finished


func fade_in(duration: float) -> void:
	if duration <= 0.0:
		_fade_rect.modulate.a = 0.0
		return
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, duration)
	await tween.finished


# --- SETUP INTERNO ---
func _build_fade_layer() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 128 # Por encima de cualquier UI de juego
	add_child(layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = fade_color
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	layer.add_child(_fade_rect)

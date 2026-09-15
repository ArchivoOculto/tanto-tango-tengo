@tool
extends Area3D
class_name WarpZone3D

## Área que teletransporta al jugador. Dos modos:
##  - LOCAL: mueve al jugador a un Marker3D dentro de esta misma escena.
##  - EXTERNAL_SCENE: carga otra escena y lo ubica en el SpawnPoint3D indicado.

enum WarpMode { LOCAL, EXTERNAL_SCENE }

@export var warp_mode: WarpMode = WarpMode.LOCAL:
	set(value):
		warp_mode = value
		notify_property_list_changed() # refresca qué campos se ven en el Inspector

@export_group("Warp Local")
@export var local_target: Marker3D ## Punto de destino dentro de esta misma escena

@export_group("Warp Externo")
@export var target_scene: PackedScene ## Escena a cargar
@export var target_spawn_id: StringName = &"default" ## Debe coincidir con el spawn_id de un SpawnPoint3D en la escena destino

@export_group("Comportamiento")
@export var one_shot: bool = false ## Si es true, la zona queda desactivada permanentemente tras usarse una vez
@export var reactivate_delay: float = 0.6 ## Evita que el jugador reactive la zona apenas llega al destino (útil si el destino queda cerca o solapado)
@export var fade_duration: float = 0.3 ## Duración del fundido a negro. 0 = sin fundido

var _consumed: bool = false


func _validate_property(property: Dictionary) -> void:
	if property.name == "local_target" and warp_mode != WarpMode.LOCAL:
		property.usage &= ~PROPERTY_USAGE_EDITOR
	elif property.name in ["target_scene", "target_spawn_id"] and warp_mode != WarpMode.EXTERNAL_SCENE:
		property.usage &= ~PROPERTY_USAGE_EDITOR


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	collision_mask = 2 # Detecta solo al jugador (Capa 2), igual que CameraZone3D
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if one_shot and _consumed:
		return
	_start_warp(body)


func _start_warp(player: Node3D) -> void:
	monitoring = false # evita retriggers mientras se resuelve el warp

	if warp_mode == WarpMode.EXTERNAL_SCENE:
		# La escena (y este nodo) se destruyen al cambiar de escena;
		# no hace falta reactivar el área ni trackear 'consumed'.
		_do_external_warp()
		return

	_consumed = true
	await _do_local_warp(player)

	if not one_shot:
		await get_tree().create_timer(reactivate_delay).timeout
		if is_instance_valid(self):
			monitoring = true
			_consumed = false


func _do_local_warp(player: Node3D) -> void:
	if not is_instance_valid(local_target):
		push_warning("WarpZone3D (%s): no se asignó 'local_target'." % name)
		monitoring = true
		return

	await WarpManager.fade_out(fade_duration)

	player.global_transform = local_target.global_transform
	if player is CharacterBody3D:
		player.velocity = Vector3.ZERO

	await WarpManager.fade_in(fade_duration)


func _do_external_warp() -> void:
	if target_scene == null:
		push_warning("WarpZone3D (%s): no se asignó 'target_scene'." % name)
		monitoring = true
		return

	WarpManager.warp_to_scene(target_scene, target_spawn_id, fade_duration)

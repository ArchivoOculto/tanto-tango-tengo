class_name EnemyPatrolZone
extends Area3D

var is_player_inside: bool = false
var player_ref: Node3D = null


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

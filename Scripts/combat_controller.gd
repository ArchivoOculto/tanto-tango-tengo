extends Node
class_name CombatController

signal attack_started

@export_group("Configuración de Ataque")
@export var attack_delay: float = 0.15
@export var attack_duration: float = 0.3

var hitbox: WeaponHitbox
var _attacking: bool = false


func _ready() -> void:
	var parent_player = get_parent()
	if parent_player:
		# La hitbox se mantiene en la guitarra de combate (righthand_grip)
		hitbox = parent_player.get_node_or_null("Visuals/Armature/Skeleton3D/righthand_grip/Guitar/GuitarHitbox")


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("attack") and not _attacking:
		start_attack()


func start_attack() -> void:
	_attacking = true
	attack_started.emit()

	get_tree().create_timer(attack_delay).timeout.connect(func():
		if _attacking and is_instance_valid(hitbox):
			hitbox.activate_hitbox(attack_duration)
	)


func on_attack_finished() -> void:
	_attacking = false
	if is_instance_valid(hitbox):
		hitbox.deactivate_hitbox()


func interrupt_actions() -> void:
	_attacking = false
	if is_instance_valid(hitbox):
		hitbox.deactivate_hitbox()


func is_attacking() -> bool: return _attacking

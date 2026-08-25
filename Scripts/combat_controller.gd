extends Node
class_name CombatController

signal attack_started
signal block_started
signal block_stopped
signal taunt_started
signal taunt_stopped

@export_group("Configuración de Ataque")
@export var attack_delay: float = 0.15
@export var attack_duration: float = 0.3

var hitbox: WeaponHitbox
var _attacking: bool = false
var _blocking: bool = false
var _taunting: bool = false


func _ready() -> void:
	var parent_player = get_parent()
	if parent_player:
		# La hitbox se mantiene en la guitarra de combate (righthand_grip)
		hitbox = parent_player.get_node_or_null("Visuals/Armature/Skeleton3D/righthand_grip/Guitar/GuitarHitbox")


func _process(_delta: float) -> void:
	# 1. ATAQUE
	if Input.is_action_just_pressed("attack") and not _is_busy_except_block():
		start_attack()
		return

	# 2. BLOQUEO
	if Input.is_action_pressed("block") and not _attacking and not _taunting:
		if not _blocking:
			start_block()
	elif _blocking and not Input.is_action_pressed("block"):
		stop_block()

	# 3. TAUNT / TOCAR GUITARRA
	if Input.is_action_pressed("taunt") and not _attacking and not _blocking:
		if not _taunting:
			start_taunt()
	elif _taunting and not Input.is_action_pressed("taunt"):
		stop_taunt()


func start_attack() -> void:
	stop_taunt()
	_blocking = false
	_attacking = true
	attack_started.emit()
	
	get_tree().create_timer(attack_delay).timeout.connect(func():
		if _attacking and is_instance_valid(hitbox):
			hitbox.activate_hitbox(attack_duration)
	)


func start_block() -> void:
	stop_taunt()
	_blocking = true
	block_started.emit()


func stop_block() -> void:
	if _blocking:
		_blocking = false
		block_stopped.emit()


func start_taunt() -> void:
	_blocking = false
	_taunting = true
	taunt_started.emit()


func stop_stop() -> void: # Alias opcional por seguridad de firma
	stop_taunt()


func stop_taunt() -> void:
	if _taunting:
		_taunting = false
		taunt_stopped.emit()


func on_attack_finished() -> void:
	_attacking = false
	if is_instance_valid(hitbox):
		hitbox.deactivate_hitbox()


func interrupt_actions() -> void:
	_attacking = false
	_blocking = false
	stop_taunt()
	if is_instance_valid(hitbox):
		hitbox.deactivate_hitbox()


func _is_busy_except_block() -> bool:
	return _attacking or _taunting

func is_attacking() -> bool: return _attacking
func is_blocking() -> bool: return _blocking
func is_taunting() -> bool: return _taunting
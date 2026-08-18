extends Node
class_name PlayerAnimationController

## Decide qué animación tocar según el estado del Player y controla
## la ventana de activación de la hitbox del arma mediante código.

const ANIM_IDLE: StringName = &"player_idle"
const ANIM_WALK: StringName = &"player_walk"
const ANIM_JUMP: StringName = &"player_jump"
const ANIM_ATTACK: StringName = &"player_attack"

@export var walk_speed_threshold: float = 0.25

## Tiempos de la ventana de golpe (Ajustar según la animación de Mixamo)
@export var attack_delay: float = 0.15  ## Tiempo antes de activar la hitbox (inicio del golpe)
@export var attack_duration: float = 0.3 ## Tiempo que permanece activa la hitbox

@onready var player: CharacterBody3D = get_parent()
@onready var anim_player: AnimationPlayer = player.get_node("Visuals/AnimationPlayer")

## Referencia a la hitbox dentro de la jerarquía de la guitarra
@onready var hitbox: WeaponHitbox = player.get_node_or_null("Visuals/Armature/Skeleton3D/Weapon/Guitar/GuitarHitbox")

var _attacking: bool = false


func _ready() -> void:
	anim_player.animation_finished.connect(_on_animation_finished)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("attack") and not _attacking:
		_start_attack()
	elif not _attacking:
		_update_locomotion_animation()


func _start_attack() -> void:
	_attacking = true
	anim_player.play(ANIM_ATTACK, -1, 2)
	
	# Espera el tiempo de retraso para activar la hitbox en el momento justo
	get_tree().create_timer(attack_delay).timeout.connect(func():
		if _attacking and is_instance_valid(hitbox):
			hitbox.activate_hitbox(attack_duration)
	)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_ATTACK:
		_attacking = false
		if is_instance_valid(hitbox):
			hitbox.deactivate_hitbox()


func _update_locomotion_animation() -> void:
	if not player.is_on_floor():
		_play_if_not_playing(ANIM_JUMP)
		return

	var horizontal_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if horizontal_speed > walk_speed_threshold:
		_play_if_not_playing(ANIM_WALK)
	else:
		_play_if_not_playing(ANIM_IDLE)


func _play_if_not_playing(anim_name: StringName) -> void:
	if anim_player.current_animation != anim_name:
		anim_player.play(anim_name)


func is_attacking() -> bool:
	return _attacking
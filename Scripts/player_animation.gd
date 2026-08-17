extends Node
class_name PlayerAnimationController

## Decide que animacion tocar segun el estado del Player. Vive como hijo
## de Player y lee su velocity/is_on_floor() — no toca fisica ni input de
## movimiento, solo mira y reacciona.
##
## Los nombres de animacion (player_idle, player_walk, etc) son
## especificos de ESTE modelo: si cambias de modelo, este es el unico
## archivo que hay que retocar, player.gd queda intacto.

const ANIM_IDLE: StringName = &"player_idle"
const ANIM_WALK: StringName = &"player_walk"
const ANIM_JUMP: StringName = &"player_jump"
const ANIM_ATTACK: StringName = &"player_attack"

@export var walk_speed_threshold: float = 0.25  ## por debajo de esto, se considera "quieto"

@onready var player: CharacterBody3D = get_parent()
@onready var anim_player: AnimationPlayer = player.get_node("Visuals/AnimationPlayer")

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
	anim_player.play(ANIM_ATTACK, -1, 10.0)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_ATTACK:
		_attacking = false


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


## Publico para que el futuro sistema de combate (o player.gd, si hace
## falta) sepa si hay que bloquear otras acciones mientras se ataca.
func is_attacking() -> bool:
	return _attacking
extends Node
class_name PlayerAnimationController

const ANIM_IDLE: StringName = &"player_idle"
const ANIM_WALK: StringName = &"player_walk"
const ANIM_JUMP: StringName = &"player_jump"
const ANIM_ATTACK: StringName = &"player_attack"
const ANIM_BLOCK: StringName = &"player_block"
const ANIM_GUITAR: StringName = &"player_guitar"

@export var walk_speed_threshold: float = 0.25

var anim_player: AnimationPlayer
var combat_controller: CombatController
@onready var player: CharacterBody3D = get_parent()

# Referencias a los nodos visuales de las dos guitarras
var normal_guitar: Node3D
var playing_guitar: Node3D


func _ready() -> void:
	if player:
		anim_player = player.get_node_or_null("Visuals/AnimationPlayer")
		combat_controller = player.get_node_or_null("CombatController")
		
		# Nodos de las guitarras dentro del Skeleton3D
		normal_guitar = player.get_node_or_null("Visuals/Armature/Skeleton3D/righthand_grip")
		playing_guitar = player.get_node_or_null("Visuals/Armature/Skeleton3D/Guitar_playing_grip")

	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)

	if combat_controller:
		combat_controller.attack_started.connect(func(): 
			_set_guitar_mode_playing(false)
			if anim_player: anim_player.play(ANIM_ATTACK, -1, 2)
		)
		combat_controller.block_started.connect(func(): 
			_set_guitar_mode_playing(false)
			_play_if_not_playing(ANIM_BLOCK)
		)
		combat_controller.taunt_started.connect(func(): 
			_set_guitar_mode_playing(true)
			_play_if_not_playing(ANIM_GUITAR)
		)
		combat_controller.taunt_stopped.connect(func(): 
			_set_guitar_mode_playing(false)
		)


func update_locomotion(is_on_floor: bool, horizontal_speed: float) -> void:
	if not anim_player:
		return

	var is_attacking: bool = combat_controller and combat_controller.is_attacking()
	var is_taunting: bool = combat_controller and combat_controller.is_taunting()

	if is_attacking or is_taunting:
		return

	if not is_on_floor:
		_play_if_not_playing(ANIM_JUMP)
		return

	var is_blocking: bool = combat_controller and combat_controller.is_blocking()
	if is_blocking:
		_play_if_not_playing(ANIM_BLOCK)
		return

	if horizontal_speed > walk_speed_threshold:
		_play_if_not_playing(ANIM_WALK)
	else:
		_play_if_not_playing(ANIM_IDLE)


func play_jump() -> void:
	_set_guitar_mode_playing(false)
	if anim_player:
		anim_player.seek(0.0, true)
		anim_player.play(ANIM_JUMP)


func _set_guitar_mode_playing(is_playing: bool) -> void:
	if normal_guitar:
		normal_guitar.visible = not is_playing
	if playing_guitar:
		playing_guitar.visible = is_playing


func _play_if_not_playing(anim_name: StringName) -> void:
	if anim_player and anim_player.current_animation != anim_name:
		anim_player.play(anim_name)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_ATTACK and combat_controller:
		combat_controller.on_attack_finished()
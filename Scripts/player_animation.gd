extends Node
class_name PlayerAnimationController

const ANIM_IDLE: StringName = &"player_idle"
const ANIM_WALK: StringName = &"player_walk"
const ANIM_JUMP: StringName = &"player_jump"
const ANIM_ATTACK: StringName = &"player_attack"
## Pose que se mantiene durante todo el modo fusil (ver RifleController).
const ANIM_RIFLE: StringName = &"player_guitar"

@export var walk_speed_threshold: float = 0.25
@export_group("Modo fusil")
@export var rifle_pose_blend: float = 0.25 ## Segundos de mezcla al entrar/salir de la pose del fusil
@export var rifle_shows_guitar_prop: bool = true ## Muestra la guitarra "tocando" (Guitar_playing) mientras dura la pose

var anim_player: AnimationPlayer
var combat_controller: CombatController
@onready var player: CharacterBody3D = get_parent()

# Referencias a los nodos visuales de las dos guitarras
var normal_guitar: Node3D
var playing_guitar: Node3D

var _rifle_pose_active: bool = false


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
			if anim_player: anim_player.play(ANIM_ATTACK, -1, 2)
		)


func update_locomotion(is_on_floor: bool, horizontal_speed: float) -> void:
	if not anim_player:
		return

	var is_attacking: bool = combat_controller and combat_controller.is_attacking()
	if is_attacking or _rifle_pose_active:
		return

	if not is_on_floor:
		_play_if_not_playing(ANIM_JUMP)
		return

	if horizontal_speed > walk_speed_threshold:
		_play_if_not_playing(ANIM_WALK)
	else:
		_play_if_not_playing(ANIM_IDLE)


func play_jump() -> void:
	if anim_player:
		anim_player.seek(0.0, true)
		anim_player.play(ANIM_JUMP)


## Empieza la pose del fusil y la mantiene hasta exit_rifle_pose().
func enter_rifle_pose() -> void:
	_rifle_pose_active = true
	_set_rifle_props(true)
	_play_if_not_playing(ANIM_RIFLE, rifle_pose_blend)


## Termina la pose del fusil y vuelve a la guitarra de combate con un idle.
func exit_rifle_pose() -> void:
	_rifle_pose_active = false
	_set_rifle_props(false)
	_play_if_not_playing(ANIM_IDLE, rifle_pose_blend)


func is_rifle_pose_active() -> bool:
	return _rifle_pose_active


func _set_rifle_props(rifle_active: bool) -> void:
	if normal_guitar:
		normal_guitar.visible = not rifle_active
	if playing_guitar:
		playing_guitar.visible = rifle_active and rifle_shows_guitar_prop


func _play_if_not_playing(anim_name: StringName, blend: float = -1.0) -> void:
	if anim_player and anim_player.current_animation != anim_name:
		anim_player.play(anim_name, blend)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_ATTACK and combat_controller:
		combat_controller.on_attack_finished()

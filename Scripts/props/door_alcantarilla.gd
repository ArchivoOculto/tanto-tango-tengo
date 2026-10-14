extends Node3D
class_name DoorAlcantarilla

signal opened
signal closed

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var tapa_alcantarilla: Node3D = $TapaAlcantarilla

var is_open: bool = false


func _ready() -> void:
	reset_to_closed()


func open() -> void:
	if is_open:
		return
	is_open = true
	
	if tapa_alcantarilla:
		tapa_alcantarilla.show()
		
	if animation_player:
		if animation_player.has_animation("open"):
			animation_player.play("open")
			await animation_player.animation_finished
		else:
			push_warning("DoorAlcantarilla: No se encontró la animación 'open'.")
			
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	
	if animation_player:
		if animation_player.has_animation("RESET"):
			animation_player.play("RESET")
			await animation_player.animation_finished
		elif animation_player.has_animation("open"):
			animation_player.play_backwards("open")
			await animation_player.animation_finished
			
	reset_to_closed()
	closed.emit()


func reset_to_closed() -> void:
	is_open = false
	if animation_player:
		if animation_player.has_animation("RESET"):
			animation_player.play("RESET")
			animation_player.advance(0)
		else:
			animation_player.stop()
			
	if tapa_alcantarilla:
		tapa_alcantarilla.show()
		tapa_alcantarilla.position = Vector3.ZERO
		tapa_alcantarilla.rotation = Vector3.ZERO
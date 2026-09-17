class_name PuzzleManager
extends Node

signal puzzle_completed

@export_group("Configuración del Puzzle")
## Lista de faroles que componen el acertijo (en orden)
@export var farolitos: Array[Farolito] = []

## Clave de combinación: true = Encendido (ON), false = Apagado / Titilando (OFF / FLICKERING)
@export var target_password: Array[bool] = []

@export_group("Transición de Escena")
## Duración en segundos del fundido a negro
@export var fade_duration: float = 1.0

var is_solved: bool = false


func _ready() -> void:
	for farol in farolitos:
		if farol:
			farol.toggled.connect(_on_farolito_toggled)

	_check_puzzle.call_deferred()


func _on_farolito_toggled(_is_on: bool) -> void:
	_check_puzzle()


func _check_puzzle() -> void:
	if farolitos.is_empty() or farolitos.size() != target_password.size():
		push_warning("PuzzleManager: Las listas 'farolitos' y 'target_password' deben tener la misma cantidad de elementos.")
		return

	var correctly_matched: bool = true

	for i in range(farolitos.size()):
		var farol: Farolito = farolitos[i]
		var expected_state: bool = target_password[i]

		if not farol or farol.is_on != expected_state:
			correctly_matched = false
			break

	if correctly_matched:
		if not is_solved:
			is_solved = true
			print("Puzzle Completado")
			puzzle_completed.emit()
			_fade_out_and_reload()
	else:
		if is_solved:
			is_solved = false
			print("respuesta desarmada")


func _fade_out_and_reload() -> void:
	# Creamos una capa superior y un lienzo negro dinámico
	var canvas := CanvasLayer.new()
	canvas.layer = 100

	var color_rect := ColorRect.new()
	color_rect.color = Color(0, 0, 0, 0)
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	canvas.add_child(color_rect)
	add_child(canvas)

	# Transición de alfa (0.0 a 1.0)
	var tween := create_tween()
	tween.tween_property(color_rect, "color:a", 1.0, fade_duration)
	await tween.finished

	# Reinicia la escena actual
	get_tree().reload_current_scene()
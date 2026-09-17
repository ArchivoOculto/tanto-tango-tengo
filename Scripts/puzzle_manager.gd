class_name PuzzleManager
extends Node

signal puzzle_completed

@export_group("Configuración del Puzzle")
## Lista de faroles que componen el acertijo (en orden)
@export var farolitos: Array[Farolito] = []

## Clave de combinación: true = Encendido (ON), false = Apagado / Titilando (OFF / FLICKERING)
@export var target_password: Array[bool] = []

@export_group("Pistas / UI")
## Asignar desde el Inspector el nodo Sprite2D que contiene a RedCross0, RedCross1, etc.
@export var red_crosses_parent: Node

@export_group("Transición de Escena")
## Duración en segundos del fundido a negro
@export var fade_duration: float = 1.0

var is_solved: bool = false


func _ready() -> void:
	_generate_random_password()
	_update_puzzle_hint()

	for farol in farolitos:
		if farol:
			farol.toggled.connect(_on_farolito_toggled)

	_check_puzzle.call_deferred()


func _generate_random_password() -> void:
	var total: int = farolitos.size()
	if total < 3:
		push_warning("PuzzleManager: Se necesitan al menos 3 faroles para cumplir las condiciones de la contraseña.")
		return

	target_password.clear()
	target_password.resize(total)

	# El último farol nunca debe ir apagado (siempre true)
	target_password[total - 1] = true

	# Asignación aleatoria para las posiciones de 0 a total - 2
	var off_count: int = 0
	for i in range(total - 1):
		var is_on: bool = randf() > 0.5
		target_password[i] = is_on
		if not is_on:
			off_count += 1

	# Garantizar como mínimo 2 faroles apagados (false)
	while off_count < 2:
		var rand_idx: int = randi() % (total - 1)
		if target_password[rand_idx]:
			target_password[rand_idx] = false
			off_count += 1


func _update_puzzle_hint() -> void:
	if not red_crosses_parent:
		return

	for i in range(target_password.size()):
		var cross_node: Control = red_crosses_parent.get_node_or_null("RedCross" + str(i)) as Control
		if cross_node:
			# Si el farol está apagado (false en la contraseña), la cruz se hace visible
			cross_node.visible = not target_password[i]


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
	var canvas := CanvasLayer.new()
	canvas.layer = 100

	var color_rect := ColorRect.new()
	color_rect.color = Color(0, 0, 0, 0)
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	canvas.add_child(color_rect)
	add_child(canvas)

	var tween := create_tween()
	tween.tween_property(color_rect, "color:a", 1.0, fade_duration)
	await tween.finished

	get_tree().reload_current_scene()
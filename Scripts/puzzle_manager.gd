class_name PuzzleManager
extends Node

signal puzzle_completed
signal puzzle_failed

@export_group("Configuración del Puzzle")
@export var farolitos: Array[Farolito] = []
@export var target_password: Array[bool] = []

@export_group("Pistas / UI")
@export var red_crosses_parent: Node

@export_group("Elementos Interactivos")
## Arrastrar aquí el nodo AlcantarillaPivot (que ahora tiene el script DoorAlcantarilla)
@export var alcantarilla: DoorAlcantarilla

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
		push_warning("PuzzleManager: Se necesitan al menos 3 faroles.")
		return

	target_password.clear()
	target_password.resize(total)
	target_password[total - 1] = true

	var off_count: int = 0
	for i in range(total - 1):
		var is_on: bool = randf() > 0.5
		target_password[i] = is_on
		if not is_on:
			off_count += 1

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
			cross_node.visible = not target_password[i]

func _on_farolito_toggled(_is_on: bool) -> void:
	_check_puzzle()

func _check_puzzle() -> void:
	if farolitos.is_empty() or farolitos.size() != target_password.size():
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
			if alcantarilla:
				alcantarilla.abrir()
	else:
		if is_solved:
			is_solved = false
			print("Respuesta desarmada")
			puzzle_failed.emit()
			if alcantarilla:
				alcantarilla.cerrar()
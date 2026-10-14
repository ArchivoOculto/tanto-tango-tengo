extends Node
class_name PuzzleManager

@export_group("Configuración del Puzzle")
@export var farolitos: Array[Farolito] = []

## Si es true, genera una contraseña aleatoria fija al iniciar la sesión
@export var auto_generate_password: bool = true

## Estado objetivo para cada farolito (true = ON, false = OFF / FLICKERING)
@export var target_password: Array[bool] = [false, true, true, false, true, true, true]

@export_group("Referencias")
@export var red_crosses_parent: Node
@export var alcantarilla: DoorAlcantarilla
@export var cam_zone_alcantarilla: CameraZone3D

@export_group("Cámara y Tiempos")
@export var display_duration: float = 3.0
@export var camera_delay: float = 0.4

var is_solved: bool = false
var _is_camera_focused: bool = false


func _ready() -> void:
	var total_faroles: int = farolitos.size() if farolitos.size() > 0 else 7

	# 1. Generar la contraseña UNA SOLA VEZ para toda la sesión
	if auto_generate_password:
		target_password = generate_valid_password(total_faroles)
	else:
		_validate_and_fix_password()

	# 2. Dibujar la pista fija (cruces rojas) UNA SOLA VEZ al inicio
	_setup_initial_ui_hint()

	# 3. Conectar eventos de los faroles (sin tocar la UI durante el juego)
	for i in range(farolitos.size()):
		var farol: Farolito = farolitos[i]
		if farol:
			farol.toggled.connect(func(_is_on: bool): _check_puzzle())


## Genera una contraseña fija respetando estrictamente las dos leyes:
## Ley A: Mínimo 2 faroles apagados (false)
## Ley B: Farol 07 (último índice) SIEMPRE encendido (true)
func generate_valid_password(size: int = 7) -> Array[bool]:
	var pw: Array[bool] = []
	pw.resize(size)

	# Ley B: El último farol (índice size - 1) SIEMPRE es true (ON)
	pw[size - 1] = true

	# Asignación aleatoria para los primeros (0 a size - 2)
	for i in range(size - 1):
		pw[i] = randf() > 0.5

	# Ley A: Garantizar al menos 2 faroles false (OFF) entre los primeros
	var off_count: int = 0
	for i in range(size - 1):
		if not pw[i]:
			off_count += 1

	while off_count < 2:
		var rand_idx: int = randi() % (size - 1)
		if pw[rand_idx]:
			pw[rand_idx] = false
			off_count += 1

	return pw


func _validate_and_fix_password() -> void:
	var size: int = target_password.size()
	if size == 0:
		return

	# Ley B: Forzar último en true
	target_password[size - 1] = true

	# Ley A: Forzar mínimo 2 en false
	var off_count: int = 0
	for i in range(size - 1):
		if not target_password[i]:
			off_count += 1

	while off_count < 2:
		var rand_idx: int = randi() % (size - 1)
		if target_password[rand_idx]:
			target_password[rand_idx] = false
			off_count += 1


## Muestra las cruces rojas de forma ESTÁTICA al inicio como pista fija
## (Muestra la cruz en las posiciones donde la contraseña exige que el farol esté OFF)
func _setup_initial_ui_hint() -> void:
	if not red_crosses_parent:
		return

	for i in range(target_password.size()):
		var cross_node: Node = red_crosses_parent.get_node_or_null("RedCross" + str(i))
		if cross_node:
			cross_node.visible = not target_password[i]


func _check_puzzle() -> void:
	var currently_solved: bool = _is_password_correct()
	
	if currently_solved and not is_solved:
		is_solved = true
		_on_puzzle_solved()
	elif not currently_solved and is_solved:
		is_solved = false
		_on_puzzle_unsolved()


func _is_password_correct() -> bool:
	if farolitos.size() != target_password.size():
		return false

	for i in range(farolitos.size()):
		var farol: Farolito = farolitos[i]
		if not farol:
			return false
		if farol.is_on != target_password[i]:
			return false

	return true


func _on_puzzle_solved() -> void:
	if cam_zone_alcantarilla:
		_is_camera_focused = true
		CameraDirector.force_zone(cam_zone_alcantarilla)

	if camera_delay > 0.0:
		await get_tree().create_timer(camera_delay).timeout

	if not is_solved:
		_restore_camera()
		return

	if alcantarilla:
		if alcantarilla.has_method("open"):
			alcantarilla.open()

	if cam_zone_alcantarilla and _is_camera_focused:
		await get_tree().create_timer(display_duration).timeout
		_restore_camera()


func _on_puzzle_unsolved() -> void:
	if alcantarilla:
		if alcantarilla.has_method("close"):
			alcantarilla.close()

	_restore_camera()


func _restore_camera() -> void:
	if cam_zone_alcantarilla and _is_camera_focused:
		_is_camera_focused = false
		CameraDirector.release_zone(cam_zone_alcantarilla)
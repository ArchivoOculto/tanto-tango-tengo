extends Area3D
class_name WeaponHitbox

@export var damage: float = 25.0
@export var knockback_strength: float = 6.0
@export var knockback_upward: float = 2.5
## Tiempo mínimo (ms) entre dos golpes al MISMO objetivo. Red de seguridad contra dobles impactos
## (ej: farolas) cuando la hitbox se reactiva o el objetivo sale y vuelve a entrar en un mismo golpe.
@export var rehit_lockout_msec: int = 400

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Registro para no golpear más de una vez al mismo objetivo por ataque
var _hit_targets: Array[Node] = []
var _last_hit_msec: Dictionary = {} # objetivo -> Time.get_ticks_msec() del último golpe
var _attack_serial: int = 0 # identifica el golpe vigente: un temporizador viejo no puede cortar uno nuevo


func _ready() -> void:
	collision_shape.disabled = true
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func activate_hitbox(duration: float = 0.3) -> void:
	_attack_serial += 1
	var serial: int = _attack_serial
	# Si ya estaba activa es el MISMO golpe (reactivación tardía): no se olvida a quién ya golpeó
	if collision_shape.disabled:
		_hit_targets.clear() # Limpia la lista al iniciar cada nuevo ataque
	collision_shape.disabled = false
	get_tree().create_timer(duration).timeout.connect(func():
		if serial == _attack_serial:
			deactivate_hitbox()
	)


func deactivate_hitbox() -> void:
	_attack_serial += 1 # invalida los temporizadores pendientes del golpe anterior
	collision_shape.disabled = true
	_hit_targets.clear()


func _on_body_entered(body: Node3D) -> void:
	_process_hit(body)


func _on_area_entered(area: Area3D) -> void:
	_process_hit(area)


func _process_hit(target: Node3D) -> void:
	if target == owner or target.is_in_group("player"):
		return

	# Subir por el árbol de nodos hasta encontrar la raíz con métodos interactivos
	var interactive_target: Node = target
	while interactive_target and not interactive_target.has_method("take_hit") and not interactive_target.has_method("take_damage"):
		interactive_target = interactive_target.get_parent()

	if not interactive_target:
		return

	# Si ya fue golpeado en este mismo ataque, ignorar
	if _hit_targets.has(interactive_target):
		return

	# Red de seguridad: el mismo objetivo no recibe dos golpes seguidos casi simultáneos
	var now: int = Time.get_ticks_msec()
	if now - int(_last_hit_msec.get(interactive_target, -1000000)) < rehit_lockout_msec:
		return
	_last_hit_msec[interactive_target] = now

	# Registrar el objetivo como golpeado
	_hit_targets.append(interactive_target)

	# Impacto a objetos interactivos (farolas, props, etc.)
	if interactive_target.has_method("take_hit"):
		interactive_target.take_hit(damage)

	# Impacto a enemigos
	if interactive_target.has_method("take_damage"):
		var knockback_dir: Vector3 = (interactive_target.global_position - global_position)
		knockback_dir.y = 0.0
		knockback_dir = knockback_dir.normalized()

		var final_knockback: Vector3 = knockback_dir * knockback_strength + Vector3.UP * knockback_upward
		interactive_target.take_damage(damage, final_knockback)
		

extends Area3D
class_name WeaponHitbox

@export var damage: float = 25.0
@export var knockback_strength: float = 6.0  ## Fuerza horizontal del empujón
@export var knockback_upward: float = 2.0    ## Elevación leve al recibir el golpe

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	collision_shape.disabled = true
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func activate_hitbox(duration: float = 0.3) -> void:
	collision_shape.disabled = false
	get_tree().create_timer(duration).timeout.connect(deactivate_hitbox)


func deactivate_hitbox() -> void:
	collision_shape.disabled = true


func _on_body_entered(body: Node3D) -> void:
	if body == owner or body.is_in_group("player"):
		return

	if body.has_method("take_damage"):
		var knockback_dir: Vector3 = (body.global_position - global_position)
		knockback_dir.y = 0.0
		knockback_dir = knockback_dir.normalized()

		var final_knockback: Vector3 = knockback_dir * knockback_strength + Vector3.UP * knockback_upward
		body.take_damage(damage, final_knockback)


func _on_area_entered(area: Area3D) -> void:
	if area.owner == owner:
		return

	if area.has_method("take_damage"):
		var knockback_dir: Vector3 = (area.global_position - global_position)
		knockback_dir.y = 0.0
		knockback_dir = knockback_dir.normalized()

		var final_knockback: Vector3 = knockback_dir * knockback_strength + Vector3.UP * knockback_upward
		area.take_damage(damage, final_knockback)
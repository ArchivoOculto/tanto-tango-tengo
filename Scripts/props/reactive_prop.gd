extends RigidBody3D
class_name ReactiveProp

## RigidBody3D que reacciona a los golpes de la guitarra (WeaponHitbox) y a los disparos del
## fusil (RifleController). Ambos suben por el árbol buscando un nodo con take_damage() o
## take_hit(), así que alcanza con tener este método en la raíz del RigidBody3D.
##
## Cualquier RigidBody3D del nivel puede volverse "empujable" asignándole este script.

## Se emite en cada impacto. Útil para conectar sonido, partículas, etc.
signal hit(damage: float, knockback: Vector3)

## Cuánto del knockback que recibiría un enemigo se aplica como cambio de velocidad.
## 1.0 = igual que a un enemigo; menos = salen menos disparadas.
@export_range(0.0, 3.0, 0.05) var impulse_multiplier: float = 0.5
## Tope de velocidad resultante (m/s), para que nunca salgan volando fuera del nivel.
@export var max_launch_speed: float = 5.0
## Giro aleatorio que se les da al golpearlas (rad/s). 0 = sin giro.
@export var spin_strength: float = 10.0


func take_damage(amount: float, knockback: Vector3 = Vector3.ZERO) -> void:
	sleeping = false # un RigidBody dormido ignoraría el golpe

	var new_velocity: Vector3 = linear_velocity + knockback * impulse_multiplier
	linear_velocity = new_velocity.limit_length(max_launch_speed)

	if spin_strength > 0.0:
		var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		if axis.length() > 0.001:
			angular_velocity = axis.normalized() * spin_strength * randf_range(0.6, 1.0)

	hit.emit(amount, knockback)

extends RefCounted
class_name PlayerControlLock

## Congela y libera al jugador cuando se abre/cierra un menú (cuadros, objetos, inventario).
##
## Está en un solo lugar a propósito: copiar esta lógica en cada menú ya provocó un softlock (al
## cerrar, el menú no encontraba al jugador porque este había salido del Area3D). Quien congela
## debe guardar su propia referencia al jugador y llamar a release() SIEMPRE al cerrar.
##
## release() no pisa el bloqueo del final del juego: Level00Manager usa PROCESS_MODE_DISABLED,
## que set_physics_process(true) no puede revertir.

static func freeze(player: Node) -> void:
	if not is_instance_valid(player):
		return
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	if "anim_controller" in player and player.anim_controller:
		player.anim_controller.update_locomotion(player.is_on_floor(), 0.0)
	player.set_physics_process(false)
	if "combat_controller" in player and player.combat_controller:
		player.combat_controller.interrupt_actions()
		player.combat_controller.set_process(false)


static func release(player: Node) -> void:
	if not is_instance_valid(player):
		return
	player.set_physics_process(true)
	if "combat_controller" in player and player.combat_controller:
		player.combat_controller.set_process(true)

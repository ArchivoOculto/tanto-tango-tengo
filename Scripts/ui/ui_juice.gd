class_name UiJuice
extends RefCounted

## Animaciones breves de menú ("game juice"): todas son tweens que siguen corriendo con el juego en pausa y
## que se pisan entre sí de forma segura (cada efecto de un nodo corta el anterior del mismo tipo).
##
##   pop_in(control)            el control aparece creciendo un poco (con rebote) y con fundido: al abrir un menú.
##   pop_in_children(parent)    lo mismo para todos los hijos visibles de 'parent' (menos los excluidos: el fondo).
##   pop(control, amount)       "salta" de tamaño al seleccionarlo: arranca más grande (o más chico, si 'amount' es
##                              negativo) y vuelve a 1 con rebote.
##   hop(control)               un saltito vertical, para objetos que no están dentro de un contenedor.

const META_PREFIX: String = "_ui_juice_"


static func pop_in(control: Control, from_scale: float = 0.94, duration: float = 0.2) -> void:
	if not control.is_inside_tree():
		return
	# El alpha original se recuerda: un cartel a media transparencia no debe terminar opaco
	var alpha: float = _remember(control, &"alpha", control.modulate.a)
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * from_scale
	control.modulate.a = 0.0
	var tween: Tween = _new_tween(control, &"pop_in").set_parallel()
	tween.tween_property(control, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", alpha, duration * 0.6)


static func pop_in_children(parent: Node, exclude: Array = [], from_scale: float = 0.94, duration: float = 0.2) -> void:
	for child in parent.get_children():
		if child is Control and child.visible and not exclude.has(child.name):
			pop_in(child as Control, from_scale, duration)


static func pop(control: Control, amount: float = 0.07, pivot_ratio: Vector2 = Vector2(0.5, 0.5),
		duration: float = 0.18) -> void:
	if not control.is_inside_tree():
		return
	# Un control recién creado en un contenedor todavía no tiene tamaño: se usa el mínimo que va a ocupar
	var size: Vector2 = control.size if control.size != Vector2.ZERO else control.get_combined_minimum_size()
	control.pivot_offset = size * pivot_ratio
	control.scale = Vector2.ONE * (1.0 + amount)
	var tween: Tween = _new_tween(control, &"pop")
	tween.tween_property(control, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func hop(control: Control, height: float = 8.0, duration: float = 0.32) -> void:
	if not control.is_inside_tree():
		return
	# Si el salto anterior sigue en curso, la posición "de reposo" es la que se guardó entonces
	var base_key: StringName = &"hop_base"
	var base: Vector2 = control.position
	if _is_running(control, &"hop") and control.has_meta(META_PREFIX + String(base_key)):
		base = control.get_meta(META_PREFIX + String(base_key))
	control.set_meta(META_PREFIX + String(base_key), base)
	control.position = base
	var tween: Tween = _new_tween(control, &"hop")
	tween.tween_property(control, "position:y", base.y - height, duration * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "position:y", base.y, duration * 0.65) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


static func _new_tween(control: Control, key: StringName) -> Tween:
	var meta_key: String = META_PREFIX + "tween_" + String(key)
	if control.has_meta(meta_key):
		var old: Tween = control.get_meta(meta_key)
		if old and old.is_valid():
			old.kill()
	# TWEEN_PAUSE_PROCESS: tiene que animar también con el juego en pausa (menú de pausa, inventario desde pausa)
	var tween: Tween = control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	control.set_meta(meta_key, tween)
	return tween


static func _is_running(control: Control, key: StringName) -> bool:
	var meta_key: String = META_PREFIX + "tween_" + String(key)
	if not control.has_meta(meta_key):
		return false
	var tween: Tween = control.get_meta(meta_key)
	return tween != null and tween.is_valid() and tween.is_running()


static func _remember(control: Control, key: StringName, value: Variant) -> Variant:
	var meta_key: String = META_PREFIX + String(key)
	if not control.has_meta(meta_key):
		control.set_meta(meta_key, value)
	return control.get_meta(meta_key)

class_name DoorAlcantarilla
extends Node3D

signal animacion_terminada

@onready var tapa = $TapaAlcantarilla
@onready var spotlight = $SpotLight3D 

var tween_actual: Tween

func _ready() -> void:
	if spotlight:
		spotlight.visible = false

func abrir() -> void:
	if tween_actual and tween_actual.is_valid():
		tween_actual.kill()
		
	# Sincronizamos el Tween con el proceso de física de AnimatableBody3D
	tween_actual = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	
	# 1. Movimiento principal (desplazamiento suave y rotación)
	tween_actual.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween_actual.tween_property(tapa, "position", Vector3(0.35, 0.01, 0), 2.0)
	tween_actual.parallel().tween_property(tapa, "rotation", Vector3(0, deg_to_rad(45), 0), 2.0)
	
	# 2. Caída al final (usando Vector3 completo manteniendo el X/Z del paso anterior)
	tween_actual.tween_property(tapa, "position", Vector3(0.35, -0.05, 0), 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# 3. Encender luz y emitir señal
	tween_actual.tween_callback(func():
		if spotlight: 
			spotlight.visible = true
		animacion_terminada.emit()
	)

func cerrar() -> void:
	if tween_actual and tween_actual.is_valid():
		tween_actual.kill()
		
	tween_actual = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	
	if spotlight:
		spotlight.visible = false
		
	tween_actual.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# 1. Levantar la tapa antes de deslizar
	tween_actual.tween_property(tapa, "position", Vector3(0.35, 0.01, 0), 0.2)
	
	# 2. Deslizar y rotar de vuelta a cero
	tween_actual.tween_property(tapa, "position", Vector3.ZERO, 1.8)
	tween_actual.parallel().tween_property(tapa, "rotation", Vector3.ZERO, 1.8)
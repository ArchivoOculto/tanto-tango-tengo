extends Control

## Escena a la que se cambiará una vez termine el fade out.
@export var target_scene: PackedScene

## Tiempo (en segundos) que la escena se mantendrá visible antes de hacer el fade out.
@export var wait_time: float = 3.0

## Duración de las animaciones de entrada y salida (fade in / fade out).
@export var fade_duration: float = 1.0

func _ready() -> void:
	# Aseguramos que el nodo empiece completamente transparente
	modulate.a = 0.0
	
	# Iniciamos la secuencia de animación
	_start_sequence()

func _start_sequence() -> void:
	var tween = create_tween()
	
	# 1. Fade In: Cambia la opacidad de 0 a 1 en el tiempo de fade_duration
	tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	
	# 2. Espera el tiempo configurado en la variable exportada
	tween.tween_interval(wait_time)
	
	# 3. Fade Out: Cambia la opacidad de 1 a 0
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	
	# 4. Conectamos la señal para cambiar de escena cuando todo el tween termine
	tween.finished.connect(_on_fade_out_finished)

func _on_fade_out_finished() -> void:
	if target_scene:
		get_tree().change_scene_to_packed(target_scene)
	else:
		print_rich("[color=yellow]Advertencia:[/color] No se ha asignado ninguna escena en 'Target Scene'.")
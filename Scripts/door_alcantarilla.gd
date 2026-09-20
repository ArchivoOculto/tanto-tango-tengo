class_name DoorAlcantarilla
extends Node3D

@onready var tapa = $TapaAlcantarilla
var tween_actual: Tween

func abrir() -> void:
    _animar_tapa(Vector3(0.35, 0.01, 0), Vector3(0, deg_to_rad(45), 0))

func cerrar() -> void:
    # Vuelve a la posición y rotación original (0,0,0)
    _animar_tapa(Vector3.ZERO, Vector3.ZERO)

func _animar_tapa(pos_destino: Vector3, rot_destino: Vector3) -> void:
    # Si la tapa ya se estaba moviendo, cortamos esa animación para empezar la nueva
    if tween_actual and tween_actual.is_valid():
        tween_actual.kill()
        
    tween_actual = create_tween()
    tween_actual.set_trans(Tween.TRANS_SINE)
    tween_actual.set_ease(Tween.EASE_IN_OUT)
    
    tween_actual.tween_property(tapa, "position", pos_destino, 2.43)
    tween_actual.parallel().tween_property(tapa, "rotation", rot_destino, 1.0)
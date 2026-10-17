extends Node

## Autoload "GameSettings": ajustes del jugador que se guardan en disco (user://settings.cfg) y se
## aplican al abrir el juego, sin importar por qué escena se entre.
##
##  - Volumen por bus (Master, Music, SFX... ver AudioBuses), de 0.0 a 1.0 (lineal).
##  - Pantalla completa.
##
## Los sliders del menú de opciones solo llaman a set_volume() / set_fullscreen().

signal volume_changed(bus: StringName, linear: float)

const SETTINGS_PATH: String = "user://settings.cfg"
const MUTE_THRESHOLD: float = 0.001

var _volumes: Dictionary = {}
var _fullscreen: bool = false


func _ready() -> void:
	_load()
	for entry: Array in AudioBuses.OPTION_SLIDERS:
		_apply_volume(entry[0], get_volume(entry[0]))
	_apply_fullscreen(_fullscreen)


## Volumen del bus, de 0.0 a 1.0 (1.0 por defecto).
func get_volume(bus: StringName) -> float:
	return float(_volumes.get(bus, 1.0))


func set_volume(bus: StringName, linear: float) -> void:
	linear = clampf(linear, 0.0, 1.0)
	_volumes[bus] = linear
	_apply_volume(bus, linear)
	volume_changed.emit(bus, linear)
	_save()


func is_fullscreen() -> bool:
	return _fullscreen


func set_fullscreen(enabled: bool) -> void:
	_fullscreen = enabled
	_apply_fullscreen(enabled)
	_save()


func _apply_volume(bus_name: StringName, linear: float) -> void:
	var bus: int = AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, linear <= MUTE_THRESHOLD)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(linear, MUTE_THRESHOLD)))


func _apply_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for entry: Array in AudioBuses.OPTION_SLIDERS:
		_volumes[entry[0]] = float(config.get_value("audio", String(entry[0]), 1.0))
	_fullscreen = bool(config.get_value("video", "fullscreen", false))


func _save() -> void:
	var config := ConfigFile.new()
	for bus: StringName in _volumes:
		config.set_value("audio", String(bus), _volumes[bus])
	config.set_value("video", "fullscreen", _fullscreen)
	config.save(SETTINGS_PATH)

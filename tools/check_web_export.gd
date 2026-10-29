extends SceneTree

## Verifica el preset "Web" de export_presets.cfg: calcula qué archivos entrarían al .pck y avisa si algo de lo que entra
## necesita un archivo que quedó afuera (en la web sería un recurso faltante, por ejemplo un sonido mudo).
##
## El preset exporta solo las escenas de 'export_files' y todo lo que referencian. Lo que se carga por nombre en tiempo de
## ejecución (los eventos de audio de Resources/audio/events/) se agrega con 'include_filter', y Godot NO arrastra las
## dependencias de esos archivos: sus audios hay que listarlos también. Este script lo comprueba.
##
## También detecta el caso más traicionero: un script que usa una clase global (class_name) por su nombre, sin ninguna
## ruta que Godot pueda seguir. Si el script de esa clase no entra al .pck, el juego falla al arrancar con
## "Could not find type ...".
##
## Ojo con lo que Godot NO hace en este modo: los scripts de los autoloads y los archivos de include_filter se exportan
## solos, sin sus dependencias. Si un autoload hace preload("res://algo.tscn"), ese archivo tiene que estar en
## 'export_files' (que sí arrastra dependencias) o el autoload falla al arrancar.
##
## Uso (desde la carpeta del proyecto):  godot --headless --script res://tools/check_web_export.gd
## Termina con código 1 si falta algo.

const PRESET_NAME: String = "Web"

## Archivos que solo se cargan en tiempo de ejecución desde código de escritorio (menú principal, pausa y el manager del
## nivel completo), que existe en el .pck pero nunca se ejecuta en la escena web. No se consideran faltantes.
const RUNTIME_ONLY_DESKTOP: Array[String] = [
	"res://Scenes/ui/main_menu.tscn",
	"res://Scenes/ui/pause_menu.tscn",
	"res://Scenes/levels/terrain.tscn",
]

## Ajustes de project.godot que apuntan a archivos que no hay que declarar: la web no usa el icono de la ventana ni la escena
## principal de PC, y el logo de arranque (boot_splash/image) el exportador lo empaqueta solo.
const NOT_NEEDED_IN_WEB: Array[String] = ["application/config/icon", "application/run/main_scene", "application/boot_splash/image"]

var _exported: Dictionary = {} # ruta -> true
var _needed_by: Dictionary = {} # ruta faltante -> [quién la necesita]
var _class_paths: Dictionary = {} # nombre de clase global -> ruta de su script


func _initialize() -> void:
	var config := ConfigFile.new()
	if config.load("res://export_presets.cfg") != OK:
		push_error("No se pudo leer export_presets.cfg")
		quit(1)
		return
	var section := ""
	for s in config.get_sections():
		if not s.contains(".options") and config.get_value(s, "name", "") == PRESET_NAME:
			section = s
	if section == "":
		push_error("No hay un preset llamado '%s'" % PRESET_NAME)
		quit(1)
		return

	var include_filters := _split_filters(config.get_value(section, "include_filter", ""))
	var exclude_filters := _split_filters(config.get_value(section, "exclude_filter", ""))
	var roots: Array = Array(config.get_value(section, "export_files", PackedStringArray()))

	# 1) Las escenas/recursos de export_files, con TODO lo que referencian (esto sí sigue las dependencias)
	for root_path in roots:
		_add_with_dependencies(root_path)
	# 2) Los archivos que pide include_filter (SOLO ellos: sin sus dependencias)
	for path in _all_project_files("res://"):
		if _matches(path, include_filter_list_or_empty(include_filters)):
			_exported[path] = true
	# 3) Lo que excluye exclude_filter
	for path in _exported.keys():
		if _matches(path, exclude_filters):
			_exported.erase(path)

	# 4) ¿Algo de lo que entra necesita algo que no entra?
	for global_class in ProjectSettings.get_global_class_list():
		_class_paths[String(global_class["class"])] = String(global_class["path"])
	for referenced in _project_settings_references():
		if not _exported.has(referenced):
			_report_missing(referenced, "project.godot")
	for path in _exported.keys():
		for dependency in _dependencies_of(path):
			if not _exported.has(dependency) and FileAccess.file_exists(dependency):
				_report_missing(dependency, path)
		if path.get_extension() == "gd":
			for dependency in _classes_used_by(path):
				if not _exported.has(dependency):
					_report_missing(dependency, path)
			for dependency in _paths_written_in(path):
				if not _exported.has(dependency):
					_report_missing(dependency, path)

	print("Preset '%s': %d archivos entran al .pck." % [PRESET_NAME, _exported.size()])
	if _needed_by.is_empty():
		print("OK: no falta nada.")
		quit(0)
		return
	print("FALTAN %d archivos (se necesitan pero NO entran al .pck):" % _needed_by.size())
	var suggestion := PackedStringArray(roots.map(func(r): return '"%s"' % r))
	var text_files := PackedStringArray()
	for missing in _needed_by:
		print("  %s\n      lo necesita: %s" % [missing, ", ".join(_needed_by[missing].slice(0, 3))])
		if missing.get_extension() == "gd" or missing.get_extension() == "gdshader":
			text_files.append(missing.trim_prefix("res://"))
		else:
			suggestion.append('"%s"' % missing)
	print("\nEscenas y recursos (.tscn, .tres): súmalos a export_files, que arrastra sus dependencias:")
	print("export_files=PackedStringArray(%s)" % ", ".join(suggestion))
	if not text_files.is_empty():
		print("Scripts y shaders (no los arrastra export_files): súmalos a include_filter: %s" % ", ".join(text_files))
	quit(1)


func include_filter_list_or_empty(filters: PackedStringArray) -> PackedStringArray:
	return filters


func _report_missing(missing: String, needed_by: String) -> void:
	if RUNTIME_ONLY_DESKTOP.has(missing):
		return
	if not _needed_by.has(missing):
		_needed_by[missing] = []
	if not _needed_by[missing].has(needed_by):
		_needed_by[missing].append(needed_by)


## Archivos que el código de 'path' nombra con una ruta escrita ("res://..."): preload, load o una constante. Godot NO sigue
## estas rutas al exportar (get_dependencies de un script devuelve vacío), así que hay que comprobarlas a mano.
func _paths_written_in(path: String) -> Array[String]:
	var found: Array[String] = []
	var regex := RegEx.create_from_string('"(res://[^"\\n]+)"')
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		for result in regex.search_all(line):
			var target: String = result.get_string(1)
			if FileAccess.file_exists(target) and not found.has(target):
				found.append(target)
	return found


## Archivos que project.godot referencia (layout de buses de audio, escena principal web...), por ruta o por uid. Godot
## tampoco los sigue solo en este modo: sin el layout de buses, por ejemplo, el juego arranca sin los buses de audio.
func _project_settings_references() -> Array[String]:
	var found: Array[String] = []
	var config := ConfigFile.new()
	if config.load("res://project.godot") != OK:
		return found
	for section in config.get_sections():
		if section in ["input", "editor_plugins"]:
			continue
		for key in config.get_section_keys(section):
			var value: Variant = config.get_value(section, key)
			if typeof(value) != TYPE_STRING:
				continue
			var path: String = String(value).trim_prefix("*")
			if path.begins_with("uid://"):
				var id := ResourceUID.text_to_id(path)
				path = ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
			if not path.begins_with("res://") or not FileAccess.file_exists(path):
				continue
			if "%s/%s" % [section, key] in NOT_NEEDED_IN_WEB:
				continue
			if not found.has(path):
				found.append(path)
	return found


## Rutas de los scripts de las clases globales que el código de 'path' nombra.
func _classes_used_by(path: String) -> Array[String]:
	var used: Array[String] = []
	var source := FileAccess.get_file_as_string(path)
	for class_name_text in _class_paths:
		var class_path: String = _class_paths[class_name_text]
		if class_path == path or used.has(class_path):
			continue
		var regex := RegEx.create_from_string("\\b%s\\b" % class_name_text)
		if regex.search(source) != null:
			used.append(class_path)
	return used


func _add_with_dependencies(path: String) -> void:
	if _exported.has(path) or not FileAccess.file_exists(path):
		return
	_exported[path] = true
	for dependency in _dependencies_of(path):
		_add_with_dependencies(dependency)


func _dependencies_of(path: String) -> Array[String]:
	var result: Array[String] = []
	if not ResourceLoader.exists(path):
		return result
	for entry in ResourceLoader.get_dependencies(path):
		var parts := String(entry).split("::")
		var dependency: String = parts[2] if parts.size() >= 3 else String(entry)
		if dependency != "":
			result.append(dependency)
	return result


func _all_project_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	if FileAccess.file_exists(dir_path.path_join(".gdignore")):
		return files
	for f in DirAccess.get_files_at(dir_path):
		if not f.ends_with(".import") and not f.ends_with(".uid"):
			files.append(dir_path.path_join(f))
	for d in DirAccess.get_directories_at(dir_path):
		if not d.begins_with("."):
			files.append_array(_all_project_files(dir_path.path_join(d)))
	return files


func _split_filters(text: String) -> PackedStringArray:
	var filters := PackedStringArray()
	for part in text.split(",", false):
		filters.append(part.strip_edges())
	return filters


## Los filtros de Godot son patrones (con * y ?) sobre la ruta sin "res://".
func _matches(path: String, filters: PackedStringArray) -> bool:
	var relative := path.trim_prefix("res://")
	for pattern in filters:
		if relative.match(pattern):
			return true
	return false

class_name SaveGame
extends RefCounted
## Saving and loading: game progress in user://save.json, settings in
## user://settings.json (kept even when starting a new game).

const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"
const DEFAULT_SETTINGS := {
	"quality": "balanced",   # battery, balanced or sharp
	"music": 0.7,            # 0..1
	"effects": 0.9,          # 0..1
	"sensitivity": 1.0,      # camera look speed multiplier
	"show_fps": false,
}


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func save(state: Dictionary) -> void:
	_write(SAVE_PATH, state)


static func load_save() -> Dictionary:
	return _read(SAVE_PATH)


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


static func load_settings() -> Dictionary:
	var s := DEFAULT_SETTINGS.duplicate()
	s.merge(_read(SETTINGS_PATH), true)
	return s


static func save_settings(s: Dictionary) -> void:
	_write(SETTINGS_PATH, s)


static func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

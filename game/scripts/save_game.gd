class_name SaveGame
extends RefCounted
## Saving and loading. Every adventure is its own save slot, a file in
## user://saves/<slot>.json holding the whole game state plus a "meta" header
## (name, region, level, playtime, when it was saved) for the Load screen.
## Settings live in user://settings.json (shared by all slots).
##
## Writes are crash-safe: the new file is written beside the old one and
## swapped in, and the previous version is kept as <slot>.json.bak, which is
## read if the main file is ever damaged. A save from before slots existed
## (user://save.json) is copied into a slot once and the original is left
## untouched.

## Where slots live; tests point these at a scratch folder.
static var save_dir := "user://saves"
static var legacy_path := "user://save.json"
const LEGACY_SLOT := "adventure_1"
const SETTINGS_PATH := "user://settings.json"
const DEFAULT_SETTINGS := {
	"quality": "balanced",   # battery, balanced or sharp
	"music": 0.7,            # 0..1
	"effects": 0.9,          # 0..1
	"sensitivity": 1.0,      # camera look speed multiplier
	"show_fps": false,
	"master": 1.0,
	"ambience": 0.9,          # wind, birds, lava, tavern murmur
	"fullscreen": false,      # desktop only
	"window_size": "1600x900",
	"vsync": true,
	"brightness": 1.0,        # 0.7..1.3
	"shadows": "high",        # off, low, high
	"foliage": 1.0,           # grass density 0.25..1
	"view_distance": "far",   # near, normal, far
	"aa": "msaa",             # off, fxaa, msaa (desktop)
	"laptop_mode": "auto",    # auto, on, off: lighter graphics for weak PCs (desktop, on restart)
	"hud_full": true,
	"text_size": 1.0,         # interface scale 0.85..1.3
	"reduced_motion": false,
}


# ---------- Slots ----------

## All save slots, most recently saved first: [{id, name, region, level, playtime, saved_at}].
static func list_slots() -> Array:
	migrate_legacy()
	var out := []
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			var id := f.get_basename()
			var meta: Dictionary = load_save(id).get("meta", {})
			out.append({"id": id, "name": str(meta.get("name", id.capitalize())), "region": str(meta.get("region", "")),
				"level": int(meta.get("level", 1)), "playtime": float(meta.get("playtime", 0.0)), "saved_at": float(meta.get("saved_at", 0))})
	out.sort_custom(func(a, b): return a.saved_at > b.saved_at)
	return out


static func has_save() -> bool:
	return not list_slots().is_empty()


## The slot to Continue: the one saved most recently ("" if there is none).
static func latest_slot() -> String:
	var slots := list_slots()
	return slots[0].id if not slots.is_empty() else ""


## A fresh, empty slot for a new adventure. Never reuses an existing one.
static func new_slot(slot_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var base := "adventure_%d" % int(Time.get_unix_time_from_system())
	var id := base
	var n := 2
	while FileAccess.file_exists(_path(id)):
		id = "%s_%d" % [base, n]
		n += 1
	_write(_path(id), {"meta": {"name": slot_name, "saved_at": int(Time.get_unix_time_from_system())}})
	return id


## A name for the next new adventure ("Adventure 3").
static func next_name() -> String:
	var names := list_slots().map(func(s): return s.name)
	var n := names.size() + 1
	while "Adventure %d" % n in names:
		n += 1
	return "Adventure %d" % n


## Writes a slot. `state` is the game state; `meta` the Load-screen header.
static func save(slot: String, state: Dictionary, meta: Dictionary = {}) -> void:
	if slot == "":
		return
	DirAccess.make_dir_recursive_absolute(save_dir)
	var d := state.duplicate()
	var m: Dictionary = load_save(slot).get("meta", {}) if meta.is_empty() else {}
	m.merge(meta, true)
	m["saved_at"] = Time.get_unix_time_from_system()
	d["meta"] = m
	_write(_path(slot), d)


## Reads a slot (or, given "", the latest). Falls back to the backup copy.
static func load_save(slot := "") -> Dictionary:
	if slot == "":
		slot = latest_slot()
		if slot == "":
			return {}
	var d := _read(_path(slot))
	return d if not d.is_empty() else _read(_path(slot) + ".bak")


static func rename_slot(slot: String, slot_name: String) -> void:
	var d := load_save(slot)
	if d.is_empty() or slot_name.strip_edges() == "":
		return
	var m: Dictionary = d.get("meta", {})
	m["name"] = slot_name.strip_edges()
	d["meta"] = m
	_write(_path(slot), d)


## Permanently removes a slot (and its backup). The menu confirms first.
static func delete_slot(slot: String) -> void:
	for p in [_path(slot), _path(slot) + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Copies a pre-slots save (user://save.json) into its own slot, once. The
## old file is never changed or deleted.
static func migrate_legacy() -> void:
	if not FileAccess.file_exists(legacy_path) or FileAccess.file_exists(_path(LEGACY_SLOT)) \
			or FileAccess.file_exists(_path(LEGACY_SLOT) + ".bak"):
		return
	var old := _read(legacy_path)
	if old.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(save_dir)
	var m: Dictionary = old.get("meta", {})
	m.merge({"name": "Adventure 1", "level": int(old.get("progress", {}).get("level", 1)),
		"saved_at": int(FileAccess.get_modified_time(legacy_path))})
	old["meta"] = m
	_write(_path(LEGACY_SLOT), old)


static func _path(slot: String) -> String:
	return "%s/%s.json" % [save_dir, slot]


# ---------- Settings ----------

static func load_settings() -> Dictionary:
	var s := DEFAULT_SETTINGS.duplicate()
	s.merge(_read(SETTINGS_PATH), true)
	return s


static func save_settings(s: Dictionary) -> void:
	_write(SETTINGS_PATH, s)


# ---------- Files ----------

## Write beside, keep the previous version as .bak, then swap in: a crash or
## a phone killing the app mid-write never leaves only a half-written file.
static func _write(path: String, d: Dictionary) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("could not write " + path)
		return
	f.store_string(JSON.stringify(d))
	f.close()
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(abs_path + ".bak")
		DirAccess.rename_absolute(abs_path, abs_path + ".bak")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

class_name GameState
extends Node
## The explorer's progress outside of quests: coins, experience and level,
## Brickton reputation, inventory, weapons and armour, blacksmith upgrades and
## world flags (discovered places, opened chests, solved shrines, defeated
## bosses...). Applies the resulting stats to the player and is saved with the game.

signal changed
## Short messages for the HUD ("+50 coins", "Level up!").
signal notify(text: String, kind: String)

var items_cfg: Dictionary = {}
var shops: Dictionary = {}
var player: Player

var coins := 0
var xp := 0
var level := 1
var reputation := 0
var items := {}            # id -> count
var weapon := "iron_sword"
var armor := ""
var smith_level := 0
var flags := {}            # name -> true / value


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	items_cfg = d.items
	shops = d.shop


func item(id: String) -> Dictionary:
	return items_cfg.get(id, {"name": id, "kind": "material"})


func item_name(id: String) -> String:
	return item(id).get("name", id)


func count(id: String) -> int:
	return int(items.get(id, 0))


func add_item(id: String, n := 1, quiet := false) -> void:
	if n <= 0:
		return
	var it := item(id)
	if it.kind == "weapon" or it.kind == "armor":
		if count(id) > 0:
			return
		items[id] = 1
		if not quiet:
			notify.emit("New %s: %s" % ["weapon" if it.kind == "weapon" else "armour", it.name], "item")
		# Equip it straight away when it is better than what you have.
		if it.kind == "weapon" and float(it.get("damage", 1.0)) > float(item(weapon).get("damage", 1.0)):
			equip(id)
		elif it.kind == "armor" and (armor == "" or float(it.get("armor", 1.0)) <= float(item(armor).get("armor", 1.0))):
			equip(id)
	else:
		items[id] = count(id) + n
		if not quiet:
			notify.emit("+%d %s" % [n, it.name] if n > 1 else "+ " + it.name, "item")
	if id in ["magic_crystal", "warden_sigil"]:
		apply_stats()
	changed.emit()


func remove_item(id: String, n := 1) -> bool:
	if count(id) < n:
		return false
	items[id] = count(id) - n
	if items[id] <= 0:
		items.erase(id)
	changed.emit()
	return true


func add_coins(n: int, quiet := false) -> void:
	coins = maxi(0, coins + n)
	if n > 0 and not quiet:
		notify.emit("+%d coins" % n, "coins")
	changed.emit()


func xp_for_next() -> int:
	return 150 + 100 * (level - 1)


func add_xp(n: int) -> void:
	if n <= 0:
		return
	xp += n
	notify.emit("+%d XP" % n, "xp")
	while xp >= xp_for_next():
		xp -= xp_for_next()
		level += 1
		notify.emit("Level %d!  Health and sword damage increased." % level, "level")
		apply_stats()
		if player:
			player.health = player.max_health
			player.health_changed.emit(player.health, player.max_health)
	changed.emit()


func add_reputation(n: int) -> void:
	reputation += n
	notify.emit("+%d reputation in Brickton" % n, "rep")
	changed.emit()


func set_flag(name: String, value: Variant = true) -> void:
	flags[name] = value
	changed.emit()


func has_flag(name: String) -> bool:
	return flags.has(name) and flags[name] != false


func equip(id: String) -> void:
	var it := item(id)
	if count(id) <= 0 and id != "iron_sword":
		return
	if it.kind == "weapon":
		weapon = id
	elif it.kind == "armor":
		armor = id
	apply_stats()
	changed.emit()


## Price of an item at a shop (Hale's discount once you've helped him).
func price(id: String) -> int:
	var it := item(id)
	var p := int(it.get("price", int(it.get("value", 5)) * 3))
	if has_flag("merchant_discount"):
		p = int(round(p * 0.8))
	return p


func sword_damage_mult() -> float:
	var sigil := 1.08 if count("warden_sigil") > 0 else 1.0
	return float(item(weapon).get("damage", 1.0)) * (1.0 + 0.12 * smith_level) * (1.0 + 0.03 * (level - 1)) * sigil


## Pushes weapon, armour, level and charms onto the player.
func apply_stats() -> void:
	if player == null:
		return
	var w := item(weapon)
	var glow = w.get("glow", null)
	player.damage_mult = sword_damage_mult()
	if player.body:
		if glow is Array:
			player.body.set_blade_glow(Color(glow[0], glow[1], glow[2]))
		else:
			player.body.clear_blade_glow()
	var a := item(armor) if armor != "" else {}
	player.armor_mult = float(a.get("armor", 1.0))
	player.resist = {"frost": float(a.get("frost", 1.0)), "fire": float(a.get("fire", 1.0))}
	var base: float = player.combat.get("max_health", 100.0)
	var new_max := base + 10.0 * (level - 1) + (15.0 if count("magic_crystal") > 0 else 0.0)
	if not is_equal_approx(new_max, player.max_health):
		player.max_health = new_max
		player.health = minf(player.health, new_max)
		player.health_changed.emit(player.health, player.max_health)


## Drinks the strongest potion carried. Returns true if one was used.
func use_potion() -> bool:
	for id in ["potion", "elixir"]:
		if count(id) > 0:
			remove_item(id)
			if player:
				player.heal_left += float(item(id).get("heal", 45)) - float(player.combat.get("potion_heal", 45.0))
			notify.emit("Drank a " + item_name(id), "item")
			return true
	notify.emit("No healing potions left", "warn")
	return false


func save_state() -> Dictionary:
	return {"coins": coins, "xp": xp, "level": level, "reputation": reputation, "items": items,
		"weapon": weapon, "armor": armor, "smith_level": smith_level, "flags": flags}


func load_state(s: Dictionary) -> void:
	coins = int(s.get("coins", 0))
	xp = int(s.get("xp", 0))
	level = int(s.get("level", 1))
	reputation = int(s.get("reputation", 0))
	items = s.get("items", {}).duplicate()
	for k in items.keys():
		items[k] = int(items[k])
	weapon = s.get("weapon", "iron_sword")
	armor = s.get("armor", "")
	smith_level = int(s.get("smith_level", 0))
	flags = s.get("flags", {}).duplicate()
	if s.is_empty():
		items = {"potion": 3}
	apply_stats()
	changed.emit()

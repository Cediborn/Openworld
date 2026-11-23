class_name Story
extends Node3D
## Villagers, conversations and the Elder's quest ("The Island's Heart").
## Finds the nearest thing to interact with (a villager or a heart-stone),
## shows the prompt, runs dialogue, and moves the quest through its stages:
## intro -> hunt -> return -> forge -> done. State is saved by SaveGame.

## Emitted whenever quest progress changes (the world autosaves on it).
signal progress_changed

const STAGES := ["intro", "hunt", "return", "forge", "done"]

var data: WorldData
var player: Player
var hud: Hud
var touch := false
var npc_cfg: Dictionary
var quest_cfg: Dictionary
var villagers: Array[Villager] = []
var stones := {}             # id -> Node3D (removed once picked up)
var stage := "intro"
var found: Array = []        # ids of heart-stones picked up
var dialogue_lines: Array = []
var dialogue_index := -1
var dialogue_with: Villager
var focus = null             # Villager or stone id under the prompt
var _cull := 0.0


func setup(world_data: WorldData, p: Player, h: Hud, is_touch: bool) -> void:
	data = world_data
	player = p
	hud = h
	touch = is_touch
	npc_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/npcs.json"))
	quest_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/quest.json"))
	var i := 0
	for v: Dictionary in npc_cfg.villagers:
		var vil := Villager.new()
		add_child(vil)
		vil.setup(v, 77 + i)
		vil.player = player
		vil.height_at = func(x: float, z: float) -> float: return data.height(x, z)
		vil.global_position = Vector3(vil.home.x, data.height(vil.home.x, vil.home.z), vil.home.z)
		vil.rotation.y = PI if vil.home.z < -2.0 else 0.0   # face the street
		villagers.append(vil)
		i += 1
	hud.interact_pressed.connect(interact)
	hud.dialogue_advanced.connect(_advance)
	_refresh()


## Restores progress from a save.
func load_state(s: Dictionary) -> void:
	stage = s.get("stage", "intro")
	found = s.get("found", [])
	if stage == "done":
		player.set_sword_upgrade(quest_cfg.reward_damage_multiplier, _color(quest_cfg.reward_blade_color))
	_refresh()


func save_state() -> Dictionary:
	return {"stage": stage, "found": found}


func _refresh() -> void:
	# Heart-stones exist in the world only while being hunted and not yet found.
	for st: Dictionary in quest_cfg.stones:
		var want: bool = stage == "hunt" and not st.id in found
		if want and not stones.has(st.id):
			stones[st.id] = _make_stone(st)
		elif not want and stones.has(st.id):
			stones[st.id].queue_free()
			stones.erase(st.id)
	_update_tracker()


func _update_tracker() -> void:
	var t := ""
	match stage:
		"intro":
			t = "Talk to Elder Tobin in the village (west)"
		"hunt":
			t = quest_cfg.title + "\n"
			for st: Dictionary in quest_cfg.stones:
				t += ("✔ " if st.id in found else "○ ") + st.name + "\n"
		"return":
			t = quest_cfg.title + "\nReturn to Elder Tobin"
		"forge":
			t = quest_cfg.title + "\nVisit Bram the Blacksmith"
		"done":
			t = ""
	hud.set_quest(t)


func _make_stone(st: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var x: float = st.pos[0]
	var z: float = st.pos[1]
	root.global_position = Vector3(x, maxf(data.height(x, z), WorldData.LAVA_LEVEL + 0.3), z)
	var c := _color(st.color)
	var gem := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.35, 0.5, 0.35)
	gem.mesh = prism
	var gm := StandardMaterial3D.new()
	gm.albedo_color = c
	gm.emission_enabled = true
	gm.emission = c
	gm.emission_energy_multiplier = 3.0
	gm.metallic = 0.3
	gm.roughness = 0.15
	gem.material_override = gm
	gem.position.y = 1.0
	gem.name = "Gem"
	root.add_child(gem)
	var lower := MeshInstance3D.new()
	var p2 := PrismMesh.new()
	p2.size = Vector3(0.35, 0.3, 0.35)
	lower.mesh = p2
	lower.material_override = gm
	lower.rotation.z = PI
	lower.position.y = -0.4
	gem.add_child(lower)
	# A tall beam of light so you can find it from far away.
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.3
	cyl.height = 90.0
	beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(c.r, c.g, c.b, 0.22)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 45.0
	root.add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 2.0
	light.omni_range = 6.0
	light.position.y = 1.2
	root.add_child(light)
	root.set_meta("stone", st)
	return root


func _process(delta: float) -> void:
	if player == null:
		return
	for id in stones:
		var gem: Node3D = stones[id].get_node("Gem")
		gem.rotation.y += delta * 1.2
		gem.position.y = 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.002)
	_cull -= delta
	if _cull <= 0.0:
		_cull = 0.5
		var far: float = npc_cfg.active_distance
		for v in villagers:
			var on := v.global_position.distance_to(player.global_position) < far
			v.visible = on
			v.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if dialogue_index >= 0:
		return
	_find_focus()


func _find_focus() -> void:
	focus = null
	var label := ""
	if player.dead:
		hud.set_prompt("", touch)
		return
	var best: float = npc_cfg.talk_distance
	for v in villagers:
		var d := v.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			focus = v
			label = "Talk to " + v.display_name
	for id in stones:
		var d: float = stones[id].global_position.distance_to(player.global_position)
		if d < quest_cfg.pickup_distance:
			focus = id
			label = "Pick up " + stones[id].get_meta("stone").name
	hud.set_prompt(label, touch)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if dialogue_index >= 0:
			_advance()
		else:
			interact()


## Talks to the focused villager or picks up the focused heart-stone.
func interact() -> void:
	if focus == null or dialogue_index >= 0:
		return
	if focus is Villager:
		_start_dialogue(focus)
	elif focus is String and stones.has(focus):
		_pick_up(focus)


func _pick_up(id: String) -> void:
	var st: Dictionary = stones[id].get_meta("stone")
	player.body.play_once("PickUp_Table", 0.1, 1.2)
	found.append(id)
	hud.show_notice("%s found  (%d/3)" % [st.name, found.size()])
	if found.size() >= quest_cfg.stones.size():
		stage = "return"
		hud.show_notice("All three heart-stones found!\nReturn to Elder Tobin.")
	_refresh()
	progress_changed.emit()


func _start_dialogue(v: Villager) -> void:
	dialogue_with = v
	dialogue_lines = v.lines_for(stage)
	if dialogue_lines.is_empty():
		return
	dialogue_index = 0
	v.set_talking(true)
	player.in_conversation = true
	hud.set_prompt("", touch)
	hud.show_dialogue(v.display_name, dialogue_lines[0])


func _advance() -> void:
	if dialogue_index < 0:
		return
	dialogue_index += 1
	if dialogue_index < dialogue_lines.size():
		hud.show_dialogue(dialogue_with.display_name, dialogue_lines[dialogue_index])
		return
	dialogue_index = -1
	hud.hide_dialogue()
	dialogue_with.set_talking(false)
	player.in_conversation = false
	_after_dialogue(dialogue_with)


## Quest stage changes happen when a conversation ends.
func _after_dialogue(v: Villager) -> void:
	var role: String = v.cfg.get("role", "")
	var before := stage
	if role == "quest_giver" and stage == "intro":
		stage = "hunt"
		hud.show_notice("New quest: " + quest_cfg.title + "\nFind the three heart-stones.")
	elif role == "quest_giver" and stage == "return":
		stage = "forge"
	elif role == "smith" and stage == "forge":
		stage = "done"
		player.set_sword_upgrade(quest_cfg.reward_damage_multiplier, _color(quest_cfg.reward_blade_color))
		hud.show_notice("Quest complete!\nYour sword now carries the island's heart.")
	if stage != before:
		_refresh()
		progress_changed.emit()


## True while a conversation is open (the player shouldn't attack then).
func in_dialogue() -> bool:
	return dialogue_index >= 0


static func _color(a: Array) -> Color:
	return Color(a[0], a[1], a[2])

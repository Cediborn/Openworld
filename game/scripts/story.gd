class_name Story
extends Node3D
## People and conversations. Spawns the villagers, finds the nearest thing to
## interact with (a villager, a heart-stone or any Interactable), shows the
## prompt, and runs dialogue: pages of lines that can end in choices.
##
## It also still runs the Elder's original quest ("The Island's Heart"):
## intro -> hunt -> return -> forge -> done. Every newer quest lives in the
## Quests node, which Story asks first whenever you talk to someone.

## Emitted whenever quest progress changes (the world autosaves on it).
signal progress_changed
## Emitted after any conversation with a villager ends.
signal talked(v: Villager)

const STAGES := ["intro", "hunt", "return", "forge", "done"]

## How far away (metres) a mission giver's "!" can still be seen.
const MARKER_RANGE := 600.0
var data: WorldData
var player: Player
var hud: Hud
var town: Town
var touch := false
var npc_cfg: Dictionary
var quest_cfg: Dictionary
var villagers: Array[Villager] = []
var by_id := {}
var stones := {}             # id -> Node3D (removed once picked up)
var stage := "intro"
var found: Array = []        # ids of heart-stones picked up
var focus = null             # Villager, stone id or Interactable under the prompt
var _cull := 0.0
var mobile := false
## How many villagers are drawn at once (0 = this device's default).
var draw_cap := 0
## Newer systems, set by the world.
var quests: Quests
var state: GameState
var services: Callable       # (villager) -> conversation Dictionary or {}
## Called when Bram finishes the heart-stone blade.
var on_heart_blade: Callable

# A conversation: {"speaker", "lines": [..], "choices": [..], "on_choice": Callable(i) -> next convo or {}, "on_end": Callable}
var convo: Dictionary = {}
var line_i := -1
var dialogue_with: Villager


func setup(world_data: WorldData, p: Player, h: Hud, is_touch: bool, t: Town = null, is_mobile := false) -> void:
	data = world_data
	player = p
	hud = h
	touch = is_touch
	town = t
	mobile = is_mobile
	npc_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/npcs.json"))
	quest_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/quest.json"))
	var i := 0
	var extras := 0
	for v: Dictionary in npc_cfg.villagers:
		# Phones run out of memory with every townsperson: keep everyone with
		# a role, and only a few background villagers.
		if mobile and v.get("role", "") in ["villager", "guard"] and not v.get("keep", false):
			extras += 1
			if extras > 6:
				continue
		spawn_villager(v, 77 + i)
		i += 1
	hud.interact_pressed.connect(interact)
	hud.dialogue_advanced.connect(_advance)
	hud.choice_made.connect(_choose)
	_refresh()


func spawn_villager(v: Dictionary, seed_value: int) -> Villager:
	var vil := Villager.new()
	add_child(vil)
	vil.setup(v, seed_value)
	vil.player = player
	vil.town = town
	vil.height_at = func(x: float, z: float) -> float: return data.height(x, z)
	vil.global_position = Vector3(vil.home.x, data.height(vil.home.x, vil.home.z), vil.home.z)
	if v.has("face"):
		vil.rotation.y = deg_to_rad(float(v.face))
	else:
		vil.rotation.y = PI if vil.home.z < -2.0 else 0.0   # face the street
	villagers.append(vil)
	by_id[vil.id] = vil
	return vil


func remove_villager(id: String) -> void:
	var v: Villager = by_id.get(id)
	if v == null:
		return
	villagers.erase(v)
	by_id.erase(id)
	v.queue_free()


## Restores progress from a save.
func load_state(s: Dictionary) -> void:
	stage = s.get("stage", "intro")
	found = s.get("found", [])
	if stage == "done" and on_heart_blade.is_valid():
		on_heart_blade.call(true)
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


## The original quest's tracker text ("" once it is done; Quests shows the rest).
func original_tracker() -> String:
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
	return t


## Where the original quest wants you to go next (for the objective marker).
func original_target() -> Vector3:
	match stage:
		"intro", "return":
			return by_id["elder"].global_position if by_id.has("elder") else Vector3.INF
		"forge":
			return by_id["smith"].global_position if by_id.has("smith") else Vector3.INF
		"hunt":
			var best := Vector3.INF
			for id in stones:
				var p: Vector3 = stones[id].global_position
				if best == Vector3.INF or p.distance_to(player.global_position) < best.distance_to(player.global_position):
					best = p
			return best
	return Vector3.INF


func _update_tracker() -> void:
	if quests:
		quests.refresh_tracker()
	else:
		hud.set_quest(original_tracker())


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
		_cull_villagers()
	if line_i >= 0:
		return
	_find_focus()


## Hides far villagers, animates mid-distance ones less often, and on phones
## keeps only the nearest ones awake.
func _cull_villagers() -> void:
	var far: float = npc_cfg.active_distance
	var p := player.global_position
	var list := []
	for v in villagers:
		list.append([v.global_position.distance_squared_to(p), v])
	list.sort_custom(func(a, b): return a[0] < b[0])
	var cap := draw_cap if draw_cap > 0 else (18 if mobile else 60)
	for i in list.size():
		var v: Villager = list[i][1]
		var d := sqrt(list[i][0])
		var on: bool = d < far and i < cap
		if v.hiding and not v.visible:
			on = false
		# Someone with a mission for you keeps their "!" in view from afar,
		# even when they are too far away to be drawn themselves.
		var mark: String = quests.marker_for(v) if quests else ""
		var beacon: bool = mark != "" and not v.hiding and d < MARKER_RANGE
		v.visible = on or (v.hiding and v.visible) or beacon
		if v.body:
			v.body.visible = on or v.hiding
		v.process_mode = Node.PROCESS_MODE_INHERIT if (on or v.hiding) else Node.PROCESS_MODE_DISABLED
		v.set_marker(mark if (on or beacon) else "")
		var cam := get_viewport().get_camera_3d()
		Villager.fit_marker(v.marker, v.marker.global_position.distance_to(cam.global_position) if cam else d)
		v.lod = 0 if d < 35.0 else 1
		if v.body:
			for mi: GeometryInstance3D in v.body.find_children("*", "MeshInstance3D", true, false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d < 30.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _find_focus() -> void:
	focus = null
	var label := ""
	if player.dead or get_tree().paused:
		hud.set_prompt("", touch)
		return
	var best: float = npc_cfg.talk_distance
	for v in villagers:
		if not v.visible:
			continue
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
	var best_i := INF
	for it: Interactable in get_tree().get_nodes_in_group("interactables"):
		if not it.enabled or not it.is_visible_in_tree():
			continue
		var d := it.global_position.distance_to(player.global_position)
		if d < it.radius and d < best_i:
			best_i = d
			if d < best + 0.5 or not focus is Villager:
				focus = it
				label = it.label
	hud.set_prompt(label, touch)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if line_i >= 0:
			if not hud.has_choices():
				_advance()
		else:
			interact()


## Talks to the focused villager, picks up a heart-stone or uses an Interactable.
func interact() -> void:
	if focus == null or line_i >= 0 or player.dead:
		return
	if focus is Villager:
		_start_dialogue(focus)
	elif focus is String and stones.has(focus):
		_pick_up(focus)
	elif focus is Interactable and is_instance_valid(focus):
		focus.use()


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


# ---------- Conversations ----------

## Opens a conversation (also used by quests and world features for
## narration: speaker "" shows no name).
func open(c: Dictionary, with: Villager = null) -> void:
	if c.is_empty() or c.get("lines", []).is_empty():
		if c.has("on_end") and c.on_end.is_valid():
			c.on_end.call()
		return
	convo = c
	line_i = 0
	dialogue_with = with
	if state:
		# Inscriptions read and rumours heard go into the journal.
		if c.has("lore"):
			state.add_note("lore", c.lore, "\n".join(c.lines))
		elif c.has("note"):
			state.add_note("rumour", c.note, "\n".join(c.lines))
	if with:
		with.set_talking(true)
	player.in_conversation = true
	hud.set_prompt("", touch)
	if not touch:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # so choices can be clicked
	_show_line()


func _show_line() -> void:
	var lines: Array = convo.lines
	var last := line_i == lines.size() - 1
	var speaker: String = convo.get("speaker", dialogue_with.display_name if dialogue_with else "")
	hud.show_dialogue(speaker, lines[line_i], convo.get("choices", []) if last else [])


func _start_dialogue(v: Villager) -> void:
	var c: Dictionary = {}
	if quests:
		c = quests.handle_talk(v)
	if c.is_empty():
		c = _original_talk(v)
	if c.is_empty() and services.is_valid():
		c = services.call(v)
	if c.is_empty():
		var lines := v.lines_for(stage if v.cfg.get("lines", {}).has(stage) else "default")
		c = {"lines": lines}
	c["speaker"] = v.display_name
	if state:
		state.flags["met:" + v.id] = true   # the journal's People section
	open(c, v)


## The Elder's and Bram's lines for the original quest while it is running.
func _original_talk(v: Villager) -> Dictionary:
	if stage == "done":
		return {}
	if v.id in ["elder", "smith", "baker", "lina", "kid"] and v.cfg.lines.has(stage):
		return {"lines": v.cfg.lines[stage], "on_end": func() -> void: _after_dialogue(v)}
	return {}


func _advance() -> void:
	if line_i < 0:
		return
	if line_i == convo.lines.size() - 1 and not convo.get("choices", []).is_empty():
		return   # waiting for a choice
	line_i += 1
	if line_i < convo.lines.size():
		_show_line()
		return
	_finish({})


func _choose(i: int) -> void:
	if line_i < 0 or convo.get("choices", []).is_empty():
		return
	var next: Dictionary = {}
	if convo.has("on_choice") and convo.on_choice.is_valid():
		var r = convo.on_choice.call(i)
		if r is Dictionary:
			next = r
	_finish(next)


func _finish(next: Dictionary) -> void:
	var ended := convo
	var with := dialogue_with
	line_i = -1
	convo = {}
	hud.hide_dialogue()
	if not next.is_empty() and not next.get("lines", []).is_empty():
		if with and not next.has("speaker"):
			next["speaker"] = with.display_name
		open(next, with)
		return
	if with:
		with.set_talking(false)
	player.in_conversation = false
	dialogue_with = null
	if not touch and not get_tree().paused and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if ended.has("on_end") and ended.on_end.is_valid():
		ended.on_end.call()
	if not next.is_empty() and next.has("on_end") and next.on_end.is_valid():
		next.on_end.call()
	if with:
		talked.emit(with)


## Quest stage changes happen when a conversation ends.
func _after_dialogue(v: Villager) -> void:
	var role: String = v.cfg.get("role", "")
	var before := stage
	if role == "quest_giver" and v.id == "elder" and stage == "intro":
		stage = "hunt"
		hud.show_notice("New quest: " + quest_cfg.title + "\nFind the three heart-stones.")
	elif role == "quest_giver" and v.id == "elder" and stage == "return":
		stage = "forge"
	elif role == "smith" and stage == "forge":
		stage = "done"
		if on_heart_blade.is_valid():
			on_heart_blade.call(false)
		else:
			player.set_sword_upgrade(quest_cfg.reward_damage_multiplier, _color(quest_cfg.reward_blade_color))
		hud.show_notice("Quest complete!\nYour sword now carries the island's heart.")
	if stage != before:
		_refresh()
		progress_changed.emit()


## True while a conversation is open (the player shouldn't attack then).
func in_dialogue() -> bool:
	return line_i >= 0


static func _color(a: Array) -> Color:
	return Color(a[0], a[1], a[2])

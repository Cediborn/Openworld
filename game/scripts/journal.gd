class_name Journal
extends CanvasLayer
## The journal (J, or the book button on phones): quests split into Main
## Story, Side Quests, Special Quests, Contracts and Completed, each with its
## description, objectives (done ones ticked), location and rewards; a map of
## the island; the explorer's gear and bag; and progress (discoveries,
## shrines, treasures, bosses). The game pauses while it is open.

signal closed

var quests: Quests
var state: GameState
var features: WorldFeatures
var data: WorldData
var player: Player
var panel: PanelContainer
var tabs: TabContainer
var quest_list: ItemList
var quest_detail: RichTextLabel
var track_btn: Button
var quest_ids: Array = []
var map_rect: TextureRect
var map_marks: Control
var gear_list: ItemList
var gear_detail: RichTextLabel
var gear_ids: Array = []
var progress_text: RichTextLabel
var filter := "main"
var map_tex: Texture2D


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60
	panel.offset_right = -60
	panel.offset_top = 40
	panel.offset_bottom = -40
	panel.add_theme_stylebox_override("panel", Hud._box(Color(0.09, 0.08, 0.07, 0.96), 18))
	add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var title := Label.new()
	title.text = "Journal"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := _button("Close  [J]")
	close.pressed.connect(close_journal)
	top.add_child(close)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 24)
	col.add_child(tabs)
	_build_quests_tab()
	_build_map_tab()
	_build_gear_tab()
	_build_progress_tab()
	tabs.tab_changed.connect(func(_i: int) -> void: refresh())


func _button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_stylebox_override("normal", Hud._box(Color(0.25, 0.22, 0.18, 0.95), 10))
	b.add_theme_stylebox_override("hover", Hud._box(Color(0.38, 0.32, 0.22, 0.95), 10))
	b.add_theme_stylebox_override("pressed", Hud._box(Color(0.5, 0.4, 0.25, 0.95), 10))
	return b


func _build_quests_tab() -> void:
	var root := VBoxContainer.new()
	root.name = "Quests"
	tabs.add_child(root)
	var filters := HBoxContainer.new()
	root.add_child(filters)
	for f in [["main", "Main Story"], ["side", "Side Quests"], ["special", "Special"], ["contract", "Contracts"], ["done", "Completed"]]:
		var b := _button(f[1])
		var key: String = f[0]
		b.pressed.connect(func() -> void:
			filter = key
			refresh())
		filters.add_child(b)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	quest_list = ItemList.new()
	quest_list.custom_minimum_size = Vector2(430, 0)
	quest_list.add_theme_font_size_override("font_size", 22)
	quest_list.item_selected.connect(func(i: int) -> void: _show_quest(quest_ids[i]))
	split.add_child(quest_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	quest_detail = RichTextLabel.new()
	quest_detail.bbcode_enabled = true
	quest_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quest_detail.add_theme_font_size_override("normal_font_size", 22)
	quest_detail.add_theme_font_size_override("bold_font_size", 26)
	right.add_child(quest_detail)
	track_btn = _button("Track this quest")
	track_btn.pressed.connect(func() -> void:
		var sel := quest_list.get_selected_items()
		if not sel.is_empty():
			quests.track(quest_ids[sel[0]])
			_show_quest(quest_ids[sel[0]]))
	right.add_child(track_btn)


func _build_map_tab() -> void:
	var root := Control.new()
	root.name = "Map"
	tabs.add_child(root)
	map_rect = TextureRect.new()
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(map_rect)
	map_marks = Control.new()
	map_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_marks.draw.connect(_draw_map)
	root.add_child(map_marks)


func _build_gear_tab() -> void:
	var split := HSplitContainer.new()
	split.name = "Gear & Bag"
	tabs.add_child(split)
	gear_list = ItemList.new()
	gear_list.custom_minimum_size = Vector2(430, 0)
	gear_list.add_theme_font_size_override("font_size", 22)
	gear_list.item_selected.connect(func(i: int) -> void: _show_item(gear_ids[i]))
	split.add_child(gear_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	gear_detail = RichTextLabel.new()
	gear_detail.bbcode_enabled = true
	gear_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gear_detail.add_theme_font_size_override("normal_font_size", 22)
	gear_detail.add_theme_font_size_override("bold_font_size", 26)
	right.add_child(gear_detail)
	var equip := _button("Equip")
	equip.pressed.connect(func() -> void:
		var sel := gear_list.get_selected_items()
		if not sel.is_empty():
			state.equip(gear_ids[sel[0]])
			refresh())
	right.add_child(equip)


func _build_progress_tab() -> void:
	progress_text = RichTextLabel.new()
	progress_text.name = "Progress"
	progress_text.bbcode_enabled = true
	progress_text.add_theme_font_size_override("normal_font_size", 22)
	progress_text.add_theme_font_size_override("bold_font_size", 26)
	tabs.add_child(progress_text)


func open_journal() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close_journal() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_J or (visible and event.keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			if visible:
				close_journal()
			elif not get_tree().paused:
				open_journal()


func refresh() -> void:
	if not visible:
		return
	match tabs.current_tab:
		0:
			_fill_quests()
		1:
			map_marks.queue_redraw()
			if map_tex == null:
				map_tex = _make_map()
				map_rect.texture = map_tex
		2:
			_fill_gear()
		3:
			_fill_progress()


# ---------- Quests ----------

func _fill_quests() -> void:
	quest_list.clear()
	quest_ids.clear()
	var order := ["active", "available", "locked", "completed"]
	var list := []
	for id in quests.defs:
		var d: Dictionary = quests.defs[id]
		var st := quests.status(id)
		var typ: String = d.get("type", "side")
		if filter == "done":
			if st != "completed":
				continue
		elif typ != filter or st == "completed":
			continue
		if typ == "contract" and st != "active" and filter != "done":
			continue
		if st == "locked" and typ != "main":
			continue   # hidden until it can be started (keeps the list readable)
		list.append([order.find(st), int(d.get("chapter", 50)), id])
	list.sort()
	for e in list:
		var id: String = e[2]
		var st := quests.status(id)
		var mark: String = {"active": "▶ ", "available": "! ", "locked": "🔒 ", "completed": "✔ "}.get(st, "")
		if st == "locked":
			mark = "· "
		quest_list.add_item(mark + quests.defs[id].title + ("   (tracked)" if quests.tracked == id else ""))
		quest_ids.append(id)
	if quest_ids.is_empty():
		quest_detail.text = "Nothing here yet."
		track_btn.visible = false
	else:
		quest_list.select(0)
		_show_quest(quest_ids[0])


func _show_quest(id: String) -> void:
	var d: Dictionary = quests.defs[id]
	var st := quests.status(id)
	var t := "[b]%s[/b]\n" % d.title
	t += "[color=#e0c890]%s  ·  %s  ·  %s[/color]\n\n" % [{"main": "Main Story", "side": "Side Quest", "special": "Special Quest", "contract": "Monster Contract"}.get(d.get("type", "side"), ""),
		d.get("region", ""), {"active": "Active", "available": "Available", "locked": "Locked", "completed": "Completed"}.get(st, st)]
	t += d.get("description", "") + "\n\n"
	if st == "locked":
		var need := []
		for r in d.get("requires", []):
			if not quests.is_done(r):
				need.append(quests.defs[r].title)
		t += "[i]Unlocks after: %s[/i]\n\n" % ", ".join(need)
	if st == "available":
		if d.has("giver"):
			t += "[i]Talk to %s to begin.[/i]\n\n" % _npc_name(d.giver)
		elif d.has("trigger"):
			t += "[i]Something in %s will set you on this trail.[/i]\n\n" % d.get("region", "the world")
	if id == "island_heart" and st == "active":
		t += "[b]Objectives[/b]\n" + quests.story.original_tracker() + "\n"
	if quests.q.has(id) and d.has("steps"):
		t += "[b]Objectives[/b]\n"
		var cur: int = quests.q[id].step
		for si in d.steps.size():
			var step: Dictionary = d.steps[si]
			if si < cur or st == "completed":
				t += "[color=#8fd08f]✔ %s[/color]\n" % quests.step_text(step)
			elif si == cur:
				var goals := Quests.goals_of(step)
				if goals.size() > 1:
					t += "○ %s\n" % quests.step_text(step)
				for gi in goals.size():
					var g: Dictionary = goals[gi]
					var done := quests.goal_done(id, gi)
					var need := quests._need(g)
					var have := state.count(g.item) if g.type == "have" else quests.progress(id, gi)
					var prog := " (%d/%d)" % [mini(have, need), need] if need > 1 else ""
					t += ("    " if goals.size() > 1 else "") + ("[color=#8fd08f]✔ " if done else "○ ") + quests.goal_text(g) + prog + ("[/color]" if done else "") + "\n"
				break
	var r := quests.reward_text(id)
	if r != "":
		t += "\n[b]Rewards[/b]\n%s%s\n" % [r, "  [color=#8fd08f](received)[/color]" if st == "completed" else ""]
	quest_detail.text = t
	track_btn.visible = st == "active" and quests.tracked != id


func _npc_name(id: String) -> String:
	if quests.story.by_id.has(id):
		return quests.story.by_id[id].display_name
	return id.capitalize()


# ---------- Map ----------

func _make_map() -> Texture2D:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var cols := [Color(0.35, 0.55, 0.25), Color(0.9, 0.92, 0.96), Color(0.38, 0.22, 0.16), Color(0.15, 0.3, 0.45), Color(0.62, 0.56, 0.42)]
	for j in 256:
		for i in 256:
			var x := -512.0 + i * 4.0
			var z := -512.0 + j * 4.0
			var w := data.zone(x, z)
			var c := Color(0, 0, 0)
			for k in 5:
				c += cols[k] * float(w[k])
			var h := data.height(x, z)
			var shade := clampf(0.85 + (h - data.height(x - 4.0, z)) * 0.08, 0.55, 1.2)
			c = c * shade
			if h < WorldData.LAVA_LEVEL + 0.05 and float(w[2]) > 0.3:
				c = Color(1.0, 0.45, 0.1)
			if data.on_path(x, z) > 0.5:
				c = c.lerp(Color(0.75, 0.68, 0.5), 0.6)
			img.set_pixel(i, j, c)
	return ImageTexture.create_from_image(img)


func _map_xf() -> Array:
	var size := map_rect.size
	var s := minf(size.x, size.y)
	var off := map_rect.position + (size - Vector2(s, s)) * 0.5
	return [off, s / 1024.0]


func _to_map(p: Vector2) -> Vector2:
	var xf := _map_xf()
	return xf[0] + (p + Vector2(512, 512)) * xf[1]


func _draw_map() -> void:
	if not visible or features == null:
		return
	var font := ThemeDB.fallback_font
	for pt in features.map_points():
		var mp := _to_map(pt[1])
		var known: bool = pt[2]
		map_marks.draw_circle(mp, 6.0, Color(1.0, 0.9, 0.5) if known else Color(0.6, 0.6, 0.65))
		map_marks.draw_string_outline(font, mp + Vector2(9, 6), pt[0] if known else "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
		map_marks.draw_string(font, mp + Vector2(9, 6), pt[0] if known else "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE if known else Color(0.8, 0.8, 0.8))
	# Quest givers with something to offer, and the tracked objective.
	for v in quests.story.villagers:
		var m := quests.marker_for(v)
		if m != "":
			var mp2 := _to_map(Vector2(v.global_position.x, v.global_position.z))
			map_marks.draw_string_outline(font, mp2 + Vector2(-5, 8), m, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 5, Color(0, 0, 0, 0.8))
			map_marks.draw_string(font, mp2 + Vector2(-5, 8), m, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.85, 0.2) if m == "!" else Color(0.55, 0.85, 1.0))
	var obj := quests.objective_position()
	if obj != Vector3.INF:
		var op := _to_map(Vector2(obj.x, obj.z))
		map_marks.draw_colored_polygon(PackedVector2Array([op + Vector2(0, -12), op + Vector2(9, 0), op + Vector2(0, 12), op + Vector2(-9, 0)]), Color(1.0, 0.8, 0.2))
	var pp := _to_map(Vector2(player.global_position.x, player.global_position.z))
	var fwd := Vector2(sin(player.body.rotation.y), cos(player.body.rotation.y))
	map_marks.draw_colored_polygon(PackedVector2Array([pp + fwd * 12.0, pp + fwd.orthogonal() * 7.0 - fwd * 6.0, pp - fwd.orthogonal() * 7.0 - fwd * 6.0]), Color(1.0, 0.3, 0.25))
	for zi in 5:
		var centres := [Vector2(0, 0), Vector2(0, -300), Vector2(300, 0), Vector2(0, 300), Vector2(-300, 0)]
		var zp := _to_map(centres[zi]) + Vector2(-50, -30)
		map_marks.draw_string_outline(font, zp, WorldData.ZONE_NAMES[zi], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color(0, 0, 0, 0.7))
		map_marks.draw_string(font, zp, WorldData.ZONE_NAMES[zi], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.85))


# ---------- Gear ----------

func _fill_gear() -> void:
	gear_list.clear()
	gear_ids.clear()
	var ids := ["iron_sword"] + state.items.keys()
	var kinds := ["weapon", "armor", "potion", "key", "quest", "material", "collectible", "trophy"]
	ids.sort_custom(func(a, b): return kinds.find(state.item(a).kind) < kinds.find(state.item(b).kind) or (kinds.find(state.item(a).kind) == kinds.find(state.item(b).kind) and a < b))
	for id in ids:
		var it := state.item(id)
		var n := 1 if id == "iron_sword" else state.count(id)
		var eq: bool = (id == state.weapon or id == state.armor)
		gear_list.add_item(("★ " if eq else "") + it.name + (" ×%d" % n if n > 1 else "") + "   [%s]" % it.kind)
		gear_ids.append(id)
	_show_stats()


func _show_stats() -> void:
	gear_detail.text = "[b]%s[/b]\nLevel %d   XP %d / %d   Coins %d   Reputation %d\nSword damage ×%.2f   Health %d\nWeapon: %s\nArmour: %s" % [
		"The Explorer", state.level, state.xp, state.xp_for_next(), state.coins, state.reputation, state.sword_damage_mult(), int(player.max_health),
		state.item_name(state.weapon), state.item_name(state.armor) if state.armor != "" else "none"]


func _show_item(id: String) -> void:
	var it := state.item(id)
	var t := "[b]%s[/b]\n[color=#e0c890]%s[/color]\n\n%s\n" % [it.name, it.kind.capitalize(), it.get("desc", "")]
	if it.kind == "weapon":
		t += "\nDamage ×%.2f" % float(it.get("damage", 1.0))
	if it.kind == "armor":
		t += "\nDamage taken ×%.2f" % float(it.get("armor", 1.0))
		if it.has("frost"):
			t += "   Frost ×%.2f" % float(it.frost)
		if it.has("fire"):
			t += "   Fire ×%.2f" % float(it.fire)
	gear_detail.text = t


# ---------- Progress ----------

func _fill_progress() -> void:
	var t := "[b]Progress[/b]\n\n"
	var d_total: int = features.cfg.discoveries.size()
	var d_found := 0
	for d in features.cfg.discoveries:
		if state.has_flag("disc:" + d.id):
			d_found += 1
	var sh := 0
	for s in features.cfg.shrines:
		if state.has_flag("shrine:" + s.id):
			sh += 1
	var tr := 0
	for x in features.cfg.treasures:
		if state.has_flag("treasure:" + x.id):
			tr += 1
	var rb := 0
	for b in features.cfg.rare_bosses:
		if state.has_flag("boss:" + b.id):
			rb += 1
	var qd := 0
	var qt := 0
	for id in quests.defs:
		if quests.defs[id].get("type") in ["main", "side", "special"]:
			qt += 1
			if quests.is_done(id):
				qd += 1
	t += "Quests completed: %d / %d\nPlaces discovered: %d / %d\nShrines awakened: %d / %d\nTreasures found: %d / %d\nRare bosses defeated: %d / %d\nContracts completed: %d\n\n" % [
		qd, qt, d_found, d_total, sh, features.cfg.shrines.size(), tr, features.cfg.treasures.size(), rb, features.cfg.rare_bosses.size(), _contracts_done()]
	t += "[b]Achievements[/b]\n"
	var ach := [
		["Heart of the Island", quests.is_done("island_heart")], ["The Shattered Island", quests.is_done("awakening")],
		["Cartographer (all places)", d_found == d_total], ["Pilgrim (all shrines)", sh == features.cfg.shrines.size()],
		["Treasure Hunter (all treasure)", tr == features.cfg.treasures.size()], ["Titan Slayer (all rare bosses)", rb == features.cfg.rare_bosses.size()],
		["Defender of Brickton", quests.is_done("night_beasts")], ["Heir of Caldor", quests.is_done("forgotten_kingdom")]]
	for a in ach:
		t += ("[color=#8fd08f]✔ " if a[1] else "○ ") + a[0] + ("[/color]" if a[1] else "") + "\n"
	t += "\n[b]Trophies[/b]\n"
	var any := false
	for id in state.items:
		if state.item(id).kind == "trophy":
			t += "• " + state.item_name(id) + "\n"
			any = true
	if not any:
		t += "None yet.\n"
	progress_text.text = t


func _contracts_done() -> int:
	var n := 0
	for id in quests.q:
		if quests.defs.get(id, {}).get("type") == "contract" and quests.q[id].state == "completed":
			n += 1
	return n

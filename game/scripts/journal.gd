class_name Journal
extends CanvasLayer
## The adventurer's journal (J, or the book button on phones): a two-page
## parchment book with ribbon bookmarks for Quests, People, Discoveries,
## Lore, Notes, Inventory and the Map. Every entry comes from the game's own
## records: quests from Quests, people you have talked to, places, shrines
## and treasure you have found, inscriptions you have read, rumours you have
## heard, the items in your bag. The game pauses while it is open.

signal closed

var quests: Quests
var state: GameState
var features: WorldFeatures
var data: WorldData
var player: Player

const SECTIONS := [["quests", "Quests", "quest"], ["people", "People", "person"], ["discoveries", "Discoveries", "discovery"],
	["lore", "Lore", "lore"], ["notes", "Notes", "note"], ["inventory", "Inventory", "armor"], ["map", "Map", "map"]]
const QUEST_FILTERS := [["main", "Main"], ["side", "Side"], ["special", "Special"], ["contract", "Contracts"], ["done", "Completed"]]
const ITEM_FILTERS := [["all", "All"], ["weapon", "Weapons"], ["armor", "Armour"], ["potion", "Potions"], ["material", "Materials"], ["valuable", "Valuables"], ["quest", "Quest"]]
const KIND_ICON := {"weapon": "sword", "armor": "armor", "potion": "potion", "key": "key", "quest": "quest", "material": "material",
	"collectible": "collectible", "trophy": "trophy"}
const INK_HEX := "#38230f"
const SOFT_HEX := "#6b4a26"
const DONE_HEX := "#4f6b25"

var section := "quests"
var filter := "main"
var item_filter := "all"
var sort_by_name := false

var book: PanelContainer
var spread: HBoxContainer
var left_page: PanelContainer
var right_page: PanelContainer
var map_page: PanelContainer
var tab_buttons := {}
var page_title: Label
var page_count: Label
var filter_row: HFlowContainer
var list: ItemList
var list_ids: Array = []
var detail: RichTextLabel
var detail_title: Label
var empty_icon: TextureRect
var seal: TextureRect
var action_btn: Button
var portrait: SubViewportContainer
var portrait_cam: Camera3D

var map_view: Control
var map_tex: Texture2D
var map_zoom := 1.0
var map_pan := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	book = PanelContainer.new()
	book.set_anchors_preset(Control.PRESET_FULL_RECT)
	book.offset_left = 40
	book.offset_right = -40
	book.offset_top = 22
	book.offset_bottom = -22
	book.add_theme_stylebox_override("panel", UiTheme.frame_box(18))
	root.add_child(book)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	book.add_child(col)

	# Ribbon bookmarks across the top, the close button at the end.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	col.add_child(top)
	for s in SECTIONS:
		var key: String = s[0]
		var b := UiTheme.button(s[1], s[2], func() -> void: _show_section(key), Vector2(0, 58))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 19)
		b.set_meta("silent", true)   # the page turn is the sound
		top.add_child(b)
		tab_buttons[key] = b
	var close := UiTheme.button("Close", "", close_journal, Vector2(130, 58))
	close.tooltip_text = "Close the journal (J or Esc)"
	top.add_child(close)

	spread = HBoxContainer.new()
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spread.add_theme_constant_override("separation", 0)
	col.add_child(spread)
	left_page = _page()
	right_page = _page()
	spread.add_child(left_page)
	spread.add_child(_spine())
	spread.add_child(right_page)
	_build_left()
	_build_right()

	map_page = _page()
	map_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_page.visible = false
	col.add_child(map_page)
	_build_map()


func _page() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.0
	p.add_theme_stylebox_override("panel", UiTheme.parchment_box(40))
	p.theme = UiTheme.paper_theme()
	return p


## The shadowed gutter where the two pages meet.
func _spine() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.1, 0.06, 0.03, 0.0))
	g.set_color(1, Color(0.1, 0.06, 0.03, 0.0))
	g.add_point(0.5, Color(0.1, 0.06, 0.03, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 32
	gt.height = 4
	var r := TextureRect.new()
	r.texture = gt
	r.custom_minimum_size = Vector2(26, 0)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	return r


func _build_left() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	left_page.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	page_title = UiTheme.label("", 34, UiTheme.INK, UiTheme.title_font())
	page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(page_title)
	page_count = UiTheme.label("", 20, UiTheme.INK_SOFT, UiTheme.italic_font())
	page_count.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(page_count)
	v.add_child(_rule())
	filter_row = HFlowContainer.new()
	filter_row.add_theme_constant_override("h_separation", 6)
	filter_row.add_theme_constant_override("v_separation", 6)
	v.add_child(filter_row)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(30, 30)
	list.item_selected.connect(func(i: int) -> void:
		UiTheme.sound(get_tree(), "ui_click", -16.0)
		_select(i))
	v.add_child(list)


func _build_right() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	right_page.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	detail_title = UiTheme.label("", 32, UiTheme.INK, UiTheme.title_font())
	detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(detail_title)
	seal = TextureRect.new()
	seal.texture = UiTheme.tex("seal")
	seal.custom_minimum_size = Vector2(72, 72)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.tooltip_text = "Completed"
	head.add_child(seal)
	v.add_child(_rule())

	# The explorer as they stand now (inventory only): a second camera on the live world.
	portrait = SubViewportContainer.new()
	portrait.stretch = true
	portrait.custom_minimum_size = Vector2(0, 300)
	portrait.visible = false
	var sv := SubViewport.new()
	sv.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	sv.msaa_3d = Viewport.MSAA_DISABLED
	portrait.add_child(sv)
	portrait_cam = Camera3D.new()
	portrait_cam.fov = 32.0
	sv.add_child(portrait_cam)
	v.add_child(portrait)

	empty_icon = TextureRect.new()
	empty_icon.custom_minimum_size = Vector2(0, 150)
	empty_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	empty_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	empty_icon.modulate = Color(UiTheme.INK_SOFT, 0.35)
	v.add_child(empty_icon)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(detail)
	action_btn = UiTheme.button("", "", _action, Vector2(0, 60))
	v.add_child(action_btn)


func _rule() -> TextureRect:
	var r := TextureRect.new()
	r.texture = UiTheme.tex("divider")
	r.custom_minimum_size = Vector2(0, 14)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.modulate = Color(0.55, 0.38, 0.2, 0.9)
	return r


# ---------- Opening, closing, sections ----------

## Opens the journal, optionally on a section ("quests", "inventory", "map", ...).
func open_journal(at := "") -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiTheme.sound(get_tree(), "ui_open", -12.0)
	_show_section(at if at != "" else section, false)
	UiTheme.reveal(book, 0.2)


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


func _show_section(key: String, turn := true) -> void:
	if turn and key != section:
		UiTheme.sound(get_tree(), "page_turn", -10.0)
		_turn_page()
	section = key
	for k in tab_buttons:
		tab_buttons[k].set_pressed_no_signal(k == key)
	spread.visible = key != "map"
	map_page.visible = key == "map"
	refresh()


## A page-turn: the right page folds in from the spine (skipped with reduced motion).
func _turn_page() -> void:
	if UiTheme.reduced_motion or not visible:
		return
	var page: Control = map_page if section == "map" else right_page
	page.pivot_offset = Vector2(0, page.size.y * 0.5)
	page.scale.x = 0.2
	page.modulate.a = 0.3
	var tw := create_tween().set_parallel()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(page, "scale:x", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(page, "modulate:a", 1.0, 0.22)


func refresh() -> void:
	if not visible:
		return
	portrait.visible = false
	match section:
		"quests":
			_fill_quests()
		"people":
			_fill_people()
		"discoveries":
			_fill_discoveries()
		"lore":
			_fill_notes("lore")
		"notes":
			_fill_notes("rumour")
		"inventory":
			_fill_inventory()
		"map":
			map_view.queue_redraw()
			if map_tex == null:
				map_tex = _make_map()


# ---------- Shared page plumbing ----------

func _begin(title: String, filters: Array, current: String, on_pick: Callable) -> void:
	page_title.text = title
	list.clear()
	list_ids.clear()
	for c in filter_row.get_children():
		c.queue_free()
	for f in filters:
		var key: String = f[0]
		var b := UiTheme.button(f[1], "", func() -> void: on_pick.call(key), Vector2(0, 46))
		b.toggle_mode = true
		b.set_pressed_no_signal(key == current)
		b.add_theme_font_size_override("font_size", 18)
		filter_row.add_child(b)
	filter_row.visible = not filters.is_empty()


func _add(id: Variant, text: String, icon_name: String, tint := UiTheme.INK_SOFT) -> void:
	var i := list.add_item(text, UiTheme.icon(icon_name))
	list.set_item_icon_modulate(i, tint)
	list_ids.append(id)


func _finish(empty_title: String, empty_icon_name: String, empty_text: String) -> void:
	page_count.text = "%d" % list_ids.size() if list_ids.size() > 0 else ""
	if list_ids.is_empty():
		_detail(empty_title, "[i]%s[/i]" % empty_text, false)
		empty_icon.texture = UiTheme.icon(empty_icon_name)
		empty_icon.visible = true
		action_btn.visible = false
	else:
		list.select(0)
		_select(0)


func _detail(title: String, bbcode: String, sealed: bool) -> void:
	detail_title.text = title
	detail.text = bbcode
	seal.visible = sealed
	empty_icon.visible = false
	action_btn.visible = false
	detail.scroll_to_line(0)


func _select(i: int) -> void:
	if i < 0 or i >= list_ids.size():
		return
	match section:
		"quests":
			_show_quest(list_ids[i])
		"people":
			_show_person(list_ids[i])
		"discoveries":
			_show_discovery(list_ids[i])
		"lore", "notes":
			var n: Dictionary = list_ids[i]
			_detail(n.title, "[i]%s[/i]" % n.text, false)
		"inventory":
			_show_item(list_ids[i])


func _action() -> void:
	var sel := list.get_selected_items()
	if sel.is_empty():
		return
	var id = list_ids[sel[0]]
	match section:
		"quests":
			if quests.status(id) == "declined":
				quests.start(id)
			else:
				quests.track(id)
			_show_quest(id)
			_relabel_quests()
		"inventory":
			state.equip(id)
			_fill_inventory()


# ---------- Quests ----------

func _fill_quests() -> void:
	_begin("Quests", QUEST_FILTERS, filter, func(k: String) -> void:
		filter = k
		_fill_quests())
	var order := ["active", "available", "declined", "locked", "completed"]
	var rows := []
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
		rows.append([order.find(st), int(d.get("chapter", 50)), id])
	rows.sort()
	for e in rows:
		var id: String = e[2]
		var st := quests.status(id)
		var tint: Color = {"active": Color(0.55, 0.3, 0.05), "available": Color(0.62, 0.45, 0.1), "completed": Color(0.45, 0.1, 0.08)}.get(st, Color(UiTheme.INK_SOFT, 0.5))
		_add(id, "", "quest" if st != "completed" else "discovery", tint)
	_relabel_quests()
	_finish("No entries", "quest", {"main": "The main story will be written here as it unfolds.", "done": "Quests you complete are sealed here."}.get(filter,
		"Nothing of this kind yet. Talk to people in Brickton and beyond; some of them need help."))


func _relabel_quests() -> void:
	for i in list_ids.size():
		var id: String = list_ids[i]
		var st := quests.status(id)
		var mark: String = {"active": "", "available": "New:  ", "declined": "Declined:  ", "locked": "Later:  ", "completed": ""}.get(st, "")
		list.set_item_text(i, mark + quests.defs[id].title + ("   ✦ tracked" if quests.tracked == id else ""))


func _show_quest(id: String) -> void:
	var d: Dictionary = quests.defs[id]
	var st := quests.status(id)
	var t := "[color=%s]%s  ·  %s  ·  %s[/color]\n\n" % [SOFT_HEX, {"main": "Main Story", "side": "Side Quest", "special": "Special Quest", "contract": "Monster Contract"}.get(d.get("type", "side"), ""),
		d.get("region", ""), {"active": "In progress", "available": "Not yet begun", "declined": "Declined", "locked": "Not yet open", "completed": "Completed"}.get(st, st)]
	t += d.get("description", "") + "\n\n"
	if d.has("giver"):
		t += "[color=%s][b]Given by[/b][/color]  %s%s\n\n" % [SOFT_HEX, _npc_name(d.giver), _npc_where(d.giver)]
	if st == "locked":
		var need := []
		for r in d.get("requires", []):
			if not quests.is_done(r):
				need.append(quests.defs[r].title)
		t += "[i]Opens after: %s[/i]\n\n" % ", ".join(need)
	if st == "available":
		if d.has("giver"):
			t += "[i]Talk to %s to begin.[/i]\n\n" % _npc_name(d.giver)
		elif d.has("trigger"):
			t += "[i]Something in %s will set you on this trail.[/i]\n\n" % d.get("region", "the world")
	if st == "declined":
		t += "[i]You turned this down. Reconsider below, or talk to %s again.[/i]\n\n" % _npc_name(d.giver) if d.has("giver") else "[i]You turned this down. You can reconsider below.[/i]\n\n"
	if id == "island_heart" and st == "active":
		t += "[b]Objectives[/b]\n" + quests.story.original_tracker() + "\n"
	if quests.q.has(id) and st != "declined" and d.has("steps"):
		t += "[b]Objectives[/b]\n"
		var cur: int = quests.q[id].step
		for si in d.steps.size():
			var step: Dictionary = d.steps[si]
			if si < cur or st == "completed":
				t += "[color=%s]✔  %s[/color]\n" % [DONE_HEX, quests.step_text(step)]
			elif si == cur:
				var goals := Quests.goals_of(step)
				if goals.size() > 1:
					t += "○  %s\n" % quests.step_text(step)
				for gi in goals.size():
					var g: Dictionary = goals[gi]
					var done := quests.goal_done(id, gi)
					var need := quests._need(g)
					var have := state.count(g.item) if g.type == "have" else quests.progress(id, gi)
					var prog := " (%d/%d)" % [mini(have, need), need] if need > 1 else ""
					t += ("      " if goals.size() > 1 else "") + ("[color=%s]✔  " % DONE_HEX if done else "○  ") + quests.goal_text(g) + prog + ("[/color]" if done else "") + "\n"
				break
	var r := quests.reward_text(id)
	if r != "":
		t += "\n[b]Rewards[/b]\n%s%s\n" % [r, "  [color=%s](received)[/color]" % DONE_HEX if st == "completed" else ""]
	_detail(d.title, t, st == "completed")
	action_btn.visible = st == "active" and quests.tracked != id or st == "declined"
	action_btn.text = "Reconsider and accept" if st == "declined" else "Track this quest"
	action_btn.icon = UiTheme.icon("pin")


func _npc_name(id: String) -> String:
	if quests.story.by_id.has(id):
		return quests.story.by_id[id].display_name
	return id.capitalize()


func _npc_where(id: String) -> String:
	if not quests.story.by_id.has(id) or data == null:
		return ""
	var home: Vector3 = quests.story.by_id[id].home
	return ", %s" % WorldData.ZONE_NAMES[data.dominant_zone(home.x, home.z)]


# ---------- People ----------

func _fill_people() -> void:
	_begin("People", [], "", Callable())
	var givers := {}
	for qid in quests.defs:
		var d: Dictionary = quests.defs[qid]
		if d.has("giver") and quests.status(qid) in ["active", "completed"]:
			givers[d.giver] = true
	var people := []
	for v in quests.story.villagers:
		if state.has_flag("met:" + v.id) or givers.has(v.id):
			people.append(v)
	people.sort_custom(func(a, b): return a.display_name < b.display_name)
	for v in people:
		_add(v.id, v.display_name, "person", UiTheme.INK_SOFT)
	_finish("No one yet", "person", "The people you meet and talk to will be remembered here.")


func _show_person(id: String) -> void:
	var v: Villager = quests.story.by_id.get(id)
	if v == null:
		return
	var role: String = {"quest_giver": "Asks for help", "smith": "Blacksmith", "merchant": "Merchant", "bartender": "Tavern keeper",
		"innkeeper": "Innkeeper", "captain": "Captain of the guard", "hunter": "Hunter", "guard": "Guard", "priest": "Priest",
		"monk": "Monk", "villager": "Townsperson"}.get(v.role, v.role.capitalize())
	var t := "[color=%s]%s%s[/color]\n\n" % [SOFT_HEX, role, _npc_where(id)]
	var said: Array = v.cfg.get("lines", {}).get("default", [])
	if not said.is_empty():
		t += "[i]“%s”[/i]\n\n" % said[0]
	var theirs := []
	for qid in quests.defs:
		var d: Dictionary = quests.defs[qid]
		if d.get("giver", "") == id and quests.status(qid) in ["active", "completed", "available"]:
			theirs.append("%s  [color=%s](%s)[/color]" % [d.title, SOFT_HEX, {"active": "in progress", "completed": "done", "available": "they need help"}[quests.status(qid)]])
	if not theirs.is_empty():
		t += "[b]Quests[/b]\n• " + "\n• ".join(theirs) + "\n"
	_detail(v.display_name, t, false)


# ---------- Discoveries ----------

func _fill_discoveries() -> void:
	_begin("Discoveries", [], "", Callable())
	_add("progress", "Your journey so far", "compass", Color(0.55, 0.3, 0.05))
	for d in features.cfg.discoveries:
		if state.has_flag("disc:" + d.id):
			_add(["disc", d], d.name, _place_icon(d.name))
	for s in features.cfg.shrines:
		if state.has_flag("shrine:" + s.id):
			_add(["shrine", s], s.name, "shrine")
	for x in features.cfg.treasures:
		if state.has_flag("treasure:" + x.id):
			_add(["treasure", x], x.get("name", "Hidden treasure"), "treasure")
	for b in features.cfg.rare_bosses:
		if state.has_flag("boss:" + b.id):
			_add(["boss", b], b.get("title", b.get("name", b.id.capitalize())), "boss", Color(0.45, 0.1, 0.08))
	_finish("", "discovery", "")


## Icon for a place from what it is called.
static func _place_icon(name: String) -> String:
	var n := name.to_lower()
	for k in ["grotto", "sinkhole", "vault", "cave"]:
		if k in n:
			return "cave"
	for k in ["ruins", "temple", "forge", "mill", "lodge", "hut", "camp", "sanctuary"]:
		if k in n:
			return "landmark"
	if "square" in n or "market" in n:
		return "town"
	return "discovery"


func _show_discovery(e: Variant) -> void:
	if e is String:
		_detail("Your journey so far", _progress_text(), false)
		return
	var kind: String = e[0]
	var d: Dictionary = e[1]
	var where := ""
	if d.has("pos") and data:
		where = WorldData.ZONE_NAMES[data.dominant_zone(float(d.pos[0]), float(d.pos[1]))]
	var t := "[color=%s]%s%s[/color]\n\n" % [SOFT_HEX, {"disc": "Place", "shrine": "Shrine (awakened)", "treasure": "Treasure (found)", "boss": "Rare beast (defeated)"}[kind],
		("  ·  " + where) if where != "" else ""]
	for l in d.get("lines", []):
		t += "[i]%s[/i]\n\n" % l
	if kind == "shrine" and d.has("hint"):
		t += "[i]%s[/i]\n" % d.hint
	_detail(d.get("name", d.get("title", "")), t, kind == "boss")


func _progress_text() -> String:
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
	var t := "Quests completed:  [b]%d[/b] / %d\nPlaces discovered:  [b]%d[/b] / %d\nShrines awakened:  [b]%d[/b] / %d\nTreasures found:  [b]%d[/b] / %d\nRare beasts slain:  [b]%d[/b] / %d\nContracts fulfilled:  [b]%d[/b]\n\n" % [
		qd, qt, d_found, d_total, sh, features.cfg.shrines.size(), tr, features.cfg.treasures.size(), rb, features.cfg.rare_bosses.size(), _contracts_done()]
	t += "[b]Deeds[/b]\n"
	var ach := [
		["Heart of the Island", quests.is_done("island_heart")], ["The Shattered Island", quests.is_done("awakening")],
		["Cartographer (all places)", d_found == d_total], ["Pilgrim (all shrines)", sh == features.cfg.shrines.size()],
		["Treasure Hunter (all treasure)", tr == features.cfg.treasures.size()], ["Titan Slayer (all rare beasts)", rb == features.cfg.rare_bosses.size()],
		["Defender of Brickton", quests.is_done("night_beasts")], ["Heir of Caldor", quests.is_done("forgotten_kingdom")]]
	for a in ach:
		t += ("[color=%s]✔  " % DONE_HEX if a[1] else "○  ") + a[0] + ("[/color]" if a[1] else "") + "\n"
	return t


func _contracts_done() -> int:
	var n := 0
	for id in quests.q:
		if quests.defs.get(id, {}).get("type") == "contract" and quests.q[id].state == "completed":
			n += 1
	return n


# ---------- Lore and notes ----------

func _fill_notes(kind: String) -> void:
	_begin("Lore" if kind == "lore" else "Notes", [], "", Callable())
	for n in state.flags.get("journal_notes", []):
		if n.get("kind", "") == kind:
			_add(n, n.get("title", ""), "lore" if kind == "lore" else "note")
	if kind == "lore":
		_finish("Nothing read yet", "lore", "Inscriptions, carvings and old writings you read are copied here: look for them in the church and on the island's ancient stones.")
	else:
		_finish("Nothing noted yet", "note", "Rumours you hear (the tavern keeper always has one) are written down here.")


# ---------- Inventory ----------

func _fill_inventory() -> void:
	_begin("Inventory", ITEM_FILTERS + [["sort", "Sort: name" if sort_by_name else "Sort: kind"]], item_filter, func(k: String) -> void:
		if k == "sort":
			sort_by_name = not sort_by_name
		else:
			item_filter = k
		_fill_inventory())
	var ids := ["iron_sword"] + state.items.keys()
	var kinds := ["weapon", "armor", "potion", "key", "quest", "material", "collectible", "trophy"]
	if sort_by_name:
		ids.sort_custom(func(a, b): return state.item_name(a) < state.item_name(b))
	else:
		ids.sort_custom(func(a, b): return kinds.find(state.item(a).kind) < kinds.find(state.item(b).kind) or (kinds.find(state.item(a).kind) == kinds.find(state.item(b).kind) and a < b))
	for id in ids:
		var it := state.item(id)
		var k: String = it.kind
		var group := "valuable" if k in ["collectible", "trophy"] else ("quest" if k in ["quest", "key"] else k)
		if item_filter != "all" and group != item_filter:
			continue
		var n := 1 if id == "iron_sword" else state.count(id)
		var eq: bool = (id == state.weapon or id == state.armor)
		_add(id, it.name + (" ×%d" % n if n > 1 else "") + ("   ✦ equipped" if eq else ""), KIND_ICON.get(k, "collectible"),
			Color(0.55, 0.3, 0.05) if eq else UiTheme.INK_SOFT)
	_finish("Nothing here", "armor", "No items of this kind in your bag.")
	_update_portrait()


func _show_item(id: String) -> void:
	var it := state.item(id)
	var eq: bool = (id == state.weapon or id == state.armor)
	var t := "[color=%s]%s%s[/color]\n\n%s\n" % [SOFT_HEX, it.kind.capitalize(), "  ·  equipped" if eq else "", it.get("desc", "")]
	if it.kind == "weapon":
		t += "\n[b]Damage[/b]  ×%.2f" % float(it.get("damage", 1.0))
	if it.kind == "armor":
		t += "\n[b]Damage taken[/b]  ×%.2f" % float(it.get("armor", 1.0))
		if it.has("frost"):
			t += "     [b]Frost[/b]  ×%.2f" % float(it.frost)
		if it.has("fire"):
			t += "     [b]Fire[/b]  ×%.2f" % float(it.fire)
	t += "\n\n[color=%s]─────────────[/color]\n[b]%s[/b]   Level %d   ·   XP %d / %d\nCoins %d   ·   Reputation %d   ·   Health %d\nSword ×%.2f   ·   Weapon: %s   ·   Armour: %s" % [
		SOFT_HEX, "The Explorer", state.level, state.xp, state.xp_for_next(), state.coins, state.reputation, int(player.max_health), state.sword_damage_mult(),
		state.item_name(state.weapon), state.item_name(state.armor) if state.armor != "" else "none"]
	_detail(it.name, t, false)
	portrait.visible = player != null and player.is_inside_tree()
	action_btn.visible = it.kind in ["weapon", "armor"] and not eq
	action_btn.text = "Equip"
	action_btn.icon = UiTheme.icon(KIND_ICON.get(it.kind, "armor"))


## Points the portrait camera at the explorer's front.
func _update_portrait() -> void:
	if player == null or not player.is_inside_tree():
		return
	var sv: SubViewport = portrait.get_child(0)
	sv.world_3d = player.get_world_3d()
	var yaw: float = player.body.rotation.y
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var at := player.global_position + Vector3(0, 1.0, 0)
	portrait_cam.global_position = at + fwd * 2.6 + Vector3(0, 0.25, 0)
	portrait_cam.look_at(at, Vector3.UP)


# ---------- Map ----------

func _build_map() -> void:
	var v := VBoxContainer.new()
	map_page.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var t := UiTheme.label("Map of the Island", 34, UiTheme.INK, UiTheme.title_font())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var hint := UiTheme.label("Drag to move, wheel or buttons to zoom", 18, UiTheme.INK_SOFT, UiTheme.italic_font())
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hint)
	for z in [["−", -1], ["+", 1], ["Centre", 0]]:
		var dir: int = z[1]
		head.add_child(UiTheme.button(z[0], "", func() -> void:
			if dir == 0:
				map_zoom = 1.0
				map_pan = Vector2.ZERO
			else:
				_zoom_at(map_view.size * 0.5, 1.35 if dir > 0 else 1.0 / 1.35)
			map_view.queue_redraw(), Vector2(64 if dir != 0 else 120, 50)))
	map_view = Control.new()
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.clip_contents = true
	map_view.draw.connect(_draw_map)
	map_view.gui_input.connect(_map_input)
	v.add_child(map_view)


func _map_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = e.pressed
		elif e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(e.position, 1.15 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
	elif e is InputEventMouseMotion and _dragging:
		map_pan += e.relative
	elif e is InputEventScreenDrag:
		map_pan += e.relative
	elif e is InputEventMagnifyGesture:
		_zoom_at(e.position, e.factor)
	else:
		return
	map_view.queue_redraw()


func _zoom_at(at: Vector2, f: float) -> void:
	var nz := clampf(map_zoom * f, 1.0, 5.0)
	var base := _map_xf()
	var world: Vector2 = (at - base[0]) / base[1]
	map_zoom = nz
	var after := _map_xf()
	map_pan += at - (after[0] + world * float(after[1]))


## A sepia, hand-drawn-looking map made from the real terrain: region tints,
## hill shading, contour lines every 15 m, lava in red ink, roads and paths.
func _make_map() -> Texture2D:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var cols := [Color(0.80, 0.76, 0.56), Color(0.92, 0.91, 0.86), Color(0.66, 0.50, 0.38), Color(0.66, 0.62, 0.70), Color(0.82, 0.71, 0.55)]
	for j in n:
		for i in n:
			var x := -512.0 + i * 4.0
			var z := -512.0 + j * 4.0
			var w := data.zone(x, z)
			var c := Color(0, 0, 0)
			for k in 5:
				c += cols[k] * float(w[k])
			var h := data.height(x, z)
			var shade := clampf(0.92 + (h - data.height(x - 4.0, z - 4.0)) * 0.05, 0.7, 1.12)
			c = c * shade
			if int(h / 15.0) != int(data.height(x + 4.0, z) / 15.0) or int(h / 15.0) != int(data.height(x, z + 4.0) / 15.0):
				c = c.lerp(Color(0.45, 0.32, 0.18), 0.35)   # contour line
			if h < WorldData.LAVA_LEVEL + 0.05 and float(w[2]) > 0.3:
				c = Color(0.72, 0.24, 0.1)
			if data.is_water(x, z):
				c = Color(0.42, 0.58, 0.62).lerp(Color(0.85, 0.9, 0.92), float(w[1]) * 0.8)   # ice in Frost Peaks
			elif data.on_path(x, z) > 0.5:
				c = c.lerp(Color(0.38, 0.25, 0.12), 0.55)
			img.set_pixel(i, j, c)
	return ImageTexture.create_from_image(img)


func _map_xf() -> Array:
	var size := map_view.size
	var s := minf(size.x, size.y) * map_zoom
	var off := (size - Vector2(s, s)) * 0.5 + map_pan
	return [off, s / 1024.0]


func _to_map(p: Vector2) -> Vector2:
	var xf := _map_xf()
	return xf[0] + (p + Vector2(512, 512)) * xf[1]


func _draw_map() -> void:
	if not visible or features == null or map_tex == null:
		return
	var xf := _map_xf()
	map_view.draw_texture_rect(map_tex, Rect2(xf[0], Vector2(1024, 1024) * xf[1]), false, Color(1, 1, 1, 0.92))
	var font := UiTheme.title_font()
	var body := UiTheme.body_font()
	var ink := Color(0.24, 0.15, 0.07)
	for zi in 5:
		var centres := [Vector2(0, 0), Vector2(0, -300), Vector2(300, 0), Vector2(0, 300), Vector2(-300, 0)]
		var zp := _to_map(centres[zi]) + Vector2(-90, -40)
		map_view.draw_string(font, zp, WorldData.ZONE_NAMES[zi].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 180, 22, Color(ink, 0.55))
	for pt in features.map_points():
		var mp := _to_map(pt[1])
		var known: bool = pt[2]
		var kind := "shrine" if features.cfg.shrines.any(func(s): return s.name == pt[0]) else _place_icon(pt[0])
		if known:
			_map_icon(kind, mp, 24.0, ink)
			map_view.draw_string_outline(body, mp + Vector2(15, 6), pt[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0.93, 0.87, 0.72, 0.8))
			map_view.draw_string(body, mp + Vector2(15, 6), pt[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ink)
		else:
			map_view.draw_circle(mp, 9.0, Color(ink, 0.18))
			map_view.draw_string(font, mp + Vector2(-5, 7), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(ink, 0.55))
	# People with something for you, and the tracked objective.
	for v in quests.story.villagers:
		var m := quests.marker_for(v)
		if m != "":
			var mp2 := _to_map(Vector2(v.global_position.x, v.global_position.z))
			map_view.draw_string_outline(font, mp2 + Vector2(-6, 9), m, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 5, Color(0.2, 0.1, 0.02, 0.9))
			map_view.draw_string(font, mp2 + Vector2(-6, 9), m, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1.0, 0.8, 0.25) if m == "!" else Color(0.55, 0.85, 1.0))
	var obj := quests.objective_position()
	if obj != Vector3.INF:
		_map_icon("pin", _to_map(Vector2(obj.x, obj.z)) - Vector2(0, 12), 30.0, Color(0.62, 0.14, 0.08))
	var pp := _to_map(Vector2(player.global_position.x, player.global_position.z))
	var fwd := Vector2(sin(player.body.rotation.y), cos(player.body.rotation.y))
	var tri := PackedVector2Array([pp + fwd * 15.0, pp + fwd.orthogonal() * 9.0 - fwd * 8.0, pp - fwd.orthogonal() * 9.0 - fwd * 8.0])
	map_view.draw_colored_polygon(tri, Color(0.7, 0.1, 0.06))
	map_view.draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0.2, 0.05, 0.02), 2.0)
	_map_icon("compass", Vector2(map_view.size.x - 60, map_view.size.y - 60), 80.0, Color(ink, 0.5))
	map_view.draw_string(font, Vector2(map_view.size.x - 66, map_view.size.y - 106), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.7))


func _map_icon(name: String, at: Vector2, size: float, tint: Color) -> void:
	var t := UiTheme.icon(name)
	if t:
		map_view.draw_texture_rect(t, Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), false, tint)

class_name GameMenu
extends CanvasLayer
## Title screen, pause menu and settings, styled with UiTheme. Runs while the
## game is paused. The title sits over the live island (the camera drifts
## slowly); the pause screen shows where you are and the time of day.
## Buttons are big enough to tap on a phone.

## Start a new adventure in a new save slot with this name.
signal new_game(slot_name: String)
signal continue_game
## Load this save slot.
signal load_slot(id: String)
## Pause menu "Save Game".
signal save_now
signal resumed
signal save_and_quit
signal settings_changed(settings: Dictionary)
## Pause menu: open the journal on a section ("quests", "inventory", "map").
signal open_journal(section: String)
signal quit_game
## A slot was renamed on the Load screen (the world updates the name it saves under).
signal slot_renamed(id: String, slot_name: String)

var settings: Dictionary
var root: Control
var title_box: Control
var pause_box: Control
var settings_box: Control
var confirm_box: Control
var slots_box: Control
var slots_list: VBoxContainer
var load_btns: Array[Button] = []
## The slot being played (marked on the Load screen; can't be deleted mid-game).
var current_slot := ""
var continue_btn: Button
var pause_info: Label
var pause_saved: Label
var back_to := "title"
var showing := ""
var drift_cam: Camera3D
var drift_t := 0.0
var _prev_cam: Camera3D

## The settings screen edits this copy; Apply sends it, Cancel drops it.
var draft: Dictionary = {}
var settings_tabs: TabContainer
var _sync_fns: Array[Callable] = []
var apply_btn: Button

const QUALITY_NAMES := {"battery": "Battery saver", "balanced": "Balanced", "sharp": "Sharp"}
const QUALITY_ORDER := ["battery", "balanced", "sharp"]
const SHADOW_ORDER := ["off", "low", "high"]
const VIEW_ORDER := ["near", "normal", "far"]
const AA_ORDER := ["off", "fxaa", "msaa"]
const LAPTOP_ORDER := ["auto", "on", "off"]
const WINDOW_SIZES := ["1280x720", "1600x900", "1920x1080", "2560x1440"]


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	add_child(root)
	_build_title()
	_build_pause()
	_build_settings()
	_build_slots()
	_build_confirm()
	visible = false


# ---------- Title ----------

func _build_title() -> void:
	title_box = Control.new()
	title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_box)
	# A dark veil on the left so the title reads over the island behind it.
	var veil := TextureRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.02, 0.015, 0.92))
	g.set_color(1, Color(0.03, 0.02, 0.015, 0.0))
	g.add_point(0.45, Color(0.03, 0.02, 0.015, 0.7))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	veil.texture = gt
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	title_box.add_child(veil)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 90
	col.offset_right = 610
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	title_box.add_child(col)
	var title := UiTheme.label("OPENWORLD", 104, UiTheme.GOLD_BRIGHT, UiTheme.title_font())
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	title.add_theme_constant_override("outline_size", 12)
	col.add_child(title)
	var sub := UiTheme.label("The Island's Heart", 34, UiTheme.CREAM, UiTheme.italic_font())
	col.add_child(sub)
	var rule := TextureRect.new()
	rule.texture = UiTheme.tex("divider")
	rule.custom_minimum_size = Vector2(520, 18)
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_SCALE
	col.add_child(rule)
	col.add_child(_spacer(18))
	continue_btn = _menu_button("Continue", "continue", func() -> void: continue_game.emit())
	col.add_child(continue_btn)
	col.add_child(_menu_button("New Game", "compass", _ask_new_game))
	var load_title := _menu_button("Load Game", "book", func() -> void: _open_slots("title"))
	load_btns.append(load_title)
	col.add_child(load_title)
	col.add_child(_menu_button("Settings", "gear", func() -> void: _open_settings("title")))
	col.add_child(_menu_button("Quit", "quit", func() -> void: quit_game.emit()))


## New Game asks for a name, then starts in a fresh slot: other adventures stay as they are.
func _ask_new_game() -> void:
	_ask_name("A New Adventure", "Name this adventure. Your other saves stay as they are.", SaveGame.next_name(), "Begin",
		func(n: String) -> void: new_game.emit(n))


# ---------- Pause ----------

func _build_pause() -> void:
	pause_box = Control.new()
	pause_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(pause_box)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.55)
	pause_box.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 0)
	pause_box.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiTheme.heading("Paused", 52))
	pause_info = UiTheme.label("", 22, UiTheme.CREAM_DIM, UiTheme.italic_font())
	pause_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(pause_info)
	col.add_child(_spacer(6))
	col.add_child(_menu_button("Continue", "continue", func() -> void: resumed.emit(), 500))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for e in [["Journal", "book", "quests"], ["Inventory", "armor", "inventory"], ["Map", "map", "map"]]:
		var key: String = e[2]
		var b := _tile(e[0], e[1], func() -> void: open_journal.emit(key))
		grid.add_child(b)
	col.add_child(grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var save_b := _menu_button("Save Game", "save", func() -> void:
		save_now.emit()
		pause_saved.text = "Game saved"
		UiTheme.reveal(pause_saved), 245)
	var load_b := _menu_button("Load Game", "book", func() -> void: _open_slots("pause"), 245)
	load_btns.append(load_b)
	row.add_child(save_b)
	row.add_child(load_b)
	col.add_child(row)
	col.add_child(_menu_button("Settings", "gear", func() -> void: _open_settings("pause"), 500))
	col.add_child(_menu_button("Save and Main Menu", "quit", func() -> void: save_and_quit.emit(), 500))
	pause_saved = UiTheme.label("", 19, UiTheme.GOOD, UiTheme.italic_font())
	pause_saved.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(pause_saved)


## A square button with a big icon over its label (pause menu shortcuts).
func _tile(text: String, icon_name: String, cb: Callable) -> Button:
	var b := UiTheme.button(text, icon_name, cb, Vector2(160, 118))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_constant_override("icon_max_width", UiTheme.px(46))
	b.add_theme_font_size_override("font_size", UiTheme.px(20))
	return b


# ---------- Settings ----------

func _build_settings() -> void:
	settings_box = Control.new()
	settings_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(settings_box)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.6)
	settings_box.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 70
	panel.offset_right = -70
	panel.offset_top = 36
	panel.offset_bottom = -36
	settings_box.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiTheme.heading("Settings", 44))
	settings_tabs = TabContainer.new()
	settings_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_tabs.tab_changed.connect(func(_i: int) -> void: UiTheme.sound(get_tree(), "ui_click", -14.0))
	col.add_child(settings_tabs)
	var desktop := not OS.has_feature("mobile")

	var p := _page("Display", "display")
	if desktop:
		_toggle(p, "Fullscreen", "fullscreen", "Fill the whole screen.")
		_choice(p, "Window size", "window_size", WINDOW_SIZES, WINDOW_SIZES, "Used when not in fullscreen.")
		_toggle(p, "VSync", "vsync", "Lock the frame rate to the screen to stop tearing.")
	_slider(p, "Brightness", "brightness", 0.7, 1.3, "Lift dark scenes or deepen them.", true)

	p = _page("Graphics", "graphics")
	_choice(p, "Quality", "quality", QUALITY_ORDER, QUALITY_ORDER.map(func(k: String) -> String: return QUALITY_NAMES[k]),
		"Battery saver: 30 fps and a softer image. Sharp: higher resolution, may run warmer.")
	_choice(p, "Shadows", "shadows", SHADOW_ORDER, ["Off", "Low", "High"], "Sun shadows. Low draws them only near you.")
	_slider(p, "Grass density", "foliage", 0.25, 1.0, "Thinner grass runs faster on phones.", true)
	_choice(p, "View distance", "view_distance", VIEW_ORDER, ["Near", "Normal", "Far"], "How far the camera draws the world.")
	if desktop:
		_choice(p, "Anti-aliasing", "aa", AA_ORDER, ["Off", "FXAA", "MSAA 2×"], "Smooths jagged edges.")
		_choice(p, "Laptop mode", "laptop_mode", LAPTOP_ORDER, ["Auto", "On", "Off"],
			"Lighter effects, shadows and plants so laptops run smoothly. Auto turns it on for built-in graphics. Takes effect when you restart the game.")

	p = _page("Audio", "audio")
	_slider(p, "Master volume", "master", 0.0, 1.0, "", true)
	_slider(p, "Music", "music", 0.0, 1.0, "", true)
	_slider(p, "Sound effects", "effects", 0.0, 1.0, "Combat, footsteps, menus.", true)
	_slider(p, "Environment", "ambience", 0.0, 1.0, "Wind, birds, crackling lava, the tavern's murmur.", true)

	p = _page("Gameplay", "sword")
	_slider(p, "Camera speed", "sensitivity", 0.4, 2.0, "How fast the camera turns with the mouse or your thumb.", false)
	_toggle(p, "Full HUD", "hud_full", "Off: only health, prompts and dialogue stay on screen.")
	_toggle(p, "Show FPS", "show_fps", "Frame-rate counter in the corner.")

	p = _page("Controls", "controls")
	_controls_reference(p)

	p = _page("Accessibility", "access")
	_slider(p, "Text size", "text_size", 0.85, 1.3, "Size of menu, journal and HUD text.", true)
	_toggle(p, "Reduced motion", "reduced_motion", "No fades or sliding in menus; the title camera holds still.")

	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 12)
	col.add_child(bar)
	var reset := UiTheme.button("Reset to defaults", "", func() -> void:
		draft = SaveGame.DEFAULT_SETTINGS.duplicate()
		_sync(), Vector2(260, 60))
	reset.add_theme_color_override("font_color", Color(0.95, 0.6, 0.5))
	bar.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	bar.add_child(UiTheme.button("Cancel", "", _cancel_settings, Vector2(180, 60)))
	apply_btn = UiTheme.button("Apply", "", _apply_settings, Vector2(180, 60))
	bar.add_child(apply_btn)


func _page(title: String, icon_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_tabs.add_child(scroll)
	settings_tabs.set_tab_icon(settings_tabs.get_tab_count() - 1, UiTheme.icon(icon_name))
	settings_tabs.set_tab_icon_max_width(settings_tabs.get_tab_count() - 1, UiTheme.px(26))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	scroll.add_child(v)
	return v


## One settings row: name and a short explanation on the left, the control on the right.
func _row(parent: Container, label: String, help: String, ctl: Control) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 76)
	row.add_theme_constant_override("separation", 20)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 0)
	left.add_child(UiTheme.label(label, 26, UiTheme.CREAM, UiTheme.title_font()))
	if help != "":
		var h := UiTheme.label(help, 19, UiTheme.CREAM_DIM, UiTheme.italic_font())
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(h)
	row.add_child(left)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ctl)
	parent.add_child(row)
	var line := ColorRect.new()
	line.color = Color(UiTheme.GOLD, 0.15)
	line.custom_minimum_size = Vector2(0, 1)
	parent.add_child(line)


func _toggle(parent: Container, label: String, key: String, help: String) -> void:
	var t := CheckButton.new()
	t.focus_mode = Control.FOCUS_NONE
	t.toggled.connect(func(on: bool) -> void:
		draft[key] = on
		_mark_dirty())
	_sync_fns.append(func() -> void: t.set_pressed_no_signal(bool(draft.get(key, false))))
	_row(parent, label, help, t)


func _choice(parent: Container, label: String, key: String, values: Array, names: Array, help: String) -> void:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Vector2(260, 58)
	for n in names:
		o.add_item(n)
	o.item_selected.connect(func(i: int) -> void:
		draft[key] = values[i]
		_mark_dirty())
	_sync_fns.append(func() -> void: o.select(maxi(0, values.find(draft.get(key, values[0])))))
	_row(parent, label, help, o)


func _slider(parent: Container, label: String, key: String, lo: float, hi: float, help: String, percent: bool) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.custom_minimum_size = Vector2(300, 44)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := UiTheme.label("", 22, UiTheme.GOLD_BRIGHT)
	val.custom_minimum_size = Vector2(76, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var show := func(v: float) -> void: val.text = ("%d%%" % roundi(v * 100.0)) if percent else ("×%.2f" % v)
	s.value_changed.connect(func(v: float) -> void:
		draft[key] = v
		show.call(v)
		_mark_dirty())
	_sync_fns.append(func() -> void:
		s.set_value_no_signal(float(draft.get(key, lo)))
		show.call(s.value))
	box.add_child(s)
	box.add_child(val)
	_row(parent, label, help, box)


## Read-only key and touch reference (remapping isn't supported yet).
func _controls_reference(parent: Container) -> void:
	var pc := [["Move", "Arrow keys"], ["Sprint", "W (or Shift)"], ["Walk slowly", "Ctrl"], ["Jump", "Space"],
		["Sword attack", "A (or left mouse)"], ["Shoot the shotgun", "S"], ["Defend (block)", "Hold D"],
		["Aim the shotgun", "Right mouse"], ["Dodge roll", "Q"], ["Interact, talk", "E"], ["Drink a potion", "H"],
		["Draw or put away the shotgun", "G"], ["Load shells", "R"], ["Whistle for your horse", "T"], ["Journal", "J"], ["Pause", "Esc / P"]]
	var touch := [["Move", "Left thumb stick"], ["Look", "Drag the right side"], ["Attack, block, dodge", "Bottom-right buttons"],
		["Interact", "Tap the prompt"], ["Journal, pause", "Top-right buttons"]]
	for group in [["Keyboard and mouse", pc], ["Touch", touch]]:
		var h := UiTheme.label(group[0], 26, UiTheme.GOLD_BRIGHT, UiTheme.title_font())
		parent.add_child(h)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 40)
		grid.add_theme_constant_override("v_separation", 6)
		for e in group[1]:
			grid.add_child(UiTheme.label(e[0], 22, UiTheme.CREAM))
			grid.add_child(UiTheme.label(e[1], 22, UiTheme.GOLD, UiTheme.bold_font()))
		parent.add_child(grid)
		parent.add_child(_spacer(12))


func _mark_dirty() -> void:
	apply_btn.disabled = draft == settings
	apply_btn.text = "Apply" if apply_btn.disabled else "Apply  •"


func _sync() -> void:
	for f in _sync_fns:
		f.call()
	_mark_dirty()


func _apply_settings() -> void:
	settings = draft.duplicate()
	settings_changed.emit(settings)
	_mark_dirty()


func _cancel_settings() -> void:
	draft = settings.duplicate()
	_show(back_to)


# ---------- Save slots ----------

func _build_slots() -> void:
	slots_box = Control.new()
	slots_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(slots_box)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.6)
	slots_box.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 160
	panel.offset_right = -160
	panel.offset_top = 36
	panel.offset_bottom = -36
	slots_box.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiTheme.heading("Your Adventures", 44))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	slots_list = VBoxContainer.new()
	slots_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_list.add_theme_constant_override("separation", 10)
	scroll.add_child(slots_list)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(bar)
	bar.add_child(UiTheme.button("Back", "", func() -> void: _show(back_to), Vector2(180, 60)))


func _open_slots(from: String) -> void:
	back_to = from
	_fill_slots()
	_show("slots")


## One card per adventure: name, level, region, time played, when saved; Load, Rename, Delete.
func _fill_slots() -> void:
	for c in slots_list.get_children():
		c.queue_free()
	var slots := SaveGame.list_slots()
	if slots.is_empty():
		var l := UiTheme.label("No saved adventures yet.", 24, UiTheme.CREAM_DIM, UiTheme.italic_font())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slots_list.add_child(l)
	for sl in slots:
		var id: String = sl.id
		var playing: bool = id == current_slot and back_to == "pause"
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.12, 0.09, 0.065, 0.9), Color(UiTheme.GOLD, 0.8 if playing else 0.35), 2 if playing else 1, 4))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		info.add_child(UiTheme.label(sl.name + ("   ·   playing now" if playing else ""), 28, UiTheme.GOLD_BRIGHT, UiTheme.title_font()))
		var bits := ["Level %d" % sl.level]
		if sl.region != "":
			bits.append(sl.region)
		bits.append(format_playtime(sl.playtime) + " played")
		info.add_child(UiTheme.label("   ·   ".join(bits), 21, UiTheme.CREAM))
		info.add_child(UiTheme.label("Saved " + format_date(sl.saved_at), 19, UiTheme.CREAM_DIM, UiTheme.italic_font()))
		var load_b := UiTheme.button("Load", "continue", func() -> void:
			if back_to == "pause" and id != current_slot:
				_confirm("Load this adventure?", "Your current adventure was saved when you paused; anything after that is kept too.", "Load", func() -> void: load_slot.emit(id))
			else:
				load_slot.emit(id), Vector2(150, 60))
		load_b.disabled = playing
		row.add_child(load_b)
		row.add_child(UiTheme.button("Rename", "", func() -> void:
			_ask_name("Rename Adventure", "", sl.name, "Rename", func(n: String) -> void:
				SaveGame.rename_slot(id, n)
				slot_renamed.emit(id, n)
				_fill_slots()), Vector2(150, 60)))
		var del := UiTheme.button("Delete", "", func() -> void:
			_confirm("Delete \"%s\"?" % sl.name, "This adventure will be gone for good. This cannot be undone.", "Delete", func() -> void:
				SaveGame.delete_slot(id)
				_fill_slots()), Vector2(150, 60))
		del.add_theme_color_override("font_color", Color(0.95, 0.6, 0.5))
		del.disabled = playing
		del.tooltip_text = "You can't delete the adventure you're playing." if playing else ""
		row.add_child(del)
		slots_list.add_child(card)


static func format_playtime(sec: float) -> String:
	var m := int(sec / 60.0)
	return "%dh %02dm" % [m / 60, m % 60] if m >= 60 else "%d min" % m


static func format_date(unix: float) -> String:
	if unix <= 0:
		return "some time ago"
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + int(Time.get_time_zone_from_system().bias) * 60)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %d, %02d:%02d" % [d.day, months[d.month - 1], d.year, d.hour, d.minute]


# ---------- Confirm ----------

func _build_confirm() -> void:
	confirm_box = Control.new()
	confirm_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(confirm_box)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	confirm_box.add_child(dim)
	confirm_box.visible = false


## A small yes/no dialog for things that can't be undone.
func _confirm(title: String, text: String, yes: String, on_yes: Callable) -> void:
	_dialog(title, text, yes, on_yes, null)


## Asks for a name (new adventure, rename); `on_ok` gets the text.
func _ask_name(title: String, text: String, start: String, ok: String, on_ok: Callable) -> void:
	var edit := LineEdit.new()
	edit.text = start
	edit.max_length = 32
	edit.custom_minimum_size = Vector2(0, 58)
	edit.select_all_on_focus = true
	edit.add_theme_font_size_override("font_size", 26)
	edit.add_theme_stylebox_override("normal", UiTheme.flat(Color(0.05, 0.04, 0.03, 0.9), Color(UiTheme.GOLD, 0.6), 1))
	edit.add_theme_stylebox_override("focus", UiTheme.flat(Color(0.05, 0.04, 0.03, 0.9), UiTheme.GOLD_BRIGHT, 2))
	edit.add_theme_color_override("font_color", UiTheme.CREAM)
	var go := func() -> void:
		if edit.text.strip_edges() != "":
			confirm_box.visible = false
			on_ok.call(edit.text.strip_edges())
	edit.text_submitted.connect(func(_t: String) -> void: go.call())
	_dialog(title, text, ok, go, edit)
	edit.call_deferred("grab_focus")


func _dialog(title: String, text: String, yes: String, on_yes: Callable, extra: Control) -> void:
	for c in confirm_box.get_children().slice(1):
		c.queue_free()
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(620, 0)
	confirm_box.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	col.add_child(UiTheme.heading(title, 34))
	var l := UiTheme.label(text, 24, UiTheme.CREAM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	if extra:
		col.add_child(extra)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	row.add_child(UiTheme.button("Cancel", "", func() -> void: confirm_box.visible = false, Vector2(220, 62)))
	var y := UiTheme.button(yes, "", func() -> void:
		if extra == null:
			confirm_box.visible = false
		on_yes.call(), Vector2(220, 62))
	if extra == null:   # yes/no questions here are destructive: red
		y.add_theme_color_override("font_color", Color(1.0, 0.65, 0.55))
		y.add_theme_stylebox_override("normal", UiTheme.flat(Color(0.3, 0.08, 0.06, 0.92), Color(UiTheme.DANGER, 0.9), 1))
	row.add_child(y)
	confirm_box.visible = true
	UiTheme.reveal(panel)


# ---------- Showing ----------

## Shows the title screen (Continue only if a save exists).
func show_title(has_save: bool, s: Dictionary) -> void:
	settings = s
	var slots := SaveGame.list_slots() if has_save else []
	continue_btn.visible = not slots.is_empty()
	if not slots.is_empty():
		continue_btn.text = "Continue  ·  %s" % slots[0].name
	for b in load_btns:
		b.disabled = slots.is_empty()
	_show("title")
	UiTheme.sound(get_tree(), "ui_open", -14.0)
	_start_drift()


## Shows the pause menu; `info` is e.g. "Brickton  ·  21:40", `saved` how
## the progress stands ("Progress saved").
func show_pause(s: Dictionary, info := "", saved := "") -> void:
	settings = s
	pause_info.text = info
	pause_info.visible = info != ""
	pause_saved.text = saved
	_show("pause")
	UiTheme.sound(get_tree(), "ui_open", -14.0)


func hide_menu() -> void:
	visible = false
	showing = ""
	confirm_box.visible = false
	_stop_drift()


func _open_settings(from: String) -> void:
	back_to = from
	draft = settings.duplicate()
	_sync()
	_show("settings")


func _show(which: String) -> void:
	visible = true
	showing = which
	title_box.visible = which == "title"
	pause_box.visible = which == "pause"
	settings_box.visible = which == "settings"
	slots_box.visible = which == "slots"
	var shown: Control = {"title": title_box, "pause": pause_box, "settings": settings_box, "slots": slots_box}.get(which)
	UiTheme.reveal(shown, 0.3 if which == "title" else 0.18)


## Esc steps back out of settings or a confirmation instead of resuming.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if confirm_box.visible:
		confirm_box.visible = false
		get_viewport().set_input_as_handled()
	elif showing == "settings":
		_cancel_settings()
		get_viewport().set_input_as_handled()
	elif showing == "slots":
		_show(back_to)
		get_viewport().set_input_as_handled()


# ---------- Title camera drift ----------

func _start_drift() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or UiTheme.reduced_motion or cam == drift_cam:
		return
	_prev_cam = cam
	if drift_cam == null:
		drift_cam = Camera3D.new()
		drift_cam.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(drift_cam)
	drift_cam.global_transform = cam.global_transform
	drift_cam.fov = cam.fov
	drift_cam.far = cam.far
	drift_cam.set_meta("base", cam.global_transform)
	drift_t = 0.0
	drift_cam.current = true


func _stop_drift() -> void:
	if drift_cam and drift_cam.current and _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.current = true


func _process(delta: float) -> void:
	if drift_cam == null or not drift_cam.current or showing != "title":
		return
	drift_t += delta
	var base: Transform3D = drift_cam.get_meta("base")
	# A slow look across the island, as if standing and taking it in.
	drift_cam.global_transform = base.rotated_local(Vector3.UP, sin(drift_t * 0.06) * 0.12) \
		.translated_local(Vector3(sin(drift_t * 0.04) * 1.5, 0.6, 0))


# ---------- Helpers ----------

func _menu_button(t: String, icon_name: String, cb: Callable, width := 420) -> Button:
	var b := UiTheme.button(t, icon_name, cb, Vector2(width, 70))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", UiTheme.px(28))
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

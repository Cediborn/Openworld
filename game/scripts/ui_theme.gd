class_name UiTheme
extends RefCounted
## Openworld's one visual identity for every menu, the journal and the HUD:
## the palette, the fonts (Cinzel for titles, Alegreya for reading; both OFL),
## the gold-framed dark panel, the parchment page, icons, menu sounds and
## the Godot Theme that styles buttons, tabs, sliders, lists and tooltips.
## Art comes from tools/make_ui_art.py; sounds from tools/audio/synth_ui.py.

const GOLD := Color(0.79, 0.64, 0.36)
const GOLD_BRIGHT := Color(0.97, 0.83, 0.52)
const BRONZE := Color(0.52, 0.4, 0.25)
const CHARCOAL := Color(0.075, 0.062, 0.05)
const BROWN := Color(0.15, 0.11, 0.075)
const CREAM := Color(0.95, 0.9, 0.79)       ## text on dark
const CREAM_DIM := Color(0.78, 0.72, 0.6)
const INK := Color(0.22, 0.14, 0.07)        ## text on parchment
const INK_SOFT := Color(0.42, 0.3, 0.17)
const DANGER := Color(0.74, 0.22, 0.17)
const GOOD := Color(0.45, 0.62, 0.3)

## Reduced-motion accessibility setting (applied by the world).
static var reduced_motion := false

static var _theme: Theme
static var _paper_theme: Theme
static var _cache := {}
static var _sound: AudioStreamPlayer


# ---------- Fonts and art ----------

static func title_font() -> Font:
	return _font("Cinzel", 600)


static func body_font() -> Font:
	return _font("Alegreya", 450)


static func bold_font() -> Font:
	return _font("Alegreya", 700)


static func italic_font() -> Font:
	return _font("Alegreya-Italic", 450)


static func _font(file: String, weight: int) -> Font:
	var key := "%s:%d" % [file, weight]
	if not _cache.has(key):
		var base: FontFile = load("res://assets/ui/fonts/%s.ttf" % file)
		var v := FontVariation.new()
		v.base_font = base
		v.variation_opentype = {"wght": weight}
		_cache[key] = v
	return _cache[key]


## A white icon from assets/ui/icons (tint it with modulate or a theme colour).
static func icon(name: String) -> Texture2D:
	var key := "icon:" + name
	if not _cache.has(key):
		var path := "res://assets/ui/icons/%s.svg" % name
		_cache[key] = load(path) if ResourceLoader.exists(path) else null
	return _cache[key]


static func tex(name: String) -> Texture2D:
	var key := "tex:" + name
	if not _cache.has(key):
		_cache[key] = load("res://assets/ui/%s.png" % name)
	return _cache[key]


## Dark panel with the double gold border and corner ornaments.
static func frame_box(margin := 26) -> StyleBoxTexture:
	var b := StyleBoxTexture.new()
	b.texture = tex("frame")
	b.set_texture_margin_all(30)
	b.set_content_margin_all(margin)
	return b


## A parchment page.
static func parchment_box(margin := 34) -> StyleBoxTexture:
	var b := StyleBoxTexture.new()
	b.texture = tex("parchment")
	b.set_texture_margin_all(44)
	b.set_content_margin_all(margin)
	return b


## Flat box with an optional thin gold border (small panels, bars, buttons).
static func flat(bg: Color, border := Color(0, 0, 0, 0), width := 0, radius := 3) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.content_margin_left = 16
	b.content_margin_right = 16
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	b.anti_aliasing = true
	return b


## Sizes are in the 1600x900 design space; the Text size setting scales the
## whole interface through the window's content scale instead.
static func px(size: float) -> int:
	return int(size)


# ---------- Theme ----------

## The shared theme for dark surfaces (menus, HUD, dialogue).
static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = px(24)

	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))

	for ty in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_font("font", ty, title_font())
		t.set_font_size("font_size", ty, px(22))
		t.set_color("font_color", ty, CREAM)
		t.set_color("font_hover_color", ty, GOLD_BRIGHT)
		t.set_color("font_pressed_color", ty, GOLD_BRIGHT)
		t.set_color("font_focus_color", ty, GOLD_BRIGHT)
		t.set_color("font_hover_pressed_color", ty, GOLD_BRIGHT)
		t.set_color("font_disabled_color", ty, Color(CREAM_DIM, 0.45))
		t.set_color("icon_normal_color", ty, GOLD)
		t.set_color("icon_hover_color", ty, GOLD_BRIGHT)
		t.set_color("icon_pressed_color", ty, GOLD_BRIGHT)
		t.set_color("icon_focus_color", ty, GOLD_BRIGHT)
		t.set_constant("h_separation", ty, 14)
		t.set_constant("icon_max_width", ty, px(30))
	var normal := flat(Color(0.12, 0.09, 0.065, 0.92), Color(GOLD, 0.45), 1)
	var hover := flat(Color(0.2, 0.15, 0.09, 0.95), GOLD_BRIGHT, 2)
	var pressed := flat(Color(0.3, 0.22, 0.12, 0.97), GOLD_BRIGHT, 2)
	var disabled := flat(Color(0.1, 0.08, 0.06, 0.6), Color(GOLD, 0.15), 1)
	var focus := flat(Color(0, 0, 0, 0), Color(GOLD_BRIGHT, 0.8), 2)
	for ty in ["Button", "OptionButton"]:
		t.set_stylebox("normal", ty, normal)
		t.set_stylebox("hover", ty, hover)
		t.set_stylebox("pressed", ty, pressed)
		t.set_stylebox("hover_pressed", ty, pressed)
		t.set_stylebox("disabled", ty, disabled)
		t.set_stylebox("focus", ty, focus)
	for ty in ["CheckBox", "CheckButton"]:
		var none := StyleBoxEmpty.new()
		none.set_content_margin_all(6)
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(s, ty, none)
		t.set_stylebox("focus", ty, focus)
	t.set_icon("checked", "CheckButton", _toggle(true))
	t.set_icon("unchecked", "CheckButton", _toggle(false))
	t.set_icon("arrow", "OptionButton", _arrow())

	t.set_stylebox("panel", "PanelContainer", frame_box())
	t.set_stylebox("panel", "PopupMenu", frame_box(14))
	t.set_font("font", "PopupMenu", body_font())
	t.set_font_size("font_size", "PopupMenu", px(24))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", GOLD_BRIGHT)
	t.set_stylebox("hover", "PopupMenu", flat(Color(GOLD, 0.18), Color(0, 0, 0, 0), 0, 2))
	t.set_constant("v_separation", "PopupMenu", 10)

	# Tabs: a gold rule under the chosen one.
	var tab_sel := flat(Color(0.18, 0.13, 0.08, 0.95))
	tab_sel.border_color = GOLD_BRIGHT
	tab_sel.border_width_bottom = 3
	var tab_off := flat(Color(0.1, 0.08, 0.06, 0.75))
	var tab_hover := flat(Color(0.16, 0.12, 0.08, 0.9))
	tab_hover.border_color = Color(GOLD, 0.6)
	tab_hover.border_width_bottom = 2
	for ty in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", ty, tab_sel)
		t.set_stylebox("tab_unselected", ty, tab_off)
		t.set_stylebox("tab_hovered", ty, tab_hover)
		t.set_stylebox("tab_focus", ty, StyleBoxEmpty.new())
		t.set_font("font", ty, title_font())
		t.set_font_size("font_size", ty, px(21))
		t.set_color("font_selected_color", ty, GOLD_BRIGHT)
		t.set_color("font_unselected_color", ty, CREAM_DIM)
		t.set_color("font_hovered_color", ty, CREAM)
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())

	# Sliders: dark groove, gold fill, a diamond grabber big enough for a thumb.
	var groove := flat(Color(0.05, 0.04, 0.03, 0.9), Color(GOLD, 0.4), 1, 2)
	groove.content_margin_top = 4
	groove.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", groove)
	var fill := flat(Color(GOLD, 0.85), Color(0, 0, 0, 0), 0, 2)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _diamond(GOLD))
	t.set_icon("grabber_highlight", "HSlider", _diamond(GOLD_BRIGHT))

	t.set_stylebox("background", "ProgressBar", flat(Color(0.05, 0.04, 0.03, 0.85), Color(GOLD, 0.5), 1, 2))
	t.set_stylebox("fill", "ProgressBar", flat(GOLD, Color(0, 0, 0, 0), 0, 2))

	for ty in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", ty, flat(Color(0, 0, 0, 0.18), Color(0, 0, 0, 0), 0, 4))
		t.set_stylebox("grabber", ty, flat(Color(BRONZE, 0.8), Color(0, 0, 0, 0), 0, 4))
		t.set_stylebox("grabber_highlight", ty, flat(GOLD, Color(0, 0, 0, 0), 0, 4))
		t.set_stylebox("grabber_pressed", ty, flat(GOLD_BRIGHT, Color(0, 0, 0, 0), 0, 4))

	t.set_stylebox("panel", "TooltipPanel", parchment_box(14))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", px(20))

	_rich(t, CREAM)
	_list(t, CREAM, CREAM_DIM)
	_theme = t
	_paper_theme = null
	return t


## Theme for content laid on parchment (journal pages): ink text, ink-gold
## selection. Set it on the page; everything else falls back to get_theme().
static func paper_theme() -> Theme:
	get_theme()
	if _paper_theme:
		return _paper_theme
	var t := Theme.new()
	t.set_color("font_color", "Label", INK)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0))
	_rich(t, INK)
	_list(t, INK, INK_SOFT)
	var b_normal := flat(Color(0.33, 0.22, 0.12, 0.12), Color(INK_SOFT, 0.55), 1)
	var b_hover := flat(Color(0.5, 0.33, 0.12, 0.2), Color(0.55, 0.36, 0.12), 2)
	var b_pressed := flat(Color(0.5, 0.33, 0.12, 0.3), Color(0.55, 0.36, 0.12), 2)
	t.set_stylebox("normal", "Button", b_normal)
	t.set_stylebox("hover", "Button", b_hover)
	t.set_stylebox("pressed", "Button", b_pressed)
	t.set_stylebox("hover_pressed", "Button", b_pressed)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color(0.45, 0.24, 0.05))
	t.set_color("font_pressed_color", "Button", Color(0.45, 0.24, 0.05))
	t.set_color("font_hover_pressed_color", "Button", Color(0.45, 0.24, 0.05))
	t.set_color("icon_normal_color", "Button", INK_SOFT)
	t.set_color("icon_hover_color", "Button", Color(0.45, 0.24, 0.05))
	t.set_color("icon_pressed_color", "Button", Color(0.45, 0.24, 0.05))
	for ty in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", ty, flat(Color(INK, 0.08), Color(0, 0, 0, 0), 0, 4))
		t.set_stylebox("grabber", ty, flat(Color(INK_SOFT, 0.55), Color(0, 0, 0, 0), 0, 4))
	_paper_theme = t
	return t


static func _rich(t: Theme, col: Color) -> void:
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", bold_font())
	t.set_font("italics_font", "RichTextLabel", italic_font())
	t.set_font_size("normal_font_size", "RichTextLabel", px(23))
	t.set_font_size("bold_font_size", "RichTextLabel", px(25))
	t.set_font_size("italics_font_size", "RichTextLabel", px(23))
	t.set_color("default_color", "RichTextLabel", col)
	t.set_constant("line_separation", "RichTextLabel", 3)


static func _list(t: Theme, col: Color, dim: Color) -> void:
	t.set_stylebox("panel", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var sel := flat(Color(GOLD, 0.22), Color(GOLD, 0.7), 1, 2)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_stylebox("hovered", "ItemList", flat(Color(GOLD, 0.1), Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("hovered_selected", "ItemList", sel)
	t.set_stylebox("hovered_selected_focus", "ItemList", sel)
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_font("font", "ItemList", body_font())
	t.set_font_size("font_size", "ItemList", px(23))
	t.set_color("font_color", "ItemList", col)
	t.set_color("font_hovered_color", "ItemList", col)
	t.set_color("font_selected_color", "ItemList", col)
	t.set_color("font_hovered_selected_color", "ItemList", col)
	t.set_constant("v_separation", "ItemList", 12)
	t.set_constant("h_separation", "ItemList", 12)
	t.set_constant("icon_margin", "ItemList", 10)
	t.set_color("guide_color", "ItemList", Color(dim, 0.0))


static func _diamond(c: Color) -> Texture2D:
	var s := px(30)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var h := s * 0.5
	for y in s:
		for x in s:
			var d := absf(x + 0.5 - h) + absf(y + 0.5 - h)
			if d < h - 1:
				var edge := d > h - 4
				img.set_pixel(x, y, Color(0.18, 0.12, 0.06) if edge else c)
	return ImageTexture.create_from_image(img)


## A pill-shaped switch: gold knob on the right when on.
static func _toggle(on: bool) -> Texture2D:
	var w := px(64)
	var h := px(32)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.5
	for y in h:
		for x in w:
			var cx := clampf(x + 0.5, r, w - r)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - r).length()
			if d < r:
				var c := Color(0.35, 0.25, 0.12) if on else Color(0.1, 0.08, 0.06)
				if d > r - 2.0:
					c = GOLD if on else Color(GOLD, 0.5)
				img.set_pixel(x, y, c)
			var kx := (w - r) if on else r
			if Vector2(x + 0.5 - kx, y + 0.5 - r).length() < r - 5.0:
				img.set_pixel(x, y, GOLD_BRIGHT if on else CREAM_DIM)
	return ImageTexture.create_from_image(img)


static func _arrow() -> Texture2D:
	var s := px(18)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			if y > s * 0.3 and y < s * 0.75 and absf(x + 0.5 - s * 0.5) < (s * 0.75 - y) * 1.1:
				img.set_pixel(x, y, GOLD)
	return ImageTexture.create_from_image(img)


# ---------- Building blocks ----------

## A title or section heading with the ornamental rule beneath.
static func heading(text: String, size := 40, color := GOLD_BRIGHT) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", px(size))
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	var rule := TextureRect.new()
	rule.texture = tex("divider")
	rule.custom_minimum_size = Vector2(0, 16)
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	return box


## A themed button with an optional icon. Big enough to tap on a phone.
static func button(text: String, icon_name := "", cb := Callable(), min_size := Vector2(0, 64)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = false
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Small label in the given font colour.
static func label(text: String, size := 22, color := CREAM, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px(size))
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


# ---------- Motion and sound ----------

## Fades a control (and, unless reduced motion is on, lifts it slightly) into view.
static func reveal(c: CanvasItem, dur := 0.22) -> void:
	if c == null or not c.is_inside_tree():
		return
	if reduced_motion:
		c.modulate.a = 1.0
		return
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(c, "modulate:a", 1.0, dur)


## Plays a menu sound (works while the game is paused).
static func sound(tree: SceneTree, name: String, db := -8.0) -> void:
	if tree == null:
		return
	if _sound == null or not is_instance_valid(_sound):
		_sound = AudioStreamPlayer.new()
		_sound.process_mode = Node.PROCESS_MODE_ALWAYS
		_sound.bus = "Effects" if AudioServer.get_bus_index("Effects") != -1 else "Master"
		_sound.max_polyphony = 3
		tree.root.add_child(_sound)
	var path := "res://assets/audio/sfx/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return
	_sound.stream = load(path)
	_sound.volume_db = db
	_sound.play()


## Every Button added under `root` clicks when pressed (meta "silent" opts out).
static func click_sounds(root: Node) -> void:
	root.get_tree().node_added.connect(func(n: Node) -> void:
		if n is BaseButton and not n.has_meta("silent") and root.is_ancestor_of(n):
			n.pressed.connect(func() -> void: sound(n.get_tree(), "ui_click", -12.0)))

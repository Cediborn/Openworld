class_name GameMenu
extends CanvasLayer
## Title screen, pause menu and settings. Runs while the game is paused.
## Big buttons so they're easy to tap on a phone.

signal new_game
signal continue_game
signal resumed
signal save_and_quit
signal settings_changed(settings: Dictionary)

var settings: Dictionary
var root: Control
var title_box: VBoxContainer
var pause_box: VBoxContainer
var settings_box: VBoxContainer
var continue_btn: Button
var back_to := "title"
var quality_btn: Button
var fps_btn: Button
var music_slider: HSlider
var effects_slider: HSlider
var sens_slider: HSlider

const QUALITY_NAMES := {"battery": "Battery saver", "balanced": "Balanced", "sharp": "Sharp"}
const QUALITY_ORDER := ["battery", "balanced", "sharp"]


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.55)
	root.add_child(dim)

	title_box = _column()
	var title := _text("OPENWORLD", 96)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	title_box.add_child(title)
	title_box.add_child(_text("The Island's Heart", 34))
	title_box.add_child(_spacer(30))
	continue_btn = _button("Continue", func() -> void: continue_game.emit())
	title_box.add_child(continue_btn)
	title_box.add_child(_button("New game", func() -> void: new_game.emit()))
	title_box.add_child(_button("Settings", func() -> void: _open_settings("title")))

	pause_box = _column()
	pause_box.add_child(_text("Paused", 64))
	pause_box.add_child(_spacer(20))
	pause_box.add_child(_button("Resume", func() -> void: resumed.emit()))
	pause_box.add_child(_button("Settings", func() -> void: _open_settings("pause")))
	pause_box.add_child(_button("Save and quit", func() -> void: save_and_quit.emit()))

	settings_box = _column()
	settings_box.add_child(_text("Settings", 56))
	quality_btn = _button("", _cycle_quality)
	settings_box.add_child(quality_btn)
	music_slider = _slider(settings_box, "Music", "music")
	effects_slider = _slider(settings_box, "Sound effects", "effects")
	sens_slider = _slider(settings_box, "Camera speed", "sensitivity", 0.4, 2.0)
	fps_btn = _button("", func() -> void:
		settings.show_fps = not settings.show_fps
		_sync()
		settings_changed.emit(settings))
	settings_box.add_child(fps_btn)
	settings_box.add_child(_button("Back", func() -> void: _show(back_to)))
	visible = false


## Shows the title screen (Continue only if a save exists).
func show_title(has_save: bool, s: Dictionary) -> void:
	settings = s
	continue_btn.visible = has_save
	_show("title")


func show_pause(s: Dictionary) -> void:
	settings = s
	_show("pause")


func hide_menu() -> void:
	visible = false


func _open_settings(from: String) -> void:
	back_to = from
	_sync()
	_show("settings")


func _show(which: String) -> void:
	visible = true
	title_box.visible = which == "title"
	pause_box.visible = which == "pause"
	settings_box.visible = which == "settings"


func _sync() -> void:
	quality_btn.text = "Graphics: " + QUALITY_NAMES.get(settings.quality, "Balanced")
	fps_btn.text = "Show FPS: " + ("On" if settings.show_fps else "Off")
	music_slider.set_value_no_signal(settings.music)
	effects_slider.set_value_no_signal(settings.effects)
	sens_slider.set_value_no_signal(settings.sensitivity)


func _cycle_quality() -> void:
	var i := QUALITY_ORDER.find(settings.quality)
	settings.quality = QUALITY_ORDER[(i + 1) % QUALITY_ORDER.size()]
	_sync()
	settings_changed.emit(settings)


func _column() -> VBoxContainer:
	var c := VBoxContainer.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_theme_constant_override("separation", 14)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	c.custom_minimum_size = Vector2(520, 0)
	root.add_child(c)
	return c


func _text(t: String, size: int) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 10)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(480, 76)
	b.add_theme_font_size_override("font_size", 32)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", Hud._box(Color(0.12, 0.13, 0.16, 0.85), 16))
	b.add_theme_stylebox_override("hover", Hud._box(Color(0.22, 0.24, 0.3, 0.9), 16))
	b.add_theme_stylebox_override("pressed", Hud._box(Color(0.35, 0.3, 0.2, 0.95), 16))
	b.pressed.connect(cb)
	return b


func _slider(parent: Container, label: String, key: String, lo := 0.0, hi := 1.0) -> HSlider:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(480, 60)
	var l := _text(label, 26)
	l.custom_minimum_size = Vector2(220, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(240, 40)
	s.value_changed.connect(func(v: float) -> void:
		settings[key] = v
		settings_changed.emit(settings))
	row.add_child(s)
	parent.add_child(row)
	return s

class_name Hud
extends CanvasLayer
## On-screen game information: health bar, hurt flash, "defeated" screen,
## interact prompt, dialogue box, quest tracker and short notices.
## Touch players tap the prompt / dialogue box; PC players press E.

signal interact_pressed
signal dialogue_advanced
## A dialogue choice was picked (index into the choices shown).
signal choice_made(index: int)
## A big banner was shown (for sounds).
signal banner_shown(title: String)

var health_bar: ProgressBar
var health_label: Label
var hurt_rect: ColorRect
var defeated: Label
var prompt: Button
var dialogue: PanelContainer
var dlg_name: Label
var dlg_text: Label
var quest: Label
var notice: Label
var notice_time := 0.0
var hurt_amount := 0.0
var hurt_color := Color(0.8, 0.05, 0.05)
var notices: Array = []         # queued centre messages
var stats: RichTextLabel
var xp_bar: ProgressBar
var toasts: VBoxContainer
var boss_box: VBoxContainer
var boss_name: Label
var boss_bar: ProgressBar
var banner: Label
var banner_sub: Label
var banner_time := 0.0
var choice_box: VBoxContainer
var choice_buttons: Array = []
var hint: Label
var stat_bg: PanelContainer
var quest_box: VBoxContainer
var quest_caption: Label
var banner_rule: TextureRect
var dlg_rule: TextureRect
var letterbox: Array[ColorRect] = []
var _letterbox := 0.0
var full := true
var saving: Label
var objective_pos := Vector3.INF
var objective_text := ""
var marker: Control


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)

	hurt_rect = ColorRect.new()
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.8, 0.05, 0.05, 1.0);
uniform float amount = 0.0;
void fragment() {
	float edge = smoothstep(0.35, 0.95, length(UV - 0.5) * 1.6);
	COLOR = vec4(tint.rgb, edge * amount);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	hurt_rect.material = m
	root.add_child(hurt_rect)

	# Cinematic bars that slide in while someone is talking.
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.85)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = 0
		bar.offset_bottom = 0
		root.add_child(bar)
		letterbox.append(bar)

	# Health: heart, crimson bar in a thin gold frame, the number.
	var bar_bg := PanelContainer.new()
	bar_bg.position = Vector2(18, 72)
	bar_bg.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.05, 0.035, 0.025, 0.62), Color(UiTheme.GOLD, 0.45), 1, 4))
	root.add_child(bar_bg)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 10)
	bar_bg.add_child(bar_row)
	var heart := TextureRect.new()
	heart.texture = UiTheme.icon("heart")
	heart.custom_minimum_size = Vector2(26, 26)
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.modulate = Color(0.86, 0.25, 0.2)
	bar_row.add_child(heart)
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(260, 18)
	health_bar.show_percentage = false
	health_bar.add_theme_stylebox_override("background", UiTheme.flat(Color(0.12, 0.03, 0.02, 0.85), Color(UiTheme.GOLD, 0.55), 1, 2))
	health_bar.add_theme_stylebox_override("fill", UiTheme.flat(Color(0.7, 0.13, 0.1), Color(0, 0, 0, 0), 0, 2))
	health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(health_bar)
	health_label = _label(20)
	health_label.add_theme_font_override("font", UiTheme.title_font())
	bar_row.add_child(health_label)

	# Coins, level, potions with drawn icons; experience as a thin gold line.
	stat_bg = PanelContainer.new()
	stat_bg.position = Vector2(18, 116)
	stat_bg.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.05, 0.035, 0.025, 0.55), Color(UiTheme.GOLD, 0.3), 1, 4))
	root.add_child(stat_bg)
	var stat_col := VBoxContainer.new()
	stat_col.add_theme_constant_override("separation", 4)
	stat_bg.add_child(stat_col)
	stats = RichTextLabel.new()
	stats.bbcode_enabled = true
	stats.fit_content = true
	stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	stats.scroll_active = false
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_font_size_override("normal_font_size", 20)
	stats.add_theme_constant_override("outline_size", 5)
	stats.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	stat_col.add_child(stats)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(220, 5)
	xp_bar.show_percentage = false
	var xp_bg := UiTheme.flat(Color(0.05, 0.04, 0.03, 0.8), Color(0, 0, 0, 0), 0, 2)
	var xp_fill := UiTheme.flat(UiTheme.GOLD, Color(0, 0, 0, 0), 0, 2)
	for b in [xp_bg, xp_fill]:
		b.set_content_margin_all(0)   # a thin line, not a box
	xp_bar.add_theme_stylebox_override("background", xp_bg)
	xp_bar.add_theme_stylebox_override("fill", xp_fill)
	stat_col.add_child(xp_bar)

	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	toasts.position = Vector2(24, -330)
	toasts.size = Vector2(560, 150)
	toasts.alignment = BoxContainer.ALIGNMENT_END
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)

	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.position = Vector2(-330, 18)
	boss_box.size = Vector2(660, 60)
	boss_box.visible = false
	root.add_child(boss_box)
	boss_name = _label(28)
	boss_name.add_theme_font_override("font", UiTheme.title_font())
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	boss_box.add_child(boss_name)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(660, 14)
	boss_bar.show_percentage = false
	boss_bar.add_theme_stylebox_override("background", UiTheme.flat(Color(0.1, 0.03, 0.03, 0.85), Color(UiTheme.GOLD, 0.6), 1, 2))
	boss_bar.add_theme_stylebox_override("fill", UiTheme.flat(Color(0.6, 0.1, 0.08), Color(0, 0, 0, 0), 0, 2))
	boss_box.add_child(boss_bar)

	banner = _label(54)
	banner.add_theme_font_override("font", UiTheme.title_font())
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.position = Vector2(-600, 140)
	banner.size = Vector2(1200, 70)
	banner.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	banner.modulate.a = 0.0
	root.add_child(banner)
	banner_rule = TextureRect.new()
	banner_rule.texture = UiTheme.tex("divider")
	banner_rule.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_rule.position = Vector2(-260, 210)
	banner_rule.size = Vector2(520, 18)
	banner_rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner_rule.stretch_mode = TextureRect.STRETCH_SCALE
	banner_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_rule.modulate.a = 0.0
	root.add_child(banner_rule)
	banner_sub = _label(26)
	banner_sub.add_theme_font_override("font", UiTheme.italic_font())
	banner_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.position = Vector2(-500, 230)
	banner_sub.size = Vector2(1000, 40)
	banner_sub.modulate.a = 0.0
	root.add_child(banner_sub)

	marker = Control.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker.draw.connect(_draw_marker)
	root.add_child(marker)

	# Tracked quest, top right: a small gold caption over the objective.
	quest_box = VBoxContainer.new()
	quest_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quest_box.position = Vector2(-620, 100)
	quest_box.size = Vector2(590, 200)
	quest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_box.add_theme_constant_override("separation", 2)
	root.add_child(quest_box)
	quest_caption = _label(17)
	quest_caption.text = "CURRENT QUEST"
	quest_caption.add_theme_font_override("font", UiTheme.title_font())
	quest_caption.add_theme_color_override("font_color", UiTheme.GOLD)
	quest_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest_box.add_child(quest_caption)
	quest = _label(22)
	quest.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest.autowrap_mode = TextServer.AUTOWRAP_WORD
	quest.custom_minimum_size = Vector2(590, 0)
	quest_box.add_child(quest)

	notice = _label(34)
	notice.add_theme_font_override("font", UiTheme.title_font())
	notice.add_theme_color_override("font_color", UiTheme.CREAM)
	notice.set_anchors_preset(Control.PRESET_CENTER)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.position = Vector2(-500, -170)
	notice.size = Vector2(1000, 100)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD
	notice.modulate.a = 0.0
	root.add_child(notice)

	defeated = _label(70)
	defeated.add_theme_font_override("font", UiTheme.title_font())
	defeated.text = "You were defeated"
	defeated.set_anchors_preset(Control.PRESET_CENTER)
	defeated.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	defeated.position = Vector2(-500, -60)
	defeated.size = Vector2(1000, 120)
	defeated.add_theme_color_override("font_color", Color(0.86, 0.36, 0.3))
	defeated.visible = false
	root.add_child(defeated)

	prompt = Button.new()
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(-210, -250)
	prompt.size = Vector2(420, 66)
	prompt.add_theme_font_size_override("font_size", 24)
	prompt.add_theme_stylebox_override("normal", UiTheme.flat(Color(0.06, 0.045, 0.03, 0.78), Color(UiTheme.GOLD, 0.7), 1, 4))
	prompt.add_theme_stylebox_override("hover", UiTheme.flat(Color(0.14, 0.1, 0.06, 0.85), UiTheme.GOLD_BRIGHT, 2, 4))
	prompt.add_theme_stylebox_override("pressed", UiTheme.flat(Color(0.25, 0.18, 0.1, 0.9), UiTheme.GOLD_BRIGHT, 2, 4))
	prompt.focus_mode = Control.FOCUS_NONE
	prompt.visible = false
	prompt.set_meta("silent", true)
	prompt.pressed.connect(func() -> void: interact_pressed.emit())
	root.add_child(prompt)

	# Dialogue: a framed panel at the bottom; the speaker's name in gold over a rule.
	dialogue = PanelContainer.new()
	dialogue.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	# Pinned to the bottom edge and grows upwards, so extra choices never push
	# the last buttons off the bottom of the screen.
	dialogue.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialogue.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialogue.offset_left = -560
	dialogue.offset_right = 560
	dialogue.offset_bottom = -28
	dialogue.offset_top = -28 - 228
	dialogue.add_theme_stylebox_override("panel", UiTheme.frame_box(30))
	dialogue.visible = false
	dialogue.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed and not has_choices():
			dialogue_advanced.emit())
	root.add_child(dialogue)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	dialogue.add_child(col)
	dlg_name = _label(30)
	dlg_name.add_theme_font_override("font", UiTheme.title_font())
	dlg_name.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	col.add_child(dlg_name)
	dlg_rule = TextureRect.new()
	dlg_rule.texture = UiTheme.tex("divider")
	dlg_rule.custom_minimum_size = Vector2(360, 12)
	dlg_rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	dlg_rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dlg_rule.stretch_mode = TextureRect.STRETCH_SCALE
	col.add_child(dlg_rule)
	dlg_text = _label(27)
	dlg_text.add_theme_color_override("font_color", UiTheme.CREAM)
	dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	dlg_text.custom_minimum_size = Vector2(1050, 100)
	col.add_child(dlg_text)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 6)
	col.add_child(choice_box)
	for i in 4:
		var b := Button.new()
		b.add_theme_font_override("font", UiTheme.body_font())
		b.add_theme_font_size_override("font_size", 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 52)
		var idx := i
		b.pressed.connect(func() -> void: choice_made.emit(idx))
		choice_box.add_child(b)
		choice_buttons.append(b)
	hint = _label(18)
	hint.add_theme_font_override("font", UiTheme.italic_font())
	hint.text = "Tap or press E to continue"
	hint.modulate.a = 0.6
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(hint)


func _process(delta: float) -> void:
	if hurt_amount > 0.0:
		hurt_amount = maxf(0.0, hurt_amount - delta * 1.6)
	(hurt_rect.material as ShaderMaterial).set_shader_parameter("amount", hurt_amount)
	(hurt_rect.material as ShaderMaterial).set_shader_parameter("tint", hurt_color)
	if notice_time > 0.0:
		notice_time -= delta
		notice.modulate.a = clampf(minf(notice_time, 4.0 - notice_time) * 2.0, 0.0, 1.0)
	elif not notices.is_empty():
		notice.text = notices.pop_front()
		notice_time = 4.0
	if banner_time > 0.0:
		banner_time -= delta
		var a := clampf(minf(banner_time, 5.0 - banner_time) * 1.5, 0.0, 1.0)
		banner.modulate.a = a
		banner_sub.modulate.a = a
		banner_rule.modulate.a = a
	for t in toasts.get_children():
		var left: float = t.get_meta("left") - delta
		t.set_meta("left", left)
		t.modulate.a = clampf(left, 0.0, 1.0)
		if left <= 0.0:
			t.queue_free()
	marker.queue_redraw()
	var want := 1.0 if dialogue.visible else 0.0
	_letterbox = want if UiTheme.reduced_motion else move_toward(_letterbox, want, delta * 3.0)
	var bar_h := get_viewport().get_visible_rect().size.y * 0.07 * _letterbox
	letterbox[0].offset_bottom = bar_h
	letterbox[1].offset_top = -bar_h


## A small "Saving..." mark in the corner each time progress is written.
func show_saving() -> void:
	if saving == null:
		saving = _label(18)
		saving.add_theme_font_override("font", UiTheme.italic_font())
		saving.add_theme_color_override("font_color", UiTheme.GOLD)
		saving.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		saving.position = Vector2(-200, -48)
		saving.size = Vector2(180, 30)
		saving.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		saving.text = "Saving…"
		get_child(0).add_child(saving)
	saving.modulate.a = 1.0
	var tw := saving.create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(saving, "modulate:a", 0.0, 0.7)


## Full HUD setting: off keeps only health, prompts, dialogue and notices.
func set_full(on: bool) -> void:
	full = on
	stat_bg.visible = on
	quest_box.visible = on and quest.text != ""
	toasts.visible = on


## Updates the health bar.
func set_health(hp: float, max_hp: float) -> void:
	health_bar.max_value = max_hp
	health_bar.value = hp
	health_label.text = " %d" % ceili(hp)


## Red flash at the screen edges (orange for lava burns).
func flash_hurt(burn: bool) -> void:
	hurt_color = Color(1.0, 0.45, 0.05) if burn else Color(0.8, 0.05, 0.05)
	hurt_amount = 0.6 if burn else 0.9


func show_defeated(on: bool) -> void:
	defeated.visible = on


## Shows a short centred message for a few seconds (queued behind others).
func show_notice(text: String) -> void:
	if notice_time <= 0.0:
		notice.text = text
		notice_time = 4.0
	elif notices.size() < 6 and not text in notices and notice.text != text:
		notices.append(text)


## Small message in the corner ("+50 coins"), with an icon for its kind.
func toast(text: String, kind := "") -> void:
	var colors := {"coins": Color(1.0, 0.85, 0.35), "xp": Color(0.75, 0.85, 1.0), "level": Color(0.7, 1.0, 0.6),
		"item": UiTheme.CREAM, "rep": Color(0.95, 0.75, 1.0), "warn": Color(1.0, 0.55, 0.45), "quest": UiTheme.GOLD_BRIGHT}
	var icons := {"coins": "coin", "xp": "discovery", "level": "discovery", "item": "treasure", "rep": "person", "warn": "boss", "quest": "quest"}
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var ic := TextureRect.new()
	ic.texture = UiTheme.icon(icons.get(kind, "note"))
	ic.custom_minimum_size = Vector2(22, 22)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = colors.get(kind, UiTheme.CREAM)
	row.add_child(ic)
	var l := _label(22)
	l.text = text
	l.add_theme_color_override("font_color", colors.get(kind, UiTheme.CREAM))
	row.add_child(l)
	row.set_meta("left", 4.0)
	toasts.add_child(row)
	if not UiTheme.reduced_motion:
		row.position.x = -40.0
		var tw := row.create_tween()
		tw.tween_property(row, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	while toasts.get_child_count() > 6:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()


## Large title for discoveries and quest milestones.
func show_banner(title: String, sub := "") -> void:
	banner.text = title
	banner_sub.text = sub
	banner_time = 5.0
	banner_shown.emit(title)


func set_stats(coins: int, level: int, xp: int, xp_next: int, potions: int) -> void:
	stats.text = "[img=22x22 color=#e3c27a]res://assets/ui/icons/coin.svg[/img] %d     [font_size=18][color=#c9a35c]LEVEL[/color][/font_size] %d     [img=22x22 color=#d9534a]res://assets/ui/icons/potion.svg[/img] %d" % [coins, level, potions]
	xp_bar.max_value = xp_next
	xp_bar.value = xp


func show_boss(boss_title: String, frac: float) -> void:
	boss_box.visible = true
	boss_name.text = boss_title
	boss_bar.max_value = 1.0
	boss_bar.value = frac


func hide_boss() -> void:
	boss_box.visible = false


## Where the tracked objective is (Vector3.INF for none); drawn as an on-screen marker.
func set_objective(pos: Vector3, text := "") -> void:
	objective_pos = pos
	objective_text = text


func _draw_marker() -> void:
	if objective_pos == Vector3.INF or not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var size := marker.get_viewport_rect().size
	var p := objective_pos + Vector3.UP * 2.0
	var behind := cam.is_position_behind(p)
	var sp := cam.unproject_position(p)
	if behind:
		sp = size - sp
	var margin := 60.0
	var inside := not behind and sp.x > margin and sp.x < size.x - margin and sp.y > margin and sp.y < size.y - margin
	var d := cam.global_position.distance_to(objective_pos)
	var col := Color(1.0, 0.85, 0.3, 0.95)
	if not inside:
		var c := size * 0.5
		var dir := (sp - c).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		var t := minf((size.x * 0.5 - margin) / maxf(absf(dir.x), 0.001), (size.y * 0.5 - margin) / maxf(absf(dir.y), 0.001))
		sp = c + dir * t
		var tip := sp + dir * 20.0
		var side := Vector2(-dir.y, dir.x) * 14.0
		marker.draw_colored_polygon(PackedVector2Array([tip, sp - dir * 8.0 + side, sp - dir * 8.0 - side]), col)
	else:
		marker.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -16), sp + Vector2(12, 0), sp + Vector2(0, 16), sp + Vector2(-12, 0)]), col)
		marker.draw_polyline(PackedVector2Array([sp + Vector2(0, -16), sp + Vector2(12, 0), sp + Vector2(0, 16), sp + Vector2(-12, 0), sp + Vector2(0, -16)]), Color(0, 0, 0, 0.6), 2.0)
	var font := UiTheme.title_font()
	var txt := "%d m" % int(d)
	marker.draw_string_outline(font, sp + Vector2(-30, 36), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, 18, 5, Color(0, 0, 0, 0.7))
	marker.draw_string(font, sp + Vector2(-30, 36), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, 18, col)


func set_quest(text: String) -> void:
	quest.text = text
	quest_box.visible = full and text != ""


## Shows or hides the interact prompt, e.g. "Talk to Mara".
func set_prompt(text: String, touch: bool) -> void:
	prompt.visible = text != ""
	prompt.text = text if touch else text + "   [E]"


func show_dialogue(speaker: String, text: String, choices: Array = []) -> void:
	var was_open := dialogue.visible
	dialogue.visible = true
	dlg_name.text = speaker
	dlg_name.visible = speaker != ""
	dlg_rule.visible = speaker != ""
	dlg_text.text = text
	for i in choice_buttons.size():
		var b: Button = choice_buttons[i]
		b.visible = i < choices.size()
		if i < choices.size():
			b.text = "  %d   %s" % [i + 1, choices[i]]
	hint.visible = choices.is_empty()
	if not was_open:
		UiTheme.reveal(dialogue, 0.18)


func has_choices() -> bool:
	return dialogue.visible and choice_buttons[0].visible


func hide_dialogue() -> void:
	dialogue.visible = false
	for b in choice_buttons:
		b.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if has_choices() and event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode - KEY_1
		if k >= 0 and k < choice_buttons.size() and choice_buttons[k].visible:
			choice_made.emit(k)
			get_viewport().set_input_as_handled()


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _box(c: Color, radius: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = c
	b.set_corner_radius_all(radius)
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b

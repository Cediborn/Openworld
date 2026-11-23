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
var stats: Label
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
var objective_pos := Vector3.INF
var objective_text := ""
var marker: Control


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	var bar_bg := PanelContainer.new()
	bar_bg.position = Vector2(18, 72)
	bar_bg.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.35), 8))
	root.add_child(bar_bg)
	var bar_row := HBoxContainer.new()
	bar_bg.add_child(bar_row)
	var heart := Label.new()
	heart.text = "♥"
	heart.add_theme_font_size_override("font_size", 26)
	heart.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	bar_row.add_child(heart)
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(260, 22)
	health_bar.show_percentage = false
	health_bar.add_theme_stylebox_override("background", _box(Color(0.15, 0.05, 0.05, 0.8), 6))
	health_bar.add_theme_stylebox_override("fill", _box(Color(0.82, 0.18, 0.16), 6))
	health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(health_bar)
	health_label = _label(18)
	bar_row.add_child(health_label)

	var stat_bg := PanelContainer.new()
	stat_bg.position = Vector2(18, 112)
	stat_bg.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.3), 8))
	root.add_child(stat_bg)
	var stat_col := VBoxContainer.new()
	stat_bg.add_child(stat_col)
	stats = _label(18)
	stat_col.add_child(stats)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(200, 6)
	xp_bar.show_percentage = false
	xp_bar.add_theme_stylebox_override("background", _box(Color(0.1, 0.1, 0.15, 0.8), 3))
	xp_bar.add_theme_stylebox_override("fill", _box(Color(0.45, 0.7, 1.0), 3))
	stat_col.add_child(xp_bar)

	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	toasts.position = Vector2(24, -330)
	toasts.size = Vector2(520, 150)
	toasts.alignment = BoxContainer.ALIGNMENT_END
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)

	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.position = Vector2(-330, 18)
	boss_box.size = Vector2(660, 60)
	boss_box.visible = false
	root.add_child(boss_box)
	boss_name = _label(26)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	boss_box.add_child(boss_name)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(660, 16)
	boss_bar.show_percentage = false
	boss_bar.add_theme_stylebox_override("background", _box(Color(0.1, 0.03, 0.03, 0.85), 5))
	boss_bar.add_theme_stylebox_override("fill", _box(Color(0.75, 0.15, 0.55), 5))
	boss_box.add_child(boss_bar)

	banner = _label(48)
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.position = Vector2(-500, 150)
	banner.size = Vector2(1000, 60)
	banner.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	banner.modulate.a = 0.0
	root.add_child(banner)
	banner_sub = _label(24)
	banner_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.position = Vector2(-500, 212)
	banner_sub.size = Vector2(1000, 40)
	banner_sub.modulate.a = 0.0
	root.add_child(banner_sub)

	marker = Control.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker.draw.connect(_draw_marker)
	root.add_child(marker)

	quest = _label(22)
	quest.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quest.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest.position = Vector2(-620, 104)
	quest.size = Vector2(500, 200)
	quest.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(quest)

	notice = _label(34)
	notice.set_anchors_preset(Control.PRESET_CENTER)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.position = Vector2(-450, -170)
	notice.size = Vector2(900, 100)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD
	notice.modulate.a = 0.0
	root.add_child(notice)

	defeated = _label(64)
	defeated.text = "You were defeated"
	defeated.set_anchors_preset(Control.PRESET_CENTER)
	defeated.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	defeated.position = Vector2(-450, -60)
	defeated.size = Vector2(900, 120)
	defeated.add_theme_color_override("font_color", Color(0.95, 0.75, 0.7))
	defeated.visible = false
	root.add_child(defeated)

	prompt = Button.new()
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(-190, -250)
	prompt.size = Vector2(380, 70)
	prompt.add_theme_font_size_override("font_size", 26)
	prompt.add_theme_stylebox_override("normal", _box(Color(0.1, 0.1, 0.12, 0.7), 14))
	prompt.add_theme_stylebox_override("hover", _box(Color(0.2, 0.2, 0.24, 0.8), 14))
	prompt.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.3, 0.34, 0.85), 14))
	prompt.focus_mode = Control.FOCUS_NONE
	prompt.visible = false
	prompt.pressed.connect(func() -> void: interact_pressed.emit())
	root.add_child(prompt)

	dialogue = PanelContainer.new()
	dialogue.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue.position = Vector2(-520, -260)
	dialogue.size = Vector2(1040, 220)
	dialogue.add_theme_stylebox_override("panel", _box(Color(0.06, 0.06, 0.08, 0.88), 16))
	dialogue.visible = false
	dialogue.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed and not has_choices():
			dialogue_advanced.emit())
	root.add_child(dialogue)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	dialogue.add_child(col)
	dlg_name = _label(28)
	dlg_name.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	col.add_child(dlg_name)
	dlg_text = _label(26)
	dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	dlg_text.custom_minimum_size = Vector2(1000, 110)
	col.add_child(dlg_text)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 6)
	col.add_child(choice_box)
	for i in 3:
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", _box(Color(0.2, 0.2, 0.25, 0.85), 10))
		b.add_theme_stylebox_override("hover", _box(Color(0.35, 0.3, 0.2, 0.9), 10))
		b.add_theme_stylebox_override("pressed", _box(Color(0.45, 0.38, 0.22, 0.95), 10))
		var idx := i
		b.pressed.connect(func() -> void: choice_made.emit(idx))
		choice_box.add_child(b)
		choice_buttons.append(b)
	hint = _label(18)
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
	for t in toasts.get_children():
		var left: float = t.get_meta("left") - delta
		t.set_meta("left", left)
		t.modulate.a = clampf(left, 0.0, 1.0)
		if left <= 0.0:
			t.queue_free()
	marker.queue_redraw()


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


## Small message in the corner ("+50 coins").
func toast(text: String, kind := "") -> void:
	var l := _label(22)
	l.text = text
	var colors := {"coins": Color(1.0, 0.85, 0.35), "xp": Color(0.6, 0.8, 1.0), "level": Color(0.6, 1.0, 0.6),
		"item": Color(0.9, 0.9, 0.9), "rep": Color(0.95, 0.7, 1.0), "warn": Color(1.0, 0.55, 0.45), "quest": Color(1.0, 0.95, 0.6)}
	l.add_theme_color_override("font_color", colors.get(kind, Color.WHITE))
	l.set_meta("left", 4.0)
	toasts.add_child(l)
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
	stats.text = "◉ %d    Lv %d    ✚ %d" % [coins, level, potions]
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
	var font := ThemeDB.fallback_font
	var txt := "%d m" % int(d)
	marker.draw_string_outline(font, sp + Vector2(-30, 36), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, 18, 5, Color(0, 0, 0, 0.7))
	marker.draw_string(font, sp + Vector2(-30, 36), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, 18, col)


func set_quest(text: String) -> void:
	quest.text = text


## Shows or hides the interact prompt, e.g. "Talk to Mara".
func set_prompt(text: String, touch: bool) -> void:
	prompt.visible = text != ""
	prompt.text = text if touch else text + "   [E]"


func show_dialogue(speaker: String, text: String, choices: Array = []) -> void:
	dialogue.visible = true
	dlg_name.text = speaker
	dlg_text.text = text
	for i in choice_buttons.size():
		var b: Button = choice_buttons[i]
		b.visible = i < choices.size()
		if i < choices.size():
			b.text = "%d.  %s" % [i + 1, choices[i]]
	hint.visible = choices.is_empty()


func has_choices() -> bool:
	return dialogue.visible and choice_buttons[0].visible


func hide_dialogue() -> void:
	dialogue.visible = false
	for b in choice_buttons:
		b.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if has_choices() and event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode - KEY_1
		if k >= 0 and k < 3 and choice_buttons[k].visible:
			choice_made.emit(k)
			get_viewport().set_input_as_handled()


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 6)
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

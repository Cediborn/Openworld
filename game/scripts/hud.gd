class_name Hud
extends CanvasLayer
## On-screen game information: health bar, hurt flash, "defeated" screen,
## interact prompt, dialogue box, quest tracker and short notices.
## Touch players tap the prompt / dialogue box; PC players press E.

signal interact_pressed
signal dialogue_advanced

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
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
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
	var hint := _label(18)
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


## Shows a short centred message for a few seconds.
func show_notice(text: String) -> void:
	notice.text = text
	notice_time = 4.0


func set_quest(text: String) -> void:
	quest.text = text


## Shows or hides the interact prompt, e.g. "Talk to Mara".
func set_prompt(text: String, touch: bool) -> void:
	prompt.visible = text != ""
	prompt.text = text if touch else text + "   [E]"


func show_dialogue(speaker: String, text: String) -> void:
	dialogue.visible = true
	dlg_name.text = speaker
	dlg_text.text = text


func hide_dialogue() -> void:
	dialogue.visible = false


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

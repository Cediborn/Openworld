class_name TouchControls
extends Control
## Landscape phone controls: joystick bottom-left, drag the right side to look,
## jump, sprint and sword buttons bottom-right, pause top-right. Hidden on PC.

var player: Player
var stick_touch := -1
var look_touch := -1
var stick_center := Vector2.ZERO
var stick_pos := Vector2.ZERO
const STICK_R := 90.0

var jump_btn := Rect2()
var sprint_btn := Rect2()
var attack_btn := Rect2()
var pause_btn := Rect2()
var sprint_on := false
## Called when the pause button is tapped.
var on_pause: Callable


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _layout() -> void:
	var s := get_viewport_rect().size
	var u: float = s.y / 720.0
	stick_center = Vector2(190 * u, s.y - 190 * u)
	jump_btn = Rect2(Vector2(s.x - 210 * u, s.y - 210 * u), Vector2(150, 150) * u)
	sprint_btn = Rect2(Vector2(s.x - 360 * u, s.y - 170 * u), Vector2(110, 110) * u)
	attack_btn = Rect2(Vector2(s.x - 330 * u, s.y - 340 * u), Vector2(140, 140) * u)
	pause_btn = Rect2(Vector2(s.x - 96 * u, 16 * u), Vector2(76, 76) * u)


func _input(event: InputEvent) -> void:
	if player == null:
		return
	_layout()
	var s := get_viewport_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			if jump_btn.has_point(event.position):
				player.jump_pressed = true
			elif attack_btn.has_point(event.position):
				player.attack_pressed = true
			elif pause_btn.has_point(event.position):
				if on_pause.is_valid():
					on_pause.call()
			elif sprint_btn.has_point(event.position):
				sprint_on = not sprint_on
				player.sprint_held = sprint_on
			elif event.position.x < s.x * 0.4 and stick_touch == -1:
				stick_touch = event.index
				stick_pos = event.position
			elif event.position.x >= s.x * 0.4 and look_touch == -1:
				look_touch = event.index
		else:
			if event.index == stick_touch:
				stick_touch = -1
				player.move_input = Vector2.ZERO
			if event.index == look_touch:
				look_touch = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == stick_touch:
			stick_pos = event.position
			var off: Vector2 = (stick_pos - stick_center).limit_length(STICK_R * s.y / 720.0)
			player.move_input = off / (STICK_R * s.y / 720.0)
			queue_redraw()
		elif event.index == look_touch:
			player.look_input += event.relative


func _draw() -> void:
	_layout()
	var u: float = get_viewport_rect().size.y / 720.0
	draw_circle(stick_center, STICK_R * u, Color(1, 1, 1, 0.18))
	draw_arc(stick_center, STICK_R * u, 0, TAU, 48, Color(1, 1, 1, 0.55), 3.0 * u)
	var knob: Vector2 = stick_center
	if stick_touch != -1:
		knob += (stick_pos - stick_center).limit_length(STICK_R * u)
	draw_circle(knob, 40 * u, Color(1, 1, 1, 0.85))
	draw_circle(jump_btn.get_center(), jump_btn.size.x * 0.5, Color(1, 1, 1, 0.8))
	var c := jump_btn.get_center()
	draw_polyline(PackedVector2Array([c + Vector2(-26, 14) * u, c + Vector2(0, -14) * u, c + Vector2(26, 14) * u]), Color(0.1, 0.1, 0.12), 8 * u)
	draw_circle(sprint_btn.get_center(), sprint_btn.size.x * 0.5, Color(0.95, 0.55, 0.2, 0.95 if sprint_on else 0.55))
	var sc := sprint_btn.get_center()
	draw_colored_polygon(PackedVector2Array([sc + Vector2(6, -26) * u, sc + Vector2(-14, 4) * u, sc + Vector2(0, 4) * u, sc + Vector2(-6, 26) * u, sc + Vector2(14, -4) * u, sc + Vector2(0, -4) * u]), Color(1, 1, 1))
	# Sword button: a blade drawn diagonally.
	var ac := attack_btn.get_center()
	draw_circle(ac, attack_btn.size.x * 0.5, Color(0.85, 0.25, 0.2, 0.75))
	draw_line(ac + Vector2(-26, 26) * u, ac + Vector2(26, -26) * u, Color(1, 1, 1), 9 * u)
	draw_line(ac + Vector2(-30, 8) * u, ac + Vector2(-8, 30) * u, Color(1, 1, 1), 7 * u)
	# Pause button.
	var pc := pause_btn.get_center()
	draw_circle(pc, pause_btn.size.x * 0.5, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(pc + Vector2(-14, -16) * u, Vector2(9, 32) * u), Color(1, 1, 1, 0.9))
	draw_rect(Rect2(pc + Vector2(5, -16) * u, Vector2(9, 32) * u), Color(1, 1, 1, 0.9))

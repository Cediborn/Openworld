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
var dodge_btn := Rect2()
var block_btn := Rect2()
var potion_btn := Rect2()
var journal_btn := Rect2()
var gun_btn := Rect2()
var reload_btn := Rect2()
var whistle_btn := Rect2()
var sprint_on := false
var block_touch := -1
## Called when the pause button is tapped.
var on_pause: Callable
## Called when the journal button is tapped.
var on_journal: Callable


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
	dodge_btn = Rect2(Vector2(s.x - 160 * u, s.y - 330 * u), Vector2(100, 100) * u)
	block_btn = Rect2(Vector2(s.x - 470 * u, s.y - 290 * u), Vector2(100, 100) * u)
	potion_btn = Rect2(Vector2(s.x - 96 * u, 110 * u), Vector2(76, 76) * u)
	journal_btn = Rect2(Vector2(s.x - 190 * u, 16 * u), Vector2(76, 76) * u)
	gun_btn = Rect2(Vector2(s.x - 96 * u, 204 * u), Vector2(76, 76) * u)
	whistle_btn = Rect2(Vector2(s.x - 96 * u, 298 * u), Vector2(76, 76) * u)
	reload_btn = Rect2(Vector2(s.x - 470 * u, s.y - 170 * u), Vector2(100, 100) * u)


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
			elif dodge_btn.has_point(event.position):
				player.dodge_pressed = true
			elif block_btn.has_point(event.position):
				block_touch = event.index
				player.block_held = true
			elif potion_btn.has_point(event.position):
				player.potion_pressed = true
			elif gun_btn.has_point(event.position) and player.gun and player.gun.owned():
				player.gun_toggle_pressed = true
			elif whistle_btn.has_point(event.position):
				player.whistle_pressed = true
			elif reload_btn.has_point(event.position) and player.gun and player.gun.drawn:
				player.reload_pressed = true
			elif journal_btn.has_point(event.position):
				if on_journal.is_valid():
					on_journal.call()
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
			if event.index == block_touch:
				block_touch = -1
				player.block_held = false
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
	# Dodge (curved arrow), block (shield), potion (flask), journal (book).
	var dc := dodge_btn.get_center()
	draw_circle(dc, dodge_btn.size.x * 0.5, Color(0.25, 0.55, 0.85, 0.7))
	draw_arc(dc, 22 * u, -2.6, 1.2, 16, Color(1, 1, 1), 7 * u)
	draw_colored_polygon(PackedVector2Array([dc + Vector2(10, 22) * u, dc + Vector2(-6, 30) * u, dc + Vector2(4, 12) * u]), Color(1, 1, 1))
	var bc := block_btn.get_center()
	draw_circle(bc, block_btn.size.x * 0.5, Color(0.55, 0.55, 0.6, 0.85 if block_touch != -1 else 0.6))
	draw_colored_polygon(PackedVector2Array([bc + Vector2(-20, -22) * u, bc + Vector2(20, -22) * u, bc + Vector2(18, 6) * u, bc + Vector2(0, 26) * u, bc + Vector2(-18, 6) * u]), Color(1, 1, 1))
	var fc := potion_btn.get_center()
	draw_circle(fc, potion_btn.size.x * 0.5, Color(0, 0, 0, 0.35))
	draw_circle(fc + Vector2(0, 8) * u, 16 * u, Color(0.9, 0.25, 0.3))
	draw_rect(Rect2(fc + Vector2(-6, -20) * u, Vector2(12, 16) * u), Color(0.9, 0.85, 0.8))
	var jc := journal_btn.get_center()
	draw_circle(jc, journal_btn.size.x * 0.5, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(jc + Vector2(-18, -20) * u, Vector2(36, 40) * u), Color(0.75, 0.55, 0.3))
	draw_line(jc + Vector2(-10, -8) * u, jc + Vector2(10, -8) * u, Color(1, 1, 1), 3 * u)
	draw_line(jc + Vector2(-10, 2) * u, jc + Vector2(10, 2) * u, Color(1, 1, 1), 3 * u)
	# Pistol (draw / holster), reload (while drawn) and the horse whistle.
	if player and player.gun and player.gun.owned():
		var gc := gun_btn.get_center()
		draw_circle(gc, gun_btn.size.x * 0.5, Color(0.55, 0.35, 0.15, 0.85) if player.gun.drawn else Color(0, 0, 0, 0.35))
		draw_rect(Rect2(gc + Vector2(-22, -10) * u, Vector2(36, 9) * u), Color(0.85, 0.85, 0.85))
		draw_colored_polygon(PackedVector2Array([gc + Vector2(-22, -2) * u, gc + Vector2(-8, -2) * u, gc + Vector2(-14, 20) * u, gc + Vector2(-26, 18) * u]), Color(0.6, 0.4, 0.2))
		if player.gun.drawn:
			var rc := reload_btn.get_center()
			draw_circle(rc, reload_btn.size.x * 0.5, Color(0.3, 0.3, 0.3, 0.7))
			draw_arc(rc, 22 * u, 0.4, TAU - 0.4, 20, Color(1, 1, 1), 6 * u)
			draw_colored_polygon(PackedVector2Array([rc + Vector2(22, -14) * u, rc + Vector2(30, 4) * u, rc + Vector2(12, 2) * u]), Color(1, 1, 1))
	var wc := whistle_btn.get_center()
	draw_circle(wc, whistle_btn.size.x * 0.5, Color(0, 0, 0, 0.35))
	draw_arc(wc + Vector2(0, 4) * u, 18 * u, PI * 1.1, PI * 1.9 + TAU * 0.5, 14, Color(0.95, 0.85, 0.6), 7 * u)
	draw_line(wc + Vector2(-18, 4) * u, wc + Vector2(-18, 18) * u, Color(0.95, 0.85, 0.6), 7 * u)
	draw_line(wc + Vector2(18, 4) * u, wc + Vector2(18, 18) * u, Color(0.95, 0.85, 0.6), 7 * u)
	# Pause button.
	var pc := pause_btn.get_center()
	draw_circle(pc, pause_btn.size.x * 0.5, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(pc + Vector2(-14, -16) * u, Vector2(9, 32) * u), Color(1, 1, 1, 0.9))
	draw_rect(Rect2(pc + Vector2(5, -16) * u, Vector2(9, 32) * u), Color(1, 1, 1, 0.9))

class_name Interactable
extends Node3D
## Something in the world the explorer can use with E / the prompt button:
## tracks to examine, a chest, a lever, a shrine stone, a pickup. The Story
## node finds the nearest one in range and shows `label`; using it calls
## `action` (which receives this node). Quests and world features create them.

var label := "Examine"
var radius := 2.6
var action: Callable
var enabled := true
## Shown above it while it is part of the tracked quest.
var beacon: Label3D
var visual: Node3D
## Gentle bob for pickups.
var bob := false
var _t := 0.0


func _init(text := "Examine", reach := 2.6, cb := Callable()) -> void:
	label = text
	radius = reach
	action = cb
	add_to_group("interactables")


func _ready() -> void:
	beacon = Label3D.new()
	beacon.text = "◆"
	beacon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	beacon.font_size = 96
	beacon.pixel_size = 0.004
	beacon.outline_size = 14
	beacon.modulate = Color(1.0, 0.85, 0.3)
	beacon.position.y = 2.2
	beacon.visible = false
	add_child(beacon)


func set_beacon(on: bool) -> void:
	if beacon:
		beacon.visible = on


func use() -> void:
	if enabled and action.is_valid():
		action.call(self)


func _process(delta: float) -> void:
	if bob and visual:
		_t += delta
		visual.position.y = 0.5 + 0.12 * sin(_t * 2.2)
		visual.rotation.y += delta * 1.2

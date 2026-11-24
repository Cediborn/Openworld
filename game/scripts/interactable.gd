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


## A mission marker ("!" to start a quest here, "" for none) floating above it.
var quest_mark: Label3D
## Height of the quest mark above the object (metres).
var quest_mark_y := 2.3


func set_quest_mark(kind: String) -> void:
	if quest_mark == null:
		if kind == "":
			return
		quest_mark = Villager.make_marker()
		quest_mark.position.y = quest_mark_y
		add_child(quest_mark)
	Villager.paint_marker(quest_mark, kind)


func set_beacon(on: bool) -> void:
	if beacon:
		beacon.visible = on


func use() -> void:
	if enabled and action.is_valid():
		action.call(self)


func _process(delta: float) -> void:
	if quest_mark and quest_mark.visible:
		quest_mark.position.y = quest_mark_y + 0.12 * sin(Time.get_ticks_msec() * 0.004)
		var cam := get_viewport().get_camera_3d()
		if cam:
			Villager.fit_marker(quest_mark, cam.global_position.distance_to(quest_mark.global_position))
	if bob and visual:
		_t += delta
		visual.position.y = 0.5 + 0.12 * sin(_t * 2.2)
		visual.rotation.y += delta * 1.2

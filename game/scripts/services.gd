class_name Services
extends CanvasLayer
## What townsfolk do for you beyond quests: merchants trade (buy potions and
## supplies, sell materials), the innkeeper and camp fires let you rest until
## night or morning, the captain and the hunter hand out monster contracts,
## and Bram upgrades your sword for coins and starsteel. Also the shop window.

var state: GameState
var quests: Quests
var features: WorldFeatures
var story: Story
var shop_panel: PanelContainer
var shop_title: Label
var buy_list: ItemList
var sell_list: ItemList
var info: Label
var buy_ids: Array = []
var sell_ids: Array = []
var shop_kind := "merchant"
## What the barkeep has heard (one per ask).
const RUMOURS := [
	"Father Aldric's relic went missing from the altar. He won't say so, but he's beside himself.",
	"A pilgrim left here for the old shrine in Glow Hollow. Never came back for her pack.",
	"Sister Maud swears something scratches at the church windows after dark.",
	"Brann the hunter says the deer bolt at a gunshot from half a mile off. Shoot once and make it count.",
	"The archivist says the church chronicle has pages torn out. Old pages. Older than Brickton.",
	"Whistle and a good horse will come running. Bad ones too, if they like you.",
	"Hale's prices went up again. Says the roads are dangerous. Says that every year.",
]


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	shop_panel = PanelContainer.new()
	shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	shop_panel.position = Vector2(-560, -330)
	shop_panel.size = Vector2(1120, 660)
	shop_panel.add_theme_stylebox_override("panel", Hud._box(Color(0.09, 0.08, 0.07, 0.96), 18))
	add_child(shop_panel)
	var col := VBoxContainer.new()
	shop_panel.add_child(col)
	shop_title = Label.new()
	shop_title.add_theme_font_size_override("font_size", 32)
	shop_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	col.add_child(shop_title)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 22)
	col.add_child(info)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	for side in ["Buy", "Sell"]:
		var c2 := VBoxContainer.new()
		c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c2)
		var l := Label.new()
		l.text = side
		l.add_theme_font_size_override("font_size", 26)
		c2.add_child(l)
		var list := ItemList.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.add_theme_font_size_override("font_size", 22)
		c2.add_child(list)
		var b := Button.new()
		b.text = side + " selected"
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		c2.add_child(b)
		if side == "Buy":
			buy_list = list
			b.pressed.connect(_buy)
		else:
			sell_list = list
			b.pressed.connect(_sell)
	var close := Button.new()
	close.text = "Done"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(close_shop)
	col.add_child(close)


## Conversation for a villager's role, or {} if they offer nothing special.
func for_villager(v: Villager) -> Dictionary:
	var lines := v.lines_for("default")
	match v.role:
		"merchant":
			var kind: String = v.cfg.get("shop", "merchant")
			return {"lines": lines, "choices": ["Let's trade", "Goodbye"], "on_choice": func(i: int) -> Dictionary:
				if i == 0:
					open_shop(kind, v.display_name)
				return {}}
		"innkeeper":
			return {"lines": lines, "choices": ["I'd like to rest", "Goodbye"], "on_choice": func(i: int) -> Dictionary:
				return features.rest_menu(v.display_name) if i == 0 else {}}
		"bartender":
			return {"lines": lines, "choices": ["Something to eat or drink", "Heard any rumours?", "Any work going?", "Goodbye"], "on_choice": func(i: int) -> Dictionary:
				match i:
					0:
						open_shop("tavern", v.display_name)
					1:
						return {"lines": [RUMOURS[randi() % RUMOURS.size()]]}
					2:
						var c := quests.contract_convo("board")
						return c if not c.is_empty() else {"lines": ["Father Aldric up at the church was asking for help. And the contract board in the square always has something."]}
				return {}}
		"captain", "hunter":
			var opts := ["Any monster contracts?", "Goodbye"]
			if v.role == "hunter":
				opts.insert(1, "Pistol shot and powder")
			return {"lines": lines, "choices": opts, "on_choice": func(i: int) -> Dictionary:
				if i == 0:
					return quests.contract_convo(v.id)
				if v.role == "hunter" and i == 1:
					open_shop("hunter", v.display_name)
				return {}}
		"smith":
			if story.stage != "done":
				return {}
			var lvl := state.smith_level
			if lvl >= 3:
				return {"lines": ["That blade is as good as I can make it. Look after it."]}
			var cost := 150 * (lvl + 1)
			return {"lines": lines + ["I can temper your blade again: %d coins and a starsteel ingot." % cost], "choices": ["Upgrade my sword (%d coins, 1 starsteel)" % cost, "Not now"],
				"on_choice": func(i: int) -> Dictionary:
					if i != 0:
						return {}
					if state.coins < cost or state.count("starsteel") < 1:
						return {"lines": ["Come back with %d coins and a starsteel ingot. You have %d coins and %d starsteel." % [cost, state.coins, state.count("starsteel")]]}
					state.add_coins(-cost)
					state.remove_item("starsteel")
					state.smith_level += 1
					state.apply_stats()
					return {"lines": ["*clang* *clang* *hiss* ... There. Sharper than ever. (+12% damage)"]}}
		"traveller":
			if v.id == "lost_traveller":
				return {"lines": lines, "choices": ["Give a healing potion", "Leave"], "on_choice": func(i: int) -> Dictionary:
					return features.help_traveller() if i == 0 else {}}
	return {}


func open_shop(kind: String, who: String) -> void:
	shop_kind = kind
	shop_title.text = who
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fill()


func close_shop() -> void:
	visible = false
	get_tree().paused = false


func _fill() -> void:
	buy_list.clear()
	sell_list.clear()
	buy_ids.clear()
	sell_ids.clear()
	for id in state.shops.get(shop_kind, []):
		buy_list.add_item("%s   %d coins" % [state.item_name(id), state.price(id)])
		buy_ids.append(id)
	for id in state.items:
		var it := state.item(id)
		if it.kind in ["material", "potion"] and int(it.get("value", 0)) > 0:
			sell_list.add_item("%s ×%d   %d coins each" % [it.name, state.count(id), int(it.value)])
			sell_ids.append(id)
	info.text = "Coins: %d%s" % [state.coins, "   (Hale's discount: 20% off)" if state.has_flag("merchant_discount") else ""]


func _buy() -> void:
	var sel := buy_list.get_selected_items()
	if sel.is_empty():
		return
	var id: String = buy_ids[sel[0]]
	if state.coins < state.price(id):
		info.text = "Not enough coins (%d needed, you have %d)." % [state.price(id), state.coins]
		return
	state.add_coins(-state.price(id), true)
	state.add_item(id, 1)
	_fill()


func _sell() -> void:
	var sel := sell_list.get_selected_items()
	if sel.is_empty():
		return
	var id: String = sell_ids[sel[0]]
	if state.remove_item(id, 1):
		state.add_coins(int(state.item(id).value), true)
	_fill()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_E]:
		get_viewport().set_input_as_handled()
		close_shop()

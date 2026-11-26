class_name GameAudio
extends Node
## All game sound: biome ambience that crossfades as the player travels,
## footsteps that match the ground (grass, stone, snow), jump and landing
## thuds, 3D calls and roars from creatures, and music that turns tense while
## something is hunting you. Music and effects have their own volume buses. Sounds are synthesized by
## tools/audio/synth_sounds.py; the mix lives in data/audio.json.

const ZONE_KEYS := ["meadow", "frost", "ember", "glow", "village"]

var cfg: Dictionary = {}
var data: WorldData
var player: Player
var ambience := {}          # key -> AudioStreamPlayer
var amb_target := {}        # key -> 0..1 weight
var steps := {}             # surface -> Array[AudioStream]
var step_player: AudioStreamPlayer
var fx_player: AudioStreamPlayer
var creature_sounds := {}   # file name -> AudioStream
var walked := 0.0
var was_on_floor := true
var air := 0.0
var zone_timer := 0.0
var rng := RandomNumberGenerator.new()
var theme: AudioStreamPlayer
var battle: AudioStreamPlayer
var battle_mix := 0.0
var _danger_check := 0.0
var in_danger := false


## Creates the Music and Effects buses once, so settings can change them.
static func ensure_buses() -> void:
	for bus in ["Music", "Effects", "Ambience"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


## Applies the settings volumes (0..1).
static func apply_volumes(music: float, effects: float, master := 1.0, ambience := 0.9) -> void:
	ensure_buses()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), linear_to_db(maxf(ambience, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Effects"), linear_to_db(maxf(effects, 0.0001)))


## Starts ambience, prepares footsteps and wires every creature's voice.
func setup(world_data: WorldData, p: Player, creatures: Array) -> void:
	data = world_data
	player = p
	ensure_buses()
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio.json"))
	theme = _music_player(cfg.music.theme, cfg.music.volume_db)
	battle = _music_player(cfg.music.battle, -80.0)
	theme.play()
	for key in ZONE_KEYS:
		var a: Dictionary = cfg.ambience[key]
		var s := AudioStreamPlayer.new()
		var stream: AudioStreamOggVorbis = load(a.file)
		stream.loop = true
		s.stream = stream
		s.volume_db = -80.0
		s.bus = "Ambience"
		s.set_meta("base_db", float(a.volume_db))
		add_child(s)
		ambience[key] = s
		amb_target[key] = 0.0
	var takes: int = cfg.footsteps.takes
	for surface in ["grass", "stone", "snow", "water"]:
		var list: Array[AudioStream] = []
		for i in takes:
			list.append(load("res://assets/audio/steps/%s_%d.ogg" % [surface, i]))
		steps[surface] = list
	step_player = AudioStreamPlayer.new()
	step_player.volume_db = cfg.footsteps.volume_db
	step_player.max_polyphony = 2
	step_player.bus = "Effects"
	add_child(step_player)
	fx_player = AudioStreamPlayer.new()
	fx_player.bus = "Effects"
	add_child(fx_player)
	for c in creatures:
		attach_creature(c)
	_update_zone_weights()


## Gives a creature a 3D voice; it speaks when it emits `vocal`.
func attach_creature(c: Creature) -> void:
	var snd: Dictionary = c.cfg.get("sounds", {})
	if snd.is_empty():
		return
	var voice := AudioStreamPlayer3D.new()
	voice.max_distance = cfg.creature_max_distance
	voice.unit_size = cfg.creature_unit_size
	voice.volume_db = float(snd.get("volume_db", 0.0))
	voice.position = Vector3(0, 1.0, 0)
	voice.bus = "Effects"
	c.add_child(voice)
	c.vocal.connect(func(kind: String) -> void:
		var name: String = snd.get(kind, snd.get("call", ""))
		if name == "" or not c.visible:
			return
		voice.stream = _creature_stream(name)
		voice.pitch_scale = rng.randf_range(0.92, 1.08)
		voice.play())


func _creature_stream(name: String) -> AudioStream:
	if not creature_sounds.has(name):
		creature_sounds[name] = load("res://assets/audio/creatures/%s.ogg" % name)
	return creature_sounds[name]


func _process(delta: float) -> void:
	if player == null:
		return
	zone_timer -= delta
	if zone_timer <= 0.0:
		zone_timer = 0.25
		_update_zone_weights()
	_fade_ambience(delta)
	_footsteps(delta)
	_music(delta)


func _music_player(path: String, db: float) -> AudioStreamPlayer:
	var m := AudioStreamPlayer.new()
	var st: AudioStreamOggVorbis = load(path)
	st.loop = true
	m.stream = st
	m.volume_db = db
	m.bus = "Music"
	add_child(m)
	return m


## Battle music while any monster near you is chasing or attacking.
func _music(delta: float) -> void:
	_danger_check -= delta
	if _danger_check <= 0.0:
		_danger_check = 0.5
		in_danger = false
		var p := player.global_position
		for c in get_tree().get_nodes_in_group("creatures"):
			if c.visible and c.state in [Creature.State.CHASE, Creature.State.ATTACK, Creature.State.ROAR] \
					and c.global_position.distance_to(p) < cfg.music.danger_distance:
				in_danger = true
				break
	battle_mix = move_toward(battle_mix, 1.0 if in_danger else 0.0, delta / float(cfg.music.fade))
	var base: float = db_to_linear(cfg.music.volume_db)
	theme.volume_db = linear_to_db(maxf(base * (1.0 - battle_mix), 0.0001))
	battle.volume_db = linear_to_db(maxf(base * battle_mix, 0.0001))
	if battle_mix > 0.0 and not battle.playing:
		battle.play()
	elif battle_mix <= 0.0 and battle.playing:
		battle.stop()


func _update_zone_weights() -> void:
	var p := player.global_position
	var w: Array = data.zone(p.x, p.z)
	for i in ZONE_KEYS.size():
		amb_target[ZONE_KEYS[i]] = clampf(w[i], 0.0, 1.0)


func _fade_ambience(delta: float) -> void:
	var k := clampf(delta / float(cfg.ambience_fade), 0.0, 1.0)
	for key in ZONE_KEYS:
		var s: AudioStreamPlayer = ambience[key]
		var lin := db_to_linear(s.volume_db) if s.playing else 0.0
		var goal: float = amb_target[key] * db_to_linear(s.get_meta("base_db"))
		lin = lerpf(lin, goal, k)
		# Silent layers are stopped, so phones only decode what can be heard.
		if lin < 0.003:
			if s.playing and goal < 0.003:
				s.stop()
			continue
		if not s.playing:
			s.play(rng.randf() * 20.0)
		s.volume_db = linear_to_db(lin)


func _surface() -> String:
	if player.water_depth > 0.08:
		return "water"
	var p := player.global_position
	var w: Array = data.zone(p.x, p.z)
	if w[1] > 0.5:
		return "snow"
	if data.on_path(p.x, p.z) > 0.5 or w[4] > 0.5 or w[2] > 0.5:
		return "stone"
	return "grass"


func _footsteps(delta: float) -> void:
	var on_floor := player.is_on_floor()
	air = 0.0 if on_floor and was_on_floor else air + delta
	if on_floor and not was_on_floor and air > 0.25:
		_fx("res://assets/audio/steps/land.ogg", cfg.land_db)
	elif not on_floor and was_on_floor and player.velocity.y > 1.0:
		_fx("res://assets/audio/steps/jump.ogg", cfg.jump_db)
	was_on_floor = on_floor
	if not on_floor:
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if speed < 0.3:
		walked = 0.0
		return
	var stride: float = lerpf(cfg.footsteps.walk_stride, cfg.footsteps.run_stride, clampf((speed - 2.0) / 4.0, 0.0, 1.0))
	walked += speed * delta
	if walked >= stride:
		walked -= stride
		var list: Array = steps[_surface()]
		step_player.stream = list[rng.randi() % list.size()]
		step_player.pitch_scale = rng.randf_range(0.9, 1.1)
		step_player.play()


var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_cache := {}


## Plays a short effect from assets/audio/sfx (several can overlap).
func sfx(name: String, db := -4.0, pitch := 1.0) -> void:
	if not sfx_cache.has(name):
		var path := "res://assets/audio/sfx/%s.ogg" % name
		sfx_cache[name] = load(path) if ResourceLoader.exists(path) else null
	if sfx_cache[name] == null:
		return
	var p: AudioStreamPlayer = null
	for q in sfx_pool:
		if not q.playing:
			p = q
			break
	if p == null:
		if sfx_pool.size() >= 8:
			p = sfx_pool[0]
		else:
			p = AudioStreamPlayer.new()
			p.bus = "Effects"
			add_child(p)
			sfx_pool.append(p)
	p.stream = sfx_cache[name]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _fx(path: String, db: float) -> void:
	fx_player.stream = load(path)
	fx_player.volume_db = db
	fx_player.play()

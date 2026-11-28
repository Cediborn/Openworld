class_name Firearm
extends Node3D
## The explorer's pump-action shotgun: draw it (G or the gun button), aim
## (right mouse, or automatically on phones), fire (left click / the attack
## button), reload (R, or automatically when you fire it empty).
## The magazine tube holds `capacity` shells; after every shot the fore-end is
## pumped to chamber the next one. Reloading thumbs in one shell at a time
## from the pouch ("shotgun_shell") and can be cut short by firing. Each shot
## throws `pellets` pellets in a cone towards the crosshair; every pellet stops
## at the first wall, rock or creature, and hurts less with distance.
## Gunfire carries: deer and other shy animals bolt, monsters nearby come for
## you. Tuning: data/game_config.json "firearm".

signal fired(hit: Node3D, at: Vector3)
## Ammo or load state changed (HUD refresh).
signal ammo_changed
signal message(text: String)

const AMMO_ITEM := "shotgun_shell"
const GUN_ITEM := "shotgun"
## Items from saves made before the shotgun replaced the flintlock.
const OLD_GUN_ITEM := "flintlock"
const OLD_AMMO_ITEM := "pistol_shot"

var player: Player
var state: GameState
var cfg: Dictionary = {}
var drawn := false
## Shells in the magazine tube (one is chambered while it's above zero).
var shells := 6
## True while a shell is ready to fire (kept for older callers).
var loaded: bool:
	get:
		return shells > 0
	set(v):
		shells = maxi(shells, 1) if v else 0
var aiming := false
var reload_left := 0.0
## Seconds until the pump stroke after a shot is finished.
var pump_left := 0.0
var cooldown := 0.0
var _flash: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_t := 0.0
var _smoke: CPUParticles3D
var _impact: CPUParticles3D
var _rng := RandomNumberGenerator.new()
## Plays a named sound effect (wired to GameAudio.sfx by the world).
var play_sfx: Callable = Callable()


func setup(p: Player, game_state: GameState, config: Dictionary) -> void:
	player = p
	state = game_state
	cfg = config
	_rng.seed = 77
	shells = capacity()
	_build_effects()


func capacity() -> int:
	return int(cfg.get("capacity", 6))


func pumping() -> bool:
	return pump_left > 0.0


## Whether the explorer owns the pistol.
func owned() -> bool:
	return state != null and state.count(GUN_ITEM) > 0


func ammo() -> int:
	return state.count(AMMO_ITEM) if state else 0


func reloading() -> bool:
	return reload_left > 0.0


## Draws or holsters the pistol (the sword goes back in its scabbard).
func toggle() -> void:
	if not owned():
		message.emit("You don't have a firearm.")
		return
	set_drawn(not drawn)


func set_drawn(on: bool) -> void:
	drawn = on and owned()
	if not drawn:
		aiming = false
		reload_left = 0.0
		pump_left = 0.0
	player.body.set_gun_drawn(drawn)
	if drawn:
		player.body.set_sword_drawn(false)
	ammo_changed.emit()


## Called every physics frame by the player while on foot.
func update(delta: float, want_fire: bool, want_aim: bool, want_reload: bool) -> void:
	cooldown -= delta
	if _flash_t > 0.0:
		_flash_t -= delta
		var k := clampf(_flash_t / 0.07, 0.0, 1.0)
		_flash.light_energy = 9.0 * k
		_flash_mesh.visible = _flash_t > 0.02
		_flash.visible = _flash_t > 0.0
	if not drawn:
		return
	if pump_left > 0.0:
		pump_left -= delta
		player.body.set_pump(1.0 - clampf(pump_left / _pump_time(), 0.0, 1.0))
		if pump_left <= 0.0:
			player.body.set_pump(0.0)
			ammo_changed.emit()
	# Phones have no aim button: a drawn gun is held up and aimed at the crosshair.
	aiming = want_aim or DisplayServer.is_touchscreen_available()
	if reload_left > 0.0:
		# Firing cuts a reload short as soon as one shell is in.
		if want_fire and shells > 0:
			reload_left = 0.0
			player.body.cancel_action()
		else:
			reload_left -= delta
			aiming = false
			if reload_left <= 0.0:
				if state.remove_item(AMMO_ITEM, 1):
					shells += 1
					player.body.load_shell()
					_sfx("shotgun_shell", -7.0, _rng.randf_range(0.95, 1.05))
				ammo_changed.emit()
				if shells < capacity() and ammo() > 0:
					_next_shell()
			return
	if want_reload and shells < capacity():
		start_reload()
		return
	if want_fire and cooldown <= 0.0 and not pumping():
		if shells > 0:
			fire()
		elif ammo() > 0:
			start_reload()
		else:
			_sfx("shotgun_click", -6.0)
			cooldown = 0.4
			message.emit("Out of shells. Buy them from Tilly, Hale or Brann.")


## Starts loading shells one at a time until the tube is full (or you fire).
func start_reload() -> void:
	if shells >= capacity() or reloading() or ammo() <= 0:
		if ammo() <= 0 and shells == 0:
			message.emit("Out of shells. Buy them from Tilly, Hale or Brann.")
		return
	# One reload animation spread over every shell that will go in.
	var n := mini(capacity() - shells, ammo())
	var length := player.body.anim_length("Pistol_Reload")
	player.body.play_once("Pistol_Reload", 0.12, length / (n * float(cfg.get("reload_time", 0.5))) if length > 0.0 else 1.0)
	_next_shell()
	ammo_changed.emit()


func _next_shell() -> void:
	reload_left = float(cfg.get("reload_time", 0.5))


func _pump_time() -> float:
	return float(cfg.get("pump_time", 0.45))


## Where the crosshair points: the first thing under the screen centre, or a
## far point straight ahead.
func aim_point() -> Vector3:
	var cam := player.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var far := from + dir * float(cfg.get("range", 120.0))
	var hit := _ray(from, far)
	var best: Vector3 = far if hit.is_empty() else hit.position
	var c := _creature_on_segment(from, best)
	if not c.is_empty():
		best = c["point"]
	return best


## Fires one shell: a cone of pellets towards the crosshair. Each creature hit
## takes the sum of its pellets in one blow. Returns the creature that took
## the most pellets, or null.
func fire() -> Node3D:
	if shells <= 0 or not drawn or pumping():
		return null
	shells -= 1
	cooldown = float(cfg.get("fire_cooldown", 0.3))
	var target := aim_point()
	var muzzle := player.body.muzzle_position()
	var aim_dir := (target - muzzle).normalized()
	# Buckshot spreads; tighter when aimed, wider from the hip or on the move.
	var spread := float(cfg.get("spread_aimed", 0.04)) if aiming else float(cfg.get("spread_hip", 0.07))
	if Vector2(player.velocity.x, player.velocity.z).length() > 2.0:
		spread *= 1.4
	var reach := float(cfg.get("range", 45.0))
	var per := float(cfg.get("damage", 14.0))
	var hits := {}     # creature -> [damage, pellets, point]
	var wall_at := Vector3.INF
	for i in int(cfg.get("pellets", 8)):
		var dir := (aim_dir + Vector3(_rng.randfn(0, spread), _rng.randfn(0, spread), _rng.randfn(0, spread))).normalized()
		var end := muzzle + dir * reach
		var wall := _ray(muzzle, end)
		var stop: Vector3 = end if wall.is_empty() else wall.position
		var hit := _creature_on_segment(muzzle, stop)
		if hit.is_empty():
			if not wall.is_empty() and wall_at == Vector3.INF:
				wall_at = stop
			continue
		var c: Node3D = hit["creature"]
		var h: Array = hits.get(c, [0.0, 0, hit["point"]])
		h[0] += per * damage_falloff(muzzle.distance_to(hit["point"]))
		h[1] += 1
		hits[c] = h
	var victim: Node3D = null
	var best := 0
	for c in hits:
		c.take_hit(hits[c][0], player.global_position)
		if hits[c][1] > best:
			best = hits[c][1]
			victim = c
	var at: Vector3 = hits[victim][2] if victim else (wall_at if wall_at != Vector3.INF else muzzle + aim_dir * reach)
	if victim:
		player.struck.emit(victim, at)
	_effects(muzzle, aim_dir, at, victim == null and wall_at != Vector3.INF)
	_alert(player.global_position)
	# Recoil: the camera kicks up hard and the gun jumps.
	player.pitch = clampf(player.pitch + float(cfg.get("recoil", 0.09)), -1.2, 0.6)
	player.body.play_once("Pistol_Shoot", 0.04)
	player.body.kick()
	_sfx("shotgun_shot", -1.0, _rng.randf_range(0.96, 1.04))
	# Rack the pump: the spent hull flies out and the next shell is chambered.
	if shells > 0:
		pump_left = _pump_time()
		get_tree().create_timer(0.12).timeout.connect(func() -> void:
			_sfx("shotgun_pump", -5.0)
			player.body.eject_shell())
	ammo_changed.emit()
	fired.emit(victim, at)
	return victim


## Damage multiplier with distance: full up close, falloff_min at the far limit.
func damage_falloff(dist: float) -> float:
	var a := float(cfg.get("falloff_start", 8.0))
	var b := float(cfg.get("falloff_end", 30.0))
	return lerpf(1.0, float(cfg.get("falloff_min", 0.25)), clampf((dist - a) / maxf(b - a, 1.0), 0.0, 1.0))


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	return player.get_world_3d().direct_space_state.intersect_ray(q)


## Nearest live creature whose body the segment passes through: {creature, point} or {}.
func _creature_on_segment(a: Vector3, b: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for c in player.get_tree().get_nodes_in_group("creatures"):
		if not c.visible or not c.alive():
			continue
		var ax: Array = c.body_axis()
		var pts := Geometry3D.get_closest_points_between_segments(a, b, ax[0], ax[1])
		if pts[0].distance_to(pts[1]) < c.hit_radius() + 0.05:
			var d := a.distance_to(pts[0])
			if d < best_d:
				best_d = d
				best = {"creature": c, "point": pts[0]}
	return best


## Gunfire carries: shy animals bolt, monsters within earshot come for you.
func _alert(from: Vector3) -> void:
	var shy := float(cfg.get("startle_radius", 70.0))
	var loud := float(cfg.get("alert_radius", 35.0))
	for c in player.get_tree().get_nodes_in_group("creatures"):
		if not c.alive():
			continue
		var d: float = c.global_position.distance_to(from)
		c.hear_gunshot(from, d < shy, d < loud)


func _sfx(name: String, db := -4.0, pitch := 1.0) -> void:
	if play_sfx.is_valid():
		play_sfx.call(name, db, pitch)


# ---------- Effects ----------

func _build_effects() -> void:
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.72, 0.38)
	_flash.omni_range = 7.0
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)
	_flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.38, 0.38)
	_flash_mesh.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = _flash_texture()
	fm.albedo_color = Color(1.0, 0.8, 0.45)
	_flash_mesh.material_override = fm
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.visible = false
	add_child(_flash_mesh)
	_smoke = _puff(Color(0.78, 0.76, 0.72, 0.55), 26, 1.6, 0.9, 0.25)
	_impact = _puff(Color(0.55, 0.48, 0.4, 0.8), 18, 0.7, 2.6, 0.12)


func _puff(col: Color, amount: int, life: float, vel: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.9
	p.local_coords = false
	p.direction = Vector3(0, 0, -1)
	p.spread = 25.0
	p.initial_velocity_min = vel * 0.4
	p.initial_velocity_max = vel
	p.gravity = Vector3(0, 0.35, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = grad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _flash_texture()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = m
	p.mesh = mesh
	add_child(p)
	return p


func _effects(muzzle: Vector3, dir: Vector3, at: Vector3, hit_world: bool) -> void:
	_flash.global_position = muzzle + dir * 0.1
	_flash_mesh.global_position = muzzle + dir * 0.12
	_flash_t = 0.07
	_flash.visible = true
	_flash_mesh.visible = true
	_smoke.global_position = muzzle + dir * 0.15
	_smoke.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	_smoke.restart()
	if hit_world:
		_impact.global_position = at - dir * 0.05
		_impact.global_basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
		_impact.restart()


static var _flash_tex: Texture2D
static func _flash_texture() -> Texture2D:
	if _flash_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_flash_tex = t
	return _flash_tex

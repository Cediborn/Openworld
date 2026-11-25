class_name Firearm
extends Node3D
## The explorer's flintlock pistol: draw it (G or the pistol button), aim
## (right mouse, or automatically on phones), fire (left click / the attack
## button), reload (R, or automatically when you fire an empty pistol).
## One ball per load, like a real flintlock; each reload uses a "pistol_shot"
## (lead ball and powder) from the pouch. The shot leaves the muzzle and flies
## to where the crosshair points; it stops at the first wall, rock or creature.
## Gunfire carries: deer and other shy animals bolt, monsters nearby come for
## you. Tuning: data/game_config.json "firearm".

signal fired(hit: Node3D, at: Vector3)
## Ammo or load state changed (HUD refresh).
signal ammo_changed
signal message(text: String)

const AMMO_ITEM := "pistol_shot"
const GUN_ITEM := "flintlock"

var player: Player
var state: GameState
var cfg: Dictionary = {}
var drawn := false
var loaded := true
var aiming := false
var reload_left := 0.0
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
	_build_effects()


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
	if reload_left > 0.0:
		reload_left -= delta
		aiming = false
		if reload_left <= 0.0:
			if state.remove_item(AMMO_ITEM, 1):
				loaded = true
			ammo_changed.emit()
		return
	# Phones have no aim button: a drawn pistol is held up and aimed at the crosshair.
	aiming = want_aim or DisplayServer.is_touchscreen_available()
	if want_reload and not loaded:
		start_reload()
		return
	if want_fire and cooldown <= 0.0:
		if loaded:
			fire()
		elif ammo() > 0:
			start_reload()
		else:
			_sfx("flintlock_click", -6.0)
			cooldown = 0.4
			message.emit("Out of shot. Buy lead and powder from Tilly, Hale or Brann.")


func start_reload() -> void:
	if loaded or reloading() or ammo() <= 0:
		if ammo() <= 0 and not loaded:
			message.emit("Out of shot. Buy lead and powder from Tilly, Hale or Brann.")
		return
	reload_left = float(cfg.get("reload_time", 2.0))
	player.body.play_once("Pistol_Reload", 0.12, 2.0 / reload_left)
	_sfx("flintlock_reload", -8.0)
	ammo_changed.emit()


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


## Fires the loaded ball. Returns the creature hit, or null.
func fire() -> Node3D:
	if not loaded or not drawn:
		return null
	loaded = false
	cooldown = float(cfg.get("fire_cooldown", 0.5))
	var target := aim_point()
	var muzzle := player.body.muzzle_position()
	var dir := (target - muzzle).normalized()
	# A flintlock is not a rifle: a little scatter, more when fired from the hip or on the move.
	var spread := float(cfg.get("spread_aimed", 0.008)) if aiming else float(cfg.get("spread_hip", 0.03))
	if Vector2(player.velocity.x, player.velocity.z).length() > 2.0:
		spread *= 1.8
	dir = (dir + Vector3(_rng.randfn(0, spread), _rng.randfn(0, spread), _rng.randfn(0, spread))).normalized()
	var end := muzzle + dir * float(cfg.get("range", 120.0))
	var wall := _ray(muzzle, end)
	var stop: Vector3 = end if wall.is_empty() else wall.position
	var hit := _creature_on_segment(muzzle, stop)
	var at := stop
	var victim: Node3D = null
	if not hit.is_empty():
		victim = hit["creature"]
		at = hit["point"]
		var d := muzzle.distance_to(at)
		var dmg := float(cfg.get("damage", 70.0)) * damage_falloff(d)
		victim.take_hit(dmg, player.global_position)
		player.struck.emit(victim, at)
	_effects(muzzle, dir, at, victim == null and not wall.is_empty())
	_alert(player.global_position)
	# Recoil: the camera kicks up and the arm jumps.
	player.pitch = clampf(player.pitch + float(cfg.get("recoil", 0.05)), -1.2, 0.6)
	player.body.play_once("Pistol_Shoot", 0.04)
	_sfx("flintlock_shot", -1.0, _rng.randf_range(0.95, 1.05))
	ammo_changed.emit()
	fired.emit(victim, at)
	return victim


## Damage multiplier with distance: full up close, half at the far limit.
func damage_falloff(dist: float) -> float:
	var a := float(cfg.get("falloff_start", 18.0))
	var b := float(cfg.get("falloff_end", 70.0))
	return lerpf(1.0, 0.5, clampf((dist - a) / maxf(b - a, 1.0), 0.0, 1.0))


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

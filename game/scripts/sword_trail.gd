class_name SwordTrail
extends MeshInstance3D
## A short fading ribbon behind the blade while a swing is live, so the arc of
## each cut reads clearly. Built from the blade's real world positions.

const MAX_POINTS := 10
const LIFE := 0.16

var body: ExplorerBody
var emitting := false
var points: Array = []    # [base, tip, age]
var im := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m


func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	for p in points:
		p[2] += delta
	while not points.is_empty() and points[0][2] > LIFE:
		points.pop_front()
	if emitting and body:
		var seg := body.blade_segment()
		points.append([seg[0], seg[1], 0.0])
		if points.size() > MAX_POINTS:
			points.pop_front()
	im.clear_surfaces()
	if points.size() < 2:
		return
	var glow: Color = body.blade_mat.emission if body.blade_mat and body.blade_mat.emission_enabled else Color(0.9, 0.95, 1.0)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in points:
		var a := clampf(1.0 - p[2] / LIFE, 0.0, 1.0) * 0.45
		im.surface_set_color(Color(glow.r, glow.g, glow.b, a * 0.2))
		im.surface_add_vertex(p[0])
		im.surface_set_color(Color(glow.r, glow.g, glow.b, a))
		im.surface_add_vertex(p[1])
	im.surface_end()

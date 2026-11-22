// Animal fur material. Author: Claude (Openworld).
// Targets Forward+ and Mobile. Budget: 3 noise reads (triplanar), no branching.
// Base colour comes from the model's vertex colours (painted by
// tools/creatures/build_creatures.py); the noise adds fine fur streaks so the
// coat doesn't look like plastic up close.
shader_type spatial;
render_mode cull_back;

group_uniforms fur;
uniform sampler2D fur_noise : filter_linear_mipmap, repeat_enable;
uniform float streak_scale = 14.0;   // fur streaks per metre (stretched along the body)
uniform float streak_strength = 0.34;
uniform float sheen = 0.35;          // soft light around the silhouette, like backlit fur
uniform float tint = 1.0;            // per-animal brightness variation
group_uniforms;

varying vec3 obj_pos;
varying vec3 obj_nrm;

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

void fragment() {
	vec3 w = abs(obj_nrm);
	w /= (w.x + w.y + w.z);
	// Streaks run front-to-back (along z) and down the legs (along y).
	float nx = texture(fur_noise, vec2(obj_pos.z * 1.5, obj_pos.y * 4.0) * streak_scale * 0.25).r;
	float ny = texture(fur_noise, vec2(obj_pos.x * 4.0, obj_pos.z * 1.5) * streak_scale * 0.25).r;
	float nz = texture(fur_noise, vec2(obj_pos.x * 4.0, obj_pos.y * 2.0) * streak_scale * 0.25).r;
	float n = nx * w.x + ny * w.y + nz * w.z;
	// Vertex colours arrive gamma-encoded; decode to linear albedo.
	vec3 base = pow(COLOR.rgb, vec3(1.6)) * tint;   // 1.6 not 2.2: keeps coats readable in shade
	ALBEDO = base * (1.0 - streak_strength * 0.5 + streak_strength * n);
	ROUGHNESS = 0.82 + 0.12 * n;
	SPECULAR = 0.28;
	RIM = sheen;
	RIM_TINT = 0.6;
}

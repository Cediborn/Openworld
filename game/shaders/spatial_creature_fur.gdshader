// Creature skin/fur/rock material. Author: Claude (Openworld).
// Targets Forward+, Mobile and Compatibility. Budget: 3 noise reads
// (triplanar), no branching.
// Base colour comes from the model's vertex colours (painted by
// tools/creatures/); vertex alpha stores 1 - glow, which drives emission for
// lava cracks, ice crystals and glowing spots. Noise adds fine streaks so the
// coat doesn't look like plastic up close. UV.x stores gloss (0 = the
// creature's base roughness, 1 = wet eyes, noses, polished shell and horn).
shader_type spatial;
render_mode cull_back;

group_uniforms surface;
uniform sampler2D fur_noise : filter_linear_mipmap, repeat_enable;
uniform float streak_scale = 14.0;   // fur streaks per metre (stretched along the body)
uniform float streak_strength = 0.34;
uniform float base_roughness = 0.85; // 0.35 for a beetle's shiny shell
uniform float sheen = 0.35;          // soft light around the silhouette, like backlit fur
uniform float tint = 1.0;            // per-creature brightness variation
group_uniforms glow;
uniform vec3 glow_color : source_color = vec3(1.0, 0.5, 0.1);
uniform float glow_energy = 0.0;     // 0 = no emission (ordinary animals)
uniform float pulse_speed = 1.6;     // radians per second of the slow throb
uniform float pulse_offset = 0.0;    // per-creature phase so herds don't throb in sync
uniform float hit_flash = 0.0;       // 1 when struck, fades to 0
group_uniforms;

const float GAMMA_DECODE = 1.6;
const float WET_ROUGHNESS = 0.12;    // eyes and noses
const float WET_SPECULAR = 0.7;      // 1.6 not 2.2: keeps dark coats readable in shade

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
	float glow = 1.0 - COLOR.a;
	float gloss = clamp(UV.x, 0.0, 1.0);
	vec3 base = pow(COLOR.rgb, vec3(GAMMA_DECODE)) * tint;
	// Glossy parts (eyes, noses, shell) get no fur streaks.
	ALBEDO = base * mix(1.0 - streak_strength * 0.5 + streak_strength * n, 1.0, gloss);
	ROUGHNESS = mix(base_roughness + 0.12 * n, WET_ROUGHNESS, gloss);
	SPECULAR = mix(mix(0.28, 0.5, step(base_roughness, 0.5)), WET_SPECULAR, gloss);
	CLEARCOAT = gloss;
	CLEARCOAT_ROUGHNESS = 0.08;
	RIM = sheen * (1.0 - gloss);
	RIM_TINT = 0.6;
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed + pulse_offset + obj_pos.y * 3.0);
	EMISSION = glow_color * glow * glow_energy * pulse * (0.7 + 0.6 * n) + vec3(1.0, 0.35, 0.25) * hit_flash * 0.8;
}

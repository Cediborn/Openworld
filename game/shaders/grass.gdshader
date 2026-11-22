shader_type spatial;
render_mode cull_disabled;
// Geometric grass blades (no alpha, cheap on phones) with wind and colour variation.

uniform sampler2D variation : filter_linear_mipmap, repeat_enable;
uniform float wind_strength = 0.18;
uniform float fade_start = 40.0;
uniform float fade_end = 70.0;

varying float tip;
varying vec3 inst_pos;

void vertex() {
	tip = UV.y;
	inst_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(inst_pos, CAMERA_POSITION_WORLD);
	float shrink = 1.0 - smoothstep(fade_start, fade_end, d);
	VERTEX *= vec3(1.0, shrink, 1.0);
	float gust = texture(variation, inst_pos.xz * 0.01 + vec2(TIME * 0.03, TIME * 0.02)).r;
	float sway = sin(TIME * 1.8 + inst_pos.x * 0.35 + inst_pos.z * 0.2) * 0.5 + gust;
	VERTEX.x += sway * wind_strength * tip * tip;
	VERTEX.z += sway * wind_strength * 0.6 * tip * tip;
}

void fragment() {
	float v = texture(variation, inst_pos.xz * 0.02).r;
	vec3 base = vec3(0.07, 0.13, 0.03);
	vec3 mid = mix(vec3(0.24, 0.38, 0.09), vec3(0.42, 0.46, 0.15), v);
	vec3 top = mix(vec3(0.55, 0.62, 0.25), vec3(0.72, 0.66, 0.32), v);
	ALBEDO = mix(mix(base, mid, smoothstep(0.0, 0.5, tip)), top, smoothstep(0.55, 1.0, tip));
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.35, 0.45, 0.15) * tip;
	AO = mix(0.35, 1.0, tip);
	AO_LIGHT_AFFECT = 0.6;
	// Bend normals towards up so the field lights evenly, like real grass.
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.6));
}

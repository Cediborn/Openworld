// Leaf and needle cards. Author: Claude (Openworld).
// Forward+ and Mobile. One texture read; alpha scissor (no sorting cost).
// Vertex colour red = depth in the crown (0 inside, 1 outer edge).
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(1.0);
uniform float snow = 0.0;              // 1 = dust upward-facing leaves with snow
uniform float wind = 0.05;             // sway amplitude in metres per metre of height
uniform float alpha_cut = 0.45;

varying float depth;
varying vec3 wnrm;

void vertex() {
	depth = COLOR.r;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = dot(wp.xz, vec2(0.25, 0.18));
	// Gusts roll across the island (slow travelling waves), and leaves flutter faster at the tips.
	float gust = 0.55 + 0.45 * sin(TIME * 0.35 + wp.x * 0.015 + wp.z * 0.01) * sin(TIME * 0.21 + wp.z * 0.02);
	VERTEX.x += sin(TIME * 1.4 + phase) * wind * gust * VERTEX.y * 0.1;
	VERTEX.z += cos(TIME * 1.1 + phase) * wind * gust * VERTEX.y * 0.06;
	VERTEX += NORMAL * sin(TIME * 7.0 + phase * 9.0) * 0.012 * gust * depth;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 c = t.rgb * tint;
	// Self-shadowing: inner leaves are darker.
	c *= mix(0.45, 1.0, depth);
	float s = snow * smoothstep(0.35, 0.8, wnrm.y);
	ALBEDO = mix(c, vec3(0.9, 0.93, 0.97), s);
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.8 * (1.0 - s);
	AO = mix(0.4, 1.0, depth);
	AO_LIGHT_AFFECT = 0.5;
}

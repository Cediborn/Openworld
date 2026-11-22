shader_type spatial;
render_mode cull_back;
// Leaf clumps: noisy displacement, light through the leaves, darker inside the crown.
// Vertex colour r = baked occlusion (0 inside, 1 outside).

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 leaf_dark : source_color = vec3(0.10, 0.20, 0.05);
uniform vec3 leaf_light : source_color = vec3(0.33, 0.47, 0.14);
uniform float wind = 0.06;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = texture(noise_tex, wpos.xz * 0.35 + wpos.y * 0.2).r;
	VERTEX += NORMAL * (n - 0.5) * 0.9;
	VERTEX.x += sin(TIME * 1.3 + wpos.y * 0.6 + wpos.x * 0.2) * wind * VERTEX.y * 0.15;
}

void fragment() {
	float n = texture(noise_tex, wpos.xz * 1.7 + wpos.y).r;
	float speck = texture(noise_tex, wpos.xz * 6.0 - wpos.y * 3.0).r;
	vec3 c = mix(leaf_dark, leaf_light, clamp(COLOR.r * 0.8 + n * 0.4 - 0.1, 0.0, 1.0));
	c *= 0.75 + speck * 0.5;
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.9;
	AO = mix(0.25, 1.0, COLOR.r);
	AO_LIGHT_AFFECT = 0.7;
}

// Frost spirit: see-through, glowing at the edges, with drifting mist.
// Author: Claude (Openworld). Targets Forward+, Mobile and Compatibility.
// Budget: 2 noise reads, alpha blended (only a few spirits are ever awake).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

group_uniforms mist;
uniform sampler2D fur_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 glow_color : source_color = vec3(0.75, 0.9, 1.0);
uniform float glow_energy = 1.0;
uniform float edge_power = 2.0;      // higher = thinner bright rim
uniform float body_alpha = 0.6;      // how solid the centre of the body looks
uniform float drift_speed = 0.12;    // how fast the mist pattern rises (UV per second)
uniform float tint = 1.0;
uniform float base_roughness = 1.0;  // unused; keeps one parameter set for all creatures
uniform float pulse_offset = 0.0;
group_uniforms;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), edge_power);
	vec2 uv = vec2(obj_pos.x + obj_pos.z, obj_pos.y - TIME * drift_speed) * 2.5;
	float m1 = texture(fur_noise, uv).r;
	float m2 = texture(fur_noise, uv * 2.3 + vec2(0.0, TIME * drift_speed * 1.7)).r;
	float mist = m1 * 0.6 + m2 * 0.4;
	// The trailing tail (low in the model) fades out entirely.
	float fade = smoothstep(0.1, 0.9, obj_pos.y);
	vec3 col = COLOR.rgb * tint;
	ALBEDO = mix(col, glow_color, rim) * glow_energy * (0.8 + 0.4 * mist);
	ALPHA = clamp((body_alpha + rim * 0.8) * (0.55 + 0.6 * mist) * fade + 0.1 * sin(TIME + pulse_offset), 0.0, 1.0);
}

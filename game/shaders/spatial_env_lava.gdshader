// Molten lava surface. Author: Claude (Openworld).
// Forward+ and Mobile. Two scrolling noise reads, emissive only.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D flow_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 hot_color : source_color = vec3(1.0, 0.55, 0.12);
uniform vec3 crust_color : source_color = vec3(0.08, 0.03, 0.02);
uniform float flow_speed = 0.012;     // how fast the crust drifts (UV per second)
uniform float glow_energy = 6.0;      // emission strength of the hot cracks

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Slow heaving of the surface.
	VERTEX.y += sin(TIME * 0.6 + wpos.x * 0.15) * 0.08 + cos(TIME * 0.4 + wpos.z * 0.2) * 0.08;
}

void fragment() {
	vec2 uv = wpos.xz * 0.03;
	float a = texture(flow_noise, uv + vec2(TIME * flow_speed, TIME * flow_speed * 0.6)).r;
	float b = texture(flow_noise, uv * 2.3 - vec2(TIME * flow_speed * 0.8, 0.0)).r;
	// Hot cracks where the two noises cross the middle; dark crust elsewhere.
	float crack = 1.0 - smoothstep(0.0, 0.12, abs(a - b));
	float heat = clamp(crack + smoothstep(0.62, 0.8, a) * 0.6, 0.0, 1.0);
	ALBEDO = mix(crust_color, hot_color * 0.4, heat);
	EMISSION = hot_color * heat * glow_energy + vec3(0.6, 0.12, 0.0) * 0.6;
	ROUGHNESS = mix(0.9, 0.4, heat);
}

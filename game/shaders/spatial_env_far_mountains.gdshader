// Distant mountain ring. Author: Claude (Openworld).
// Forward+ and Mobile. Rock with snow on high, flat ground; fog does the rest.
shader_type spatial;

uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 rock_color : source_color = vec3(0.36, 0.36, 0.38);
uniform vec3 snow_color : source_color = vec3(0.92, 0.94, 0.98);
uniform float snow_height = 330.0;   // snow starts around this height (metres)

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = texture(macro_noise, wpos.xz * 0.003).r;
	float streak = texture(macro_noise, vec2(wpos.x * 0.01, wpos.y * 0.04)).r;
	float flat_ground = smoothstep(0.55, 0.8, wnrm.y);
	float snow = smoothstep(snow_height - 80.0, snow_height + 40.0, wpos.y + n * 120.0) * mix(0.35, 1.0, flat_ground);
	vec3 rock = rock_color * (0.7 + streak * 0.5);
	ALBEDO = mix(rock, snow_color, snow);
	ROUGHNESS = 0.9 - snow * 0.2;
}

shader_type spatial;
// Ground: grass, dirt path (vertex colour red) and rock on steep slopes and peaks.
// Uses downloaded photo textures when present, otherwise procedural colour.

uniform bool use_textures = false;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float tile = 0.25;
uniform float snow_height = 95.0;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 sample_or(sampler2D t, vec2 uv, vec3 fallback) {
	return use_textures ? texture(t, uv).rgb : fallback;
}

void fragment() {
	vec2 uv = world_pos.xz * tile;
	float macro = texture(macro_noise, world_pos.xz * 0.004).r;
	float micro = texture(macro_noise, world_pos.xz * 0.09).r;

	vec3 grass_c = mix(vec3(0.20, 0.33, 0.08), vec3(0.38, 0.45, 0.14), macro);
	grass_c *= 0.8 + micro * 0.4;
	vec3 path_c = mix(vec3(0.36, 0.27, 0.17), vec3(0.48, 0.38, 0.25), micro);
	vec3 rock_c = mix(vec3(0.33, 0.32, 0.30), vec3(0.50, 0.48, 0.45), micro);

	vec3 grass = sample_or(grass_albedo, uv, grass_c) * (use_textures ? mix(0.8, 1.15, macro) : 1.0);
	vec3 path = sample_or(path_albedo, uv * 1.3, path_c);
	vec3 rock = sample_or(rock_albedo, uv * 0.35, rock_c);

	float slope = 1.0 - world_nrm.y;
	float rock_w = smoothstep(0.28, 0.42, slope + (micro - 0.5) * 0.08);
	float path_w = smoothstep(0.35, 0.75, COLOR.r + (micro - 0.5) * 0.35);
	float snow_w = smoothstep(snow_height - 10.0, snow_height + 10.0, world_pos.y + macro * 25.0) * (1.0 - smoothstep(0.55, 0.7, slope));

	vec3 col = mix(grass, path, path_w);
	col = mix(col, rock, rock_w);
	col = mix(col, vec3(0.92, 0.94, 0.97), snow_w);
	ALBEDO = col;

	if (use_textures) {
		vec3 n = mix(texture(grass_normal, uv).rgb, texture(path_normal, uv * 1.3).rgb, path_w);
		n = mix(n, texture(rock_normal, uv * 0.35).rgb, rock_w);
		NORMAL_MAP = mix(n, vec3(0.5, 0.5, 1.0), snow_w);
	}
	ROUGHNESS = mix(0.95, 0.75, rock_w) - snow_w * 0.3;
	SPECULAR = 0.3;
}

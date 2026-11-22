// Ground for the whole island. Author: Claude (Openworld).
// Targets Forward+ (PC) and Mobile (phone). Heights come from the baked height
// texture, so the CPU never builds terrain meshes.
// Layers (texture array order): 0 meadow, 1 snow, 2 lava rock, 3 glow floor,
// 4 village grass, 5 dirt trail, 6 cobblestone, 7 cliff rock.
// Budget: 2 zone layers + trail + road + cliff + snow cap = 6 albedo reads
// (+6 normal reads on PC). Zone selection uses the two strongest weights.
shader_type spatial;

group_uniforms world;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D biome_map : filter_linear, repeat_disable;
uniform sampler2D path_map : filter_linear, repeat_disable;
uniform float world_size = 1024.0;
uniform float texel = 2.0;                 // metres per height sample
group_uniforms surface;
uniform bool use_textures = false;
uniform bool use_normal_maps = true;       // off on phones
uniform sampler2DArray albedo_layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_layers : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 fallback_colors[8];           // used when photo textures are missing
uniform float layer_scale[8];              // texture repeats per metre, per layer
uniform vec3 layer_tint[8];                // colour grade per layer to set each zone's mood
uniform float snow_line = 120.0;           // peaks above this get snow everywhere
group_uniforms;

varying vec3 world_pos;
varying vec3 world_nrm;

vec2 map_uv(vec2 xz) {
	// Centre of the first texel sits at -world_size/2.
	float res = world_size / texel + 1.0;
	return (xz + world_size * 0.5) / texel / res + 0.5 / res;
}

float h_at(vec2 xz) {
	return texture(height_map, map_uv(xz)).r;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = h_at(wp.xz);
	VERTEX.y = h;
	world_pos = vec3(wp.x, h, wp.z);
	// Central differences for the normal.
	float hx = h_at(wp.xz + vec2(texel, 0.0)) - h_at(wp.xz - vec2(texel, 0.0));
	float hz = h_at(wp.xz + vec2(0.0, texel)) - h_at(wp.xz - vec2(0.0, texel));
	world_nrm = normalize(vec3(-hx, 2.0 * texel, -hz));
	NORMAL = (MODEL_MATRIX * vec4(world_nrm, 0.0)).xyz;
}

vec3 layer_albedo(int i, vec2 xz) {
	vec3 tex = texture(albedo_layers, vec3(xz * layer_scale[i], float(i))).rgb * layer_tint[i];
	return use_textures ? tex : fallback_colors[i];
}

vec3 layer_normal(int i, vec2 xz) {
	return texture(normal_layers, vec3(xz * layer_scale[i], float(i))).rgb;
}

void fragment() {
	vec2 xz = world_pos.xz;
	vec4 b = texture(biome_map, map_uv(xz));
	vec2 pm = texture(path_map, map_uv(xz)).rg;
	float macro = texture(macro_noise, xz * 0.006).r;
	float micro = texture(macro_noise, xz * 0.11).r;

	// Five zone weights; meadow is whatever the four outer zones leave.
	float w[5] = float[5](max(0.0, 1.0 - b.r - b.g - b.b - b.a), b.r, b.g, b.b, b.a);
	// Pick the two strongest zones (layers 0, 1, 2, 3, 4 match zones 0..4).
	int a_i = 0;
	for (int i = 1; i < 5; i++) { a_i = w[i] > w[a_i] ? i : a_i; }
	int b_i = a_i == 0 ? 1 : 0;
	for (int i = 0; i < 5; i++) { b_i = (i != a_i && w[i] > w[b_i]) ? i : b_i; }
	float blend = w[b_i] / max(w[a_i] + w[b_i], 0.001);
	// Break up the zone border with noise so it doesn't look like a gradient.
	blend = smoothstep(0.25, 0.75, blend + (macro - 0.5) * 0.5);

	vec3 col = mix(layer_albedo(a_i, xz), layer_albedo(b_i, xz), blend);
	vec3 nrm = use_normal_maps ? mix(layer_normal(a_i, xz), layer_normal(b_i, xz), blend) : vec3(0.5, 0.5, 1.0);
	col *= mix(0.82, 1.12, macro);   // large-scale colour variation

	float slope = 1.0 - world_nrm.y;
	float cliff = smoothstep(0.30, 0.45, slope + (micro - 0.5) * 0.1);
	float trail = smoothstep(0.3, 0.7, pm.r + (micro - 0.5) * 0.4);
	float road = smoothstep(0.4, 0.6, pm.g);
	float snow_cap = smoothstep(snow_line - 15.0, snow_line + 15.0, world_pos.y + macro * 30.0) * (1.0 - smoothstep(0.55, 0.75, slope));

	// Trails through snow are trampled snow, not bare dirt.
	vec3 trail_c = mix(layer_albedo(5, xz), layer_albedo(1, xz) * 0.82, smoothstep(0.3, 0.7, w[1]));
	col = mix(col, trail_c, trail);
	col = mix(col, layer_albedo(6, xz), road);
	col = mix(col, layer_albedo(7, xz) * mix(vec3(1.0), vec3(0.55, 0.5, 0.52), w[2]), cliff);
	col = mix(col, layer_albedo(1, xz), snow_cap);
	if (use_normal_maps) {
		nrm = mix(nrm, layer_normal(5, xz), trail);
		nrm = mix(nrm, layer_normal(6, xz), road);
		nrm = mix(nrm, layer_normal(7, xz), cliff);
		NORMAL_MAP = nrm;
	}
	// Ground near lava glows faintly orange.
	float heat = w[2] * (1.0 - smoothstep(1.0, 3.5, world_pos.y));
	EMISSION = vec3(1.0, 0.35, 0.05) * heat * 2.0;

	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.75, cliff) - snow_cap * 0.25 - road * 0.1;
	SPECULAR = 0.3 + snow_cap * 0.2;
}

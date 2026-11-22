// Grass and wildflowers that follow the camera. Author: Claude (Openworld).
// Forward+ and Mobile. Instances sit on a fixed grid that moves with the player
// in whole cells, so each blade keeps its world spot. Height, zone and trail
// masks come from the baked maps; blades where grass can't grow shrink to zero.
shader_type spatial;
render_mode cull_disabled;

group_uniforms world;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D biome_map : filter_linear, repeat_disable;
uniform sampler2D path_map : filter_linear, repeat_disable;
uniform float world_size = 1024.0;
uniform float texel = 2.0;
group_uniforms look;
uniform sampler2D variation : filter_linear_mipmap, repeat_enable;
uniform float radius = 45.0;          // grass fades out at this distance from the player
uniform float wind_strength = 0.16;
uniform bool flowers = false;         // this instance set draws flower heads instead
uniform float night = 0.0;            // 0 day .. 1 night, makes Glow Hollow grass shine
group_uniforms;

varying float tip;
varying vec3 tint;
varying float glow;

vec2 map_uv(vec2 xz) {
	float res = world_size / texel + 1.0;
	return (xz + world_size * 0.5) / texel / res + 0.5 / res;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	tip = UV.y;
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 cell = floor(base.xz * 4.0 + 0.5);
	vec2 jitter = vec2(hash(cell), hash(cell + 17.0)) - 0.5;
	vec2 xz = base.xz + jitter * 0.6;
	float rot = hash(cell + 3.0) * 6.2831;
	float size = mix(0.6, 1.25, hash(cell + 9.0));

	vec4 b = texture(biome_map, map_uv(xz));
	vec2 pm = texture(path_map, map_uv(xz)).rg;
	float meadow = max(0.0, 1.0 - b.r - b.g - b.b - b.a);
	float density = clamp(meadow + b.a * 0.7 + b.b * 0.9 - b.r * 2.0 - b.g * 2.0, 0.0, 1.0);
	density *= 1.0 - smoothstep(0.15, 0.5, max(pm.r, pm.g));
	float keep = step(hash(cell + 5.0), density);
	// Flowers: only a few, only in meadow and village grass.
	float flower_keep = step(hash(cell + 41.0), 0.07 * (meadow + b.a * 0.5));
	keep = flowers ? keep * flower_keep : keep;

	float d = distance(xz, CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(radius * 0.65, radius, d);
	float s = size * keep * fade;

	vec3 v = VERTEX;
	v.xz = mat2(vec2(cos(rot), -sin(rot)), vec2(sin(rot), cos(rot))) * v.xz;
	v *= vec3(s, s * mix(0.45, 0.85, hash(cell + 13.0)) * (flowers ? 1.4 : 1.0), s);
	float gust = texture(variation, xz * 0.012 + vec2(TIME * 0.03, TIME * 0.02)).r;
	float sway = sin(TIME * 1.7 + xz.x * 0.35 + xz.y * 0.2) * 0.5 + gust;
	v.x += sway * wind_strength * tip * tip;
	v.z += sway * wind_strength * 0.5 * tip * tip;

	float h = texture(height_map, map_uv(xz)).r;
	vec3 world = vec3(xz.x, h - 0.02, xz.y) + v;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;

	// Colour per zone: green meadow, drier village grass, blue-violet Glow Hollow.
	float var_ = texture(variation, xz * 0.02).r;
	vec3 meadow_c = mix(vec3(0.22, 0.36, 0.08), vec3(0.42, 0.46, 0.14), var_);
	vec3 village_c = mix(vec3(0.38, 0.40, 0.16), vec3(0.52, 0.48, 0.24), var_);
	vec3 glow_c = mix(vec3(0.12, 0.10, 0.28), vec3(0.18, 0.32, 0.42), var_);
	float tot = max(meadow + b.a + b.b, 0.001);
	tint = (meadow_c * meadow + village_c * b.a + glow_c * b.b) / tot;
	glow = b.b / tot;
	// Flower petal colour picked per plant.
	float fc = hash(cell + 77.0);
	vec3 petal = fc < 0.35 ? vec3(0.95, 0.92, 0.85) : (fc < 0.65 ? vec3(0.98, 0.78, 0.15) : (fc < 0.85 ? vec3(0.62, 0.42, 0.85) : vec3(0.35, 0.55, 0.95)));
	tint = flowers ? petal : tint;
}

void fragment() {
	vec3 root = tint * 0.25;
	vec3 top = flowers ? tint : tint * 1.35 + vec3(0.06, 0.05, 0.0);
	ALBEDO = mix(root, top, smoothstep(0.0, 0.9, tip));
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = tint * 0.6 * tip;
	AO = mix(0.35, 1.0, tip);
	AO_LIGHT_AFFECT = 0.6;
	EMISSION = vec3(0.25, 0.65, 1.0) * glow * tip * tip * (0.25 + night * 1.2);
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.6));
}

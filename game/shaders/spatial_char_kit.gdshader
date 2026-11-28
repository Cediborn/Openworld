// spatial_char_kit: clothing from the Quaternius outfit kit, recoloured per person.
// Author: Claude (Openworld). Targets Forward+, Mobile and Compatibility; 3 texture
// samples, no branching (masks are mixed with step/smoothstep).
//
// recolor = 0: as painted.
// recolor = 1: every cloth pixel takes the tint's hue and saturation but keeps its
//              own light and dark (folds, seams, stitching).
// green_only = 1: only green cloth is recoloured (leather, buckles keep their colour).
// whiten = 1: the cloth becomes a near-white of the tint's hue; folds stay visible.
shader_type spatial;

group_uniforms textures;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
// R = ambient occlusion, G = roughness, B = metallic (glTF ORM layout).
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;

group_uniforms recolour;
uniform vec4 tint : source_color = vec4(1.0);
uniform float recolor : hint_range(0.0, 1.0) = 0.0;
uniform float green_only : hint_range(0.0, 1.0) = 0.0;
uniform float whiten : hint_range(0.0, 1.0) = 0.0;
// Typical brightness of the painted cloth; the tint's brightness is relative to it.
uniform float ref_value : hint_range(0.05, 1.0) = 0.62;
// How far towards the tint's saturation the cloth goes (lower = more of the
// painted, earthy look survives).
uniform float dye_amount : hint_range(0.0, 1.0) = 0.65;
// Dyed cloth never gets more saturated than this (keeps a muted, medieval palette).
uniform float max_saturation : hint_range(0.0, 1.0) = 0.35;
// 1 = very dark pixels (gloves, hands, shadows in the paint) keep their colour.
uniform float keep_dark : hint_range(0.0, 1.0) = 0.0;
// Grazing-angle sheen on cloth (0 = none).
uniform float sheen : hint_range(0.0, 0.5) = 0.15;

// Pixels above this metallic value count as metal and are never recoloured.
const float METAL_LO = 0.35;
const float METAL_HI = 0.6;
// Green must exceed red and blue by this much to count as green cloth.
const float GREEN_LO = 0.004;
const float GREEN_HI = 0.03;
// White cloth: brightness = base + painted brightness * gain, capped.
// Painted brightness below DARK_LO is "dark" for keep_dark, above DARK_HI is cloth.
const float DARK_LO = 0.14;
const float DARK_HI = 0.24;
// < 1 compresses the paint's light/dark range so the tint sets the overall brightness.
const float DETAIL_GAMMA = 0.55;
const float WHITE_BASE = 0.55;
const float WHITE_GAIN = 0.9;
const float WHITE_CAP = 0.88;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	float cloth = 1.0 - smoothstep(METAL_LO, METAL_HI, orm.b);
	float green = smoothstep(GREEN_LO, GREEN_HI, c.g - max(c.r, c.b));
	vec3 src = rgb2hsv(c);
	float m = recolor * cloth * mix(1.0, green, green_only) * mix(1.0, smoothstep(DARK_LO, DARK_HI, src.z), keep_dark);
	vec3 t = rgb2hsv(tint.rgb);
	// Coloured cloth: tint hue, mostly tint saturation, painted shading scaled to the tint's brightness.
	float sat = min(mix(src.y, t.y, dye_amount), max_saturation);
	// The garment takes the tint's brightness; the paint's light and dark survive, compressed.
	float val = clamp(t.z * pow(src.z / ref_value, DETAIL_GAMMA), 0.0, 1.0);
	vec3 dyed = hsv2rgb(vec3(t.x, sat, val));
	// White cloth: lifted brightness, a third of the tint's saturation.
	vec3 white = hsv2rgb(vec3(t.x, t.y * 0.35, clamp(WHITE_BASE + src.z * WHITE_GAIN, 0.0, WHITE_CAP) * t.z));
	c = mix(c, mix(dyed, white, whiten), m);
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	RIM = sheen * cloth;
	RIM_TINT = 0.6;
}

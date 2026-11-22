// Northern lights curtains. Author: Claude (Openworld).
// Forward+ and Mobile. Unshaded additive ribbons; two noise reads.
// UV.x runs along the curtain, UV.y from bottom (0) to top (1).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float strength = 0.0;         // 0 hidden (day) .. ~1.4 bright night over the snow
uniform vec3 low_color : source_color = vec3(0.2, 1.0, 0.55);
uniform vec3 high_color : source_color = vec3(0.45, 0.25, 0.95);
uniform float drift = 0.01;           // how fast the folds travel along the curtain

void fragment() {
	float rays = texture(noise_tex, vec2(UV.x * 6.0 + TIME * drift, 0.1)).r;
	float folds = texture(noise_tex, vec2(UV.x * 2.0 - TIME * drift * 0.5, UV.y * 0.3 + TIME * 0.005)).r;
	// Bright lower edge, fading upward; vertical streaks from the ray noise.
	float edge = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.15, 1.0, UV.y));
	float streak = smoothstep(0.35, 0.8, rays) * 0.8 + 0.2;
	float a = edge * streak * smoothstep(0.3, 0.7, folds) * strength;
	vec3 c = mix(low_color, high_color, smoothstep(0.1, 0.8, UV.y));
	ALBEDO = c * a * 1.4;
}

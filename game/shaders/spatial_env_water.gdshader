shader_type spatial;
// Openworld water: rivers, streams, waterfalls, ponds and lakes, and (frozen)
// ice. One cheap forward shader for PC and phones: no screen or depth reads.
// Author: Claude (Openworld). Targets Forward+, Mobile and Compatibility; budget: 3 noise
// samples per pixel, no loops; the frozen/falling switches are per-material uniforms.
// Mesh vertex colour carries what the builder measured from the terrain:
//   COLOR.r  water depth in metres / 4 (0 at the shore) -> colour, clarity, foam
//   COLOR.g  turbulence 0..1 (rapids, the foot of a waterfall)
// UV.y runs along the flow (metres), UV.x across it.
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform sampler2D ripple_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 shallow_color : source_color = vec4(0.30, 0.48, 0.42, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.16, 0.20, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.95, 0.95, 1.0);
uniform float flow_speed = 0.6;          // metres per second along UV.y (0 for still water)
uniform float murk = 0.0;                // 0 clear .. 1 muddy river water
uniform float clarity = 1.5;             // metres of depth before the colour is fully deep
uniform float ripple_scale = 0.12;
uniform bool frozen = false;             // ice: no flow, pale, cracked
uniform bool falling = false;            // waterfall sheet: streaks, always foamy
uniform float night = 0.0;               // dims the sky glint at night

varying float v_depth;
varying float v_turb;

void vertex() {
	v_depth = COLOR.r * 4.0;
	v_turb = COLOR.g;
	if (!frozen && !falling) {
		float t = TIME * 0.8;
		VERTEX.y += sin(VERTEX.x * 0.7 + t) * 0.015 + cos(VERTEX.z * 0.9 - t * 1.3) * 0.015;
	}
}

void fragment() {
	vec2 flow = vec2(0.0, -TIME * flow_speed);
	vec2 uv = UV;
	if (falling) {
		uv = vec2(UV.x * 2.0, UV.y * 0.35);
		flow *= 1.8;
	}
	vec3 n1 = texture(ripple_noise, (uv + flow) * ripple_scale).rgb;
	vec3 n2 = texture(ripple_noise, (uv * 1.7 + flow * 1.4 + vec2(0.37, 0.11)) * ripple_scale).rgb;
	vec3 ripple = (n1 + n2) - 1.0;

	float depth_t = clamp(v_depth / max(clarity, 0.01), 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth_t);
	col = mix(col, vec3(0.36, 0.30, 0.20), murk * 0.7);

	// Foam: along the shore, in rapids, and all over a falling sheet.
	float shore = 1.0 - smoothstep(0.0, 0.25, v_depth);
	float churn = v_turb * smoothstep(0.35, 0.75, n1.r + n2.g * 0.6);
	float streak = falling ? smoothstep(0.42, 0.7, texture(ripple_noise, vec2(uv.x * 0.6, uv.y * 0.05 + flow.y * 0.25)).r) : 0.0;
	float foam = clamp(shore * smoothstep(0.4, 0.7, n2.r) + churn + streak + (falling ? 0.25 : 0.0), 0.0, 1.0);
	col = mix(col, foam_color.rgb, foam);

	if (frozen) {
		float crack = smoothstep(0.48, 0.5, abs(n1.r - 0.5) + 0.47) * 0.35;
		col = mix(vec3(0.74, 0.84, 0.9), vec3(0.55, 0.7, 0.8), depth_t * 0.6) - crack;
		ROUGHNESS = 0.25;
		ALPHA = 0.97;
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	} else {
		ROUGHNESS = mix(0.04, 0.35, foam);
		NORMAL_MAP = normalize(vec3(ripple.xy * (falling ? 0.8 : 0.45), 1.0)) * 0.5 + 0.5;
		// Clear at the very edge so the shoreline blends into the bank.
		ALPHA = mix(0.35, 0.9, smoothstep(0.0, 0.6, v_depth)) * (1.0 - murk * 0.2) + murk * 0.2;
		ALPHA = max(ALPHA, foam * 0.95);
		if (falling) {
			ALPHA = 0.55 + foam * 0.4;
		}
	}
	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.25, night);
}

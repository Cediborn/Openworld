shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Ground warning under a heavy attack: a ring that fills towards the impact.
uniform vec4 color : source_color = vec4(1.0, 0.35, 0.1, 1.0);
uniform float fill = 0.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float edge = smoothstep(1.0, 0.94, r) * smoothstep(0.84, 0.92, r);
	float inner = step(r, fill) * smoothstep(1.0, 0.9, r) * 0.35;
	float a = max(edge * 0.85, inner) * (0.6 + 0.4 * fill);
	ALBEDO = color.rgb;
	ALPHA = a;
}

// Explorer outfit material. Author: Claude (Openworld).
// Targets Forward+ and Mobile. Budget: 4 texture reads (skin) + 3 noise reads.
// Vertex colour red picks the region: 0 skin, 1/3 jacket, 2/3 pants, 1 boots.
// Regions are blended with step() masks, so there is no branching per pixel.
shader_type spatial;

group_uniforms skin;
uniform sampler2D skin_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D skin_rough : hint_roughness_g, filter_linear_mipmap;
group_uniforms cloth;
uniform sampler2D weave_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 jacket_color : source_color = vec3(0.29, 0.29, 0.19);
uniform vec3 pants_color : source_color = vec3(0.16, 0.16, 0.13);
uniform vec3 boots_color : source_color = vec3(0.27, 0.17, 0.10);
uniform float weave_scale = 40.0;      // fabric weave repeats across the UV sheet
uniform float fibre_scale = 90.0;      // fine fibre detail
uniform float grime_scale = 3.0;       // large dirty patches
group_uniforms;

varying float region;

void vertex() {
	region = COLOR.r * 3.0;
}

void fragment() {
	// One-hot masks for the four regions.
	float is_jacket = step(0.5, region) * (1.0 - step(1.5, region));
	float is_pants = step(1.5, region) * (1.0 - step(2.5, region));
	float is_boots = step(2.5, region);
	float is_cloth = clamp(is_jacket + is_pants + is_boots, 0.0, 1.0);

	float n1 = texture(weave_noise, UV * weave_scale).r;
	float n2 = texture(weave_noise, UV * fibre_scale).r;
	float grime = texture(weave_noise, UV * grime_scale).r;

	vec3 cloth = jacket_color * is_jacket + pants_color * is_pants + boots_color * is_boots;
	cloth *= (0.92 + n2 * 0.16) * mix(0.86, 1.04, grime);
	vec3 cloth_n = normalize(vec3(n2 - 0.5, n1 - 0.5, mix(1.7, 2.5, is_boots))) * 0.5 + 0.5;
	float cloth_r = mix(0.93, mix(0.45, 0.8, n1), is_boots);

	ALBEDO = mix(texture(skin_albedo, UV).rgb, cloth, is_cloth);
	NORMAL_MAP = mix(texture(skin_normal, UV).rgb, cloth_n, is_cloth);
	ROUGHNESS = mix(texture(skin_rough, UV).g, cloth_r, is_cloth);
	SPECULAR = mix(0.5, mix(0.3, 0.45, is_boots), is_cloth);
	SSS_STRENGTH = 0.25 * (1.0 - is_cloth);
}

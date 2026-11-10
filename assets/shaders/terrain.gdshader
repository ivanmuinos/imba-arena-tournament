shader_type spatial;
// Arena ground: ash floor + triplanar basalt on slopes, glowing magma cracks (vertex alpha = crack glow),
// detail roughness variation. Vertex colour = tint.

uniform sampler2D ash_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D ash_nrm : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_nrm : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float bump = 0.9;
uniform sampler2D glow_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 glow_color : source_color = vec3(1.0, 0.35, 0.1);
uniform float glow_strength = 1.2;
uniform float pulse_speed = 0.8;
uniform float tint_scale = 1.7;
uniform float rock_scale = 0.12;

varying vec3 v_wpos;
varying vec3 v_wn;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar(sampler2D t, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

float lum(vec3 c) {
	return dot(c, vec3(0.333));
}

void fragment() {
	vec3 ash = texture(ash_tex, UV).rgb;
	// The same texture again, finer (grain up close) and much coarser (broad patches that hide the tiling); each is
	// divided by its own average so it only adds variation, not brightness.
	vec2 uv_fine = UV * 3.7 + vec2(0.37, 0.11);
	vec2 uv_macro = v_wpos.xz * 0.021;
	ash *= mix(1.0, lum(texture(ash_tex, uv_fine).rgb) / max(lum(textureLod(ash_tex, uv_fine, 7.0).rgb), 0.01), 0.35);
	ash *= mix(1.0, lum(texture(rock_tex, uv_macro).rgb) / max(lum(textureLod(rock_tex, uv_macro, 8.0).rgb), 0.01), 0.22);
	// Face normal from screen derivatives: heightfield cliffs have smoothed vertex normals that look flat-ish,
	// which stretched the ash texture down vertical walls.
	vec3 fn = normalize(cross(dFdx(v_wpos), dFdy(v_wpos)));
	vec3 rn = normalize(mix(v_wn, fn * sign(dot(fn, v_wn)), 0.65));
	vec3 rp = v_wpos * rock_scale;
	vec3 rock = triplanar(rock_tex, rp, rn);
	float slope = smoothstep(0.42, 0.68, 1.0 - abs(fn.y));
	vec3 base = mix(ash, rock, slope);
	ALBEDO = base * COLOR.rgb * tint_scale;
	ROUGHNESS = mix(0.95, 0.75, slope) - base.r * 0.15;
	// Relief: the mesh has no tangents, so the normal maps are applied in world space (floor: x/z; rock: per axis).
	vec2 nf = (texture(ash_nrm, UV).rg * 2.0 - 1.0) + (texture(ash_nrm, uv_fine).rg * 2.0 - 1.0) * 0.6;
	vec3 w = pow(abs(rn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 bx = texture(rock_nrm, rp.zy).rg * 2.0 - 1.0;
	vec2 by = texture(rock_nrm, rp.xz).rg * 2.0 - 1.0;
	vec2 bz = texture(rock_nrm, rp.xy).rg * 2.0 - 1.0;
	vec3 rock_bump = vec3(0.0, bx.y, bx.x) * w.x + vec3(by.x, 0.0, by.y) * w.y + vec3(bz.x, bz.y, 0.0) * w.z;
	vec3 wn = normalize(v_wn + mix(vec3(nf.x, 0.0, nf.y), rock_bump, slope) * bump);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float crack = texture(glow_tex, UV).r * (1.0 - slope * 0.85);
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed + v_wpos.x * 0.35 + v_wpos.z * 0.27);
	EMISSION = glow_color * crack * glow_strength * COLOR.a * pulse;
}

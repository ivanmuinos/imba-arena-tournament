shader_type spatial;
// Weathered surface for the environment kit (stone, wood, metal): world-space triplanar albedo + normal map
// (so every scaled piece keeps the same texel density), vertex-colour AO from Blender, dust on upward faces and
// edge wear from screen-space curvature (bevelled edges and chipped corners get lighter).

uniform vec4 base_color : source_color = vec4(0.5, 0.45, 0.4, 1.0);
uniform sampler2D albedo_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float tex_scale = 0.28;
uniform float normal_strength = 0.8;
uniform float rough = 0.85;
uniform float metallic = 0.0;
uniform float dust_amount = 0.35;
uniform vec3 dust_color : source_color = vec3(0.55, 0.5, 0.44);
uniform float wear_amount = 0.6;

varying vec3 v_pos;
varying vec3 v_n;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	vec3 w = pow(abs(v_n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = v_pos * tex_scale;
	vec3 tex = tri(albedo_tex, p, w);
	float up = smoothstep(0.55, 0.95, v_n.y);
	vec3 col = base_color.rgb * tex * 1.9;
	col = mix(col, dust_color * (0.6 + tex.r), up * dust_amount);
	float curv = clamp(length(fwidth(v_n)) * 9.0, 0.0, 1.0);
	col = mix(col, col * 1.45 + vec3(0.04), curv * wear_amount);
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = clamp(rough - curv * 0.25 + (1.0 - tex.r) * 0.1, 0.1, 1.0);
	METALLIC = metallic;
	vec3 nm = tri(normal_tex, p, w);
	NORMAL_MAP = vec3(nm.xy, 0.5);
	NORMAL_MAP_DEPTH = normal_strength;
}

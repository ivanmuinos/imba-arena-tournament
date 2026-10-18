shader_type spatial;
// Arena ground: ash floor + triplanar basalt on slopes, glowing magma cracks (vertex alpha = crack glow),
// detail roughness variation. Vertex colour = tint.

uniform sampler2D ash_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
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

void fragment() {
	vec3 ash = texture(ash_tex, UV).rgb;
	// Face normal from screen derivatives: heightfield cliffs have smoothed vertex normals that look flat-ish,
	// which stretched the ash texture down vertical walls.
	vec3 fn = normalize(cross(dFdx(v_wpos), dFdy(v_wpos)));
	vec3 rn = normalize(mix(v_wn, fn * sign(dot(fn, v_wn)), 0.65));
	vec3 rock = triplanar(rock_tex, v_wpos * rock_scale, rn);
	float slope = smoothstep(0.42, 0.68, 1.0 - abs(fn.y));
	vec3 base = mix(ash, rock, slope);
	ALBEDO = base * COLOR.rgb * tint_scale;
	ROUGHNESS = mix(0.95, 0.75, slope) - base.r * 0.15;
	float crack = texture(glow_tex, UV).r * (1.0 - slope * 0.85);
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed + v_wpos.x * 0.35 + v_wpos.z * 0.27);
	EMISSION = glow_color * crack * glow_strength * COLOR.a * pulse;
}

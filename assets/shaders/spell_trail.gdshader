shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Comet tail on a cone (axis = mesh Y, wide end at +Y = head): alpha falls off along the length and breaks up with noise.

uniform vec4 mid : source_color = vec4(1.0, 0.4, 0.05, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform float length_m = 3.0;
uniform float energy = 2.0;
uniform float speed = 3.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying float t;

void vertex() {
	t = clamp(0.5 - VERTEX.y / length_m, 0.0, 1.0);
}

void fragment() {
	float n = texture(noise_tex, vec2(UV.x * 2.0, t * 1.6 + TIME * speed)).r;
	float a = pow(1.0 - t, 1.7) * (0.55 + n * 0.8);
	float fres = pow(clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.5);
	vec3 col = mix(mid.rgb, core.rgb, pow(1.0 - t, 3.0));
	ALBEDO = col * energy;
	ALPHA = clamp(a * (0.4 + fres * 0.6), 0.0, 1.0);
}

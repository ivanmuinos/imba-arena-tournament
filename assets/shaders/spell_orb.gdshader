shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
// Energy orb: hot core, fresnel rim and scrolling-noise breakup; `dissolve` (0..1) eats it away.

uniform vec4 core : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 mid : source_color = vec4(1.0, 0.4, 0.05, 1.0);
uniform vec4 edge : source_color = vec4(0.7, 0.1, 0.0, 1.0);
uniform float energy = 2.4;
uniform float speed = 1.4;
uniform float dissolve = 0.0;
uniform float fade = 1.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	float n = texture(noise_tex, UV * vec2(3.0, 2.0) + vec2(TIME * speed * 0.25, TIME * speed)).r;
	float body = 1.0 - fres;
	vec3 col = mix(mid.rgb, core.rgb, body * body);
	col = mix(col, edge.rgb, smoothstep(0.55, 1.0, fres) * 0.8);
	col *= 0.75 + n * 0.5;
	float cut = smoothstep(dissolve, dissolve + 0.18, n);
	ALBEDO = col * energy;
	ALPHA = clamp((0.55 + fres * 0.5) * cut * fade, 0.0, 1.0);
}

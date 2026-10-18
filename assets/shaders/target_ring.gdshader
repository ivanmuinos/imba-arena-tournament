shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// Big animated selection ring under the target: rotating dashes, soft inner glow and an expanding pulse.

uniform vec4 ring_color : source_color = vec4(1.0, 0.15, 0.1, 1.0);
uniform float intensity = 2.0;
uniform float dashes = 10.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ring = smoothstep(0.70, 0.74, r) * (1.0 - smoothstep(0.88, 0.92, r));
	float dash = step(0.35, fract(a * dashes / 6.2831853 + TIME * 0.18));
	float thin = smoothstep(0.93, 0.95, r) * (1.0 - smoothstep(0.97, 0.99, r));
	float pulse_r = 0.35 + fract(TIME * 0.7) * 0.55;
	float pulse = (1.0 - smoothstep(0.0, 0.06, abs(r - pulse_r))) * (1.0 - fract(TIME * 0.7)) * 0.7;
	float glow = (1.0 - smoothstep(0.0, 0.7, r)) * 0.18;
	float m = ring * mix(0.45, 1.0, dash) + thin * 0.8 + pulse + glow;
	m *= 1.0 - step(1.0, r);
	ALBEDO = ring_color.rgb * intensity * m;
	ALPHA = clamp(m, 0.0, 1.0);
}

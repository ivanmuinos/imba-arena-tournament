shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Ground effect decal on a quad: rotating dashed rim, pulsing fill and a growing "charge" ring (progress 0..1).

uniform vec4 color : source_color = vec4(1.0, 0.3, 0.05, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float fill = 0.22;
uniform float progress = 1.0;
uniform float fade = 1.0;
uniform float spin = 0.7;
uniform float rim = 0.06;
uniform float energy = 1.8;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float inside = step(r, 1.0);
	float edge = smoothstep(rim, 0.0, abs(r - 0.93));
	float dash = 0.35 + 0.65 * smoothstep(-0.2, 0.4, sin((a + TIME * spin) * 14.0));
	float inner = smoothstep(1.0, 0.0, r) * fill * (0.75 + 0.25 * sin(TIME * 4.0 - r * 7.0));
	float charge = smoothstep(rim * 0.8, 0.0, abs(r - progress * 0.93)) * 0.9;
	float spokes = smoothstep(0.82, 1.0, sin(a * 6.0 + TIME * spin * 2.0)) * smoothstep(0.2, 0.9, r) * (1.0 - smoothstep(0.9, 0.95, r)) * 0.25;
	float v = edge * dash + inner + charge + spokes;
	vec3 col = mix(color.rgb, core.rgb, clamp(edge * 0.5 + charge, 0.0, 1.0));
	ALBEDO = col * energy;
	ALPHA = clamp(v, 0.0, 1.0) * fade * inside;
}

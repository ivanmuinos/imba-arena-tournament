shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Weapon slash trail: a bright crescent whose head sweeps across the quad (progress 0..1) leaving a fading tail.

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform vec4 core : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress = 0.0;
uniform float fade = 1.0;
uniform float sweep = 2.6;     // total arc in radians
uniform float energy = 1.8;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.x, -p.y);                      // 0 straight up, +- sweep/2 at the ends
	float head = mix(-sweep * 0.5, sweep * 0.5, progress);
	float behind = head - a;                        // >0 behind the head
	float tail = clamp(1.0 - behind / (sweep * 0.7), 0.0, 1.0);
	float on_arc = step(0.0, behind) * step(a, head + 0.05) * step(-sweep * 0.5, a);
	float ring = smoothstep(0.55, 0.78, r) * (1.0 - smoothstep(0.92, 1.0, r));
	float thin = 1.0 - smoothstep(0.0, 0.16, abs(r - (0.72 + 0.2 * (1.0 - tail))));
	float v = on_arc * tail * tail * mix(ring, thin, 0.6);
	float hot = smoothstep(0.85, 1.0, tail) * on_arc;
	ALBEDO = mix(color.rgb, core.rgb, hot) * energy;
	ALPHA = clamp(v * 1.4, 0.0, 1.0) * fade;
}

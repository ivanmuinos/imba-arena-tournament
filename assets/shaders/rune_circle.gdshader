shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Casting circle under a caster: two thin rings, a band of rune-like marks turning one way, two triangles turning the
// other, and an arc on the outer ring that fills as the cast completes (`progress` 0..1).

uniform vec4 color : source_color = vec4(0.7, 0.4, 1.0, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.9, 1.0, 1.0);
uniform float progress = 0.0;
uniform float fade = 1.0;
uniform float energy = 1.5;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float line(float d, float w) {
	return 1.0 - smoothstep(0.0, w, abs(d));
}

// Distance from the centre to the edge of a triangle turned by `turn`, along the direction of angle `a`.
float tri(float a, float r, float turn) {
	float seg = 2.0943951;
	float k = a - turn;
	return cos(floor(0.5 + k / seg) * seg - k) * r;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float outer = line(r - 0.94, 0.025);
	float inner = line(r - 0.6, 0.018);
	// rune band: 18 cells between the rings, each with a mark made of 2-3 strokes picked by its number
	float cells = 18.0;
	float u = (a + TIME * 0.25) / 6.2831853 * cells;
	float id = floor(u);
	float fx = fract(u) - 0.5;
	float fr = (r - 0.77) / 0.11;
	float band = step(abs(fr), 1.0);
	float stem = line(fx, 0.09) * step(abs(fr), 0.8);
	float bar_hi = line(fr - 0.5, 0.22) * step(abs(fx), 0.3) * step(0.4, hash(id));
	float bar_lo = line(fr + 0.45, 0.22) * step(abs(fx), 0.3) * step(0.5, hash(id + 7.0));
	float slant = line(fx - fr * 0.3 * (hash(id + 3.0) - 0.5) * 2.0, 0.09) * step(0.6, hash(id + 11.0)) * step(abs(fr), 0.7);
	float runes = clamp(max(max(stem * step(0.25, hash(id + 1.0)), slant), max(bar_hi, bar_lo)), 0.0, 1.0) * band;
	// two triangles, counter-rotating
	float inside = step(r, 0.6);
	float tris = (line(tri(a, r, -TIME * 0.4) - 0.29, 0.014) + line(tri(a, r, 1.0471976 - TIME * 0.4) - 0.29, 0.014)) * inside;
	// progress arc on the outer ring, starting at the top
	float turn = fract((a + 1.5707963) / 6.2831853);
	float done = step(turn, progress);
	float glow = (1.0 - smoothstep(0.0, 1.0, r)) * 0.1;
	float v = outer * (0.35 + 0.9 * done) + inner * 0.6 + runes * 0.55 + tris * 0.5 + glow;
	vec3 col = mix(color.rgb, core.rgb, clamp(outer * done + tris * 0.3, 0.0, 1.0));
	ALBEDO = col * energy;
	ALPHA = clamp(v, 0.0, 1.0) * fade * (1.0 - step(1.0, r));
}

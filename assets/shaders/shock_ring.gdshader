shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Shockwave: a thin soft ring at the edge of the quad (the mesh is scaled up as it travels) with a faint wash inside.

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float fade = 1.0;
uniform float width = 0.14;
uniform float energy = 1.6;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float ring = smoothstep(1.0 - width * 2.2, 1.0 - width, r) * (1.0 - smoothstep(1.0 - width * 0.6, 1.0, r));
	float wash = smoothstep(0.1, 1.0 - width, r) * (1.0 - step(1.0, r)) * 0.1;
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(ring + wash, 0.0, 1.0) * fade;
}

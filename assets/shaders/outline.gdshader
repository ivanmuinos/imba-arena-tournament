shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
// Inverted-hull ink outline (second pass of every character material): back faces pushed out along the normal.

uniform vec4 ink : source_color = vec4(0.09, 0.045, 0.03, 1.0);
uniform float width = 0.018;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = ink.rgb;
}

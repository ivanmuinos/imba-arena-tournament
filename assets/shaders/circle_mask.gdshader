shader_type canvas_item;
// Shows a texture only inside the circle that fills its rect (portraits in the round frames of the HUD).
// zoom < 1 shrinks the picture inside the circle and rings it with an even band of `fill` (the square painted
// ability icons: the subject no longer fills the whole button).
uniform float zoom = 1.0;
uniform vec4 fill : source_color = vec4(0.09, 0.06, 0.05, 1.0);

void fragment() {
	vec2 uv = (UV - vec2(0.5)) / zoom + vec2(0.5);
	vec4 c = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
	float d = distance(UV, vec2(0.5));
	if (zoom < 1.0) {
		c = mix(c, fill, smoothstep(0.5 * zoom - 0.01, 0.5 * zoom + 0.01, d));
	}
	c *= COLOR;
	c.a *= 1.0 - smoothstep(0.48, 0.5, d);
	COLOR = c;
}

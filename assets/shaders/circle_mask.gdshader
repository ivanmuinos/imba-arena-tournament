shader_type canvas_item;
// Shows a texture only inside the circle that fills its rect (portraits in the round frames of the HUD).

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = distance(UV, vec2(0.5));
	c.a *= 1.0 - smoothstep(0.48, 0.5, d);
	COLOR = c;
}

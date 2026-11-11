shader_type canvas_item;
// A round window on the map image, centred on the player. Past the map's edge it shows the mountains' grey-green.

uniform sampler2D map_tex : filter_linear;
uniform vec2 center = vec2(0.5);
uniform float span = 0.25;  // radius of the window, in map uv
uniform vec3 beyond : source_color = vec3(0.16, 0.2, 0.14);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	vec2 uv = center + d * 2.0 * span;
	vec3 c = texture(map_tex, uv).rgb;
	float out_of_map = step(1.0, max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0);
	c = mix(c, beyond, out_of_map);
	c *= mix(1.0, 0.6, smoothstep(0.72, 1.0, r));
	COLOR = vec4(c, 1.0 - smoothstep(0.985, 1.0, r));
}

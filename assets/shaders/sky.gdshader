shader_type sky;
// Arena sky: a top-to-horizon gradient, the sun (disc + halo) where the directional light says it is, and a layer of
// soft clouds lit from the sun side. Static on purpose: a sky that animates re-renders its reflection map every frame.

uniform vec3 top_color : source_color = vec3(0.1, 0.15, 0.4);
uniform vec3 horizon_color : source_color = vec3(0.9, 0.6, 0.4);
uniform vec3 ground_color : source_color = vec3(0.2, 0.15, 0.12);
uniform vec3 cloud_color : source_color = vec3(1.0, 0.9, 0.85);
uniform sampler2D cloud_tex : repeat_enable, filter_linear_mipmap;
uniform float cloud_cover = 0.5;
uniform float sun_size = 1.0;

void sky() {
	vec3 d = EYEDIR;
	vec3 col = mix(horizon_color, top_color, pow(clamp(d.y, 0.0, 1.0), 0.5));
	col = mix(col, ground_color, smoothstep(0.0, -0.18, d.y));
	float sd = LIGHT0_ENABLED ? max(dot(d, LIGHT0_DIRECTION), 0.0) : 0.0;
	float disc = smoothstep(1.0 - 0.0009 * sun_size, 1.0 - 0.0005 * sun_size, sd);
	vec3 sun = LIGHT0_COLOR * (disc * 5.0 + pow(sd, 220.0) * 0.8 + pow(sd, 14.0) * 0.22);
	float cover = 0.0;
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.14);
		float n = texture(cloud_tex, uv * 0.07).r * 0.62 + texture(cloud_tex, uv * 0.19 + vec2(0.31, 0.57)).r * 0.38;
		cover = smoothstep(1.0 - cloud_cover, 1.25 - cloud_cover, n) * smoothstep(0.0, 0.16, d.y);
		vec3 lit = mix(cloud_color, LIGHT0_COLOR, 0.25 + 0.55 * pow(sd, 5.0));
		vec3 cloud = mix(mix(horizon_color, top_color, 0.5) * 0.75, lit, smoothstep(0.35, 0.95, n));
		col = mix(col + sun * (1.0 - cover), cloud + sun * 0.15, cover * 0.9);
	} else {
		col += sun * smoothstep(-0.05, 0.0, d.y);
	}
	COLOR = col;
}

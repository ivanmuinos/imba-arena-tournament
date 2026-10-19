shader_type spatial;
// Pet fur in two tones: `belly` below `lo`, `back` above `hi` (mesh-space height), blended in between.

uniform vec4 back : source_color = vec4(0.35, 0.32, 0.3, 1.0);
uniform vec4 belly : source_color = vec4(0.8, 0.76, 0.7, 1.0);
uniform float lo = 0.0;
uniform float hi = 1.0;
uniform float roughness = 0.85;

varying float h;

void vertex() {
	h = VERTEX.y;
}

void fragment() {
	ALBEDO = mix(belly.rgb, back.rgb, smoothstep(lo, hi, h));
	ROUGHNESS = roughness;
}

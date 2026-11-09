// Água escura de pântano/lago: ondulação procedural, fresnel e transparência por profundidade.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.04, 0.07, 0.07);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.2, 0.16);
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * 0.35;
	float t = TIME * 0.4;
	float e = 0.08;
	float h0 = vnoise(p + t) + vnoise(p * 2.3 - t * 1.3) * 0.5;
	float hx = vnoise(p + vec2(e, 0) + t) + vnoise((p + vec2(e, 0)) * 2.3 - t * 1.3) * 0.5;
	float hz = vnoise(p + vec2(0, e) + t) + vnoise((p + vec2(0, e)) * 2.3 - t * 1.3) * 0.5;
	vec3 n = normalize(vec3((h0 - hx) * 1.5, 1.0, (h0 - hz) * 1.5));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;

	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float thickness = clamp((-world.z) - (-VERTEX.z), 0.0, 10.0);
	float k = smoothstep(0.0, 2.5, thickness);
	ALBEDO = mix(shallow_color, deep_color, k);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALPHA = clamp(0.55 + k * 0.4 + fres * 0.3, 0.0, 0.97);
}

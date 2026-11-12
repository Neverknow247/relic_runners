shader_type canvas_item;

// Blood-potion liquid for the heart vial. Drawn on the white health_bar.png mask:
// the mask's alpha is the liquid's shape, everything else is generated here.
// The script (health_ui.gd) drives fill / ghost_fill / slosh.

uniform float fill : hint_range(0.0, 1.0) = 1.0;       // surface height, 0 = empty, 1 = full
uniform float ghost_fill : hint_range(0.0, 1.0) = 1.0; // lagging "just lost" level
uniform float slosh = 0.0;                              // 0..1, kicked on hit, decays
uniform float slosh_dir = 1.0;                          // which way the liquid tilts

// Liquid's vertical extent inside the 1280px canvas (from the mask's bounding box).
uniform float liquid_top = 0.372;
uniform float liquid_bottom = 0.882;

uniform vec4 deep_color : source_color = vec4(0.22, 0.0, 0.03, 1.0);
uniform vec4 mid_color : source_color = vec4(0.55, 0.02, 0.07, 1.0);
uniform vec4 surface_color : source_color = vec4(0.85, 0.12, 0.16, 1.0);
uniform vec4 ghost_color : source_color = vec4(1.0, 0.75, 0.75, 0.55);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float surface_at(float level, float x, float t) {
	float wave = sin(x * 14.0 + t * 1.8) * 0.004 + sin(x * 27.0 - t * 2.7) * 0.0025;
	wave += sin(x * 9.0 + t * 7.0) * 0.018 * slosh;
	wave += (x - 0.5) * 0.10 * slosh * slosh_dir * sin(t * 6.0);
	return level + wave;
}

void fragment() {
	float mask = texture(TEXTURE, UV).a;
	vec2 uv = UV;
	float t = TIME;
	float span = liquid_bottom - liquid_top;
	// Full overshoots the top a little so waves never show a gap at 100%.
	float level = mix(liquid_bottom + 0.004, liquid_top - 0.03, fill);
	float ghost_level = mix(liquid_bottom + 0.004, liquid_top - 0.03, max(ghost_fill, fill));

	float surface = surface_at(level, uv.x, t);
	float ghost_surface = surface_at(ghost_level, uv.x, t + 1.3);
	float d = uv.y - surface; // > 0 means below the surface (inside the liquid)

	vec4 col = vec4(0.0);
	if (d > 0.0 && fill > 0.0) {
		float depth = clamp(d / max(span, 0.001), 0.0, 1.0);
		vec3 c = mix(mid_color.rgb, deep_color.rgb, smoothstep(0.0, 0.9, depth));
		// Slow swirling murk.
		vec2 q = uv * vec2(6.0, 8.0) + vec2(t * 0.15, -t * 0.25);
		float n = noise(q + noise(q * 1.7 - t * 0.2) * 1.5);
		c *= 0.8 + 0.4 * n;
		// Darker toward the glass edges (fake volume), brighter down the middle.
		float edge = abs(uv.x - 0.5) * 2.0;
		c *= 1.0 - 0.35 * smoothstep(0.3, 0.75, edge);
		// Bright meniscus band right under the surface.
		float band = 1.0 - smoothstep(0.0, 0.025, d);
		c = mix(c, surface_color.rgb, band * 0.85);
		// Rising bubbles.
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float speed = 0.05 + hash(vec2(fi, 3.1)) * 0.07;
			float bx = 0.3 + hash(vec2(fi, 7.7)) * 0.4 + sin(t * 1.5 + fi) * 0.01;
			float prog = fract(t * speed + hash(vec2(fi, 1.9)));
			float by = mix(liquid_bottom, surface, prog);
			float r = 0.005 + hash(vec2(fi, 5.3)) * 0.006;
			float dist = length((uv - vec2(bx, by)) * vec2(1.0, 1.0));
			float ring = smoothstep(r, r * 0.6, dist) - smoothstep(r * 0.6, r * 0.2, dist) * 0.6;
			c += vec3(1.0, 0.45, 0.45) * ring * 0.45 * step(0.0, uv.y - surface - 0.01);
		}
		col = vec4(c, 1.0);
	} else if (uv.y > ghost_surface && ghost_fill > fill) {
		// Recently lost health: pale ghost liquid that drains away after a beat.
		col = ghost_color;
	}
	COLOR = vec4(col.rgb, col.a * mask);
}

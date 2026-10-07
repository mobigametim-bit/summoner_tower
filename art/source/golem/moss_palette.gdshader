shader_type canvas_item;

uniform bool recolor_enabled = false;
uniform vec4 moss_color : source_color = vec4(0.533333, 0.725490, 0.419608, 1.0);
uniform sampler2D moss_mask : filter_linear, repeat_disable;
varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	// Маска и исходный зелёный fill сохраняют камень, глаза и тёмный outline.
	bool moss = texel.g > texel.r * 1.15 && texel.g > texel.b * 1.3;
	if (recolor_enabled && moss) {
		float mask = texture(moss_mask, UV).a;
		float shade = texel.g / (185.0 / 255.0);
		vec3 recolored = clamp(moss_color.rgb * shade, vec3(0.0), vec3(1.0));
		texel.rgb = mix(texel.rgb, recolored, mask);
	}
	COLOR = texel * item_color;
}

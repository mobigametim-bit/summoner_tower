shader_type canvas_item;

uniform vec4 accent_color : source_color = vec4(0.533333, 0.725490, 0.419608, 1.0);
varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	// Только зелёные акценты новых деталей; металл, дерево, камень и outline фиксированы.
	bool accent = texel.g > texel.r * 1.15 && texel.g > texel.b * 1.3;
	if (accent) {
		float shade = texel.g / (185.0 / 255.0);
		texel.rgb = clamp(accent_color.rgb * shade, vec3(0.0), vec3(1.0));
	}
	COLOR = texel * item_color;
}

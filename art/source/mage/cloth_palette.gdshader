shader_type canvas_item;

uniform vec4 cloth_color : source_color = vec4(0.443, 0.569, 0.243, 1.0);
varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	// Только синие fills ткани; cyan crystal, золото, кожа и outline сохраняются.
	bool cloth = texel.b > texel.g * 1.4 && texel.b > texel.r * 1.8;
	if (cloth) {
		float shade = (texel.r + texel.g + texel.b) / (0.208 + 0.408 + 0.714);
		texel.rgb = clamp(cloth_color.rgb * shade, vec3(0.0), vec3(1.0));
	}
	COLOR = texel * item_color;
}

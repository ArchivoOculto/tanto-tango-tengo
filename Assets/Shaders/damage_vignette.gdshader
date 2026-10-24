shader_type canvas_item;
render_mode unshaded;

// Viñeta roja de daño: se enciende en los bordes de la pantalla y se apaga sola (ScreenFX anima 'intensity').
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.8, 0.02, 0.02, 1.0);
// Ventana de la imagen visible, en UV de pantalla (x, y, ancho, alto). Con las barras 4:3 la viñeta se ajusta a
// la imagen 4:3 y no a la pantalla entera (ScreenFX la mantiene al día).
uniform vec4 view_rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	vec2 c = ((SCREEN_UV - view_rect.xy) / view_rect.zw) * 2.0 - 1.0;
	float edge = smoothstep(0.35, 1.25, length(c * vec2(0.9, 1.0)));
	COLOR = vec4(color.rgb, edge * intensity * 0.85);
}

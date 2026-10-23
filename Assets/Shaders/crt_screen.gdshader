shader_type canvas_item;
render_mode unshaded;

// Curvatura del "tubo": más alto = más plano. 7 = muy curvo, 12-16 = sutil.
uniform float curvature : hint_range(4.0, 40.0) = 14.0;
// Oscurecimiento de las esquinas. Es MULTIPLICATIVO (0 = nada, 1 = esquinas negras): no se come las zonas oscuras.
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.40;
// Cuánto se notan las líneas de barrido y cuántas hay (240 = una cada 2 px de la imagen base de 480).
uniform float scanline_strength : hint_range(0.0, 0.5) = 0.07;
uniform float scanline_count = 240.0;
// Separación de colores en los bordes (px de la imagen base). 0 = apagado.
uniform float chroma_px : hint_range(0.0, 3.0) = 0.6;

// "Ventana" del tubo dentro de la pantalla, en UV de pantalla (x, y, ancho, alto). Por defecto, toda la pantalla.
// ScreenFX la anima al activar las barras 4:3 para que la curvatura y la viñeta se calculen sobre la imagen
// que realmente se ve. Fuera de la ventana (bajo las barras) la imagen pasa intacta.
uniform vec4 view_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Pulso de distorsión (0 = nada, 1 = máximo): más curvatura, aberración, líneas y una ondulación horizontal.
// ScreenFX lo anima al teletransportarse.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

void fragment() {
	vec2 local = (SCREEN_UV - view_rect.xy) / view_rect.zw;
	float in_rect = step(0.0, local.x) * step(local.x, 1.0) * step(0.0, local.y) * step(local.y, 1.0);

	vec2 c = local * 2.0 - 1.0;
	float curv = mix(curvature, curvature * 0.4, pulse);
	vec2 warp = c.yx / curv;
	vec2 w = c + c * warp * warp;
	w.x += sin(w.y * 38.0 + TIME * 30.0) * 0.006 * pulse;
	float inside = step(abs(w.x), 1.0) * step(abs(w.y), 1.0);
	vec2 uv = view_rect.xy + (w + 1.0) * 0.5 * view_rect.zw;

	// aberración cromática: crece hacia los bordes
	vec2 px = vec2(chroma_px * (1.0 + pulse * 5.0)) / vec2(textureSize(screen_texture, 0));
	vec2 off = c * px;
	vec3 col = vec3(
		texture(screen_texture, uv + off).r,
		texture(screen_texture, uv).g,
		texture(screen_texture, uv - off).b);

	// la densidad de líneas se mantiene aunque la ventana sea más baja que la pantalla
	float scan_str = scanline_strength * (1.0 + pulse * 2.0);
	float scan = 1.0 - scan_str * (0.5 + 0.5 * sin(w.y * scanline_count * view_rect.w * 3.14159265));
	float vig = (pow(abs(c.x), 4.0) + pow(abs(c.y), 4.0)) * 0.5;
	col *= scan * (1.0 - vignette_strength * vig) * inside * (1.0 + pulse * 0.25);
	// fuera de la ventana (bajo las barras 4:3) la imagen pasa sin filtrar
	COLOR = vec4(mix(texture(screen_texture, SCREEN_UV).rgb, col, in_rect), 1.0);
}

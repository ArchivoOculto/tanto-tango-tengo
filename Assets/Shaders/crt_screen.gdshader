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

// Aberración cromática extra y momentánea (px de la imagen base). ScreenFX la dispara al recibir daño.
uniform float chroma_boost : hint_range(0.0, 12.0) = 0.0;
// Encendido (1) y apagado (0) del tubo: al apagarse la imagen se aplasta en una línea brillante, la línea se
// encoge hasta un punto y el punto se apaga. ScreenFX lo anima al salir del juego.
uniform float power : hint_range(0.0, 1.0) = 1.0;
// Señal perdida (0 = nada, 1 = máximo): bandas que se desgarran, desfasaje de color, rodillo vertical, nieve y
// parpadeo. ScreenFX lo anima al empezar una partida nueva.
uniform float glitch : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 local = (SCREEN_UV - view_rect.xy) / view_rect.zw;
	float in_rect = step(0.0, local.x) * step(local.x, 1.0) * step(0.0, local.y) * step(local.y, 1.0);

	vec2 c = local * 2.0 - 1.0;
	float curv = mix(curvature, curvature * 0.4, pulse);
	vec2 warp = c.yx / curv;
	vec2 w = c + c * warp * warp;
	w.x += sin(w.y * 38.0 + TIME * 30.0) * 0.006 * pulse;
	float inside = step(abs(w.x), 1.0) * step(abs(w.y), 1.0);
	float wy = w.y; // sin aplastar: las líneas de barrido y la viñeta no deben depender del apagado

	// Apagado / encendido: primero se cierra en vertical hasta una línea, después en horizontal hasta un punto
	float vy = smoothstep(0.5, 1.0, power);
	float half_h = mix(0.004, 1.0, vy * vy);
	float half_w = smoothstep(0.0, 0.5, power);
	float on_mask = step(abs(w.y), half_h) * step(abs(w.x), half_w);
	w.y /= half_h;

	// Glitch: desgarro por bandas (cada banda se desplaza o no, al azar, 24 veces por segundo) y rodillo vertical
	float tick = floor(TIME * 24.0);
	float row = floor(c.y * 18.0);
	float torn = step(1.0 - glitch * 0.6, hash(vec2(row, tick)));
	w.x += torn * (hash(vec2(row, tick + 7.0)) - 0.5) * 0.4 * glitch;
	w.y += sin(TIME * 9.0) * glitch * glitch * 0.3;
	vec2 uv = view_rect.xy + (w + 1.0) * 0.5 * view_rect.zw;

	// aberración cromática: crece hacia los bordes (y se desfasa en horizontal con el glitch)
	vec2 texel = 1.0 / vec2(textureSize(screen_texture, 0));
	float chroma = chroma_px * (1.0 + pulse * 5.0) + chroma_boost + glitch * 6.0;
	vec2 off = c * chroma * texel + vec2(glitch * 3.0 * texel.x, 0.0);
	vec3 col = vec3(
		texture(screen_texture, uv + off).r,
		texture(screen_texture, uv).g,
		texture(screen_texture, uv - off).b);

	// glitch: nieve y parpadeo
	col += (hash(local * vec2(845.0, 480.0) + fract(TIME)) - 0.5) * glitch * 0.7;
	col *= 1.0 + (hash(vec2(tick, 3.0)) - 0.5) * glitch * 0.5;

	// la franja que queda al apagar es incandescente, y el punto final se apaga
	float collapse = 1.0 - vy;
	col = mix(col, vec3(1.0), collapse * 0.9) * (1.0 + collapse * 3.0);
	col *= smoothstep(0.0, 0.12, power);

	// la densidad de líneas se mantiene aunque la ventana sea más baja que la pantalla
	float scan_str = scanline_strength * (1.0 + pulse * 2.0);
	float scan = 1.0 - scan_str * (0.5 + 0.5 * sin(wy * scanline_count * view_rect.w * 3.14159265));
	float vig = (pow(abs(c.x), 4.0) + pow(abs(c.y), 4.0)) * 0.5;
	col *= scan * (1.0 - vignette_strength * vig) * inside * on_mask * (1.0 + pulse * 0.25);

	// fuera de la ventana (bajo las barras 4:3) la imagen pasa sin filtrar, salvo que el tubo esté apagado
	vec3 plain = texture(screen_texture, SCREEN_UV).rgb * step(0.999, power);
	COLOR = vec4(mix(plain, col, in_rect), 1.0);
}

#version 460 core
#include <flutter/runtime_effect.glsl>

// Vetro spesso con bordi arrotondati, senza sfocatura.
// Coordinate in pixel fisici della finestra.
uniform vec2 uSize;      // dimensione della texture (impostata dal motore)
uniform vec4 uRect;      // lastra: x, y, larghezza, altezza
uniform float uRadius;   // raggio degli angoli
uniform float uBezel;    // larghezza della zona curva lungo i bordi
uniform float uDensity;  // 0 = lastra sottile, 1 = pannello con molto testo
uniform sampler2D uTex;

out vec4 fragColor;

float sdRoundBox(vec2 q, vec2 b, float r) {
  vec2 d = abs(q) - b + vec2(r);
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

vec3 sampleAt(vec2 p) {
  vec2 uv = clamp(p / uSize, vec2(0.0), vec2(1.0));
#ifdef GLASS_FLIP_Y
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTex, uv).rgb;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 half_ = uRect.zw * 0.5;
  vec2 c = uRect.xy + half_;
  vec2 q = p - c;
  float r = min(uRadius, min(half_.x, half_.y));
  float d = sdRoundBox(q, half_, r);

  // Normale del bordo (verso l'esterno) dal gradiente della distanza.
  float e = 1.0;
  vec2 n = vec2(
    sdRoundBox(q + vec2(e, 0.0), half_, r) - sdRoundBox(q - vec2(e, 0.0), half_, r),
    sdRoundBox(q + vec2(0.0, e), half_, r) - sdRoundBox(q - vec2(0.0, e), half_, r));
  n = length(n) > 0.0001 ? normalize(n) : vec2(0.0);

  // Profilo del bordo: un quarto di cerchio (0 sul filo, 1 dove è piano).
  float b = max(uBezel, 1.0);
  float t = clamp(-d / b, 0.0, 1.0);
  float u = 1.0 - t;
  float h = sqrt(max(1.0 - u * u, 0.0));
  float slope = u / max(h, 0.08);

  // Rifrazione: verso il bordo il vetro piega la luce e si vede ciò che sta
  // più all'interno, compresso. Al centro un lievissimo ingrandimento.
  float bend = b * 1.1 * (1.0 - h);
  vec2 base = c + q * 0.985;
  vec2 dir = -n;
  vec3 col;
  col.r = sampleAt(base + dir * bend * 0.92).r;
  col.g = sampleAt(base + dir * bend * 1.00).g;
  col.b = sampleAt(base + dir * bend * 1.10).b;

  // Normale 3D della superficie: dove il vetro curva verso il bordo
  // riflette più ambiente (Fresnel). La luce viene dall'alto a sinistra:
  // il filo superiore è il più vivo, quello inferiore si accende per
  // riflessione interna, più debole.
  vec3 N = normalize(vec3(n * slope, 1.0));
  float fres = pow(1.0 - N.z, 2.6);
  float lit = max(dot(n, normalize(vec2(-0.35, -1.0))), 0.0);
  float back = max(dot(n, normalize(vec2(0.35, 1.0))), 0.0);
  float glow = fres * (0.18 + 0.85 * lit + 0.45 * back);

  // Assorbimento minimo del vetro, un po' di più dove c'è testo.
  float absorb = mix(0.95, 0.66, uDensity);
  col *= absorb;
  col = mix(col, vec3(1.0), clamp(glow, 0.0, 0.9));

  // Filo luminoso sottilissimo sul bordo esterno.
  float rim = smoothstep(1.6, 0.0, -d) * 0.35;
  col = mix(col, vec3(1.0), rim);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}

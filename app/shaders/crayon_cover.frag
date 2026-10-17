// Crayon's covers (mood board, 9 Oct): the real cover drawn as line art on
// paper, coloured in with crayon from the left as the song plays.
//
// Used as an ImageFilter over the drawn artwork, so the engine binds the
// size (first vec2) and the artwork texture (first sampler2D).
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uProgress; // 0..1, how much is coloured in
uniform float uDark;     // 1 on the chalkboard (dark Crayon)
uniform sampler2D uImage;

out vec4 fragColor;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 tex(vec2 uv) { return texture(uImage, uv).rgb; }

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  float a = texture(uImage, uv).a;
  vec2 px = 1.6 / uSize;

  // Sobel on brightness: where the cover changes, an ink line.
  float tl = luma(tex(uv + px * vec2(-1, -1)));
  float t = luma(tex(uv + px * vec2(0, -1)));
  float tr = luma(tex(uv + px * vec2(1, -1)));
  float l = luma(tex(uv + px * vec2(-1, 0)));
  float r = luma(tex(uv + px * vec2(1, 0)));
  float bl = luma(tex(uv + px * vec2(-1, 1)));
  float b = luma(tex(uv + px * vec2(0, 1)));
  float br = luma(tex(uv + px * vec2(1, 1)));
  float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
  float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
  float edge = smoothstep(0.18, 0.55, length(vec2(gx, gy)));

  // A few flat crayons, not a photo: posterised, then pushed bright and
  // saturated, because crayon is never darker than the paper allows (a
  // dark cover would otherwise fill in as mud).
  vec3 c = tex(uv);
  vec3 crayon = floor(c * 4.0 + 0.5) / 4.0;
  float y = luma(crayon);
  crayon = clamp(mix(vec3(y), crayon, 1.6), 0.0, 1.0);
  crayon = mix(crayon, vec3(1.0), 0.18 + 0.25 * (1.0 - y));
  crayon = max(crayon, vec3(0.32));

  // Crayon on paper never covers it fully: the paper's tooth shows through
  // softly, in strokes rather than pixels.
  float tooth = hash(floor(vec2(frag.x / 3.0, frag.y / 1.5 + frag.x * 0.3)));
  float laid = mix(0.72, 1.0, smoothstep(0.15, 0.6, tooth));

  // Coloured in from the left, along a wobbly edge.
  float wobble = sin(uv.y * 23.0) * 0.012 + sin(uv.y * 61.0) * 0.005;
  float filled = 1.0 - smoothstep(uProgress - 0.01, uProgress + 0.01, uv.x + wobble);

  vec3 paper = mix(vec3(1.0, 0.984, 0.949), vec3(0.145, 0.133, 0.227), uDark);
  vec3 ink = mix(vec3(0.133, 0.125, 0.11), vec3(0.965, 0.945, 0.902), uDark);

  vec3 col = mix(paper, crayon, filled * laid * 0.9);
  col = mix(col, ink, edge * 0.9);
  fragColor = vec4(col * a, a);
}

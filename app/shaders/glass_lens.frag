// Glass's lens: the page behind a floating pane bends at the pane's rounded
// rim, as it would through a thick piece of glass, with a faint colour
// fringe. Run as a backdrop filter after the blur (core/ui/glass.dart).
//
// Coordinates are physical pixels in the backdrop texture. The engine sets
// u_size and u_texture; the rest are set per frame from where the pane is.

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;       // the backdrop texture (engine)
uniform vec2 u_origin;     // the pane's top-left
uniform vec2 u_pane;       // the pane's size
uniform float u_radius;    // its corner radius
uniform float u_bend;      // how far the rim pulls the page, at most
uniform float u_rim;       // how wide the bending band is
uniform float u_fringe;    // the colour split at the rim

uniform sampler2D u_texture;

out vec4 frag_color;

// Signed distance to a rounded box centred on the origin: negative inside.
float roundBox(vec2 p, vec2 half_size, float r) {
  vec2 q = abs(p) - half_size + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec4 sampleAt(vec2 px) {
  vec2 uv = px / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(u_texture, uv);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 half_size = u_pane * 0.5;
  vec2 p = px - (u_origin + half_size);
  float r = min(u_radius, min(half_size.x, half_size.y));
  float d = roundBox(p, half_size, r);
  if (d > 0.0) {
    frag_color = sampleAt(px);
    return;
  }
  // The outward normal, from the distance field's slope.
  vec2 e = vec2(1.0, 0.0);
  vec2 n = vec2(
    roundBox(p + e.xy, half_size, r) - roundBox(p - e.xy, half_size, r),
    roundBox(p + e.yx, half_size, r) - roundBox(p - e.yx, half_size, r)
  );
  n = n / max(length(n), 1e-4);
  // 1 at the rim, easing to 0 a rim's width in: the glass is flat inside.
  float depth = clamp(-d / max(u_rim, 1.0), 0.0, 1.0);
  float lens = (1.0 - depth) * (1.0 - depth);
  vec2 shift = n * lens * u_bend;
  vec2 split = n * lens * u_fringe;
  // Sample inward of where we are, so the page appears pulled out to the
  // rim, magnified as through a curved edge.
  float red = sampleAt(px - shift - split).r;
  vec4 mid = sampleAt(px - shift);
  float blue = sampleAt(px - shift + split).b;
  frag_color = vec4(red, mid.g, blue, mid.a);
}

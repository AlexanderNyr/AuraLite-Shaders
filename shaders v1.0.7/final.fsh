#version 460 compatibility
// AuraLite Shaders v1.0.7 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Final Post-Processing Pass Fragment Shader (GLSL 460)
// [v1.0.7] Fixed glass & ice water distortion bug via colortex2 tag (0.8) & added clean underwater screen ripple.
// ==============================================================================
// [v1.0.3] Bypass colortex6 entirely. On Iris 1.20 the multi-target write in
//   composite.fsh (DRAWBUFFERS:06) does not reliably land in colortex6 when the
//   shader is read by final, so SSR silently failed. We now read the surface
//   normal directly from colortex2 (written by every gbuffer pass) and derive
//   reflectivity from colortex1.z (PBR roughness). This is the same data path
//   used for PBR specular highlights, which are confirmed working.

#define VIGNETTE // [true false]
#define EXPOSURE 2 // [1 2 3]
#define COLOR_SATURATION 2 // [1 2 3 4]
#define CONTRAST 2 // [1 2 3 4]
#define SSR // [true false]
#define SSR_QUALITY 2 // [1 2 3]
#define SSR_STRENGTH 2 // [1 2 3]
#define WATER_WAVE_SCALE 2     // [1 2 3 4] - 1: Calm, 2: Standard, 3: Choppy, 4: Stormy (visible wave amplitude)
#define WATER_WAVE_DETAIL 2    // [1 2 3] - 1: Coarse few waves, 2: Standard, 3: Dense many small waves

// ==============================================================================
// SPATIAL ANTI-ALIASING — Select post-process AA mode
// 0: Off — no spatial AA (TAA-only or nothing)
// 1: FXAA — Fast Approximate AA (Timothy Lottes, NVIDIA). Cheap, effective.
// 2: SMAA — Subpixel Morphological AA (Jorge Jimenez, SIGGRAPH 2012). Depth + luma edge detection.
// Can be freely combined with TAA (composite1 pass) for temporal + spatial smoothing.
// ==============================================================================
#define SPATIAL_AA_MODE 1 // [0 1 2] - 0: Off, 1: FXAA (Fast), 2: SMAA (Quality)

// ==============================================================================
// HEAT SHIMMER ABOVE LAVA — [v1.0.6]
// Toggle and strength control for the heat distortion post-effect.
// ==============================================================================
#define HEAT_SHIMMER          // [true false]
#define HEAT_SHIMMER_STRENGTH 2 // [1 2 3] - 1: Subtle, 2: Balanced, 3: Strong

// [DIAG] 0 = off, 1 = show reflectivity, 2 = show normal, 3 = force-reflect everything, 4 = ray direction, 5 = mirror UV
#define SSR_DEBUG 0 // [0 1 2 3 4 5]

in vec2 texcoord;

uniform sampler2D colortex0; // Fully lit scene (post composite)
uniform sampler2D colortex1; // lightmap.xy, roughness.z, metalness.w
uniform sampler2D colortex2; // view-space normal.xyz, emissive flag.a
uniform sampler2D depthtex0; // depth WITH translucent (water, glass, ice)
uniform sampler2D depthtex1; // depth WITHOUT translucent (terrain only)
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelViewInverse;
uniform int isEyeInWater; // 0 = air, 1 = water, 2 = lava

layout(location = 0) out vec4 fragColor;

// ---------- Tonemap & color ----------
vec3 ACESFilm(vec3 x) {
    float a = 2.51; float b = 0.03; float c = 2.43; float d = 0.59; float e = 0.14;
    return clamp((x * ((a) * (x) + (b))) / ((x) * (((c) * (x) + (d))) + (e)), 0.0, 1.0);
}

// [v1.0.3] Photographic (AgX-like) tone mapping.
// Sigmoidal curve with natural highlight desaturation inspired by AgX / Filmlight.
// Keeps foliage saturation under control while giving a cinematic, non-crushed look.
vec3 tonemapPhotographic(vec3 x) {
    // Exposure bias: AgX Base expects ~0.5–0.6 mid-grey at 18%.
    x *= 0.65;

    // --- Highlight chromatic attenuation (AgX signature) ---
    // As luminance grows beyond mid-grey, compress chroma toward
    // the achromatic axis to avoid neon/clip artefacts.
    float luma = dot(x, vec3(0.2126, 0.7152, 0.0722));
    vec3 chroma = x - vec3(luma);
    // Roll-off starts around luma=0.35, almost fully desaturated at 2.0+
    float desatFactor = pow(smoothstep(0.35, 2.2, luma), 1.4);
    x = vec3(luma) + chroma * mix(1.0, 0.35, desatFactor);

    // --- Sigmoid (Hable/Hejl-inspired with better toe) ---
    // Polynomial rational fit tuned for pleasing skin-tone and sky behaviour.
    vec3 num = x * (x * (x * 1.55 + 0.75) + 0.20) + 0.018;
    vec3 den = x * (x * (x * 1.35 + 0.65) + 0.50) + 0.13;
    x = num / den - 0.018 / 0.13;

    // Soft sRGB output gamma tweak (slightly lifted blacks, not harsh)
    x = pow(max(x, vec3(0.0)), vec3(0.95));
    return clamp(x, 0.0, 1.0);
}

vec3 applyVibrancy(vec3 color, float amount) {
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    vec3 diff = color - vec3(luma);
    // [FIX v1.0.3] Negative amount now properly oversaturates instead of
    // relying on undefined GLSL mix extrapolation + hard clamping.
    return clamp(((diff) * (1.0 - amount) + (vec3(luma))), 0.0, 1.0);
}

// ---------- Coord transforms ----------
vec3 screenToView(vec2 uv, float depth) {
    vec4 ndc = vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * ndc;
    return view.xyz / view.w;
}
vec3 viewToScreen(vec3 view) {
    vec4 clip = gbufferProjection * vec4(view, 1.0);
    return clip.xyz / clip.w * 0.5 + 0.5;
}

float edgeFade(vec2 uv) {
    vec2 e = smoothstep(vec2(0.0), vec2(0.04), uv) *
             (1.0 - smoothstep(vec2(0.96), vec2(1.0), uv));
    return e.x * e.y;
}

// ---------- Smooth animated water ripples ----------
// [v1.0.3] Multi-octave fBm with quintic smoothstep. The combination
// of higher frequency and 4 octaves gives many more small waves with no
// triangular/blocky artifacts. We derive the wave normal as the analytic
// gradient of the height-field, not from random offsets — this gives a
// physically coherent normal direction (waves always slope correctly),
// not a noisy direction that "tears" reflections.
float wHash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
// Quintic smoothstep (6t^5 - 15t^4 + 10t^3) — C2-continuous, eliminates
// the visible "block edges" you get with the cubic (3t^2 - 2t^3) variant.
float wNoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(wHash(i),               wHash(i + vec2(1,0)), u.x),
               mix(wHash(i + vec2(0,1)),   wHash(i + vec2(1,1)), u.x), u.y);
}
// fBm: 4 octaves, each at 2x frequency and 0.5 amplitude, rotated to
// hide the underlying grid. Returns scalar height in [0,1].
const mat2 waterRotMat = mat2(0.84, 0.54, -0.54, 0.84); // ~33° per octave

// fBm: 4 octaves, each at 2x frequency and 0.5 amplitude, rotated to
// hide the underlying grid. Returns scalar height in [0,1].
float waterHeight(vec2 p, vec2 d1, vec2 d2, vec2 d3, vec2 d4) {
    float h = 0.0, a = 0.5;
    // Base wave frequency — controlled by WATER_WAVE_DETAIL menu option.
    float waveFreq = 0.9;
    #if WATER_WAVE_DETAIL == 1
    waveFreq = 0.45;  // coarse, fewer big waves
    #elif WATER_WAVE_DETAIL == 3
    waveFreq = 1.55;  // dense, many tiny waves
    #endif
    p *= waveFreq;
    h += wNoise(p +  d1) * a; p = waterRotMat * p * 2.03; a *= 0.55;
    h += wNoise(p +  d2) * a; p = waterRotMat * p * 2.07; a *= 0.55;
    h += wNoise(p +  d3) * a; p = waterRotMat * p * 2.11; a *= 0.55;
    h += wNoise(p +  d4) * a;
    return h;
}
// Analytic gradient of the height-field — gives the *correct* slope of
// waves so reflections move smoothly with the wave instead of jittering.
// Uses 4-sample central differences in WORLD coordinates → resolution
// independent and tiny artifacts.
vec2 waterRippleOffset(vec2 worldXZ, float t) {
    float e = 0.08; // sample epsilon in world units (smaller = finer detail)
    vec2 d1 = vec2( 0.42,  0.18) * t;
    vec2 d2 = vec2(-0.31,  0.27) * t;
    vec2 d3 = vec2( 0.17, -0.34) * t;
    vec2 d4 = vec2(-0.22, -0.15) * t;
    float hx1 = waterHeight(worldXZ + vec2( e, 0.0), d1, d2, d3, d4);
    float hx0 = waterHeight(worldXZ + vec2(-e, 0.0), d1, d2, d3, d4);
    float hz1 = waterHeight(worldXZ + vec2( 0.0,  e), d1, d2, d3, d4);
    float hz0 = waterHeight(worldXZ + vec2( 0.0, -e), d1, d2, d3, d4);
    // Gradient of the height-field. Negate so peaks slope outward.
    return vec2(hx1 - hx0, hz1 - hz0) / (2.0 * e);
}

// ==============================================================================
// SSR — view-space adaptive march with binary refinement.
//
// Implementation notes (original to AuraLite v0.2.9):
//   Standard textbook screen-space reflection: march the reflected ray in
//   view space, projecting each sample into screen space to compare against
//   the depth buffer. When a crossing is detected, refine the hit point
//   with a few binary-search steps. The marching step adapts to how far
//   the marker is from the visible surface, so long stretches of empty
//   space are skipped quickly.
//
//   This is the same family of techniques described in countless real-time
//   rendering references (Heitz, Hennessy, Crassin; "Real-Time Rendering"
//   4th ed., chapter on screen-space methods). It has been the de facto
//   standard for SSR since the early 2010s.
// ==============================================================================
#ifdef SSR
vec4 traceSSR(vec3 viewPos, vec3 R, vec3 N) {
    int   maxSteps    = 24;
    int   refineSteps = 5;
    float stepScale   = 1.30;
    #if SSR_QUALITY == 1
    maxSteps = 14; refineSteps = 4; stepScale = 1.55;
    #elif SSR_QUALITY == 3
    maxSteps = 40; refineSteps = 7; stepScale = 1.10;
    #endif

    // Reject rays going back toward the camera — they cannot hit anything
    // that's actually visible on screen.
    if (R.z >= -0.05) return vec4(0.0);

    float invRz    = 1.0 / abs(R.z);
    float invFar2  = 1.0 / (2.0 * far);
    float marchT   = 1.0;            // start a small distance off the surface
    vec3  prevPos  = viewPos;

    for (int i = 0; i < 64; ++i) {
        if (i >= maxSteps) break;

        vec3 here    = viewPos + R * marchT;
        vec3 hereScr = viewToScreen(here);

        if (hereScr.x < 0.0 || hereScr.x > 1.0 ||
            hereScr.y < 0.0 || hereScr.y > 1.0) break;

        float sceneDepth = texture(depthtex0, hereScr.xy).r;
        float sceneZ     = screenToView(hereScr.xy, sceneDepth).z;

        // Distance-aware tolerance: tiny near the camera, slightly larger
        // far away. Prevents Z-fighting on distant samples.
        float distEps = clamp(abs(sceneZ) * invFar2, 0.0, 1.0);
        float zTol    = 1.0 + 0.1 * distEps;
        float gap     = here.z - sceneZ * zTol;

        if (gap < 0.0) {
            // Marker is now behind the visible geometry — there's a hit
            // somewhere between prevPos and here. Refine with binary search.
            vec3 a = prevPos, b = here;
            if (gap > -16.0) {
                for (int j = 0; j < 8; ++j) {
                    if (j >= refineSteps) break;
                    vec3 mid  = (a + b) * 0.5;
                    vec3 mScr = viewToScreen(mid);
                    float mDepth = texture(depthtex0, mScr.xy).r;
                    float mSceneZ = screenToView(mScr.xy, mDepth).z;
                    if (-mid.z < -mSceneZ) a = mid;
                    else                   b = mid;
                }
            }
            vec3 hit = viewToScreen((a + b) * 0.5);
            if (hit.x < 0.002 || hit.x > 0.998 ||
                hit.y < 0.002 || hit.y > 0.998) break;

            float hitDepth = texture(depthtex0, hit.xy).r;
            if (hitDepth >= 1.0) break;          // hit the sky — bail out

            vec3 hitColor = texture(colortex0, hit.xy).rgb;

            // Schlick Fresnel with F0 = 0.02 (clean dielectric water).
            vec3 V = normalize(-viewPos);
            float NoV = clamp(dot(N, V), 0.0, 1.0);
            float fresnel = clamp(0.02 + 0.98 * pow(1.0 - NoV, 5.0),
                                   0.05, 1.0);

            return vec4(hitColor, edgeFade(hit.xy) * fresnel);
        }

        prevPos = here;
        // Adaptive step — jump proportional to how far away from the
        // visible surface the marker currently sits. [FIX v1.0.3] Lowered
        // minimum from 1.0 to 0.3 view-space units for better near-field hit rate.
        marchT += max(stepScale * abs(gap) * invRz, 0.3);
    }
    return vec4(0.0);
}
#endif

// ==============================================================================
// FXAA — Conservative edge-only anti-aliasing (gradient-directed)
// Only processes actual high-contrast edges with very low blend weight.
// Subpixel weight kept very low to avoid washing out the entire image.
// ==============================================================================
#if SPATIAL_AA_MODE == 1
vec3 applyFXAA(vec2 uv, vec3 centerColor, float expFac) {
    vec2 px = 1.0 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    const vec3 L = vec3(0.2126, 0.7152, 0.0722);

    float lC  = dot(centerColor, L);
    float lN  = dot(texture(colortex0, uv + vec2( 0,    -px.y)).rgb * expFac, L);
    float lS  = dot(texture(colortex0, uv + vec2( 0,     px.y)).rgb * expFac, L);
    float lW  = dot(texture(colortex0, uv + vec2(-px.x,  0)).rgb * expFac, L);
    float lE  = dot(texture(colortex0, uv + vec2( px.x,  0)).rgb * expFac, L);
    float lNW = dot(texture(colortex0, uv + vec2(-px.x, -px.y)).rgb * expFac, L);
    float lNE = dot(texture(colortex0, uv + vec2( px.x, -px.y)).rgb * expFac, L);
    float lSW = dot(texture(colortex0, uv + vec2(-px.x,  px.y)).rgb * expFac, L);
    float lSE = dot(texture(colortex0, uv + vec2( px.x,  px.y)).rgb * expFac, L);

    float lMin   = min(lC, min(min(lN, lS), min(lW, lE)));
    float lMax   = max(lC, max(max(lN, lS), max(lW, lE)));
    float lRange = lMax - lMin;

    // High threshold - only process real edges, skip subtle variations
    if (lRange < 0.15) return centerColor;

    // Sobel gradient direction (points across the edge toward bright side)
    float gx = (lNE + 2.0 * lE + lSE) - (lNW + 2.0 * lW + lSW);
    float gy = (lSW + 2.0 * lS + lSE) - (lNW + 2.0 * lN + lNE);

    float gLen = max(length(vec2(gx, gy)), 1e-5);
    vec2 dir = vec2(gx, gy) / gLen;

    // Sample across the edge in gradient direction
    vec3 cPos = texture(colortex0, clamp(uv + dir * px, vec2(0.001), vec2(0.999))).rgb * expFac;
    vec3 cNeg = texture(colortex0, clamp(uv - dir * px, vec2(0.001), vec2(0.999))).rgb * expFac;
    float lPos = dot(cPos, L);
    float lNeg = dot(cNeg, L);

    // Pick the side of the edge most different from center
    float dPos = abs(lPos - lC);
    float dNeg = abs(lNeg - lC);
    vec3  blendColor = dPos >= dNeg ? cPos : cNeg;

    // Very conservative weight - only a subtle softening
    float edgeWeight = clamp(max(dPos, dNeg) / (lRange + 1e-5) * 0.15, 0.0, 0.15);

    return mix(centerColor, blendColor, edgeWeight);
}
#endif

// ==============================================================================
// SMAA-like — Conservative edge AA with depth awareness
// Same gradient-directed approach as FXAA but adds depth edge detection
// for geometry edges where luma contrast may be low. Very low blend weight.
// ==============================================================================
#if SPATIAL_AA_MODE == 2
vec3 applySMAA(vec2 uv, vec3 centerColor, float expFac) {
    vec2 px = 1.0 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    const vec3 L = vec3(0.2126, 0.7152, 0.0722);

    float lC  = dot(centerColor, L);
    float lN  = dot(texture(colortex0, uv + vec2( 0,    -px.y)).rgb * expFac, L);
    float lS  = dot(texture(colortex0, uv + vec2( 0,     px.y)).rgb * expFac, L);
    float lW  = dot(texture(colortex0, uv + vec2(-px.x,  0)).rgb * expFac, L);
    float lE  = dot(texture(colortex0, uv + vec2( px.x,  0)).rgb * expFac, L);
    float lNW = dot(texture(colortex0, uv + vec2(-px.x, -px.y)).rgb * expFac, L);
    float lNE = dot(texture(colortex0, uv + vec2( px.x, -px.y)).rgb * expFac, L);
    float lSW = dot(texture(colortex0, uv + vec2(-px.x,  px.y)).rgb * expFac, L);
    float lSE = dot(texture(colortex0, uv + vec2( px.x,  px.y)).rgb * expFac, L);

    float lMin = min(lC, min(min(lN, lS), min(lW, lE)));
    float lMax = max(lC, max(max(lN, lS), max(lW, lE)));
    float lRange = lMax - lMin;

    // Depth neighborhood
    float dC = texture(depthtex0, uv).r;
    float dN = texture(depthtex0, uv + vec2( 0,    -px.y)).r;
    float dS = texture(depthtex0, uv + vec2( 0,     px.y)).r;
    float dW = texture(depthtex0, uv + vec2(-px.x,  0)).r;
    float dE = texture(depthtex0, uv + vec2( px.x,  0)).r;

    bool hasLumaEdge  = lRange > 0.10;
    bool hasDepthEdge = abs(dN - dC) > 0.003 || abs(dS - dC) > 0.003
                     || abs(dW - dC) > 0.003 || abs(dE - dC) > 0.003;

    // Skip if no edge at all
    if (!hasLumaEdge && !hasDepthEdge) return centerColor;

    // Combined gradient: luma + depth
    float lumaGx = (lNE + 2.0 * lE + lSE) - (lNW + 2.0 * lW + lSW);
    float lumaGy = (lSW + 2.0 * lS + lSE) - (lNW + 2.0 * lN + lNE);
    float depthGx = dE - dW;
    float depthGy = dS - dN;

    float depthScale = max(lRange, 0.05) * 4.0;
    float gx = lumaGx + depthGx * depthScale;
    float gy = lumaGy + depthGy * depthScale;

    float gLen = max(length(vec2(gx, gy)), 1e-5);
    vec2 dir = vec2(gx, gy) / gLen;

    // Sample across the edge
    vec3 cPos = texture(colortex0, clamp(uv + dir * px, vec2(0.001), vec2(0.999))).rgb * expFac;
    vec3 cNeg = texture(colortex0, clamp(uv - dir * px, vec2(0.001), vec2(0.999))).rgb * expFac;
    float lPos = dot(cPos, L);
    float lNeg = dot(cNeg, L);

    float dPos = abs(lPos - lC);
    float dNeg = abs(lNeg - lC);
    vec3  blendColor = dPos >= dNeg ? cPos : cNeg;

    // Conservative weight
    float weight = 0.12;
    if (hasLumaEdge) weight = clamp(max(dPos, dNeg) / (lRange + 1e-5) * 0.18, 0.0, 0.18);
    if (hasDepthEdge && !hasLumaEdge) weight = 0.10;

    return mix(centerColor, blendColor, weight);
}
#endif

void main() {
    // [v1.0.7] Early depth fetch and unique water alpha tag check (0.8).
    float depth  = texture(depthtex0, texcoord).r;  // includes translucent
    float depthS = texture(depthtex1, texcoord).r;  // solid only (no water/glass)
    vec4 ndPre   = texture(colortex2, texcoord);
    bool isWaterSurface = (depthS - depth) > 1e-5 && abs(ndPre.a - 0.8) < 0.05;

    vec3 color;
    // [v1.0.7] Clean screen-space ripple view distortion applied post-lighting when underwater
    if (isEyeInWater == 1 && depth < 0.99999) {
        vec3 uwViewPos = screenToView(texcoord, depth);
        float distortionStrength = 0.0018 * smoothstep(2.0, 12.0, abs(uwViewPos.z));
        vec2 rippleOffset = vec2(
            sin(texcoord.y * 35.0 + frameTimeCounter * 2.8) * distortionStrength,
            cos(texcoord.x * 28.0 + frameTimeCounter * 2.2) * distortionStrength
        );
        vec2 distortedUV = clamp(texcoord + rippleOffset, vec2(0.001), vec2(0.999));
        color = texture(colortex0, distortedUV).rgb;
    } else {
        color = texture(colortex0, texcoord).rgb;
    }

    vec3 waterNormal = vec3(0.0, 1.0, 0.0);
    bool haveWaterNormal = false;

    // --- Reconstruct geometric water normal (4-tap depth derivative) once ---
    if (isWaterSurface && depth < 1.0) {
        vec2 px = vec2(1.0 / max(viewWidth, 1.0), 1.0 / max(viewHeight, 1.0));
        float d_xp = texture(depthtex0, texcoord + vec2( px.x, 0.0)).r;
        float d_xn = texture(depthtex0, texcoord + vec2(-px.x, 0.0)).r;
        float d_yp = texture(depthtex0, texcoord + vec2( 0.0,  px.y)).r;
        float d_yn = texture(depthtex0, texcoord + vec2( 0.0, -px.y)).r;
        vec3 vp_xp = screenToView(texcoord + vec2( px.x, 0.0), d_xp);
        vec3 vp_xn = screenToView(texcoord + vec2(-px.x, 0.0), d_xn);
        vec3 vp_yp = screenToView(texcoord + vec2( 0.0,  px.y), d_yp);
        vec3 vp_yn = screenToView(texcoord + vec2( 0.0, -px.y), d_yn);

        vec3 dpx = vp_xp - vp_xn;
        vec3 dpy = vp_yp - vp_yn;
        vec3 derivedN = cross(dpy, dpx);
        if (length(derivedN) > 1e-6) {
            waterNormal = normalize(derivedN);
            if (waterNormal.z > 0.0) waterNormal = -waterNormal;
        } else {
            waterNormal = vec3(0.0, 0.0, -1.0);
        }

        // --- Procedural ripple perturbation (shared with SSR) ---
        vec3 vpHere = screenToView(texcoord, depth);
        vec3 worldFromView = (gbufferModelViewInverse * vec4(vpHere, 1.0)).xyz;
        vec3 worldPos = worldFromView + cameraPosition;
        vec2 ripple = waterRippleOffset(worldPos.xz, frameTimeCounter);

        vec3 T = normalize(dpx);
        vec3 B = normalize(dpy);
        float waveAmp = 0.18;
        #if WATER_WAVE_SCALE == 1
        waveAmp = 0.07;
        #elif WATER_WAVE_SCALE == 3
        waveAmp = 0.30;
        #elif WATER_WAVE_SCALE == 4
        waveAmp = 0.45;
        #endif
        waterNormal = normalize(waterNormal - T * (ripple.x * waveAmp)
                                                - B * (ripple.y * waveAmp));
        if (waterNormal.z > 0.0) waterNormal = -waterNormal;
        haveWaterNormal = true;
    }

    // ==================================================================
    // [v1.0.3] SCREEN-SPACE WATER REFRACTION
    // When looking at water from above, the underwater scene is read
    // through a displaced UV computed from the wave normal. This gives
    // physically-plausible distortion of the bottom without feedback
    // loops. Strength follows (1 - N·V): strongest at shallow angles,
    // vanishing when looking straight down (Snell's law approximation).
    // ==================================================================
    if (isWaterSurface && isEyeInWater != 1 && depth < 1.0 && haveWaterNormal) {
        vec3 vpHere = screenToView(texcoord, depth);
        // --- Compute refracted UV offset ---
        vec3 V = normalize(-vpHere);
        float NoV = clamp(dot(waterNormal, V), 0.0, 1.0);
        // Approximate refracted offset in screen-space.
        // The (1.0 - NoV) term makes the distortion vanish when looking
        // straight down and grow at grazing view angles.
        vec2 refractOffset = waterNormal.xz * 0.045 * (1.0 - NoV);
        vec2 refractedUV = texcoord + refractOffset;

        // --- Validate: must hit solid geometry behind the water ---
        float refractedDepthS = texture(depthtex1, refractedUV).r;
        bool validRefraction = all(greaterThanEqual(refractedUV, vec2(0.0)))
                            && all(lessThanEqual(refractedUV, vec2(1.0)))
                            && refractedDepthS > depth + 1e-4
                            && refractedDepthS < 1.0;

        if (validRefraction) {
            color = texture(colortex0, refractedUV).rgb;
        }
    }

    #ifdef SSR
    // Skip sky (pixel where even the translucent depth = 1.0 = far plane)
    if (depth < 1.0) {
        // Read PBR roughness from colortex1.z (written by every gbuffer pass).
        vec4 lm = texture(colortex1, texcoord);
        float roughness = lm.z;

        // Read normal + emissive flag from colortex2.
        vec4 nd = texture(colortex2, texcoord);
        vec3 N = nd.xyz * 2.0 - 1.0;
        float emissive = 1.0 - step(0.5, nd.a); // alpha < 0.5 → emissive (portals)

        // ==================================================================
        // [v1.0.3] BULLETPROOF WATER DETECTOR via depth comparison.
        // ==================================================================
        bool isWaterSurfaceInner = (depthS - depth) > 1e-5 && abs(nd.a - 0.8) < 0.05;
        if (isWaterSurfaceInner) {
            roughness = 0.05; // force water-like roughness
            if (haveWaterNormal) {
                N = waterNormal;
            }
        }

        // Reflectivity from roughness. Water (0.03-0.11) → 0.67-0.91.
        // Rough terrain (>= 0.33) → 0. Wet surfaces in rain get a boost.
        float wetBoost = 0.0;
        if (rainStrength > 0.01) {
            wetBoost = rainStrength * clamp(N.y, 0.0, 1.0) * 0.5;
            roughness = mix(roughness, 0.08, wetBoost);
        }
        float reflectivity = clamp(1.0 - roughness * 3.0, 0.0, 1.0);
        if (emissive > 0.5) reflectivity = 0.0;

        // Underwater: don't reflect anything (camera is INSIDE the water column)
        if (isEyeInWater == 1) reflectivity = 0.0;

        // ---------- DEBUG VIEWS ----------
        #if SSR_DEBUG == 1
        fragColor = vec4(reflectivity, 0.0, 0.0, 1.0); return;
        #elif SSR_DEBUG == 2
        fragColor = vec4(N * 0.5 + 0.5, 1.0); return;
        #elif SSR_DEBUG == 3
        reflectivity = 1.0;
        #endif

        #if SSR_DEBUG == 4
        if (reflectivity > 0.01) {
            N = normalize(N);
            vec3 viewPos = screenToView(texcoord, depth);
            vec3 V = normalize(viewPos);
            vec3 R = normalize(reflect(V, N));
            // Green if R points into the scene (R.z < -0.05, ray traces forward)
            // Red if R points toward camera (R.z >= -0.05, ray is rejected)
            // Brightness = |R.z| so we can see how strong the rejection is
            vec3 dc = R.z < -0.05 ? vec3(0.0, abs(R.z), 0.0) : vec3(abs(R.z), 0.0, 0.0);
            fragColor = vec4(dc, 1.0); return;
        }
        fragColor = vec4(0.0, 0.0, 0.2, 1.0); return;
        #endif

        #if SSR_DEBUG == 5
        // Brute-force: just mirror the screen UV. If water reflects something
        // that looks like an upside-down view of the scene, the trace logic
        // is at fault. If it still shows nothing, then colortex0 itself is
        // black at the place we'd be sampling from.
        if (reflectivity > 0.01) {
            vec2 mirroredUV = vec2(texcoord.x, 1.0 - texcoord.y);
            fragColor = vec4(texture(colortex0, mirroredUV).rgb, 1.0); return;
        }
        #endif

        if (reflectivity > 0.01 && length(N) > 0.5) {
            N = normalize(N);
            vec3 viewPos = screenToView(texcoord, depth);
            vec3 V = normalize(viewPos);
            vec3 R = normalize(reflect(V, N));

            vec4 refl = traceSSR(viewPos, R, N);

            float ssrMult = 0.75;
            #if SSR_STRENGTH == 1
            ssrMult = 0.45;
            #elif SSR_STRENGTH == 3
            ssrMult = 1.00;
            #endif

            color = mix(color, refl.rgb, refl.a * reflectivity * ssrMult);
        }
    }
    #endif

    // ==============================================================================
    // HEAT SHIMMER / HEAT WAVES ABOVE LAVA — [v1.0.6]
    // Optimized: only 5 samples (center + 4 cross neighbors) instead of 9.
    // Corrected logic: shimmer now applies to the air in front of lava
    // (neighborDepth > depth), i.e. pixels that are closer than the lava surface.
    // ==============================================================================
    #ifdef HEAT_SHIMMER
    float shimmerMask = 0.0;
    vec2 px = 1.0 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    vec4 nd = texture(colortex2, texcoord);

    if (depth < 0.99999) {
        if (abs(nd.a - 0.1) < 0.05) {
            // Pixel is lava itself
            shimmerMask = 1.0;
        } else {
            // Search in a small cross pattern for lava behind this pixel.
            // Heat rises, so the strongest effect is on pixels just above the lava surface.
            const ivec2 offsets[4] = ivec2[](ivec2(0, -2), ivec2(0, 2), ivec2(-2, 0), ivec2(2, 0));
            for (int i = 0; i < 4; ++i) {
                vec2 sampleUV = texcoord + vec2(offsets[i]) * px;
                if (sampleUV.x > 0.0 && sampleUV.x < 1.0 && sampleUV.y > 0.0 && sampleUV.y < 1.0) {
                    vec4 neighborND = texture(colortex2, sampleUV);
                    float neighborDepth = texture(depthtex0, sampleUV).r;
                    // Lava must be non-sky and behind the current pixel.
                    if (neighborDepth < 0.99999 && abs(neighborND.a - 0.1) < 0.05 && neighborDepth > depth) {
                        float dist = length(vec2(offsets[i]));
                        float distFalloff = 1.0 - clamp(dist / 3.0, 0.0, 1.0);
                        float depthFalloff = 1.0 - clamp((neighborDepth - depth) * 4.0, 0.0, 1.0);
                        shimmerMask = max(shimmerMask, 0.65 * distFalloff * depthFalloff);
                    }
                }
            }
        }
    }

    if (shimmerMask > 0.005) {
        float intensity = 0.7;
        #if HEAT_SHIMMER_STRENGTH == 1
        intensity = 0.45;
        #elif HEAT_SHIMMER_STRENGTH == 3
        intensity = 1.0;
        #endif

        float t = frameTimeCounter * 3.5; // slow, smooth rising heatwaves
        vec2 shimmerOffset = vec2(
            sin(texcoord.y * 35.0 + t) * 0.00028,
            cos(texcoord.x * 30.0 - t * 0.8) * 0.00018
        ) * shimmerMask * intensity;

        vec2 distortedUV = clamp(texcoord + shimmerOffset, vec2(0.001), vec2(0.999));
        float distortedDepth = texture(depthtex0, distortedUV).r;
        if (distortedDepth < 0.99999) {
            color = texture(colortex0, distortedUV).rgb;
        }
    }
    #endif

    // ---------- Standard post-processing ----------
    float expFactor = 1.0;
    #if EXPOSURE == 1
    expFactor = 0.75;
    #elif EXPOSURE == 3
    expFactor = 1.35;
    #endif
    color *= expFactor;

    // ---------- Subtle HDR bloom for overbright emissive sources ----------
    // [v1.0.3] Cheap single-pass neighbour blur: only pixels whose luminance
    // exceeds threshold after exposure receive a soft 3x3 glow. This naturally
    // affects sun/moon disks, lava, portals, bright specular, and torches
    // without smearing the entire scene or requiring extra buffers.
    float bloomThresh = 0.75;
    float bloomLuma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    if (bloomLuma > bloomThresh) {
        vec2 bPx = vec2(1.5 / max(viewWidth, 1.0), 1.5 / max(viewHeight, 1.0));
        vec3 bAccum = vec3(0.0);
        float bWeight = 0.0;
        for (int bx = -1; bx <= 1; ++bx) {
            for (int by = -1; by <= 1; ++by) {
                if (bx == 0 && by == 0) continue;
                vec2 bOff = vec2(float(bx), float(by)) * bPx;
                // Neighbours are read from the raw composite buffer at same exposure
                vec3 bSamp = texture(colortex0, texcoord + bOff).rgb * expFactor;
                float bL = dot(bSamp, vec3(0.2126, 0.7152, 0.0722));
                float bW = max(bL - bloomThresh, 0.0);
                bW *= bW; // square falloff: very bright neighbours dominate
                bAccum += bSamp * bW;
                bWeight += bW;
            }
        }
        if (bWeight > 1e-5) {
            // Intensity ramps with how far above threshold we are (0.10..0.18)
            float bloomIntensity = 0.10 + 0.08 * smoothstep(bloomThresh, bloomThresh + 1.0, bloomLuma);
            color += (bAccum / bWeight) * bloomIntensity;
        }
    }

    // ==============================================================================
    // SPATIAL ANTI-ALIASING (FXAA / SMAA)
    // Applied in linear space after exposure + bloom, before tone mapping.
    // Detects edges using colortex0 neighbors; blends center (with SSR/refraction/bloom)
    // toward the offset sample to smooth aliasing without destroying detail.
    // Can be combined with TAA (composite1 pass) for temporal + spatial smoothing.
    // ==============================================================================
    #if SPATIAL_AA_MODE == 1
    color = applyFXAA(texcoord, color, expFactor);
    #elif SPATIAL_AA_MODE == 2
    color = applySMAA(texcoord, color, expFactor);
    #endif

#if CONTRAST == 1
    color = clamp(mix(color, ACESFilm(color), 0.45), 0.0, 1.0);
    #elif CONTRAST == 2
    color = ACESFilm(color);
    #elif CONTRAST == 3
    color = ACESFilm(color);
    color = clamp(pow(color, vec3(1.12)), 0.0, 1.0);
    #elif CONTRAST == 4
    color = tonemapPhotographic(color);
    #endif

    color = pow(color, vec3(1.0 / 2.2));

    #ifdef VIGNETTE
    vec2 uv = texcoord - 0.5;
    float vignette = 1.0 - dot(uv, uv) * 0.38;
    color *= clamp(vignette, 0.0, 1.0);
    #endif

    float vibAmount = -0.06;
    #if COLOR_SATURATION == 1
    vibAmount = 0.15;
    #elif COLOR_SATURATION == 3
    vibAmount = -0.16;
    #elif COLOR_SATURATION == 4
    vibAmount = -0.28;
    #endif
    color = applyVibrancy(color, vibAmount);

    fragColor = vec4(color, 1.0);
}

#version 460 compatibility
// AuraLite Shaders v1.1.4 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

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
#define WET_REFLECTIONS     // [true false] - Toggles wet reflections during rain
#define WATER_WAVE_SCALE 2     // [1 2 3 4] - 1: Calm, 2: Standard, 3: Choppy, 4: Stormy (visible wave amplitude)
#define WATER_WAVE_DETAIL 2    // [1 2 3] - 1: Coarse few waves, 2: Standard, 3: Dense many small waves
#define SKY_MODE 0                 // [0 1] shared physical sky mode
#define ATMOSPHERE_TURBIDITY 2     // [1 2 3]
#define ATMOSPHERE_SCALE 3         // [1 2 3]

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

// ==============================================================================
// [v1.1.4] HDR BLOOM (half-resolution Gaussian chain, composite3-7) & POST-TAA SHARPENING
// ==============================================================================
#define BLOOM             // [true false] - master switch; program scheduling skips composite3-7 when disabled
#define HDR_BLOOM 2       // [1 2 3] - 1: Subtle, 2: Balanced, 3: Strong — wide gaussian glow on overbright HDR sources
#define POST_SHARPEN      // [true false] - [v1.1.3] gentle unsharp mask that recovers detail softened by TAA

// [DIAG] 0 = off, 1 = show reflectivity, 2 = show normal, 3 = force-reflect everything, 4 = ray direction, 5 = mirror UV
#define SSR_DEBUG 0 // Internal diagnostic: 0 off, 1 reflectivity, 2 normal, 3 force, 4 ray, 5 mirror UV

in vec2 texcoord;

uniform sampler2D colortex0; // Fully lit scene (post composite)
uniform sampler2D colortex1; // lightmap.xy, roughness.z, metalness.w
uniform sampler2D colortex2; // view-space normal.xyz, emissive flag.a
uniform sampler2D colortex3; // [v1.1.4] finished half-resolution HDR bloom chain (composite3-7)
uniform sampler2D colortex5; // tiny physical-atmosphere direct-transmittance LUT
uniform sampler2D colortex6; // tiny physical-atmosphere multi-scatter LUT
uniform sampler2D depthtex0; // depth WITH translucent (water, glass, ice)
uniform sampler2D depthtex1; // depth WITHOUT translucent (terrain only)
// [v1.1.4] Distant Horizons keeps its own depth pair and projection. tex0
// contains DH terrain/water; tex1 is the solid-only companion used to identify
// refractable distant water without mixing incompatible vanilla depth values.
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform sampler2D dhDepthTex1;
uniform mat4 dhProjectionInverse;
#endif
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float rainStrength;
uniform float thunderStrength;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelViewInverse;
uniform int isEyeInWater; // 0 = air, 1 = water, 2 = lava
uniform int worldTime;       // [v1.1.3] day/night state for the SSR sky fallback
uniform int moonPhase;       // [v1.1.3] moon brightness for the SSR sky fallback
uniform vec3 shadowLightPosition; // [v1.1.3] sun/moon direction for the SSR sky fallback

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
#ifdef DISTANT_HORIZONS
vec3 dhScreenToView(vec2 uv, float depth) {
    vec4 ndc = vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
    vec4 view = dhProjectionInverse * ndc;
    return view.xyz / view.w;
}
#endif
vec3 viewToScreen(vec3 view) {
    vec4 clip = gbufferProjection * vec4(view, 1.0);
    return clip.xyz / clip.w * 0.5 + 0.5;
}

float edgeFade(vec2 uv) {
    vec2 e = smoothstep(vec2(0.0), vec2(0.04), uv) *
             (1.0 - smoothstep(vec2(0.96), vec2(1.0), uv));
    return e.x * e.y;
}

// ---------- Coherent directional water spectrum --------------------------------
// [v1.1.4] Replaces the old value-noise/fBm central-difference normal. That
// field was stable mathematically but visually read as high-frequency random
// glitter. A small directional Gerstner spectrum produces coherent wind waves,
// analytic slopes and a calmer default surface.
float waterDetailMultiplier() {
    #if WATER_WAVE_DETAIL == 1
    return 0.62; // Coarse: longer swell, fewer ripples
    #elif WATER_WAVE_DETAIL == 3
    return 1.42; // Dense: smaller capillary detail
    #else
    return 1.0;
    #endif
}

// Returns dh/dx, dh/dz of a travelling multi-directional height field.
vec2 waterRippleOffset(vec2 worldXZ, float t) {
    float detail = waterDetailMultiplier();
    vec2 gradient = vec2(0.0);

    // Dominant wind swell: long wavelength, slow motion.
    vec2 d0 = normalize(vec2(0.82, 0.57));
    float p0 = dot(worldXZ, d0) * (0.48 * detail) + t * 0.62;
    gradient += d0 * cos(p0) * (0.125 * 0.48 * detail);

    // Cross swell breaks perfect parallel bands.
    vec2 d1 = normalize(vec2(-0.31, 0.95));
    float p1 = dot(worldXZ, d1) * (0.91 * detail) + t * 0.88 + 1.9;
    gradient += d1 * cos(p1) * (0.058 * 0.91 * detail);

    // Short wind ripples, deliberately low amplitude.
    vec2 d2 = normalize(vec2(0.96, -0.28));
    float p2 = dot(worldXZ, d2) * (1.72 * detail) + t * 1.34 + 4.1;
    gradient += d2 * cos(p2) * (0.022 * 1.72 * detail);

    // Opposed small component avoids an overly regular wave train.
    vec2 d3 = normalize(vec2(0.18, 0.98));
    float p3 = dot(worldXZ, d3) * (2.48 * detail) - t * 1.56 + 0.7;
    gradient += d3 * cos(p3) * (0.009 * 2.48 * detail);

    return clamp(gradient, vec2(-0.22), vec2(0.22));
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
// ==============================================================================
// [v1.1.3] Procedural sky fallback for SSR misses. When a reflected ray leaves
// the screen or hits the sky itself, the physically correct answer for
// water / wet ground is "reflect the sky" — the old code returned black,
// which forced the waterMirrorBoost hack to overcompensate. This lightweight
// gradient mirrors the look of the SKY_MODE 0 gradient sky: zenith/horizon
// blend, warm sun-side glow, sunset tint, night sky, storm grey-out.
// ==============================================================================
#ifdef SSR
#if SKY_MODE == 1
float finalAtmosphereMetersPerBlock() {
    #if ATMOSPHERE_SCALE == 1
    return 25.0;
    #elif ATMOSPHERE_SCALE == 2
    return 50.0;
    #else
    return 100.0;
    #endif
}

float finalAtmosphereMieScale() {
    float base = 1.0;
    #if ATMOSPHERE_TURBIDITY == 1
    base = 0.62;
    #elif ATMOSPHERE_TURBIDITY == 3
    base = 1.70;
    #endif
    return base * mix(1.0, 2.35, rainStrength);
}

vec2 finalAtmosphereLutUV(float sunY) {
    float altitude = clamp(max(0.0, cameraPosition.y - 63.0) * finalAtmosphereMetersPerBlock(), 0.0, 30000.0);
    return vec2(clamp((sunY + 0.16) / 1.16, 0.0, 1.0), altitude / 30000.0);
}

vec3 physicalReflectionSky(vec3 direction, vec3 sunDir, float dayFactor) {
    float up = clamp(direction.y, 0.0, 1.0);
    float haze = clamp((finalAtmosphereMieScale() - 0.55) / 2.40, 0.0, 1.0);
    vec3 zenith = mix(vec3(0.004, 0.006, 0.010), vec3(0.055, 0.22, 0.62), dayFactor);
    vec3 horizon = mix(vec3(0.012, 0.018, 0.038), vec3(0.50, 0.64, 0.82), dayFactor);
    horizon = mix(horizon, vec3(0.42, 0.46, 0.50), haze * dayFactor);
    vec3 sky = mix(horizon, zenith, pow(up, mix(0.72, 1.10, haze)));
    float solarVisibility = smoothstep(-0.12, 0.025, sunDir.y);
    vec3 trans = texture(colortex5, finalAtmosphereLutUV(sunDir.y)).rgb * solarVisibility;
    vec3 ms = texture(colortex6, finalAtmosphereLutUV(sunDir.y)).rgb * solarVisibility;
    float forward = pow(clamp(dot(direction, sunDir), 0.0, 1.0), mix(14.0, 5.5, haze));
    sky += trans * vec3(1.0, 0.96, 0.90) * forward * mix(0.14, 0.52, haze);
    sky += ms * mix(0.20, 0.70, up);
    return max(sky, vec3(0.0));
}
#endif

vec3 auraliteSkyFallback(vec3 Rw) {
    float time = mod(float(worldTime), 24000.0);
    float dayFactor;
    if (time < 12000.0)      dayFactor = 1.0;
    else if (time < 13000.0) dayFactor = 1.0 - (time - 12000.0) / 1000.0;
    else if (time < 23000.0) dayFactor = 0.0;
    else                     dayFactor = (time - 23000.0) / 1000.0;

    float sunsetFactor = 0.0;
    if (time >= 11000.0 && time < 13000.0) {
        sunsetFactor = sin(clamp((time - 11000.0) / 2000.0, 0.0, 1.0) * 3.14159265);
    } else if (time >= 22500.0 || time < 1500.0) {
        float sr = time >= 22500.0 ? time - 24000.0 : time;
        sunsetFactor = sin(clamp((sr + 1500.0) / 3000.0, 0.0, 1.0) * 3.14159265);
    }

    // shadowLightPosition points to the sun by day and to the moon at night;
    // the sun is on the opposite side when the moon is the active light.
    vec3 worldL = normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));
    vec3 sunDir = (time < 12800.0 || time > 23200.0) ? worldL : -worldL;

    #if SKY_MODE == 1
    // Match physical sky twilight to solar elevation rather than legacy ticks.
    dayFactor = smoothstep(-0.105, 0.040, sunDir.y);
    vec3 skyPhysical = physicalReflectionSky(Rw, sunDir, dayFactor);
    float physicalMoonBr = 0.75;
    if (moonPhase == 0) physicalMoonBr = 1.0;
    else if (moonPhase == 4) physicalMoonBr = 0.35;
    else if (moonPhase == 3 || moonPhase == 5) physicalMoonBr = 0.50;
    else if (moonPhase == 1 || moonPhase == 7) physicalMoonBr = 0.65;
    vec3 moonDir = -sunDir;
    float moonGlow = pow(clamp(dot(Rw, moonDir), 0.0, 1.0), 18.0);
    skyPhysical += vec3(0.075, 0.105, 0.19) * moonGlow * physicalMoonBr * (1.0 - dayFactor);
    float stormVeil = rainStrength * mix(0.34, 0.66, thunderStrength);
    vec3 overcastPhysical = mix(vec3(0.24, 0.27, 0.31), vec3(0.075, 0.085, 0.105), thunderStrength);
    return mix(skyPhysical, overcastPhysical * (dayFactor * 0.56 + 0.12), stormVeil);
    #endif

    float up = clamp(Rw.y, 0.0, 1.0);
    vec3 dayCol = mix(vec3(0.55, 0.68, 0.82), vec3(0.10, 0.26, 0.58), pow(up, 0.6));
    float sunAmt = pow(clamp(dot(Rw, sunDir), 0.0, 1.0), 8.0);
    dayCol += vec3(1.0, 0.55, 0.25) * sunAmt * (0.6 + 0.8 * sunsetFactor);

    float moonBr = 0.75;
    if (moonPhase == 0) moonBr = 1.0;
    else if (moonPhase == 4) moonBr = 0.35;
    else if (moonPhase == 3 || moonPhase == 5) moonBr = 0.5;
    else if (moonPhase == 1 || moonPhase == 7) moonBr = 0.65;
    float moonAmt = pow(clamp(dot(Rw, -sunDir), 0.0, 1.0), 16.0);
    vec3 nightCol = mix(vec3(0.0035, 0.0045, 0.0065), vec3(0.006, 0.008, 0.012), up)
                  + vec3(0.10, 0.13, 0.22) * moonAmt * moonBr * 0.5;

    vec3 sky = mix(nightCol, dayCol, dayFactor);
    sky = mix(sky, vec3(0.82, 0.36, 0.10), sunsetFactor * (1.0 - up) * 0.65);
    vec3 storm = vec3(0.20, 0.22, 0.25) * mix(0.45, 1.0, dayFactor);
    return mix(sky, storm, rainStrength * 0.85);
}

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
    // [FIX v1.1.3] Start 0.5 view units off the surface (was 1.0) so the water
    // plane in front of the player's feet still picks up near-field reflections.
    float marchT   = 0.5;
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

    // [v1.1.3] SKY FALLBACK. Reaching here means the ray left the screen, hit
    // the sky, or never crossed geometry — for water and wet surfaces that is
    // exactly the "reflect the sky" case which the old code drew as a black
    // hole (and then compensated with the waterMirrorBoost hack). Return the
    // procedural gradient sky along the reflected direction, weighted by the
    // same Schlick Fresnel so behaviour mirrors real hits. Edge fade comes
    // from projecting a far point along the ray: off-screen rays fade out
    // naturally instead of smearing border pixels.
    {
        vec3 V = normalize(-viewPos);
        float NoV = clamp(dot(N, V), 0.0, 1.0);
        float fresnel = clamp(0.02 + 0.98 * pow(1.0 - NoV, 5.0), 0.05, 1.0);
        vec3 Rworld = normalize(mat3(gbufferModelViewInverse) * R);
        vec2 farScr = viewToScreen(viewPos + R * 24.0).xy;
        return vec4(auraliteSkyFallback(Rworld), edgeFade(farScr) * fresnel);
    }
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
    // [v1.0.7/v1.1.4] Gather vanilla and (when active) DH depth pairs before
    // classifying water. The two projection systems must never be compared to
    // each other; each uses its own tex0/tex1 difference.
    float depth  = texture(depthtex0, texcoord).r;  // vanilla: includes translucent
    float depthS = texture(depthtex1, texcoord).r;  // vanilla: solid only
    float dhDepth = 1.0;
    float dhDepthS = 1.0;
    bool isDHGeometry = false;
    #ifdef DISTANT_HORIZONS
    dhDepth = texture(dhDepthTex0, texcoord).r;
    dhDepthS = texture(dhDepthTex1, texcoord).r;
    isDHGeometry = depth >= 0.99999 && dhDepth < 0.99999;
    #endif

    vec4 ndPre   = texture(colortex2, texcoord);
    bool tagWaterF  = abs(ndPre.a - 0.8) < 0.05;
    bool depthDiffF = (depthS - depth) > 1e-5 && depth < 1.0;
    bool dhDepthDiffF = false;
    #ifdef DISTANT_HORIZONS
    dhDepthDiffF = isDHGeometry && (dhDepthS - dhDepth) > 1e-5 && dhDepth < 1.0;
    #endif

    vec3 cPre = texture(colortex0, texcoord).rgb;
    // MRT-safe hue guards shared with composite.fsh. They keep portals, lava,
    // pale ice and clear glass out of the water fallback path.
    bool portalF = cPre.b > cPre.g * 1.8 && cPre.g < 0.42 && cPre.g < cPre.r * 0.75;
    bool lavaF = cPre.b < cPre.r * 0.45 && cPre.b < cPre.g * 0.60 && cPre.r > cPre.g * 0.80;
    float lumC = dot(cPre, vec3(0.299, 0.587, 0.114));
    bool waterColF = (cPre.b >= cPre.r * 0.95 && lumC < 0.56) ||
                     (cPre.g > cPre.r * 2.2 && cPre.b > cPre.r * 2.2);

    bool vanillaWaterSurface = depthDiffF && (tagWaterF || (waterColF && !portalF && !lavaF));
    // [v1.1.4] DH water has a valid, independent solid depth companion. Prefer
    // its explicit 0.8 tag but keep the same hue-guarded rescue route.
    bool isDHWaterSurface = dhDepthDiffF && (tagWaterF || (waterColF && !portalF && !lavaF));
    bool isWaterSurface = vanillaWaterSurface || isDHWaterSurface;

    // True geometry test for heat shimmer and other final-stage effects.
    bool isRealGeometry = depth < 0.99999 || isDHGeometry;

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

    #ifdef POST_SHARPEN
    // [v1.1.3] POST-TAA DETAIL RECOVERY.
    // TAA's 0.64-0.92 history weight inevitably softens fine texture detail.
    // This luma-safe 5-tap unsharp mask runs on the resolved image BEFORE any
    // water refraction / SSR / bloom work (those sample their own pixels).
    // Amplitude is deliberately small and the result is clamped at 0 so the
    // negative lobe cannot create halos or black fireflies.
    {
        vec2 spx = 1.0 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
        vec3 cN = texture(colortex0, texcoord + vec2(0.0,  spx.y)).rgb;
        vec3 cS = texture(colortex0, texcoord - vec2(0.0,  spx.y)).rgb;
        vec3 cE = texture(colortex0, texcoord + vec2(spx.x, 0.0)).rgb;
        vec3 cW = texture(colortex0, texcoord - vec2(spx.x, 0.0)).rgb;
        vec3 blur = (cN + cS + cE + cW + color) * 0.2;
        color = max(color + (color - blur) * 0.18, vec3(0.0));
    }
    #endif

    vec3 waterNormal = vec3(0.0, 1.0, 0.0);
    bool haveWaterNormal = false;

    // --- Reconstruct water normal once ---
    // DH water already writes its option-controlled ripple normal to colortex2,
    // while its depth projection differs from vanilla. Reuse that normal rather
    // than deriving it with incompatible vanilla depth samples.
    if (isDHWaterSurface) {
        vec3 dhNormal = ndPre.xyz * 2.0 - 1.0;
        waterNormal = length(dhNormal) > 1e-5 ? normalize(dhNormal) : vec3(0.0, 0.0, -1.0);
        if (waterNormal.z > 0.0) waterNormal = -waterNormal;
        haveWaterNormal = true;
    } else if (isWaterSurface && depth < 1.0) {
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
        // The coherent spectrum stays clean without noise, but Standard must still
        // visibly break reflections. Calm is deliberately flatter; Choppy and
        // Stormy raise the same directional waves instead of adding random grain.
        float waveAmp = 0.55;
        #if WATER_WAVE_SCALE == 1
        waveAmp = 0.20;
        #elif WATER_WAVE_SCALE == 3
        waveAmp = 0.92;
        #elif WATER_WAVE_SCALE == 4
        waveAmp = 1.25;
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
    if (isWaterSurface && isEyeInWater != 1 && haveWaterNormal) {
        bool useDHRefraction = isDHWaterSurface;
        float surfaceDepth = useDHRefraction ? dhDepth : depth;
        vec3 vpHere;
        #ifdef DISTANT_HORIZONS
        vpHere = useDHRefraction ? dhScreenToView(texcoord, dhDepth)
                                 : screenToView(texcoord, depth);
        #else
        vpHere = screenToView(texcoord, depth);
        #endif

        // The (1.0 - N·V) term vanishes when looking straight down and grows at
        // grazing angles. DH uses the same screen-space approximation, but
        // validates against dhDepthTex1 in its own projection domain.
        vec3 V = normalize(-vpHere);
        float NoV = clamp(dot(waterNormal, V), 0.0, 1.0);
        vec2 refractOffset = waterNormal.xz * 0.045 * (1.0 - NoV);
        vec2 refractedUV = texcoord + refractOffset;

        float refractedDepthS;
        #ifdef DISTANT_HORIZONS
        refractedDepthS = useDHRefraction ? texture(dhDepthTex1, refractedUV).r
                                          : texture(depthtex1, refractedUV).r;
        #else
        refractedDepthS = texture(depthtex1, refractedUV).r;
        #endif
        bool validRefraction = all(greaterThanEqual(refractedUV, vec2(0.0)))
                            && all(lessThanEqual(refractedUV, vec2(1.0)))
                            && refractedDepthS > surfaceDepth + 1e-4
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
        float emissive = 1.0 - step(0.5, nd.a); // alpha < 0.5 → emissive (portal/lava/DH illuminated)

        // ==================================================================
        // [v1.0.3] BULLETPROOF WATER DETECTOR via depth comparison.
        // [FIX v1.1.3] Reuse the MRT-proof decision made at the top of
        // main() (tag 0.8 OR depth-rescued with lava/portal guards).
        // ==================================================================
        bool isWaterSurfaceInner = isWaterSurface;
        if (isWaterSurfaceInner) {
            // [v1.1.1] Return water to the older near-mirror look.
            // Force very low roughness; final blend below boosts water hit alpha.
            roughness = 0.015;
            if (haveWaterNormal) {
                N = waterNormal;
            }
        }

        // Reflectivity from roughness. Water (0.03-0.11) → 0.67-0.91.
        // Rough terrain (>= 0.33) → 0. Wet surfaces in rain get a boost.
        float wetBoost = 0.0;
        #ifdef WET_REFLECTIONS
        if (rainStrength > 0.01) {
            wetBoost = rainStrength * clamp(N.y, 0.0, 1.0) * 0.5;
            roughness = mix(roughness, 0.08, wetBoost);

            // [v1.1.3] PROCEDURAL RAINDROP RINGS on wet up-facing surfaces.
            // Two layers of expanding circular waves perturb the normal used
            // by the SSR trace below, so rain reads as thousands of tiny
            // ripples instead of one perfectly flat mirror.
            if (wetBoost > 0.02 && N.y > 0.6) {
                vec3 wetWorldPos = (gbufferModelViewInverse * vec4(screenToView(texcoord, depth), 1.0)).xyz + cameraPosition;
                vec2 rippleGrad = vec2(0.0);
                for (int layer = 0; layer < 2; ++layer) {
                    float cellScale = layer == 0 ? 3.0 : 6.5;
                    vec2 p = wetWorldPos.xz * cellScale;
                    vec2 cell = floor(p);
                    vec2 f = fract(p);
                    vec2 hCell = cell + float(layer) * 17.31;
                    float h1 = fract(sin(dot(hCell, vec2(127.1, 311.7))) * 43758.5453);
                    float h2 = fract(h1 * 34.73 + 0.17);
                    vec2 center = 0.15 + 0.7 * vec2(h1, h2);
                    float phase = fract(frameTimeCounter * (0.7 + h2 * 0.5) + h1);
                    vec2 dvec = f - center;
                    float r = max(length(dvec), 1e-4);
                    float wave = sin(24.0 * r - phase * 6.2831853)
                               * exp(-r * 2.4) * (1.0 - phase) * smoothstep(0.0, 0.10, phase);
                    rippleGrad += (dvec / r) * wave;
                }
                N.xz += rippleGrad * 0.20 * wetBoost;
                N = normalize(N);
            }
        }
        #endif
        float reflectivity = clamp(1.0 - roughness * 3.0, 0.0, 1.0);
        // [FIX v1.1.3] Depth-rescued water can arrive with a cleared
        // colortex2.a (= 0.0 → looks "emissive") on broken-MRT Iris builds;
        // do not let that zero its reflectivity. Real portals/lava were
        // already excluded from isWaterSurfaceInner by the albedo guards.
        if (emissive > 0.5 && !isWaterSurfaceInner) reflectivity = 0.0;

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

            if (isWaterSurfaceInner) {
                // [v1.1.1] traceSSR() already contains a conservative
                // Fresnel term (min ~0.05), which made water reflections barely
                // visible from common top-down angles. Boost only water hits so
                // the surface returns to the old mirror-like style.
                float waterMirrorBoost = 6.5;
                #if SSR_STRENGTH == 1
                waterMirrorBoost = 4.5;
                #elif SSR_STRENGTH == 3
                waterMirrorBoost = 8.5;
                #endif
                // At night water should keep a moon glint, not become a bright
                // blue mirror of an amplified fallback. Reduce the old near-
                // mirror boost after sunset; physical mode derives night from
                // the actual sun direction rather than the elevated moon.
                float waterTime = mod(float(worldTime), 24000.0);
                float waterDay = (waterTime < 12000.0) ? 1.0 :
                                 (waterTime < 13000.0) ? 1.0 - (waterTime - 12000.0) / 1000.0 :
                                 (waterTime < 23000.0) ? 0.0 : (waterTime - 23000.0) / 1000.0;
                #if SKY_MODE == 1
                vec3 waterWorldL = normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));
                vec3 waterSunDir = (waterTime < 12800.0 || waterTime > 23200.0) ? waterWorldL : -waterWorldL;
                waterDay = smoothstep(-0.105, 0.040, waterSunDir.y);
                #endif
                float nightMirrorScale = mix(0.38, 1.0, waterDay);
                float waterAlpha = clamp(refl.a * max(reflectivity, 0.92) * ssrMult * waterMirrorBoost * nightMirrorScale, 0.0, 0.88);
                color = mix(color, refl.rgb, waterAlpha);
            } else {
                color = mix(color, refl.rgb, refl.a * reflectivity * ssrMult);
            }
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

    // [FIX v1.1.2] Use isRealGeometry (checks dhDepthTex0 too) instead of raw
    // depth < 0.99999 so distant Distant Horizons lava lakes also get shimmer
    // instead of being silently skipped as "sky".
    if (isRealGeometry) {
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

    // ---------- HDR bloom (half-resolution Gaussian chain, composite3-7) ----------
    // [v1.1.4] The bright-pass and four separable blur passes now execute into
    // half-resolution post-process buffers. final.fsh samples the finished glow
    // with hardware-linear upsampling, preserving the soft falloff while cutting
    // bloom bandwidth substantially. When BLOOM is disabled, shaders.properties
    // skips all five composite passes; this guard also prevents stale-buffer reads
    // on legacy loaders that do not support program.<name>.enabled.
    #ifdef BLOOM
    {
        float bloomAmp = 0.12;
        #if HDR_BLOOM == 1
        bloomAmp = 0.06;
        #elif HDR_BLOOM == 3
        bloomAmp = 0.22;
        #endif
        color += texture(colortex3, texcoord).rgb * bloomAmp;
    }
    #endif

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

    // ==========================================================================
    // [BANDING FIX] LINEAR-SPACE DITHER — applied BEFORE tone mapping.
    // This is the correct location for killing dark-sky + moon-halo banding (the
    // technique BSL/Complementary use). Both the night sky gradient and the
    // smooth glow around the sun/moon disks are so dark after tone mapping that
    // they compress to only a handful of output codes; a post-gamma ±1 LSB dither
    // cannot smooth that. But because gamma EXPANDS dark values, a small LINEAR
    // noise here becomes a much larger sRGB delta in the darks — exactly enough
    // to blend the gradient into a smooth transition. In bright regions the same
    // linear noise maps to <±0.5 code, so it stays invisible. Triangle
    // distribution (n1+n2-1) suppresses banding harder than uniform noise.
    // Strength 1.0/255 matches the BSL/Complementary reference.
    // ==========================================================================
    {
        vec2 dp = gl_FragCoord.xy;
        float n1 = fract(sin(dot(dp,        vec2(12.9898, 78.233))) * 43758.5453);
        float n2 = fract(sin(dot(dp + 17.0, vec2(12.9898, 78.233))) * 43758.5453);
        color += vec3((n1 + n2 - 1.0) * (1.0 / 255.0));
    }

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

    // Note: the output (post-gamma) dither that used to live here has been
    // REMOVED. Banding is now handled by the LINEAR-space dither applied BEFORE
    // tone mapping above, which is far more effective in dark regions (the only
    // place banding was visible) and silent in bright regions.
    // [FIX v1.1.2] Removed two duplicate copy-pasted post-gamma dither blocks that
    // were left over from a refactor (they re-added the same noise term two more
    // times right below this comment, contradicting it and wasting ALU per pixel
    // for no visual benefit — the single pre-tonemap dither above is sufficient).

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}

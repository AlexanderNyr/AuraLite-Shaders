#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

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

// ==============================================================================
// COLOUR GRADING — user controls [v1.2.0]
// ------------------------------------------------------------------------------
// Everything here is a float, so Iris/OptiFine render it as a slider you can drag
// (the values in the bracket list are the slider's stops). All defaults are the
// identity except COLOR_VIBRANCE, whose 0.00 reproduces the pack's historic
// -0.06 vibrancy exactly, so a fresh install looks identical to v1.1.4.
// The pipeline is split the way a camera splits it:
//   LINEAR  (before tone mapping)  exposure, per-channel gain, warmth, tint
//   DISPLAY (after tone mapping)   gamma, brightness, contrast, saturation, vibrance
// Exposure and gain live in linear light because that is where they physically
// act: pushing them before the tone curve compresses highlights, pushing them
// after just clips them. Brightness/contrast are display-referred by definition.
// ==============================================================================
#define COLOR_EXPOSURE 1.00    // [0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00] - Overall exposure, applied in linear light before tone mapping. Above 1.00 brightens the scene and rolls highlights off; below 1.00 darkens it.
#define COLOR_RED 1.00         // [0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50] - Red channel gain. Multiplies scene-linear red before tone mapping.
#define COLOR_GREEN 1.00       // [0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50] - Green channel gain.
#define COLOR_BLUE 1.00        // [0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50] - Blue channel gain.
#define COLOR_WARMTH 0.00      // [-1.00 -0.90 -0.80 -0.70 -0.60 -0.50 -0.40 -0.30 -0.20 -0.10 0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00] - Shifts the red/blue balance without touching green: positive is warmer (sunset), negative is cooler (overcast, moonlight).
#define COLOR_TINT 0.00        // [-1.00 -0.90 -0.80 -0.70 -0.60 -0.50 -0.40 -0.30 -0.20 -0.10 0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00] - Shifts the green/magenta balance: positive is greener, negative is magenta.
#define COLOR_BRIGHTNESS 1.00  // [0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40] - Midtone lift. Applied as a gamma curve after tone mapping, so blacks and whites stay put and nothing clips.
#define COLOR_CONTRAST 1.00    // [0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60] - Contrast around middle grey (0.5), i.e. the classic brightness-contrast operation.
#define COLOR_SATURATION 1.00  // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00] - 0.00 is greyscale, 1.00 is untouched, above 1.00 is oversaturated.
#define COLOR_GAMMA 2.20       // [1.80 1.85 1.90 1.95 2.00 2.05 2.10 2.15 2.20 2.25 2.30 2.35 2.40 2.45 2.50 2.55 2.60 2.65 2.70 2.75 2.80] - Output encode exponent. 2.20 is the pack default; lower lifts shadows, higher crushes them.
#define COLOR_VIBRANCE 0.00    // [-0.30 -0.29 -0.28 -0.27 -0.26 -0.25 -0.24 -0.23 -0.22 -0.21 -0.20 -0.19 -0.18 -0.17 -0.16 -0.15 -0.14 -0.13 -0.12 -0.11 -0.10 -0.09 -0.08 -0.07 -0.06 -0.05 -0.04 -0.03 -0.02 -0.01 0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30] - Selective saturation: lifts muted colours more than already-saturated ones, which plain saturation cannot do. 0.00 is the pack default.
#define COLOR_VIGNETTE 1.00    // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00] - Corner darkening strength. 0.00 disables the vignette without switching VIGNETTE off, 2.00 doubles it.
// [v1.2.0] Pre-tonemap dither, back but weaker. v1.1.4 used +/-1/255 and it
// read as permanent grain; 2 is half that amplitude. 1 turns it off.
#define DITHER_STRENGTH 2   // [1 2 3 4] - 1: Off, 2: Light (+/-0.5/255, half of v1.1.4), 3: Medium (+/-0.75/255), 4: v1.1.4 (+/-1/255)
#define COLOR_TONEMAP 1        // [1 2 3 4] - 1: ACES (default), 2: ACES soft roll-off, 3: ACES punchy, 4: Photographic (AgX-like, desaturates highlights)
#define COLOR_LUMA_PROTECT // [true false] - Keep average brightness fixed while you move the RGB / warmth / tint sliders. Off = raw per-channel multipliers, which also change overall brightness.
#define SSR // [true false]
#define SSR_QUALITY 2 // [1 2 3]
#define SSR_STRENGTH 2 // [1 2 3]
#define WET_REFLECTIONS     // [true false] - Toggles wet reflections during rain
#define WATER_WAVE_SCALE 2     // [1 2 3 4] - 1: Calm, 2: Standard, 3: Choppy, 4: Stormy (visible wave amplitude)
#define WATER_WAVE_DETAIL 2    // [1 2 3] - 1: Coarse few waves, 2: Standard, 3: Dense many small waves
// [v1.2.0] How much the water surface is allowed to show through when you
// are UNDER it. 0 restores the original (v1.1.4) calm look; 1 is the default
// subtle setting; 2 adds light caustics; 3 is the full-strength version.
#define UNDERWATER_WAVES 1     // [0 1 2 3] - 0: Off (calm), 1: Subtle, 2: Light caustics, 3: Strong
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

#define BLOOM             // [true false] - master switch; program scheduling skips composite3-7 when disabled
#define HDR_BLOOM 2       // [1 2 3] - 1: Subtle, 2: Balanced, 3: Strong — wide gaussian glow on overbright HDR sources
#define POST_SHARPEN      // [true false] - [v1.1.3] gentle unsharp mask that recovers detail softened by TAA

// [DIAG] 0 = off, 1 = show reflectivity, 2 = show normal, 3 = force-reflect everything, 4 = ray direction, 5 = mirror UV

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
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;   // [v1.2.0] always the SUN, never the moon

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
    // Negative amount now properly oversaturates instead of
    // relying on undefined GLSL mix extrapolation + hard clamping.
    return clamp(((diff) * (1.0 - amount) + (vec3(luma))), 0.0, 1.0);
}

// [v1.2.0] Per-channel grading gain (linear stage).
// The three channel sliders are plain multipliers; warmth and tint are the same
// kind of multiplier on the red/blue and green/magenta axes, folded in here so
// white balance happens in exactly one place.
// COLOR_LUMA_PROTECT: a gain that changes luminance as well as hue is a trap --
// push red to 1.50 and the whole frame brightens. With the guard on, the vector
// is divided by its own Rec.709 luminance, so the sliders move colour and leave
// average brightness alone. Turn the guard off for raw channel multipliers.
vec3 auraliteGradingGain() {
    vec3 gain = vec3(COLOR_RED, COLOR_GREEN, COLOR_BLUE);
    gain *= vec3(1.0 + 0.15 * COLOR_WARMTH - 0.05 * COLOR_TINT,
                 1.0 + 0.10 * COLOR_TINT,
                 1.0 - 0.15 * COLOR_WARMTH - 0.05 * COLOR_TINT);
    #ifdef COLOR_LUMA_PROTECT
    float gainLuma = dot(gain, vec3(0.2126, 0.7152, 0.0722));
    gain /= max(gainLuma, 1e-3);
    #endif
    return max(gain, vec3(0.0));
}

// [v1.2.0] Tone-map selector. The four curves are the ones v1.1.4 exposed
// as CONTRAST levels 1-4; they are now a named choice instead of being smuggled
// into a "contrast" button, because they are not contrast: they are different
// filmic curves.
vec3 auraliteToneMap(vec3 color) {
    #if COLOR_TONEMAP == 2
    return clamp(mix(color, ACESFilm(color), 0.45), 0.0, 1.0);
    #elif COLOR_TONEMAP == 3
    return clamp(pow(ACESFilm(color), vec3(1.12)), 0.0, 1.0);
    #elif COLOR_TONEMAP == 4
    return tonemapPhotographic(color);
    #else
    return ACESFilm(color);
    #endif
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

// ==============================================================================
// [v1.2.0] Shared wind-wave spectrum (see the full note in gbuffers_water.vsh)
// ==============================================================================
// Must stay numerically identical to the copy in gbuffers_water.vsh/.fsh: the
// reflection normal here is the same surface the geometry and the G-buffer
// describe, otherwise reflections swim against the waves.
const float WAVE_G = 9.81;
const vec4 WAVE_COMP[8] = vec4[8](
    vec4( 0.61, 26.0, 0.055, 1.0),
    vec4(-0.33, 15.5, 0.060, 1.0),
    vec4( 1.42,  9.5, 0.062, 1.0),
    vec4( 0.18,  6.2, 0.058, 0.0),
    vec4( 1.95,  3.9, 0.052, 0.0),
    vec4(-1.07,  2.5, 0.046, 0.0),
    vec4( 0.87,  1.8, 0.040, 0.0),
    vec4(-1.60,  1.3, 0.034, 0.0)
);

vec3 auraliteWaveField(vec2 worldXZ, float t, float amp, bool geometryOnly) {
    float h = 0.0;
    vec2 grad = vec2(0.0);
    for (int i = 0; i < 8; ++i) {
        vec4 c = WAVE_COMP[i];
        if (geometryOnly && c.w < 0.5) continue;
        float k     = 6.28318530718 / c.y;
        vec2  d     = vec2(cos(c.x), sin(c.x));
        float A     = c.z / k;
        float omega = sqrt(WAVE_G * k);
        float phase = k * dot(d, worldXZ) - omega * t + float(i) * 1.7;
        h    += A * sin(phase);
        grad += A * k * d * cos(phase);
    }
    return vec3(h, grad) * amp;
}

// Returns dh/dx, dh/dz of a travelling multi-directional height field.
vec2 waterRippleOffset(vec2 worldXZ, float t) {
    // [v1.2.0] Was its own four-component sine field at 0.48..2.48 rad/block
    // with a hard `clamp(gradient, -0.22, 0.22)`. The four amplitudes sum to 0.246,
    // so the clamp actually engaged on most crests: a clipped derivative is a
    // FLAT TOP with a hard corner, which is precisely the sharp, cardboard look.
    // Now it is the same eight-component dispersive spectrum the geometry and the
    // G-buffer normal use, scaled by the same ripple factor, with no clamp at all.
    float detail = waterDetailMultiplier();
    vec3 field = auraliteWaveField(worldXZ, t, detail, false);
    return field.yz;   // dh/dx, dh/dz -- already bounded by the sum of steepnesses
}

// ==============================================================================
// SSR — view-space adaptive march with binary refinement.
// Implementation notes (original to AuraLite v0.2.9):
//   Standard textbook screen-space reflection: march the reflected ray in
//   view space, projecting each sample into screen space to compare against
//   the depth buffer. When a crossing is detected, refine the hit point
//   with a few binary-search steps. The marching step adapts to how far
//   the marker is from the visible surface, so long stretches of empty
//   space are skipped quickly.
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
// IMPORTANT: identical copy in gbuffers_skybasic.fsh, composite.fsh, final.fsh.
vec3 auraliteSunDir(vec3 viewSun, vec3 viewLight) {
    if (dot(viewSun, viewSun) > 1.0e-6) {
        return normalize(mat3(gbufferModelViewInverse) * normalize(viewSun));
    }
    return normalize(mat3(gbufferModelViewInverse) * normalize(viewLight));
}

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
    // [v1.2.0] smoothstep(-0.12, 0.025) switched this reflection off by solar
    // -1.4°, so anything the SSR could not resolve turned black exactly when the
    // sky was at its most colourful. Use the same soft twilight ramp as the sky.
    float twilightGate = smoothstep(-0.20, -0.03, sunDir.y);
    vec3 trans = texture(colortex5, finalAtmosphereLutUV(sunDir.y)).rgb * twilightGate;
    vec3 ms = texture(colortex6, finalAtmosphereLutUV(sunDir.y)).rgb * twilightGate;
    float forward = pow(clamp(dot(direction, sunDir), 0.0, 1.0), mix(14.0, 5.5, haze));
    sky += trans * vec3(1.0, 0.96, 0.90) * forward * mix(0.14, 0.52, haze);
    sky += ms * mix(0.20, 0.70, up);
    // [v1.2.0] Same exposure as SKY_EXPOSURE in gbuffers_skybasic: a reflection
    // must not be brighter than the sky it reflects.
    return max(sky * 0.55, vec3(0.0));
}
#endif

// ==============================================================================
// [v1.2.0] THE SUN'S DIRECTION, TAKEN FROM THE MACHINE THAT KNOWS IT
// ==============================================================================
// shadowLightPosition is the ACTIVE light: the sun by day, the moon by night,
// flipped by Iris at a moment of its own choosing. Every shader in this pack used
// to reconstruct the sun out of it, either through a hard tick threshold
// (12800 / 23200, which disagreed with Iris and put the sun on the wrong side of
// the sky) or through a sign test against the
// analytic elevation sin(2*pi*worldTime/24000).
// The analytic test was a mistake: it assumes worldTime and the celestial angle
// are in phase. They are not always -- `/time set`, disabled daylight cycle,
// sleeping, or a server adjusting time can leave them offset, and then the test
// flips the sun by 180 degrees at the WRONG moment. The sky is then lit from
// behind, the day/night palette jumps: a sudden night, then a sunrise, then a
// flip, then a sunset again.
// The sun's own direction is available as a plain uniform and is NEVER swapped
// for the moon: `sunPosition` (view space). There is nothing left to infer, so
// nothing left to get wrong. `shadowLightPosition` is only kept as a fallback
// for the unlikely case of a driver handing over a zeroed vector.
// [v1.2.0] The function body was moved ABOVE `#ifdef SSR`: it was inside
// this block, and is also called when SSR is turned off (line ~732, water block).
// Same error class as in composite.fsh: “call to undefined function”,
// which glslang does not catch, but ANGLE (Iris on Windows) does.
// IMPORTANT: identical copy in gbuffers_skybasic.fsh, composite.fsh, final.fsh.

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

    // shadowLightPosition points to the sun by day and to the moon at night.
    // [v1.2.0] Straight from the sunPosition uniform; see auraliteSunDir().
    vec3 worldL = normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));
    vec3 sunDir = auraliteSunDir(sunPosition, shadowLightPosition);
    dayFactor *= smoothstep(-0.26, 0.04, sunDir.y);   // same guarantee as elsewhere

    #if SKY_MODE == 1
    // Match physical sky twilight to solar elevation rather than legacy ticks.
    // [v1.2.0] Widened to -0.150..0.045 to stay identical to gbuffers_skybasic:
    // the old curve reached zero at solar -6° and made the SSR fallback (and the
    // water mirror it feeds) go pitch black during twilight.
    dayFactor = smoothstep(-0.150, 0.045, sunDir.y);
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
    // Start 0.5 view units off the surface (was 1.0) so the water
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

            // [v1.2.0] REFLECTION RAY CANNOT BE REFLECTED FROM WATER.
            // ------------------------------------------------------------------
            // In the colortex0 buffer, the water pixel contains NOT a picture of water, but its
            // albedo after illumination is dark blue. All “visible water” (bottom,
            // sky reflection, Fresnel) is collected later, here in final.fsh.
            // This means that the reflection ray hits another part of the same water
            // the surface is returned not by what the eye sees, but by the dark albedo,
            // and with waterMirrorBoost = 6.5 mixed with a weight of up to 0.88:
            // the result is a smooth dark spot with a ragged edge that lives
            // with your life on the waves.
            // Exactly the same error was refracted and was cured in
            // v1.2.0 (“sand showed moving dark blotches”): appeared there
            // checking `refractedIsWater`. There was no verification here - edit
            // I only got to one of the two places. Now it's in both.
            // Physically: water is a mirror, secondary reflection from it gives less
            // 2% energy, so the correct continuation is not “dark albedo”,
            // and the sky (the branch below). One additional colortex2 sample per
            // hit.
            float hitTagA = texture(colortex2, hit.xy).a;
            if (hitTagA > 0.75 && hitTagA < 0.97) break;   //  getting into the water - to the sky

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
        // visible surface the marker currently sits. Lowered
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
vec3 applyFXAA(vec2 uv, vec3 centerColor, vec3 expFac) {   // [v1.2.0] vec3: exposure * per-channel gain
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
vec3 applySMAA(vec2 uv, vec3 centerColor, vec3 expFac) {   // [v1.2.0] vec3: exposure * per-channel gain
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

// [v1.2.0] Body of water: weakening the bottom along the way in the water. One define -
// so that you can compare “as it was” in one line without touching the code.
#define AUR_WATER_BODY

uniform float isSwampBiome;   // [v1.2.0] same detector as in composite.fsh
#ifndef WATER_TRANSPARENCY
#define WATER_TRANSPARENCY 2
#endif

// ==============================================================================
// WATER IDENTIFICATION
// ------------------------------------------------------------------------------
// Three independent signals, any two of which are enough: the material tag in
// colortex2.a, the solid-vs-translucent depth pair (in blocks), and the albedo
// hue. Portals, lava, pale ice and clear glass are excluded by the hue guards.
// ==============================================================================

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
    // [v1.2.0] THE WATER MARK IS ALWAYS MIXED WITH THE BOTTOM.
    // ------------------------------------------------------------------
    // The water passage writes 0.8, the bottom below it writes 1.0, the coefficient is SRC_ALPHA
    // (water alpha 0.8) gives in the buffer 0.8*0.8 + 0.2*1.0 = 0.84. Therefore the window
    // is taken around 0.84, and not around 0.80: 0.75...0.97. Adjacent values
    // pack scales - 0.62 (wet surfaces) and 1.0 (normal surface) - in
    // the window doesn't fit. If Iris ever stops mixing, pure
    // 0.80 is also inside the window.
    // And most importantly: water identification is NOT tied to this. Three independent
    // sign, and any two are sufficient:
    // 1) material mark in the window 0.75…0.97;
    // 2) compartment depth greater than 5 cm;
    // 3) albedo color: b dominates over r and g.
    bool tagWaterF  = (ndPre.a > 0.75) && (ndPre.a < 0.97);
    // [v1.2.0] “IS THIS A SEPARATE SURFACE?” - IN BLOCKS, NOT IN NDC.
    // ---------------------------------------------------------------------
    // Comparing NORMALIZED depth -- `(depthS - depth) > 1e-5` -- has no physical
    // meaning: with a 24-bit buffer over a 40-block range, 1e-5 in NDC is metres
    // near the horizon and centimetres at the camera.
    // That is why water used to be identified in spots: wherever the threshold
    // happened to pass there was water, and everywhere else the pixel stayed “not
    // water” and showed the bare albedo of water, i.e. dark blue. Those are the
    // “dark spots on the water” one block apart.
    // Both pixels are therefore converted to view coordinates (screenToView, the
    // function refraction already uses) and the distance between the surface and
    // what is behind it is taken in blocks. Water is more than 5 cm of separation
    // along the beam. That is an invariant: it does not depend on range, on the
    // projection, or on depth settings.
    float sepVanilla = 0.0;
    if (depth < 0.999999 && depthS < 0.999999) {
        vec3 vpA = screenToView(texcoord, depth);
        vec3 vpB = screenToView(texcoord, depthS);
        sepVanilla = distance(vpA, vpB);
    }
    bool depthDiffF = (sepVanilla > 0.05) && depth < 1.0;
    bool dhDepthDiffF = false;
    #ifdef DISTANT_HORIZONS
    if (isDHGeometry && dhDepth < 0.999999 && dhDepthS < 0.999999) {
        vec3 vpA = dhScreenToView(texcoord, dhDepth);
        vec3 vpB = dhScreenToView(texcoord, dhDepthS);
        dhDepthDiffF = distance(vpA, vpB) > 0.05;
    }
    #endif

    vec3 cPre = texture(colortex0, texcoord).rgb;
    // MRT-safe hue guards shared with composite.fsh. They keep portals, lava,
    // pale ice and clear glass out of the water fallback path.
    bool portalF = cPre.b > cPre.g * 1.8 && cPre.g < 0.42 && cPre.g < cPre.r * 0.75;
    bool lavaF = cPre.b < cPre.r * 0.45 && cPre.b < cPre.g * 0.60 && cPre.r > cPre.g * 0.80;
    // [v1.2.0] WATER COLOR TEST NO LONGER DEPENDS ON BRIGHTNESS.
    // ------------------------------------------------------------------
    // The old test also required `lumC < 0.56`: bright water (which is almost the whole
    // pond under a midday sky) failed the brightness check, and the pixel stopped
    // being treated as water - no refraction, no reflection, no body of water. That is
    // exactly the “dark spots on bright water, one block apart” report.
    // What remains is the channel ratio, with no brightness threshold. Water in this pack
    // blue-dominant in construction (the albedo of the biome kicks from below like
    // max(color, b*vec3(0.16, 0.34, 1.0)) in both water shaders), so
    // b > r and b >= g are what distinguishes it from grass, sand, wood and stone.
    // Portal and lava are still excluded by the individual checks above.
    bool waterColF = (cPre.b > cPre.r * 1.05) && (cPre.b >= cPre.g) && (cPre.g > cPre.r);

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
        vec3 uwWorldPos = (gbufferModelViewInverse * vec4(uwViewPos, 1.0)).xyz + cameraPosition;
        vec3 uwSunDir = auraliteSunDir(sunPosition, shadowLightPosition);
        float uwTime = frameTimeCounter;

        // [v1.2.0] The previous attempt was gated on `isWaterSurface`, i.e.
        // on "this pixel is the water surface". Almost NO pixel you look at while
        // underwater is the water surface -- it is sand, kelp, stone, seen through
        // it. The effect therefore ran at 25 % strength on the one surface it was
        // meant for and at nothing everywhere else, which is why the waves stayed
        // invisible. Everything below is now applied to the whole underwater view.

        // ---------------------------------------------------------------------
        // 1. CAUSTICS -- the actual reason you can see waves from below.
        // A wavy surface is a lens. Sunlight entering it is bent into a network of
        // bright filaments where the surface converges, and dark gaps where it
        // spreads. That is the last cue to disappear from an underwater scene and
        // the pack had none of it at all.
        // First-order caustic estimate: take the surface slope at the point where
        // this fragment's sun ray crosses the surface, then measure how the slope
        // CHANGES along the sun's azimuth. Convergence (negative divergence)
        // squeezes the same amount of light into less area -> bright.
        // ---------------------------------------------------------------------
        // [v1.2.0] The whole caustic computation is skipped below setting 2,
        // so the default subtle look costs no extra work at all.
        float caustic = 1.0;
        #if UNDERWATER_WAVES > 1
        vec2 sunFlat = uwSunDir.xz;
        float sunFlatLen = length(sunFlat);
        vec2 sunFlatDir = sunFlatLen > 1e-4 ? sunFlat / sunFlatLen : vec2(1.0, 0.0);

        // Where the bundle of sunlight this fragment receives came through the
        // surface. The exact surface height is not available in this pass, so the
        // distance is nominal; it only scales the pattern, it does not change its
        // motion or its structure.
        float optPath = 2.2 / max(uwSunDir.y, 0.12);
        vec2 surfXZ = uwWorldPos.xz + sunFlatDir * (sunFlatLen * optPath);

        // All eight components: the divergence of the long three only has
        // std 0.016 (a +-3 % wobble, invisible), all eight give 0.089, which is
        // what produces a real filament network. Step 0.45 blocks resolves the
        // ~1.3 block components without aliasing them.
        const float refineEps = 0.45;
        const float CAUSTIC_GAIN = 5.6;      // 1 sigma of the divergence -> 0.5 of brightness
        vec2 slopeA = auraliteWaveField(surfXZ, uwTime, 1.0, false).yz;
        vec2 slopeB = auraliteWaveField(surfXZ + sunFlatDir * refineEps, uwTime, 1.0, false).yz;
        float convergence = dot(slopeB - slopeA, sunFlatDir) / refineEps;

        // Bounded so a bright filament can never blow out and a dark gap can never
        // punch to black -- the same reasoning as the twilight overlays: a real
        // caustic is a modulation of the light, not a replacement for it.
        caustic = clamp(1.0 - convergence * CAUSTIC_GAIN, 0.30, 2.10);
        #if UNDERWATER_WAVES == 2
        caustic = mix(1.0, caustic, 0.45);   // Light: 45 % strength
        #endif

        // Caustics are a FOCUSED pattern: the finer it gets with distance, the
        // more it shimmers as the camera moves. Fade the modulation with view
        // distance so far water reads as gently moving light instead of noise.
        caustic = mix(1.0, caustic, smoothstep(34.0, 7.0, length(uwViewPos)));
        #endif

        // Daylight only: at night there is no focused sunlight, just moon glow.
        float causticGate = smoothstep(0.02, 0.28, uwSunDir.y) * (1.0 - rainStrength * 0.55);

        // ---------------------------------------------------------------------
        // 2. SURFACE SLOPE SEEN FROM BELOW
        // Snell's window compresses the whole above-water hemisphere into a ~97
        // degree cone, and outside that cone the surface becomes a mirror of the
        // water below. Either way the surface clips and shifts what is behind it,
        // strongly and everywhere -- so the distortion applies to the whole view
        // and is not faded out per pixel.
        // ---------------------------------------------------------------------
        // [v1.2.0] Strength per setting. Level 3 is what the earlier build ran
        // at all the time, and it was too strong to live with.
        #if UNDERWATER_WAVES == 0
        float uwAmp = 0.0;
        #elif UNDERWATER_WAVES == 2
        float uwAmp = 0.10;
        #elif UNDERWATER_WAVES == 3
        float uwAmp = 0.16;
        #else
        float uwAmp = 0.05;
        #endif
        #if UNDERWATER_WAVES == 0
        vec2 uwGrad = vec2(0.0);          // off: skip the whole spectrum here
        #else
        vec2 uwGrad = waterRippleOffset(uwWorldPos.xz, uwTime);
        #endif
        float depthFade = smoothstep(0.15, 4.0, abs(uwViewPos.z));
        vec2 rippleOffset = uwGrad * uwAmp * depthFade
                          + vec2(sin(uwWorldPos.z * 1.9 + uwTime * 1.7),
                                 cos(uwWorldPos.x * 1.7 + uwTime * 1.5))
                            * (0.0011 * smoothstep(1.0, 14.0, abs(uwViewPos.z)));

        // The surface tilt relative to the sun: a slope facing the sun passes more
        // light, a slope turned away passes less. This is the only brightness cue
        // left when reflections are disabled, and it is what makes the underside
        // of a swell roll as it travels overhead.
        float uwTilt = dot(normalize(vec3(uwGrad.x, 1.0, uwGrad.y)),
                           normalize(vec3(uwSunDir.x, 1.0, uwSunDir.z)));
        #if UNDERWATER_WAVES == 0
        float uwShade = 1.0;
        #elif UNDERWATER_WAVES == 2
        float uwShade = mix(0.76, 1.24, clamp(uwTilt * 0.5 + 0.5, 0.0, 1.0));
        #elif UNDERWATER_WAVES == 3
        float uwShade = mix(0.60, 1.45, clamp(uwTilt * 0.5 + 0.5, 0.0, 1.0));
        #else
        float uwShade = mix(0.86, 1.13, clamp(uwTilt * 0.5 + 0.5, 0.0, 1.0));
        #endif
        uwShade = mix(1.0, uwShade, smoothstep(0.0, 0.35, causticGate + 0.25));

        vec2 distortedUV = clamp(texcoord + rippleOffset, vec2(0.001), vec2(0.999));
        color = texture(colortex0, distortedUV).rgb * mix(1.0, caustic, causticGate) * uwShade;

        // ---------------------------------------------------------------------
        // 3. THE SURFACE ITSELF, when the pixel IS the underside of the water.
        // It must read as a rolling mirror, not as a flat pane: scale its
        // brightness by the same slope, harder than the water behind it.
        // ---------------------------------------------------------------------
        #if UNDERWATER_WAVES > 1
        if (isWaterSurface) {
            color *= mix(1.0, uwShade, 0.55);
            color += vec3(0.06, 0.09, 0.10) * clamp(uwTilt, 0.0, 1.0) * causticGate;
        }
        #endif
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
    // [v1.2.0] Water column and surface height, needed by the refraction
    // block when looking straight down.
    vec2 waterWorldXZ = vec2(0.0);
    float waterWaveHeight = 0.0;

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
        // ==================================================================
        // [v1.2.0] WATER NORMAL IS ANALYTICAL, NOT FROM DEPTH.
        // ==================================================================
        // Here the normal was collected from the depth buffer by finite differences in
        // neighboring pixels, and then turned over twice with a hard test
        //     if (waterNormal.z > 0.0) waterNormal = -waterNormal;
        // This drew a pattern on the water. The reasons were:
        // 1) difference between neighboring depth values at 40 blocks from the camera
        // comparable to buffer accuracy. The normal turns out to be stepwise:
        // between neighboring pixels it jumps between a few
        // values, and does not change smoothly;
        // 2) a hard flip according to the z sign turns this step into a BREAK:
        // where z changes sign, the normal is instantly reflected, and on
        // a sharp boundary appears in the lighting;
        // 3) another addition to the normal was superimposed on top (in the tangent
        // basis, also from depth differences), that is, the waves were considered
        // twice and in different spaces;
        // 4) the same corrupted normal set the shift of the bottom sample, therefore
        // the spots on the bottom went in even steps.
        // The pack ALREADY knows the wave field: auraliteWaveField() - the same function as
        // picks up the geometry in gbuffers_water.vsh. Its gradient is
        // regular inclined surface: smooth, deterministic, without
        // noise and no depth reading. We assemble the normal directly from it.
        // Nothing is selected: the field amplitude is taken from the same place as
        // and for geometry, and the slope is physically limited (slope > 1 is
        // no longer a wave, but a wall).
        vec3 vpHereA = screenToView(texcoord, depth);
        vec3 worldPosA = (gbufferModelViewInverse * vec4(vpHereA, 1.0)).xyz + cameraPosition;
        waterWorldXZ = worldPosA.xz;                       // for refraction
        waterWaveHeight = auraliteWaveField(worldPosA.xz, frameTimeCounter, 0.30, true).x;

        float waveSlope = 1.0;
        #if WATER_WAVE_SCALE == 1
        waveSlope = 0.45;
        #elif WATER_WAVE_SCALE == 3
        waveSlope = 1.45;
        #elif WATER_WAVE_SCALE == 4
        waveSlope = 1.90;
        #endif
        vec2 gradW = waterRippleOffset(worldPosA.xz, frameTimeCounter) * waveSlope;
        gradW = clamp(gradW, vec2(-0.75), vec2(0.75));     // physical limit of steepness
        vec3 nWorld = normalize(vec3(-gradW.x, 1.0, -gradW.y));
        waterNormal = normalize(mat3(gbufferModelView) * nWorld);

        // One reference point instead of a hard flip according to the z sign: the normal must
        // look at the camera. The scalar product changes sign smoothly and
        // does not cause ruptures.
        vec3 Vv = normalize(-vpHereA);
        if (dot(waterNormal, Vv) < 0.0) waterNormal = -waterNormal;
        haveWaterNormal = true;
    }

    // ==================================================================
    // [v1.0.3] SCREEN-SPACE WATER REFRACTION
    // When looking at water from above, the underwater scene is read
    // through a displaced UV computed from the wave normal. This gives
    // physically-plausible distortion of the bottom without feedback
    // loops.
    // [v1.2.0] The strength is now driven by the WATER COLUMN, not by
    // (1 - N·V).
    // Looking straight down at water, EVERY other wave cue this engine has
    // disappears at once:
    //   * Fresnel reflection is F0 = 0.02 at normal incidence -> no sky mirror;
    //   * specular is Fresnel-weighted           -> no sun glint;
    //   * refraction used (1 - N·V)              -> exactly 0.
    // The old note called that "Snell's law approximation". It is not: Snell's
    // law is the reason the bottom looks SHIFTED, and the shift does not vanish
    // head-on. A surface slope a displaces the refracted bottom by roughly
    //   depth * a * (1 - 1/n)  ~  0.25 * depth * a,
    // which is largest per slope exactly when you look straight down -- that is
    // why a real rock under water swims when you stand over it, and why the
    // water looked like a flat sheet here.
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

        // How much water is between the surface and the bottom along this view
        // ray. Read the unrefracted depth first; that is the bottom behind the
        // water at this very pixel.
        float bottomDepthS;
        #ifdef DISTANT_HORIZONS
        bottomDepthS = useDHRefraction ? texture(dhDepthTex1, texcoord).r
                                       : texture(depthtex1, texcoord).r;
        #else
        bottomDepthS = texture(depthtex1, texcoord).r;
        #endif
        vec3 vpBottom;
        #ifdef DISTANT_HORIZONS
        vpBottom = useDHRefraction ? dhScreenToView(texcoord, bottomDepthS)
                                   : screenToView(texcoord, bottomDepthS);
        #else
        vpBottom = screenToView(texcoord, bottomDepthS);
        #endif
        vec3 columnVec = vpBottom - vpHere;
        float waterColumn = clamp(length(columnVec), 0.0, 24.0); // blocks
        // [v1.2.0] Vertical water column: light comes to the bottom from above,
        // that is, it passes through it, and not the length of the gaze ray.
        float columnVertical = clamp(abs(columnVec.y), 0.0, 24.0); // blocks

        vec3 V = normalize(-vpHere);
        float NoV = clamp(dot(waterNormal, V), 0.0, 1.0);

        // Apparent lateral shift of the bottom: column * slope * (1 - 1/1.333),
        // converted to screen UV with the on-screen scale at that distance.
        // A shallow puddle distorts almost nothing, deep water a lot -- the
        // strength now comes from the scene instead of a magic constant, and a
        // mild angular term keeps grazing view a little stronger (longer path
        // through the column, more amplification of the slope).
        float refractEta = 1.0 - 1.0 / 1.333;
        // 0.714 = 1 / (2 * tan(half vertical FOV)) at ~70 deg: turns a lateral
        // displacement in blocks into a screen-space UV offset at that distance.
        float screenScale = 0.714 / max(length(vpBottom), 0.5);
        // Physical term (survives a head-on view) plus a modest grazing term that
        // keeps the previous look at shallow angles, where the reflected sky
        // already carries most of the wave motion.
        float refractStrength = 1.50 * refractEta * waterColumn * screenScale
                              + 0.34 * (1.0 - NoV);
        // Cap in PIXELS, not in UV: the same UV offset is a 15 px jump at 1080p,
        // which is what let the sample escape onto neighbouring geometry.
        vec2 pixelSize = 1.0 / max(vec2(viewWidth, viewHeight), vec2(1.0));
        vec2 refractOffset = clamp(waterNormal.xz * refractStrength,
                                   -pixelSize * 7.0, pixelSize * 7.0);
        vec2 refractedUV = texcoord + refractOffset;

        float refractedDepthS;
        #ifdef DISTANT_HORIZONS
        refractedDepthS = useDHRefraction ? texture(dhDepthTex1, refractedUV).r
                                          : texture(depthtex1, refractedUV).r;
        #else
        refractedDepthS = texture(depthtex1, refractedUV).r;
        #endif
        // [v1.2.0] The offset used to be unbounded in screen space, and any
        // sample that passed the depth test was accepted -- including a sample
        // that landed on ANOTHER piece of the water surface. That pixel holds the
        // dark water albedo instead of the sand, so the sand showed moving dark
        // blotches. Reject samples that are themselves tagged as water, and keep
        // the offset within a few pixels.
        // [v1.2.0] MAIN CORRECTION OF STAINS ON SAND.
        // ------------------------------------------------------------------
        // The bottom sample was rejected if it “itself is water” - but only by software
        // LABEL colortex2.a. On this Iris assembly the water mark is lost
        // (0.00 - measured), then it mixes up to 0.84, then it’s not there at all, so
        // checking by label skips neighboring WATER pixels. And a sample from them
        // brings the color of water (dark blue) rather than sand. Hence exactly what
        // visible in the frames: stepped rectangular spots (the shift is limited
        // 7 px, step per block) with noise inside (the shift sets the wave normal),
        // dark [14,18,29] with white sand [250] nearby, independent of
        // shadows, nor from cloud shadows.
        // A couple of depths cannot lie - the pack already holds on this same property
        // definition of water in composite.fsh: if there is TRANSPARENT at the point
        // surface, then depthtex0 is closer than depthtex1. Checking the point
        // sample exactly like this, and leave the label as a second, independent condition.
        float refractedTagA = texture(colortex2, refractedUV).a;
        bool refractedTaggedWater = (abs(refractedTagA - 0.8) < 0.10) ||
                                    (refractedTagA > 0.72 && refractedTagA < 0.97);
        float refrD0 = texture(depthtex0, refractedUV).r;
        float refrD1 = texture(depthtex1, refractedUV).r;
        bool refractedDepthWater = (refrD1 - refrD0) > 1e-5;
        bool refractedIsWater = refractedTaggedWater || refractedDepthWater;
        bool validRefraction = all(greaterThanEqual(refractedUV, vec2(0.0)))
                            && all(lessThanEqual(refractedUV, vec2(1.0)))
                            && refractedDepthS > surfaceDepth + 1e-4
                            && refractedDepthS < 1.0
                            && !refractedIsWater;

        bool bedUnderPixel = (bottomDepthS > surfaceDepth + 1e-4 && bottomDepthS < 1.0);
        bool bedValid = false;
        vec2 bedUV = texcoord;
        if (validRefraction) {
            bedValid = true;
            bedUV = refractedUV;
        } else {
            // the shift is rejected - we read the bottom directly under the pixel
            bedValid = bedUnderPixel;
        }
        if (bedValid) {
            vec3 bed = texture(colortex0, bedUV).rgb;
            // [v1.2.0] Second cue that survives a head-on view: the wave
            // moves the surface up and down, so the column of water the light
            // travels through gets shorter over a crest and longer in a trough.
            // Water absorbs along that path, so the bottom brightens on crests.
            // Bounded, physical, and invisible at grazing angles where the
            // column barely changes relative to its length.
            bed *= mix(1.0, exp(-waterWaveHeight * 0.9), 0.65);

            // [v1.2.0] WATER IS A BODY, NOT A SHEET OF GLASS.
            // ------------------------------------------------------------------
            // Before this edit, the bottom under water was simply SUBSTITUTED instead of color
            // water: `color = texture(colortex0, refractedUV).rgb`. None
            // there was no member to weaken it along the way, so the color
            // any dark spot on the bottom (gravel, stone, shadow of a cloud on the bottom)
            // came to the eye with the same brightness as on land. At depth
            // 4-10 blocks this gave brown and blue blots on the surface of the water
            // instead of water, and in shallow water there was no difference at all from land.
            // Physically, a column of water is a scattering and absorbing medium. Light
            // passes it TWICE (down to the bottom and back to the eye), so
            // optical path = 2 * waterColumn. Bouguer-Lambert transmission:
            //     T = exp(-2 * column * sigma)
            // The sigma coefficients are taken to be the same as those that already work underwater in
            // composite.fsh (v1.1.3): pure water (0.18, 0.045, 0.015) 1/block,
            // muddy swamp (0.23, 0.038, 0.10) 1/block. Nothing new
            // made up - this is the same water as from the inside.
            // The second term is the pillar’s own glow (single scattering):
            // (1 - T) from the color of the illuminated water at this point. Deep without him
            // the water would go into black: with 24 blocks T in red = 2e-4.
            // The color is taken from colortex0 at the CURRENT pixel, that is, it is exactly
            // that water that the pack already considered illuminated (with shadow, sky and
            // cloudy shadow) - there are no new constants.
            // What does this do to the picture (numbers are for water by default, look
            // from above): at 1 m from the bottom 43% of red remains, at 2 m - 19%,
            // at 4 m - 3.5%, at 6 m - 0.1%. The shallow water near the shore is clear,
            // the depth becomes water. The shallow water near the shore remains clear, the depth becomes
            // water. No dithering, noise or tweaking by eye.
            #if defined(AUR_WATER_BODY)
            {
            // Attenuation = absorption + turbidity.
            // Absorption - the same coefficients that already work underwater
            // (composite.fsh v1.1.3): pure water (0.18, 0.045, 0.015) 1/block,
            // swamp (0.23, 0.038, 0.10) 1/block;
            // Turbidity is a gray dispersion in suspended matter, and its value is derived from
            // transparency according to the Secchi disk, and not selected by eye:
            // attenuation index c = 1.7 / z_Secchi (standard ratio
            // Secchi: The white disk is no longer visible when the contrast drops to
            // ~2%, for water this gives exactly c ≈ 1.7/z). Take z = 6 m
            // (mesotrophic lake; oligotrophic 5-15 m, eutrophic 1-3 m), then
            // there is c = 0.283 1/block, of which 0.045 is the intrinsic absorption in
            // green, the rest 0.238 is scattering. WATER_TRANSPARENCY option
            // sets the water class: 1 - transparent (z = 10 m), 2 - lake (6 m),
            // 3 - muddy (4 m). There are no new sliders.
            float secchiZ = 6.0;
            #if WATER_TRANSPARENCY == 1
            secchiZ = 10.0;
            #elif WATER_TRANSPARENCY == 3
            secchiZ = 4.0;
            #endif
            float sigmaScatter = max(1.7 / secchiZ - 0.045, 0.0);
            vec3 sigmaWater = mix(vec3(0.18, 0.045, 0.015),
                                  vec3(0.23, 0.038, 0.10),
                                  clamp(isSwampBiome, 0.0, 1.0))
                            + vec3(sigmaScatter);
            // Optical path: light travels vertically to the bottom and back to the eye
            // along the line of sight. Directly from above, both segments are equal to the depth (2*d), with
            // When viewed along the surface, the vertical is short and the beam is long.
            vec3 transmit = exp(-(waterColumn + columnVertical) * sigmaWater);
            color = bed * transmit + color * (1.0 - transmit);
            }
            #else
            color = bed;
            #endif
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
        // Reuse the MRT-proof decision made at the top of
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
        // Depth-rescued water can arrive with a cleared
        // colortex2.a (= 0.0 → looks "emissive") on broken-MRT Iris builds;
        // do not let that zero its reflectivity. Real portals/lava were
        // already excluded from isWaterSurfaceInner by the albedo guards.
        if (emissive > 0.5 && !isWaterSurfaceInner) reflectivity = 0.0;

        // Underwater: don't reflect anything (camera is INSIDE the water column)
        if (isEyeInWater == 1) reflectivity = 0.0;


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
                vec3 waterSunDir = auraliteSunDir(sunPosition, shadowLightPosition);
                waterDay = smoothstep(-0.150, 0.045, waterSunDir.y);
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

    // Use isRealGeometry (checks dhDepthTex0 too) instead of raw
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
    // [v1.2.0] LINEAR GRADING STAGE: exposure * per-channel gain, applied
    // before tone mapping. Everything that physically acts on incoming light
    // happens here; display-referred controls wait until after the encode below.
    float expFactor = COLOR_EXPOSURE;
    vec3  gradeFac  = expFactor * auraliteGradingGain();
    color *= gradeFac;

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
    color = applyFXAA(texcoord, color, gradeFac);
    #elif SPATIAL_AA_MODE == 2
    color = applySMAA(texcoord, color, gradeFac);
    #endif

    // ==========================================================================
    // [v1.2.0] STABLE ORDERED DITHER, NOT PER-FRAME NOISE.
    // --------------------------------------------------------------------------
    // The previous line fed two fract(sin(...)) hashes of gl_FragCoord in. Two
    // things were wrong with that:
    //   * it is a HASH, not a dither: adjacent pixels are uncorrelated, so the
    //     result is grain, and grain on a moving camera reads as "the whole
    //     picture is boiling";
    //   * the hashes are re-evaluated every frame, and the sine product is not
    //     stable in float, so the pattern *shimmered* even when nothing moved.
    // A 4x4 ordered (Bayer) matrix has the same job -- turn an 8-bit quantisation
    // step into a spatial average -- while being fixed to the pixel grid: it does
    // not crawl, it disappears at a distance, and it costs 4 constants instead of
    // two transcendental functions.
    // Sky pixels are excluded, as before: the sky has its own gradient handling and
    // the cloud march is deterministic.
    if (isRealGeometry) {
        float ditherAmp = 0.5 / 255.0;
        #if DITHER_STRENGTH == 1
        ditherAmp = 0.0;
        #elif DITHER_STRENGTH == 3
        ditherAmp = 0.75 / 255.0;
        #elif DITHER_STRENGTH == 4
        ditherAmp = 1.0 / 255.0;
        #endif
        ivec2 ditherCell = ivec2(gl_FragCoord.xy) & 3;
        const float BAYER4[16] = float[16](
             0.0,  8.0,  2.0, 10.0,
            12.0,  4.0, 14.0,  6.0,
             3.0, 11.0,  1.0,  9.0,
            15.0,  7.0, 13.0,  5.0);
        float bayer = BAYER4[ditherCell.y * 4 + ditherCell.x] * (1.0 / 16.0) - 0.5;
        // Triangular weighting of two independent ordered taps would need a second
        // grid; a single centred Bayer tap at half the amplitude is visually just as
        // quiet and does not break the fixed pattern.
        color += bayer * ditherAmp;
    }

    color = auraliteToneMap(color);

    // --------------------------------------------------------------------------
    // DISPLAY-REFERRED GRADING [v1.2.0]
    // Everything below acts on the tone-mapped, encoded image, which is the space
    // the user is actually looking at. With every slider at its default the whole
    // block collapses to the v1.1.4 chain (pow 1/2.2 -> vignette -> vibrancy),
    // so a fresh install is unchanged.
    // --------------------------------------------------------------------------
    color = pow(max(color, vec3(0.0)), vec3(1.0 / max(COLOR_GAMMA, 0.10)));

    // Midtone lift. pow() keeps 0.0 at 0.0 and 1.0 at 1.0, so this moves the
    // curve instead of scaling it -- it cannot clip highlights or float blacks.
    color = pow(max(color, vec3(0.0)), vec3(1.0 / max(COLOR_BRIGHTNESS, 0.10)));

    // Contrast pivots on middle grey, the classic brightness-contrast operation.
    color = clamp((color - 0.5) * COLOR_CONTRAST + 0.5, 0.0, 1.0);

    // Saturation: interpolate between the pixel's own Rec.709 grey and itself.
    float gradeLuma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(gradeLuma), color, max(COLOR_SATURATION, 0.0));

    #ifdef VIGNETTE
    vec2 uv = texcoord - 0.5;
    float vignette = 1.0 - dot(uv, uv) * 0.38 * COLOR_VIGNETTE;
    color *= clamp(vignette, 0.0, 1.0);
    #endif

    // Vibrance last: it is per-pixel (muted colours move more than saturated
    // ones), so it has to see the final hue relationships. The -0.06 reproduces
    // the pack's historic value; the slider adds to it, 0.00 = unchanged.
    color = applyVibrancy(color, COLOR_VIBRANCE - 0.06);

    // Dither was applied in linear space before tone mapping (see above), so the
    // tone curve and the gamma encoding both spread it instead of preserving it as
    // grain. Nothing is added after this point.

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}

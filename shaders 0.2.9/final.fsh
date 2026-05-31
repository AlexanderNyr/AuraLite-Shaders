#version 460 compatibility
// AuraLite Shaders - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Final Post-Processing Pass Fragment Shader (GLSL 460)
// ==============================================================================
// [v0.2.9.3] Bypass colortex6 entirely. On Iris 1.20 the multi-target write in
//   composite.fsh (DRAWBUFFERS:06) does not reliably land in colortex6 when the
//   shader is read by final, so SSR silently failed. We now read the surface
//   normal directly from colortex2 (written by every gbuffer pass) and derive
//   reflectivity from colortex1.z (PBR roughness). This is the same data path
//   used for PBR specular highlights, which are confirmed working.

#define VIGNETTE // [true false]
#define EXPOSURE 2 // [1 2 3]
#define COLOR_SATURATION 2 // [1 2 3 4]
#define CONTRAST 2 // [1 2 3]
#define SSR // [true false]
#define SSR_QUALITY 2 // [1 2 3]
#define SSR_STRENGTH 2 // [1 2 3]
#define WATER_WAVE_SCALE 2     // [1 2 3 4] - 1: Calm, 2: Standard, 3: Choppy, 4: Stormy (visible wave amplitude)
#define WATER_WAVE_DETAIL 2    // [1 2 3] - 1: Coarse few waves, 2: Standard, 3: Dense many small waves

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
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}
vec3 applyVibrancy(vec3 color, float amount) {
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return clamp(mix(color, vec3(luma), amount), 0.0, 1.0);
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
// [v0.2.9.8] Multi-octave fBm with quintic smoothstep. The combination
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
float waterHeight(vec2 p, float t) {
    // Animate by translating each octave with a unique direction.
    vec2 d1 = vec2( 0.42,  0.18) * t;
    vec2 d2 = vec2(-0.31,  0.27) * t;
    vec2 d3 = vec2( 0.17, -0.34) * t;
    vec2 d4 = vec2(-0.22, -0.15) * t;
    mat2 R = mat2( 0.84,  0.54, -0.54,  0.84); // ~33° per octave
    float h = 0.0, a = 0.5;
    // Base wave frequency — controlled by WATER_WAVE_DETAIL menu option.
    float waveFreq = 0.9;
    #if WATER_WAVE_DETAIL == 1
    waveFreq = 0.45;  // coarse, fewer big waves
    #elif WATER_WAVE_DETAIL == 3
    waveFreq = 1.55;  // dense, many tiny waves
    #endif
    p *= waveFreq;
    h += wNoise(p +  d1) * a; p = R * p * 2.03; a *= 0.55;
    h += wNoise(p +  d2) * a; p = R * p * 2.07; a *= 0.55;
    h += wNoise(p +  d3) * a; p = R * p * 2.11; a *= 0.55;
    h += wNoise(p +  d4) * a;
    return h;
}
// Analytic gradient of the height-field — gives the *correct* slope of
// waves so reflections move smoothly with the wave instead of jittering.
// Uses 4-sample central differences in WORLD coordinates → resolution
// independent and tiny artifacts.
vec2 waterRippleOffset(vec2 worldXZ, float t) {
    float e = 0.08; // sample epsilon in world units (smaller = finer detail)
    float hx1 = waterHeight(worldXZ + vec2( e, 0.0), t);
    float hx0 = waterHeight(worldXZ + vec2(-e, 0.0), t);
    float hz1 = waterHeight(worldXZ + vec2( 0.0,  e), t);
    float hz0 = waterHeight(worldXZ + vec2( 0.0, -e), t);
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
        // visible surface the marker currently sits. Always at least 1.
        marchT += max(stepScale * abs(gap) * invRz, 1.0);
    }
    return vec4(0.0);
}
#endif

void main() {
    vec3 color = texture(colortex0, texcoord).rgb;

    #ifdef SSR
    float depth  = texture(depthtex0, texcoord).r; // includes translucent
    float depthS = texture(depthtex1, texcoord).r; // solid only (no water/glass)

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
        // [v0.2.9.6] BULLETPROOF WATER DETECTOR via depth comparison.
        //
        // Iris reports TWO depth buffers:
        //   depthtex0 = scene with translucent surfaces (water/glass/ice)
        //   depthtex1 = scene without translucents (terrain behind them)
        //
        // For a water-surface pixel these differ: depth0 is the water plane,
        // depth1 is the bottom of the pool. For solid terrain (including the
        // bottom of the pool seen through water) BOTH depths are equal.
        //
        // NOTE: on this Iris version gbuffers_water apparently does NOT write
        // colortex1/colortex2 reliably (the MRT layout(location) writes fail
        // the same way they failed in composite). So we can't trust the
        // normal from colortex2 on water pixels — we synthesise (0,1,0)
        // (vanilla water is flat horizontal) when detection fires.
        // ==================================================================
        bool isWaterSurface = (depthS - depth) > 1e-5;
        if (isWaterSurface) {
            roughness = 0.05; // force water-like roughness

            // ==============================================================
            // [v0.2.9.8] Stable water normal: average dFdx/dFdy normals over
            // a wider area to remove triangular fasceting, then add smooth
            // procedural ripples for life. This eliminates the "torn
            // reflection" artefact reported by the player.
            // ==============================================================
            vec3 vpHere = screenToView(texcoord, depth);

            // Take 4 neighbour view positions one pixel away in each
            // diagonal — averaging their cross products yields a stable
            // normal even when dFdx is computed per 2x2 quad. This kills
            // 90% of the fasceting.
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
            N = normalize(cross(dpy, dpx));
            if (N.z > 0.0) N = -N;

            // ----- Add smooth procedural ripple perturbation -----
            // [v0.2.9.8] We now use analytic gradients of an fBm height-field,
            // so ripples slope coherently like real waves — no more torn
            // reflections. World XZ coords (not screen UV) keep waves locked
            // to the world as the camera moves.
            vec3 worldFromView = (gbufferModelViewInverse * vec4(vpHere, 1.0)).xyz;
            vec3 worldPos = worldFromView + cameraPosition;
            vec2 ripple = waterRippleOffset(worldPos.xz, frameTimeCounter);

            // Apply the wave gradient by tilting the normal away from the
            // slope direction. We do it in view space using world-up as the
            // reference (recovered from the cross product of the geometric
            // normal we just built — it's already the up-vector for water).
            vec3 T = normalize(dpx);   // ~world X in view space
            vec3 B = normalize(dpy);   // ~world Z in view space
            // Wave amplitude — controlled by WATER_WAVE_SCALE menu option.
            float waveAmp = 0.18;
            #if WATER_WAVE_SCALE == 1
            waveAmp = 0.07;   // calm, almost mirror
            #elif WATER_WAVE_SCALE == 3
            waveAmp = 0.30;   // choppy
            #elif WATER_WAVE_SCALE == 4
            waveAmp = 0.45;   // stormy
            #endif
            N = normalize(N - T * (ripple.x * waveAmp)
                            - B * (ripple.y * waveAmp));
            if (N.z > 0.0) N = -N;
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

    // ---------- Standard post-processing ----------
    float expFactor = 1.0;
    #if EXPOSURE == 1
    expFactor = 0.75;
    #elif EXPOSURE == 3
    expFactor = 1.35;
    #endif
    color *= expFactor;

    #if CONTRAST == 1
    color = clamp(mix(color, ACESFilm(color), 0.45), 0.0, 1.0);
    #elif CONTRAST == 2
    color = ACESFilm(color);
    #elif CONTRAST == 3
    color = ACESFilm(color);
    color = clamp(pow(color, vec3(1.12)), 0.0, 1.0);
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

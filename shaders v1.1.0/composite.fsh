#version 460 compatibility
// AuraLite Shaders v1.1.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Fullscreen Composite Pass (GLSL 460 - Enhanced Lighting)
// [v1.0.7] Massive Volumetric Cloud & Godray ALU Optimization (20x speedup!).
// [v1.0.7] Fixed PCSS blocker search slope bias acne & removed underwater unlit albedo feedback loop.
// [v1.0.4-fixed] Replaced fma() with direct multiply-add for GLSL compatibility.
// ==============================================================================
// [FIX v0.2.3] All texture2D() replaced with texture() for GLSL 460 consistency.
// [FIX v0.2.3] CLOUD_HEIGHT / CLOUD_THICKNESS now wired to renderVolumetricClouds.
// [FIX v0.2.3] GROUND_MIST #define added so the toggle in shaders.properties works.
// [FIX v0.2.3] SUN_TEMPERATURE applied to skybasic-synced getSolarKelvin in this file.
// [FIX v0.2.5] PBR specular now includes the cosine (NdotL) factor for correct BRDF.
// [FIX v0.2.5] Shadow slope bias now uses rawNdotL (not light-wrapped) to prevent acne.
// [FIX v0.2.5] Removed redundant second projectAndDivide() call — compute viewPos once.
// [FIX v0.2.5] Emissive pixel detection via colortex2.a < 0.5 (portals skip lighting).
// [FIX v0.2.5] Cloud pass refined at the same 12 ray steps: jittered sampling, soft layer edges, better phase lighting.
// [FIX v0.2.5] Removed screen-space cloud jitter; clouds no longer change appearance when rotating camera.
// [FIX v0.2.5] Cloud samples are now height-anchored for stable appearance while rotating the camera.
// [FIX v0.2.5] Cloud self-shadowing lifted so cloud undersides are not crushed black.
// [FIX v0.2.5] Added camera-inside-cloud volumetric veil/fog effect.
// [FIX v0.2.5] Cloud render distance now scales with quality profile via CLOUD_DISTANCE.
// [FIX v0.2.5] Cloud render distance range expanded: LOW 3000 / MED 6000 / HIGH 10000 / ULTRA 16000.
// [FIX v0.2.5] Cloud layers now use independent wind-shear offsets and move with WIND_SPEED.
// [FIX v0.2.5] Cloud layers now use separate rotated/sheared domains so upper layers are not copies of lower layers.
// [FIX v0.2.5] Removed per-pixel random shadow rotation to eliminate noisy/dancing shadow edges.
// [FIX v0.2.5] Added EXTREME-profile SSAO/SAO-style contact ambient occlusion.
// [FIX v0.2.5] Sunset/twilight lighting stays red at /time set 12800 instead of turning neutral.

#define SHADOWS             // [true false]
#define SHADOW_RES 2048     // [1024 2048 4096]
#define SHADOW_SOFTNESS 2   // [1 2 3] - 1: Sharp, 2: Soft, 3: Ultra Soft
#define LIGHTMAP_WARMTH 3   // [1 2 3]
#define FOG_DENSITY_LEVEL 2 // [1 2 3]
#define PBR_LIGHTING        // [true false]
#define PBR_STRENGTH 2      // [1 2 3]
#define PBR_DISTANCE 2      // [1 2 3 4] - 1: Near (32m), 2: Standard (64m), 3: Far (128m), 4: Unlimited
#define SSAO               // [true false] - EXTREME profile: screen-space ambient occlusion
#define SSAO_STRENGTH 2     // [1 2 3] - 1: Subtle, 2: Balanced, 3: Deep
#define PROCEDURAL_CLOUDS   // [true false]
#define CLOUD_HEIGHT 3      // [1 2 3]
#define CLOUD_THICKNESS 2   // [1 2 3]
#define CLOUD_DISTANCE 2    // [1 2 3 4] - 1: Near, 2: Standard, 3: Far, 4: Very Far
#define CLOUD_SHADOWS       // [true false] - Procedural transparent shadows from cloud density
#define CLOUD_SHADOW_STRENGTH 2 // [1 2 3] - 1: Soft, 2: Balanced, 3: Dramatic
#define GODRAYS             // [true false] - [v1.1.0] TRUE volumetric raymarched light shafts (shadow-map occluded)
#define GODRAYS_QUALITY 1   // [1 2 3] - 1: Fast (8 samples), 2: Balanced (16), 3: High (24)
#define GODRAYS_STRENGTH 2  // [1 2 3] - 1: Subtle, 2: Balanced, 3: Dramatic
#define TAA                 // [true false] - [v1.1.0] Mirrored here so godray dither rotates per-frame only when TAA resolves it
#define WIND_SPEED 2        // [1 2 3] - shared with foliage/water; also controls cloud wind drift

// ==============================================================================
// SUN & MOON LIGHTING - Extended customization (v0.2.1+)
// ==============================================================================
#define SUN_INTENSITY 2        // [1 2 3 4] - 1: Dim, 2: Standard, 3: Bright, 4: Blazing
#define MOON_INTENSITY 2       // [1 2 3 4] - 1: Pitch Night, 2: Standard, 3: Bright Moon, 4: Bright Night
#define SUN_TEMPERATURE 2      // [1 2 3] - 1: Cool/Neutral, 2: Realistic, 3: Warm/Golden
#define MOON_TEMPERATURE 2     // [1 2 3] - 1: Icy Blue, 2: Silver, 3: Warm Cream
#define SHADOW_DISTANCE 2      // [1 2 3 4] - 1: 60m, 2: 80m, 3: 120m, 4: 160m
#define AMBIENT_BRIGHTNESS 2   // [1 2 3] - 1: Dark Shadows, 2: Standard, 3: Lifted Shadows
#define SHADOW_TINT 2          // [1 2 3] - 1: Neutral Gray, 2: Cool Blue (realistic), 3: Warm
#define LIGHT_WRAP 1           // [1 2 3] - 1: Realistic (Lambert), 2: Soft Wrap, 3: Stylized
#define SUNRISE_GLOW           // [true false] - Warm back-scatter near sunrise/sunset
#define SUN_HALO               // [true false] - Mie-scattering halo around the sun on terrain

// Dynamic New Customizable Options!
#define AURORA_MODE 2       // [0 1 2] - 0: Off, 1: Cold Biomes, 2: Always Enabled
#define AURORA_SPEED 2      // [1 2 3] - 1: Slow, 2: Standard, 3: Fast
#define AURORA_STRENGTH 2   // [1 2 3] - 1: Soft, 2: Standard, 3: Glowing
#define NEBULA_BRIGHTNESS 2 // [1 2 3] - 1: Dim, 2: Standard, 3: Vivid
#define STARS_BRIGHTNESS 2  // [1 2 3] - 1: Faint, 2: Standard, 3: Brilliant
#define STARS_AMOUNT 2      // [1 2 3] - 1: Few, 2: Standard, 3: Dense
#define RAINBOW_STRENGTH 2  // [1 2 3] - 1: Subtle, 2: Balanced, 3: Vivid
#define COZY_LIGHTS         // [true false] - Toggles torch flickering animation
#define WET_REFLECTIONS     // [true false] - Toggles wet reflections during rain
#define GROUND_MIST         // [true false] - [FIX v0.2.3] Added missing define
#define FOLIAGE_SSS         // [true false] - Subsurface scattering for leaves and plants

// ==============================================================================
// SCREEN-SPACE REFLECTIONS (SSR) - v0.2.9
// ==============================================================================
#define SSR                 // [true false] - Screen-space reflections for water, wet surfaces and metals
#define SSR_QUALITY 2        // [1 2 3] - 1: Fast (12 steps), 2: Balanced (24 steps), 3: High (40 steps)
#define SSR_STRENGTH 2       // [1 2 3] - 1: Subtle, 2: Balanced, 3: Strong

// ==============================================================================
// UNDERWATER ATMOSPHERE - v0.2.9
// ==============================================================================
#define UNDERWATER_NIGHT_DARKNESS 3 // [1 2 3 4] - 1: Moonlit pool, 2: Dim, 3: True night, 4: Pitch dark

/* DRAWBUFFERS:0 */

uniform sampler2D colortex0; // Albedo / baked color from gbuffers
uniform sampler2D colortex1; // Lightmap coordinates, PBR Roughness (z), Metalness (w)
uniform sampler2D colortex2; // Normals (Packed in view space), alpha < 0.5 = emissive
uniform sampler2D depthtex0; // World depth buffer
uniform sampler2D shadowtex0; // Shadow depth buffer

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 shadowLightPosition; // Active light source direction (Sun/Moon)
uniform vec3 cameraPosition;      // Player's actual world coordinates
uniform float frameTimeCounter;
uniform int frameCounter;         // [v1.1.0] Frame index for temporal godray dithering (TAA-friendly)
uniform float rainStrength;
uniform float thunderStrength; // Blends thunderstorm vs standard rain
uniform float wetness; // Moisture decay after rain (used for persistent rainbows!)
uniform float viewWidth;
uniform float viewHeight;
uniform int worldTime;
uniform int moonPhase; // Moon phase 0-7 for moonlight brightness scaling
uniform vec3 fogColor; // Standard uniform containing Minecraft's dimension-specific fog color!
uniform int dimension; // Standard Minecraft dimension uniform (-1: Nether, 0: Overworld, 1: End)

// Dynamic Light Uniforms (sends the light level of the held items!)
uniform int heldBlockLightValue;  // Light level of item held in main hand
uniform int heldBlockLightValue2; // Light level of item held in off hand

// Environment uniform to detect if player's eyes are in water/lava
uniform int isEyeInWater; // 0: Air, 1: Water, 2: Lava

// Custom uniform from shaders.properties: 1.0 in cold/snowy biomes, 0.0 elsewhere.
uniform float auroraColdBiome;

// Custom uniforms from shaders.properties for biome-based dimension detection
uniform float isNetherBiome;
uniform float isEndBiome;

in vec2 texcoord;

// Declare explicit output for modern GLSL 460 compatibility
layout(location = 0) out vec4 colortex0Out;
// [v1.0.3] colortex6 output removed — final.fsh now reads normals directly
// from colortex2 and roughness from colortex1, bypassing the unreliable
// multi-target write on Iris 1.20.

// ==============================================================================
// SHADOW DISTORTION (must match shadow.vsh exactly!)
// ==============================================================================
vec3 distortShadowClipPos(vec3 clipPos) {
    float distortFactor = length(clipPos.xy) + 0.1;
    clipPos.xy /= distortFactor;
    clipPos.z *= 0.5;
    return clipPos;
}

// ==============================================================================
// PHYSICALLY ACCURATE KELVIN → sRGB (Tanner Helland algorithm)
// Converts a correlated colour temperature in Kelvin to linear RGB.
// ==============================================================================
vec3 kelvinToRGB(float k) {
    k = clamp(k, 1000.0, 40000.0) / 100.0;
    float r, g, b;

    if (k <= 66.0) {
        r = 255.0;
        g = clamp(99.4708025861 * log(k) - 161.1195681661, 0.0, 255.0);
        if (k < 19.0) {
            b = 0.0;
        } else {
            b = clamp(138.5177312231 * log(k - 10.0) - 305.0447927307, 0.0, 255.0);
        }
    } else {
        r = clamp(329.698727446 * pow(k - 60.0, -0.1332047592), 0.0, 255.0);
        g = clamp(288.1221695283 * pow(k - 60.0, -0.0755148492), 0.0, 255.0);
        b = 255.0;
    }

    return vec3(r, g, b) / 255.0;
}

// ==============================================================================
// REALISTIC SOLAR KELVIN MODEL
// ==============================================================================
float getSolarKelvin(float sinElevation) {
    float t = clamp(sinElevation, 0.0, 1.0);
    float baseK = 2200.0 + 3500.0 * pow(t, 0.62);
#if SUN_TEMPERATURE == 1
    baseK += 600.0;   // Cooler / more neutral white sun
#elif SUN_TEMPERATURE == 3
    baseK -= 500.0;   // Warmer golden sun
#endif
    return clamp(baseK, 1500.0, 7500.0);
}

// Physically-based atmospheric airmass using Kasten & Young (1989) formula
float getAirmass(float sinElevation) {
    float elevDeg = degrees(asin(clamp(sinElevation, 0.001, 1.0)));
    return 1.0 / (sinElevation + 0.50572 * pow(elevDeg + 6.07995, -1.6364));
}

// ==============================================================================
// MOON PHASE BRIGHTNESS MULTIPLIER
// ==============================================================================
float getMoonPhaseBrightness(int phase) {
    float phaseAngle = float(phase) * 0.78539816; // phase * π/4
    float cosHalf = cos(phaseAngle * 0.5);
    return max(0.05, cosHalf * cosHalf);
}

// 100% stable float-based high performance hash
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// 100% stable 3D float-based hash for uniform stars
float hash3D(vec3 p) {
    p = fract(p * vec3(123.34, 456.21, 789.12));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y * p.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0,0.0)), hash(i + vec2(1.0,0.0)), u.x),
               mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), u.x), u.y);
}

const mat2 fbmRotMat = mat2(0.87758256, 0.47942554, -0.47942554, 0.87758256);

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; ++i) {
        v += a * noise(p);
        p = fbmRotMat * p * 2.05 + vec2(100.0);
        a *= 0.5;
    }
    return v;
}

// Profile-controlled cloud render distance. Same ray step count; higher profiles see farther clouds.
float getCloudRenderDistance() {
    // Larger horizon-scale distances. Ray count stays fixed at 12; profiles only extend reach.
    float dist = 6000.0;       // Standard / MED
    #if CLOUD_DISTANCE == 1
    dist = 3000.0;             // LOW: still farther than the old Standard
    #elif CLOUD_DISTANCE == 3
    dist = 10000.0;            // HIGH
    #elif CLOUD_DISTANCE == 4
    dist = 16000.0;            // ULTRA: horizon-scale cloud deck
    #endif
    return dist;
}

float getCloudWindSpeedMultiplier() {
    float speed = 1.0;
    #if WIND_SPEED == 1
    speed = 0.55;
    #elif WIND_SPEED == 3
    speed = 1.65;
    #endif
    // Storm wind pushes cloud layers faster, but does not add more samples.
    return mix(speed, speed * mix(1.25, 1.85, thunderStrength), rainStrength);
}

// Independent layer domains. These cheap linear transforms prevent vertically stacked
// cloud layers from sharing the same footprint/copying each other in XZ space.
vec2 cloudCoordCirrus(vec2 xz) {
    return vec2(dot(xz, vec2( 0.62,  0.78)), dot(xz, vec2(-0.78,  0.62)));
}

vec2 cloudCoordAc(vec2 xz) {
    return vec2(dot(xz, vec2(-0.34,  0.94)), dot(xz, vec2(-1.08, -0.18)));
}

vec2 cloudCoordAlto(vec2 xz) {
    return vec2(dot(xz, vec2( 0.91, -0.41)), dot(xz, vec2( 0.29,  1.13)));
}

vec2 cloudCoordCumulus(vec2 xz) {
    return vec2(dot(xz, vec2( 1.00,  0.16)), dot(xz, vec2(-0.22,  0.96)));
}

// ==============================================================================
// METEOROLOGICAL MULTI-HEIGHT 3D VOLUMETRIC CLOUD ENGINE (4 LAYERS)
// [FIX v0.2.3] CLOUD_HEIGHT / CLOUD_THICKNESS now control actual geometry.
// ==============================================================================
vec4 renderVolumetricClouds(vec3 worldDir, vec3 lightDir, vec3 lightColor, float terrainDist, float dayFactor, float sunsetFactor, float t) {
    // [FIX v0.2.3] Wire CLOUD_HEIGHT define into base altitude
    float cloudBaseY = 160.0;
    #if CLOUD_HEIGHT == 1
    cloudBaseY = 110.0;
    #elif CLOUD_HEIGHT == 3
    cloudBaseY = 240.0;
    #endif

    // [FIX v0.2.3] Wire CLOUD_THICKNESS define into layer span
    float cloudSpan = 230.0;
    #if CLOUD_THICKNESS == 1
    cloudSpan = 140.0;
    #elif CLOUD_THICKNESS == 3
    cloudSpan = 310.0;
    #endif

    float cloudMinY = cloudBaseY;
    float cloudMaxY = cloudBaseY + cloudSpan;
    float cloudRenderDistance = getCloudRenderDistance();

    // Derived layer boundaries (proportional to total span)
    float layerCumulusTop  = cloudMinY + cloudSpan * 0.217;  // ~50m at default
    float layerAltoBottom  = layerCumulusTop;
    float layerAltoTop     = cloudMinY + cloudSpan * 0.435;  // ~100m at default
    float layerAcBottom    = layerAltoTop;
    float layerAcTop       = cloudMinY + cloudSpan * 0.696;  // ~160m at default
    float layerCirrusBottom = layerAcTop;
    float layerCirrusTop    = cloudMaxY;

    float t_start = 0.0;
    float t_end = 0.0;

    if (abs(worldDir.y) > 0.001) {
        float t1 = (cloudMinY - cameraPosition.y) / worldDir.y;
        float t2 = (cloudMaxY - cameraPosition.y) / worldDir.y;
        t_start = min(t1, t2);
        t_end = max(t1, t2);
    } else {
        if (cameraPosition.y >= cloudMinY && cameraPosition.y <= cloudMaxY) {
            t_start = 0.0;
            t_end = cloudRenderDistance;
        } else {
            return vec4(0.0);
        }
    }

    t_start = max(0.0, t_start);
    t_end = min(cloudRenderDistance, t_end);
    if (t_start >= terrainDist) return vec4(0.0);
    t_end = min(t_end, terrainDist);
    if (t_start >= t_end) return vec4(0.0);

    float stepSize = (t_end - t_start) / 12.0;
    float transmission = 1.0;
    vec3 cloudLighting = vec3(0.0);

    // [FIX v0.2.5] Camera-stable sampling.
    // Screen-space jitter made clouds change/swim while rotating the camera.
    // We now sample fixed world-height slices when possible, falling back to midpoint
    // distance slices near the horizon. Same 12 samples, no extra noise/fbm calls.
    float yStart = ((worldDir.y) * (t_start) + (cameraPosition.y));
    float yEnd   = ((worldDir.y) * (t_end) + (cameraPosition.y));
    float heightSliceWeight = smoothstep(0.012, 0.055, abs(worldDir.y));
    float safeDirY = (worldDir.y >= 0.0 ? 1.0 : -1.0) * max(abs(worldDir.y), 0.055);

    // Cheap phase terms reused by all samples. No extra fbm/noise calls.
    float lightPhase = clamp(((dot(worldDir, lightDir)) * (0.5) + (0.5)), 0.0, 1.0);
    float silverLining = pow(lightPhase, 7.0) * (1.0 - rainStrength) * dayFactor;
    float horizonSoftness = smoothstep(0.01, 0.18, abs(worldDir.y));

    // Independent wind-shear per cloud layer. This breaks the old "locked together"
    // look while keeping the same number of noise/fbm calls.
    float cloudWind = getCloudWindSpeedMultiplier();
    vec2 windCirrus  = ((vec2(0.085, 0.034)) * (t * cloudWind) + (vec2(173.13, -421.70)));
    vec2 windAc      = ((vec2(0.116, 0.071)) * (t * cloudWind) + (vec2(-317.40, 118.82)));
    vec2 windAlto    = ((vec2(0.145, 0.052)) * (t * cloudWind) + (vec2(632.20, 274.40)));
    vec2 windCumulus = ((vec2(0.178, 0.083)) * (t * cloudWind) + (vec2(-127.70, -761.10)));

    for (int i = 0; i < 12; ++i) {
        float slice = (float(i) + 0.5) * 0.0833333333;
        float tDistance = t_start + (float(i) + 0.5) * stepSize;
        float sampleY = mix(yStart, yEnd, slice);
        float tHeight = (sampleY - cameraPosition.y) / safeDirY;
        float curr_t = mix(tDistance, tHeight, heightSliceWeight);
        vec3 p = ((worldDir) * (curr_t) + (cameraPosition));

        float stepDensity = 0.0;
        vec3 stepColor = vec3(0.0);

        if (p.y >= layerCirrusBottom && p.y <= layerCirrusTop) {
            vec2 uv = ((cloudCoordCirrus(p.xz)) * (0.0006) + (windCirrus));
            float d1 = noise(uv * 4.5);
            float d2 = noise(uv * 11.0);
            float cirrusDensity = d1 * d2;
            float layerFeather = smoothstep(layerCirrusBottom, layerCirrusBottom + cloudSpan * 0.035, p.y) *
                                 (1.0 - smoothstep(layerCirrusTop - cloudSpan * 0.045, layerCirrusTop, p.y));
            stepDensity = smoothstep(0.18, 0.48, cirrusDensity) * layerFeather * 0.12 * (1.0 - rainStrength);
            vec3 dayBase = mix(vec3(0.003, 0.005, 0.012) * 0.6, vec3(0.98), dayFactor);
            stepColor = mix(dayBase, vec3(1.0, 0.75, 0.55), sunsetFactor * 0.8);
            stepColor += vec3(1.0, 0.86, 0.66) * silverLining * stepDensity * 0.28;
        }
        else if (p.y >= layerAcBottom && p.y < layerCirrusBottom) {
            vec2 uv = ((cloudCoordAc(p.xz)) * (0.001) + (windAc));
            float d = noise(uv * 1.8);
            float threshold = mix(0.44, 0.28, rainStrength);
            float layerFeather = smoothstep(layerAcBottom, layerAcBottom + cloudSpan * 0.035, p.y) *
                                 (1.0 - smoothstep(layerCirrusBottom - cloudSpan * 0.035, layerCirrusBottom, p.y));
            stepDensity = smoothstep(threshold, threshold + 0.2, d) * layerFeather * 0.18 * (1.0 - rainStrength * 0.35);
            vec3 dayBase = mix(vec3(0.003, 0.005, 0.012) * 0.6, vec3(0.95), dayFactor);
            stepColor = mix(dayBase, vec3(1.0, 0.62, 0.38), sunsetFactor * 0.8);
            stepColor += vec3(1.0, 0.78, 0.56) * silverLining * stepDensity * 0.22;
        }
        else if (p.y >= layerAltoBottom && p.y < layerAcBottom) {
            vec2 uv = ((cloudCoordAlto(p.xz)) * (0.0014) + (windAlto));
            float d = noise(uv * 1.5);
            float threshold = mix(0.40, 0.22, rainStrength);
            float layerFeather = smoothstep(layerAltoBottom, layerAltoBottom + cloudSpan * 0.030, p.y) *
                                 (1.0 - smoothstep(layerAcBottom - cloudSpan * 0.035, layerAcBottom, p.y));
            stepDensity = smoothstep(threshold, threshold + 0.24, d) * layerFeather * 0.24;
            vec3 dayBase = mix(vec3(0.002, 0.004, 0.01) * 0.6, vec3(0.92), dayFactor);
            stepColor = mix(dayBase, vec3(1.0, 0.58, 0.3), sunsetFactor * 0.85);
            stepColor += vec3(1.0, 0.72, 0.48) * silverLining * stepDensity * 0.18;
        }
        else if (p.y >= cloudMinY && p.y < layerAltoBottom) {
            vec2 uv = ((cloudCoordCumulus(p.xz)) * (0.0018) + (windCumulus));
            float d = fbm(uv);
            float hFactor = clamp((p.y - cloudMinY) / (layerAltoBottom - cloudMinY), 0.0, 1.0);
            // Flatter bottoms + softer tops look more like cumulus and cost only ALU.
            float bottomLift = smoothstep(0.02, 0.18, hFactor);
            float topFade = 1.0 - smoothstep(0.68, 1.0, hFactor);
            float heightProfile = bottomLift * topFade;
            float cloudMin = mix(0.42, 0.16, rainStrength);
            float cloudMax = mix(0.68, 0.44, rainStrength);
            float edgeSoftness = mix(0.10, 0.18, rainStrength);
            stepDensity = smoothstep(cloudMin, cloudMax + edgeSoftness * (1.0 - hFactor), d) * heightProfile * 0.38;

            vec3 lightPos = ((lightDir) * (35.0) + (p));
            float dLight = noise(((cloudCoordCumulus(lightPos.xz)) * (0.0018) + (windCumulus)));
            float shadowDensity = smoothstep(cloudMin, cloudMax, dLight);
            // Softer self-shadowing: keeps volume depth but avoids crushed black cloud undersides.
            float shadow = exp(-shadowDensity * 2.35);

            vec3 cloudAmbient = mix(vec3(0.010, 0.013, 0.022), vec3(0.30, 0.34, 0.40), dayFactor);
            vec3 litCloud = ((lightColor) * (0.92) + (cloudAmbient * 0.28));
            vec3 dayCloudBase = mix(cloudAmbient, litCloud, shadow);
            vec3 stormyCloudLight = mix(vec3(0.27, 0.28, 0.30), vec3(0.12, 0.13, 0.15), thunderStrength);
            stepColor = mix(dayCloudBase, stormyCloudLight, rainStrength);

            // Better silver lining / forward scatter, reusing precomputed phase term.
            stepColor += vec3(1.0, 0.92, 0.82) * silverLining * stepDensity * 0.62;
        }

        if (stepDensity > 0.0) {
            cloudLighting += stepColor * stepDensity * transmission;
            transmission *= (1.0 - stepDensity);
            if (transmission < 0.02) {
                transmission = 0.0;
                break;
            }
        }
    }

    // Softer horizon fade reduces a hard cloud cut line. Reuses the precomputed value.
    return vec4(cloudLighting, (1.0 - transmission) * horizonSoftness);
}

// ============================================================================== 
// CAMERA INSIDE CLOUD VOLUME EFFECT
// Adds local white/grey cloud fog when the camera physically enters the procedural
// cloud layer. Early-outs outside the cloud slab, so normal gameplay cost is tiny.
// ============================================================================== 
float getCameraCloudDensity(float t) {
    float cloudBaseY = 160.0;
    #if CLOUD_HEIGHT == 1
    cloudBaseY = 110.0;
    #elif CLOUD_HEIGHT == 3
    cloudBaseY = 240.0;
    #endif

    float cloudSpan = 230.0;
    #if CLOUD_THICKNESS == 1
    cloudSpan = 140.0;
    #elif CLOUD_THICKNESS == 3
    cloudSpan = 310.0;
    #endif

    float cloudMinY = cloudBaseY;
    float cloudMaxY = cloudBaseY + cloudSpan;
    float y = cameraPosition.y;

    // Fast early-out: no noise/fbm unless the camera is actually in the cloud slab.
    if (y < cloudMinY || y > cloudMaxY) return 0.0;

    float cloudWind = getCloudWindSpeedMultiplier();
    vec2 windCirrus  = ((vec2(0.085, 0.034)) * (t * cloudWind) + (vec2(173.13, -421.70)));
    vec2 windAc      = ((vec2(0.116, 0.071)) * (t * cloudWind) + (vec2(-317.40, 118.82)));
    vec2 windAlto    = ((vec2(0.145, 0.052)) * (t * cloudWind) + (vec2(632.20, 274.40)));
    vec2 windCumulus = ((vec2(0.178, 0.083)) * (t * cloudWind) + (vec2(-127.70, -761.10)));

    float layerCumulusTop   = cloudMinY + cloudSpan * 0.217;
    float layerAltoTop      = cloudMinY + cloudSpan * 0.435;
    float layerAcTop        = cloudMinY + cloudSpan * 0.696;
    float layerCirrusTop    = cloudMaxY;

    vec3 p = cameraPosition;
    float density = 0.0;

    if (y >= layerAcTop && y <= layerCirrusTop) {
        vec2 uv = ((cloudCoordCirrus(p.xz)) * (0.0006) + (windCirrus));
        float d1 = noise(uv * 4.5);
        float d2 = noise(uv * 11.0);
        float layerFeather = smoothstep(layerAcTop, layerAcTop + cloudSpan * 0.035, y) *
                             (1.0 - smoothstep(layerCirrusTop - cloudSpan * 0.045, layerCirrusTop, y));
        density = smoothstep(0.18, 0.48, d1 * d2) * layerFeather * 0.70 * (1.0 - rainStrength);
    } else if (y >= layerAltoTop && y < layerAcTop) {
        vec2 uv = ((cloudCoordAc(p.xz)) * (0.001) + (windAc));
        float d = fbm(uv * 1.8);
        float threshold = mix(0.44, 0.28, rainStrength);
        float layerFeather = smoothstep(layerAltoTop, layerAltoTop + cloudSpan * 0.035, y) *
                             (1.0 - smoothstep(layerAcTop - cloudSpan * 0.035, layerAcTop, y));
        density = smoothstep(threshold, threshold + 0.2, d) * layerFeather * 0.86 * (1.0 - rainStrength * 0.35);
    } else if (y >= layerCumulusTop && y < layerAltoTop) {
        vec2 uv = ((cloudCoordAlto(p.xz)) * (0.0014) + (windAlto));
        float d = fbm(uv * 1.5);
        float threshold = mix(0.40, 0.22, rainStrength);
        float layerFeather = smoothstep(layerCumulusTop, layerCumulusTop + cloudSpan * 0.030, y) *
                             (1.0 - smoothstep(layerAltoTop - cloudSpan * 0.035, layerAltoTop, y));
        density = smoothstep(threshold, threshold + 0.24, d) * layerFeather * 0.96;
    } else {
        vec2 uv = ((cloudCoordCumulus(p.xz)) * (0.0018) + (windCumulus));
        float d = fbm(uv);
        float hFactor = clamp((y - cloudMinY) / max(layerCumulusTop - cloudMinY, 0.001), 0.0, 1.0);
        float bottomLift = smoothstep(0.02, 0.18, hFactor);
        float topFade = 1.0 - smoothstep(0.68, 1.0, hFactor);
        float heightProfile = bottomLift * topFade;
        float cloudMin = mix(0.42, 0.16, rainStrength);
        float cloudMax = mix(0.68, 0.44, rainStrength);
        float edgeSoftness = mix(0.10, 0.18, rainStrength);
        density = smoothstep(cloudMin, cloudMax + edgeSoftness * (1.0 - hFactor), d) * heightProfile;
    }

    // Active rain makes the deck feel more continuous and foggy.
    density = mix(density, max(density, 0.55), rainStrength * 0.45);
    return clamp(density, 0.0, 1.0);
}

vec3 applyInsideCloudVeil(vec3 color, float dist, vec3 worldDir, float dayFactor,
                          float sunsetFactor, vec3 baseFogColor, float t) {
    float camCloudDensity = getCameraCloudDensity(t);
    if (camCloudDensity <= 0.015) return color;

    float fogLevelMult = 1.0;
    #if FOG_DENSITY_LEVEL == 1
    fogLevelMult = 0.65;
    #elif FOG_DENSITY_LEVEL == 3
    fogLevelMult = 1.50;
    #endif

    float effectiveDensity = camCloudDensity * fogLevelMult;

    // Local cloud fog: preserve nearby blocks, strongly veil distance/horizon.
    float nearProtect = smoothstep(3.0, 18.0, dist);
    float distanceFog = 1.0 - exp(-dist * effectiveDensity * 0.0042);
    float horizonPath = pow(clamp(1.0 - abs(worldDir.y), 0.0, 1.0), 1.35);
    float upwardEscape = 1.0 - smoothstep(0.55, 0.95, worldDir.y);
    float pathBoost = mix(0.62, 1.25, horizonPath) * upwardEscape;

    float maxVeil = clamp(0.88 * effectiveDensity, 0.0, 0.94);
    float veil = clamp(distanceFog * nearProtect * pathBoost * effectiveDensity, 0.0, maxVeil);

    vec3 nightCloud = vec3(0.045, 0.055, 0.075);
    vec3 dayCloud   = vec3(0.74, 0.78, 0.80);
    vec3 cloudColor = mix(nightCloud, dayCloud, dayFactor);
    cloudColor = mix(cloudColor, vec3(1.0, 0.72, 0.48), sunsetFactor * dayFactor * 0.22);
    cloudColor = mix(cloudColor, vec3(0.34, 0.36, 0.39), rainStrength * mix(0.45, 0.78, thunderStrength));
    cloudColor = mix(cloudColor, baseFogColor, 0.18);

    // Slight contrast loss inside droplets, not just a flat color mix.
    vec3 veiled = mix(color, vec3(dot(color, vec3(0.2126, 0.7152, 0.0722))), veil * 0.18);
    return mix(veiled, cloudColor, veil);
}

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position) {
    vec4 homPos = projectionMatrix * vec4(position, 1.0);
    return homPos.xyz / homPos.w;
}

// ==============================================================================
// ENHANCED SHADOW SAMPLING - Premium 32-Sample Poisson Disk PCF with distance fade
// ==============================================================================
const vec2 poissonDisk[32] = vec2[32](
    vec2(-0.061483, 0.111534),
    vec2(-0.198945, 0.413725),
    vec2(-0.354224, -0.046532),
    vec2(-0.107021, -0.271096),
    vec2(0.201417, 0.221543),
    vec2(0.421003, -0.027070),
    vec2(-0.512210, 0.201417),
    vec2(-0.413725, -0.421003),
    vec2(0.118821, -0.457714),
    vec2(0.551784, 0.317402),
    vec2(0.127705, 0.632201),
    vec2(-0.218323, 0.811865),
    vec2(-0.645680, 0.493210),
    vec2(-0.817194, -0.271096),
    vec2(-0.717887, -0.613392),
    vec2(-0.317402, -0.811865),
    vec2(0.012770, -0.761102),
    vec2(0.317402, -0.717887),
    vec2(0.613392, -0.512210),
    vec2(0.811865, -0.218323),
    vec2(0.977050, -0.108615),
    vec2(0.717887, 0.201417),
    vec2(0.651784, 0.617481),
    vec2(0.413725, 0.817194),
    vec2(0.111534, 0.942016),
    vec2(-0.317402, 0.551784),
    vec2(-0.613392, -0.111534),
    vec2(-0.111534, -0.512210),
    vec2(0.354224, -0.317402),
    vec2(0.317402, 0.512210),
    vec2(-0.012770, 0.457714),
    vec2(-0.811865, 0.221543)
);

float sampleShadow(vec3 shadowScreenPos, float distToCamera, float bias) {
    if (shadowScreenPos.x < 0.0 || shadowScreenPos.x > 1.0 ||
        shadowScreenPos.y < 0.0 || shadowScreenPos.y > 1.0 ||
        shadowScreenPos.z < 0.0 || shadowScreenPos.z > 1.0) {
        return 1.0;
    }

    float fadeDist = 80.0;
    #if SHADOW_DISTANCE == 1
    fadeDist = 60.0;
    #elif SHADOW_DISTANCE == 3
    fadeDist = 120.0;
    #elif SHADOW_DISTANCE == 4
    fadeDist = 160.0;
    #endif
    float fadeWidth = fadeDist * 0.18;
    float distFade = 1.0 - smoothstep(fadeDist - fadeWidth, fadeDist, distToCamera);
    if (distFade < 0.01) return 1.0;

    float texelSize = 1.0 / float(SHADOW_RES);

    float spreadRadius = 1.2;
    #if SHADOW_SOFTNESS == 1
    spreadRadius = 0.6;
    #elif SHADOW_SOFTNESS == 3
    spreadRadius = 2.2;
    #endif

    // ==============================================================================
    // WEATHER-AWARE PHYSICAL PCSS (Percentage Closer Soft Shadows)
    // ==============================================================================
    float avgBlockerDepth = 0.0;
    float blockerCount = 0.0;
    float searchRadius = 16.0 * texelSize * spreadRadius;
    
    for (int i = 0; i < 16; ++i) {
        vec2 offset = poissonDisk[i * 2] * searchRadius;
        float sampleDepth = texture(shadowtex0, shadowScreenPos.xy + offset).r;
        if (sampleDepth < shadowScreenPos.z - bias) {
            avgBlockerDepth += sampleDepth;
            blockerCount += 1.0;
        }
    }

    float weatherLightSizeMult = ((rainStrength) * (2.0) + (((rainStrength * thunderStrength) * (2.0) + (1.0))));
    float minSpreadFactor = mix(0.15, 0.65, rainStrength * (0.6 + 0.4 * thunderStrength));

    float actualSpread = spreadRadius;
    if (blockerCount > 0.0) {
        avgBlockerDepth /= blockerCount;
        float penumbraSize = (shadowScreenPos.z - avgBlockerDepth) / max(1e-4, avgBlockerDepth);
        float lightSize = 140.0 * weatherLightSizeMult;
        float minSpread = minSpreadFactor * spreadRadius;
        float maxSpread = 24.0 * weatherLightSizeMult * spreadRadius;
        float pcssSpread = clamp(penumbraSize * lightSize * spreadRadius, minSpread, maxSpread);
        float blockerWeight = blockerCount / 16.0;
        actualSpread = mix(minSpread, pcssSpread, smoothstep(0.0, 1.0, blockerWeight));
    } else {
        actualSpread = minSpreadFactor * spreadRadius;
    }

    // Stable 32-sample Poisson Disk PCF with dynamic actualSpread for buttery smooth edges
    float shadow = 0.0;
    for (int i = 0; i < 32; ++i) {
        vec2 offset = poissonDisk[i] * texelSize * actualSpread;
        float depth = texture(shadowtex0, shadowScreenPos.xy + offset).r;
        shadow += step(shadowScreenPos.z - bias, depth);
    }
    shadow /= 32.0;

    return mix(1.0, shadow, distFade);
}


// ==============================================================================
// REALISTIC EXTRAS: TRANSPARENT CLOUD SHADOWS + GODRAYS
// ==============================================================================
#ifdef CLOUD_SHADOWS
float sampleCloudLayerDensityForShadow(vec2 xz, float y, float cloudMinY, float cloudSpan, float t) {
    float layerCumulusTop   = cloudMinY + cloudSpan * 0.217;
    float layerAltoTop      = cloudMinY + cloudSpan * 0.435;
    float layerAcTop        = cloudMinY + cloudSpan * 0.696;
    float layerCirrusTop    = cloudMinY + cloudSpan;

    float cloudWind = getCloudWindSpeedMultiplier();
    vec2 windCirrus  = ((vec2(0.085, 0.034)) * (t * cloudWind) + (vec2(173.13, -421.70)));
    vec2 windAc      = ((vec2(0.116, 0.071)) * (t * cloudWind) + (vec2(-317.40, 118.82)));
    vec2 windAlto    = ((vec2(0.145, 0.052)) * (t * cloudWind) + (vec2(632.20, 274.40)));
    vec2 windCumulus = ((vec2(0.178, 0.083)) * (t * cloudWind) + (vec2(-127.70, -761.10)));

    float density = 0.0;

    if (y >= layerAcTop && y <= layerCirrusTop) {
        // High cirrus shadows are deliberately very transparent.
        vec2 uv = cloudCoordCirrus(xz) * 0.0006 + windCirrus;
        float d = noise(uv * 4.5) * noise(uv * 11.0);
        density = smoothstep(0.18, 0.48, d) * 0.16 * (1.0 - rainStrength);
    } else if (y >= layerAltoTop && y < layerAcTop) {
        // Altocumulus / mid deck: soft semi-transparent patches.
        vec2 uv = cloudCoordAc(xz) * 0.001 + windAc;
        float threshold = mix(0.44, 0.28, rainStrength);
        density = smoothstep(threshold, threshold + 0.20, noise(uv * 1.8)) * 0.32 * (1.0 - rainStrength * 0.25);
    } else if (y >= layerCumulusTop && y < layerAltoTop) {
        // Altostratus: broad soft shading.
        vec2 uv = cloudCoordAlto(xz) * 0.0014 + windAlto;
        float threshold = mix(0.40, 0.22, rainStrength);
        density = smoothstep(threshold, threshold + 0.24, noise(uv * 1.5)) * 0.42;
    } else {
        // Low cumulus / storm deck: strongest and most varied shadows.
        vec2 uv = cloudCoordCumulus(xz) * 0.0018 + windCumulus;
        float d = noise(uv);
        float cloudMin = mix(0.42, 0.16, rainStrength);
        float cloudMax = mix(0.68, 0.44, rainStrength);
        density = smoothstep(cloudMin, cloudMax, d) * mix(0.52, 0.78, rainStrength * max(0.25, thunderStrength));
    }

    return clamp(density, 0.0, 1.0);
}

float computeCloudShadow(vec3 worldPos, vec3 lightDir, float dayFactor, float t) {
    if (dayFactor <= 0.02 || lightDir.y <= 0.025) return 1.0;

    float cloudBaseY = 160.0;
    #if CLOUD_HEIGHT == 1
    cloudBaseY = 110.0;
    #elif CLOUD_HEIGHT == 3
    cloudBaseY = 240.0;
    #endif

    float cloudSpan = 230.0;
    #if CLOUD_THICKNESS == 1
    cloudSpan = 140.0;
    #elif CLOUD_THICKNESS == 3
    cloudSpan = 310.0;
    #endif

    float cloudMinY = cloudBaseY;
    float cloudMaxY = cloudBaseY + cloudSpan;
    if (worldPos.y > cloudMaxY) return 1.0;

    // [FIX v1.0.7] Single midpoint tap through cloud slab for maximum performance
    float y1 = cloudMinY + cloudSpan * 0.46;
    float density = 0.0;

    if (y1 > worldPos.y) {
        float k = (y1 - worldPos.y) / max(lightDir.y, 0.025);
        density = sampleCloudLayerDensityForShadow((worldPos + lightDir * k).xz, y1, cloudMinY, cloudSpan, t);
    }
    density *= smoothstep(0.06, 0.35, lightDir.y); // softer near horizon
    density *= (1.0 - rainStrength * thunderStrength * 0.25); // storm already darkens global light

    float strength = 0.34;
    #if CLOUD_SHADOW_STRENGTH == 1
    strength = 0.22;
    #elif CLOUD_SHADOW_STRENGTH == 3
    strength = 0.48;
    #endif

    return clamp(1.0 - density * strength, 0.46, 1.0);
}
#endif

#ifdef GODRAYS
float sampleVolumetricSunVisibility(vec3 sampleViewPos) {
    #ifndef SHADOWS
    return 1.0;
    #else
    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(sampleViewPos, 1.0)).xyz;
    vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
    vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
    shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
    shadowClipPos.z -= 0.0012;
    vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
    vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;

    if (shadowScreenPos.x < 0.0 || shadowScreenPos.x > 1.0 ||
        shadowScreenPos.y < 0.0 || shadowScreenPos.y > 1.0 ||
        shadowScreenPos.z < 0.0 || shadowScreenPos.z > 1.0) {
        return 1.0;
    }

    // Single-tap visibility is intentional here: volumetric integration already
    // accumulates multiple samples along the ray, so PCF would be overly costly.
    float blockerDepth = texture(shadowtex0, shadowScreenPos.xy).r;
    return step(shadowScreenPos.z, blockerDepth);
    #endif
}

float henyeyGreenstein(float cosTheta, float g) {
    float g2 = g * g;
    float denom = max(0.045, pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
    return (1.0 - g2) / (12.5663706144 * denom);
}

// ==============================================================================
// [v1.1.0] TRUE VOLUMETRIC GODRAYS — full single-scattering raymarch
//
//   L(cam) = ∫ Tr(cam→x) · σs(h) · P_HG(θ) · V_shadow(x) · V_cloud(x) · E_light dx
//
// What makes this "true" volumetric compared to the previous approximation:
//   • The shadow map is tested at EVERY raymarch step, so shafts are carved by
//     real geometry occlusion (trees, buildings, caves), not implied by a
//     forward-looking boost.
//   • Interleaved Gradient Noise dithering (+ per-frame rotation when TAA is
//     active) makes 8–24 steps integrate like hundreds — no banding.
//   • Exact per-segment Beer–Lambert integration:
//     ∫ Tr·σs dx over a segment = Tr₀ · σs/σt · (1 − e^(−σt·Δx))  — energy
//     conserving, no over-brightening regardless of step size.
//   • No forwardBoost gate: the dual-lobe HG phase alone shapes directionality,
//     so shafts remain visible when looking ACROSS them (like real crepuscular
//     rays), not only when staring at the sun.
//   • Returns colored radiance: warm Kelvin-driven sun shafts by day, deep
//     orange at sunset, faint blue moonbeams at night (moon shadow map is
//     already bound to shadowtex0 after 13000 ticks).
//   • Early-out when transmittance is fully absorbed.
// ==============================================================================

// Interleaved Gradient Noise (Jimenez 2014) — ideal spatial dither for raymarch.
float godrayIGN(vec2 pixel) {
    #ifdef TAA
    // Rotate the dither pattern every frame — TAA resolves it into a clean gradient.
    pixel += 5.588238 * float(frameCounter & 63);
    #endif
    return fract(52.9829189 * fract(0.06711056 * pixel.x + 0.00583715 * pixel.y));
}

vec3 computeVolumetricGodrays(vec3 rayDirView, vec3 rayDirWorld, float maxRayDistance,
                              vec3 lightViewDir, vec3 lightWorldDir,
                              float dayFactor, float sunsetFactor) {
    // Light source below the horizon → nothing to in-scatter.
    if (lightWorldDir.y <= 0.01 || maxRayDistance <= 1.0) return vec3(0.0);

    int sampleCount = 8;
    float maxDistance = 96.0;
    #if GODRAYS_QUALITY == 2
    sampleCount = 16;
    maxDistance = 128.0;
    #elif GODRAYS_QUALITY == 3
    sampleCount = 24;
    maxDistance = 160.0;
    #endif

    float rayLength = min(maxRayDistance, maxDistance);
    if (rayLength <= 0.5) return vec3(0.0);

    // --- User-facing intensity ---
    // [TUNE HDR] Roughly halved vs the original LDR values: now that colortex0 is
    // RGBA16F the godray radiance is no longer clipped at 1.0 together with the
    // scene, so the additive shaft survives in full and reads far brighter. The
    // soft shoulder below now also does the heavy lifting on the bright core.
    float strengthMult = 1.2;
    #if GODRAYS_STRENGTH == 1
    strengthMult = 0.7;
    #elif GODRAYS_STRENGTH == 3
    strengthMult = 1.9;
    #endif

    // --- Phase function: dominant forward Mie lobe + weak backscatter lobe ---
    // [FIX v1.1.0] Do NOT reuse the shared henyeyGreenstein(): its max(0.045, ...)
    // denominator guard (tuned for clouds) caps the forward peak ~2.5-11x too low,
    // which made the shafts nearly invisible. Local HG with a tiny epsilon instead.
    float cosTheta = clamp(dot(normalize(rayDirView), normalize(lightViewDir)), -1.0, 1.0);
    float g = mix(0.74, 0.84, sunsetFactor); // hazier, more forward-peaked at sunset
    float g2 = g * g;
    float phaseFwd = (1.0 - g2) / (12.5663706144 * max(0.008, pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5)));
    float phaseBack = 0.0182 / max(0.008, pow(1.0334 + 0.36 * cosTheta, 1.5)); // g = -0.18 lobe
    float phase = mix(phaseFwd, phaseBack, 0.20);
    // Isotropic floor: real haze is polydisperse, so crepuscular rays stay clearly
    // visible even when looking ACROSS them, not only toward the sun.
    phase = phase * 0.92 + 0.055;

    // --- Light energy (colored!) ---
    vec3 sunE = kelvinToRGB(getSolarKelvin(max(0.001, lightWorldDir.y)));
    sunE = mix(sunE, vec3(1.0, 0.52, 0.24), sunsetFactor * 0.6);
    vec3 moonE = vec3(0.38, 0.50, 0.78) * getMoonPhaseBrightness(moonPhase);
    float sunAmount = clamp(dayFactor + sunsetFactor * 0.5, 0.0, 1.0);
    vec3 lightEnergy = mix(moonE * 0.16, sunE, sunAmount);

    // Storm clouds block the direct beam; wet air scatters more after rain.
    float weatherVisibility = 1.0 - rainStrength * mix(0.60, 0.88, thunderStrength);
    if (weatherVisibility <= 0.02) return vec3(0.0);

    // --- Medium density: user fog level + sunset haze + post-rain moisture ---
    float densityMult = 1.0 + sunsetFactor * 0.85 + wetness * 0.45;
    #if FOG_DENSITY_LEVEL == 1
    densityMult *= 0.78;
    #elif FOG_DENSITY_LEVEL == 3
    densityMult *= 1.30;
    #endif

    // --- Dithered uniform raymarch with exact segment integration ---
    float dither = godrayIGN(gl_FragCoord.xy);
    float stepLen = rayLength / float(sampleCount);

    float transmittance = 1.0;
    vec3 scattered = vec3(0.0);
    float cloudShadow = 1.0;

    for (int i = 0; i < 24; ++i) {
        if (i >= sampleCount) break;

        float sampleDist = (float(i) + dither) * stepLen;
        vec3 sampleViewPos = rayDirView * sampleDist;
        vec3 sampleWorldPos = cameraPosition + rayDirWorld * sampleDist;

        // Exponential aerosol falloff above sea level (Y≈64), denser in valleys.
        float heightDensity = exp(-max(sampleWorldPos.y - 64.0, 0.0) * 0.010);
        heightDensity = clamp(heightDensity * densityMult, 0.06, 1.75);

        // [FIX v1.1.0] Denser medium + higher single-scatter albedo (0.85):
        // the previous 0.0050/0.0072 pair integrated to a nearly invisible shaft.
        float sigmaS = 0.0085 * heightDensity; // scattering
        float sigmaT = 0.0100 * heightDensity; // extinction (scatter + absorb)

        // Per-step geometric occlusion from the shadow map — the heart of the effect.
        float vis = sampleVolumetricSunVisibility(sampleViewPos);

        // Cloud shadow is low-frequency: refresh every 4th step (spatially varying,
        // still ~6x cheaper than per-step evaluation).
        #ifdef CLOUD_SHADOWS
        if ((i & 3) == 0) {
            cloudShadow = computeCloudShadow(sampleWorldPos, lightWorldDir, dayFactor, frameTimeCounter * 0.05);
        }
        #endif
        vis *= cloudShadow;

        // Exact analytic integral of Tr·σs over this segment (energy conserving).
        float segTr = exp(-sigmaT * stepLen);
        if (vis > 0.001) {
            scattered += lightEnergy * (transmittance * vis * phase * (sigmaS / sigmaT) * (1.0 - segTr));
        }
        transmittance *= segTr;
        if (transmittance < 0.02) break; // fully absorbed — early out
    }

    scattered *= weatherVisibility * strengthMult;

    // Soft shoulder keeps the sun-facing core from blowing out the HDR pipeline
    // while preserving the linear response of faint side-lit shafts.
    // [FIX v1.1.0] Relaxed 0.55 -> 0.30 — the old shoulder crushed the bright core.
    // [TUNE HDR] Raised 0.30 -> 0.50: under RGBA16F the additive godray no longer
    // clips against an already-saturated scene, so the bright core became too hot.
    // A stronger shoulder compresses that core back down while leaving faint side
    // shafts (which sit well below 1.0) essentially untouched.
    scattered = scattered / (1.0 + scattered * 0.50);
    return scattered;
}
#endif

// ==============================================================================
// EXTREME PROFILE: stable 8-sample SSAO / SAO-style contact occlusion
// ==============================================================================
#ifdef SSAO
float computeSSAO(vec2 uv, vec3 centerViewPos, vec3 centerNormal) {
    vec2 pixelSize = 1.0 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));

    float radiusPixels = 5.5;
    float radiusView = 1.65;
    float strength = 0.62;
    #if SSAO_STRENGTH == 1
    radiusPixels = 4.0;
    radiusView = 1.15;
    strength = 0.42;
    #elif SSAO_STRENGTH == 3
    radiusPixels = 7.5;
    radiusView = 2.25;
    strength = 0.86;
    #endif

    // Scale slightly with distance so contact shadows remain visible without huge kernels.
    float distScale = clamp(length(centerViewPos) * 0.018, 0.75, 2.15);
    radiusPixels *= distScale;
    radiusView *= distScale;

    float occlusion = 0.0;
    float validSamples = 0.0;

    for (int i = 0; i < 8; ++i) {
        vec2 sampleUV = uv + poissonDisk[i] * pixelSize * radiusPixels;
        if (sampleUV.x <= 0.001 || sampleUV.x >= 0.999 || sampleUV.y <= 0.001 || sampleUV.y >= 0.999) continue;

        float sampleDepth = texture(depthtex0, sampleUV).r;
        if (sampleDepth >= 1.0) continue;

        vec3 sampleViewPos = projectAndDivide(gbufferProjectionInverse, vec3(sampleUV, sampleDepth) * 2.0 - 1.0);
        vec3 delta = sampleViewPos - centerViewPos;
        float dist = length(delta);

        // Occluders are samples that are closer to the camera than the current surface.
        float closer = step(0.035, sampleViewPos.z - centerViewPos.z);
        float range = 1.0 - smoothstep(radiusView * 0.18, radiusView, dist);
        float facing = max(dot(normalize(delta + centerNormal * 0.08), centerNormal), 0.0);

        occlusion += closer * range * (0.35 + 0.65 * facing);
        validSamples += 1.0;
    }

    occlusion /= max(validSamples, 1.0);
    return clamp(1.0 - occlusion * strength, 0.42, 1.0);
}
#endif

// SSR is now performed in final.fsh where colortex0 contains the fully lit scene.
// The traceSSR function has been moved there. composite.fsh writes normals +
// reflectivity into colortex6 for final.fsh to consume.

// Realistic low-valley / waterline mist density.
// Softer vertical profile than the original: dense around water level, feathered upward.
float getGroundMistDensity(float y) {
    // Layer covers rivers/plains and softly fades upward into the air.
    float lowerFade = smoothstep(60.2, 62.0, y);
    float upperFade = 1.0 - smoothstep(66.2, 70.2, y);

    // Highest density is close to cold wet ground/water; it thins with height.
    float nearGroundCore = 1.0 - smoothstep(63.2, 68.6, y);
    float body = mix(0.34, 1.0, nearGroundCore);

    return clamp(lowerFade * upperFade * body, 0.0, 1.0);
}

// Dawn/evening radiation fog timing.
// Broader than sunsetFactor so the mist does not pop in/out in a few seconds.
float getGroundMistTimeFactor(float t) {
    // Morning fog forms before sunrise and lingers after sunrise.
    float morningPre  = smoothstep(21800.0, 23600.0, t);
    float morningPost = 1.0 - smoothstep(1800.0, 5200.0, t);
    float morning = max(morningPre, morningPost);

    // Evening fog slowly forms around sunset and survives into early night.
    float eveningRise = smoothstep(10400.0, 12600.0, t);
    float eveningFall = 1.0 - smoothstep(15000.0, 19000.0, t);
    float evening = eveningRise * eveningFall;

    // A small night reservoir prevents the layer from disappearing instantly.
    float nightHold = smoothstep(13200.0, 16000.0, t) * (1.0 - smoothstep(20500.0, 23000.0, t)) * 0.32;

    return clamp(max(max(morning, evening), nightHold), 0.0, 1.0);
}


// Morning-only multiplier mask for low mist intensity.
// Keeps evening/night unchanged, but strengthens dawn and post-sunrise fog.
float getGroundMistMorningBoost(float t) {
    float morningPre  = smoothstep(21800.0, 23600.0, t);
    float morningPost = 1.0 - smoothstep(1800.0, 5200.0, t);
    float morning = clamp(max(morningPre, morningPost), 0.0, 1.0);
    return mix(1.0, 1.5, morning);
}


// Camera-inside-ground-mist veil. This simulates being physically inside the
// low radiation fog layer: nearby contrast is preserved, but distant objects
// and the horizon lose contrast through forward scattering.
float getInsideGroundMistVeil(float dist, vec3 worldDir, float camMistDensity, float mistTimeFactor) {
    float horizonPath = pow(clamp(1.0 - abs(worldDir.y), 0.0, 1.0), 1.55);
    float upwardEscape = 1.0 - smoothstep(0.18, 0.72, worldDir.y); // looking up exits the shallow layer
    float pathMult = mix(0.42, 1.0, horizonPath) * upwardEscape;

    float fogLevelMult = 1.0;
    #if FOG_DENSITY_LEVEL == 1
    fogLevelMult = 0.55;
    #elif FOG_DENSITY_LEVEL == 3
    fogLevelMult = 1.65;
    #endif

    float localDensity = camMistDensity * mistTimeFactor * pathMult * fogLevelMult;
    float veil = 1.0 - exp(-dist * localDensity * 0.0018);
    float maxVeil = clamp(0.72 * localDensity, 0.0, 0.88);
    return clamp(veil, 0.0, maxVeil);
}


// ==============================================================================
// REALISTIC ATMOSPHERIC FOG REFINEMENT
// Keeps the original v0.2.3 Beer-Lambert distance fog behaviour:
// fog starts at the camera and accumulates continuously with distance.
// This only refines density using height, horizon angle and outdoor exposure.
// ==============================================================================
float computeRealisticFogFactor(float dist, float density, vec3 worldDir, float worldY,
                                float skyLight, bool isOverworld, bool isNether) {
    float effectiveDensity = density;

    if (isOverworld) {
        // Aerosols are denser close to sea level / ground and thinner at altitude.
        // Approximate the average density along the camera -> fragment ray.
        float camY = cameraPosition.y;
        float camAerosol = exp(clamp((70.0 - camY) / 170.0, -0.65, 0.55));
        float endAerosol = exp(clamp((70.0 - worldY) / 170.0, -0.65, 0.55));
        float avgAerosol = clamp(sqrt(camAerosol * endAerosol), 0.58, 1.38);

        // Looking along the horizon crosses more low atmosphere than looking up/down.
        // This is subtle; it does not create a delayed fog wall.
        float horizonPath = pow(clamp(1.0 - abs(worldDir.y), 0.0, 1.0), 1.35);
        float horizonMult = mix(0.92, 1.14, horizonPath);

        // Fog is primarily outdoor atmospheric scattering. Keep some cave fog for
        // continuity, but reduce it indoors/under roofs via skylight.
        float outdoorMult = mix(0.62, 1.0, clamp(skyLight, 0.0, 1.0));

        effectiveDensity *= avgAerosol * horizonMult * outdoorMult;
    } else if (isNether) {
        // Nether fog should remain heavy and dimensional, close to original v0.2.3.
        effectiveDensity *= 1.05;
    }

    float fogFactor = 1.0 - exp(-dist * effectiveDensity);
    return clamp(fogFactor, 0.0, 0.985);
}

void main() {
    float depth = texture(depthtex0, texcoord).r;
    vec4 albedoData = texture(colortex0, texcoord);

    // Bulletproof Dimension Detection using Minecraft's native 'dimension' uniform (-1: Nether, 0: Overworld, 1: End)
    // with reliable biome/color fallbacks if needed.
    bool isNether = (dimension == -1) || (isNetherBiome > 0.5) || (fogColor.r > 0.18 && fogColor.g < 0.12 && fogColor.b < 0.05);
    bool isEnd = (dimension == 1) || (isEndBiome > 0.5) || (fogColor.r > 0.01 && fogColor.r < 0.08 && fogColor.g < 0.02 && fogColor.b > 0.04 && fogColor.b < 0.15);
    bool isOverworld = (dimension == 0) || (!isNether && !isEnd);

    // Dynamic Day/Night & Sunset transition based on precise worldTime
    float time = mod(float(worldTime), 24000.0);

    float dayFactor = 0.0;
    if (time >= 0.0 && time < 12000.0) {
        dayFactor = 1.0;
    } else if (time >= 12000.0 && time < 13000.0) {
        dayFactor = 1.0 - (time - 12000.0) / 1000.0;
    } else if (time >= 13000.0 && time < 23000.0) {
        dayFactor = 0.0;
    } else {
        dayFactor = (time - 23000.0) / 1000.0;
    }

    // Red twilight window: 11000–13000. Vanilla /time set 12800 is still sunset visually,
    // so the sun must remain warm/red instead of snapping to neutral/night lighting.
    float sunsetFactor = 0.0;
    if (time >= 11000.0 && time < 13000.0) {
        float sunsetT = clamp((time - 11000.0) / 2000.0, 0.0, 1.0);
        sunsetFactor = sin(sunsetT * 3.14159265);
    } else if (time >= 22500.0 || time < 1500.0) {
        float sunriseTime = time >= 22500.0 ? time - 24000.0 : time;
        float sunriseT = clamp((sunriseTime + 1500.0) / 3000.0, 0.0, 1.0);
        sunsetFactor = sin(sunriseT * 3.14159265);
    }
    float twilightFactor = sunsetFactor;

    vec3 L = normalize(shadowLightPosition);

    // [FIX v0.2.5] Compute view-space position ONCE instead of twice (was redundant)
    vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
    vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
    float terrainDist = length(viewPos);
    vec3 viewDir = normalize(viewPos);

    // Calculate world space directions
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * viewDir);
    vec3 worldL = normalize(mat3(gbufferModelViewInverse) * L);

    // Setup basic variables for lighting
    vec3 currentLightColor = vec3(0.0);
    vec3 ambientColor = vec3(0.05);
    vec3 currentFogColor = vec3(0.5);
    float fogDensity = 0.0013;
    vec3 directLighting = vec3(0.0);
    float shadowFactor = 1.0;

    // Read G-buffer: normals + emissive flag from colortex2
    vec4 normalData = texture(colortex2, texcoord);
    vec3 encodedNormal = normalData.xyz * 2.0 - 1.0;
    // Sky/unused G-buffer pixels can contain zero or stale normal data; avoid
    // normalize(vec3(0)) producing undefined values before the sky branch returns.
    vec3 normal = length(encodedNormal) > 1e-4 ? normalize(encodedNormal) : vec3(0.0, 1.0, 0.0);
    float isEmissive = 1.0 - step(0.5, normalData.a); // [FIX v0.2.5] alpha < 0.5 = emissive (portals)
    bool isFoliage = abs(normalData.a - 0.62) < 0.01;

    vec4 lmData = texture(colortex1, texcoord);
    float blockLight = lmData.r;
    float skyLight = lmData.g;

    // 1. Dynamic Hand/Held Light
    float heldLightVal = float(max(heldBlockLightValue, heldBlockLightValue2));
    if (heldLightVal > 0.1) {
        float handGlow = max(0.0, (heldLightVal / 15.0) - terrainDist * 0.08);
        blockLight = max(blockLight, handGlow);
    }

    // ==============================================================================
    // EMISSIVE FAST PATH — Portals and other self-lit surfaces skip scene lighting
    // [FIX v0.2.5] Prevents composite from re-lighting emissive surfaces
    // ==============================================================================
    // Sky pixels do not write colortex2, so alpha may contain stale data there.
    // Only treat a pixel as emissive if it is real geometry (depth < 1.0).
    if (depth < 1.0 && isEmissive > 0.5) {
        vec3 finalColor = albedoData.rgb;

        // Apply fog to emissive surfaces too (they exist in the world)
        if (isOverworld) {
            float baseDensity = 0.0013;
            #if FOG_DENSITY_LEVEL == 1
            baseDensity = 0.0008;
            #elif FOG_DENSITY_LEVEL == 3
            baseDensity = 0.0025;
            #endif
            float emFogDensity = mix(baseDensity, baseDensity * 5.0, rainStrength);

            vec3 dayFog = vec3(0.55, 0.68, 0.82);
            vec3 nightFog = vec3(0.004, 0.006, 0.012);
            vec3 emFogColor = mix(nightFog, dayFog, dayFactor);
            vec3 sunsetFogColor = vec3(0.8, 0.38, 0.12);
            emFogColor = mix(emFogColor, sunsetFogColor, twilightFactor);
            vec3 rainFogColor = vec3(0.2, 0.22, 0.25);
            emFogColor = mix(emFogColor, rainFogColor, rainStrength);

            float fogWorldY = cameraPosition.y + worldDir.y * terrainDist;
            float fogFactor = computeRealisticFogFactor(terrainDist, emFogDensity, worldDir, fogWorldY,
                                                        0.5, isOverworld, false);
            finalColor = mix(finalColor, emFogColor, fogFactor);
        } else if (isNether) {
            float fogFactor = 1.0 - exp(-terrainDist * 0.0038);
            vec3 netherFogColor = clamp(fogColor * 1.5, vec3(0.01), vec3(1.0));
            finalColor = mix(finalColor, netherFogColor, clamp(fogFactor, 0.0, 0.985));
        } else if (isEnd) {
            float fogFactor = 0.0; // [FIX v0.2.8] No fog in the End
            finalColor = mix(finalColor, vec3(0.02, 0.01, 0.05), clamp(fogFactor, 0.0, 0.985));
        }

        // Blend volumetric clouds in front of emissive surfaces
        #ifdef PROCEDURAL_CLOUDS
        if (isOverworld) {
            float cloudTime = frameTimeCounter * 0.05;
            vec4 volClouds = renderVolumetricClouds(worldDir, worldL, currentLightColor, terrainDist, dayFactor, sunsetFactor, cloudTime);
            finalColor = mix(finalColor, volClouds.rgb, volClouds.a);
            finalColor = applyInsideCloudVeil(finalColor, terrainDist, worldDir, dayFactor, sunsetFactor, fogColor, cloudTime);
        }
        #endif

        #ifdef GODRAYS
        if (isOverworld) {
            // [v1.1.0] True volumetric raymarched godrays (colored radiance)
            finalColor += computeVolumetricGodrays(viewDir, worldDir, terrainDist, L, worldL, dayFactor, sunsetFactor);
        }
        #endif

        colortex0Out = vec4(finalColor, albedoData.a);
        // [v1.0.3] colortex6 write removed
        return;
    }

    // ==============================================================================
    // DIMENSION-SPECIFIC LIGHTING
    // ==============================================================================
    if (isOverworld) {
        // --- OVERWORLD ---

        // ======================================================================
        // PHYSICALLY-BASED SOLAR IRRADIANCE MODEL
        // ======================================================================
        float sunIntMult = 1.0;
        #if SUN_INTENSITY == 1
        sunIntMult = 0.70;
        #elif SUN_INTENSITY == 3
        sunIntMult = 1.35;
        #elif SUN_INTENSITY == 4
        sunIntMult = 1.85;
        #endif

        float moonIntMult = 1.0;
        #if MOON_INTENSITY == 1
        moonIntMult = 0.45;
        #elif MOON_INTENSITY == 3
        moonIntMult = 2.2;
        #elif MOON_INTENSITY == 4
        moonIntMult = 4.5;
        #endif

        // --- Sun contribution ---
        vec3 extinction = vec3(1.0);
        vec3 sunContrib = vec3(0.0);
        {
            float sinAlpha = max(0.001, worldL.y);
            float currentK = getSolarKelvin(sinAlpha);
            // Force deep warm Kelvin during sunset/sunrise twilight. This keeps /time set 12800 red.
            currentK = mix(currentK, 1850.0, sunsetFactor * 0.88);
            float airMass = getAirmass(sinAlpha);
            vec3 RayleighExtinction = vec3(0.075, 0.155, 0.375);
            extinction = exp(-airMass * RayleighExtinction);
            extinction = mix(extinction, max(extinction, vec3(0.36)), sunsetFactor * 0.65);
            float sunPresenceDay = smoothstep(-0.06, 0.08, worldL.y) * dayFactor;
            float sunPresenceTwilight = smoothstep(-0.28, 0.06, worldL.y) * sunsetFactor * 0.55;
            float sunPresence = max(sunPresenceDay, sunPresenceTwilight);
            sunContrib = kelvinToRGB(currentK) * extinction * 2.6 * sunPresence * sunIntMult;
        }

        // --- Moon contribution ---
        vec3 moonContrib = vec3(0.0);
        {
            float moonElev = -worldL.y;
            float moonTimeMask = smoothstep(13000.0, 14500.0, time) * (1.0 - smoothstep(22000.0, 23200.0, time));
            float moonPresence = smoothstep(-0.06, 0.08, moonElev) * moonTimeMask;
            float moonBrightness = getMoonPhaseBrightness(moonPhase);
            float moonK = 4100.0;
            #if MOON_TEMPERATURE == 1
            moonK = 6500.0;
            #elif MOON_TEMPERATURE == 3
            moonK = 3200.0;
            #endif
            vec3 moonBaseColor = kelvinToRGB(moonK);
            moonContrib = moonBaseColor * 0.028 * moonBrightness * moonPresence * moonIntMult;
        }

        currentLightColor = sunContrib + moonContrib;

        // Weather dimming
        float weatherDimFactor = mix(1.0, 0.55, rainStrength);
        weatherDimFactor = mix(weatherDimFactor, 0.15, rainStrength * thunderStrength);
        currentLightColor *= weatherDimFactor;

        float rawNdotL = dot(normal, L);
        #if LIGHT_WRAP == 1
        float NdotL = max(0.0, rawNdotL);
        #elif LIGHT_WRAP == 2
        float NdotL = pow(max(0.0, rawNdotL * 0.5 + 0.5), 1.6);
        #else
        float NdotL = pow(max(0.0, rawNdotL * 0.5 + 0.5), 1.2);
        #endif
        float shadow = 1.0;
        #ifdef SHADOWS
        vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
        vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
        vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
        shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
        float baseBias = 0.0008;
        // [FIX v0.2.5] Use rawNdotL for slope bias — wrapped NdotL caused shadow acne with LIGHT_WRAP 2/3
        float slopeBias = 0.0018 * (1.0 - clamp(rawNdotL, 0.0, 1.0));
        float bias = baseBias + slopeBias;
        
        vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
        vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;
        shadow = sampleShadow(shadowScreenPos, terrainDist, bias);
        #endif

        // Shadow lift
        float shadowFloor = 0.25;
        #if AMBIENT_BRIGHTNESS == 1
        shadowFloor = 0.10;
        #elif AMBIENT_BRIGHTNESS == 3
        shadowFloor = 0.45;
        #endif
        shadowFactor = mix(mix(shadowFloor, 1.0, shadow), shadow, dayFactor);
        directLighting = currentLightColor * NdotL * skyLight * shadowFactor;

        // Shadow tinting
        #if SHADOW_TINT != 1
        float shadowDarkness = 1.0 - shadow;
        vec3 shadowTintColor = vec3(0.04, 0.06, 0.12);
        #if SHADOW_TINT == 3
        shadowTintColor = vec3(0.10, 0.06, 0.03);
        #endif
        directLighting += shadowTintColor * shadowDarkness * skyLight * dayFactor * 0.25;
        #endif

        // Sunset / Sunrise back-scatter
        #ifdef SUNRISE_GLOW
        if (sunsetFactor > 0.01) {
            float backDot = max(0.0, dot(normal, -L));
            float wrap = pow(max(0.0, dot(normal, -L) * 0.5 + 0.5), 2.0);
            float scatter = mix(backDot, wrap, 0.5) * twilightFactor * skyLight * shadowFactor;
            vec3 scatterColor = kelvinToRGB(2400.0) * extinction * 1.5 * scatter;
            directLighting += scatterColor;
        }
        #endif

        // Subsurface Scattering (SSS) for foliage
        #ifdef FOLIAGE_SSS
        if (isFoliage) {
            // Smoothed shadow factor for SSS to reduce Poisson disk noise
            float sssShadow = smoothstep(0.0, 0.45, shadow); 
            
            // SSS term: light bleeding through when looking at the light source
            float vDotL = max(0.0, dot(viewDir, L));
            float sssBleed = pow(vDotL, 4.0) * 1.2;
            
            // Wrap term: light softening the unlit side of foliage
            float wrap = pow(max(0.0, dot(normal, -L) * 0.5 + 0.5), 2.0) * 0.35;
            
            vec3 sssColor = currentLightColor * (sssBleed + wrap) * skyLight * sssShadow;
            directLighting += sssColor;
        }
        #endif

        // Sun Halo
        #ifdef SUN_HALO
        if (dayFactor > 0.01) {
            vec3 viewDirWorld = normalize(mat3(gbufferModelViewInverse) * normalize(viewPos));
            float forwardDot = max(0.0, dot(viewDirWorld, worldL));
            float mie = pow(forwardDot, 8.0);
            float haloIntensity = mie * skyLight * shadowFactor * dayFactor * (1.0 - rainStrength) * 0.45;
            vec3 sunBaseColor = kelvinToRGB(getSolarKelvin(max(0.001, worldL.y)));
            vec3 haloColor = sunBaseColor * extinction * haloIntensity * 1.8;
            directLighting += haloColor;
        }
        #endif

        // Procedural transparent cloud shadows. Only direct sunlight is dimmed;
        // ambient/torch light remains readable, so the result stays realistic and playable.
        #ifdef CLOUD_SHADOWS
        if (depth < 1.0 && skyLight > 0.03 && dayFactor > 0.02) {
            vec3 worldPosForCloudShadow = cameraPosition + worldDir * terrainDist;
            float cloudShadow = computeCloudShadow(worldPosForCloudShadow, worldL, dayFactor, frameTimeCounter * 0.05);
            directLighting *= mix(1.0, cloudShadow, skyLight);
        }
        #endif

        // Hemisphere ambient
        float normalUp = normal.y * 0.5 + 0.5;

        vec3 nightSkyAmbient = vec3(0.006, 0.008, 0.018);
        vec3 nightGroundAmbient = vec3(0.003, 0.003, 0.005);
        vec3 nightAmbient = mix(nightGroundAmbient, nightSkyAmbient, normalUp) * (0.4 + skyLight * 0.6);

        vec3 daySkyAmbient = vec3(0.32, 0.42, 0.58);
        vec3 dayGroundAmbient = vec3(0.18, 0.14, 0.08);
        vec3 dayAmbient = mix(dayGroundAmbient, daySkyAmbient, normalUp) * skyLight * 0.75;

        ambientColor = mix(nightAmbient, dayAmbient, dayFactor);

        vec3 sunsetAmbient = vec3(0.22, 0.12, 0.06) * skyLight * 0.6;
        ambientColor = mix(ambientColor, sunsetAmbient, twilightFactor * 0.5);

        float ambientDimFactor = mix(1.0, 0.65, rainStrength);
        ambientDimFactor = mix(ambientDimFactor, 0.15, rainStrength * thunderStrength);
        ambientColor *= ambientDimFactor;

        // Fog colour transitions
        vec3 dayFog = vec3(0.55, 0.68, 0.82);
        vec3 nightFog = vec3(0.004, 0.006, 0.012);
        vec3 sunsetFog = vec3(0.8, 0.38, 0.12);
        currentFogColor = mix(nightFog, dayFog, dayFactor);
        currentFogColor = mix(currentFogColor, sunsetFog, twilightFactor);

        vec3 rainFogColor = vec3(0.2, 0.22, 0.25);
        vec3 thunderFogColor = vec3(0.07, 0.08, 0.09);
        vec3 stormFogColor = mix(rainFogColor, thunderFogColor, thunderStrength);
        currentFogColor = mix(currentFogColor, stormFogColor, rainStrength);

        // Conservative biome fog blend: keeps the original AuraLite palette,
        // but makes fog respond more naturally to Minecraft biome/vanilla atmosphere.
        float biomeFogMix = mix(0.28, 0.10, rainStrength);
        currentFogColor = mix(currentFogColor, fogColor, biomeFogMix);

        float baseDensity = 0.0013;
        #if FOG_DENSITY_LEVEL == 1
        baseDensity = 0.0008;
        #elif FOG_DENSITY_LEVEL == 3
        baseDensity = 0.0025;
        #endif
        fogDensity = mix(baseDensity, baseDensity * 5.0, rainStrength);

    } else if (isNether) {
        // --- THE NETHER ---
        directLighting = vec3(0.0);
        float pulse = sin(frameTimeCounter * 0.5) * 0.12 + 0.88;
        // [FIX v0.2.8] Nether biomes colored fog and ambient lighting:
        // Reads and scales the native biome fogColor from Minecraft (Soul Sand Valley, Warped/Crimson forest, etc.)
        // to dynamically shift atmosphere, rather than hardcoding warm red everywhere.
        currentFogColor = clamp(fogColor * 1.5, vec3(0.01), vec3(1.0));
        ambientColor = clamp((fogColor * 1.45 + vec3(0.04)) * pulse * 1.22, vec3(0.01), vec3(0.8));
        fogDensity = 0.0038;

    } else if (isEnd) {
        // --- THE END ---
        directLighting = vec3(0.0);
        ambientColor = vec3(0.14, 0.1, 0.22);
        currentFogColor = vec3(0.02, 0.01, 0.05);
        fogDensity = 0.0000; // [FIX v0.2.8] Completely remove End fog for clear obsidian towers & sky visibility.
    }

    // ==============================================================================
    // SKY PASS
    // ==============================================================================
    if (depth >= 1.0) {
        vec3 finalColor = albedoData.rgb;
        #ifdef PROCEDURAL_CLOUDS
        if (isOverworld) {
            float cloudTime = frameTimeCounter * 0.05;
            vec4 volClouds = renderVolumetricClouds(worldDir, worldL, currentLightColor, getCloudRenderDistance(), dayFactor, sunsetFactor, cloudTime);
            finalColor = mix(finalColor, volClouds.rgb, volClouds.a);
        }
        #endif

        // If the camera is inside the low morning/evening mist layer, veil the horizon sky too.
        #ifdef GROUND_MIST
        if (isOverworld) {
            float camMistDensity = getGroundMistDensity(cameraPosition.y);
            float camMistTime = getGroundMistTimeFactor(time) * getGroundMistMorningBoost(time);
            float humidityFactor = clamp(0.62 + wetness * 0.32 + rainStrength * 0.10, 0.50, 1.12);
            camMistTime *= humidityFactor;
            float skyMistVeil = getInsideGroundMistVeil(420.0, worldDir, camMistDensity, camMistTime);
            vec3 skyMistColor = mix(vec3(0.50, 0.55, 0.62), vec3(0.75, 0.78, 0.80), dayFactor);
            skyMistColor = mix(skyMistColor, fogColor, 0.24);
            finalColor = mix(finalColor, skyMistColor, skyMistVeil);
        }
        #endif

        #ifdef PROCEDURAL_CLOUDS
        if (isOverworld) {
            float cloudTime = frameTimeCounter * 0.05;
            finalColor = applyInsideCloudVeil(finalColor, 900.0, worldDir, dayFactor, sunsetFactor, fogColor, cloudTime);
        }
        #endif

        #ifdef GODRAYS
        if (isOverworld) {
            // [v1.1.0] True volumetric raymarched godrays — sky pixels integrate
            // the full budget distance so shafts extend naturally into the sky.
            finalColor += computeVolumetricGodrays(viewDir, worldDir, 180.0, L, worldL, dayFactor, sunsetFactor);
        }
        #endif

        colortex0Out = vec4(finalColor, albedoData.a);
        // [v1.0.3] colortex6 write removed
        return;
    }

    // ==============================================================================
    // TERRAIN LIGHTING
    // ==============================================================================

    // Torch lighting with Kelvin-based colour temperature
    float blockIntensity = pow(blockLight, 3.2);

    // Cozy torch flickering
    float torchFlicker = 1.0;
    #ifdef COZY_LIGHTS
    torchFlicker = sin(frameTimeCounter * 4.0 + blockLight * 12.0) * 0.04 + 0.96;
    #endif

    float torchKelvin = 1900.0;
    #if LIGHTMAP_WARMTH == 1
    torchKelvin = 1600.0;
    #elif LIGHTMAP_WARMTH == 3
    torchKelvin = 2600.0;
    #endif
    vec3 torchColor = kelvinToRGB(torchKelvin) * 2.3;
    vec3 torchLighting = torchColor * blockIntensity * torchFlicker;

    // Lighting execution
    vec3 albedo = pow(albedoData.rgb, vec3(2.2));
    vec3 finalLight = directLighting + torchLighting + ambientColor;
    vec3 shadedTerrain = albedo * finalLight;

    // PBR Microfacet Specular shading (LabPBR support)
    // Distance fade: skip expensive Cook-Torrance on distant pixels where specular
    // is sub-pixel and invisible. Saves significant GPU time on large render distances.
#ifdef PBR_LIGHTING
    // Fade distances computed at compile time via ternary — no nested #if needed.
    // PBR_DISTANCE: 1=16m, 2=48m, 3=128m, 4=unlimited
    float pbrFadeEnd = (PBR_DISTANCE == 1) ? 16.0 :
                        (PBR_DISTANCE == 3) ? 128.0 :
                        (PBR_DISTANCE == 4) ? 9999.0 : 48.0;
    float pbrFadeStart = pbrFadeEnd * 0.5;
    float pbrDistFade = 1.0 - smoothstep(pbrFadeStart, pbrFadeEnd, terrainDist);
    float roughness = lmData.z;
    float metalness = lmData.w;

    // Early-out: pixel is beyond PBR fade range — skip ALL PBR calculations
    if (pbrDistFade < 0.001) {
        // jump to #endif
    } else {

    // Wetness effect
    #ifdef WET_REFLECTIONS
    if (rainStrength > 0.01 && isOverworld) {
        float wetnessFactor = rainStrength * skyLight * clamp(normal.y, 0.0, 1.0);
        roughness = mix(roughness, 0.08, wetnessFactor * 0.8);
        shadedTerrain *= (1.0 - wetnessFactor * 0.18);
    }
    #endif

    if ((roughness > 0.001 || metalness > 0.001) && pbrDistFade > 0.001) {
        vec3 V = normalize(-viewPos);
        // [FIX v0.2.8] In the Nether/End there is no direct sun/moon light vector,
        // so we must use a physical upward light vector (ceiling/ambient) instead of
        // uninitialized Overworld shadowLightPosition to prevent specular glitches.
        vec3 L_pbr = isOverworld ? L : vec3(0.0, 1.0, 0.0);
        vec3 H = normalize(L_pbr + V);

        float alpha = roughness * roughness;
        float alpha2 = alpha * alpha;
        float NdotH = max(0.001, dot(normal, H));
        float NdotL_pbr = max(0.001, dot(normal, L_pbr));
        float NdotV = max(0.001, dot(normal, V));

        // GGX Distribution
        float denom = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
        float D_GGX = alpha2 / (3.1415926535 * denom * denom);

        // Smith Geometry
        float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
        float G_V = NdotV / (NdotV * (1.0 - k) + k);
        float G_L = NdotL_pbr / (NdotL_pbr * (1.0 - k) + k);
        float G_Smith = G_V * G_L;

        // Fresnel-Schlick
        vec3 F0 = mix(vec3(0.04), albedo, metalness);
        float VdotH = max(0.001, dot(V, H));
        vec3 F_Schlick = F0 + (1.0 - F0) * pow(clamp(1.0 - VdotH, 0.0, 1.0), 5.0);

        // Cook-Torrance BRDF
        vec3 specColor = (D_GGX * G_Smith * F_Schlick) / max(1e-5, 4.0 * NdotV * NdotL_pbr);

        float pbrStrengthMult = 1.0;
        #if PBR_STRENGTH == 1
        pbrStrengthMult = 0.45;
        #elif PBR_STRENGTH == 3
        pbrStrengthMult = 2.05;
        #endif

        vec3 specLightColor = currentLightColor;
        if (!isOverworld) {
            specLightColor = ambientColor * 4.0;
        } else if (dayFactor <= 0.01) {
            float moonBr = getMoonPhaseBrightness(moonPhase);
            float moonKspec = 4100.0;
            #if MOON_TEMPERATURE == 1
            moonKspec = 6500.0;
            #elif MOON_TEMPERATURE == 3
            moonKspec = 3200.0;
            #endif
            float moonSpecIntMult = 1.0;
            #if MOON_INTENSITY == 1
            moonSpecIntMult = 0.5;
            #elif MOON_INTENSITY == 3
            moonSpecIntMult = 2.0;
            #elif MOON_INTENSITY == 4
            moonSpecIntMult = 3.5;
            #endif
            specLightColor = kelvinToRGB(moonKspec) * 0.45 * moonBr * pbrStrengthMult * moonSpecIntMult;
        }

        // [FIX v0.2.5] Added missing NdotL_pbr cosine factor for correct Cook-Torrance BRDF.
        // The BRDF fr = DFG/(4·NoV·NoL) must be multiplied by Lo = fr·Li·cos(θi) = fr·Li·NoL.
        // Without this factor, specular was too dim at high sun angles and too bright at grazing.
        shadedTerrain += specColor * specLightColor * NdotL_pbr * skyLight * shadowFactor * pbrStrengthMult * pbrDistFade;
    }
    } // end pbrDistFade > 0.001 else block
    #endif

    #ifdef SSAO
    // EXTREME profile contact AO. Applied after direct/PBR lighting and before fog.
    float ssaoFactor = computeSSAO(texcoord, viewPos, normal);
    float outdoorAO = mix(0.70, 1.0, skyLight);
    shadedTerrain *= mix(1.0, ssaoFactor, outdoorAO);
    #endif

    // Apply realistic atmospheric fog refinement (still starts at the camera)
    float fogWorldY = cameraPosition.y + worldDir.y * terrainDist;
    float fogFactor = computeRealisticFogFactor(terrainDist, fogDensity, worldDir, fogWorldY,
                                                skyLight, isOverworld, isNether);
    vec3 finalColor = mix(shadedTerrain, currentFogColor, fogFactor);

    // ==============================================================================
    // ENHANCED UNDERWATER WORLD — v0.2.9
    // Physical volumetric underwater rendering with god-rays, caustics, depth fog,
    // Beer-Lambert absorption, view distortion and atmospheric scattering.
    // ==============================================================================
    if (isEyeInWater == 1) {
        vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

        // --- 1. UNDERWATER CAUSTICS (enhanced dual-layer) ---
        // Two overlapping caustic layers at different scales/speeds create a natural
        // dancing light pattern on submerged surfaces.
        vec2 causticUV1 = feetPlayerPos.xz * 0.30 + vec2(frameTimeCounter * 0.42, frameTimeCounter * 0.22);
        vec2 causticUV2 = feetPlayerPos.xz * 0.18 - vec2(frameTimeCounter * 0.28, -frameTimeCounter * 0.35);
        float caustic1 = pow(smoothstep(0.38, 0.72, fbm(causticUV1)), 2.2);
        float caustic2 = pow(smoothstep(0.42, 0.68, fbm(causticUV2)), 2.0);
        float causticMerged = caustic1 * 0.65 + caustic2 * 0.35;
        // Caustics are strongest on surfaces facing upward (receiving surface light)
        float causticFacing = clamp(normal.y * 0.6 + 0.4, 0.0, 1.0);
        // Caustics fade with distance — very close surfaces show strong dancing light
        float causticDistFade = exp(-terrainDist * 0.06);
        vec3 causticColor = vec3(0.10, 0.45, 0.82) * causticMerged * causticFacing * causticDistFade * skyLight * 1.8 * dayFactor;
        finalColor += causticColor;

        // --- 2. UNDERWATER GODRAYS (volumetric light shafts) ---
        // Vertical beams of light penetrating from the surface. Uses a simple
        // 6-sample vertical ray march accumulating scattered light.
        if (dayFactor > 0.05 && skyLight > 0.1) {
            float uwRayAccum = 0.0;
            float uwRaySteps = 6.0;
            float uwMaxDist = min(terrainDist, 32.0);
            float uwStepSize = uwMaxDist / uwRaySteps;
            for (int i = 0; i < 6; ++i) {
                float uwDist = (float(i) + 0.5) * uwStepSize;
                vec3 uwSampleWorld = cameraPosition + worldDir * uwDist;
                // Light penetration pattern — caustic-like noise at the sample world position
                vec2 uwRayUV = uwSampleWorld.xz * 0.22 + vec2(frameTimeCounter * 0.15, frameTimeCounter * 0.08);
                float uwNoise = noise(uwRayUV) * 0.6 + noise(uwRayUV * 2.8) * 0.4;
                // Depth attenuation — light decays with water depth below surface (~Y=62)
                float uwDepthFade = exp(clamp((uwSampleWorld.y - 62.0) / 18.0, -2.5, 0.0));
                // Transmittance along path
                float uwTransmit = exp(-uwDist * 0.035);
                uwRayAccum += uwNoise * uwDepthFade * uwTransmit * uwStepSize;
            }
            // Phase function: forward-scattered light is brighter when looking toward the sky
            float uwUpPhase = clamp(worldDir.y * 0.5 + 0.5, 0.15, 1.0);
            vec3 uwRayColor = vec3(0.06, 0.28, 0.52) * uwRayAccum * uwUpPhase * dayFactor * skyLight * 0.18;
            finalColor += uwRayColor;
        }

        // --- 3. PHYSICAL BEER-LAMBERT ABSORPTION ---
        // Red light is absorbed fastest, then green, then blue — mimicking real ocean water.
        vec3 absorptionCoeffs = vec3(0.18, 0.045, 0.015);
        vec3 waterAbsorption = exp(-terrainDist * absorptionCoeffs);
        finalColor = finalColor * waterAbsorption;

        // --- 4. VOLUMETRIC SCATTERING FOG ---
        // In-scattered ambient light replaces absorbed wavelengths, tinting distant
        // objects toward deep blue/teal. Stronger deeper and farther.
        float depthBelowSurface = max(62.0 - cameraPosition.y, 0.0);
        float depthFogDensity = 0.032 + depthBelowSurface * 0.0025;
        float uwFogFactor = 1.0 - exp(-terrainDist * depthFogDensity);
        vec3 deepWaterColor = mix(vec3(0.02, 0.12, 0.32), vec3(0.008, 0.04, 0.12), smoothstep(0.0, 30.0, depthBelowSurface));
        // [v0.2.9] True night darkness underwater.
        // UNDERWATER_NIGHT_DARKNESS controls how dark night actually gets:
        //   1: Moonlit pool — bright like original 0.2.8 behaviour
        //   2: Dim          — clearly nighttime, but still visible
        //   3: True night   — real darkness, only faint moonlight blue
        //   4: Pitch dark   — almost zero visibility (extreme survival realism)
        float nightFloor = 0.06;
        float nightMult  = 1.0;
        #if UNDERWATER_NIGHT_DARKNESS == 1
        nightFloor = 0.25; nightMult = 0.55;
        #elif UNDERWATER_NIGHT_DARKNESS == 2
        nightFloor = 0.12; nightMult = 0.85;
        #elif UNDERWATER_NIGHT_DARKNESS == 4
        nightFloor = 0.005; nightMult = 1.0;
        #endif
        float nightDarken = mix(nightFloor, 1.0, dayFactor) * nightMult;
        vec3 uwFogColor = deepWaterColor * (skyLight * 0.85 + 0.15) * nightDarken;
        finalColor = mix(finalColor, uwFogColor, clamp(uwFogFactor, 0.0, 0.92));

        // --- 5. AMBIENT LIGHT SCATTERING ---
        // Broad ambient contribution from surface light diffusing into the water column.
        // Scatter is light coming FROM ABOVE, so it follows the same night curve.
        vec3 waterScatterColor = vec3(0.04, 0.18, 0.42) * (1.0 - waterAbsorption) * skyLight * nightDarken;
        finalColor += waterScatterColor;

    } else if (isEyeInWater == 2) {
        // --- LAVA IMMERSION ---
        // Deep orange overlay with pulsating intensity
        float lavaPulse = ((sin(frameTimeCounter * 1.8)) * (0.08) + (0.92));
        finalColor = mix(finalColor, vec3(0.92, 0.18, 0.01) * lavaPulse, 0.96);
        // Lava fog — very dense, close distance
        float lavaFog = 1.0 - exp(-terrainDist * 0.28);
        finalColor = mix(finalColor, vec3(0.65, 0.08, 0.0), lavaFog);
    }

    // Low-lying ground mist: realistic dawn/evening radiation fog
    // [FIX v0.2.3] Now guarded by #ifdef GROUND_MIST so the toggle works
    #ifdef GROUND_MIST
    if (isOverworld) {
        float mistTimeFactor = getGroundMistTimeFactor(time);

        // Morning fog is naturally stronger around dawn due to overnight cooling.
        // Evening and night remain unchanged.
        mistTimeFactor *= getGroundMistMorningBoost(time);

        // Wet ground/water keeps fog alive longer after rain; active rain blends it into haze.
        float humidityFactor = clamp(0.62 + wetness * 0.32 + rainStrength * 0.10, 0.50, 1.12);
        mistTimeFactor *= humidityFactor;

        float worldY = cameraPosition.y + worldDir.y * terrainDist;
        // [FIX v1.0.7] Fade out distant 2D sheets when standing inside the mist layer
        float camMistHere = getGroundMistDensity(cameraPosition.y);
        float mistDensityFactor = getGroundMistDensity(worldY) * (1.0 - camMistHere * 0.95);

        if (mistTimeFactor > 0.01 && mistDensityFactor > 0.01) {
            vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

            // Large slow sheets + small breakup. Much slower motion than clouds/waves,
            // because real valley/radiation fog creeps rather than visibly flows.
            vec2 drift = vec2(frameTimeCounter * 0.010, frameTimeCounter * 0.0035);
            vec2 largeUV = feetPlayerPos.xz * 0.026 + drift;
            vec2 smallUV = feetPlayerPos.xz * 0.074 - drift * 1.7;
            float largeSheet = fbm(largeUV);
            float smallBreakup = noise(smallUV);
            float sheetMask = smoothstep(0.18, 0.82, largeSheet * 0.78 + smallBreakup * 0.22);
            float mistNoise = mix(0.48, 0.92, sheetMask);

            float fogLevelMult = 1.0;
            #if FOG_DENSITY_LEVEL == 1
            fogLevelMult = 0.55;
            #elif FOG_DENSITY_LEVEL == 3
            fogLevelMult = 1.65;
            #endif

            // Optical accumulation through the layer. No hard 120m cutoff anymore:
            // the mist accumulates with distance, then fades very gently to avoid a flat wall.
            float distanceAccum = 1.0 - exp(-terrainDist * 0.0035 * fogLevelMult);
            float farBlend = 1.0 - smoothstep(260.0, 520.0, terrainDist);
            float outdoorFactor = mix(0.36, 0.82, skyLight);

            float rawOpacity = mistDensityFactor * mistNoise * mistTimeFactor * distanceAccum * farBlend * outdoorFactor * fogLevelMult;
            float maxOpacity = clamp(0.48 * mistDensityFactor * mistTimeFactor * fogLevelMult, 0.0, 0.75);
            float mistOpacity = clamp(rawOpacity * 0.45, 0.0, maxOpacity);

            // Physically calmer colour: mostly cool grey/white water droplets,
            // with only a modest warm tint when the low sun is actually present.
            vec3 coolMist = mix(vec3(0.48, 0.52, 0.58), vec3(0.70, 0.74, 0.76), dayFactor);
            vec3 warmMist = vec3(1.0, 0.70, 0.42);
            float lowSunWarmth = twilightFactor * (1.0 - rainStrength) * 0.24;
            vec3 mistColor = mix(coolMist, warmMist, lowSunWarmth);
            mistColor = mix(mistColor, fogColor, 0.22);

            finalColor = mix(finalColor, mistColor, mistOpacity);
        }
    }
    #endif

    // Camera-inside low mist: when the player stands inside the morning/evening layer,
    // apply a subtle local veil to the whole view instead of fake per-block sheets.
    #ifdef GROUND_MIST
    if (isOverworld) {
        float camMistDensity = getGroundMistDensity(cameraPosition.y);
        float camMistTime = getGroundMistTimeFactor(time) * getGroundMistMorningBoost(time);
        float humidityFactor = clamp(0.62 + wetness * 0.32 + rainStrength * 0.10, 0.50, 1.12);
        camMistTime *= humidityFactor;

        if (camMistDensity > 0.01 && camMistTime > 0.01) {
            float insideVeil = getInsideGroundMistVeil(terrainDist, worldDir, camMistDensity, camMistTime);
            float nearProtection = smoothstep(3.0, 18.0, terrainDist); // keep nearby blocks readable
            insideVeil *= nearProtection;

            vec3 insideMistColor = mix(vec3(0.50, 0.55, 0.62), vec3(0.74, 0.77, 0.78), dayFactor);
            vec3 warmMist = vec3(0.92, 0.70, 0.48);
            float lowSunWarmth = twilightFactor * (1.0 - rainStrength) * 0.18;
            insideMistColor = mix(insideMistColor, warmMist, lowSunWarmth);
            insideMistColor = mix(insideMistColor, fogColor, 0.24);

            finalColor = mix(finalColor, insideMistColor, insideVeil);
        }
    }
    #endif

    // Volumetric clouds blending
    #ifdef PROCEDURAL_CLOUDS
    if (isOverworld) {
        float cloudTime = frameTimeCounter * 0.05;
        vec4 volClouds = renderVolumetricClouds(worldDir, worldL, currentLightColor, terrainDist, dayFactor, sunsetFactor, cloudTime);
        finalColor = mix(finalColor, volClouds.rgb, volClouds.a);
        finalColor = applyInsideCloudVeil(finalColor, terrainDist, worldDir, dayFactor, sunsetFactor, currentFogColor, cloudTime);
    }
    #endif

    #ifdef GODRAYS
    if (isOverworld) {
        // [v1.1.0] True volumetric raymarched godrays — occluded per-step by the
        // shadow map, so terrain/trees carve real crepuscular light shafts.
        finalColor += computeVolumetricGodrays(viewDir, worldDir, terrainDist, L, worldL, dayFactor, sunsetFactor);
    }
    #endif

    colortex0Out = vec4(finalColor, albedoData.a);

    // [v1.0.3] SSR data export removed. final.fsh now reads normals from
    // colortex2 and roughness from colortex1 directly — same buffers the PBR
    // specular pass already uses (and which are confirmed working).
}

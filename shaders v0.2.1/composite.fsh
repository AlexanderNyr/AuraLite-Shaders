#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Fullscreen Composite Pass (GLSL 460 - Enhanced Lighting)
// ==============================================================================

#define SHADOWS             // [true false]
#define SHADOW_RES 2048     // [1024 2048 4096]
#define SHADOW_SOFTNESS 2   // [1 2 3] - 1: Sharp, 2: Soft, 3: Ultra Soft
#define LIGHTMAP_WARMTH 2   // [1 2 3]
#define FOG_DENSITY_LEVEL 2 // [1 2 3]
#define PBR_LIGHTING        // [true false]
#define PBR_STRENGTH 2      // [1 2 3]
#define PROCEDURAL_CLOUDS   // [true false]
#define CLOUD_HEIGHT 2      // [1 2 3]
#define CLOUD_THICKNESS 2   // [1 2 3]

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

/* DRAWBUFFERS:0 */

uniform sampler2D colortex0; // Albedo / baked color from gbuffers
uniform sampler2D colortex1; // Lightmap coordinates, PBR Roughness (z), Metalness (w)
uniform sampler2D colortex2; // Normals (Packed in view space)
uniform sampler2D depthtex0; // World depth buffer
uniform sampler2D shadowtex0; // Shadow depth buffer

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 shadowLightPosition; // Active light source direction (Sun/Moon)
uniform vec3 cameraPosition;      // Player's actual world coordinates
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength; // Blends thunderstorm vs standard rain
uniform float wetness; // Moisture decay after rain (used for persistent rainbows!)
uniform int worldTime;
uniform int moonPhase; // Moon phase 0-7 for moonlight brightness scaling
uniform vec3 fogColor; // Standard uniform containing Minecraft's dimension-specific fog color!

// Dynamic Light Uniforms (sends the light level of the held items!)
uniform int heldBlockLightValue;  // Light level of item held in main hand
uniform int heldBlockLightValue2; // Light level of item held in off hand

// Environment uniform to detect if player's eyes are in water/lava
uniform int isEyeInWater; // 0: Air, 1: Water, 2: Lava

in vec2 texcoord; // Match vertex output EXACTLY (no layout location to prevent driver linker errors!)

// Declare explicit output for modern GLSL 460 compatibility
layout(location = 0) out vec4 colortex0Out;

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
// Real sun photosphere ≈ 5778 K, but atmospheric Rayleigh scattering shifts
// the *apparent* colour temperature seen by the observer:
//   Zenith  → ~5700 K  (nearly white-yellow)
//   30°     → ~4500 K  (warm gold)
//   10°     → ~3200 K  (deep orange)
//   Horizon → ~2200 K  (fiery red-orange, heavy extinction)
// We model this with a smooth power curve keyed to sin(elevation).
// ==============================================================================
float getSolarKelvin(float sinElevation) {
    // sinElevation: 0 at horizon, 1 at zenith
    float t = clamp(sinElevation, 0.0, 1.0);
    // Attempt to match real-world CCT curve:
    //   t=0.0 → 2200 K (horizon)
    //   t=0.17 → ~3200 K (10°)
    //   t=0.5 → ~4500 K (30°)
    //   t=1.0 → 5700 K (zenith)
    return 2200.0 + 3500.0 * pow(t, 0.62);
}

// Physically-based atmospheric airmass using Kasten & Young (1989) formula
// Returns the relative optical path through the atmosphere.
float getAirmass(float sinElevation) {
    float elevDeg = degrees(asin(clamp(sinElevation, 0.001, 1.0)));
    return 1.0 / (sinElevation + 0.50572 * pow(elevDeg + 6.07995, -1.6364));
}

// ==============================================================================
// MOON PHASE BRIGHTNESS MULTIPLIER
// Full moon (phase 0) → 1.0, New moon (phase 4) → 0.05
// Based on real lunar albedo geometry: illumination ∝ cos(phase_angle/2)^2
// ==============================================================================
float getMoonPhaseBrightness(int phase) {
    // phase 0 = full, 4 = new
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

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (int i = 0; i < 4; ++i) {
        v += a * noise(p);
        p = rot * p * 2.1 + shift;
        a *= 0.5;
    }
    return v;
}

// ==============================================================================
// METEOROLOGICAL MULTI-HEIGHT 3D VOLUMETRIC CLOUD ENGINE (4 LAYERS)
// ==============================================================================
vec4 renderVolumetricClouds(vec3 worldDir, vec3 lightDir, vec3 lightColor, float terrainDist, float dayFactor, float sunsetFactor, float t) {
    float cloudMinY = 240.0;
    float cloudMaxY = 470.0;

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
            t_end = 2500.0;
        } else {
            return vec4(0.0);
        }
    }

    t_start = max(0.0, t_start);
    t_end = min(2500.0, t_end);
    if (t_start >= terrainDist) return vec4(0.0);
    t_end = min(t_end, terrainDist);
    if (t_start >= t_end) return vec4(0.0);

    float stepSize = (t_end - t_start) / 12.0;
    float transmission = 1.0;
    vec3 cloudLighting = vec3(0.0);

    for (int i = 0; i < 12; ++i) {
        float curr_t = t_start + (float(i) * stepSize);
        vec3 p = cameraPosition + worldDir * curr_t;

        float stepDensity = 0.0;
        vec3 stepColor = vec3(0.0);

        if (p.y >= 400.0 && p.y <= 470.0) {
            vec2 uv = p.xz * 0.0006 + vec2(t * 0.08, t * 0.03);
            float d1 = noise(uv * 4.5);
            float d2 = noise(uv * 11.0);
            float cirrusDensity = d1 * d2;
            stepDensity = smoothstep(0.18, 0.48, cirrusDensity) * 0.12 * (1.0 - rainStrength);
            vec3 dayBase = mix(vec3(0.003, 0.005, 0.012) * 0.6, vec3(0.98), dayFactor);
            stepColor = mix(dayBase, vec3(1.0, 0.75, 0.55), sunsetFactor * 0.8);
        }
        else if (p.y >= 340.0 && p.y < 400.0) {
            vec2 uv = p.xz * 0.001 + vec2(t * 0.13, t * 0.05);
            float d = fbm(uv * 1.8);
            float threshold = mix(0.44, 0.28, rainStrength);
            stepDensity = smoothstep(threshold, threshold + 0.2, d) * 0.18 * (1.0 - rainStrength * 0.35);
            vec3 dayBase = mix(vec3(0.003, 0.005, 0.012) * 0.6, vec3(0.95), dayFactor);
            stepColor = mix(dayBase, vec3(1.0, 0.62, 0.38), sunsetFactor * 0.8);
        }
        else if (p.y >= 290.0 && p.y < 340.0) {
            vec2 uv = p.xz * 0.0014 + vec2(t * 0.15, t * 0.07);
            float d = fbm(uv * 1.5);
            float threshold = mix(0.40, 0.22, rainStrength);
            stepDensity = smoothstep(threshold, threshold + 0.24, d) * 0.24;
            vec3 dayBase = mix(vec3(0.002, 0.004, 0.01) * 0.6, vec3(0.92), dayFactor);
            stepColor = mix(dayBase, vec3(1.0, 0.58, 0.3), sunsetFactor * 0.85);
        }
        else if (p.y >= 240.0 && p.y < 290.0) {
            vec2 uv = p.xz * 0.0018 + vec2(t * 0.18, t * 0.08);
            float d = fbm(uv);
            float hFactor = clamp((p.y - 240.0) / 50.0, 0.0, 1.0);
            float heightProfile = hFactor * (1.0 - hFactor) * 4.0;
            float cloudMin = mix(0.42, 0.16, rainStrength);
            float cloudMax = mix(0.68, 0.44, rainStrength);
            stepDensity = smoothstep(cloudMin, cloudMax, d) * heightProfile * 0.35;

            vec3 lightPos = p + lightDir * 35.0;
            float dLight = fbm(lightPos.xz * 0.0018 + vec2(t * 0.18, t * 0.08));
            float shadowDensity = smoothstep(cloudMin, cloudMax, dLight);
            float shadow = exp(-shadowDensity * 3.5);

            vec3 dayCloudBase = mix(vec3(0.001, 0.002, 0.005) * 0.6, lightColor * 0.9, shadow);
            vec3 stormyCloudLight = mix(vec3(0.2, 0.21, 0.23), vec3(0.06, 0.07, 0.08), thunderStrength);
            stepColor = mix(dayCloudBase, stormyCloudLight, rainStrength);

            float sunGlint = pow(max(0.0, dot(worldDir, lightDir) * 0.5 + 0.5), 4.0);
            stepColor += vec3(1.0, 0.92, 0.82) * sunGlint * stepDensity * 0.5 * (1.0 - rainStrength) * dayFactor;
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

    float horizonFade = smoothstep(0.0, 0.12, abs(worldDir.y));
    return vec4(cloudLighting, (1.0 - transmission) * horizonFade);
}

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position) {
    vec4 homPos = projectionMatrix * vec4(position, 1.0);
    return homPos.xyz / homPos.w;
}

// ==============================================================================
// ENHANCED SHADOW SAMPLING - Rotated Poisson Disk PCF with distance fade
// ==============================================================================
const vec2 poissonDisk[8] = vec2[8](
    vec2(-0.613392,  0.617481),
    vec2( 0.170019, -0.040254),
    vec2(-0.299417,  0.791925),
    vec2( 0.645680,  0.493210),
    vec2(-0.651784,  0.717887),
    vec2( 0.421003,  0.027070),
    vec2(-0.817194, -0.271096),
    vec2( 0.977050, -0.108615)
);

float sampleShadow(vec3 shadowScreenPos, float distToCamera, float NdotL) {
    if (shadowScreenPos.x < 0.0 || shadowScreenPos.x > 1.0 ||
        shadowScreenPos.y < 0.0 || shadowScreenPos.y > 1.0 ||
        shadowScreenPos.z < 0.0 || shadowScreenPos.z > 1.0) {
        return 1.0;
    }

    float fadeDist = 80.0;
    float fadeWidth = 16.0;
    float distFade = 1.0 - smoothstep(fadeDist - fadeWidth, fadeDist, distToCamera);
    if (distFade < 0.01) return 1.0;

    float texelSize = 1.0 / float(SHADOW_RES);

    float spreadRadius = 1.2;
    #if SHADOW_SOFTNESS == 1
    spreadRadius = 0.6;
    #elif SHADOW_SOFTNESS == 3
    spreadRadius = 2.2;
    #endif

    float rotAngle = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
    float cosA = cos(rotAngle);
    float sinA = sin(rotAngle);
    mat2 rotation = mat2(cosA, sinA, -sinA, cosA);

    float shadow = 0.0;
    for (int i = 0; i < 8; ++i) {
        vec2 offset = rotation * poissonDisk[i] * texelSize * spreadRadius;
        float depth = texture2D(shadowtex0, shadowScreenPos.xy + offset).r;
        shadow += step(shadowScreenPos.z, depth);
    }
    shadow /= 8.0;

    return mix(1.0, shadow, distFade);
}

// Graded ground mist density calculations (62m - 66.5m)
float getGroundMistDensity(float y) {
    if (y < 61.5 || y > 66.5) return 0.0;

    float density = 0.0;
    if (y >= 65.5) {
        density = mix(0.0, 0.2, clamp((66.5 - y) / 1.0, 0.0, 1.0));
    } else if (y >= 64.5) {
        density = mix(0.2, 0.55, clamp((65.5 - y) / 1.0, 0.0, 1.0));
    } else if (y >= 63.5) {
        density = mix(0.55, 0.85, clamp((64.5 - y) / 1.0, 0.0, 1.0));
    } else {
        density = mix(0.85, 1.0, clamp((63.5 - y) / 2.0, 0.0, 1.0));
    }
    return density;
}

void main() {
    float depth = texture2D(depthtex0, texcoord).r;
    vec4 albedoData = texture2D(colortex0, texcoord);

    // Organic Dimension Detection based on vanilla fog colors
    bool isNether = (fogColor.r > 0.18 && fogColor.g < 0.12 && fogColor.b < 0.05);
    bool isEnd = (fogColor.r > 0.01 && fogColor.r < 0.08 && fogColor.g < 0.02 && fogColor.b > 0.04 && fogColor.b < 0.15);
    bool isOverworld = !isNether && !isEnd;

    // Dynamic Day/Night & Sunset transition based on precise worldTime
    float time = float(worldTime);

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

    float sunsetFactor = 0.0;
    if (time >= 11500.0 && time < 12500.0) {
        sunsetFactor = 1.0 - abs(time - 12000.0) / 500.0;
    } else if (time >= 23500.0 || time < 500.0) {
        float t = time >= 23500.0 ? time - 24000.0 : time;
        sunsetFactor = 1.0 - abs(t) / 500.0;
    }

    vec3 L = normalize(shadowLightPosition);

    // Calculate world space directions
    vec3 viewDir = normalize(projectAndDivide(gbufferProjectionInverse, vec3(texcoord.xy, depth) * 2.0 - 1.0));
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * viewDir);
    vec3 worldL = normalize(mat3(gbufferModelViewInverse) * L);

    // Rebuild view space distance
    vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
    vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
    float terrainDist = length(viewPos);

    // Setup basic variables for lighting
    vec3 currentLightColor = vec3(0.0);
    vec3 ambientColor = vec3(0.05);
    vec3 currentFogColor = vec3(0.5);
    float fogDensity = 0.0013;
    vec3 directLighting = vec3(0.0);
    float shadowFactor = 1.0;

    vec3 normal = normalize(texture2D(colortex2, texcoord).xyz * 2.0 - 1.0);
    vec4 lmData = texture2D(colortex1, texcoord);
    float blockLight = lmData.r;
    float skyLight = lmData.g;

    // 1. Dynamic Hand/Held Light
    float heldLightVal = float(max(heldBlockLightValue, heldBlockLightValue2));
    if (heldLightVal > 0.1) {
        float handGlow = max(0.0, (heldLightVal / 15.0) - terrainDist * 0.08);
        blockLight = max(blockLight, handGlow);
    }

    // ==============================================================================
    // DIMENSION-SPECIFIC LIGHTING
    // ==============================================================================
    if (isOverworld) {
        // --- OVERWORLD ---

        // ======================================================================
        // PHYSICALLY-BASED SOLAR IRRADIANCE MODEL
        // ======================================================================
        if (dayFactor > 0.01) {
            float sinAlpha = max(0.001, worldL.y);

            // Realistic Kelvin from solar elevation
            float currentK = getSolarKelvin(sinAlpha);

            // Kasten & Young atmospheric airmass + Beer-Lambert extinction
            float airMass = getAirmass(sinAlpha);
            // Rayleigh optical depth ~0.10 at sea level (tuned for game aesthetics)
            float extinction = exp(-airMass * 0.10);

            // Solar irradiance: colour × extinction × dayFactor
            // The 2.6 multiplier maps to ~100 klux at zenith (real world ≈ 100-120 klux)
            currentLightColor = kelvinToRGB(currentK) * extinction * 2.6 * dayFactor;
        } else {
            // ======================================================================
            // MOONLIGHT - phase-dependent, physically tinted
            // Real moonlight ≈ 4100 K (reflected sunlight, slight blueing)
            // Full moon ≈ 0.25 lux, new moon ≈ 0.001 lux
            // ======================================================================
            float moonBrightness = getMoonPhaseBrightness(moonPhase);
            vec3 moonBaseColor = kelvinToRGB(4100.0); // Silver-blue tint
            currentLightColor = moonBaseColor * 0.028 * moonBrightness;
        }

        // Weather dimming
        float weatherDimFactor = mix(1.0, 0.55, rainStrength);
        weatherDimFactor = mix(weatherDimFactor, 0.15, rainStrength * thunderStrength);
        currentLightColor *= weatherDimFactor;

        float NdotL = max(0.0, dot(normal, L));
        float shadow = 1.0;
        #ifdef SHADOWS
        vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
        vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
        vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
        shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
        float baseBias = 0.0008;
        float slopeBias = 0.0018 * (1.0 - clamp(NdotL, 0.0, 1.0));
        shadowClipPos.z -= (baseBias + slopeBias);
        vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
        vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;
        shadow = sampleShadow(shadowScreenPos, terrainDist, NdotL);
        #endif

        shadowFactor = mix(mix(0.25, 1.0, shadow), shadow, dayFactor);
        directLighting = currentLightColor * NdotL * skyLight * shadowFactor;

        // ======================================================================
        // SUNSET / SUNRISE BACK-SCATTER (subsurface-like warm rim glow)
        // When sun is low, surfaces facing AWAY from sun receive warm
        // scattered light through the thick atmosphere. Cost: 1 dot product.
        // ======================================================================
        if (sunsetFactor > 0.01 && dayFactor > 0.01) {
            float backDot = max(0.0, dot(normal, -L)); // surfaces facing away from sun
            float scatter = backDot * sunsetFactor * dayFactor * skyLight * shadowFactor;
            // Warm orange-red back-scatter tinted by the low-sun Kelvin
            vec3 scatterColor = kelvinToRGB(2400.0) * 0.35 * scatter;
            directLighting += scatterColor;
        }

        // ======================================================================
        // HEMISPHERE AMBIENT - sky dome above + ground bounce below
        // Instead of flat ambient, we blend between sky colour (up-facing)
        // and warm ground bounce colour (down-facing).
        // This gives natural directional ambient with zero extra texture fetches.
        // ======================================================================
        float normalUp = normal.y * 0.5 + 0.5; // 0 = facing down, 1 = facing up

        // Night base ambient (very dark blue)
        vec3 nightSkyAmbient = vec3(0.006, 0.008, 0.018);
        vec3 nightGroundAmbient = vec3(0.003, 0.003, 0.005);
        vec3 nightAmbient = mix(nightGroundAmbient, nightSkyAmbient, normalUp) * (0.4 + skyLight * 0.6);

        // Day ambient: blue sky dome from above, warm earth bounce from below
        vec3 daySkyAmbient = vec3(0.32, 0.42, 0.58);  // Blue sky indirect
        vec3 dayGroundAmbient = vec3(0.18, 0.14, 0.08); // Warm brown earth bounce
        vec3 dayAmbient = mix(dayGroundAmbient, daySkyAmbient, normalUp) * skyLight * 0.75;

        ambientColor = mix(nightAmbient, dayAmbient, dayFactor);

        // Sunset ambient gets warmer overall
        vec3 sunsetAmbient = vec3(0.22, 0.12, 0.06) * skyLight * 0.6;
        ambientColor = mix(ambientColor, sunsetAmbient, sunsetFactor * dayFactor * 0.5);

        // Weather dimming for ambient
        float ambientDimFactor = mix(1.0, 0.65, rainStrength);
        ambientDimFactor = mix(ambientDimFactor, 0.15, rainStrength * thunderStrength);
        ambientColor *= ambientDimFactor;

        // Fog colour transitions
        vec3 dayFog = vec3(0.55, 0.68, 0.82);
        vec3 nightFog = vec3(0.004, 0.006, 0.012);
        vec3 sunsetFog = vec3(0.8, 0.38, 0.12);
        currentFogColor = mix(nightFog, dayFog, dayFactor);
        currentFogColor = mix(currentFogColor, sunsetFog, sunsetFactor * dayFactor);

        vec3 rainFogColor = vec3(0.2, 0.22, 0.25);
        vec3 thunderFogColor = vec3(0.07, 0.08, 0.09);
        vec3 stormFogColor = mix(rainFogColor, thunderFogColor, thunderStrength);
        currentFogColor = mix(currentFogColor, stormFogColor, rainStrength);

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
        ambientColor = vec3(0.24, 0.13, 0.08) * pulse * 1.3;
        currentFogColor = vec3(0.24, 0.05, 0.01);
        fogDensity = 0.0038;

    } else if (isEnd) {
        // --- THE END ---
        directLighting = vec3(0.0);
        ambientColor = vec3(0.14, 0.1, 0.22);
        currentFogColor = vec3(0.02, 0.01, 0.05);
        fogDensity = 0.0012;
    }

    // ==============================================================================
    // SKY PASS
    // ==============================================================================
    if (depth >= 1.0) {
        vec3 finalColor = albedoData.rgb;
        #ifdef PROCEDURAL_CLOUDS
        if (isOverworld) {
            float cloudTime = frameTimeCounter * 0.05;
            vec4 volClouds = renderVolumetricClouds(worldDir, worldL, currentLightColor, 2500.0, dayFactor, sunsetFactor, cloudTime);
            finalColor = mix(finalColor, volClouds.rgb, volClouds.a);
        }
        #endif

        // Post-Rain Rainbow (Double Rainbow & Moonbow)
        if (isOverworld) {
            float dotRainbow = dot(worldDir, -worldL);
            float rainbowWidth = 0.055;

            if (dayFactor > 0.4) {
                float rainbowCenter = 0.745;
                float rainbowCenter2 = 0.629;

                float rFactor = smoothstep(rainbowCenter - rainbowWidth, rainbowCenter, dotRainbow) *
                                smoothstep(rainbowCenter + rainbowWidth, rainbowCenter, dotRainbow);
                float rFactor2 = smoothstep(rainbowCenter2 - rainbowWidth, rainbowCenter2, dotRainbow) *
                                 smoothstep(rainbowCenter2 + rainbowWidth, rainbowCenter2, dotRainbow);

                float pbrIntensityMult = 1.0;
                #if RAINBOW_STRENGTH == 1
                pbrIntensityMult = 0.45;
                #elif RAINBOW_STRENGTH == 3
                pbrIntensityMult = 1.85;
                #endif

                if (rFactor > 0.01) {
                    float bandPos = (dotRainbow - (rainbowCenter - rainbowWidth)) / (2.0 * rainbowWidth);
                    vec3 rainbowColor = vec3(0.0);
                    rainbowColor.r = smoothstep(0.4, 0.7, bandPos);
                    rainbowColor.g = smoothstep(0.2, 0.5, bandPos) * smoothstep(0.8, 0.5, bandPos);
                    rainbowColor.b = smoothstep(0.6, 0.3, bandPos);
                    float rainbowAlpha = rFactor * 0.32 * smoothstep(0.02, 0.15, worldDir.y) * pbrIntensityMult;
                    float clearingFactor = clamp(wetness * 1.5, 0.0, 1.0) * (1.0 - rainStrength);
                    rainbowAlpha *= clearingFactor;
                    finalColor += rainbowColor * rainbowAlpha;
                }

                if (rFactor2 > 0.01) {
                    float bandPos2 = 1.0 - ((dotRainbow - (rainbowCenter2 - rainbowWidth)) / (2.0 * rainbowWidth));
                    vec3 rainbowColor2 = vec3(0.0);
                    rainbowColor2.r = smoothstep(0.4, 0.7, bandPos2);
                    rainbowColor2.g = smoothstep(0.2, 0.5, bandPos2) * smoothstep(0.8, 0.5, bandPos2);
                    rainbowColor2.b = smoothstep(0.6, 0.3, bandPos2);
                    float rainbowAlpha2 = rFactor2 * 0.11 * smoothstep(0.02, 0.15, worldDir.y) * pbrIntensityMult;
                    float clearingFactor2 = clamp(wetness * 1.5, 0.0, 1.0) * (1.0 - rainStrength);
                    rainbowAlpha2 *= clearingFactor2;
                    finalColor += rainbowColor2 * rainbowAlpha2;
                }
            } else {
                float rainbowCenter = 0.745;
                float rFactorMoon = smoothstep(rainbowCenter - rainbowWidth, rainbowCenter, dotRainbow) *
                                    smoothstep(rainbowCenter + rainbowWidth, rainbowCenter, dotRainbow);
                if (rFactorMoon > 0.01) {
                    vec3 moonbowColor = vec3(0.45, 0.58, 0.8) * 0.18;
                    float moonbowAlpha = rFactorMoon * 0.28 * smoothstep(0.02, 0.15, worldDir.y);
                    float clearingFactorMoon = clamp(wetness * 1.5, 0.0, 1.0) * (1.0 - rainStrength);
                    moonbowAlpha *= clearingFactorMoon;
                    finalColor += moonbowColor * moonbowAlpha;
                }
            }
        }

        // Aurora Borealis
        #if AURORA_MODE != 0
        if (isOverworld && worldDir.y > 0.05) {
            float speedFactor = 1.0;
            #if AURORA_SPEED == 1
            speedFactor = 0.5;
            #elif AURORA_SPEED == 3
            speedFactor = 1.8;
            #endif
            float t = frameTimeCounter * 0.22 * speedFactor;
            vec2 auroraUV = worldDir.xz / (worldDir.y + 0.08);
            float northFactor = smoothstep(0.0, -0.65, worldDir.z);

            bool isColdBiome = true;
            #if AURORA_MODE == 1
            isColdBiome = (fogColor.b > fogColor.r * 1.01 && fogColor.b > 0.5) ||
                          (rainStrength > 0.1 && abs(worldTime - 12000) > 6000);
            #endif

            if (northFactor > 0.01 && isColdBiome) {
                float wave1 = noise(vec2(auroraUV.x * 1.5 + t, t * 0.15));
                float wave2 = noise(vec2(auroraUV.x * 3.0 - t * 0.25, t * 0.1));
                float curtain = smoothstep(0.35, 0.65, noise(auroraUV * 0.6 + wave1)) * 0.5 +
                                smoothstep(0.3, 0.7, noise(auroraUV * 1.3 - wave2)) * 0.5;

                vec3 greenColor = vec3(0.04, 0.95, 0.28);
                vec3 purpleColor = vec3(0.58, 0.05, 0.88);
                vec3 auroraColor = mix(greenColor, purpleColor, worldDir.y * 1.4);

                float multStr = 0.25;
                #if AURORA_STRENGTH == 1
                multStr = 0.08;
                #elif AURORA_STRENGTH == 3
                multStr = 0.55;
                #endif
                float auroraIntensity = mix(0.01, 1.0, 1.0 - dayFactor) * (1.0 - rainStrength) * multStr;
                float auroraAlpha = curtain * 0.38 * auroraIntensity * northFactor * smoothstep(0.02, 0.15, worldDir.y);
                finalColor += auroraColor * auroraAlpha;
            }
        }
        #endif

        colortex0Out = vec4(finalColor, albedoData.a);
        return;
    }

    // ==============================================================================
    // TERRAIN LIGHTING
    // ==============================================================================

    // ======================================================================
    // TORCH LIGHTING with Kelvin-based colour temperature
    // Real torch flame ≈ 1800 K, lantern/glowstone ≈ 2800-3200 K
    // We use the warmth slider to shift the colour temperature.
    // ======================================================================
    float blockIntensity = pow(blockLight, 3.2);

    // Cozy torch flickering
    float torchFlicker = 1.0;
    #ifdef COZY_LIGHTS
    torchFlicker = sin(frameTimeCounter * 4.0 + blockLight * 12.0) * 0.04 + 0.96;
    #endif

    // Kelvin-based torch colour
    float torchKelvin = 1900.0; // Default warm orange
    #if LIGHTMAP_WARMTH == 1
    torchKelvin = 1600.0;  // Very cozy deep amber (candlelight)
    #elif LIGHTMAP_WARMTH == 3
    torchKelvin = 2600.0;  // Brighter warm white (lantern-like)
    #endif
    vec3 torchColor = kelvinToRGB(torchKelvin) * 2.3;
    vec3 torchLighting = torchColor * blockIntensity * torchFlicker;

    // Lighting execution
    vec3 albedo = pow(albedoData.rgb, vec3(2.2));
    vec3 finalLight = directLighting + torchLighting + ambientColor;
    vec3 shadedTerrain = albedo * finalLight;

    // PBR Microfacet Specular shading (LabPBR support)
    #ifdef PBR_LIGHTING
    float roughness = lmData.z;
    float metalness = lmData.w;

    // Wetness effect
    #ifdef WET_REFLECTIONS
    if (rainStrength > 0.01 && isOverworld) {
        float wetnessFactor = rainStrength * skyLight * clamp(normal.y, 0.0, 1.0);
        roughness = mix(roughness, 0.08, wetnessFactor * 0.8);
        shadedTerrain *= (1.0 - wetnessFactor * 0.18);
    }
    #endif

    if (roughness > 0.001 || metalness > 0.001) {
        vec3 V = normalize(-viewPos);
        vec3 H = normalize(L + V);
        if (!isOverworld) {
            H = normalize(vec3(0.0, 1.0, 0.0) + V);
        }

        float alpha = roughness * roughness;
        float alpha2 = alpha * alpha;
        float NdotH = max(0.001, dot(normal, H));
        float NdotL_pbr = max(0.001, dot(normal, L));
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
        vec3 specColor = (D_GGX * G_Smith * F_Schlick) / max(0.08, 4.0 * NdotV * NdotL_pbr);

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
            // Moon specular — tinted by Kelvin 4100K, scaled by phase
            float moonBr = getMoonPhaseBrightness(moonPhase);
            specLightColor = kelvinToRGB(4100.0) * 0.45 * moonBr * pbrStrengthMult;
        }

        shadedTerrain += specColor * specLightColor * skyLight * shadowFactor * pbrStrengthMult;
    }
    #endif

    // Apply dimensional fog
    float fogFactor = 1.0 - exp(-terrainDist * fogDensity);
    fogFactor = clamp(fogFactor, 0.0, 1.0);
    vec3 finalColor = mix(shadedTerrain, currentFogColor, fogFactor);

    // Underwater Caustics & Underlava
    if (isEyeInWater == 1) {
        vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
        vec2 causticCoord = feetPlayerPos.xz * 0.28 + vec2(frameTimeCounter * 0.45, frameTimeCounter * 0.25);
        float causticNoise = fbm(causticCoord);
        float caustic = pow(smoothstep(0.42, 0.68, causticNoise), 2.2);
        vec3 causticColor = vec3(0.12, 0.48, 0.85) * caustic * skyLight * 1.6 * dayFactor;
        finalColor += causticColor;
        finalColor = mix(finalColor, vec3(0.08, 0.35, 0.62), 0.32);
    } else if (isEyeInWater == 2) {
        finalColor = mix(finalColor, vec3(0.85, 0.12, 0.01), 0.95);
    }

    // Low-lying ground mist
    if (sunsetFactor > 0.01 && isOverworld) {
        float worldY = cameraPosition.y + worldDir.y * terrainDist;
        float mistDensityFactor = getGroundMistDensity(worldY);

        if (mistDensityFactor > 0.01) {
            vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
            vec2 mistUV = feetPlayerPos.xz * 0.06 + vec2(frameTimeCounter * 0.05, frameTimeCounter * 0.02);
            float mistNoise = noise(mistUV) * 0.4 + 0.6;
            float mistOpacity = mistDensityFactor * mistNoise * sunsetFactor * 0.68;
            mistOpacity *= clamp(1.0 - terrainDist / 120.0, 0.0, 1.0);
            vec3 mistColor = mix(vec3(0.92, 0.94, 0.96), vec3(1.0, 0.45, 0.1), sunsetFactor * 0.55);
            finalColor = mix(finalColor, mistColor, mistOpacity);
        }
    }

    // Volumetric clouds blending
    #ifdef PROCEDURAL_CLOUDS
    if (isOverworld) {
        float cloudTime = frameTimeCounter * 0.05;
        vec4 volClouds = renderVolumetricClouds(worldDir, worldL, currentLightColor, terrainDist, dayFactor, sunsetFactor, cloudTime);
        finalColor = mix(finalColor, volClouds.rgb, volClouds.a);
    }
    #endif

    colortex0Out = vec4(finalColor, albedoData.a);
}

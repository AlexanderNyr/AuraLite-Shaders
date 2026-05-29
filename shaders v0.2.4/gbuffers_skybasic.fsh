#version 460 compatibility

// ==============================================================================
// AuraLite Shader Pack - Sky Fragment Shader (GLSL 460 - Enhanced Lighting)
// ==============================================================================
// [FIX v0.2.3] Added CLOUD_HEIGHT / CLOUD_THICKNESS defines so sky clouds match composite.
// [FIX v0.2.3] Added SUN_TEMPERATURE define so sun disk colour matches composite Kelvin curve.
// [FIX v0.2.3] Removed unused 'uniform int dimension' declaration.
// [FIX v0.2.5] Removed dead renderVolumetricClouds() function — it was never called
//       (clouds are rendered exclusively in composite.fsh). This saves GPU compilation time.

#define PROCEDURAL_CLOUDS   // [true false]
#define CLOUD_HEIGHT 2      // [1 2 3] - [FIX v0.2.3] Added
#define CLOUD_THICKNESS 2   // [1 2 3] - [FIX v0.2.3] Added
#define SUN_TEMPERATURE 2   // [1 2 3] - [FIX v0.2.3] Added
#define NEBULA_BRIGHTNESS 2 // [1 2 3]
#define STARS_BRIGHTNESS 2  // [1 2 3]
#define STARS_AMOUNT 2      // [1 2 3]

/* DRAWBUFFERS:0 */

in vec4 glcolor;
in vec3 viewPos;

uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;
uniform int worldTime;
uniform float rainStrength;
uniform float thunderStrength;
uniform int moonPhase;

layout(location = 0) out vec4 colortex0;

// ==============================================================================
// PHYSICALLY ACCURATE KELVIN → sRGB (Tanner Helland algorithm)
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
// REALISTIC SOLAR KELVIN MODEL (synced with composite.fsh)
// [FIX v0.2.3] Now applies SUN_TEMPERATURE offset, matching composite.fsh
// ==============================================================================
float getSolarKelvin(float sinElevation) {
    float t = clamp(sinElevation, 0.0, 1.0);
    float baseK = 2200.0 + 3500.0 * pow(t, 0.62);
#if SUN_TEMPERATURE == 1
    baseK += 600.0;
#elif SUN_TEMPERATURE == 3
    baseK -= 500.0;
#endif
    return clamp(baseK, 1500.0, 7500.0);
}

float getAirmass(float sinElevation) {
    float elevDeg = degrees(asin(clamp(sinElevation, 0.001, 1.0)));
    return 1.0 / (sinElevation + 0.50572 * pow(elevDeg + 6.07995, -1.6364));
}

// 100% stable float-based high performance hash
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

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

// [FIX v0.2.5] Removed dead renderVolumetricClouds() function.
// Clouds are rendered exclusively in composite.fsh. This function was ~70 lines
// of raymarching code that was compiled but never called, wasting GPU time.

// 3D LUNAR SPHERE PHASE CARVER WITH EARTHSHINE GLOW
float getMoonIllumination(vec2 coord, int phase) {
    float r2 = dot(coord, coord);
    if (r2 > 1.0) return 0.0;

    float diskEdge = smoothstep(1.0, 0.96, r2);
    float z = sqrt(1.0 - r2);
    vec3 normal3D = vec3(coord.x, coord.y, z);

    float phaseAngle = float(phase) * 0.78539816;
    vec3 localLightDir = vec3(sin(phaseAngle), 0.0, cos(phaseAngle));
    float ndotl = dot(normal3D, localLightDir);

    float illumination = mix(0.012, 1.0, smoothstep(-0.06, 0.06, ndotl));
    return diskEdge * illumination;
}

void main() {
    vec3 dir = normalize(viewPos);
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * dir);
    float dotUp = worldDir.y;

    // Dimension Detection
    bool isNether = (glcolor.r > 0.15 && glcolor.g < 0.05 && glcolor.b < 0.05);
    bool isEnd = (glcolor.r > 0.01 && glcolor.r < 0.08 && glcolor.g < 0.02 && glcolor.b > 0.08 && glcolor.b < 0.2);
    bool isOverworld = !isNether && !isEnd;

    vec3 finalSky;

    if (isOverworld) {
        // --- OVERWORLD SKY ---
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

        float gradHeight = clamp(dotUp * 0.5 + 0.5, 0.0, 1.0);

        vec3 daySky = mix(vec3(0.42, 0.62, 0.9), vec3(0.12, 0.32, 0.72), gradHeight);
        vec3 nightSky = mix(vec3(0.004, 0.006, 0.012), vec3(0.0005, 0.001, 0.003), gradHeight);
        vec3 sunsetSky = mix(vec3(0.85, 0.42, 0.12), vec3(0.18, 0.08, 0.28), gradHeight);

        vec3 skyColor = mix(nightSky, daySky, dayFactor);
        skyColor = mix(skyColor, sunsetSky, sunsetFactor * dayFactor);

        vec3 rainSky = vec3(0.24, 0.26, 0.29);
        vec3 thunderSky = vec3(0.05, 0.055, 0.065);
        vec3 stormSky = mix(rainSky, thunderSky, thunderStrength);
        skyColor = mix(skyColor, stormSky, rainStrength * 0.85);

        vec3 baseSky = skyColor;

        float horizonGlow = clamp(1.0 - abs(dotUp), 0.0, 1.0);
        horizonGlow = pow(horizonGlow, 4.5);

        vec3 worldL = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
        float dotLight = dot(worldDir, worldL);

        vec3 glowColor = vec3(0.0);
        vec3 sunLightColor = vec3(1.0);

        if (dayFactor > 0.1) {
            // ======================================================================
            // REALISTIC SUN DISK — Kelvin from elevation, Kasten & Young airmass
            // [FIX v0.2.3] getSolarKelvin now respects SUN_TEMPERATURE
            // ======================================================================
            float sinAlpha = max(0.001, worldL.y);
            float currentK = getSolarKelvin(sinAlpha);
            float airMass = getAirmass(sinAlpha);
            float extinction = exp(-airMass * 0.10);
            sunLightColor = kelvinToRGB(currentK) * extinction;

            float sunGlow = max(0.0, dotLight);
            float sunDisk = smoothstep(0.9994, 0.9996, dotLight);

            float corona = pow(sunGlow, 180.0) * 0.95;
            float halo = pow(sunGlow, 10.0) * 0.25 * dayFactor;
            glowColor = sunLightColor * (sunDisk * 5.0 + corona + halo);

            if (sunsetFactor > 0.01) {
                vec3 lowSunTint = kelvinToRGB(getSolarKelvin(0.02));
                float horizonSunset = pow(max(0.0, 1.0 - abs(dotUp)), 6.0) * sunsetFactor;
                baseSky += lowSunTint * horizonSunset * 0.25;
            }
        } else {
            // --- MOON ---
            float dotMoon = dot(worldDir, worldL);
            float moonGlow = max(0.0, dotMoon);

            vec3 moonTangent = normalize(cross(worldL, vec3(0.0, 1.0, 0.0)));
            vec3 moonBinormal = normalize(cross(worldL, moonTangent));
            vec2 moonCoord = vec2(dot(worldDir, moonTangent), dot(worldDir, moonBinormal));
            vec2 normMoonCoord = moonCoord / 0.028;

            float moonMask = getMoonIllumination(normMoonCoord, moonPhase);

            float moonCorona = pow(moonGlow, 260.0) * 0.5;
            float moonHalo = pow(moonGlow, 14.0) * 0.12 * (1.0 - dayFactor);

            vec3 moonColor = kelvinToRGB(4100.0);
            glowColor = moonColor * (moonMask * 3.5 + moonCorona + moonHalo) * 0.5;
        }

        glowColor *= (1.0 - rainStrength * mix(0.65, 0.95, thunderStrength));

        finalSky = baseSky + glowColor + baseSky * horizonGlow * 0.28;

        // Stars
        if (dayFactor < 0.9) {
            vec3 starDir = normalize(worldDir);

            float amountMult = 220.0;
            #if STARS_AMOUNT == 1
            amountMult = 140.0;
            #elif STARS_AMOUNT == 3
            amountMult = 320.0;
            #endif

            vec3 starGrid = floor(starDir * amountMult);
            float starNoise = hash3D(starGrid);

            float threshold = 0.994;
            #if STARS_AMOUNT == 1
            threshold = 0.997;
            #elif STARS_AMOUNT == 3
            threshold = 0.988;
            #endif

            float starGlow = smoothstep(threshold, 1.0, starNoise);
            float twinkle = sin(frameTimeCounter * 3.5 + starNoise * 80.0) * 0.35 + 0.65;

            float brightMult = 1.0;
            #if STARS_BRIGHTNESS == 1
            brightMult = 0.4;
            #elif STARS_BRIGHTNESS == 3
            brightMult = 2.2;
            #endif

            float starTemp = 3500.0 + starNoise * 5500.0;
            vec3 starColor = kelvinToRGB(starTemp);

            vec3 stars = starColor * starGlow * twinkle * smoothstep(-0.02, 0.15, worldDir.y) * (1.0 - dayFactor) * (1.0 - rainStrength) * brightMult;
            finalSky += stars;
        }

        // Milky Way Nebula
        if (dayFactor < 0.9) {
            float galacticPlane = dot(worldDir, normalize(vec3(1.0, 1.2, -0.8)));
            float milkyWay = smoothstep(0.28, 0.0, abs(galacticPlane));

            float nebulaNoise = fbm(worldDir.xz * 1.8 + vec2(frameTimeCounter * 0.003));

            float nebBright = 1.0;
            #if NEBULA_BRIGHTNESS == 1
            nebBright = 0.45;
            #elif NEBULA_BRIGHTNESS == 3
            nebBright = 1.95;
            #endif

            vec3 nebulaColor = mix(vec3(0.004, 0.002, 0.008), vec3(0.08, 0.048, 0.022), milkyWay * 0.7) * smoothstep(0.35, 0.75, nebulaNoise);

            vec3 starGridDust = floor(worldDir * 280.0);
            float dustNoise = hash3D(starGridDust);
            float starDust = smoothstep(0.995, 1.0, dustNoise) * smoothstep(0.4, 0.7, nebulaNoise) * milkyWay;
            vec3 starDustColor = vec3(0.95, 0.92, 0.82) * starDust * 0.4;

            finalSky += (nebulaColor + starDustColor) * (1.0 - dayFactor) * (1.0 - rainStrength) * nebBright;
        }

    } else if (isNether) {
        finalSky = vec3(0.12, 0.02, 0.0);

    } else if (isEnd) {
        float gradHeight = clamp(dotUp * 0.5 + 0.5, 0.0, 1.0);
        vec3 spaceGrad = mix(vec3(0.008, 0.0, 0.018), vec3(0.028, 0.008, 0.055), gradHeight);

        vec2 starCoord = worldDir.xy / (abs(worldDir.z) + 0.04) * 8.0;
        float starNoise = hash(floor(starCoord * 14.0));
        float starGlow = smoothstep(0.993, 1.0, starNoise);
        float twinkle = sin(frameTimeCounter * 3.5 + starNoise * 80.0) * 0.35 + 0.65;
        vec3 stars = vec3(0.92, 0.88, 1.0) * starGlow * twinkle * smoothstep(-0.15, 0.15, worldDir.y);

        float nebulaNoise = fbm(worldDir.xz * 2.8 + vec2(frameTimeCounter * 0.006));
        vec3 nebulaColor = vec3(0.12, 0.015, 0.18) * smoothstep(0.35, 0.72, nebulaNoise);

        finalSky = spaceGrad + stars + nebulaColor;
    }

    colortex0 = vec4(finalSky, glcolor.a);
}

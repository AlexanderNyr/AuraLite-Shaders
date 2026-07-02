#version 460 compatibility
// AuraLite Shaders v1.0.8 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack — Sky Fragment Shader (GLSL 460)
// [v1.0.8] Dual Sky System — switchable between:
//   NEW_SKY ON  → Physically-Based Atmospheric Scattering (Rayleigh + Mie)
//   NEW_SKY OFF → Legacy gradient sky from v1.0.7 (Kelvin sun/moon)
// ==============================================================================

// --- Sky configuration ---
//#define NEW_SKY               // [true false] Atmospheric scattering sky (ON) or legacy gradient sky (OFF)
#define SKY_QUALITY 3         // [1 2 3] Scattering sample counts (only when NEW_SKY is ON)
#define NEBULA_BRIGHTNESS 2   // [1 2 3]
#define STARS_BRIGHTNESS 2    // [1 2 3]
#define STARS_AMOUNT 2        // [1 2 3]
#define AURORA_MODE 2         // [0 1 2]
#define AURORA_SPEED 2        // [1 2 3]
#define AURORA_STRENGTH 2     // [1 2 3]
#define RAINBOW_STRENGTH 2    // [1 2 3]
#define SHOOTING_STARS              // [true false]
#define SHOOTING_STARS_FREQUENCY 2  // [1 2 3]
#define SHOOTING_STARS_BRIGHTNESS 2 // [1 2 3]

/* DRAWBUFFERS:0 */

in vec4 glcolor;
in vec3 viewPos;

uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;
uniform int worldTime;
uniform float rainStrength;
uniform float thunderStrength;
uniform float wetness;
uniform int moonPhase;
uniform float auroraColdBiome;
uniform int dimension;
uniform float isNetherBiome;
uniform float isEndBiome;
uniform vec3 cameraPosition;

layout(location = 0) out vec4 colortex0;

// ==============================================================================
// CONSTANTS
// ==============================================================================
const float PI = 3.14159265359;

#ifdef NEW_SKY
// Atmosphere physics (used only by atmospheric scattering sky)
const float R_GROUND   = 6371000.0;
const float R_ATMO     = 6471000.0;
const float H_RAYLEIGH = 8000.0;
const float H_MIE      = 1200.0;
const vec3  BETA_R = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const vec3  BETA_M = vec3(21.0e-6, 21.0e-6, 21.0e-6);
const float MIE_EXTINCTION_MULT = 1.1;
const float SUN_RADIUS = 0.00467;
const float MOON_RADIUS = 0.00450;
const vec3  SUN_IRRADIANCE = vec3(25.0, 23.8, 22.5);

// Ozone layer — Chappuis absorption band (~600nm, orange-red)
// Responsible for deep blue/violet twilight colors
const vec3  BETA_OZ = vec3(3.4e-6, 5.0e-6, 0.25e-6); // Absorption coefficients
const float H_OZ_PEAK = 25000.0;  // Peak altitude (m)
const float H_OZ_WIDTH = 15000.0; // Gaussian half-width (m)

float getCameraAltitude() {
    return max(0.0, (cameraPosition.y - 63.0)) * 100.0;
}

// Ozone density: Gaussian profile centered at ~25 km
float ozoneDensity(float h) {
    float d = (h - H_OZ_PEAK) / H_OZ_WIDTH;
    return exp(-d * d * 0.5);
}

// Atmospheric refraction (Bennett's formula)
// Lifts the apparent elevation of objects near the horizon by up to ~0.57°
vec3 applyRefraction(vec3 dir) {
    float elev = asin(clamp(dir.y, -1.0, 1.0));
    float elevDeg = degrees(elev);
    float refArcmin = 0.0;
    if (elevDeg > -1.5) {
        float arg = max(elevDeg + 10.3 / (elevDeg + 5.11), 0.05);
        refArcmin = 1.02 / tan(radians(arg));
        refArcmin = clamp(refArcmin, 0.0, 35.0);
    }
    float newElev = elev + radians(refArcmin / 60.0);
    float horizLen = length(dir.xz);
    if (horizLen < 1e-6) return vec3(0.0, sin(newElev), cos(newElev) * step(0.0, dir.z));
    vec2 horizDir = dir.xz / horizLen;
    return vec3(horizDir * cos(newElev), sin(newElev));
}

bool raySphere(vec3 ro, vec3 rd, float R, out float t0, out float t1) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - R * R;
    float disc = b * b - c;
    if (disc < 0.0) return false;
    disc = sqrt(disc);
    t0 = -b - disc;
    t1 = -b + disc;
    return true;
}

float phaseRayleigh(float cosTheta) {
    return 0.05968310366 * (1.0 + cosTheta * cosTheta);
}

float phaseMie(float cosTheta) {
    const float g = 0.76;
    const float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) / (4.0 * PI * denom * sqrt(denom));
}

bool lightRayOpticalDepth(vec3 p, vec3 sunDir, int N_light,
                          out float odR, out float odM, out float odOZ) {
    odR = 0.0; odM = 0.0; odOZ = 0.0;
    float tLight0, tLight1;
    if (!raySphere(p, sunDir, R_ATMO, tLight0, tLight1)) return false;
    float dtL = max(tLight1, 0.0) / float(N_light);
    for (int j = 0; j < 12; ++j) {
        if (j >= N_light) break;
        float tL = (float(j) + 0.5) * dtL;
        vec3 pL = p + sunDir * tL;
        float hL = length(pL) - R_GROUND;
        if (hL < 0.0) return false;
        odR  += exp(-hL / H_RAYLEIGH) * dtL;
        odM  += exp(-hL / H_MIE) * dtL;
        odOZ += ozoneDensity(hL) * dtL;
    }
    return true;
}

vec3 computeAtmosphericScattering(vec3 viewDir, vec3 sunDir) {
    float camAlt = getCameraAltitude();
    vec3 ro = vec3(0.0, R_GROUND + camAlt, 0.0);
    // Apply atmospheric refraction to the view direction
    vec3 rd = applyRefraction(viewDir);
    float tAtmo0, tAtmo1;
    if (!raySphere(ro, rd, R_ATMO, tAtmo0, tAtmo1)) return vec3(0.0);
    tAtmo0 = max(tAtmo0, 0.0);
    float rayLen = tAtmo1 - tAtmo0;
    if (rayLen <= 0.0) return vec3(0.0);

    int N = 12; int N_light = 6;
    #if SKY_QUALITY == 1
    N = 8; N_light = 4;
    #elif SKY_QUALITY == 3
    N = 16; N_light = 8;
    #endif

    float dt = rayLen / float(N);
    vec3 sumR = vec3(0.0), sumM = vec3(0.0);
    float viewOdR = 0.0, viewOdM = 0.0, viewOdOZ = 0.0;

    for (int i = 0; i < 24; ++i) {
        if (i >= N) break;
        float t = tAtmo0 + (float(i) + 0.5) * dt;
        vec3 p = ro + rd * t;
        float h = length(p) - R_GROUND;
        float hr = exp(-h / H_RAYLEIGH) * dt;
        float hm = exp(-h / H_MIE) * dt;
        float hoz = ozoneDensity(h) * dt;
        float odLightR, odLightM, odLightOZ;
        if (!lightRayOpticalDepth(p, sunDir, N_light, odLightR, odLightM, odLightOZ)) {
            viewOdR += hr; viewOdM += hm; viewOdOZ += hoz; continue;
        }
        // Total optical depth: Rayleigh + Mie + Ozone absorption
        vec3 tau = BETA_R * (viewOdR + odLightR)
                 + BETA_M * MIE_EXTINCTION_MULT * (viewOdM + odLightM)
                 + BETA_OZ * (viewOdOZ + odLightOZ);
        vec3 attenuation = exp(-tau);
        sumR += attenuation * hr;
        sumM += attenuation * hm;
        viewOdR += hr; viewOdM += hm; viewOdOZ += hoz;
    }

    float cosTheta = dot(rd, sunDir);
    vec3 skyColor = SUN_IRRADIANCE * (sumR * BETA_R * phaseRayleigh(cosTheta)
                                     + sumM * BETA_M * phaseMie(cosTheta));

    // ====================================================================
    // ENHANCED MULTIPLE SCATTERING
    // ====================================================================
    // (1) Scale up single scattering to compensate for missing higher orders
    skyColor *= 1.45;

    // (2) Isotropic ambient fill from multiply-scattered light
    float sunAbove = smoothstep(-0.20, 0.30, sunDir.y);
    skyColor += SUN_IRRADIANCE * 0.007 * sunAbove * vec3(0.40, 0.50, 0.64);

    // (3) Forward-scatter aureole (bright haze around the sun from Mie)
    float aureole = pow(max(0.0, cosTheta), 8.0) * 0.45 * sunAbove;
    skyColor += SUN_IRRADIANCE * aureole * vec3(0.34, 0.30, 0.24) * 0.006;

    // (4) Ground albedo bounce — warm reflected light from below
    //     Earth surface average albedo ~0.3, gives warm fill to lower hemisphere
    float groundBounce = max(0.0, -rd.y) * 0.12 * sunAbove;
    skyColor += SUN_IRRADIANCE * groundBounce * vec3(0.14, 0.11, 0.06) * 0.005;

    // (5) 2nd-order Rayleigh: sky light re-scattered (fills in dark areas)
    //     Approximate as proportional to the total single-scatter energy
    float totalEnergy = dot(sumR * BETA_R, vec3(0.2126, 0.7152, 0.0722));
    skyColor += vec3(0.35, 0.45, 0.60) * totalEnergy * 0.18 * sunAbove;

    return skyColor;
}

vec3 getSunTransmittance(vec3 sunDir) {
    float camAlt = getCameraAltitude();
    vec3 ro = vec3(0.0, R_GROUND + camAlt, 0.0);
    float t0, t1;
    if (!raySphere(ro, sunDir, R_ATMO, t0, t1)) return vec3(1.0);
    int N = 8;
    #if SKY_QUALITY == 1
    N = 5;
    #elif SKY_QUALITY == 3
    N = 12;
    #endif
    float dt = max(t1, 0.0) / float(N);
    float odR = 0.0, odM = 0.0, odOZ = 0.0;
    for (int i = 0; i < 16; ++i) {
        if (i >= N) break;
        float t = (float(i) + 0.5) * dt;
        vec3 p = ro + sunDir * t;
        float h = length(p) - R_GROUND;
        odR  += exp(-h / H_RAYLEIGH) * dt;
        odM  += exp(-h / H_MIE) * dt;
        odOZ += ozoneDensity(h) * dt;
    }
    return exp(-(BETA_R * odR + BETA_M * MIE_EXTINCTION_MULT * odM + BETA_OZ * odOZ));
}

vec3 renderSunDisk(vec3 viewDir, vec3 sunDir, vec3 sunColor) {
    float cosAngle = dot(viewDir, sunDir);
    float angle = acos(clamp(cosAngle, -1.0, 1.0));

    // Refraction-based vertical flattening near horizon
    // The sun appears squished vertically because refraction lifts the bottom more than the top
    float sunElev = asin(clamp(sunDir.y, -1.0, 1.0));
    float flattenFactor = mix(0.75, 1.0, smoothstep(0.0, 0.3, abs(sunElev)));
    // Compute effective angular distance with vertical compression
    vec3 toSun = sunDir - viewDir * cosAngle;
    float toSunLen = length(toSun);
    if (toSunLen > 1e-6) {
        vec3 sunPerp = toSun / toSunLen;
        float vertComponent = dot(viewDir, vec3(0.0, 1.0, 0.0)) - cosAngle * sunDir.y;
        // Effective angle with vertical compression
        float horizAngle = sqrt(max(0.0, angle * angle - vertComponent * vertComponent));
        float vertAngle = abs(vertComponent) / flattenFactor;
        float effectiveAngle = sqrt(horizAngle * horizAngle + vertAngle * vertAngle);
        angle = effectiveAngle;
    }

    float disk = smoothstep(SUN_RADIUS * 1.08, SUN_RADIUS * 0.92, angle);
    float r = clamp(angle / SUN_RADIUS, 0.0, 1.0);

    // Improved limb darkening (Eddington approximation: I(μ) = I₀(1 - u + u·μ))
    // where μ = cos(angle from disk center), u ≈ 0.6 for the sun
    float mu = sqrt(max(0.0, 1.0 - r * r));
    float limb = 1.0 - 0.6 * (1.0 - mu);

    // Outer corona glow (extends further than disk)
    float corona = smoothstep(SUN_RADIUS * 5.0, SUN_RADIUS * 1.0, angle) * (1.0 - disk) * 0.40;
    // Inner corona (tight bright ring just outside disk)
    float innerCorona = smoothstep(SUN_RADIUS * 1.8, SUN_RADIUS * 1.0, angle)
                      * (1.0 - smoothstep(SUN_RADIUS * 0.95, SUN_RADIUS * 1.1, angle)) * 0.25;

    return (disk * limb * 14.0 + corona + innerCorona) * sunColor;
}

// ==============================================================================
// AIRGLOW — Faint emission from excited oxygen at ~90-100 km altitude
// Green OI 557.7nm line + faint red OI 630nm line. Visible on dark nights.
// ==============================================================================
vec3 computeAirglow(vec3 viewDir, float dayFactor) {
    if (dayFactor > 0.15) return vec3(0.0); // Washed out during day/twilight
    float nightVis = 1.0 - smoothstep(0.0, 0.15, dayFactor);

    float camAlt = getCameraAltitude();
    vec3 ro = vec3(0.0, R_GROUND + camAlt, 0.0);
    vec3 rd = applyRefraction(viewDir);

    // Intersect view ray with the airglow emission shell (~90-95 km)
    float shellAlt = 92000.0;
    float t0, t1;
    if (!raySphere(ro, rd, R_GROUND + shellAlt, t0, t1)) return vec3(0.0);
    float tClosest = max(0.0, -dot(ro, rd)); // Closest approach to Earth center
    tClosest = min(tClosest, t1);
    vec3 p = ro + rd * tClosest;
    float h = length(p) - R_GROUND;

    // Emission profile: peaks at 92 km, narrow Gaussian
    float emitProfile = exp(-pow((h - shellAlt) / 4500.0, 2.0));

    // Green oxygen line (557.7nm) — dominant
    // Red oxygen line (630nm) — fainter, higher altitude
    vec3 airglowColor = vec3(0.12, 0.32, 0.06) * emitProfile       // Green OI
                      + vec3(0.10, 0.03, 0.015) * emitProfile * 0.35; // Red OI

    // Slight spatial variation (wave patterns in the upper atmosphere)
    float wavePattern = vnoise(viewDir.xz * 8.0 + frameTimeCounter * 0.002) * 0.3 + 0.7;

    return airglowColor * nightVis * 0.018 * wavePattern;
}

// ==============================================================================
// ZODIACAL LIGHT — Sunlight scattered by interplanetary dust in the solar system
// Visible as a faint cone of light along the ecliptic after sunset / before sunrise
// ==============================================================================
vec3 computeZodiacalLight(vec3 viewDir, vec3 sunDir, float dayFactor) {
    // Only visible during twilight and early night (Gegenschein at opposition is too faint)
    if (dayFactor > 0.6 || sunDir.y > 0.15) return vec3(0.0);
    float vis = smoothstep(0.6, 0.0, dayFactor) * smoothstep(0.15, -0.1, sunDir.y);

    // Angular distance from the sun (elongation)
    float cosAngle = dot(viewDir, sunDir);
    float elongation = acos(clamp(cosAngle, -1.0, 1.0));

    // Intensity: strong near the sun, falls as ~elongation^-2.3
    float intensity = pow(max(0.0, 1.0 - elongation / PI), 2.3);
    // Only visible as a cone close to the sun direction
    intensity *= smoothstep(PI * 0.6, 0.15, elongation);

    // Concentrated near the ecliptic plane (tilt ~23.4° from celestial equator)
    // Approximate ecliptic normal
    vec3 eclipticNormal = normalize(vec3(0.0, cos(radians(23.4)), sin(radians(23.4))));
    float eclipticLat = abs(dot(viewDir, eclipticNormal));
    float eclipticBand = exp(-eclipticLat * eclipticLat * 12.0);
    intensity *= eclipticBand;

    // Warm color (reflected sunlight, slightly reddened)
    vec3 zodiacalColor = vec3(0.95, 0.82, 0.58) * intensity * 0.012;

    return zodiacalColor * vis;
}

// ==============================================================================
// TWILIGHT PHENOMENA — Belt of Venus + Earth Shadow + Afterglow
// These are visible during civil/nautical twilight when sun is just below horizon
// ==============================================================================
vec3 computeTwilightPhenomena(vec3 viewDir, vec3 sunDir, float dayFactor, float sunsetFactor) {
    if (sunsetFactor < 0.01 && dayFactor > 0.5) return vec3(0.0);

    vec3 result = vec3(0.0);
    float sunElev = asin(clamp(sunDir.y, -1.0, 1.0));

    // --- BELT OF VENUS ---
    // Pink/rose band ~10-20° above the anti-solar horizon during twilight
    // Caused by backscattered sunlight in the upper atmosphere
    vec3 antiSunDir = -sunDir;
    float antiSunDot = dot(viewDir, antiSunDir);
    float antiSunAngle = acos(clamp(antiSunDot, -1.0, 1.0));

    // Belt peaks at ~15° above anti-solar point, visible near horizon
    float beltAngle = antiSunAngle;
    float beltPeak = smoothstep(0.15, 0.35, beltAngle) * (1.0 - smoothstep(0.35, 0.55, beltAngle));
    float horizonMask = smoothstep(0.0, 0.12, viewDir.y) * (1.0 - smoothstep(0.12, 0.35, viewDir.y));
    float beltIntensity = beltPeak * horizonMask;

    // Belt is pink/rose colored (backscattered red light from sunset)
    vec3 beltColor = vec3(0.85, 0.45, 0.55) * beltIntensity * 0.18;

    // Visibility: strongest during twilight (sun 0° to -6° below horizon)
    float twilightVis = smoothstep(0.08, -0.05, sunDir.y) * smoothstep(-0.18, -0.05, sunDir.y);
    beltColor *= twilightVis;
    result += beltColor;

    // --- EARTH SHADOW ---
    // Dark blue/gray band below the Belt of Venus (Earth's shadow on the atmosphere)
    // Visible as a darkening just above the horizon opposite to the sun
    float shadowBand = smoothstep(0.0, 0.08, viewDir.y) * (1.0 - smoothstep(0.08, 0.18, viewDir.y));
    float antiSunHorizon = smoothstep(-0.3, 0.1, antiSunDot);
    float earthShadow = shadowBand * antiSunHorizon * 0.35;

    // Dark blue/gray color
    vec3 shadowColor = vec3(0.08, 0.12, 0.18) * earthShadow * twilightVis;
    // Subtract from sky (darken it)
    result -= shadowColor;

    // --- AFTERGLOW ---
    // Warm orange/red band that persists on the horizon after sunset
    // Caused by multiple scattering in the lower atmosphere
    float sunHorizon = smoothstep(0.15, -0.05, sunDir.y) * smoothstep(-0.25, -0.05, sunDir.y);
    float sunDirDot = dot(viewDir, sunDir);
    float sunAngle = acos(clamp(sunDirDot, -1.0, 1.0));

    // Afterglow is concentrated near the sun's azimuth on the horizon
    float afterglowHorizon = smoothstep(0.0, 0.08, viewDir.y) * (1.0 - smoothstep(0.08, 0.25, viewDir.y));
    float afterglowSpread = smoothstep(1.8, 0.4, sunAngle); // Spread ~60° from sun azimuth
    float afterglowIntensity = sunHorizon * afterglowHorizon * afterglowSpread;

    // Warm orange/red color (multiply scattered sunset light)
    vec3 afterglowColor = vec3(0.95, 0.45, 0.18) * afterglowIntensity * 0.22;
    result += afterglowColor;

    return result;
}

#endif // NEW_SKY

// ==============================================================================
// KELVIN SOLAR MODEL (used by legacy sky for sun/moon color)
// ==============================================================================
vec3 kelvinToRGB(float k) {
    k = clamp(k, 1000.0, 40000.0) / 100.0;
    float r, g, b;
    if (k <= 66.0) {
        r = 255.0;
        g = clamp(99.4708025861 * log(k) - 161.1195681661, 0.0, 255.0);
        b = k < 19.0 ? 0.0 : clamp(138.5177312231 * log(k - 10.0) - 305.0447927307, 0.0, 255.0);
    } else {
        r = clamp(329.698727446 * pow(k - 60.0, -0.1332047592), 0.0, 255.0);
        g = clamp(288.1221695283 * pow(k - 60.0, -0.0755148492), 0.0, 255.0);
        b = 255.0;
    }
    return vec3(r, g, b) / 255.0;
}

#ifndef NEW_SKY
float getSolarKelvin(float sinElevation) {
    float t = clamp(sinElevation, 0.0, 1.0);
    float baseK = 2200.0 + 3500.0 * pow(t, 0.62);
    return clamp(baseK, 1500.0, 7500.0);
}

float getAirmass(float sinElevation) {
    float elevDeg = degrees(asin(clamp(sinElevation, 0.001, 1.0)));
    return 1.0 / (sinElevation + 0.50572 * pow(elevDeg + 6.07995, -1.6364));
}
#endif

// ==============================================================================
// HASH / NOISE (common to both skies)
// ==============================================================================
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

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1,0)), u.x),
               mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), u.x), u.y);
}

const mat2 fbmRot = mat2(0.87758256, 0.47942554, -0.47942554, 0.87758256);

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += a * vnoise(p);
        p = fbmRot * p * 2.1 + vec2(100.0);
        a *= 0.5;
    }
    return v;
}

// ==============================================================================
// MOON (common to both skies — extinction varies)
// ==============================================================================
float getMoonIllumination(vec2 coord, int phase) {
    float r2 = dot(coord, coord);
    if (r2 > 1.0) return 0.0;
    float diskEdge = 1.0 - smoothstep(0.96, 1.0, r2);
    float z = sqrt(max(0.0, 1.0 - r2));
    vec3 n3d = vec3(coord.x, coord.y, z);
    float phaseAngle = float(phase) * 0.78539816;
    vec3 lightDir = vec3(sin(phaseAngle), 0.0, cos(phaseAngle));
    float ndotl = dot(n3d, lightDir);
    float illumination = mix(0.015, 1.0, smoothstep(-0.06, 0.08, ndotl));
    return diskEdge * illumination;
}

float getMoonPhaseBrightness(int phase) {
    float phaseAngle = float(phase) * 0.78539816;
    float cosHalf = cos(phaseAngle * 0.5);
    return max(0.05, cosHalf * cosHalf);
}

vec3 renderMoon(vec3 viewDir, vec3 moonDir, int phase, vec3 moonExtinction) {
    vec3 helper = abs(moonDir.y) > 0.95 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
    vec3 moonT = normalize(cross(moonDir, helper));
    vec3 moonB = normalize(cross(moonDir, moonT));
    vec2 moonCoord = vec2(dot(viewDir, moonT), dot(viewDir, moonB));
    float moonR = 0.028;
    #ifdef NEW_SKY
    moonR = 0.00450; // Physical angular radius
    #endif
    vec2 normCoord = moonCoord / moonR;
    float moonMask = getMoonIllumination(normCoord, phase);
    float cosAngle = dot(viewDir, moonDir);
    float angle = acos(clamp(cosAngle, -1.0, 1.0));
    float disk = smoothstep(moonR * 1.06, moonR * 0.94, angle);
    float illumination = moonMask;
    float earthshine = disk * (1.0 - illumination) * 0.035;
    float halo = pow(max(0.0, cosAngle), 260.0) * 0.45;
    vec3 moonBase = vec3(0.88, 0.85, 0.78);
    vec3 moonColor = moonBase * moonExtinction;
    return moonColor * (illumination * disk * 3.8 + earthshine + halo);
}

// ==============================================================================
// METEORS (common to both skies)
// ==============================================================================
vec2 greatCircleDistance(vec3 viewDir, vec3 pA, vec3 pB) {
    vec3 N = cross(pA, pB);
    float Nlen = length(N);
    if (Nlen < 1e-6) return vec2(-1.0);
    N /= Nlen;
    float across = asin(clamp(dot(viewDir, N), -1.0, 1.0));
    vec3 projDir = viewDir - N * dot(viewDir, N);
    float projLen = length(projDir);
    if (projLen < 1e-6) return vec2(-1.0);
    vec3 proj = projDir / projLen;
    float chordA = clamp(dot(proj, pA), -1.0, 1.0);
    float along = acos(chordA);
    vec3 tangentAB = normalize(pB - pA * dot(pB, pA));
    if (dot(proj, tangentAB) < 0.0) along = -along;
    return vec2(along, abs(across));
}

vec4 sampleMeteor3D(vec3 viewDir, float eventHash, float slotPhaseFrac,
                    float cycle, float t, vec3 radiantDir) {
    float r1 = hash(vec2(eventHash * 37.13, 7.0));
    float r2 = hash(vec2(eventHash * 91.31, 13.0));
    float r3 = hash(vec2(eventHash * 17.97, 23.0));
    float r4 = hash(vec2(eventHash * 53.71, 31.0));
    float r5 = hash(vec2(eventHash * 23.19, 41.0));
    float r6 = hash(vec2(eventHash * 71.93, 59.0));
    float r7 = hash(vec2(eventHash * 41.27, 113.0));
    float r8 = hash(vec2(eventHash * 13.71, 211.0));
    float startAz = r6 * 6.2831853;
    float cosElev = r7;
    float sinElev = sqrt(max(0.0, 1.0 - cosElev * cosElev));
    vec3 startDir = normalize(vec3(cos(startAz) * sinElev, cosElev, sin(startAz) * sinElev));
    if (r8 < 0.18) {
        float pull = 0.55 + r8 * 1.0;
        startDir = normalize(mix(startDir, normalize(radiantDir), pull));
    }
    vec3 rAxis = startDir;
    vec3 helper = abs(rAxis.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 rT = normalize(cross(rAxis, helper));
    vec3 rB = normalize(cross(rAxis, rT));
    float throwAngle = radians(mix(8.0, 55.0, r1));
    float azimuth = r2 * 6.2831853;
    vec3 perp = normalize(cos(azimuth) * rT + sin(azimuth) * rB);
    vec3 dirTail = rAxis;
    vec3 dirHeadMax = normalize(cos(throwAngle) * rAxis + sin(throwAngle) * perp);
    float duration = mix(0.5, 2.0, r3);
    float magnitude = pow(mix(0.35, 1.0, r4), 1.6);
    float localT = mod(t + slotPhaseFrac * cycle, cycle);
    bool isTrain = false;
    float trainFade = 0.0;
    if (localT > duration) {
        if (magnitude < 0.75) return vec4(0.0);
        float trainAge = localT - duration;
        if (trainAge > 6.0) return vec4(0.0);
        trainFade = exp(-trainAge * 0.35) * (magnitude - 0.75) / 0.25;
        isTrain = true;
    }
    float u = isTrain ? 1.0 : (localT / duration);
    float ablation = isTrain ? 0.0 : max(0.0, u * (1.0 - u) * 4.0);
    ablation = pow(ablation, 0.85);
    if (!isTrain && magnitude > 0.7) {
        ablation += smoothstep(0.78, 0.95, u) * (1.0 - smoothstep(0.95, 1.0, u)) * (magnitude - 0.7) * 4.0;
    }
    float cosT = clamp(dot(dirTail, dirHeadMax), -1.0, 1.0);
    float theta = acos(cosT);
    if (theta < 1e-4) return vec4(0.0);
    float sinT = sin(theta);
    vec3 dirHead = normalize((sin((1.0 - u) * theta) * dirTail + sin(u * theta) * dirHeadMax) / sinT);
    if (dirHead.y < -0.02) return vec4(0.0);
    vec2 gc = greatCircleDistance(viewDir, dirTail, dirHead);
    float along = gc.x, across = gc.y;
    float arcLen = acos(clamp(dot(dirTail, dirHead), -1.0, 1.0));
    if (arcLen < 1e-5 || along < -0.001 || along > arcLen + 0.001) return vec4(0.0);
    float trailHW = 0.00065, headHW = 0.0020;
    float trail = exp(-pow(across / trailHW, 2.0)) * pow(along / arcLen, 0.55) * ablation;
    float head = exp(-pow(acos(clamp(dot(viewDir, dirHead), -1.0, 1.0)) / headHW, 2.0)) * ablation * 3.5;
    float intensity = (trail + head) * magnitude;
    float trainSample = 0.0;
    if (isTrain) {
        trainSample = exp(-pow(across / (trailHW * 1.6), 2.0)) * mix(0.35, 1.0, along / arcLen) * trainFade;
    }
    return vec4(intensity, mix(3500.0, 5500.0, r5) / 10000.0, trainSample, 0.0);
}

vec3 renderShootingStars(vec3 worldDir, float dayFactor, float rainAtten, float moonBrightness) {
    if (worldDir.y < 0.02) return vec3(0.0);
    int numSlots = 4; float cycle = 40.0;
    #if SHOOTING_STARS_FREQUENCY == 1
    numSlots = 2; cycle = 40.0;
    #elif SHOOTING_STARS_FREQUENCY == 3
    numSlots = 12; cycle = 36.0;
    #endif
    float radHash = floor(frameTimeCounter / 600.0);
    float radAng = hash(vec2(radHash, 1.0)) * 6.2831853;
    float radElev = mix(0.3, 0.85, hash(vec2(radHash, 2.0)));
    vec3 radiantDir = normalize(vec3(cos(radAng) * sqrt(1.0 - radElev * radElev), radElev, sin(radAng) * sqrt(1.0 - radElev * radElev)));
    float totalIntensity = 0.0; vec3 totalColor = vec3(0.0); float totalTrain = 0.0;
    float invSlots = 1.0 / float(numSlots);
    for (int i = 0; i < 32; ++i) {
        if (i >= numSlots) break;
        vec4 m = sampleMeteor3D(worldDir, float(i) * 0.137 + 0.31, float(i) * invSlots, cycle, frameTimeCounter, radiantDir);
        if (m.x > 0.0001 || m.z > 0.0001) {
            float metAirMass = 1.0 / max(worldDir.y + 0.025, 0.025);
            vec3 metExt = exp(-metAirMass * 0.35 * vec3(0.075, 0.155, 0.375));
            vec3 c = kelvinToRGB(m.y * 10000.0) * metExt;
            totalIntensity += m.x; totalColor += c * m.x; totalTrain += m.z;
        }
    }
    if (totalIntensity < 1e-5 && totalTrain < 1e-5) return vec3(0.0);
    vec3 meteorRGB = totalIntensity > 1e-5 ? totalColor / max(totalIntensity, 1e-5) : vec3(1.0);
    float moonWash = mix(1.0, 0.35, clamp(moonBrightness, 0.0, 1.0));
    float nightFactor = 1.0 - smoothstep(0.05, 0.5, dayFactor);
    float brightMult = 1.0;
    #if SHOOTING_STARS_BRIGHTNESS == 1
    brightMult = 0.6;
    #elif SHOOTING_STARS_BRIGHTNESS == 3
    brightMult = 1.6;
    #endif
    return (meteorRGB * totalIntensity + vec3(0.30, 1.00, 0.55) * totalTrain) * nightFactor * rainAtten * moonWash * brightMult;
}

// ==============================================================================
// MAIN
// ==============================================================================
void main() {
    vec3 dir = normalize(viewPos);
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * dir);

    bool isNether = (dimension == -1) || (isNetherBiome > 0.5)
                  || (glcolor.r > 0.15 && glcolor.g < 0.05 && glcolor.b < 0.05);
    bool isEnd = (dimension == 1) || (isEndBiome > 0.5)
               || (glcolor.r > 0.01 && glcolor.r < 0.08 && glcolor.g < 0.02
                   && glcolor.b > 0.08 && glcolor.b < 0.2);
    bool isOverworld = (dimension == 0) || (!isNether && !isEnd);

    vec3 finalSky;

    if (isOverworld) {
        // =============================================================
        // TIME CALCULATIONS (common to both skies)
        // =============================================================
        float time = mod(float(worldTime), 24000.0);
        float dayFactor = 0.0;
        if (time >= 0.0 && time < 12000.0) dayFactor = 1.0;
        else if (time >= 12000.0 && time < 13000.0) dayFactor = 1.0 - (time - 12000.0) / 1000.0;
        else if (time >= 13000.0 && time < 23000.0) dayFactor = 0.0;
        else dayFactor = (time - 23000.0) / 1000.0;

        float sunsetFactor = 0.0;
        if (time >= 11000.0 && time < 13000.0) {
            sunsetFactor = sin(clamp((time - 11000.0) / 2000.0, 0.0, 1.0) * PI);
        } else if (time >= 22500.0 || time < 1500.0) {
            float srTime = time >= 22500.0 ? time - 24000.0 : time;
            sunsetFactor = sin(clamp((srTime + 1500.0) / 3000.0, 0.0, 1.0) * PI);
        }

        vec3 worldL = normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));

        // Sun & moon directions
        vec3 sunWorldDir, moonWorldDir;
        if (time < 12800.0 || time > 23200.0) {
            sunWorldDir = worldL;
            moonWorldDir = -worldL;
        } else {
            moonWorldDir = worldL;
            sunWorldDir = -worldL;
        }

        // =============================================================
        // SKY RENDERING — SWITCHABLE
        // =============================================================
        #ifdef NEW_SKY
        // =========================================================
        // NEW SKY: Physically-Based Atmospheric Scattering (v1.0.8)
        // =========================================================
        if (worldDir.y > -0.08) {
            finalSky = computeAtmosphericScattering(worldDir, sunWorldDir);
        } else {
            float belowH = smoothstep(-0.08, -0.25, worldDir.y);
            vec3 horizonS = computeAtmosphericScattering(normalize(vec3(worldDir.x, -0.02, worldDir.z)), sunWorldDir);
            finalSky = mix(horizonS * 0.3, mix(vec3(0.08, 0.06, 0.04), vec3(0.02, 0.015, 0.01), dayFactor), belowH);
        }

        // Storm darkening + overcast
        float stormD = mix(1.0, 0.35, rainStrength);
        stormD = mix(stormD, 0.12, rainStrength * thunderStrength);
        finalSky *= stormD;
        vec3 overcast = mix(vec3(0.22, 0.24, 0.27), vec3(0.05, 0.055, 0.065), thunderStrength);
        finalSky = mix(finalSky, overcast * (dayFactor * 0.6 + 0.1), rainStrength * 0.72);

        // Sun disk with atmospheric color
        if (sunWorldDir.y > -0.05 && dayFactor > 0.01) {
            vec3 sunTrans = getSunTransmittance(sunWorldDir);
            vec3 sunDiskC = SUN_IRRADIANCE * sunTrans * 0.85;
            sunDiskC = mix(sunDiskC, sunDiskC * vec3(1.2, 0.7, 0.4), sunsetFactor * 0.5);
            finalSky += renderSunDisk(worldDir, sunWorldDir, sunDiskC);
        }

        #else
        // =========================================================
        // LEGACY SKY: Gradient-based from v1.0.7
        // =========================================================
        float gradHeight = clamp(worldDir.y * 0.5 + 0.5, 0.0, 1.0);
        vec3 daySky = mix(vec3(0.42, 0.62, 0.9), vec3(0.12, 0.32, 0.72), gradHeight);
        vec3 nightSky = mix(vec3(0.004, 0.006, 0.012), vec3(0.0005, 0.001, 0.003), gradHeight);
        vec3 sunsetSky = mix(vec3(0.85, 0.42, 0.12), vec3(0.18, 0.08, 0.28), gradHeight);
        vec3 skyColor = mix(nightSky, daySky, dayFactor);
        skyColor = mix(skyColor, sunsetSky, sunsetFactor);

        // Rain/storm sky
        vec3 rainSky = vec3(0.24, 0.26, 0.29);
        vec3 thunderSky = vec3(0.05, 0.055, 0.065);
        vec3 stormSky = mix(rainSky, thunderSky, thunderStrength);
        skyColor = mix(skyColor, stormSky, rainStrength * 0.85);

        vec3 baseSky = skyColor;
        float horizonGlow = pow(clamp(1.0 - abs(worldDir.y), 0.0, 1.0), 4.5);
        float dotLight = dot(worldDir, worldL);
        vec3 glowColor = vec3(0.0);

        if (dayFactor > 0.1) {
            // --- SUN (Kelvin-based, v1.0.7 style) ---
            float sinAlpha = max(0.001, worldL.y);
            float currentK = getSolarKelvin(sinAlpha);
            currentK = mix(currentK, 1850.0, sunsetFactor * 0.88);
            float airMass = getAirmass(sinAlpha);
            vec3 extinction = exp(-airMass * vec3(0.075, 0.155, 0.375));
            extinction = mix(extinction, max(extinction, vec3(0.42)), sunsetFactor * 0.55);
            vec3 sunLightColor = kelvinToRGB(currentK) * extinction;

            float sunGlow = max(0.0, dotLight);
            float sunDisk = smoothstep(0.9994, 0.9996, dotLight);
            float corona = pow(sunGlow, 180.0) * 0.95;
            float halo = pow(sunGlow, 10.0) * 0.25 * dayFactor;
            glowColor = sunLightColor * (sunDisk * 5.0 + corona + halo);

            if (sunsetFactor > 0.01) {
                vec3 lowSunTint = kelvinToRGB(getSolarKelvin(0.02));
                float horizonSunset = pow(max(0.0, 1.0 - abs(worldDir.y)), 6.0) * sunsetFactor;
                baseSky += lowSunTint * horizonSunset * 0.25;
            }
        } else {
            // --- MOON (v1.0.7 style with phase carving) ---
            float dotMoon = dot(worldDir, worldL);
            float moonGlow = max(0.0, dotMoon);
            vec3 moonHelper = abs(worldL.y) > 0.95 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
            vec3 moonTangent = normalize(cross(worldL, moonHelper));
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
        #endif
        // =========================================================
        // END OF SKY SWITCH — common overlays follow
        // =========================================================

        // Atmospheric extinction for night sky elements
        #ifdef NEW_SKY
        float starAirMass = 1.0 / max(worldDir.y + 0.02, 0.02);
        vec3 starExtinction = exp(-starAirMass * 0.18 * vec3(0.075, 0.155, 0.375));
        float moonAirMass = 1.0 / max(moonWorldDir.y + 0.02, 0.02);
        vec3 moonExtinction = exp(-moonAirMass * 0.25 * vec3(0.075, 0.155, 0.375));
        #else
        vec3 starExtinction = vec3(1.0);
        vec3 moonExtinction = vec3(1.0);
        #endif

        // ---- MOON (improved renderer, used in NEW_SKY; legacy uses its own above) ----
        #ifdef NEW_SKY
        if (dayFactor < 0.6 && moonWorldDir.y > 0.01) {
            float moonVis = (1.0 - dayFactor) * smoothstep(0.01, 0.12, moonWorldDir.y);
            float moonBr = getMoonPhaseBrightness(moonPhase);
            finalSky += renderMoon(worldDir, moonWorldDir, moonPhase, moonExtinction) * moonVis * moonBr * 0.55;
        }
        #endif

        // ---- AIRGLOW + ZODIACAL + TWILIGHT (NEW_SKY only) ----
        #ifdef NEW_SKY
        finalSky += computeAirglow(worldDir, dayFactor);
        finalSky += computeZodiacalLight(worldDir, sunWorldDir, dayFactor);
        finalSky += computeTwilightPhenomena(worldDir, sunWorldDir, dayFactor, sunsetFactor);
        #endif

        // ---- STARS ----
        if (dayFactor < 0.9) {
            float amountMult = 220.0;
            #if STARS_AMOUNT == 1
            amountMult = 140.0;
            #elif STARS_AMOUNT == 3
            amountMult = 320.0;
            #endif
            vec3 starGrid = floor(normalize(worldDir) * amountMult);
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
            finalSky += kelvinToRGB(starTemp) * starGlow * twinkle
                       * smoothstep(-0.02, 0.15, worldDir.y)
                       * (1.0 - dayFactor) * (1.0 - rainStrength) * brightMult * starExtinction;
        }

        // ---- METEORS ----
        #ifdef SHOOTING_STARS
        if (dayFactor < 0.9) {
            float rainAtten = 1.0 - rainStrength * 0.95;
            float moonAngle = float(moonPhase) * 0.78539816;
            float moonBr = pow(max(0.0, cos(moonAngle * 0.5)), 2.0);
            moonBr *= smoothstep(-0.1, 0.2, moonWorldDir.y) * (1.0 - dayFactor);
            finalSky += renderShootingStars(worldDir, dayFactor, rainAtten, moonBr);
        }
        #endif

        // ---- MILKY WAY ----
        if (dayFactor < 0.9) {
            float galacticPlane = dot(worldDir, normalize(vec3(1.0, 1.2, -0.8)));
            float milkyWay = 1.0 - smoothstep(0.0, 0.28, abs(galacticPlane));
            float nebNoise = fbm(worldDir.xz * 1.8 + vec2(frameTimeCounter * 0.003));
            float nebBright = 1.0;
            #if NEBULA_BRIGHTNESS == 1
            nebBright = 0.45;
            #elif NEBULA_BRIGHTNESS == 3
            nebBright = 1.95;
            #endif
            vec3 nebulaColor = mix(vec3(0.004, 0.002, 0.008), vec3(0.08, 0.048, 0.022), milkyWay * 0.7)
                             * smoothstep(0.35, 0.75, nebNoise);
            vec3 starGridDust = floor(worldDir * 280.0);
            float dustNoise = hash3D(starGridDust);
            float starDust = smoothstep(0.995, 1.0, dustNoise) * smoothstep(0.4, 0.7, nebNoise) * milkyWay;
            finalSky += (nebulaColor + vec3(0.95, 0.92, 0.82) * starDust * 0.4)
                       * (1.0 - dayFactor) * (1.0 - rainStrength) * nebBright * starExtinction;
        }

        // ---- AURORA BOREALIS ----
        #if AURORA_MODE != 0
        if (worldDir.y > 0.02) {
            float speedFactor = 1.0;
            #if AURORA_SPEED == 1
            speedFactor = 0.5;
            #elif AURORA_SPEED == 3
            speedFactor = 1.5;
            #endif
            float auroraTime = frameTimeCounter * 0.025 * speedFactor;
            float northFactor = smoothstep(-0.4, 0.8, -worldDir.z);
            northFactor = max(northFactor, 0.2 * smoothstep(0.15, 0.85, worldDir.y));
            float auroraBiomeMask = 1.0;
            #if AURORA_MODE == 1
            auroraBiomeMask = max(clamp(auroraColdBiome, 0.0, 1.0),
                smoothstep(0.08, 0.24, glcolor.b - glcolor.r) * smoothstep(0.25, 0.65, glcolor.b));
            #endif
            float nightFactor = 1.0 - smoothstep(0.02, 0.82, dayFactor);
            float strength = 1.0;
            #if AURORA_STRENGTH == 1
            strength = 0.5;
            #elif AURORA_STRENGTH == 3
            strength = 2.0;
            #endif
            float visibility = northFactor * nightFactor * (1.0 - rainStrength * 0.85) * auroraBiomeMask;
            if (visibility > 0.001) {
                float hMin = 40.0, hMax = 120.0;
                float dirY = max(worldDir.y, 0.04);
                float tMin = hMin / dirY, tMax = hMax / dirY;
                const int steps = 12;
                float dtA = (tMax - tMin) / float(steps);
                float smoothOff = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
                float rayT = tMin + dtA * (smoothOff * 0.6 + 0.5);
                float spatialColOff = sin(worldDir.x * 2.2 + worldDir.z * 1.7) * 0.18;
                vec3 auroraAccum = vec3(0.0);
                for (int i = 0; i < steps; ++i) {
                    vec3 p = worldDir * rayT;
                    float h = clamp((p.y - hMin) / (hMax - hMin), 0.0, 1.0);
                    vec2 uv = p.xz * 0.004; uv.x += auroraTime;
                    float warp = sin(uv.x * 3.2 + auroraTime * 1.2) * 1.4 + cos(uv.y * 2.8 - auroraTime * 0.8) * 1.1;
                    float c1 = 1.0 - abs(sin(uv.x * 2.0 + warp));
                    float c2 = 1.0 - abs(sin(uv.x * 2.8 - warp * 0.8 + 2.0));
                    float ribbon = pow(max(0.0, c1), 3.5) + pow(max(0.0, c2), 3.5) * 0.45;
                    float rayA = sin(uv.x * 14.0 + warp * 1.6 - auroraTime * 3.2) * 0.5 + 0.5;
                    float rayB = sin(uv.x * 9.0 - warp * 0.7 + auroraTime * 2.1) * 0.5 + 0.5;
                    float density = ribbon * (0.35 + 0.65 * pow(mix(rayA, rayB, 0.5), 1.8) * 1.3);
                    density *= smoothstep(0.0, 0.08, h) * (1.0 - smoothstep(0.2, 1.0, h));
                    if (density > 0.01) {
                        float colorMix = clamp(smoothstep(0.15, 0.7, h) + spatialColOff, 0.0, 1.0);
                        vec3 color = mix(vec3(0.0, 0.55, 0.32), vec3(0.42, 0.08, 0.50), colorMix);
                        color = mix(color, vec3(0.04, 0.08, 0.35), smoothstep(0.7, 1.0, h));
                        auroraAccum += color * density;
                    }
                    rayT += dtA;
                }
                finalSky += auroraAccum * (dtA / (hMax - hMin)) * 0.26 * visibility
                          * smoothstep(0.02, 0.15, worldDir.y) * strength * 0.78;
            }
        }
        #endif

        // ---- RAINBOW / MOONBOW ----
        if (wetness > 0.01 && rainStrength < 0.98) {
            vec3 antiSunDir = -sunWorldDir;
            float dotRB = dot(worldDir, antiSunDir);
            float rbWidth = 0.055;
            float clearing = clamp(wetness * 1.65, 0.0, 1.0) * (1.0 - rainStrength);
            float hMask = smoothstep(0.02, 0.16, worldDir.y) * (1.0 - smoothstep(0.82, 1.0, worldDir.y));
            float rbMult = 1.0;
            #if RAINBOW_STRENGTH == 1
            rbMult = 0.45;
            #elif RAINBOW_STRENGTH == 3
            rbMult = 1.85;
            #endif
            if (dayFactor > 0.35) {
                float rc = 0.745, rc2 = 0.629;
                float rF = smoothstep(rc - rbWidth, rc, dotRB) * (1.0 - smoothstep(rc, rc + rbWidth, dotRB));
                float rF2 = smoothstep(rc2 - rbWidth, rc2, dotRB) * (1.0 - smoothstep(rc2, rc2 + rbWidth, dotRB));
                if (rF > 0.001) {
                    float bp = clamp(1.0 - (dotRB - (rc - rbWidth)) / (2.0 * rbWidth), 0.0, 1.0);
                    vec3 rc3; rc3.r = smoothstep(0.40, 0.70, bp);
                    rc3.g = smoothstep(0.20, 0.50, bp) * (1.0 - smoothstep(0.52, 0.82, bp));
                    rc3.b = 1.0 - smoothstep(0.32, 0.62, bp);
                    finalSky += rc3 * rF * 0.34 * hMask * clearing * rbMult * dayFactor;
                }
                if (rF2 > 0.001) {
                    float bp2 = clamp((dotRB - (rc2 - rbWidth)) / (2.0 * rbWidth), 0.0, 1.0);
                    vec3 rc4; rc4.r = smoothstep(0.40, 0.70, bp2);
                    rc4.g = smoothstep(0.20, 0.50, bp2) * (1.0 - smoothstep(0.52, 0.82, bp2));
                    rc4.b = 1.0 - smoothstep(0.32, 0.62, bp2);
                    finalSky += rc4 * rF2 * 0.105 * hMask * clearing * rbMult * dayFactor;
                }
            } else {
                float mF = smoothstep(0.69, 0.745, dotRB) * (1.0 - smoothstep(0.745, 0.80, dotRB));
                if (mF > 0.001) {
                    finalSky += vec3(0.45, 0.58, 0.80) * 0.18 * mF * 0.24 * hMask * clearing * (1.0 - dayFactor) * rbMult;
                }
            }
        }

    } else if (isNether) {
        finalSky = vec3(0.12, 0.02, 0.0);
    } else if (isEnd) {
        float gradH = clamp(worldDir.y * 0.5 + 0.5, 0.0, 1.0);
        vec3 spaceGrad = mix(vec3(0.008, 0.0, 0.018), vec3(0.028, 0.008, 0.055), gradH);
        vec3 starGrid = floor(worldDir * 180.0);
        float starNoise = hash3D(starGrid);
        float starGlow = smoothstep(0.993, 1.0, starNoise);
        float twinkle = sin(frameTimeCounter * 3.5 + starNoise * 80.0) * 0.35 + 0.65;
        vec3 stars = vec3(0.92, 0.88, 1.0) * starGlow * twinkle * smoothstep(-0.15, 0.15, worldDir.y);
        float nebNoise = fbm(worldDir.xz * 2.8 + vec2(frameTimeCounter * 0.006));
        vec3 nebula = vec3(0.12, 0.015, 0.18) * smoothstep(0.35, 0.72, nebNoise);
        finalSky = spaceGrad + stars + nebula;
        #ifdef SHOOTING_STARS
        finalSky += renderShootingStars(worldDir, 0.0, 1.0, 0.0);
        #endif
    }

    colortex0 = vec4(finalSky, glcolor.a);
}

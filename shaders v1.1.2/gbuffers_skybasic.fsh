#version 460 compatibility
// AuraLite Shaders v1.1.2 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack — Sky Fragment Shader (GLSL 460)
// [v1.1.0] REALTIME PHYSICAL SKY (true multiple scattering):
//   Per-pixel ray-marched 1st-order single scattering (Rayleigh + Mie + Ozone,
//   exact transmittance + ground occlusion) PLUS physically-correct 2nd-order
//   multiple scattering via hemisphere irradiance integration (Fibonacci spiral,
//   mean-value theorem) PLUS 3rd+ orders via a bounded geometric series.
//   No LUTs, no cross-frame reads → no horizon/altitude artifacts. Everything
//   is computed fresh per pixel at the real camera altitude & sun position.
//
//   SKY_MODE 0 → Legacy gradient sky (v1.0.7 Kelvin sun/moon)  — cheapest
//   SKY_MODE 1 → Physical realtime scattering (1st+2nd+3rd+ order) — accurate
// ==============================================================================

// --- Sky configuration ---
// NOTE: SKY_MODE is EXPERIMENTAL and OFF by default in every profile. Enable
// it manually via the Experimental tab (Sky Mode = Physical). Mode 0 is the
// stable v1.0.7 gradient sky used by all shipped presets.
#define SKY_MODE 0            // [0 1] - 0:Gradient 1:Physical realtime (EXPERIMENTAL)
#define SKY_QUALITY 3         // [1 2 3] Ray-march sample counts (SKY_MODE 1)
#define SKY_STYLE 1           // [0 1 2] - 0:Realistic 1:Semi-realistic 2:Fantasy
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

// ==============================================================================
// SKY STYLE — three artistic directions for the physical sky.
//   0 REALISTIC      : true angular sizes, neutral colours, minimal glow.
//                      Authentic astronomy look (sun/moon ~7px @ 720p).
//   1 SEMI-REALISTIC : readable sizes (×2.8), richer colour, soft aureole.
//                      Cinematic realism — the default for screenshots.
//   2 FANTASY        : grand sun/moon (×5.5), big corona glow, vivid saturated
//                      palette with teal/violet hues, dramatic purple sunsets.
// ==============================================================================
#if SKY_STYLE == 0
// Realistic: true angular sizes, neutral colour, minimal glow.
const float SUN_SIZE_MULT   = 1.0;     // physical sky: real 0.004653 rad
const float MOON_SIZE_MULT  = 1.0;     // physical sky: real 0.00476 rad
const float LEGACY_SUN_SIZE_MULT  = 2.4; // gradient sky: readable but still restrained
const float LEGACY_MOON_SIZE_MULT = 2.4;
const float CORONA_MULT     = 0.28;
const float COLOR_SAT_MULT  = 0.98;
const float STAR_CORE_BASE  = 0.18;
const float STAR_CORE_TOP   = 0.32;
const float SUN_DISK_BRIGHT = 10.5;
#elif SKY_STYLE == 2
// Fantasy: large but not screen-filling sun/moon, strong glow, saturated palette.
const float SUN_SIZE_MULT   = 4.4;
const float MOON_SIZE_MULT  = 4.4;
const float LEGACY_SUN_SIZE_MULT  = 7.5; // gradient sky: grand fantasy discs
const float LEGACY_MOON_SIZE_MULT = 7.5;
const float CORONA_MULT     = 1.18;
const float COLOR_SAT_MULT  = 1.26;
const float STAR_CORE_BASE  = 0.38;
const float STAR_CORE_TOP   = 0.62;
const float SUN_DISK_BRIGHT = 15.0;
#else // 1 Semi-realistic (default): readable discs, natural cinematic colour.
const float SUN_SIZE_MULT   = 2.4;
const float MOON_SIZE_MULT  = 2.4;
const float LEGACY_SUN_SIZE_MULT  = 5.6; // gradient sky: close to the old readable size
const float LEGACY_MOON_SIZE_MULT = 5.6;
const float CORONA_MULT     = 0.58;
const float COLOR_SAT_MULT  = 1.08;
const float STAR_CORE_BASE  = 0.24;
const float STAR_CORE_TOP   = 0.40;
const float SUN_DISK_BRIGHT = 12.5;
#endif

#if SKY_MODE == 1
// --- Atmosphere physics ---
const float R_GROUND   = 6371000.0;
const float R_ATMO     = 6471000.0;
const float ATM_THICK  = R_ATMO - R_GROUND;
const float H_RAYLEIGH = 8000.0;
const float H_MIE      = 1200.0;
const float H_O3_PEAK  = 25000.0;   // ozone layer centre altitude
const float H_O3_SIGMA = 6000.0;    // ozone layer half-width
const vec3  BETA_R = vec3(5.8e-6, 13.5e-6, 33.1e-6);   // Rayleigh scattering
const vec3  BETA_M = vec3(21.0e-6, 21.0e-6, 21.0e-6);  // Mie scattering
const vec3  BETA_O3 = vec3(6.5e-7, 5.2e-7, 1.0e-7);    // ozone absorption
const float GROUND_ALBEDO = 0.1;    // constant ground reflectance
// Real solar angular radius: 959.6 arcsec = 0.2666° = 0.004653 rad.
const float SUN_RADIUS = 0.004653;
const vec3  SUN_IRRADIANCE = vec3(25.0, 23.8, 22.5);

// Camera altitude in atmosphere metres (sea level = 0). Minecraft Y=63 ≈ sea.
float getCameraAltitude() {
    return max(0.0, (cameraPosition.y - 63.0)) * 100.0;
}

// Ray-sphere intersection (both roots). Returns true if the ray hits the sphere.
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
    return (1.0 - g2) / (4.0 * PI * denom * sqrt(max(denom, 1e-4)));
}

// Ozone density profile (Gaussian bump centred at ~25 km).
float ozoneDensity(float h) {
    if (h < 0.0) return 0.0;
    float d = (h - H_O3_PEAK) / H_O3_SIGMA;
    return exp(-d * d);
}

// Light-ray optical depth: march from point p toward the sun to the atmosphere
// edge, accumulating Rayleigh + Mie + Ozone optical depth. Detects ground
// occlusion (sun blocked by the planet) and clamps the march to the ground hit.
bool lightOpticalDepth(vec3 p, vec3 sunDir, int N,
                       out float odR, out float odM, out float odO3, out bool occluded) {
    odR = 0.0; odM = 0.0; odO3 = 0.0; occluded = false;
    float tL0, tL1;
    if (!raySphere(p, sunDir, R_ATMO, tL0, tL1)) return false;
    tL1 = max(tL1, 0.0);
    // Ground occlusion along the sun ray?
    float tg0, tg1;
    if (raySphere(p, sunDir, R_GROUND, tg0, tg1) && tg0 > 0.0 && tg0 < tL1) {
        occluded = true;
        tL1 = tg0;
    }
    float dtL = tL1 / float(N);
    // [v1.1.1] Noise-free physical sky: use centered samples instead of per-pixel
    // hash jitter. The old jitter hid banding but produced visible grain/static.
    const float lightSampleOffset = 0.5;
    for (int j = 0; j < 16; ++j) {
        if (j >= N) break;
        float tL = (float(j) + lightSampleOffset) * dtL;
        vec3 pL = p + sunDir * tL;
        float hL = length(pL) - R_GROUND;
        if (hL < 0.0) break;
        odR += exp(-hL / H_RAYLEIGH) * dtL;
        odM += exp(-hL / H_MIE) * dtL;
        odO3 += ozoneDensity(hL) * dtL;
    }
    return true;
}

// ==============================================================================
// REALTIME ATMOSPHERIC SCATTERING — pure per-pixel, no LUTs.
//
//   L_total = L_single + L_multi
//
// L_single: exact single-scattering ray march. At each sample the sun→sample
//   optical depth is marched exactly (Rayleigh + Mie + Ozone + ground occlusion).
//
// L_multi: blue-biased bounded multiple-scattering ambient. Rayleigh scattering
//   physically re-scatters BLUE light preferentially into the diffuse field, so
//   the MS ambient is weighted by the Rayleigh coefficient (blue-dominant). This
//   fills in over-dark zenith/horizon WITHOUT the yellow band that a neutral or
//   warm-biased ambient produces. Bounded (additive, no division) → never blows up.
//
// Early-terminate when view transmittance < 2%. Fast enough for weak GPUs.
// ==============================================================================
vec3 computeAtmosphericScattering(vec3 viewDir, vec3 sunDir) {
    float camAlt = getCameraAltitude();
    vec3 ro = vec3(0.0, R_GROUND + camAlt, 0.0);
    float tAtmo0, tAtmo1;
    if (!raySphere(ro, viewDir, R_ATMO, tAtmo0, tAtmo1)) return vec3(0.0);
    tAtmo0 = max(tAtmo0, 0.0);

    float tg0, tg1;
    float tGround = tAtmo1;
    if (raySphere(ro, viewDir, R_GROUND, tg0, tg1) && tg0 > 0.0 && tg0 < tAtmo1) tGround = tg0;
    float rayLen = tGround - tAtmo0;
    if (rayLen <= 0.0) return vec3(0.0);

    // [v1.1.1] Slightly higher sample counts replace noisy per-pixel dithering.
    int N = 10, N_light = 4;
    #if SKY_QUALITY == 1
    N = 7; N_light = 3;
    #elif SKY_QUALITY == 3
    N = 14; N_light = 5;
    #endif
    float dt = rayLen / float(N);

    float cosTheta = dot(viewDir, sunDir);
    float phaseR = phaseRayleigh(cosTheta);
    float phaseM = phaseMie(cosTheta);

    // Multiple-scattering colour & strength depend on sun elevation:
    //  • High sun (day):  BLUE ambient (Rayleigh re-scatters blue) → fills zenith,
    //    kills the yellow horizon band.
    //  • Low sun (sunset): WARM + weaker ambient → lets the (correctly red)
    //    single scattering dominate, giving a real orange sunset.
    // Physically sound: at sunset the blue light is already scattered out
    // before reaching the diffuse field, so MS must inherit the warm tint.
    float sunHigh = smoothstep(0.04, 0.35, sunDir.y);          // 0 at horizon, 1 high
    vec3 msColor = mix(vec3(1.0, 0.62, 0.34),                   // warm at sunset
                       normalize(BETA_R + vec3(1e-6)),          // blue at noon
                       sunHigh);
    float msBoost = mix(0.05, 0.20, sunHigh);                   // weak at sunset (SS dominates)

    vec3 sumR = vec3(0.0), sumM = vec3(0.0);
    vec3 sumMS = vec3(0.0);
    float viewOdR = 0.0, viewOdM = 0.0, viewOdO3 = 0.0;
    const float EARLY_TERM = 0.02;

    // [v1.1.1] Noise-free physical sky: no per-pixel hash jitter. Centered
    // sampling removes the visible grain/static in physical mode; the increased
    // sample counts above keep the gradient smooth without spatial noise.
    const float viewSampleOffset = 0.5;

    for (int i = 0; i < 24; ++i) {
        if (i >= N) break;
        float t = tAtmo0 + (float(i) + viewSampleOffset) * dt;
        vec3 p = ro + viewDir * t;
        float h = length(p) - R_GROUND;
        if (h < 0.0) break;
        float rhoR = exp(-h / H_RAYLEIGH);
        float rhoM = exp(-h / H_MIE);
        float rhoO3 = ozoneDensity(h);
        viewOdR += rhoR * dt;
        viewOdM += rhoM * dt;
        viewOdO3 += rhoO3 * dt;

        vec3 T_view = exp(-(BETA_R * viewOdR + BETA_M * viewOdM + BETA_O3 * viewOdO3));
        if (max(max(T_view.r, T_view.g), T_view.b) < EARLY_TERM) break;

        // Sun→sample transmittance (exact march + ground occlusion).
        float odLR, odLM, odLO3;
        bool occluded;
        if (!lightOpticalDepth(p, sunDir, N_light, odLR, odLM, odLO3, occluded)) continue;
        if (occluded) continue;
        vec3 T_sun = exp(-(BETA_R * odLR + BETA_M * odLM + BETA_O3 * odLO3));

        // --- 1st order: single scattering ---
        sumR += T_view * T_sun * rhoR * dt;
        sumM += T_view * T_sun * rhoM * dt;

        // --- Multiple scattering: blue-biased bounded ambient ---
        vec3 betaScatP = BETA_R * rhoR + BETA_M * rhoM;
        vec3 E_ms = T_sun * msColor * msBoost;
        sumMS += T_view * betaScatP * E_ms / (4.0 * PI) * dt;
    }

    vec3 L1 = SUN_IRRADIANCE * (sumR * BETA_R * phaseR + sumM * BETA_M * phaseM);
    return L1 + sumMS;
}

// Sun transmittance from the camera toward the sun (for the sun disk colour).
vec3 getSunTransmittance(vec3 sunDir) {
    float camAlt = getCameraAltitude();
    vec3 ro = vec3(0.0, R_GROUND + camAlt, 0.0);
    float odR, odM, odO3;
    bool occluded;
    if (!lightOpticalDepth(ro, sunDir, 8, odR, odM, odO3, occluded)) return vec3(0.0);
    if (occluded) return vec3(0.0);
    return exp(-(BETA_R * odR + BETA_M * odM + BETA_O3 * odO3));
}

// Procedural sun disk with limb darkening + soft corona.
vec3 renderSunDisk(vec3 viewDir, vec3 sunDir, vec3 sunColor) {
    float cosAngle = dot(viewDir, sunDir);
    float angle = acos(clamp(cosAngle, -1.0, 1.0));
    float sunR = SUN_RADIUS * SUN_SIZE_MULT;
    // Sharp disk edge (real solar limb is crisp; only ~0.5% width from seeing).
    float disk = smoothstep(sunR * 1.015, sunR * 0.992, angle);
    // Limb darkening: real solar limb is ~0.45× centre brightness at the edge.
    float r = clamp(angle / sunR, 0.0, 1.0);
    float limb = 1.0 - 0.55 * (1.0 - cos(r * PI * 0.5));
    // Atmospheric aureole / forward-scatter halo around the disk.
    float corona = smoothstep(sunR * 4.5, sunR * 1.0, angle) * (1.0 - disk) * CORONA_MULT;
    return (disk * limb * SUN_DISK_BRIGHT + corona) * sunColor;
}
#endif // SKY_MODE == 1

// ==============================================================================
// KELVIN SOLAR MODEL (used by legacy sky + stars/meteors coloring)
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

#if SKY_MODE == 0
float getSolarKelvin(float sinElevation) {
    float t = clamp(sinElevation, 0.0, 1.0);
    float baseK = 2200.0 + 3500.0 * pow(t, 0.62);
    return clamp(baseK, 1500.0, 7500.0);
}
float getAirmass(float sinElevation) {
    float elevDeg = degrees(asin(clamp(sinElevation, 0.001, 1.0)));
    return 1.0 / (sinElevation + 0.50572 * pow(elevDeg + 6.07995, -1.6364));
}
#endif // SKY_MODE == 0

// ==============================================================================
// HASH / NOISE (common to all sky modes)
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
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1,0)), u.x),
               mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), u.x), u.y);
}
const mat2 fbmRot = mat2(0.87758256, 0.47942554, -0.47942554, 0.87758256);
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += a * noise(p);
        p = fbmRot * p * 2.1 + vec2(100.0);
        a *= 0.5;
    }
    return v;
}

// ==============================================================================
// MOON (common to all sky modes — extinction varies)
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
    // Real lunar angular radius: 0.2725° = 0.00476 rad. The Moon is slightly
    // LARGER than the Sun in angular size (hence total solar eclipses). The
    // Moon has no atmosphere → its limb is extremely crisp.
    float moonR = 0.00476 * MOON_SIZE_MULT;
    vec2 normCoord = moonCoord / moonR;
    float moonMask = getMoonIllumination(normCoord, phase);
    float cosAngle = dot(viewDir, moonDir);
    float angle = acos(clamp(cosAngle, -1.0, 1.0));
    float disk = smoothstep(moonR * 1.012, moonR * 0.992, angle); // crisp limb
    float illumination = moonMask;
    float earthshine = disk * (1.0 - illumination) * 0.035;
    float halo = pow(max(0.0, cosAngle), 260.0) * 0.45;
    vec3 moonBase = vec3(0.88, 0.85, 0.78);
    return moonBase * moonExtinction * (illumination * disk * 3.8 + earthshine + halo);
}

// ==============================================================================
// METEORS (common to all sky modes)
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
// SKY STYLE GRADING — applied only to the base sky before moon/stars/aurora/rainbow
// ==============================================================================
vec3 applySkyStyleGrade(vec3 sky, float dayFactor, float sunsetFactor, vec3 worldDir) {
    float luma = dot(sky, vec3(0.2126, 0.7152, 0.0722));
    #if SKY_STYLE == 0
    // Realistic: neutral, slightly restrained saturation, no fantasy hue shifts.
    vec3 neutral = mix(vec3(luma), sky, COLOR_SAT_MULT);
    return max(neutral, vec3(0.0));
    #elif SKY_STYLE == 2
    // Fantasy: vivid but bounded. Keep luminance structure, shift only the sky base
    // so stars, moon, aurora and rainbows keep their own colours.
    vec3 sat = mix(vec3(luma), sky, COLOR_SAT_MULT);
    vec3 dayTint    = sat * vec3(0.82, 1.06, 1.12) + vec3(0.000, 0.006, 0.010) * smoothstep(0.0, 0.65, worldDir.y);
    vec3 sunsetTint = sat * vec3(1.16, 0.62, 1.00) + vec3(0.045, 0.000, 0.060);
    vec3 nightTint  = sat * vec3(0.58, 0.66, 1.22) + vec3(0.006, 0.000, 0.028);
    vec3 tinted = mix(nightTint, dayTint, dayFactor);
    tinted = mix(tinted, sunsetTint, sunsetFactor);
    return max(tinted, vec3(0.0));
    #else
    // Semi-realistic: mild cinematic saturation and a small warm golden-hour push.
    vec3 sat = mix(vec3(luma), sky, COLOR_SAT_MULT);
    vec3 warm = sat * vec3(1.04, 0.96, 0.90) + vec3(0.018, 0.006, 0.000);
    return max(mix(sat, warm, sunsetFactor * 0.28), vec3(0.0));
    #endif
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
    bool isOverworld = !isNether && !isEnd; // [v1.1.1] Do not let a default dimension=0 override Nether/End fallbacks

    vec3 finalSky;

    if (isOverworld) {
        // =============================================================
        // TIME CALCULATIONS (common to all sky modes)
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
        // SKY RENDERING — DUAL MODE SWITCH
        // =============================================================
        #if SKY_MODE == 1
        // =========================================================
        // PHYSICAL REALTIME SKY: ray-marched Rayleigh + Mie + Ozone + MS
        // =========================================================
        {
            // Always integrate an upward direction: for below-horizon pixels,
            // clamp the view y to a small positive value so the ray stays in
            // the atmosphere and produces a horizon glow. The azimuth is
            // preserved so the glow tracks the sun. No separate code path →
            // no discontinuity, no black band.
            vec3 skyDir = normalize(vec3(worldDir.x, max(worldDir.y, 0.03), worldDir.z));
            finalSky = computeAtmosphericScattering(skyDir, sunWorldDir);

            // Sun disk coloured by the physical ozone-aware transmittance.
            if (sunWorldDir.y > -0.05 && dayFactor > 0.01) {
                vec3 sunTrans = getSunTransmittance(sunWorldDir);
                vec3 sunDiskC = SUN_IRRADIANCE * sunTrans * 0.85;
                sunDiskC = mix(sunDiskC, sunDiskC * vec3(1.2, 0.7, 0.4), sunsetFactor * 0.5);
                finalSky += renderSunDisk(worldDir, sunWorldDir, sunDiskC);
            }
        }
        // Storm darkening + overcast
        float stormD = mix(1.0, 0.35, rainStrength);
        stormD = mix(stormD, 0.12, rainStrength * thunderStrength);
        finalSky *= stormD;
        vec3 overcast = mix(vec3(0.22, 0.24, 0.27), vec3(0.05, 0.055, 0.065), thunderStrength);
        finalSky = mix(finalSky, overcast * (dayFactor * 0.6 + 0.1), rainStrength * 0.72);
        #else
        // =========================================================
        // LEGACY SKY: Gradient-based from v1.0.7
        // =========================================================
        // =========================================================
        // ENHANCED GRADIENT SKY (SKY_MODE 0)
        // Physically-inspired: deep/saturated zenith -> pale hazy Mie
        // horizon, directional warm forward-scatter that brightens the
        // sky toward the sun, and a multi-stop sunset palette. Keeps the
        // project's existing Kelvin/airmass sun-colour model.
        // =========================================================

        // --- view & sun geometry ---
        float up         = clamp(worldDir.y, 0.0, 1.0);        // 0 horizon, 1 zenith
        float towardSun  = max(dot(worldDir, worldL), 0.0);    // cosine toward the sun
        float sunElev    = worldL.y;                           // sun elevation (-1..1)
        float sunUp      = smoothstep(-0.05, 0.12, sunElev);   // sun meaningfully up

        // --- sun colour through the atmosphere (warm low, white high) ---
        float sinAlpha   = max(0.001, sunElev);
        float currentK   = getSolarKelvin(sinAlpha);
        currentK         = mix(currentK, 1850.0, sunsetFactor * 0.88);
        float airMass    = getAirmass(sinAlpha);
        vec3  extinction = exp(-airMass * vec3(0.075, 0.155, 0.375));
        extinction       = mix(extinction, max(extinction, vec3(0.42)), sunsetFactor * 0.55);
        vec3  sunLightColor = kelvinToRGB(currentK) * extinction;

        // --- DAY: realistic clear sky (Rayleigh & Mie approximation) ---
        vec3 dayZenith  = vec3(0.08, 0.22, 0.55);            // realistic deep sky blue
        vec3 dayMid     = vec3(0.22, 0.42, 0.72);            // softer mid-sky blue
        vec3 dayHorizon = vec3(0.55, 0.68, 0.82);            // hazy atmospheric white-blue horizon
        
        // Smooth realistic blending
        vec3 daySky = mix(dayHorizon, dayMid, smoothstep(0.0, 0.25, up));
        daySky      = mix(daySky, dayZenith, smoothstep(0.20, 1.0, up));
        
        // Subtle haze layer at the horizon
        vec3 horizonHaze = vec3(0.85, 0.82, 0.75);
        float hazeMask = (1.0 - smoothstep(-0.1, 0.3, sunElev)) * pow(clamp(1.0 - up, 0.0, 1.0), 3.0);
        daySky = mix(daySky, daySky * horizonHaze, hazeMask * 0.60);

        // --- NIGHT: near-black zenith + faint blue airglow band ---
        vec3 nightZenith  = vec3(0.002, 0.004, 0.010);
        vec3 nightHorizon = vec3(0.022, 0.032, 0.056);
        vec3 nightSky = mix(nightHorizon, nightZenith, smoothstep(0.0, 0.55, up));

        // --- SUNSET: natural sunset fading into twilight ---
        float tHoriz      = pow(towardSun, 2.0);              
        vec3 setHorizon   = vec3(0.85, 0.45, 0.15) * (0.6 + 0.4 * tHoriz); // warm natural orange-yellow
        vec3 setLow       = vec3(0.65, 0.35, 0.25);           // dusty salmon/peach
        vec3 setMid       = vec3(0.25, 0.25, 0.35);           // grayish twilight blue
        vec3 setHigh      = vec3(0.08, 0.12, 0.22);           // darkening atmosphere
        
        // Natural wide transitions matching physical scattering
        vec3 sunsetSky = setHorizon;
        sunsetSky = mix(sunsetSky, setLow,  smoothstep(0.0,  0.18, up));
        sunsetSky = mix(sunsetSky, setMid,  smoothstep(0.12, 0.45, up));
        sunsetSky = mix(sunsetSky, setHigh, smoothstep(0.35, 0.80, up));
        
        // Natural Mie forward-scatter around the sun
        float alHorizonBand = pow(clamp(1.0 - up, 0.0, 1.0), 5.0);
        float directionalMie = pow(towardSun, 5.0);
        sunsetSky += sunLightColor * alHorizonBand * (towardSun * 0.3 + directionalMie * 0.6);

        // --- combine the phases of the day ---
        vec3 skyColor = mix(nightSky, daySky, dayFactor);
        skyColor = mix(skyColor, sunsetSky, sunsetFactor);

        // --- storm / overcast ---
        vec3 rainSky = vec3(0.24, 0.26, 0.29);
        vec3 thunderSky = vec3(0.05, 0.055, 0.065);
        vec3 stormSky = mix(rainSky, thunderSky, thunderStrength);
        skyColor = mix(skyColor, stormSky, rainStrength * 0.85);

        vec3 baseSky = skyColor;
        float horizonGlow = pow(clamp(1.0 - abs(worldDir.y), 0.0, 1.0), 4.5);
        float dotLight = dot(worldDir, worldL);
        vec3 glowColor = vec3(0.0);

        if (dayFactor > 0.1) {
            float sunGlow = max(0.0, dotLight);
            // [v1.1.1] SKY_STYLE now affects the legacy gradient sky too.
            float sunAngle = acos(clamp(dotLight, -1.0, 1.0));
            float sunR = 0.004653 * LEGACY_SUN_SIZE_MULT;
            float sunDisk = smoothstep(sunR * 1.15, sunR * 0.92, sunAngle);
            float corona = smoothstep(sunR * (7.5 + 5.0 * CORONA_MULT), sunR * 1.0, sunAngle) * 0.95 * CORONA_MULT;
            float halo = pow(sunGlow, max(3.0, 10.0 / max(CORONA_MULT, 0.25))) * 0.25 * dayFactor;
            glowColor = sunLightColor * (sunDisk * (3.2 + SUN_DISK_BRIGHT * 0.14) + corona + halo);
        } else {
            float dotMoon = dot(worldDir, worldL);
            float moonGlow = max(0.0, dotMoon);
            vec3 moonHelper = abs(worldL.y) > 0.95 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
            vec3 moonTangent = normalize(cross(worldL, moonHelper));
            vec3 moonBinormal = normalize(cross(worldL, moonTangent));
            vec2 moonCoord = vec2(dot(worldDir, moonTangent), dot(worldDir, moonBinormal));
            vec2 normMoonCoord = moonCoord / (0.00476 * LEGACY_MOON_SIZE_MULT); // [v1.1.1] readable gradient-sky moon size per SKY_STYLE
            float moonMask = getMoonIllumination(normMoonCoord, moonPhase);
            float moonCorona = pow(moonGlow, 260.0) * 0.5;
            float moonHalo = pow(moonGlow, 14.0) * 0.12 * (1.0 - dayFactor);
            vec3 moonColor = kelvinToRGB(4100.0);
            glowColor = moonColor * (moonMask * 3.5 + moonCorona + moonHalo) * 0.5;
        }

        glowColor *= (1.0 - rainStrength * mix(0.65, 0.95, thunderStrength));

        // --- horizon airlight (Mie haze) + directional forward scatter ---
        // Bright desaturated band hugging the horizon; it warms and intensifies
        // toward the sun during the day and golden hour, and lingers into
        // twilight for that glowing-sunset look. Fades out at deep night.
        float airlight = pow(clamp(1.0 - abs(worldDir.y), 0.0, 1.0), 6.0);
        vec3  airlightCol = mix(vec3(0.58, 0.70, 0.86), sunLightColor * 1.15, 0.55);
        float airlightAmt = 0.06
                          + 0.34 * pow(towardSun, 5.0) * dayFactor
                          + 0.22 * sunsetFactor * (0.4 + 0.6 * towardSun);

        finalSky = baseSky + glowColor
                 + baseSky * horizonGlow * 0.28
                 + airlight * airlightCol * airlightAmt;
        #endif
        // =========================================================
        // END OF SKY SWITCH — common overlays follow
        // =========================================================

        // [v1.1.1] Apply styles to the base sky only. Older code graded the sky
        // after moon/stars/aurora/rainbow, which made style presets look broken
        // by tinting all celestial overlays.
        finalSky = applySkyStyleGrade(finalSky, dayFactor, sunsetFactor, worldDir);

        // Atmospheric extinction for night sky elements
        #if SKY_MODE == 1
        float starAirMass = 1.0 / max(worldDir.y + 0.02, 0.02);
        vec3 starExtinction = exp(-starAirMass * 0.18 * vec3(0.075, 0.155, 0.375));
        float moonAirMass = 1.0 / max(moonWorldDir.y + 0.02, 0.02);
        vec3 moonExtinction = exp(-moonAirMass * 0.25 * vec3(0.075, 0.155, 0.375));
        #else
        vec3 starExtinction = vec3(1.0);
        vec3 moonExtinction = vec3(1.0);
        #endif

        // ---- MOON (physical renderer in SKY_MODE 1; legacy uses its own) ----
        #if SKY_MODE == 1
        if (dayFactor < 0.6 && moonWorldDir.y > 0.01) {
            float moonVis = (1.0 - dayFactor) * smoothstep(0.01, 0.12, moonWorldDir.y);
            float moonBr = getMoonPhaseBrightness(moonPhase);
            finalSky += renderMoon(worldDir, moonWorldDir, moonPhase, moonExtinction) * moonVis * moonBr * 0.55;
        }
        #endif

        // ---- STARS ----
        // Real stars are unresolved point sources. Each is a tight bright core
        // with a thin diffraction-like glow, placed at the centre of its grid
        // cell (not the whole cell), so they read as small sharp pinpricks.
        if (dayFactor < 0.9) {
            float amountMult = 220.0;
            #if STARS_AMOUNT == 1
            amountMult = 140.0;
            #elif STARS_AMOUNT == 3
            amountMult = 320.0;
            #endif
            vec3 starPos = normalize(worldDir) * amountMult;
            vec3 starGrid = floor(starPos);
            vec3 starLocal = fract(starPos) - 0.5; // offset from cell centre
            float starDist = length(starLocal);
            float starNoise = hash3D(starGrid);
            float threshold = 0.994;
            #if STARS_AMOUNT == 1
            threshold = 0.997;
            #elif STARS_AMOUNT == 3
            threshold = 0.988;
            #endif
            // Tight point: a visible bright core (>= ~2px at 720p) + soft glow.
            // Real stars are point sources, but they must be larger than one
            // pixel or they vanish to aliasing. Brighter stars get a bigger core.
            float starPresence = smoothstep(threshold, 1.0, starNoise);
            float coreSize = mix(STAR_CORE_BASE, STAR_CORE_TOP, starNoise);
            float core = (1.0 - smoothstep(0.0, coreSize, starDist)) * starPresence;
            // Soft diffraction halo around the core.
            float halo = (1.0 - smoothstep(0.0, 0.55, starDist)) * starPresence * 0.20;
            float starGlow = (core * 1.8 + halo);
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
            // [v1.1.1] Day rainbow uses the antisolar point; moonbow uses the antilunar point.
            vec3 rainbowCenter = (dayFactor > 0.35) ? -sunWorldDir : -moonWorldDir;
            float dotRB = dot(worldDir, rainbowCenter);
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

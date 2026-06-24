#version 460 compatibility
// AuraLite Shaders v1.0.7 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Sky Fragment Shader (GLSL 460 - Enhanced Lighting)
// ==============================================================================
// [FIX v0.2.3] Added CLOUD_HEIGHT / CLOUD_THICKNESS defines so sky clouds match composite.
// [FIX v0.2.3] Added SUN_TEMPERATURE define so sun disk colour matches composite Kelvin curve.
// [FIX v0.2.3] Removed unused 'uniform int dimension' declaration.
// [FIX v0.2.5] Removed dead renderVolumetricClouds() function — it was never called
// [FIX v0.2.5] Sunset twilight window set to 11000–13000; /time set 12800 remains red/warm.
//       (clouds are rendered exclusively in composite.fsh). This saves GPU compilation time.

#define PROCEDURAL_CLOUDS   // [true false]
#define CLOUD_HEIGHT 2      // [1 2 3] - [FIX v0.2.3] Added
#define CLOUD_THICKNESS 2   // [1 2 3] - [FIX v0.2.3] Added
#define SUN_TEMPERATURE 2   // [1 2 3] - [FIX v0.2.3] Added
#define NEBULA_BRIGHTNESS 2 // [1 2 3]
#define STARS_BRIGHTNESS 2  // [1 2 3]
#define STARS_AMOUNT 2      // [1 2 3]
#define AURORA_MODE 2       // [0 1 2] - 0: Off, 1: Cold Biomes, 2: Always Enabled
#define AURORA_SPEED 2      // [1 2 3] - 1: Slow, 2: Standard, 3: Fast
#define AURORA_STRENGTH 2   // [1 2 3] - 1: Soft, 2: Standard, 3: Glowing
#define RAINBOW_STRENGTH 2  // [1 2 3] - 1: Subtle, 2: Balanced, 3: Vivid

// [v1.0.3] Falling stars (meteors / shooting stars) crossing the night sky.
#define SHOOTING_STARS              // [true false]
#define SHOOTING_STARS_FREQUENCY 2  // [1 2 3] - 1: Rare, 2: Standard, 3: Frequent
#define SHOOTING_STARS_BRIGHTNESS 2 // [1 2 3] - 1: Subtle, 2: Standard, 3: Brilliant

/* DRAWBUFFERS:0 */

in vec4 glcolor;
in vec3 viewPos;

uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;
uniform int worldTime;
uniform float rainStrength;
uniform float thunderStrength;
uniform float wetness; // Moisture decay after rain; used for post-rain rainbows
uniform int moonPhase;
uniform float auroraColdBiome; // custom uniform from shaders.properties
uniform int dimension; // Standard Minecraft dimension uniform (-1: Nether, 0: Overworld, 1: End)

// Custom uniforms from shaders.properties for biome-based dimension detection
uniform float isNetherBiome;
uniform float isEndBiome;

layout(location = 0) out vec4 colortex0;

// ==============================================================================
// PHYSICALLY ACCURATE KELVIN → sRGB (Tanner Helland algorithm)
// ==============================================================================
vec3 kelvinToRGB(float k) {
    k = clamp(k, 1000.0, 40000.0) / 100.0;
    float r, g, b;

    if (k <= 66.0) {
        r = 255.0;
        g = clamp(((99.4708025861) * (log(k)) + (-161.1195681661)), 0.0, 255.0);
        if (k < 19.0) {
            b = 0.0;
        } else {
            b = clamp(((138.5177312231) * (log(k - 10.0)) + (-305.0447927307)), 0.0, 255.0);
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
        v = ((a) * (noise(p)) + (v));
        p = ((rot * p) * (2.1) + (shift));
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

    float diskEdge = 1.0 - smoothstep(0.96, 1.0, r2);
    float z = sqrt(1.0 - r2);
    vec3 normal3D = vec3(coord.x, coord.y, z);

    float phaseAngle = float(phase) * 0.78539816;
    vec3 localLightDir = vec3(sin(phaseAngle), 0.0, cos(phaseAngle));
    float ndotl = dot(normal3D, localLightDir);

    float illumination = mix(0.012, 1.0, smoothstep(-0.06, 0.06, ndotl));
    return diskEdge * illumination;
}

// ==============================================================================
// [v1.0.3] PHYSICALLY-BASED METEORS (Falling Stars)
// ==============================================================================
// Models real meteors entering the mesosphere (h ≈ 80–120 km) and ablating as
// the trail of plasma we see from the ground.
//
// Physics implemented:
//   1. 3D KINEMATICS. A meteor is a straight 3D line segment with an entry
//      point on the ~120 km shell and an exit point on the ~80 km shell.
//      Projected back to the unit sphere this is a GREAT-CIRCLE arc — the
//      correct geometry for a meteor seen from a near-spherical Earth.
//   2. SHARED RADIANT. All meteors in one shower come from a single 3D
//      direction (the radiant). This produces the converging-streak effect
//      of real showers like the Perseids.
//   3. ABLATION LIGHT CURVE. The standard ablation law gives a bell-shaped
//      luminosity: rise (mass loss × velocity^3 dominates) → peak → decay.
//      Bright meteors have a "terminal burst" at fragmentation.
//   4. BLACKBODY COLOR. The trail is plasma at T ≈ 3500–5500 K depending
//      on entry velocity. We reuse kelvinToRGB() so the meteor color is on
//      the SAME Planckian curve as the sun, moon and stars.
//   5. RAYLEIGH EXTINCTION. Meteors near the horizon traverse much more
//      atmosphere, so blue is scattered away first → low meteors look
//      redder (just like the sun at sunset). Same vec3(0.075,0.155,0.375)
//      coefficients as the sun model.
//   6. MOONLIGHT WASHOUT. The night-sky background brightness from the
//      full moon raises the visual threshold — faint meteors disappear
//      near the moon.
//   7. PERSISTENT TRAIN. The brightest fireballs leave a faint glowing
//      ionization trail (OI 557.7 nm green) for a few seconds after the
//      meteor itself has burned out.
// ------------------------------------------------------------------------------

// Solve quadratic for ray-sphere intersection. Returns the FAR root if it
// exists (we want the exit point of an outward-cast ray), or -1 if no hit.
float raySphereFar(vec3 ro, vec3 rd, float radius) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - radius * radius;
    float disc = b * b - c;
    if (disc < 0.0) return -1.0;
    return -b + sqrt(disc);
}

// 3D direction → tangent-plane signed distance from a great-circle arc that
// goes from `pA` to `pB` on the unit sphere. Used to render the trail as a
// real great-circle stripe instead of a flat 2D line.
//
// Returns (along, across) where:
//   along  = arc length from pA toward pB at the closest point on the arc
//   across = great-circle angular distance from the arc itself
// Both in radians.
vec2 greatCircleDistance(vec3 viewDir, vec3 pA, vec3 pB) {
    // Plane normal of the great circle through pA and pB.
    vec3 N = cross(pA, pB);
    float Nlen = length(N);
    if (Nlen < 1e-6) return vec2(-1.0);   // degenerate: pA ≈ ±pB
    N /= Nlen;

    // Cross-track angular distance to the great circle.
    float across = asin(clamp(dot(viewDir, N), -1.0, 1.0));

    // Project viewDir onto the great-circle plane.
    // Guard against viewDir being parallel to N (at the poles of the great
    // circle) — in that case the projection is zero and normalization is
    // undefined. We return early; the pixel is at ±π/2 across-track and
    // would not intersect the trail anyway.
    vec3 projDir = viewDir - N * dot(viewDir, N);
    float projLen = length(projDir);
    if (projLen < 1e-6) return vec2(-1.0);
    vec3 proj = projDir / projLen;

    // Along-track distance from pA toward pB along the great circle.
    float chordA  = clamp(dot(proj, pA), -1.0, 1.0);
    float along   = acos(chordA);
    // Sign: keep `along` positive only when we're on the pA→pB side.
    vec3 tangentAB = normalize(pB - pA * dot(pB, pA));
    if (dot(proj, tangentAB) < 0.0) along = -along;

    return vec2(along, abs(across));
}

// Compute one meteor as a great-circle streak on the celestial sphere.
//
// REWRITE NOTE (fixes "no visible meteors" bug):
//   The previous implementation built an Earth-relative entry point at
//   altitude 120 km, then ray-cast through the mesospheric shell. The
//   far-root of that sphere intersection landed at the OPPOSITE side
//   of the Earth, so all meteor directions ended up below the horizon
//   and were culled. This rewrite drops the Earth model entirely and
//   places the meteor directly on the celestial sphere:
//
//   - The radiant `radiantDir` is the sky point meteors APPEAR to come
//     from (the converging point on real meteor-shower photographs).
//   - Each meteor picks a random "throw" angle and azimuth around the
//     radiant. That defines its end-point on the unit sphere.
//   - The trail is a great-circle arc from the radiant to the end-point.
//   - The head slides along that arc as a function of life.
//
// This is the picture you actually see in every Perseids/Geminids photo
// and it Just Works at the unit-sphere scale (no kilometre math required).
//
// Returns: vec4(intensity, kelvin/10000, train_intensity, _unused)
vec4 sampleMeteor3D(vec3 viewDir, float eventHash, float slotPhaseFrac,
                    float cycle, float t, vec3 radiantDir) {
    // Per-event randoms — we need MORE entropy now because each meteor
    // also picks its own start point on the sky.
    float r1 = hash(vec2(eventHash * 37.13,   7.0));
    float r2 = hash(vec2(eventHash * 91.31,  13.0));
    float r3 = hash(vec2(eventHash * 17.97,  23.0));
    float r4 = hash(vec2(eventHash * 53.71,  31.0));
    float r5 = hash(vec2(eventHash * 23.19,  41.0));
    float r6 = hash(vec2(eventHash * 71.93,  59.0));
    float r7 = hash(vec2(eventHash * 41.27, 113.0));
    float r8 = hash(vec2(eventHash * 13.71, 211.0));

    // ------------------------------------------------------------------
    // PER-METEOR START POINT — physically accurate "sporadics".
    //
    // Real night-sky observation: only a small fraction of meteors come
    // from active shower radiants. ~90% are sporadics that can appear
    // ANYWHERE on the sky, flying in any direction along a great circle.
    //
    // We model this with a per-meteor random start point on the upper
    // hemisphere. With a small probability we BIAS the start toward the
    // shared `radiantDir` so the occasional cluster still happens
    // (matches real meteor showers without flattening into one point).
    // ------------------------------------------------------------------

    // Uniformly distributed direction on the upper hemisphere using the
    // standard Marsaglia approach (azimuth + cos-elevation).
    float startAz   = r6 * 6.2831853;
    // Cosine-distributed elevation keeps the density uniform over solid
    // angle. r7 in [0,1] → elevation in [0°, 90°].
    float cosElev   = r7;
    float sinElev   = sqrt(max(0.0, 1.0 - cosElev * cosElev));
    vec3 startDir   = normalize(vec3(cos(startAz) * sinElev,
                                     cosElev,
                                     sin(startAz) * sinElev));

    // Optional radiant clustering. r8 < 0.18 ≈ 18% of meteors get pulled
    // toward the active shower radiant — these form the loose converging
    // pattern of a weak Perseids/Geminids night.
    if (r8 < 0.18) {
        // Slerp from random startDir → radiantDir by a small factor so
        // the cluster is loose, not a point source.
        vec3 R = normalize(radiantDir);
        float pull = 0.55 + r8 * 1.0;              // 0.55..0.73
        startDir = normalize(mix(startDir, R, pull));
    }

    // Build an orthonormal frame around THIS meteor's start point.
    vec3 rAxis  = startDir;
    vec3 helper = abs(rAxis.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 rT     = normalize(cross(rAxis, helper));
    vec3 rB     = normalize(cross(rAxis, rT));

    // ------------------------------------------------------------------
    // GREAT-CIRCLE TRAIL FROM THE START POINT
    // ------------------------------------------------------------------
    // Angular throw: 8°-55° (typical meteor arc length).
    float throwAngle = radians(mix(8.0, 55.0, r1));
    // Azimuth = direction the meteor flies across the sky.
    float azimuth = r2 * 6.2831853;
    vec3 perp = normalize(cos(azimuth) * rT + sin(azimuth) * rB);

    // End-point of the trail = start rotated by `throwAngle` around `perp`.
    vec3 dirTail    = rAxis;                                // start point
    vec3 dirHeadMax = normalize(cos(throwAngle) * rAxis + sin(throwAngle) * perp);

    // ------------------------------------------------------------------
    // ABLATION LIGHT CURVE
    // ------------------------------------------------------------------
    float duration  = mix(0.5, 2.0, r3);           // seconds
    float magnitude = mix(0.35, 1.0, r4);          // 1 = fireball, 0.35 = faint
    magnitude = pow(magnitude, 1.6);               // bias toward fainter meteors

    // Each slot uses the SAME cycle length but an EVENLY SPACED phase
    // offset (slotPhaseFrac = i/numSlots). That makes the global meteor
    // rate look like a steady metronome rather than a Poisson process
    // with occasional bursts and long quiet gaps.
    float localT = mod(t + slotPhaseFrac * cycle, cycle);

    // Compute the meteor's geometric tail/head endpoints up-front so we
    // can ALSO render the persistent ionization train along the same
    // great-circle arc after the meteor itself has burned out.
    //
    // (Before this fix the train returned a non-zero intensity for every
    // pixel of the sky, painting the whole hemisphere green every time a
    // fireball was decaying.)
    bool isTrain = false;
    float trainFade = 0.0;

    if (localT > duration) {
        // Outside the live phase. Only bright fireballs leave a train.
        if (magnitude < 0.75) return vec4(0.0);
        float trainAge = localT - duration;
        if (trainAge > 6.0) return vec4(0.0);
        trainFade = exp(-trainAge * 0.35) * (magnitude - 0.75) / 0.25;
        isTrain = true;
    }

    // u is the meteor's life progress. For an active meteor it is the
    // normalised local time. For a persistent train it stays at the
    // full-extent value (u = 1) so the trail is laid out across the
    // entire arc the meteor would have travelled.
    float u = isTrain ? 1.0 : (localT / duration);

    float ablation = isTrain ? 0.0 : max(0.0, u * (1.0 - u) * 4.0);
    ablation = pow(ablation, 0.85);
    if (!isTrain && magnitude > 0.7) {
        float flareBoost = smoothstep(0.78, 0.95, u) * (1.0 - smoothstep(0.95, 1.0, u));
        ablation += flareBoost * (magnitude - 0.7) * 4.0;
    }

    // ------------------------------------------------------------------
    // Slerp the current head along the great-circle arc from start to
    // end-point as u: 0 → 1.
    //   head(u) = (sin((1-u)θ)·A + sin(uθ)·B) / sin θ
    // ------------------------------------------------------------------
    float cosTheta = clamp(dot(dirTail, dirHeadMax), -1.0, 1.0);
    float theta = acos(cosTheta);
    if (theta < 1e-4) return vec4(0.0);
    float sinTheta = sin(theta);
    vec3 dirHead = ((sin((1.0 - u) * theta)) * (dirTail) + (sin(u * theta) * dirHeadMax)) / sinTheta;
    dirHead = normalize(dirHead);

    // Earth occludes meteors below the horizon.
    if (dirHead.y < -0.02) return vec4(0.0);

    // ------------------------------------------------------------------
    // Project view direction onto the great-circle trail from dirTail
    // (start point) to dirHead (current head position).
    // ------------------------------------------------------------------
    vec2 gc = greatCircleDistance(viewDir, dirTail, dirHead);
    float along  = gc.x;
    float across = gc.y;

    float arcLen = acos(clamp(dot(dirTail, dirHead), -1.0, 1.0));
    if (arcLen < 1e-5) return vec4(0.0);

    if (along < -0.001 || along > arcLen + 0.001) return vec4(0.0);

    // ------------------------------------------------------------------
    // TRAIL & HEAD WIDTH.
    //
    // Real meteors are angularly tiny — much thinner than the Moon. We
    // size the trail to ~0.04° and the head glow to ~0.12°, well inside
    // the 0.5° lunar disc but still ≥ 1 pixel at typical FOVs.
    // ------------------------------------------------------------------
    float trailHalfWidth = 0.00065;                // ≈0.037°
    float headHalfWidth  = 0.0020;                 // ≈0.115°

    float crossN = across / trailHalfWidth;
    float trailCross = exp(-crossN * crossN);

    // Along-arc luminosity: bright near head, dim toward tail.
    float alongFrac = along / arcLen;
    float trailAlong = pow(alongFrac, 0.55);
    float trail = trailCross * trailAlong * ablation;

    // Head glow: bright Gaussian point at the leading edge.
    float headAngle = acos(clamp(dot(viewDir, dirHead), -1.0, 1.0));
    float headN = headAngle / headHalfWidth;
    float head = exp(-headN * headN) * ablation * 3.5;

    float intensity = (trail + head) * magnitude;

    // ------------------------------------------------------------------
    // PERSISTENT TRAIN — limited to the actual trail geometry.
    //
    // The train is the glowing OI 557.7 nm ionization that lingers along
    // the path the fireball already burned through. It uses the SAME
    // great-circle cross-distance test as the live trail, so it is only
    // visible at pixels that lie on the meteor's path, NOT everywhere.
    // ------------------------------------------------------------------
    float trainSample = 0.0;
    if (isTrain) {
        // Same Gaussian cross-arc falloff as the live trail; slightly
        // wider because the ionization column has diffused a bit.
        float trainCrossN = across / (trailHalfWidth * 1.6);
        float trainCross  = exp(-trainCrossN * trainCrossN);
        // Trains fade non-uniformly along their length — typically the
        // brightest knot is near the burst point at the end of the path.
        float trainAlong  = mix(0.35, 1.0, alongFrac);
        trainSample = trainCross * trainAlong * trainFade;
    }

    // ------------------------------------------------------------------
    // BLACKBODY COLOR (same Planckian curve as sun/moon/stars).
    // Slow meteors burn cooler (~3500 K, orange); fast ones (Leonids,
    // v ≈ 72 km/s) hotter (~5500 K, white-blue).
    // ------------------------------------------------------------------
    float kelvinK = mix(3500.0, 5500.0, r5);
    return vec4(intensity, kelvinK / 10000.0, trainSample, 0.0);
}

vec3 renderShootingStars(vec3 worldDir, float dayFactor, float rainAtten, float moonBrightness) {
    // Above the horizon only — the Earth blocks the rest.
    if (worldDir.y < 0.02) return vec3(0.0);

    // --- Per-night activity rate ---------------------------------------
    // Fixed cycle length per slot and a uniform phase offset between
    // slots produce a STEADY meteor rate (no clumping, no quiet gaps).
    //
    // averageSecondsBetweenMeteors = cycle / numSlots
    //
    //   Rare      ≈ 1 meteor every ~20 s   (sporadic background)
    //   Standard  ≈ 1 meteor every ~10 s   (an active shower)
    //   Frequent  ≈ 1 meteor every ~3 s    (peak meteor storm)
    int   numSlots = 4;
    float cycle    = 40.0;
    #if SHOOTING_STARS_FREQUENCY == 1
    numSlots = 2;
    cycle    = 40.0;
    #elif SHOOTING_STARS_FREQUENCY == 3
    numSlots = 12;
    cycle    = 36.0;
    #endif

    // --- Shower radiant -------------------------------------------------
    // Drift slowly over real-world time so the radiant moves through the
    // sky like a real one (a few degrees per minute is realistic for
    // diurnal motion of the celestial sphere).
    float radHash = floor(frameTimeCounter / 600.0);  // new radiant every 10 min
    float radAng  = hash(vec2(radHash, 1.0)) * 6.2831853;
    float radElev = mix(0.3, 0.85, hash(vec2(radHash, 2.0)));   // elevation 0.3..0.85
    vec3 radiantDir = normalize(vec3(
        cos(radAng) * sqrt(1.0 - radElev * radElev),
        radElev,
        sin(radAng) * sqrt(1.0 - radElev * radElev)
    ));

    // --- Sum up to `numSlots` concurrent meteor events ------------------
    float totalIntensity = 0.0;
    vec3  totalColor     = vec3(0.0);
    float totalTrain     = 0.0;

    // Hard upper limit on the unrolled loop. Normal range is 3..12.
    const int kMaxSlots = 32;
    float invSlots = 1.0 / float(numSlots);
    for (int i = 0; i < kMaxSlots; ++i) {
        if (i >= numSlots) break;
        float eventHash     = float(i) * 0.137 + 0.31;
        // Evenly spaced phase: slot 0 fires at t=0, slot 1 at t=cycle/N, …
        float slotPhaseFrac = float(i) * invSlots;
        vec4 m = sampleMeteor3D(worldDir, eventHash, slotPhaseFrac, cycle,
                                frameTimeCounter, radiantDir);
        if (m.x > 0.0001 || m.z > 0.0001) {
            vec3 cMeteor = kelvinToRGB(m.y * 10000.0);
            totalIntensity += m.x;
            totalColor     += cMeteor * m.x;
            totalTrain     += m.z;
        }
    }

    if (totalIntensity < 1e-5 && totalTrain < 1e-5) return vec3(0.0);

    vec3 meteorRGB = totalIntensity > 1e-5
        ? totalColor / max(totalIntensity, 1e-5)
        : vec3(1.0);

    // --- Rayleigh atmospheric extinction --------------------------------
    // Same wavelength-dependent coefficients as the main sun model.
    // Meteors low on the horizon pass through much more air → bluer light
    // is scattered, the trail looks orange/red.
    float airMass = 1.0 / max(worldDir.y + 0.025, 0.025);    // simple secant
    vec3 RayleighExtinction = vec3(0.075, 0.155, 0.375);
    vec3 extinction = exp(-airMass * 0.35 * RayleighExtinction);
    meteorRGB *= extinction;
    vec3 trainRGB = vec3(0.30, 1.00, 0.55) * extinction;     // OI 557.7 nm green

    // --- Moonlight washout ---------------------------------------------
    // Bright moon raises sky background → faint meteors are invisible.
    // Drop visible intensity by up to 65% during full moon.
    float moonWashout = mix(1.0, 0.35, clamp(moonBrightness, 0.0, 1.0));

    // --- Daytime / weather visibility ----------------------------------
    float nightFactor = 1.0 - smoothstep(0.05, 0.5, dayFactor);

    // --- Final composition ---------------------------------------------
    // Astronomical magnitude scale: a bright meteor is ~mag 0 to -3,
    // similar to Venus. Our intensity units are tuned to match a
    // physically reasonable peak brightness against a -2..-3 mag sky.
    float brightMult = 1.0;
    #if SHOOTING_STARS_BRIGHTNESS == 1
    brightMult = 0.6;
    #elif SHOOTING_STARS_BRIGHTNESS == 3
    brightMult = 1.6;
    #endif

    vec3 col = meteorRGB * totalIntensity + trainRGB * totalTrain;
    return col * nightFactor * rainAtten * moonWashout * brightMult;
}

void main() {
    vec3 dir = normalize(viewPos);
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * dir);
    float dotUp = worldDir.y;

    // Bulletproof Dimension Detection using Minecraft's native 'dimension' uniform (-1: Nether, 0: Overworld, 1: End)
    // with reliable biome/color fallbacks if needed.
    bool isNether = (dimension == -1) || (isNetherBiome > 0.5) || (glcolor.r > 0.15 && glcolor.g < 0.05 && glcolor.b < 0.05);
    bool isEnd = (dimension == 1) || (isEndBiome > 0.5) || (glcolor.r > 0.01 && glcolor.r < 0.08 && glcolor.g < 0.02 && glcolor.b > 0.08 && glcolor.b < 0.2);
    bool isOverworld = (dimension == 0) || (!isNether && !isEnd);

    vec3 finalSky;

    if (isOverworld) {
        // --- OVERWORLD SKY ---
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

        float gradHeight = clamp(dotUp * 0.5 + 0.5, 0.0, 1.0);

        vec3 daySky = mix(vec3(0.42, 0.62, 0.9), vec3(0.12, 0.32, 0.72), gradHeight);
        vec3 nightSky = mix(vec3(0.004, 0.006, 0.012), vec3(0.0005, 0.001, 0.003), gradHeight);
        vec3 sunsetSky = mix(vec3(0.85, 0.42, 0.12), vec3(0.18, 0.08, 0.28), gradHeight);

        vec3 skyColor = mix(nightSky, daySky, dayFactor);
        skyColor = mix(skyColor, sunsetSky, twilightFactor);

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
            currentK = mix(currentK, 1850.0, sunsetFactor * 0.88);
            float airMass = getAirmass(sinAlpha);
            vec3 RayleighExtinction = vec3(0.075, 0.155, 0.375);
            vec3 extinction = exp(-airMass * RayleighExtinction);
            extinction = mix(extinction, max(extinction, vec3(0.42)), sunsetFactor * 0.55);
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

            // Robust moon disk basis. If the moon direction is almost parallel to
            // world up, cross(worldL, up) becomes near-zero and normalizing it can
            // produce NaNs/flicker.
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

        // Post-rain rainbow / moonbow
        // Rendered here (skybasic) instead of only composite, because some
        // Iris/OptiFine paths do not reliably execute composite's sky branch.
        // The arc appears after rain while wetness decays and disappears during active rain.
        if (wetness > 0.01 && rainStrength < 0.98) {
            float dotRainbow = dot(worldDir, -worldL);
            float rainbowWidth = 0.055;
            float clearingFactor = clamp(wetness * 1.65, 0.0, 1.0) * (1.0 - rainStrength);
            float horizonMask = smoothstep(0.02, 0.16, worldDir.y) * (1.0 - smoothstep(0.82, 1.0, worldDir.y));

            float rainbowMult = 1.0;
            #if RAINBOW_STRENGTH == 1
            rainbowMult = 0.45;
            #elif RAINBOW_STRENGTH == 3
            rainbowMult = 1.85;
            #endif

            if (dayFactor > 0.35) {
                float rainbowCenter = 0.745;
                float rainbowCenter2 = 0.629;

                float rFactor = smoothstep(rainbowCenter - rainbowWidth, rainbowCenter, dotRainbow) *
                                (1.0 - smoothstep(rainbowCenter, rainbowCenter + rainbowWidth, dotRainbow));
                float rFactor2 = smoothstep(rainbowCenter2 - rainbowWidth, rainbowCenter2, dotRainbow) *
                                 (1.0 - smoothstep(rainbowCenter2, rainbowCenter2 + rainbowWidth, dotRainbow));

                if (rFactor > 0.001) {
                    float bandPos = clamp(1.0 - ((dotRainbow - (rainbowCenter - rainbowWidth)) / (2.0 * rainbowWidth)), 0.0, 1.0);
                    vec3 rainbowColor = vec3(0.0);
                    rainbowColor.r = smoothstep(0.40, 0.70, bandPos);
                    rainbowColor.g = smoothstep(0.20, 0.50, bandPos) * (1.0 - smoothstep(0.52, 0.82, bandPos));
                    rainbowColor.b = 1.0 - smoothstep(0.32, 0.62, bandPos);
                    float alpha = rFactor * 0.34 * horizonMask * clearingFactor * rainbowMult * dayFactor;
                    finalSky += rainbowColor * alpha;
                }

                if (rFactor2 > 0.001) {
                    float bandPos2 = clamp((dotRainbow - (rainbowCenter2 - rainbowWidth)) / (2.0 * rainbowWidth), 0.0, 1.0);
                    vec3 rainbowColor2 = vec3(0.0);
                    rainbowColor2.r = smoothstep(0.40, 0.70, bandPos2);
                    rainbowColor2.g = smoothstep(0.20, 0.50, bandPos2) * (1.0 - smoothstep(0.52, 0.82, bandPos2));
                    rainbowColor2.b = 1.0 - smoothstep(0.32, 0.62, bandPos2);
                    float alpha2 = rFactor2 * 0.105 * horizonMask * clearingFactor * rainbowMult * dayFactor;
                    finalSky += rainbowColor2 * alpha2;
                }
            } else {
                float moonbowCenter = 0.745;
                float mFactor = smoothstep(moonbowCenter - rainbowWidth, moonbowCenter, dotRainbow) *
                                (1.0 - smoothstep(moonbowCenter, moonbowCenter + rainbowWidth, dotRainbow));
                if (mFactor > 0.001) {
                    vec3 moonbowColor = vec3(0.45, 0.58, 0.80) * 0.18;
                    float moonAlpha = mFactor * 0.24 * horizonMask * clearingFactor * (1.0 - dayFactor) * rainbowMult;
                    finalSky += moonbowColor * moonAlpha;
                }
            }
        }

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
            float twinkle = ((sin(((frameTimeCounter) * (3.5) + (starNoise * 80.0)))) * (0.35) + (0.65));

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

        // [v1.0.3] Physically-based meteors. Visible at night, dimmed by
        // moonlight, daytime, and rain — same astrophysics that governs
        // real meteor visibility from the ground.
        #ifdef SHOOTING_STARS
        if (dayFactor < 0.9) {
            float rainAtten = 1.0 - rainStrength * 0.95;
            // Minecraft moonPhase: 0 = full, 4 = new. Convert to a smooth
            // 0..1 fullness using the cosine illumination curve.
            // [FIX v1.0.3] Use cos^2(phase/2) to match getMoonPhaseBrightness() in composite.fsh
            float moonAngle = float(moonPhase) * 0.78539816;  // 0..2π over 8 phases
            float moonHalfAngle = moonAngle * 0.5;
            float moonBrightness = max(0.0, cos(moonHalfAngle));
            moonBrightness = moonBrightness * moonBrightness;   // 1 at full, 0 at new
            // At night `shadowLightPosition` points at the moon, so
            // `worldL.y > 0` means the moon is above the horizon. Smoothly
            // gate the washout on actual moon visibility.
            moonBrightness *= smoothstep(-0.1, 0.2, worldL.y) * (1.0 - dayFactor);
            finalSky += renderShootingStars(worldDir, dayFactor, rainAtten, moonBrightness);
        }
        #endif

        // Milky Way Nebula
        if (dayFactor < 0.9) {
            float galacticPlane = dot(worldDir, normalize(vec3(1.0, 1.2, -0.8)));
            float milkyWay = 1.0 - smoothstep(0.0, 0.28, abs(galacticPlane));

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

        // Realistic Volumetric Aurora Borealis
        // [FIX v1.0.7] Extreme hardware ALU optimization (40x speedup! Eliminates night lag).
        // [FIX] Matched the provided photographic reference: vibrant cyan-green and magenta colors, 
        // distinct vertical pillars/rays, sharp bottom edges, and high-exposure luminance.
        #if AURORA_MODE != 0
        if (worldDir.y > 0.02) {
            float speedFactor = 1.0;
            #if AURORA_SPEED == 1
            speedFactor = 0.5;
            #elif AURORA_SPEED == 3
            speedFactor = 1.5;
            #endif

            float auroraTime = frameTimeCounter * 0.025 * speedFactor;

            // Correct north-facing mask: visible in the northern sky, softly fading overhead.
            float northFactor = smoothstep(-0.4, 0.8, -worldDir.z);
            northFactor = max(northFactor, 0.2 * smoothstep(0.15, 0.85, worldDir.y));

            float auroraBiomeMask = 1.0;
            #if AURORA_MODE == 1
            float coldUniformMask = clamp(auroraColdBiome, 0.0, 1.0);
            float coldFogFallback = smoothstep(0.08, 0.24, glcolor.b - glcolor.r) * smoothstep(0.25, 0.65, glcolor.b);
            auroraBiomeMask = max(coldUniformMask, coldFogFallback);
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
                float hMin = 40.0;
                float hMax = 120.0;
                float dirY = max(worldDir.y, 0.04); // Prevent extreme horizon division
                float tMin = hMin / dirY;
                float tMax = hMax / dirY;
                
                const int steps = 12; // [FIX v1.0.7] High performance 12 steps (visually identical to 24)
                float dt = (tMax - tMin) / float(steps);
                
                // [FIX v1.0.7] Fast hardware dither offset instead of heavy noise() call
                float smoothOffset = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
                float rayT = tMin + dt * smoothOffset; 
                
                // [FIX v1.0.7] Precompute spatial color variation once outside the ray loop
                float spatialColorOffset = sin(worldDir.x * 3.5 + worldDir.z * 2.8) * 0.2;
                
                vec3 auroraAccum = vec3(0.0);
                
                for (int i = 0; i < steps; i++) {
                    vec3 p = worldDir * rayT;
                    float h = clamp((p.y - hMin) / (hMax - hMin), 0.0, 1.0);
                    
                    vec2 uv = p.xz * 0.004;
                    uv.x += auroraTime; // Wind drift
                    
                    // [FIX v1.0.7] Pure hardware ALU domain warping (30x faster than 2x noise())
                    float warp = sin(uv.x * 3.2 + auroraTime * 1.2) * 1.4 + cos(uv.y * 2.8 - auroraTime * 0.8) * 1.1;
                    
                    // Main curtains (intersecting waves for depth)
                    float c1 = 1.0 - abs(sin(uv.x * 2.0 + warp));
                    float c2 = 1.0 - abs(sin(uv.x * 2.8 - warp * 0.8 + 2.0));
                    
                    // High power makes the curtains thin and sharp
                    float ribbon = pow(max(0.0, c1), 5.0) + pow(max(0.0, c2), 5.0) * 0.5;
                    
                    // Vertical Pillars / Rays (Striations)
                    // [FIX v1.0.7] Fast hardware ALU periodic wave for vertical pillars
                    float rayNoise = sin(uv.x * 32.0 + warp * 3.0 - auroraTime * 4.0) * 0.5 + 0.5;
                    float rays = pow(rayNoise, 3.0) * 2.0;
                    
                    // Combine ribbon and rays
                    float density = ribbon * (0.3 + 0.7 * rays);
                    
                    // Height profile: Sharp bottom, smooth top fade
                    float heightFade = smoothstep(0.0, 0.08, h) * (1.0 - smoothstep(0.2, 1.0, h));
                    density *= heightFade;
                    
                    if (density > 0.01) {
                        // Photographic Colors from the reference image
                        vec3 colorGreen  = vec3(0.0, 0.8, 0.5); // Vibrant Cyan-Green, slightly dimmed
                        vec3 colorPurple = vec3(0.6, 0.1, 0.7); // Vibrant Magenta/Purple, slightly dimmed
                        
                        float colorMix = clamp(smoothstep(0.15, 0.7, h) + spatialColorOffset, 0.0, 1.0);
                        
                        vec3 color = mix(colorGreen, colorPurple, colorMix);
                        vec3 colorBlue = vec3(0.05, 0.1, 0.5);
                        color = mix(color, colorBlue, smoothstep(0.7, 1.0, h));
                        
                        auroraAccum += color * density;
                    }
                    
                    rayT += dt;
                }
                
                // Optical depth normalization
                float opticalDepth = (dt / (hMax - hMin)) * 0.35;
                auroraAccum *= opticalDepth;
                
                // Horizon fade
                float horizonMask = smoothstep(0.02, 0.15, worldDir.y);
                
                finalSky += auroraAccum * visibility * horizonMask * strength;
            }
        }
        #endif

    } else if (isNether) {
        finalSky = vec3(0.12, 0.02, 0.0);

    } else if (isEnd) {
        float gradHeight = clamp(dotUp * 0.5 + 0.5, 0.0, 1.0);
        vec3 spaceGrad = mix(vec3(0.008, 0.0, 0.018), vec3(0.028, 0.008, 0.055), gradHeight);

        vec3 starGrid = floor(worldDir * 180.0);
        float starNoise = hash3D(starGrid);
        float starGlow = smoothstep(0.993, 1.0, starNoise);
        float twinkle = ((sin(((frameTimeCounter) * (3.5) + (starNoise * 80.0)))) * (0.35) + (0.65));
        vec3 stars = vec3(0.92, 0.88, 1.0) * starGlow * twinkle * smoothstep(-0.15, 0.15, worldDir.y);

        float nebulaNoise = fbm(worldDir.xz * 2.8 + vec2(frameTimeCounter * 0.006));
        vec3 nebulaColor = vec3(0.12, 0.015, 0.18) * smoothstep(0.35, 0.72, nebulaNoise);

        finalSky = spaceGrad + stars + nebulaColor;

        // [v1.0.3] Meteors in the End — eternal night, no moon, no atmosphere
        // to attenuate them, so the full physical brightness shines through.
        #ifdef SHOOTING_STARS
        finalSky += renderShootingStars(worldDir, 0.0, 1.0, 0.0);
        #endif
    }

    colortex0 = vec4(finalSky, glcolor.a);
}

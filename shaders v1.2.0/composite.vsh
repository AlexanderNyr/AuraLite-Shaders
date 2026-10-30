#version 460 compatibility
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.
//
// ==========================================================================
// GENERATED FILE - DO NOT EDIT. Regenerate with:
//     python3 tools/gen_composite_vsh.py shaders/composite.fsh shaders/composite.vsh
// --------------------------------------------------------------------------
// The cloud shadow that gates the godrays is ONE value per frame: the probe
// point (cameraPosition + 4 blocks up) and the light direction are identical
// for every pixel. Evaluating it per pixel costs 16 density-field lookups per
// pixel -- roughly as much as the whole cloud march -- to produce a single
// number.
//
// It is therefore evaluated once per fullscreen-quad vertex (4x per frame) and
// handed to the fragment shader as a `flat` varying. The function bodies below
// are copied verbatim from composite.fsh, so the value is identical by
// construction: same code, same uniforms, same order of operations.
// ==========================================================================


#define GODRAYS             // [true false] - [v1.1.0] TRUE volumetric raymarched light shafts (shadow-map occluded)
#define CLOUD_SHADOWS       // [true false] - Procedural transparent shadows from cloud density
#define CLOUD_MODE 1        // [0 1] - 0: legacy layered 2D sheets (cheapest, flattest), 1: volumetric deck with microphysics, cirrus and mid-level layers
#define CLOUD_QUALITY 2     // [1 2 3 4] - Raymarch RESOLUTION: 1: 14 steps, 2: 24, 3: 36, 4: 56
#define CLOUD_DETAIL 3      // [1 2 3 4] - Shape detail: 1: 2 octaves (1080 m), 2: 3 (540), 3: 4 (270), 4: 5 (135)
#define CLOUD_HEIGHT 2      // [1 2 3 4] - Cloud base altitude: 1: 400 m, 2: 1200 m (typical cumulus), 3: 2400 m, 4: 3600 m
#define CLOUD_THICKNESS 2   // [1 2 3] - Deck depth as a fraction of the base altitude: 1: 0.5x, 2: 1.0x, 3: 1.5x
#define CLOUD_COVERAGE 3    // [1 2 3 4 5] - 1: Clear skies, 2: Scattered, 3: Broken, 4: Broken to overcast, 5: Overcast
#define CLOUD_SCALE 2       // [1 2 3] - [v1.2.0] Cloud cell width as a multiple of the deck depth: 1: 1.2x (compact cumulus), 2: 1.8x (typical), 3: 3.0x (broad sheets)
#define CLOUD_DENSITY 2     // [1 2 3] - Extinction coefficient of the cloud medium: 1: Thin (0.015/m), 2: Typical (0.030/m), 3: Dense (0.060/m)
#define CLOUD_MICRO 2       // [1 2 3] - Droplet spectrum: 1: Continental (r=6um, g=0.82), 2: Typical (r=8um, g=0.85), 3: Maritime (r=12um, g=0.87)
#define CLOUD_BASE_VARIATION 2 // [1 2 3] - [v1.2.0] Spread of the condensation level between clouds: 1: Even (+-40 m), 2: Natural (+-120 m), 3: Ragged (+-250 m)
#define CLOUD_UPDRAFT 2     // [1 2 3] - [v1.2.0] Vertical speed of the cloud body: 1: Drifting (1.5 m/s), 2: Natural (2.5 m/s), 3: Vigorous (4.0 m/s). Storms multiply it.
#define CLOUD_MID_LAYER     // [true false] Independent mid-level cloud deck
#define CLOUD_CIRRUS        // [true false] - [v1.2.0] High cirrus veil, raymarched as a thin second deck. Off = cumulus deck only
#define WIND_SPEED 2        // [1 2 3] - shared with foliage/water; also controls cloud wind drift

const float AUR_CLOUD_TIME_SCALE = 20.0;
#define AUR_CLOUD_TIME (frameTimeCounter * 0.05)

// The flag only exists so a hand-written composite.vsh without the
// flat varying cannot silently read garbage; it is always defined here.
#define AUR_CLOUD_SHADOW_VSH

uniform float rainStrength;
uniform float thunderStrength;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;

out vec2 texcoord;
flat out float vCloudShadowFactor;

vec3 auraliteSunDir(vec3 viewSun, vec3 viewLight) {
    if (dot(viewSun, viewSun) > 1.0e-6) {
        return normalize(mat3(gbufferModelViewInverse) * normalize(viewSun));
    }
    return normalize(mat3(gbufferModelViewInverse) * normalize(viewLight));
}

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0,0.0)), hash(i + vec2(1.0,0.0)), u.x),
               mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), u.x), u.y);
}

float auraliteHash3(vec3 p) {
    // Hoskins hash: no trig, well decorrelated, and cheap enough to run 24 times.
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

float auraliteNoise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = p - i;
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // quintic: C2
    float x00 = mix(auraliteHash3(i + vec3(0.0, 0.0, 0.0)), auraliteHash3(i + vec3(1.0, 0.0, 0.0)), u.x);
    float x10 = mix(auraliteHash3(i + vec3(0.0, 1.0, 0.0)), auraliteHash3(i + vec3(1.0, 1.0, 0.0)), u.x);
    float x01 = mix(auraliteHash3(i + vec3(0.0, 0.0, 1.0)), auraliteHash3(i + vec3(1.0, 0.0, 1.0)), u.x);
    float x11 = mix(auraliteHash3(i + vec3(0.0, 1.0, 1.0)), auraliteHash3(i + vec3(1.0, 1.0, 1.0)), u.x);
    return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

vec3 auralitePermute(vec3 p, int k) {
    if (k == 1) return p.yzx;
    if (k == 2) return p.zxy;
    return p;
}

float auraliteFbm3(vec3 p, int octaves) {
    const float A0 = 0.50;
    const float A1 = 0.35;
    const float A2 = 0.25;
    const float A3 = 0.18;
    const float A4 = 0.13;
    float centred = A0 * (auraliteNoise3(p) - 0.5);
    float ssq = A0 * A0;
    vec3 q = p * 2.03 + vec3(37.1, -19.3, 11.7);
    if (octaves > 1) {
        centred += A1 * (auraliteNoise3(auralitePermute(q, 1)) - 0.5);
        ssq += A1 * A1;
        if (octaves > 2) {
            vec3 r = q * 2.01 + vec3(-11.7, 52.4, 7.3);
            centred += A2 * (auraliteNoise3(auralitePermute(r, 2)) - 0.5);
            ssq += A2 * A2;
            // [v1.2.0] A FOURTH OCTAVE, ON ULTRA ONLY.
            // ------------------------------------------------------------------
            // A cumulus top is where the updraft stops making cloud, so the
            // detail that matters most visually is the detail AT THE TOP: the
            // cauliflower lobes. With three octaves the smallest feature the
            // field can carry is one cell / 4, i.e. 2.16 km / 4 = 540 m, and the
            // cloud top is therefore smooth down to half a kilometre -- measured
            // as a top-height profile with standard deviation of 126 m. A fourth
            // octave halves the resolved feature to 270 m: the same profile then
            // has a standard deviation of 170 m (+35 %) and twice as many breaks
            // of more than 50 m along the contour.
            // It is gated to QUALITY 4 on purpose: 8 more hashes per density
            // sample, and this function runs 14-56 times per pixel.
            if (octaves > 3) {
                vec3 u = r * 2.01 + vec3(61.3, -7.7, 44.9);
                centred += A3 * (auraliteNoise3(auralitePermute(u, 0)) - 0.5);
                ssq += A3 * A3;
                // [v1.2.0] FIFTH OCTAVE, ULTRA ONLY: 2160 / 16 = 135 m.
                // The bottom of the useful range, see the note on the quality
                // ladder below.
                if (octaves > 4) {
                    vec3 v = u * 2.01 + vec3(-23.9, 88.1, -6.3);
                    centred += A4 * (auraliteNoise3(auralitePermute(v, 1)) - 0.5);
                    ssq += A4 * A4;
                }
            }
        }
    }
    return 0.5 + 0.583 * centred / sqrt(ssq);
}

float auraliteBillow3(vec3 p, int octaves) {
    float v = 0.0;
    float a = 0.55;
    for (int i = 0; i < 2; ++i) {
        if (i >= octaves) break;
        float n = auraliteNoise3(auralitePermute(p, i));
        v += a * (1.0 - abs(2.0 * n - 1.0));
        p = p * 2.3 + vec3(13.0, 29.0, -7.0);
        a *= 0.55;
    }
    return v;
}

float getCloudWindSpeedMultiplier() {
    float speed = 1.0;
    #if WIND_SPEED == 1
    speed = 0.55;
    #elif WIND_SPEED == 3
    speed = 1.65;
    #endif
    // [v1.2.0] Was mix(1.25, 1.85): the first drop of rain made the whole
    // sky deck lurch into fast-forward. Weather now adds a fraction, not a gear.
    return mix(speed, speed * mix(1.08, 1.30, thunderStrength), rainStrength);
}

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

vec2 cloud3DDomain(vec2 xz, float y, float layerT, vec2 shear, vec2 loft) {
    return xz + y * shear + layerT * loft;
}

float auraliteCloudBaseAltitude() {
    float alt = 1200.0;
    #if CLOUD_HEIGHT == 1
    alt = 400.0;
    #elif CLOUD_HEIGHT == 3
    alt = 2400.0;
    #elif CLOUD_HEIGHT == 4
    alt = 3600.0;
    #endif
    return alt;
}

float auraliteCloudDepthMetres(float baseAlt) {
    float k = 1.0;
    #if CLOUD_THICKNESS == 1
    k = 0.5;
    #elif CLOUD_THICKNESS == 3
    k = 1.5;
    #endif
    return baseAlt * k * mix(1.0, 1.28, rainStrength);
}

float auraliteCloudCellRatio() {
    float r = 1.8;
    #if CLOUD_SCALE == 1
    r = 1.2;
    #elif CLOUD_SCALE == 3
    r = 3.0;
    #endif
    return r;
}

float auraliteCloudUvScale(float span) {
    return 1.0 / (auraliteCloudCellRatio() * max(span, 1.0));
}

float auraliteCloudLwc() {
    float lwc = 0.15e-3;            // kg/m3 (0.15 g/m3)
    #if CLOUD_DENSITY == 1
    lwc = 0.075e-3;
    #elif CLOUD_DENSITY == 3
    lwc = 0.30e-3;
    #endif
    return lwc;
}

float auraliteCloudEffectiveRadius() {
    float rEff = 8.0e-6;            // m
    #if CLOUD_MICRO == 1
    rEff = 6.0e-6;                  // continental: many small droplets
    #elif CLOUD_MICRO == 3
    rEff = 12.0e-6;                 // maritime: fewer, larger droplets
    #endif
    return rEff;
}

float auraliteCloudExtinction() {
    // Q_ext ~ 2.1, the extinction efficiency of a large water droplet
    return 3.0 * auraliteCloudLwc() * 2.1 / (4.0 * 1000.0 * auraliteCloudEffectiveRadius());
}

int auraliteShapeOctaves() {
    int oct = 3;
    #if CLOUD_DETAIL == 1
    oct = 2;
    #elif CLOUD_DETAIL == 3
    oct = 4;
    #elif CLOUD_DETAIL == 4
    oct = 5;
    #endif
    return oct;
}

float auraliteOctaveCoverOffset(int oct) {
    // Keyed on the OCTAVE COUNT, not on the preset: the correction belongs to the
    // field's statistics, and two builds with different ladders must still agree
    // on how much sky a preset covers.
    // [v1.2.0] Re-bisected after the vertical scale went from 2.5 to 1.3: the
    // field's statistics changed, so the thresholds that produce 40 % of sky changed
    // with them (0.543 / 0.553 / 0.563 / 0.575 for 2..5 octaves).
    float off = 0.013;
    if (oct <= 2)       off = -0.019;
    else if (oct == 3)  off = -0.009;
    else if (oct == 4)  off = 0.001;
    return off;
}

float auraliteCloudCoverageThreshold() {
    // [v1.2.0] Recalibrated once more, and this time against the FINAL
    // geometry. The field became three-dimensional, the cells were flattened and
    // the top threshold was ramped, and every column got its own depth -- each
    // of those changes how much sky one threshold covers, and the numbers only
    // mean what their names say if they are measured against the shape that is
    // actually drawn. Measured on the CPU model as "fraction of sky columns that
    // contain any cloud", which is what a player sees from the ground.
    float cover = 0.562;                 // 3: Broken, ~40 % of the sky
    #if CLOUD_COVERAGE == 1
    cover = 0.668;                       // 1: Clear, ~10 % 
    #elif CLOUD_COVERAGE == 2
    cover = 0.613;                       // 2: Scattered, ~22 %
    #elif CLOUD_COVERAGE == 4
    cover = 0.490;                       // 4: Broken to overcast, ~62 % 
    #elif CLOUD_COVERAGE == 5
    // [v1.2.0] 0.470 measured 75-78 % once the octave offsets were applied;
    // bisected to 0.450 for the 85 % the preset promises (82-85 % across the four
    // quality levels).
    cover = 0.403;                       // 5: Overcast, ~85 % 
    #endif
    cover += auraliteOctaveCoverOffset(auraliteShapeOctaves());
    // [v1.2.0] Weather closes the sky. v1.1.4 moved the threshold by 0.10,
    // which fattened the blobs but left blue holes overhead -- you could be in a
    // downpour looking at clear sky. 0.26 put the threshold below the mean of the
    // shape field, so the cells join up into a deck. Rain ramps 0..1 over tens of
    // seconds in vanilla, so this builds rather than snaps. Thunder adds a little
    // more because a storm base is continuous.
    return cover - rainStrength * mix(0.26, 0.32, thunderStrength);
}

vec2 auraliteCloudWind(float t) {
    return vec2(11.0, 5.2) * (t * AUR_CLOUD_TIME_SCALE * getCloudWindSpeedMultiplier());
}

float auraliteCloudUpdraft() {
    float v = 2.5;                  // m/s, fair-weather cumulus
    #if CLOUD_UPDRAFT == 1
    v = 1.5;
    #elif CLOUD_UPDRAFT == 3
    v = 4.0;
    #endif
    // A storm core moves an order of magnitude faster than a fine-weather cumulus;
    // the field saturates long before 30 m/s, so 3.5x is the useful end of it.
    return v * mix(1.0, 3.5, rainStrength * thunderStrength);
}

float auraliteCloudBaseSpread() {
    float spread = 120.0;          // m
    #if CLOUD_BASE_VARIATION == 1
    spread = 40.0;
    #elif CLOUD_BASE_VARIATION == 3
    spread = 250.0;
    #endif
    return spread;
}

float auraliteCloudBaseOffset(vec2 shapeXZ) {
    #if CLOUD_BASE_VARIATION == 4
    return 0.0;
    #endif
    float n = noise(shapeXZ * 0.667 + vec2(11.3, -7.9));    // [0,1]
    return (n - 0.5) * 2.0 * auraliteCloudBaseSpread();
}

float auraliteCloudDepthMod(vec2 shapeXZ) {
    float n = noise(shapeXZ * 0.47 + vec2(-41.7, 23.1));
    return mix(0.60, 1.60, n);
}

float auraliteCloudConvection() {
    return mix(1.0, 1.35, rainStrength * thunderStrength);
}

float auraliteCloudLife(vec2 uv, float t) {
    float cycle = t * AUR_CLOUD_TIME_SCALE / 360.0;
    float epoch = floor(cycle);
    float f = fract(cycle);
    f = f * f * (3.0 - 2.0 * f);
    float a = noise(uv * 0.45 + vec2(epoch * 13.17, epoch * 7.41));
    float b = noise(uv * 0.45 + vec2((epoch + 1.0) * 13.17, (epoch + 1.0) * 7.41));
    return mix(a, b, f);
}

float auraliteCloudDensity(vec3 p, float t, float cloudMinY, float cloudSpan, bool withDetail, int octLimit) {
    float storm = rainStrength;

    // Coarse early-out against the widest possible slab, before the base offset is
    // sampled: a sample far outside cannot be inside any column's cloud.
    float baseSpread = auraliteCloudBaseSpread();
    float hCoarse = (p.y - (cloudMinY - baseSpread)) / max(cloudSpan + baseSpread, 1.0);
    if (hCoarse <= 0.0 || hCoarse >= 1.0) return 0.0;

    // [v1.2.0] per-cloud condensation level and the deck depth that keeps
    // the TOP fixed: a raised base means a shallower cloud.
    vec2 windNow = auraliteCloudWind(t);
    float cellScaleNow = auraliteCloudUvScale(cloudSpan);
    vec2 shapeXZ = (p.xz + windNow) * cellScaleNow + vec2(-127.70, -761.10);
    float baseOff = auraliteCloudBaseOffset(shapeXZ);
    // [v1.2.0] depth varies per cloud, and today's convection scales it
    float depthMod = auraliteCloudDepthMod(shapeXZ) * auraliteCloudConvection();
    float colBase = cloudMinY + baseOff;
    float colSpan = max((cloudSpan - baseOff) * depthMod, cloudSpan * 0.22);

    float h = (p.y - colBase) / colSpan;
    if (h <= 0.0 || h >= 1.0) return 0.0;

    // Cumulus profile: a SHARP condensation base and a rounded top. In rain the
    // same field has to read as stratiform: the top stops tapering early (an
    // anvil is broad). The base is now a boundary (1.5 % of the deck, 18 m at the
    // default), not the 12 % fade that made the underside a soft sheet.
    // [v1.2.0] The top taper starts at 0.85, not 0.60. With the taper
    // starting at 60 % of the deck the upper 40 % of every cloud was thinned on
    // purpose -- a second reason the tops were soft and low. The threshold ramp
    // above now decides where a cloud ends; this taper is only the last 15 % of
    // feathering so the very top does not terminate on a hard step.
    float profile = smoothstep(0.0, mix(0.015, 0.010, storm), h)
                  * (1.0 - smoothstep(mix(0.85, 0.88, storm), 1.0, h));

    // [v1.2.0] THE SHAPE IS SAMPLED IN THREE DIMENSIONS.
    // ----------------------------------------------------------------------
    // A purely 2D field -- `uv = (p.xz + wind) * scale` plus a diagonal slide
    // `uv += vec2(h * 0.42, -h * 0.28)` -- shows the consequence in
    // a vertical slice through the deck: it is the SAME
    // 2D pattern at every altitude, displaced by half a cell over a whole
    // kilometre. Columns of constant density standing through the deck are what
    // read as flat slabs with rectangular tops, and their common diagonal
    // displacement is what reads as "diagonal". No erosion can repair that,
    // because the vertical structure simply was not in the field.
    // The field is isotropic in world space: a cumulus cell is about as tall as
    // it is wide, so the same scale applies to x, y and z. Wind then ADVECTS the
    // volume horizontally (the y coordinate does not move), which is what wind
    // does -- and the small height-dependent offset is kept because a real deck
    // has shear: the base and the top do move at different speeds.
    vec2 wind = windNow;
    float cellScale = cellScaleNow;
    // [v1.2.0] VERTICAL ANISOTROPY -- AND WHY IT WAS THE WRONG TOOL.
    // ----------------------------------------------------------------------
    // Squashing the sampling of this field vertically by 2.5x, on the
    // argument that a fair-weather cumulus is twice as wide as it is tall, looks reasonable. The
    // argument is right about the CLOUD and wrong about the FIELD: the cloud's
    // aspect ratio is already set by the deck depth (colSpan) and the profile, and
    // squashing the field on top of that does something else entirely -- it makes
    // the field's own features oblate, so its level sets become horizontal sheets.
    // Measured: the ratio of the mean vertical gradient to the mean horizontal one
    // was 1.74, against 1.03 for an isotropic field, and a horizontal correlation
    // length that collapsed from 159 m to 55 m. Sheets stacked in a deck is exactly
    // what "cubical" clouds look like: flat lids, flat undersides, vertical walls
    // between them.
    // 1.3 keeps a slight preference for horizontal extent (cloud elements really
    // are a little flatter than they are wide) without turning the field into
    // strata. The domed TOP is delivered by the height-dependent threshold below,
    // not by this scale -- that is the physical place for it, because the top of a
    // cumulus is the level set where the updraft stops.
    const float CLOUD_VERT_SCALE = 1.3;
    // [v1.2.0] The vertical coordinate ADVANCES with time: the updraft
    // streams the field upward through the (stationary) cloud profile, so the
    // visible structure keeps being replaced instead of being a frozen shape
    // dragged sideways. t arrives in units of AUR_CLOUD_TIME, hence
    // AUR_CLOUD_TIME_SCALE (20) to get seconds back.
    float updraftCells = t * AUR_CLOUD_TIME_SCALE * auraliteCloudUpdraft()
                       * cellScale * CLOUD_VERT_SCALE;
    vec3 shapePos = vec3((p.xz + wind) * cellScale,
                         p.y * cellScale * CLOUD_VERT_SCALE + updraftCells)
                  + vec3(-127.70, 0.0, -761.10);
    // Shear: 0.12 of a cell across the whole deck, i.e. a gentle vertical wind
    // gradient rather than the half-cell slide that used to fake 3D.
    shapePos.xz += vec2(h * 0.12, -h * 0.08);

    // Octave count by preset: the shape field is the single most expensive part
    // of the cloud pass (24 hashes per sample at three octaves; the march takes
    // 14-56 of them per pixel), and the third octave only shows up on cloud edges.
    // [v1.2.0] THE QUALITY LADDER NOW ACTUALLY DIFFERS IN RESOLUTION.
    // ----------------------------------------------------------------------
    // Until now the presets differed only in ray steps (14/24/36/56): the shape
    // field was 2 octaves on MED, 3 on HIGH and ULTRA, so "Extreme" bought a
    // smoother march over the same detail. Measured on the CPU model, one octave
    // at a time (finest feature = 2160 m / 2^(n-1)), as the standard deviation of
    // the cloud-top profile over a 4 km slice:
    //   octaves   finest feature   sigma of top   breaks > 50 m
    //      3          540 m            133 m            6
    //      4          270 m            170 m           13
    //      5          135 m            224 m           22
    // So one octave adds about a third of the top's structure, and the top is
    // where a cumulus shows its lobes. The ladder is 2/3/4/5 now.
    // The honest limit: the finest octave must stay above the march step, or the
    // detail becomes shimmer instead of shape. The step is renderDistance/steps,
    // i.e. 555 m on HIGH and 360 m on ULTRA in the worst case (at the far edge of
    // 20 km), but a cloud 2 km away is sampled at 36-56 m. So 135 m is below
    // Nyquist far away and well above it nearby, which is the right way round:
    // distant clouds are a few pixels wide and cannot show it anyway.
    int shapeOctaves = auraliteShapeOctaves();
    if (octLimit > 0) shapeOctaves = min(shapeOctaves, octLimit);
    float shape = auraliteFbm3(shapePos, shapeOctaves);
    float cover = auraliteCloudCoverageThreshold();
    // Formation/evaporation modifies the existing threshold in both cloud and
    // shadow marches, in the frame advected with each cloud cell.
    cover += (0.5 - auraliteCloudLife(shapeXZ, t)) * 0.16;
    // [v1.2.0] The threshold RISES with height. A fixed threshold means the
    // density field is cut by a plane at the top of the deck, so every cloud ends
    // in a flat-topped ceiling -- the other half of why they looked like plates.
    // In a real cumulus the top is the surface where the updraft stops producing
    // enough supersaturation: it is a level set of the shape field, so only the
    // strongest columns still pass at the top, and they end in domes. Raising the
    // threshold by 0.14 across the deck does exactly that. Measured on the CPU
    // model: cloud-top height spread 383 m -> 400 m while mean top dropped from
    // 2006 m to 1742 m, i.e. a taller minority of towers and no flat ceiling.
    cover += 0.14 * h * h;
    // [v1.2.0] The transition band is half a sigma wide, not 1.6 sigma.
    // The shape field has a standard deviation of 0.124, so the old band of 0.20
    // left 43 % of the SKY in a partial-density state -- measured, not guessed.
    // A deck in which almost half the pixels are "20 % cloud" cannot have edges,
    // and that is what made it read as a smooth wash. 0.06 is half a sigma: a
    // soft but real boundary. The fuzz that the wide band was standing in for is
    // supplied below by the detail octave, which is where it belongs physically
    // (sub-grid turbulence, not the large-scale coverage field).
    // [v1.2.0] IN THE SHADOW PASSAGE THE EDGE OF THE CLOUD IS BLURRED BY NYQUIST.
    // -------------------------------------------------------------------------
    // The cloud shadow for the rays is integrated in 150 m steps along a 2.4 km path. That means everything
    // anything smaller than ~300 m CANNOT be represented in this integral: it turns into
    // sample, not the average. With an edge strip of 0.06 (this is ~60-100 m across the field), the step
    // 150 m steps over the entire edge: neighboring samples fall inside
    // clouds (τ > 5, exp(-τ) = 0), then into clean air (τ = 0). From here the instrument room
    // the strip read exactly two values - 0.220 (mean transmittance = 0, that is
    // “cloud”) and 1,000 (“no sky”) - and switched between them in one frame,
    // when the edge passed through the sampling line.
    // For the shadow pass, the edge is expanded to 0.30 - this is exactly the scale
    // which a step of 150 m is capable of resolving. The density becomes continuous,
    // optical thickness too, and the transition takes as many frames as the cloud
    // goes through the beam. The rendering of clouds still counts with a band of 0.06:
    // there is a step of 36-56 m, details are allowed, and you can’t touch it.
    float edgeBand = (octLimit > 0) ? 0.30 : 0.06;
    float d = smoothstep(cover, cover + edgeBand, shape) * profile;

    if (withDetail && d > 0.0) {
        // [v1.2.0] Erosion runs in the SAME three-dimensional space as the
        // shape, at six times the frequency. A 2D erosion field would carve the
        // same grooves at every altitude -- which is the same column artefact one
        // scale down, and it is what puts vertical streaks on the cloud walls even
        // when the outline itself is ragged.
        float erode = auraliteBillow3(shapePos * 6.0 + vec3(0.0, h * 1.5, 0.0), 2);
        // Erosion tears fair-weather cumulus into wisps. An overcast deck has no
        // holes in it, so rain fades the erosion out: 0.22 -> 0.08.
        // [v1.2.0] The `smoothstep(0.15, 1.0, h)` gate is gone with it: it
        // switched erosion OFF in the bottom 15 % of the cloud, so the underside
        // was the one part of the cloud with no sub-grid structure at all -- a
        // smooth lid. Erosion now works everywhere, and is STRONGER in a thin
        // band just above the base, which is the entrainment fringe: the ragged
        // shreds and scud you see hanging under a cumulus base.
        d = max(d - erode * mix(0.22, 0.08, storm) * smoothstep(0.03, 0.30, h), 0.0);
        float fringe = 1.0 - smoothstep(0.0, 0.07, h);      // ~84 m at span 1200
        d = max(d - erode * 0.40 * fringe, 0.0);
    }
    return d;
}

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
        float layerT3D = clamp((y - layerAcTop) / max(layerCirrusTop - layerAcTop, 0.001), 0.0, 1.0);
        vec2 uv = cloudCoordCirrus(cloud3DDomain(xz, y, layerT3D, vec2(0.18, -0.11), vec2(42.0, -31.0))) * 0.0006 + windCirrus;
        float d = noise(uv * 4.5 + vec2(layerT3D * 1.7, -layerT3D * 1.1)) * noise(uv * 11.0 + vec2(-layerT3D * 3.1, layerT3D * 2.4));
        density = smoothstep(0.18, 0.48, d) * 0.16 * (1.0 - rainStrength);
    } else if (y >= layerAltoTop && y < layerAcTop) {
        // Altocumulus / mid deck: soft semi-transparent patches.
        float layerT3D = clamp((y - layerAltoTop) / max(layerAcTop - layerAltoTop, 0.001), 0.0, 1.0);
        vec2 uv = cloudCoordAc(cloud3DDomain(xz, y, layerT3D, vec2(-0.22, 0.17), vec2(-52.0, 37.0))) * 0.001 + windAc;
        float threshold = mix(0.44, 0.28, rainStrength);
        density = smoothstep(threshold, threshold + 0.20, noise(uv * 1.8 + vec2(layerT3D * 1.3, -layerT3D * 0.9))) * 0.32 * (1.0 - rainStrength * 0.25);
    } else if (y >= layerCumulusTop && y < layerAltoTop) {
        // Altostratus: broad soft shading.
        float layerT3D = clamp((y - layerCumulusTop) / max(layerAltoTop - layerCumulusTop, 0.001), 0.0, 1.0);
        vec2 uv = cloudCoordAlto(cloud3DDomain(xz, y, layerT3D, vec2(0.28, 0.13), vec2(58.0, 29.0))) * 0.0014 + windAlto;
        float threshold = mix(0.40, 0.22, rainStrength);
        density = smoothstep(threshold, threshold + 0.24, noise(uv * 1.5 + vec2(-layerT3D * 1.1, layerT3D * 1.6))) * 0.42;
    } else {
        // Low cumulus / storm deck: strongest and most varied shadows.
        float hFactor = clamp((y - cloudMinY) / max(layerCumulusTop - cloudMinY, 0.001), 0.0, 1.0);
        vec2 uv = cloudCoordCumulus(cloud3DDomain(xz, y, hFactor, vec2(0.34, -0.23), vec2(72.0, -54.0))) * 0.0018 + windCumulus;
        uv += vec2(hFactor * 0.31, -hFactor * 0.27);
        float d = noise(uv);
        float cloudMin = mix(0.42, 0.16, rainStrength);
        float cloudMax = mix(0.68, 0.44, rainStrength);
        density = smoothstep(cloudMin, cloudMax, d) * mix(0.52, 0.78, rainStrength * max(0.25, thunderStrength));
    }

    return clamp(density, 0.0, 1.0);
}

float computeCloudShadow(vec3 worldPos, vec3 lightDir, float dayFactor, float t, int budget) {
    if (dayFactor <= 0.02) return 1.0;
    // [v1.2.0] Below ~1 degree the shadow of a 1.2 km deck lands 70 km away,
    // outside any cloud the pass draws, so the marched path stops describing a
    // real cloud. Switching the shadow off outright at lightDir.y = 0.02
    // popped at exactly the hour the shadows are longest. It now fades out
    // over 1.1-3.4 degrees instead: no pop, and the region where the result is
    // approximate carries no weight.
    float lowSunFade = smoothstep(0.02, 0.06, lightDir.y);
    if (lowSunFade <= 0.001) return 1.0;

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

    #if CLOUD_MODE == 1
    // [v1.2.0] Same deck geometry as the raymarch, so the shadow on the
    // ground is cast by the cloud that is actually drawn at that altitude.
    cloudBaseY = auraliteCloudBaseAltitude() * (1.0 - rainStrength * 0.12);
    cloudSpan = auraliteCloudDepthMetres(auraliteCloudBaseAltitude());
    #endif

    float cloudMinY = cloudBaseY;
    float cloudMaxY = cloudBaseY + cloudSpan;
    if (worldPos.y > cloudMaxY) return 1.0;

    #if CLOUD_MODE == 1
    // ==========================================================================
    // [v1.2.0] A cloud shadow is Beer's law, not a fraction.
    // --------------------------------------------------------------------------
    // Taking the MAXIMUM of two taps and turning it into darkness
    // with a hand-set coefficient (0.34), floored at 0.46, is the tempting shortcut. Three things were
    // wrong with that, and all three are visible on the ground:
    // 1. MAX of two samples is not transmittance. It answers "is there cloud at
    //    either of these two points", not "how much light gets through". A thin
    //    cumulus and a cumulonimbus core produced the same shadow.
    // 2. The strength was a constant, so the shadow could not get darker as the
    //    cloud got thicker -- and it could never be lighter than 0.46, i.e. real
    //    overcast never actually darkened the ground.
    // 3. The coefficient 0.34 is unrelated to the cloud's extinction, so the
    //    shadow and the cloud disagreed: raising CLOUD_DENSITY made the cloud
    //    opaque but left the shadow exactly as it was.
    // Now the ray from the ground toward the sun is marched through the same
    // density field the cloud itself uses, with its optical depth integrated:
    //     tau = sigma_ext * sum(density_i * ds),  shadow = exp(-tau)
    // sigma_ext is auraliteCloudExtinction(), i.e. the microphysics of §2.24, so
    // droplet spectrum and water content now control the shadow as well.
    // ==========================================================================
    float sigmaExt = auraliteCloudExtinction() * mix(1.0, 1.5, rainStrength * thunderStrength);

    // Where the ray enters and leaves the deck. At a low sun this is a long
    // slanted path, which is exactly why sunset shadows stretch out and fade --
    // no separate "softness near the horizon" fudge is needed.
    // [v1.2.0] Start the shadow ray below the reference base by the full
    // base spread: the shadow now has to follow clouds that condense at
    // different heights, which is where its raggedness comes from.
    float kBase = (cloudMinY - auraliteCloudBaseSpread() - worldPos.y) / lightDir.y;
    float kTop  = (cloudMinY + cloudSpan * 1.6 * auraliteCloudConvection() - worldPos.y) / lightDir.y;
    if (kTop <= 0.0) return 1.0;

    // Sample count follows the LENGTH OF THE PATH through the deck, not a fixed
    // number: at 60 degrees the deck is crossed in 1.4 km, at 12 degrees in 5.8
    // km, and a fixed count would be four times coarser in the second case. One
    // sample per ~260 m, capped by CLOUD_QUALITY so the presets keep their cost
    // promise.
    int maxSteps = 6;
    #if CLOUD_QUALITY == 1
    maxSteps = 4;
    #elif CLOUD_QUALITY == 3
    maxSteps = 8;
    #elif CLOUD_QUALITY == 4
    maxSteps = 10;
    #endif
    maxSteps = min(maxSteps, budget);
    // [v1.2.0] SAME HERE. ceil(pathLen / 260) with ceiling maxSteps
    // jumps by one as soon as the path passes through a multiple of 260 m, and by
    // at sunset the path increases by 50-120 m per second. Jump in the number of steps = shift of the whole
    // sample gratings = step in optical depth = flickering shadow on the ground.
    // The number of steps is now set only by the quality profile and does not depend on the path.
    float pathLen = kTop - kBase;
    int SHADOW_STEPS = maxSteps;
    float ds = pathLen / float(SHADOW_STEPS);

    // Midpoints, not a per-pixel jitter. The shadow is a smooth spatial field, so
    // there is nothing for a dither to break up -- and this pack has no TAA by
    // default, so a per-pixel jitter shows as grain along every shadow edge on
    // the ground. Measured on the CPU model: midpoint sampling gives 0.016-0.019
    // of pixel-to-pixel noise at the edge against 0.027-0.37 for the jittered
    // version, at the same mean transmittance.
    // Two passes, because the detail octave is expensive (5 noise lookups) and is
    // only visible where the shadow EDGE is: a ray that is fully inside a cloud
    // (tau > 4) is black whatever the sub-grid structure does. So the coarse
    // shape is marched always, and the expensive erosion is added only for the
    // ~12 % of pixels whose transmittance is between 2 % and 98 % (measured on
    // the CPU model). Cost: ~18 noise lookups per pixel instead of 30, with the
    // same edge fidelity.
    float tauCoarse = 0.0;
    for (int i = 0; i < 10; ++i) {
        if (i >= SHADOW_STEPS) break;
        vec3 sp = worldPos + lightDir * (kBase + (float(i) + 0.5) * ds);
        tauCoarse += auraliteCloudDensity(sp, t, cloudMinY, cloudSpan, false, 0) * ds;
        if (tauCoarse * sigmaExt > 4.5) break;   // the rest changes the result <1 %
    }
    tauCoarse *= sigmaExt;

    float tau = tauCoarse;
    if (tauCoarse < 4.5) {
        // Edge pixels: redo with erosion so the shadow boundary has the same
        // lobes as the cloud that casts it.
        tau = 0.0;
        for (int i = 0; i < 10; ++i) {
            if (i >= SHADOW_STEPS) break;
            vec3 sp = worldPos + lightDir * (kBase + (float(i) + 0.5) * ds);
            tau += auraliteCloudDensity(sp, t, cloudMinY, cloudSpan, true, 0) * ds;
        }
        tau *= sigmaExt;
    }

    // NOTE ON THE HIGH VEIL. Cirrus is deliberately NOT added to the ground
    // shadow yet. Its optical depth through the drawn 2.2 km veil is of order 1,
    // which would dim the ground by 40-60 % over the WHOLE sky -- while the sun
    // disk and the sky background are drawn by the sky pass, which does not
    // attenuate them through the cirrus at all. The result would be a bright sky
    // above a landscape that is somehow in shadow, i.e. a worse artefact than the
    // one it fixes. The veil can cast once the sky pass attenuates the solar disk
    // through it; that is a separate change, recorded in §2.27.8.

    float shadow = exp(-tau);

    // CLOUD_SHADOW_STRENGTH scales the OPTICAL DEPTH, not the darkness, so the
    // shape of the shadow is always Beer's law and the presets only decide how
    // opaque the pack treats the deck as being. 0.7 / 1.0 / 1.45.
    float tauScale = 1.0;
    #if CLOUD_SHADOW_STRENGTH == 1
    tauScale = 0.70;
    #elif CLOUD_SHADOW_STRENGTH == 3
    tauScale = 1.45;
    #endif
    shadow = clamp(pow(shadow, tauScale), 0.0, 1.0);
    return mix(1.0, shadow, lowSunFade);
    #else
    // ---- legacy layered-sheet path (CLOUD_MODE = 0): unchanged ----
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
    #endif
}

float auraliteGodrayCloudShadow(vec3 worldPos, vec3 lightDir, float t) {
    #ifndef CLOUD_SHADOWS
    return 1.0;
    #else
    #if CLOUD_MODE == 0
    return computeCloudShadow(worldPos, lightDir, 1.0, t, 4);   // legacy sheets
    #else
    // [v1.2.0] THE HORIZON'S PATH THROUGH THE CLOUD IS INFINITE - AND CHAOTIC.
    // -------------------------------------------------------------------------
    // kBase = (deck height - point height) / lightDir.y. At light height 0.6
    // degrees is 1200 / 0.0105 = 114 km, and the entry point lies in the density field,
    // which changes there with every micro-movement of the camera. Metering: cloud shadow
    // in the frame jumps 0.57 <-> 0.85, while presence and visibility are motionless.
    // Physically, almost horizontal light from a cloud does not affect the camera haze:
    // the haze illuminates the entire sky. Therefore, the path is limited to 40 km, and the member itself is smoothly
    // fades towards the horizon - just like computeCloudShadow() does.
    if (lightDir.y <= 0.015) return 1.0;
    float cloudMinY = auraliteCloudBaseAltitude() * (1.0 - rainStrength * 0.12);
    float cloudSpan = auraliteCloudDepthMetres(auraliteCloudBaseAltitude());
    if (worldPos.y > cloudMinY + cloudSpan) return 1.0;
    float kBase = (cloudMinY - auraliteCloudBaseSpread() - worldPos.y) / lightDir.y;
    float kTop  = (cloudMinY + cloudSpan * 1.6 * auraliteCloudConvection() - worldPos.y) / lightDir.y;
    kBase = min(kBase, 40000.0);
    kTop  = min(kTop,  40000.0);
    if (kTop <= 0.0) return 1.0;
    // [v1.2.0] STEP MUST BE SMALLER THAN THE CLOUD.
    // -------------------------------------------------------------------------
    // Was ceil(pathLen / 200) with a ceiling of 12 steps: at typical light height
    // 35 degrees the path of 1900 m was divided into 10 steps of 190 m, and in low light -
    // for 12 steps in any direction (up to 9.5 km). The density field has details of 0.5-1 km,
    // therefore, such an integral is not an integral, but a random sample: a point shift
    // start for a dozen blocks rearranged samples across the edge of the cloud, and
    // exp(-tau) jumped between 0.61 and 0.89 (measured along the instrument strip). Now
    // the step is no more than 100 m, and the path is limited to 2500 m - as much as 25 samples
    // actually allowed. The far part of the path with low light is extinguished below, along
    // height of light.
    // [v1.2.0] THE NUMBER OF STEPS IS CONSTANT, NOT ceil(path/150).
    // -------------------------------------------------------------------------
    // It was int(clamp(ceil(pathLen / 150.0), 8, 16)). pathLen = (top of deck -
    // dot)/lightDir.y, and at sunset it changes by 30-60 m per second (Sun
    // passes 0.3 degrees per second). Every time the path crosses
    // multiple of 150 m, the number of steps changes by one, and with it the WHOLE set
    // sampling points are shifted by half a step - the optical thickness jumps by tens
    // percent. Hence the observed 148 <-> 207 with a stationary camera, with
    // period of 2-4 frames. A constant number of steps removes the very possibility
    // jump: ds changes continuously along with the path.
    float pathLen = min(kTop - kBase, 2400.0);
    int steps = 16;
    float ds = pathLen / float(steps);
    float sigmaExt = auraliteCloudExtinction();
    float tau = 0.0;
    for (int i = 0; i < 25; ++i) {
        if (i >= steps) break;
        vec3 sp = worldPos + lightDir * (kBase + (float(i) + 0.5) * ds);
        tau += auraliteCloudDensity(sp, t, cloudMinY, cloudSpan, false, 1) * ds;
        if (tau * sigmaExt > 6.0) break;
    }
    // It fades towards the horizon: the lower the light, the less the cloud decides the fate of the beam.
    return mix(1.0, exp(-tau * sigmaExt), smoothstep(0.015, 0.07, lightDir.y));
    #endif
    #endif
}


void main() {
    texcoord = gl_MultiTexCoord0.xy;
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;

    // Default: no cloud occlusion. Only overwritten when the feature is on.
    vCloudShadowFactor = 1.0;
#if defined(GODRAYS) && defined(CLOUD_SHADOWS)
    {
        vec3 sunDirW = auraliteSunDir(sunPosition, shadowLightPosition);
        vec3 marchDir = (sunDirW.y > -0.02) ? sunDirW : -sunDirW;
        vec3 probe = cameraPosition + vec3(0.0, 4.0, 0.0);
        // 0.22 floor: haze near the ground is lit by the whole sky, not only by
        // the direct beam, so a cloud dims the shafts instead of switching them off.
        vCloudShadowFactor = mix(0.22, 1.0,
            auraliteGodrayCloudShadow(probe, marchDir, AUR_CLOUD_TIME));
    }
#endif
}

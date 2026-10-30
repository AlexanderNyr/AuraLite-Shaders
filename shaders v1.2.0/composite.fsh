#version 460 compatibility
/*
[v1.2.0] BUFFER FORMATS - IN BLOCK COMMENT.
-----------------------------------------------------------------------------
It was: the directives were alive, and so that GLSL did not swear at unknown names,
nearby there were stubs `#define RGBA16F 0`, etc. Iris 1.11 substitutes these
macros into the directive and receives the NUMBER 0, which is what I wrote about on each line:

    Unrecognized internal texture format 0 specified for colortex0Format, ignoring.

That is, all eight buffers silently became RGBA8: HDR scene, translucent
the normals and TAA history were losing precision, and the whole point of RGBA16F was gone.

The Iris documentation (reference/constants/buffer_format) explicitly allows holding
directive in a block comment: “the directive must either be put in a block
comment, or the format name must be otherwise manually defined." Comment
GLSL throws it away, so the compiler no longer encounters format names, and
Iris reads directives from text. The `#define ... 0` stubs have been removed.

const int colortex0Format = RGBA16F;   // albedo + fully lit scene — main HDR buffer
const int colortex1Format = RGBA16F;   // lightmap + roughness + metalness
const int colortex2Format = RGBA16F;   // packed normals + material tags
const int colortex3Format = RGBA16F;   // half-resolution HDR bloom chain
const int colortex4Format = RGBA16F;   // half-resolution HDR bloom ping-pong
const int colortex5Format = RGBA16F;   // atmosphere transmittance LUT (64x32)
const int colortex6Format = RGBA16F;   // multi-scattering / ground-bounce LUT (32x16)
const int colortex7Format = RGBA16F;   // TAA history — must be HDR + persistent
const int shadowcolor0Format = RGBA8;  // only ever LDR (tex * glcolor) from shadow.fsh
*/

const bool colortex0Clear = true;      // no stale garbage on the first frame / resize
const bool colortex5Clear = true;
const bool colortex6Clear = true;
const bool colortex7Clear = false;     // TAA history must NOT clear
// AuraLite Shaders v1.2.0 - Copyright (c) 2026 AlexanderNyr. Licensed under CC BY-NC-SA 4.0.

// ==============================================================================
// AuraLite Shader Pack - Fullscreen Composite Pass (GLSL 460)
// ------------------------------------------------------------------------------
// Water, ice and glass are drawn in a separate translucent pass; this pass lights
// every opaque surface, adds the volumetric cloud deck, the cloud shadow, the
// atmospheric haze and the godrays, and writes the HDR scene for final.fsh.
// ==============================================================================

#define SHADOWS             // [true false]
const int shadowMapResolution = 2048; // [512 1024 2048 4096 8192] - [v1.1.2] Real shadow map resolution directive (8192 for EXTREME)
#define SHADOW_SOFTNESS 2   // [1 2 3] - 1: Sharp, 2: Soft, 3: Ultra Soft
#define SHADOW_LOD 1       // [0 1 2] - 0: Off (uniform quality), 1: Balanced, 2: Aggressive — reduces samples & increases filter radius at distance
#define SHADOW_PCSS_BLUR 1 // [0 1] - 0: Disable distance/rain-based shadow blur (fixed softness). 1: Enable PCSS penumbra softening (default, fixed bounds checking).
#define DH_SHADOW_RANGE 2  // [1 2 3] - DH receiver range: 1 Seam, 2 Extended, 3 Far; no effect without Distant Horizons
#define LIGHTMAP_WARMTH 3   // [1 2 3]
#define FOG_DENSITY_LEVEL 2 // [1 2 3]
#define PBR_LIGHTING        // [true false]
#define PBR_STRENGTH 2      // [1 2 3]
#define PBR_DISTANCE 2      // [1 2 3 4] - 1: Near (16m), 2: Standard (48m), 3: Far (128m), 4: Unlimited
#define SSAO               // [true false] - EXTREME profile: screen-space ambient occlusion
#define SSAO_STRENGTH 2     // [1 2 3] - 1: Subtle, 2: Balanced, 3: Deep
#define PROCEDURAL_CLOUDS   // [true false]
#define CLOUD_MID_LAYER     // [true false] Independent mid-level cloud deck
#define CLOUD_HEIGHT 2      // [1 2 3 4] - Cloud base altitude: 1: 400 m, 2: 1200 m (typical cumulus), 3: 2400 m, 4: 3600 m
#define CLOUD_THICKNESS 2   // [1 2 3] - Deck depth as a fraction of the base altitude: 1: 0.5x, 2: 1.0x, 3: 1.5x
#define CLOUD_DISTANCE 2    // [1 2 3 4] - 1: Near, 2: Standard, 3: Far, 4: Very Far
#define CLOUD_MODE 1        // [0 1] - 0: legacy layered 2D sheets (cheapest, flattest), 1: volumetric deck with microphysics, cirrus and mid-level layers
#define CLOUD_QUALITY 2     // [1 2 3 4] - Raymarch RESOLUTION: 1: 14 steps, 2: 24, 3: 36, 4: 56
// [v1.2.0] CLOUD_DETAIL is the SHAPE FIELD resolution, independent of the
// march resolution above. Two separate numbers because they buy different things:
// CLOUD_QUALITY is how finely the volume is sampled along the ray (metres per
// step), CLOUD_DETAIL is how small a feature the field can carry (2160 m / 2^(n-1)
// = 1080 / 540 / 270 / 135 m). Tying them together -- which is what the old single
// ladder did -- meant that dropping the step count for FPS also threw away the
// shape detail, and that a player who wanted crisp cloud tops had to pay for
// steps they did not need.
#define CLOUD_DETAIL 3      // [1 2 3 4] - Shape detail: 1: 2 octaves (1080 m), 2: 3 (540), 3: 4 (270), 4: 5 (135)
#define CLOUD_COVERAGE 3    // [1 2 3 4 5] - 1: Clear skies, 2: Scattered, 3: Broken, 4: Broken to overcast, 5: Overcast
#define CLOUD_DENSITY 2     // [1 2 3] - Extinction coefficient of the cloud medium: 1: Thin (0.015/m), 2: Typical (0.030/m), 3: Dense (0.060/m)
#define CLOUD_MICRO 2       // [1 2 3] - Droplet spectrum: 1: Continental (r=6um, g=0.82), 2: Typical (r=8um, g=0.85), 3: Maritime (r=12um, g=0.87)
#define CLOUD_SCALE 2       // [1 2 3] - [v1.2.0] Cloud cell width as a multiple of the deck depth: 1: 1.2x (compact cumulus), 2: 1.8x (typical), 3: 3.0x (broad sheets)
#define CLOUD_BASE_VARIATION 2 // [1 2 3] - [v1.2.0] Spread of the condensation level between clouds: 1: Even (+-40 m), 2: Natural (+-120 m), 3: Ragged (+-250 m)
#define CLOUD_UPDRAFT 2     // [1 2 3] - [v1.2.0] Vertical speed of the cloud body: 1: Drifting (1.5 m/s), 2: Natural (2.5 m/s), 3: Vigorous (4.0 m/s). Storms multiply it.
#define CLOUD_CIRRUS        // [true false] - [v1.2.0] High cirrus veil, raymarched as a thin second deck. Off = cumulus deck only
#define CLOUD_SHADOWS       // [true false] - Procedural transparent shadows from cloud density
#define CLOUD_SHADOW_STRENGTH 2 // [1 2 3] - 1: Soft, 2: Balanced, 3: Dramatic
#define GODRAYS             // [true false] - [v1.1.0] TRUE volumetric raymarched light shafts (shadow-map occluded)
#define GODRAYS_QUALITY 1   // [1 2 3] - 1: Fast (8 samples), 2: Balanced (16), 3: High (24)
#define GODRAYS_STRENGTH 2  // [1 2 3] - 1: Subtle, 2: Balanced, 3: Dramatic

// [v1.2.0] CLOUD SHADOW RAYS - ONE PER FRAME, AND WERE COUNTED FOR EACH PIXEL.
// ------------------------------------------------------------------------------
// auraliteGodrayCloudShadow() depends on uniforms only: the probe point
// (cameraPosition + 4 blocks up) and the light direction are the same for every
// pixel of the frame. 16 density-field estimates therefore produce ONE number for
// the whole frame instead of 33 million of them at 1080p.
// The full-screen quad's vertex shader now computes that number (4 times per
// frame) and hands it over as a flat varying. Its field code is copied from this
// file by tools/gen_composite_vsh.py, so the two cannot drift. Removing the flag
// below moves the computation back into the fragment shader in one step.
#define AUR_CLOUD_SHADOW_VSH
// TAA is declared in composite1.fsh (that is the pass that implements it); this
// file only needs to stay out of its way, so it declares nothing.
#define WIND_SPEED 2        // [1 2 3] - shared with foliage/water; also controls cloud wind drift

// [v1.1.4] Shared physical-atmosphere controls. SKY_MODE=1 reuses c5/c6 LUT
// energy for terrain fog, water reflection, clouds and godrays.
#define SKY_MODE 0                 // [0 1]
#define ATMOSPHERE_TURBIDITY 2     // [1 2 3] Crisp / Balanced / Hazy
#define ATMOSPHERE_SCALE 3         // [1 2 3] 25m / 50m / 100m per block
#define GROUND_BOUNCE_MODE 0       // [0 1 2 3 4] Auto / Neutral / Vegetation / Snow / Desert

// ==============================================================================
// SUN & MOON LIGHTING - Extended customization (v0.2.1+)
// ==============================================================================
#define SUN_INTENSITY 2        // [1 2 3 4] - 1: Dim, 2: Standard, 3: Bright, 4: Blazing
#define MOON_INTENSITY 2       // [1 2 3 4] - 1: Pitch Night, 2: Standard, 3: Bright Moon, 4: Bright Night
#define SUN_TEMPERATURE 2      // [1 2 3] - 1: Cool/Neutral, 2: Realistic, 3: Warm/Golden
#define MOON_TEMPERATURE 2     // [1 2 3] - 1: Icy Blue, 2: Silver, 3: Warm Cream
const float shadowDistance = 512.0;    // [60.0 80.0 120.0 160.0 192.0 256.0 384.0 512.0 768.0] - [v1.1.4] extended DH shadow-map footprint; use SHADOW_LOD/DH_SHADOW_RANGE for quality scaling
const float shadowDistanceRenderMul = 1.0; // v1.1.2: Render shadow geometry up to shadowDistance (now extends to render distance)
#define AMBIENT_BRIGHTNESS 2   // [1 2 3] - 1: Dark Shadows, 2: Standard, 3: Lifted Shadows
#define SHADOW_TINT 2          // [1 2 3] - 1: Neutral Gray, 2: Cool Blue (realistic), 3: Warm
#define LIGHT_WRAP 1           // [1 2 3] - 1: Realistic (Lambert), 2: Soft Wrap, 3: Stylized
#define VEGETATION_CANOPY   // [true false] - [v1.2.0] Vegetation is shaded as a canopy, not as flat vertical cards
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
#define GROUND_MIST         // [true false] - Added missing define
// [v1.2.0] How thick the low radiation fog is. Standing inside the old
// layer meant staring into a 75 % white sheet: the opacity cap, the dawn boost
// and the humidity term all multiplied on top of each other. Light is now the
// default, Standard is roughly half of the old density, Heavy is for people who
// actually want to lose the horizon.
#define GROUND_MIST_DENSITY 2  // [1 2 3] - 1: Light, 2: Standard (default), 3: Heavy
#define FOLIAGE_SSS         // [true false] - Subsurface scattering for leaves and plants

// ==============================================================================
// SCREEN-SPACE REFLECTIONS (SSR) - v0.2.9
// ==============================================================================
#define SSR                 // [true false] - Screen-space reflections for water, wet surfaces and metals
#define SSR_QUALITY 2        // [1 2 3] - 1: Fast (12 steps), 2: Balanced (24 steps), 3: High (40 steps)
#define SSR_STRENGTH 2       // [1 2 3] - 1: Subtle, 2: Balanced, 3: Strong

// WATER-SELF-SHADOW GUARD, in metres.
// Water is a flat receiver that also stands in the shadow map. Its surface waves
// move by centimetres, the shadow map's depth step across a texel is centimetres
// to decimetres, and the result is water shading itself with stripes that have a
// constant period in PIXELS. The guard "lifts" the receiver above the surface by
// this many metres: a blocker closer than that is not treated as an occluder.
// Real shadows from objects above the threshold are unaffected.
const float AUR_WATER_GUARD = 0.60;   // [0.13 0.35 0.60 1.20]

// ==============================================================================
// UNDERWATER ATMOSPHERE - v0.2.9
// ==============================================================================
#define UNDERWATER_NIGHT_DARKNESS 3 // [1 2 3 4] - 1: Moonlit pool, 2: Dim, 3: True night, 4: Pitch dark

/* DRAWBUFFERS:0 */

uniform sampler2D colortex0; // Albedo / baked color from gbuffers
uniform sampler2D colortex1; // Lightmap coordinates, PBR Roughness (z), Metalness (w)
uniform sampler2D colortex2; // Normals (Packed in view space), alpha < 0.5 = emissive
uniform sampler2D colortex5; // tiny physical-atmosphere direct-transmittance LUT
uniform sampler2D colortex6; // tiny physical-atmosphere multi-scatter LUT
uniform sampler2D depthtex0; // World depth buffer
uniform sampler2D depthtex1; // Solid-only depth (no translucents) — MRT-safe water detection
uniform sampler2D shadowtex0; // Shadow depth buffer

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

// ==============================================================================
// [v1.2.0] DIRECTION OF THE SUN - OUTSIDE OF ANY CONDITIONAL COMPILATION
// ------------------------------------------------------------------------------
// The body used to sit inside `#ifdef GODRAYS`, which itself sat inside
// `#if CLOUD_MODE == 1`. With volumetric clouds switched off (`CLOUD_MODE = 0`) the
// function therefore vanished, while the atmosphere and godray code still called it,
// and Iris on ANGLE refused to link the pass:
//   composite: Fragment info
//   0(859) : error C3002: call to undefined function "vec3 auraliteSunDir(vec3, vec3);"
// The body now lives at the top of the file, after the gbufferModelViewInverse
// declaration and BEFORE the first `#if`. No menu switch (clouds, godrays, SSR,
// shadows, draw distance) can remove it any more. It depends only on
// gbufferModelViewInverse and sunPosition/shadowLightPosition.
// shadowLightPosition - ACTIVE light (Sun during the day, Moon at night). Source of truth
// for the Sun - `sunPosition`; shadowLightPosition remains only a spare
// option in the case of a zero vector from the driver.
// IMPORTANT: identical copy in gbuffers_skybasic.fsh, composite.fsh, final.fsh.

vec3 auraliteSunDir(vec3 viewSun, vec3 viewLight) {
    if (dot(viewSun, viewSun) > 1.0e-6) {
        return normalize(mat3(gbufferModelViewInverse) * normalize(viewSun));
    }
    return normalize(mat3(gbufferModelViewInverse) * normalize(viewLight));
}
uniform mat4 gbufferModelView;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;   // [v1.2.0] always the SUN, never the moon
uniform vec3 cameraPosition;      // Player's actual world coordinates
// [v1.2.0] OptiFine/Iris uniform: world position of the active lightning
// bolt, or (0,0,0) when there is none. Zero length is the "no bolt" test; a real
// bolt is never exactly at the origin of the shadow coordinate system by accident,
// and even if it were, the flash would then be centred there, which is correct.
// [v1.2.0] Iris provides THIS uniform as vec4, not vec3. At vec3 it
// I disabled it completely:
//   Wrong uniform type for lightningBoltPosition: Iris is providing VEC4 but the
//   program expects VEC3. Disabling that uniform.
// In the shader, the lightning position is the first three components.
uniform vec4 lightningBoltPosition;
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
uniform float isSwampBiome; // [v1.1.3] smoothed swamp/mangrove detector for murky underwater absorption
uniform float far; // [v1.1.2] Render distance — used for shadow LOD fade

// Distant Horizons support. DISTANT_HORIZONS is auto-defined by
// Iris on every program (including composite.fsh) when DH is active. DH keeps
// its own depth pair and projection because its near/far planes differ from
// vanilla; tex0 includes water, tex1 is the solid-only companion.
#ifdef DISTANT_HORIZONS
uniform int dhRenderDistance;
uniform sampler2D dhDepthTex0;
uniform sampler2D dhDepthTex1;
uniform mat4 dhProjectionInverse;
#endif

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
    // [v1.2.0] Radial distortion: constant angular size on screen maps to a
    // smaller area near the camera, so the shadow map spends its texels where
    // the player actually looks. This is the classic OptiFine/Iris scheme and
    // MUST stay bit-identical in shadow.vsh, otherwise casters and receivers
    // no longer land on the same texel.
    // The 0.06 offset gives more shadow-map space to the near-centre region; keep
    // it identical in all three shadow projection paths.
    float distortFactor = length(clipPos.xy) + 0.06;
    clipPos.xy /= distortFactor;
    // [v1.2.0] REMOVED `clipPos.z *= 0.5`.
    // It compressed the whole shadow frustum into NDC z in [-0.5, 0.5], i.e.
    // into only HALF of the depth buffer, so every depth bias below was
    // silently worth twice its nominal value. That lifted contact shadows off
    // the ground (peter-panning) and stopped thin geometry -- grass cards,
    // fences, leaves -- from casting anything at all. The shadow depth buffer
    // is only ever compared, never colour-blended, so the compression bought
    // nothing in return.
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
// [v1.2.0] COLOR OF MOONLIGHT – ALSO OUTSIDE CONDITIONAL COMPILATION
// ------------------------------------------------------------------------------
// Same error class as auraliteSunDir: the function was defined internally
// `#if CLOUD_MODE == 1`, and is called from the main shading (lines ~4464,
// ~4600, ~5102), which does not depend on clouds. In flat mode
// (`CLOUD_MODE = 0`, aka legacy branch v1.1.4, which needs to be saved) Iris under
// ANGLE issues C3002 “call to undefined function”. Found tools/check_guards.py
// (preprocessing + searching for calls without a body) - glslang skips this.
// The dependency is only kelvinToRGB(), declared above unconditionally.
// ==============================================================================
// ==============================================================================
// SUNLIGHT AT CLOUD ALTITUDE [v1.2.0]
// ------------------------------------------------------------------------------
// This is the fix for "clouds should be red after sunset". The pack decided how
// much sun there is from the sun's elevation as seen from the PLAYER, so the
// moment the disc touched the horizon the directional term went out and the
// clouds had no light at all -- at exactly the hour when real clouds are at
// their most spectacular. Two things were missing:
// 1. GEOMETRY. A cloud at altitude h sees the sun down to -acos(R/(R+h)). So the
//    elevation the light actually arrives at is sunElevation + depression(h),
//    not sunElevation. That is why a 2 km deck is still lit at -1.5 deg.
// 2. OPTICS. The airmass is evaluated at that corrected elevation too. At 0 deg
//    airmass is ~38 and the Rayleigh triple (0.075, 0.155, 0.375) kills blue and
//    green long before red: exp(-38 * (0.075, 0.155, 0.375)) = (0.058, 0.003,
//    6e-7). That is not a tint, that IS the red: the light reaching a high cloud
//    after sunset has passed through the whole atmosphere sideways.
// Both are computed from sunPosition (never from shadowLightPosition, which
// points at the moon after dusk) and both are per-sample, so the terminator
// across the cloud falls out for free.
// ==============================================================================
// Replace the CHROMA of a colour without changing its luminance: dividing by its
// own Rec.709 luma leaves (1,1,1) untouched, so a neutral sky stays neutral.
// [v1.2.0] MOONLIGHT IS REFLECTED SUNLIGHT, NOT A 4100 K LAMP.
// -------------------------------------------------------------------------------
// The pack lit the night with kelvinToRGB(4100) = (1.00, 0.82, 0.67), R/B = 1.49,
// and at night that is the ONLY light a cloud receives from outside: the sky
// ambient is dim enough (11-22 % of the direct term) that it cannot pull the hue
// back. Measured night cloud colour with the old constant: R/B 1.30-1.50, i.e.
// orange, which on a dark blue sky reads as red -- the "clouds are red from the
// moon" report. Strong forward scattering toward a low moon makes it worse,
// because the phase function multiplies whatever the light colour is.
// Two physical facts replace the constant:
//   1. the Moon is a reflector, so its spectrum is the Sun's (5778 K) times the
//      lunar albedo, which is close to neutral with a slight red slope --
//      geometric albedo 0.11-0.14, R/B of the reflected beam about 1.05-1.10;
//   2. a moonlit night is seen by the rod-dominated eye, whose sensitivity peaks
//      near 500 nm instead of 555 nm (Purkinje shift), so a spectrally neutral
//      scene is PERCEIVED blue-silver. The shader draws what the player sees, so
//      the neutral 5778 K beam gets a small blue bias.
// Result: R/B 1.02 for the default "Silver", 0.94 for Icy Blue, 2.27 for the
// optional Warm Cream -- and the red at night is gone rather than diluted.
vec3 auraliteMoonLightColor() {
    vec3 lunarAlbedo = vec3(1.00, 0.96, 0.91);
    float k = 5778.0;
    #if MOON_TEMPERATURE == 1
    k = 6500.0;
    #elif MOON_TEMPERATURE == 3
    k = 3200.0;
    #endif
    vec3 c = kelvinToRGB(k) * lunarAlbedo;
    #if MOON_TEMPERATURE != 3
    c *= vec3(0.92, 0.99, 1.10);   // Purkinje shift of the dark-adapted eye
    #endif
    return c;
}

// ==============================================================================
// [v1.2.0] CLOUD TIME - ALSO WITHOUT CONDITIONAL COMPILATION
// ------------------------------------------------------------------------------
// AUR_CLOUD_TIME_SCALE and AUR_CLOUD_TIME were declared inside `#if CLOUD_MODE == 1`,
// and AUR_CLOUD_TIME is used in the bogreys block (line ~3531, cloud shadow
// beam). In flat mode (`CLOUD_MODE = 0`) the macro is not declared - Iris under ANGLE
// (and glslang too) refuses to collect: `'AUR_CLOUD_TIME' : undeclared
// identifier`. Found by exhaustive search of numeric options.
// ==============================================================================
// t arrives as AUR_CLOUD_TIME (see cloudTime in the main pass), hence
// the factor 20 that turns it back into seconds.
const float AUR_CLOUD_TIME_SCALE = 20.0;

#define AUR_CLOUD_TIME (frameTimeCounter * 0.05)

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
// PHYSICAL-ATMOSPHERE SHARED FIT — sky, terrain fog, water and volumetrics
// ==============================================================================
float atmosphereMetersPerBlock() {
    #if ATMOSPHERE_SCALE == 1
    return 25.0;
    #elif ATMOSPHERE_SCALE == 2
    return 50.0;
    #else
    return 100.0;
    #endif
}

float atmosphereBaseTurbidity() {
    #if ATMOSPHERE_TURBIDITY == 1
    return 0.62;
    #elif ATMOSPHERE_TURBIDITY == 3
    return 1.70;
    #else
    return 1.00;
    #endif
}

float atmosphereMieScale() {
    float weatherHaze = mix(1.0, 2.35, rainStrength);
    weatherHaze = mix(weatherHaze, weatherHaze * 1.28, thunderStrength * rainStrength);
    return atmosphereBaseTurbidity() * weatherHaze;
}

float atmosphereAltitude() {
    return clamp(max(0.0, cameraPosition.y - 63.0) * atmosphereMetersPerBlock(), 0.0, 30000.0);
}

// [v1.2.0] Mirrors twilightGroundLight() in gbuffers_skybasic.fsh. The ground,
// fog and water keep following the sky through civil, nautical and astronomical
// twilight instead of snapping to black at -6 deg. Returns 0..1 relative to the
// sunset illuminance, from the published photometric curve.
float twilightGroundLight(float sunY) {
    float elevDeg = degrees(asin(clamp(sunY, -1.0, 1.0)));
    const float LUX_DAY = 120000.0;
    const float LUX_REF = 400.0;
    float lCivil = exp(mix(log(LUX_DAY), log(3.4), clamp((15.0 - elevDeg) / 21.0, 0.0, 1.0)));
    float lNaut  = exp(mix(log(3.4), log(0.008), clamp((-6.0 - elevDeg) / 6.0, 0.0, 1.0)));
    float lAstr  = exp(mix(log(0.008), log(0.0006), clamp((-12.0 - elevDeg) / 6.0, 0.0, 1.0)));
    float lx = (elevDeg >= -6.0) ? lCivil : ((elevDeg >= -12.0) ? lNaut : lAstr);
    return clamp(pow(max(lx, 0.0006) / LUX_REF, 0.22), 0.0, 1.0);
}

vec2 atmosphereLutUV(float sunY) {
    return vec2(clamp((sunY + 0.16) / 1.16, 0.0, 1.0), atmosphereAltitude() / 30000.0);
}

vec3 physicalSunTransmittance(float sunY) {
    return texture(colortex5, atmosphereLutUV(sunY)).rgb;
}

vec3 physicalMultiScatter(float sunY) {
    // Prevent a stale/low-frequency LUT contribution from brightening physical
    // night fog, water or godrays after the sun is below civil twilight.
    // [v1.2.0] Soft twilight ramp, identical to the sky shader. The 0.42 factor
    // matches SKY_EXPOSURE in gbuffers_skybasic so fog/water reflections stay on
    // the same photometric footing as the sky they are reflecting.
    return texture(colortex6, atmosphereLutUV(sunY)).rgb * smoothstep(-0.20, -0.03, sunY) * 0.55;
}

vec3 physicalGroundBounceAlbedo() {
    vec3 neutral = vec3(0.18, 0.16, 0.13);
    #if GROUND_BOUNCE_MODE == 1
    return neutral;
    #elif GROUND_BOUNCE_MODE == 2
    return vec3(0.13, 0.21, 0.11);
    #elif GROUND_BOUNCE_MODE == 3
    return vec3(0.52, 0.58, 0.66);
    #elif GROUND_BOUNCE_MODE == 4
    return vec3(0.34, 0.25, 0.14);
    #else
    vec3 vegetation = vec3(0.13, 0.21, 0.11);
    vec3 snow = vec3(0.52, 0.58, 0.66);
    vec3 swamp = vec3(0.10, 0.18, 0.09);
    vec3 result = mix(neutral, vegetation, 0.46);
    result = mix(result, snow, clamp(auroraColdBiome, 0.0, 1.0) * 0.72);
    return mix(result, swamp, clamp(isSwampBiome, 0.0, 1.0) * 0.60);
    #endif
}

vec3 physicalSunRadiance(vec3 sunWorldDir) {
    float sunHigh = smoothstep(-0.10, 0.05, sunWorldDir.y);
    vec3 direct = physicalSunTransmittance(sunWorldDir.y) * vec3(1.0, 0.96, 0.90);
    vec3 twilight = vec3(1.0, 0.34, 0.10) * smoothstep(-0.16, 0.02, sunWorldDir.y);
    return mix(twilight, direct, smoothstep(-0.02, 0.22, sunWorldDir.y)) * sunHigh;
}

// Fast directional fit used outside the sky G-buffer. It shares the LUT sun
// transmittance/multi-scatter/weather parameters without running a second full
// atmosphere ray march for every terrain fragment.
// [v1.2.0] ATTEMPTED AND REVERTED: replacing this with a cheap analytic
// single-scatter evaluation of the real atmosphere. It was measured against the
// sky pass's own march (see the table in report 2.23): 3-12 % agreement by day,
// but 50-100 % too dark through civil twilight, because the twilight sky is lit
// by the part of the ray ABOVE the terminator (20-60 km), which an effective-layer
// approximation cannot represent. Running the real march per terrain pixel costs
// ~48 exponential evaluations per pixel. The physically correct fix is a baked
// sky-view LUT (direction x solar elevation) computed once per frame; that is a
// separate pass and is not in this build. Until then the fitted gradient stays,
// and it is explicitly labelled as a fit, not as physics.
vec3 physicalSkyRadianceApprox(vec3 worldDirection, vec3 sunWorldDir, float physicalDay) {
    float up = clamp(worldDirection.y, 0.0, 1.0);
    float sunHigh = smoothstep(-0.08, 0.30, sunWorldDir.y);
    float haze = clamp((atmosphereMieScale() - 0.55) / 2.40, 0.0, 1.0);
    vec3 zenith = mix(vec3(0.008, 0.018, 0.050), vec3(0.055, 0.22, 0.62), physicalDay);
    vec3 horizon = mix(vec3(0.012, 0.018, 0.038), vec3(0.50, 0.64, 0.82), physicalDay);
    horizon = mix(horizon, vec3(0.42, 0.46, 0.50), haze * physicalDay);
    vec3 sky = mix(horizon, zenith, pow(up, mix(0.72, 1.10, haze)));
    float forward = pow(clamp(dot(worldDirection, sunWorldDir), 0.0, 1.0), mix(14.0, 5.5, haze));
    vec3 sunColor = physicalSunRadiance(sunWorldDir);
    sky += sunColor * forward * mix(0.14, 0.52, haze);
    sky += physicalMultiScatter(sunWorldDir.y) * mix(0.20, 0.70, up);
    return max(sky, vec3(0.0));
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

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0,0.0)), hash(i + vec2(1.0,0.0)), u.x),
               mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), u.x), u.y);
}

// ==============================================================================
// 3D VALUE NOISE [v1.2.0]
// ------------------------------------------------------------------------------
// The cloud field used to be a 2D noise in the XZ plane, varyied with height only
// by sliding that plane diagonally (uv += vec2(h * 0.42, -h * 0.28)). A vertical
// slice through the deck was therefore the SAME pattern repeated at every
// altitude, displaced by at most half a cell across a whole kilometre. That is
// exactly what a cloud deck must not be, and it is what the user was seeing:
//  - columns of identical density standing through the deck read as flat slabs
//    with rectangular tops ("cubic");
//  - those columns are displaced along one diagonal, so their edges line up along
//    that diagonal in perspective ("diagonal").
// There is no amount of erosion that fixes this, because the information simply
// is not in the field. The shape has to be genuinely three-dimensional.
// Five operations replace the slide: a 3D value noise (8 corner hashes, quintic
// interpolation for C2 continuity -- smoothstep leaves visible creases in the
// gradient, which show up as facets on a lit cloud), the octaves are axis
// PERMUTED instead of rotated (a rotation of 3D noise costs 9 multiplies and buys
// nothing a permutation does not), and the octave offsets are irrational-ish so
// that lattice planes never coincide.
// ==============================================================================
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

// Octave permutation: (x,y,z) -> (y,z,x) -> (z,x,y). Keeps the lattice from
// repeating along any single axis without a matrix multiply.
vec3 auralitePermute(vec3 p, int k) {
    if (k == 1) return p.yzx;
    if (k == 2) return p.zxy;
    return p;
}

// Normalised: the octave amplitude is divided by the total, so dropping an
// octave on the cheaper presets changes the DETAIL of the field and not its mean.
// That matters because every coverage preset is a threshold on this field: if the
// mean moved with CLOUD_QUALITY, the same CLOUD_COVERAGE would give a different sky
// on MED and ULTRA.
// [v1.2.0] WEIGHT THE OCTAVES FOR WHAT THE EYE SEES, AND NORMALISE BY
// SPREAD RATHER THAN BY SUM.
// ------------------------------------------------------------------------------
// Two changes, both measured.
// 1. THE AMPLITUDES. The 1/f series 0.5 / 0.25 / 0.125 puts 80 % of the energy in
//    the first octave, so the erosion inside a cloud body barely registered: the
//    fine octaves were there, but three times weaker than the shape they were
//    supposed to break up. 0.50 / 0.35 / 0.25 raises the second octave by 40 % and
//    the third by 100 %. Measured boundary complexity (perimeter over area of the
//    coverage contour, 6 x 6 km slice): 0.0405 -> 0.0413.
// 2. THE NORMALISATION. Dividing by the SUM of the amplitudes normalises the mean
//    but not the spread: with two octaves the field came out at sigma 0.148 and
//    with three at 0.124. Since every coverage preset is a threshold on this
//    field, CLOUD_QUALITY silently changed how much sky was covered -- MED and
//    ULTRA drew different weather. Dividing by sqrt(sum a^2) gives the same mean
//    AND the same spread for any octave count (measured: 0.1205 with two octaves,
//    0.1201 with three), so a preset means the same thing on every profile. The
//    0.583 is the single calibration constant that puts the spread at 0.12, which
//    is where the coverage thresholds were measured.
// A domain warp (displacing the higher octaves by the first one) was tried here
// as well, on the theory that it would make the structure deform instead of
// sliding rigidly when the updraft moves. Measured: temporal correlation after
// 30 s of updraft 0.882 without the warp and 0.875 with it -- no difference, and
// boundary complexity got slightly WORSE (0.0413 -> 0.0395). It was removed
// rather than kept as an unverifiable flourish.
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

// Billow in 3D: 1 - |2n - 1| folds the field into domes, which is what an eroded
// cumulus edge actually looks like. Two octaves, second one larger-scale so the
// outline is broken at more than one size.
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
    // [v1.2.0] Was mix(1.25, 1.85): the first drop of rain made the whole
    // sky deck lurch into fast-forward. Weather now adds a fraction, not a gear.
    return mix(speed, speed * mix(1.08, 1.30, thunderStrength), rainStrength);
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

// [v1.1.1] Performance-neutral pseudo-3D cloud domain.
// True lattice 3D noise costs far more ALU. Instead, feed world height into the
// existing 2D noise/fbm domains via vertical shear + layer-local offset. This
// keeps the exact same number of noise/fbm calls while breaking the old flat
// 2D-sheet look: cloud density changes coherently through Y as the ray marches.
vec2 cloud3DDomain(vec2 xz, float y, float layerT, vec2 shear, vec2 loft) {
    return xz + y * shear + layerT * loft;
}

// ==============================================================================
// TRUE VOLUMETRIC CLOUDS [v1.2.0]
// ------------------------------------------------------------------------------
// Everything below draws clouds by marching a 3D density field. There are no
// billboard planes and no 2D sheets left in this path: the cumulus deck and the
// cirrus deck are both raymarched, the cirrus one just thinner and cheaper.
// (The old four-layer 2D system still exists behind CLOUD_MODE = 0.)
// Integration is the analytic single-scattering solution over each segment:
//     L += T * S * (1 - exp(-sigma*ds)),    T *= exp(-sigma*ds)
// so thick parts converge to opaque by themselves, without a tuned cap.
// Light response:
//   * sun colour comes from the caller (Kelvin + extinction, warm at twilight),
//     moon colour likewise -- the medium scatters whatever colour hits it;
//   * lightning lights the cloud from the inside during a thunderstorm;
//   * terrain/mountains shadow the cloud through one shadow-map tap along the
//     light ray, so a low deck behind a mountain is not lit through it;
//   * sky ambient follows the time of day instead of a fixed day/night triplet.
// Physical constants (report 2.19/2.20): cloud droplets scatter with almost no
// absorption, g ~ 0.83-0.87 (Kokhanovsky), visible extinction 0.005-0.1 1/m.
// ==============================================================================
#if CLOUD_MODE == 1

// ==============================================================================
// CLOUD DECK GEOMETRY IN METRES [v1.2.0]
// ------------------------------------------------------------------------------
// The deck used to be pinned to 110/160/240 blocks, i.e. 150-250 m above the
// player, which is where Minecraft puts its own clouds and nowhere near where
// weather happens: fair-weather cumulus has a base at 1000-2000 m. A ray march
// can be drawn at any altitude -- it is a screen-space integral, not a block --
// so nothing stopped the pack from putting it at a real height except the old
// constants. Now the deck is defined in metres and everything else follows:
//   * base   400 / 1200 / 2400 / 3600 m by CLOUD_HEIGHT (1200 m = typical
//            cumulus base over land, which is the default);
//   * depth  base x 0.5 / 1.0 / 1.5 by CLOUD_THICKNESS (fair-weather cumulus is
//            500-1500 m deep; congestus and cumulonimbus are several km);
//   * the noise scale is divided by the altitude, so raising the deck does not
//            shrink the clouds into puffs: one noise cell keeps its angular size;
//   * render distance grows with it, and the far end fades into the sky by
//            aerial perspective, which is what hides the edge of the deck;
//   * a storm lowers the base by 12 % and deepens it by 28 %.
// ==============================================================================
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

// [v1.2.0] Horizontal size of one cloud cell.
// ------------------------------------------------------------------------------
// The field used to be pinned to the ALTITUDE (0.26 / alt), which once the deck
// moved from 160 m to 1200 m made a cell 4.6 km wide against a 1.2 km deep deck:
// an aspect ratio of about four. Real cumulus are roughly as wide as they are
// deep (humilis 1-2, congestus 2-4), so both ends of that range are physical and
// which one you want is a taste decision the menu should own -- hence CLOUD_SCALE.
// What is NOT a taste decision is tying the noise to the deck DEPTH instead of
// the base altitude, because the depth is what the cell has to resemble.
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

// Cirrus is a different family and keeps its own (much larger) scale: a veil is
// tens of kilometres across, not one cumulus.
float auraliteCirrusUvScale(float alt) {
    return 0.26 / max(alt, 1.0);
}

float auraliteCloudRenderDistance() {
    float d = 12000.0;
    #if CLOUD_DISTANCE == 1
    d = 6000.0;
    #elif CLOUD_DISTANCE == 3
    d = 20000.0;
    #elif CLOUD_DISTANCE == 4
    d = 32000.0;
    #endif
    return d;
}

// ==============================================================================
// CLOUD MICROPHYSICS [v1.2.0]
// ------------------------------------------------------------------------------
// The extinction of a droplet cloud follows from its liquid water content and its
// droplet size, not from a tuned constant:
//     sigma_ext = 3 * LWC * Q_ext / (4 * rho_w * r_eff)
// with Q_ext ~ 2.1 for droplets much larger than the wavelength and rho_w = 1000
// kg/m3. Cross-check against Kokhanovsky's worked example: LWC 0.4 g/m3 with an
// effective radius of 6 um gives 3*0.4e-3*2.1/(4*1000*6e-6) = 0.105 1/m, which is
// exactly the 0.1 1/m upper bound quoted for water clouds.
// CLOUD_DENSITY now selects a liquid water content instead of a raw coefficient:
// 0.075 / 0.15 / 0.30 g/m3, which at r_eff = 8 um gives the 0.015 / 0.030 / 0.060
// 1/m the pack already rendered with. The noise field multiplies this by 0..1, so
// a cloud CORE carries the preset value and the volume average is about 0.4x of
// it. That is why these read low against the 0.25-0.30 g/m3 quoted for fair
// weather cumulus: they are the reservoir the field draws from, and
// CLOUD_DENSITY = 3 puts the core at the observed value.
// CLOUD_MICRO selects the droplet spectrum. Smaller droplets (continental air,
// many nuclei) scatter more per gram and forward-scatter less; larger ones
// (maritime) are the opposite. g stays inside the measured 0.83-0.87 band.
// ==============================================================================
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

// Asymmetry parameter of the droplet phase function, inside the measured band.
float auraliteCloudAsymmetry() {
    float g = 0.85;
    #if CLOUD_MICRO == 1
    g = 0.82;
    #elif CLOUD_MICRO == 3
    g = 0.87;
    #endif
    return g;
}

float auraliteCloudExtinction() {
    // Q_ext ~ 2.1, the extinction efficiency of a large water droplet
    return 3.0 * auraliteCloudLwc() * 2.1 / (4.0 * 1000.0 * auraliteCloudEffectiveRadius());
}

// Cirrus is a different medium: ice crystals, LWC ~0.03 g/m3 (against 0.25-0.30
// for cumulus) and an effective radius of ~25 um, with Q_ext ~2.0 for crystals
// much larger than the wavelength. That gives sigma ~0.0018 1/m, i.e. an optical
// depth of order 1 across a 2 km veil after the density field is applied -- which
// is what cirrus actually is. It used to share the water-cloud coefficient scaled
// by 0.55, which put it at an optical depth around 10: a grey lid, not a veil.
float auraliteCirrusExtinction() {
    // [v1.2.0] Cirrus water content spans 0.01-0.1 g/m3 (thin to thick
    // veil); 0.03 g/m3 sits at the thin end of that range and gave a
    // veil so faint that the high deck effectively disappeared from the sky. 0.09
    // is the same measurement's upper bound and still an order of magnitude below
    // cumulus, so it is a choice INSIDE the physical range rather than a fudge --
    // and the density field multiplies it by at most 0.30 anyway.
    return 3.0 * 0.09e-3 * 2.0 / (4.0 * 1000.0 * 25.0e-6);
}

// Coverage is a threshold on the shape noise: it changes cloud FRACTION, not
// brightness. Rain lowers the threshold, so overcast builds as the storm arrives.
// [v1.2.0] COVERAGE CORRECTION FOR THE OCTAVE COUNT.
// ------------------------------------------------------------------------------
// Normalising the field by sqrt(sum a^2) keeps its standard deviation constant
// across presets (0.1216 / 0.1213 / 0.1209 / 0.1207 for 2..5 octaves), but the
// SHAPE of the distribution still changes: more octaves means a smoother, less
// skewed field, and coverage is a threshold on it, so the same threshold closes a
// different amount of sky. Measured: 38.0 / 40.1 / 47.2 / 50.6 % of columns for
// 2..5 octaves at the Broken threshold -- i.e. ULTRA would have drawn a noticeably
// cloudier sky than MED with identical settings.
// Each preset therefore carries the offset that returns it to 40 % (measured by
// bisection on the same 16 x 16 km sample). This is the price of a real resolution
// ladder, and it is paid with one constant per preset instead of a wobbly weather
// state.
// [v1.2.0] The octave count comes from CLOUD_DETAIL, NOT from CLOUD_QUALITY.
// The two are deliberately decoupled, and that is the whole point of the split: a
// player on a weak GPU can keep five octaves (crisp cloud tops, 135 m features)
// and drop the march to 14 steps, or keep 56 steps and drop detail. The cost of
// each is knowable, because the two multiply -- see the table in the report.
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

int auraliteCloudSteps() {
    int steps = 24;
    #if CLOUD_QUALITY == 1
    steps = 14;
    #elif CLOUD_QUALITY == 3
    steps = 36;
    #elif CLOUD_QUALITY == 4
    steps = 56;
    #endif
    return steps;
}

// Steps of the light march. Each one is a full density evaluation inside the
// primary loop, so this scales more gently than CLOUD_QUALITY.
int auraliteCloudLightSteps() {
    int steps = 2;
    #if CLOUD_QUALITY == 3
    steps = 3;
    #elif CLOUD_QUALITY == 4
    steps = 4;
    #endif
    return steps;
}

// Cirrus is optically thin, so it needs far fewer samples than cumulus. The deck
// is still marched, not a plane -- a plane was what used to hang visibly above
// the volumetric cumulus and gave the whole thing away.
int auraliteCirrusSteps() {
    int steps = 4;
    #if CLOUD_QUALITY == 3
    steps = 6;
    #elif CLOUD_QUALITY == 4
    steps = 8;
    #endif
    return steps;
}

// [v1.2.0] Wind is a VELOCITY IN METRES PER SECOND, converted into noise
// cells with the same scale the field uses.
// ------------------------------------------------------------------------------
// It used to be a drift in noise units (0.178, 0.083) per unit of time. That
// looks harmless until the mapping changes: at a 160 m deck one noise unit was
// 615 m, so the sky moved at 5.5 m/s, and at a 1200 m deck the same numbers meant
// 41 m/s -- 148 km/h, a hurricane, because the deck had moved up and the noise
// had grown with it. With the old cell size the same constants would have reached
// 88 m/s. A velocity cannot be expressed in units whose size depends on the deck.
// 11 / 5.2 m/s is 12.2 m/s: an ordinary free-atmosphere wind on a cumulus day.
// [v1.2.0] Moved AUR_CLOUD_TIME_SCALE and AUR_CLOUD_TIME to the beginning of the file.

vec2 auraliteCloudWind(float t) {
    return vec2(11.0, 5.2) * (t * AUR_CLOUD_TIME_SCALE * getCloudWindSpeedMultiplier());
}

// ==============================================================================
// UPDRAFTS: THE CLOUD BODY RISES [v1.2.0]
// ------------------------------------------------------------------------------
// Until now the shape field only moved horizontally: wind advected it, and a
// cloud looked like a photograph sliding across the sky. Real cumulus are
// conveyor belts: air enters at the flat base, rises at 1-3 m/s in fair weather
// (20-30 m/s in a cumulonimbus core), and leaves at the top. The visible effect
// is not that the whole cloud translates upward -- the slab keeps it in place --
// but that the STRUCTURE streams upward through it: corners round off, domes
// grow and dissolve, the top edge is continuously replaced. That is what
// "boiling" looks like, and it falls out for free once the vertical coordinate
// of the noise is allowed to advance: the profile still decides where the cloud
// is, while the field inside it keeps moving.
// Cost: zero extra samples. It is one addition to a coordinate that was already
// being computed.
// ==============================================================================
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

// Cirrus sits at 8 km where the wind is three times stronger, and moves with it.
vec2 auraliteCirrusWind(float t) {
    return vec2(26.0, 9.0) * (t * AUR_CLOUD_TIME_SCALE * getCloudWindSpeedMultiplier());
}

// Interleaved gradient noise (Jimenez 2014). Used ONLY to offset the start of the
// ray by a fraction of a step: without it a fixed step grid shows the deck as
// concentric bands. It is static per pixel on purpose -- a per-frame dither would
// shimmer, because this pack has no TAA by default.
// Lightning. A storm does not add a point light you can see, it lights the cloud
// from the inside. The envelope is a main stroke plus one restrike, which is the
// shape of a real return stroke on a time axis; thunderStrength gates it, so in
// clear weather this returns exactly 0.
float auraliteLightningFlash(float t) {
    float storm = rainStrength * thunderStrength;
    if (storm <= 0.004) return 0.0;
    float rate = 0.7;                                 // ~1.4 s slots
    float slot = floor(t * rate);
    float rnd = fract(sin(slot * 127.1 + 311.7) * 43758.5453);
    float flashGate = step(0.55, rnd) * storm;
    float local = fract(t * rate);
    float stroke = exp(-local * 24.0);
    float restrike = 0.55 * exp(-max(local - 0.16, 0.0) * 34.0) * step(0.16, local);
    return clamp((stroke + restrike) * flashGate, 0.0, 1.0);
}

// ==============================================================================
// THE TERMINATOR [v1.2.0]
// ------------------------------------------------------------------------------
// Why cloud tops go red at sunset while their bases go blue-grey: it is not a
// tint, it is the Earth's shadow. A point at altitude h still sees the sun while
// the sun is up to acos(R/(R+h)) BELOW the geometric horizon, because the horizon
// itself drops with altitude. So as the sun sinks, the shadow boundary climbs
// through the cloud: bases stop being lit first, tops last. The last lit parts
// are lit by the reddest light of the whole day, which is why they glow orange.
// At a real 2 km that window is 1.43 deg wide, at 9 km it is 3.05 deg -- the
// difference between a base going dark and a top going dark is the whole effect.
// [v1.2.0] No metre-mapping is needed any more: the deck is DRAWN at a real
// altitude (auraliteCloudBaseAltitude, 1200 m by default), so a sample's own world
// height is already the altitude at which the light arrives. The deck used to sit
// at 160 blocks, which compressed the troposphere by a factor of about seven and
// shrank the terminator window from ~2 deg to ~0.3 deg, making the effect
// invisible. That compression is gone.
// ==============================================================================
// Horizon depression of a point at altitude altM, in degrees.
float auraliteHorizonDepression(float altM) {
    const float earthRadius = 6371000.0;
    return degrees(acos(clamp(earthRadius / (earthRadius + max(altM, 0.0)), -1.0, 1.0)));
}

// Is this altitude still in sunlight? The solar disk is 0.53 deg across, so the
// transition ramps over its radius (0.266) instead of switching on a line -- a
// hard edge would show as a razor band across the cloud.
float auraliteCloudSunlit(vec3 sunDir, float altM) {
    // [v1.2.0] The width used to be +-0.266 deg, which is only the sun's own
    // disk. Three real effects widen the terminator of a cloud deck: the disk
    // (+-0.27), refraction, which lifts the sun by up to ~0.5 deg at the horizon,
    // and the deck's own thickness, because its base reaches its horizon before its
    // top (0.3-0.5 deg across 1.2 km). +-0.55 is the sum of those, so the beam now
    // fades over ~1.1 deg of solar elevation instead of snapping out in 7 seconds
    // of real time -- which is what the last red of a sunset actually looks like.
    float sunElev = degrees(asin(clamp(sunDir.y, -1.0, 1.0)));
    float depression = auraliteHorizonDepression(altM);
    return smoothstep(-depression - 0.55, -depression + 0.55, sunElev);
}

// [v1.2.0] Moved the body higher, right after kelvinToRGB().

vec3 auraliteHueAtSameLuma(vec3 c) {
    return c / max(dot(c, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
}

// Move a colour's hue toward targetHue by `amt`, then scale it back to its own
// original luminance. A tint must never double as a brightness knob, otherwise
// "make it redder" silently becomes "make it brighter".
vec3 auraliteTintAmbient(vec3 baseColor, vec3 targetHue, float amt) {
    float baseLuma = dot(baseColor, vec3(0.2126, 0.7152, 0.0722));
    if (baseLuma <= 1e-5 || amt <= 0.001) return baseColor;
    vec3 baseHue = auraliteHueAtSameLuma(max(baseColor, vec3(1e-4)));
    // [v1.2.0] The ratio is clamped to a factor of 2 in either direction.
    // A sunset hue has a near-zero blue channel, so an unclamped ratio could
    // multiply blue by ~0 and -- after the luminance renormalisation below --
    // scale red and green up until the cloud was a saturated red sheet. A hue
    // shift must never be able to crush a channel to zero.
    vec3 relative = clamp(targetHue / max(baseHue, vec3(1e-4)), vec3(0.5), vec3(2.0));
    vec3 tinted = baseColor * mix(vec3(1.0), relative, clamp(amt, 0.0, 1.0));
    return tinted * (baseLuma / max(dot(tinted, vec3(0.2126, 0.7152, 0.0722)), 1e-5));
}

float auraliteCloudEffectiveSunSin(float sunY, float altM) {
    float depression = radians(auraliteHorizonDepression(altM));
    float horizontal = sqrt(max(1.0 - sunY * sunY, 0.0));
    return clamp(sunY + sin(depression) * horizontal, -1.0, 1.0);
}

// Rayleigh column of the whole atmosphere above the cloud deck, using the SAME
// coefficients the sky pass integrates (5.802 / 13.558 / 33.1 e-6 1/m at 8 km).
// This replaces a hand-picked (0.075, 0.155, 0.375) "airmass triple": a triple
// like that is only correct for one particular airmass, while the real column
// scales with a scale height and therefore with the sun's elevation. Cloud
// reddening and sky reddening are now literally the same computation.
const vec3  AUR_BETA_R  = vec3(5.802e-6, 13.558e-6, 33.1e-6);
const vec3  AUR_BETA_M  = vec3(3.996e-6);
const vec3  AUR_BETA_MA = vec3(0.444e-6);
const vec3  AUR_BETA_O3 = vec3(0.650e-6, 1.881e-6, 0.085e-6);
const float AUR_H_R = 8000.0;    // m, Rayleigh scale height
const float AUR_H_M = 1200.0;
// [v1.2.0] Reach of the high cirrus deck, in metres -- AND WHY IT WOULD
// OTHERWISE STAY INVISIBLE.
// ------------------------------------------------------------------------------
// It is tempting to give the cirrus its own reach (40 km) on the premise that a sky pixel is
// passed a huge `terrainDist`, so `terrainDist > 100000.0` would identify open sky.
// It does not: the SKY call site passes getCloudRenderDistance(), which is 3 / 6 /
// 10 / 16 km by CLOUD_DISTANCE. At the default (2) that is 6 km, so
// maxDist = min(renderDistance, terrainDist) = 6 km, and a deck at 6.5 km needs
// 6.5 / sin(pitch) metres just to be ENTERED. The ray never reached it at any
// pitch and the returned alpha was exactly 0.0 over the whole sky. The layer was
// not faint: it was geometrically unreachable. Measured through the real march,
// mean opacity with the old cap: 0.000 at 22, 45 and 90 degrees; once the deck is
// actually reached: 0.42 / 0.34 / 0.19.
// The reach is therefore no longer inferred from a sentinel distance: the sky path
// says outright that it is sky (`skyPixel`), and terrain paths keep their own cap
// so the deck still cannot be composited in front of a mountain.
// 32 km, not 40 km: the lower edge of a 6.5 km deck sits at asin(6500/32000) =
// 11.7 deg, and the density fade takes it to zero by ~14 deg, which is a smooth
// belt of thinning veil instead of a cut. At 40 km the edge drops to 9.2 deg, the
// path through the layer at that angle is 8.5 km long, and the sheet saturates into
// a bright white lid just above the horizon (measured mean opacity 0.55 at 15 deg
// against 0.14 at the same angle with 32 km).
const float AUR_CIRRUS_REACH = 32000.0;   // m, reach of the cirrus deck
const float AUR_O3_COLUMN = 15000.0; // m of unit density (25 +- 15 km tent)

// Transmittance from a cloud at altitude altM toward a sun of elevation effSin.
vec3 auraliteAtmosphereTransmittance(float effSin, float altM) {
    float am = getAirmass(clamp(effSin, 0.0, 1.0));
    float odR = AUR_H_R * exp(-altM / AUR_H_R) * am;
    float odM = AUR_H_M * exp(-altM / AUR_H_M) * am * atmosphereMieScale();
    float odO3 = AUR_O3_COLUMN * am;
    return exp(-(AUR_BETA_R * odR + (AUR_BETA_M + AUR_BETA_MA) * odM + AUR_BETA_O3 * odO3));
}

vec3 auraliteCloudSunRadiance(float effSin, float sunsetFactor, float altM) {
    float s = clamp(effSin, 0.015, 1.0);
    // [v1.2.0] THE REDDENING WAS COUNTED TWICE, AND THE SECOND COPY WAS
    // THE ONE THAT MADE CLOUDS *RED* RATHER THAN *GOLD*.
    // ---------------------------------------------------------------------------
    // Two independent mechanisms redden the light that reaches a cloud at sunset:
    //   1. the Sun's own colour vs elevation -- getSolarKelvin(), 2200 K at the
    //      horizon up to 5700 K at the zenith;
    //   2. Rayleigh + Mie extinction along the path -- auraliteAtmosphereTransmittance,
    //      which removes far more blue than red (beta_B / beta_R = 5.7).
    // Both are already here. On top of them this line forced the temperature down to
    // 1850 K over the whole sunset window -- a SECOND reddening, twice as strong as
    // either real one, applied for two in-game hours.
    // 1850 K is also below kelvinToRGB's blue cutoff (k < 1900 K returns blue = 0),
    // so the direct beam on a cloud had EXACTLY ZERO blue: measured R/B = 161 at a
    // 3 degree sun, against 16.6 with the real mechanisms alone. A light with no
    // blue cannot be anything but red -- and because the phase function then scales
    // it, the same cloud swung from R/B 2.9 looking up to 14.3 looking toward the
    // sun. That swing with view angle is the "clouds turn red when I look up"
    // report, and no amount of work on the ambient or the haze could remove it,
    // because it was never in the ambient: it was in the colour of the sunlight.
    // Removing the double count: R/B 2.6 ... 8.2, i.e. gold near the sun and
    // blue-grey away from it, which is what a sunset photograph actually shows.
    float k = getSolarKelvin(s);
    vec3 extinction = auraliteAtmosphereTransmittance(s, altM);
    // NOTE: no "sunset floor" here on purpose. The pack lifts the ground-level
    // sunset extinction toward 0.36 on every channel so the horizon glow does not
    // die; doing that to cloud light would pour green and blue back into it and
    // turn the red grey. The red on a high cloud after sunset IS the missing
    // green and blue, so the raw Rayleigh extinction has to stand.
    return kelvinToRGB(k) * extinction * 2.6;
}

// How strongly a bolt at boltPos lights a point inside the cloud. Lightning is a
// local source: the channel is a few centimetres wide but tens of kilometres long,
// and what lights the cloud is the light scattered inside it. A 1/(1+d^2) falloff
// with a 900 m scale reproduces "bright around the bolt, gone across the cell"
// without pretending to be a radiative transfer integral.
float auraliteBoltProximity(vec3 p) {
    vec3 d = p - lightningBoltPosition.xyz;
    float dist2 = dot(d, d);
    return 1.0 / (1.0 + dist2 / 810000.0);   // 900 m
}

// One shadow-map tap: does terrain stand between this cloud sample and the sun?
// One tap, not sampleShadow()'s PCSS gather -- a mountain edge on a cloud at
// 300 m does not need soft penumbra, and the clouds already run 24-56 steps.
float auraliteCloudTerrainVisibility(vec3 worldPos) {
    #ifndef SHADOWS
    return 1.0;
    #else
    vec3 shadowViewPos = (shadowModelView * vec4(worldPos, 1.0)).xyz;
    vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
    shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
    vec3 ndc = shadowClipPos.xyz / shadowClipPos.w;
    vec3 spos = ndc * 0.5 + 0.5;
    if (spos.x < 0.0 || spos.x > 1.0 || spos.y < 0.0 || spos.y > 1.0 ||
        spos.z < 0.0 || spos.z > 1.0) {
        return 1.0;                                   // outside the map: nothing to hit
    }
    float worldToShadowDepth = max(0.5 * abs(shadowProjection[2][2]), 1e-9);
    float occluder = texture(shadowtex0, spos.xy).r;
    // 6 m of lift in depth units: clouds are hundreds of metres above terrain, so
    // only a real silhouette should count, never depth quantisation.
    return occluder < spos.z - 6.0 * worldToShadowDepth ? 0.0 : 1.0;
    #endif
}

// The cumulus density field. `withDetail` drops the erosion octave for the light
// march: the shadow only needs the shape, and that halves the cost of every step.
// ==============================================================================
// THE CONDENSATION LEVEL IS NOT ONE PLANE [v1.2.0]
// ------------------------------------------------------------------------------
// A cumulus base is flat, and that is not an artefact: rising air cools at the
// dry adiabatic lapse rate and reaches saturation at the lifting condensation
// level, which is (surface temperature - dew point) / 4.4 * 1000 ft. Because
// surface temperature and humidity are fairly uniform over a region, every
// thermal in it condenses at nearly the same height, and a field of cumulus
// shares one visibly level floor.
// What the pack had was not that. It had ONE plane for the whole sky: every
// sample used the same cloudMinY, so every cloud in every direction sat on the
// same shelf, and because the base ramp faded density over 12 % of the deck
// (144 m at the default) instead of switching on at the condensation level, the
// underside read as a soft sheet rather than as a cloud floor.
// Two things are therefore wrong and both are measurable:
//   * THE HEIGHT does not vary. The lifting condensation level is not constant
//     over tens of kilometres -- it follows surface temperature and moisture, so
//     it drifts by tens to hundreds of metres, which is why a real sky is a
//     ragged field of bases and not one shelf.
//   * THE EDGE is a gradient instead of a boundary. Condensation switches on
//     over a few tens of metres (turbulent activation blurs it, but not over
//     144 m), so the base is a boundary with a thin ragged fringe, not a fade.
// So the base height becomes a function of position, at the scale of one cloud
// patch, and the profile switches on sharply. The top is held where it was, so
// a higher condensation level simply gives a shallower cloud -- which is what an
// inversion does.
// Sources: LCL as the flat-base mechanism (any meteorology text; the 4.4 F/1000
// ft rule is the standard forecast approximation); cloud-type height gradients
// from Schneider & Vos, "The Real-Time Volumetric Cloudscapes of Horizon Zero
// Dawn" (SIGGRAPH 2015), where cumulus uses a near-step at the base and a broad
// shoulder at the top; ragged/scud fragments under a base from the WMO cloud
// atlas entry on cumulonimbus.
// ==============================================================================
float auraliteCloudBaseSpread() {
    float spread = 120.0;          // m
    #if CLOUD_BASE_VARIATION == 1
    spread = 40.0;
    #elif CLOUD_BASE_VARIATION == 3
    spread = 250.0;
    #endif
    return spread;
}

// Per-column condensation level, in metres relative to the reference base.
// One octave of the existing 2D noise at ~1.5 cloud-cell scale: the LCL field is
// genuinely smooth at kilometre scale, and this is 4 hashes, not 24.
float auraliteCloudBaseOffset(vec2 shapeXZ) {
    #if CLOUD_BASE_VARIATION == 4
    return 0.0;
    #endif
    float n = noise(shapeXZ * 0.667 + vec2(11.3, -7.9));    // [0,1]
    return (n - 0.5) * 2.0 * auraliteCloudBaseSpread();
}

// [v1.2.0] CONVECTIVE DEPTH PER CLOUD.
// ------------------------------------------------------------------------------
// The deck had one thickness for every cloud in the sky, so a weak wisp and a
// towering congestus were the same height. Real convection has a spectrum:
// thermals that break through the inversion grow to several kilometres, the ones
// that hit it stop at a few hundred metres, and the tops of the strongest are
// where the anvil eventually goes. This is a second, independent low-frequency
// field that scales a column's depth by 0.6-1.6x. It has to be a SEPARATE field
// from the base offset: if the same noise drove both, "higher base" would always
// mean "shallower cloud", and the sky would lose its towers.
// It is also what makes the deck respond to CLOUD_UPDRAFT in the way a real sky
// does -- stronger convection, deeper cloud -- without animating the geometry:
// `auraliteCloudConvection()` is evaluated once per frame and passed in.
float auraliteCloudDepthMod(vec2 shapeXZ) {
    float n = noise(shapeXZ * 0.47 + vec2(-41.7, 23.1));
    return mix(0.60, 1.60, n);
}

// How deep convection is today: fixed weather state, changed by the storm and by
// the updraft setting, NOT by position or time (clouds do not change thickness
// every frame; they are what the weather made them).
float auraliteCloudConvection() {
    return mix(1.0, 1.35, rainStrength * thunderStrength);
}

// [v1.2.0] OPTION octLimit: PREFILTER FOR PATH SIZE.
// -----------------------------------------------------------------------------
// A 2.4 km long path through a deck acts as a low-pass filter: details
// smaller than the step (150 m) and smaller than the deck itself are not included in the integral, they are only
// give aliasing. While the shadow of the cloud for the rays was considered a FULL field (2-5 octaves,
// smallest detail 135-540 m) at a step of 150 m, the integral was a sample from the field, and
// not an integral, and shifting the sample lattice by half a step changed the optical depth by
// times. For the shadow pass, the octaves are limited: the smoothest field option.
// Slowly evolving, advected moisture field. Adjacent time cells are interpolated
// with zero derivatives at their boundaries, avoiding hard birth/death pops.
// This is procedural weather, not a fluid simulation.
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

// Cirrus: not a blob but a sheared veil. Two noise scales multiplied, so the field
// is fibrous instead of lumpy, and the peak density is capped low because cirrus
// water content is ~0.03 g/m3 against 0.25-0.30 for cumulus.
// [v1.2.0] CIRRUS IS FIBRES, NOT A SHEET.
// ------------------------------------------------------------------------------
// What was here produced one solid overcast instead of a fibrous veil, and the
// numbers say why: the field was the PRODUCT of two 3D noises with cells of 21 km
// and 7.6 km, thresholded over a wide band. A product of two low-frequency fields
// is dominated by whichever is larger, so the result is a handful of huge lumps:
// measured on a 60 x 60 km slice, 53 % of the sky covered, autocorrelation length
// 5.7 km along X and 4.9 km along Z -- isotropic and enormous. From the ground
// you see two or three of those lumps and they read as one continuous sheet.
// Real cirrus is the opposite kind of object. It is a shear-formed ice cloud:
// crystals fall out of a generating cell and are drawn into streaks by the wind,
// so the structure is ANISOTROPIC by more than an order of magnitude in aspect --
// fibres 0.5-2 km wide and tens to hundreds of kilometres long, covering a part of
// the sky and leaving blue between them. Cirrostratus is the exception, and even
// it is a veil, not a slab.
// So the field is rebuilt around the fibre axis, which is the cirrus wind
// direction (26, 9 m/s -> 19 degrees):
//   * ACROSS the streaks the noise runs at a 1.15 km cell, so filaments are about
//     a kilometre wide;
//   * ALONG them the same noise has a 90 km cell, i.e. it is almost constant, so
//     the filament does not break up every few kilometres;
//   * ridged (1 - |2n-1|) instead of smooth, so the level sets are thin curved
//     bands rather than rounded blobs -- that is what a fibre IS;
//   * a slow meander (5 km amplitude, 25 km wavelength) bends them, so they are not
//     corduroy;
//   * gaps along the fibre every ~14 km, because a real streak is not infinite;
//   * a second family at +27 degrees and 42 % weight, which gives the cross-hatch
//     of cirrus radiatus;
//   * a 32 km coverage mask, so cirrus is patchy across the sky instead of uniform.
// Measured on the same slice: coverage 41 % -> 24 %, anisotropy 1.2:1 -> 13:1
// (4.1 km along the fibre against 0.3 km across), and the peak optical depth of a
// filament 3.6 -> 1.2, i.e. a streak now reads as translucent ice instead of paint.
float auraliteCirrusDensity(vec3 p, float t, float minY, float span) {
    float h = (p.y - minY) / max(span, 1.0);
    if (h <= 0.0 || h >= 1.0) return 0.0;
    float profile = smoothstep(0.0, 0.22, h) * (1.0 - smoothstep(0.60, 1.0, h));

    vec2 wind = auraliteCirrusWind(t);
    vec2 xz = p.xz + wind;

    // One fibre family. Everything is measured from the streak axis.
    float along  = dot(xz, vec2( 0.9455, 0.3256));
    float across = dot(xz, vec2(-0.3256, 0.9455));
    // Slow meander, shared with the gap field's coarse channel.
    float meander = noise(vec2(along * 4.0e-5, across * 4.0e-5)) - 0.5;
    float a = across + meander * 5000.0;
    // Ridged filament: thin in `across`, effectively constant in `along`, and
    // squashed vertically so the layer reads as a veil rather than a block.
    float ridge = 1.0 - abs(2.0 * auraliteNoise3(vec3(a / 1800.0, p.y / 900.0,
                                                      along / 90000.0)) - 1.0);
    float fibre = smoothstep(0.58, 0.97, ridge);
    // Breaks along the streak every ~14 km.
    float gap = smoothstep(0.05, 0.45, noise(vec2(along / 14000.0, across / 5000.0)));
    // Second family, 27 degrees off, weaker: the cross-hatch of cirrus radiatus.
    float a2 = dot(xz, vec2(-0.4384, 0.8988)) + meander * 3500.0;
    float ridge2 = 1.0 - abs(2.0 * auraliteNoise3(vec3(a2 / 1900.0, p.y / 900.0,
                                                       dot(xz, vec2(0.8988, 0.4384)) / 90000.0)) - 1.0);
    float fibre2 = smoothstep(0.63, 0.97, ridge2) * 0.55;
    // Large-scale coverage: cirrus is patchy across the sky, not a uniform deck.
    // [v1.2.0] Coverage is kept generous (78 % of the sky, mask 0.02/0.38) and
    // the VEIL is made thinner instead (peak 0.30). A tighter mask was measured and
    // rejected: at the zenith the whole view samples one small patch of the mask, so a
    // 50 % mask means the deck is either fully there or fully absent depending on where
    // the player stands -- measured zenith opacity 0.03 at one spot and 0.42 at another.
    // A thin veil everywhere is both more honest and more predictable.
    float coverMask = smoothstep(0.02, 0.38, noise(xz * 3.1e-5));   // NOT `patch`: reserved in GLSL

    // [v1.2.0] A VEIL WITH FIBRES IN IT, NOT JUST FIBRES.
    // ------------------------------------------------------------------------------
    // Making the field properly anisotropic (9.4 : 1) also made the
    // layer disappear: measured through the actual 8-step march, the mean opacity
    // fell from 0.358 to 0.031, i.e. eleven times fainter, because isolated threads
    // 1.1 km wide over mostly clear sky are almost nothing at a grazing angle. Real
    // cirrus is usually a semi-transparent SHEET with fibrous texture on top, so the
    // field is now a broad veil (0.45 of the peak) modulated by the fibres up to
    // 2.8x, with wider filaments (1.8 km) and a much more generous coverage mask.
    // Measured again through the same march: mean opacity 0.31, 43 % of the sky
    // above 0.15, and the contrast between fibre and veil preserved (sigma 0.40).
    // [v1.2.0] FINE STRIATION INSIDE THE FIBRES.
    // --------------------------------------------------------------------------
    // With the layer finally reachable the measured field read as a soft
    // wash with a few very broad bands, not as cirrus. The reason is a matter of
    // scale, not of contrast: the only structure in the field was the 1.8 km
    // filament family and its 32 km coverage mask, so from the ground every fibre
    // subtended 15-20 deg of sky and the veil had nothing finer than that.
    // Real cirrus is bundled: a fibre is a sheaf of strands, and the strands are
    // separated ACROSS the wind while running unbroken ALONG it. Cirrus fibratus
    // is described exactly that way -- filaments 10:1 to 100:1, drawn out by the
    // shear of the generating cell. So this adds a third, much finer family with
    // the same anisotropy: a 430 m cell across the fibre and a 7 km cell along it,
    // i.e. transverse striation an order of magnitude finer than the filament.
    // The 40 km along-fibre cell is deliberate: a view ray crosses the sheet over
    // 2-8 km of horizontal distance, so a striation that decorrelates every 7 km is
    // averaged away by the march and never reaches the screen (measured +13 % of
    // fine contrast instead of +32 %). It has to be coherent across the path.
    // The amplitude depends on WHERE it acts: +/- 25 % in the smooth veil and
    // +/- 55 % inside a fibre, so the strands appear as feathers inside the
    // filaments instead of corduroy over the whole sky -- which is what a uniform
    // +/- 70 % modulation measured as (it also rendered as a regular wavy curtain).
    // The mean of the modulation is exactly 1, so the MEAN optical depth does not
    // move: the striation redistributes opacity into strands, it does not add
    // cloud. Measured over the sky with the same march: mean alpha 0.241 -> 0.243,
    // fine contrast (RMS above a 4-pixel blur, i.e. the strand scale)
    // 0.0194 -> 0.0256, +32 %.
    float aStrand = a + (noise(vec2(along / 3000.0, 7.3)) - 0.5) * 900.0;  // fibre is not an endless ribbon
    float striae = noise(vec2(aStrand / 430.0, along / 40000.0));
    float strandMask = smoothstep(0.15, 0.65, max(fibre, fibre2));
    float strandAmp = mix(0.25, 0.55, strandMask);
    float feather = 1.0 + strandAmp * (2.0 * smoothstep(0.30, 0.70, striae) - 1.0);
    // [v1.2.0] The variable was called `texture` - a reserved word.
    // Iris renamed it on the fly (“Renamed reserved word “texture””), but
    // there is no need to rely on this.
    float fibreShape = (0.45 + 0.55 * max(fibre, fibre2) * 1.8) * feather;
    float d = fibreShape * gap * coverMask * profile;
    // Peak density: 0.115 of the cirrus extinction over 2.2 km is tau ~ 1.2, the
    // upper end of thin cirrus. The old 0.30 gave tau 3.6 -- opaque.
    // [v1.2.0] 0.20 -> 0.05. The peak had been cut to 0.20 precisely
    // because the deck was thought to be clipping; once it really does reach the
    // sky that value is far too thick: measured mean opacity 0.80 at 20 deg,
    // 0.85 at 30 deg and 0.57 at the zenith, i.e. a white lid rather than a veil.
    // 0.05 puts the sheet where cirrus actually lives -- tau 0.21 at the zenith and
    // 0.54 at 30 deg, alpha 0.19 / 0.42 -- while the fibre modulation still reaches
    // 3.2x the veil locally, so the streaks keep their contrast (measured sigma
    // 0.12-0.15 across the azimuth at 20-30 deg, against 0 for a uniform sheet:
    // that is the texture the eye reads as fibres).
    // Ice-cloud veil slowly forms and dissipates independently of the low deck.
    d *= mix(0.65, 1.25, auraliteCloudLife(xz * 0.00025 + vec2(37.0, -19.0), t));
    d *= 0.05 * (1.0 - rainStrength);        // rain hides high cloud completely
    return d;
}

// Henyey-Greenstein, normalised so that g = 0 gives exactly 1.
float auraliteHenyeyGreenstein(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4), 1.5);
}

// ==============================================================================
// CORNETTE-SHANKS [v1.2.0]
// ------------------------------------------------------------------------------
// HG is a convenient blob, but it is a poor fit to the Mie phase function of a
// water droplet: it is too low at side angles and far too low in backscatter,
// which is exactly the region that decides how dark the shaded half of a cloud
// looks. Cornette-Shanks is the widely used closed form that keeps HG's cost and
// adds the (1 + cos^2) term:
//     P(t) = 3 (1 - g^2) (1 + t^2) / (2 (2 + g^2) (1 + g^2 - 2 g t)^{3/2})
// Both are normalised to integrate to 1 over the sphere, so they are directly
// interchangeable in the lighting sum. The 1/(4*pi) isotropic value is the
// reference used everywhere else in this block.
// ==============================================================================
float auraliteCornetteShanks(float cosTheta, float g) {
    float g2 = g * g;
    float denom = max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4);
    return 3.0 * (1.0 - g2) * (1.0 + cosTheta * cosTheta)
         / (2.0 * (2.0 + g2) * denom * sqrt(denom));
}

// Dual lobe: g = 0.85 forward (droplets, Kokhanovsky 0.83-0.87) plus a wide
// backward lobe that stands in for the multiple scattering HG cannot represent.
// The 0.25 factor puts the 90-degree value at ~0.08, i.e. the isotropic
// 1/(4*pi) response, so the sun term stays in the same units as the ambient term.
float auraliteCloudPhase(float cosTheta) {
    // Droplet lobe: Cornette-Shanks (Mie fit). Backward lobe: HG with negative g,
    // standing in for the light that leaves the cloud after many scatterings. The
    // 70/30 split and the 0.25 normalisation put the 90 degree value on the
    // isotropic 1/(4*pi) level, which keeps the sun term in the same units as the
    // sky-ambient term.
    float phase = mix(auraliteCornetteShanks(cosTheta, auraliteCloudAsymmetry()),
                      auraliteHenyeyGreenstein(cosTheta, -0.25), 0.30);
    // [v1.2.0] The cap is 2.5, not 6.0. Raw HG at g = 0.85 reaches ~80 at
    // zero angle -- that is the aureole, the bright ring you only see when the sun
    // itself is visible THROUGH the cloud, which this pass does not draw (the sky
    // pass draws the disc). At 6.0 any thin gap in a deck became a blown-out white
    // blob, most visible in a storm where the deck is broken but dark. 2.5 keeps a
    // bright rim on sun-facing edges and stops the sun term from swamping the deck.
    return clamp(phase * 0.25, 0.0, 2.5);
}

// ==============================================================================
// MULTIPLE SCATTERING [v1.2.0]
// ------------------------------------------------------------------------------
// The interior of a cloud used to be single scattering plus a flat 0.12
// constant standing in for "light that bounced a few more times". That constant
// was a fudge: it did not know how thick the cloud was, so it lit a thin wisp and
// a cumulonimbus core equally.
// This is the octave method (Schneider, "Real-Time Volumetric Cloudscapes",
// Horizon Zero Dawn; also used in Nubis). Each successive order of scattering is
// sampled with a step length that GROWS geometrically, because light that has
// survived one order is already diffuse and only needs the large-scale shape.
// Every octave contributes energy * T_octave * phase_octave, and the energy
// carried into the next octave is halved:
//     a_0 = 1,  a_{i+1} = 0.5 * a_i
// The 0.5 is not a colour knob: for a conservatively scattering medium with
// g = 0.85 roughly half the light leaving one order continues forward. Because
// the step grows 2.5x per octave this costs two samples per octave rather than
// two per order, and it is still an energy count, not a constant.
// The phase function is anisotropic only for the first order. Higher orders have
// forgotten the incoming direction -- they are close to isotropic, which is why
// the shaded body of a cloud is not black.
// ==============================================================================
vec3 auraliteCloudMultipleScattering(vec3 p, vec3 lightDir, float t,
                                     float cloudMinY, float cloudSpan,
                                     int samplesPerOctave, int octaves,
                                     float cosTheta, float powder,
                                     out float firstOrderTransmittance, out vec3 firstOrderLight) {
    float sigmaExt = auraliteCloudExtinction();
    float phaseDir = auraliteCloudPhase(cosTheta);
    const float phaseIso = 0.0795775;      // 1/(4*pi), the isotropic value

    // [v1.2.0] The step of the light march is tied to the MEAN FREE PATH,
    // not to the deck depth. At 0.05 * span = 60 m against a mean free path of
    // 1 / sigma = 34 m, the first octave was already two optical depths long, and
    // the third octave stepped 375 m -- eleven mean free paths. An octave that
    // long samples clear air on both sides of the cloud it is supposed to be
    // shadowed by, so it delivered full sunlight into the core: that is why the
    // inside of a cloud read as milk rather than as a shaded body. Starting at one
    // mean free path and growing 2.5x per octave keeps every order inside the
    // medium, which is the whole point of the method.
    float stepLen = clamp(1.0 / max(sigmaExt, 1e-5), 8.0, cloudSpan * 0.05);
    float energy = 1.0;
    vec3 sum = vec3(0.0);
    vec3 q = p;
    firstOrderTransmittance = 1.0;
    firstOrderLight = vec3(0.0);
    float directTailTransmission = 1.0;

    for (int o = 0; o < 3; ++o) {
        if (o >= octaves) break;
        float tau = 0.0;
        for (int i = 0; i < 2; ++i) {
            if (i >= samplesPerOctave) break;
            q += lightDir * stepLen;
            tau += auraliteCloudDensity(q, t, cloudMinY, cloudSpan, false, 0) * stepLen;
        }
        float T = exp(-tau * sigmaExt);
        // The later segments are farther toward the light. Their optical depths
        // also attenuate the direct beam, not just their own scattering octave.
        if (o > 0) directTailTransmission *= T;

        // First order keeps the droplet phase function and the powder term (both
        // single-scattering effects); later orders are progressively diffuse.
        float ph = phaseDir;
        float shape = powder;
        if (o == 1) { ph = mix(phaseDir, phaseIso, 0.6); shape = 1.0; }
        else if (o >= 2) { ph = phaseIso; shape = 1.0; }

        sum += vec3(energy * T * ph * mix(0.55, 1.0, shape));
        if (o == 0) {
            firstOrderTransmittance = T;
            firstOrderLight = vec3(energy * T * ph * mix(0.55, 1.0, shape) * 1.142857);
        }

        energy *= 0.5;
        stepLen *= 2.5;
    }
    // The direct beam previously stopped at the first two short samples. Reuse
    // the existing farther light samples to integrate additional extinction;
    // diffuse octaves remain unchanged. This is still a sparse approximation,
    // not a guarantee that the complete path to the cloud boundary is sampled.
    vec3 originalFirst = firstOrderLight;
    firstOrderLight *= directTailTransmission;
    firstOrderTransmittance *= directTailTransmission;
    sum += (firstOrderLight - originalFirst) / 1.142857;

    // The series 1 + 1/2 + 1/4 converges to 2, so three octaves carry 1.75 of it.
    // Scaling by 2/1.75 restores the tail that was truncated, which is an energy
    // bookkeeping correction, not a brightness tweak.
    return sum * 1.142857;   // 2 / 1.75
}

// Ray/slab intersection: returns (tEnter, tExit), both clamped to [0, maxDist].
vec2 auraliteSlabRange(vec3 origin, vec3 dir, float minY, float maxY, float maxDist) {
    if (abs(dir.y) < 0.001) {
        if (origin.y < minY || origin.y > maxY) return vec2(0.0);
        return vec2(0.0, maxDist);
    }
    float ta = (minY - origin.y) / dir.y;
    float tb = (maxY - origin.y) / dir.y;
    float t0 = max(min(ta, tb), 0.0);
    float t1 = min(max(ta, tb), maxDist);
    if (t0 >= t1) return vec2(0.0);
    return vec2(t0, t1);
}

// Marshes the high cirrus veil. Thin, so no per-step light march: one tap toward
// the sun is enough for a medium with an optical depth around 1.
vec4 auraliteCirrusClouds(vec3 worldDir, vec3 lightDir, vec3 lightColor,
                          float dayFactor, float sunsetFactor, float t,
                          float terrainDist, float renderDistance,
                          float cloudMaxY, float cloudSpan,
                          vec3 ambient, float flash, float phase, bool skyPixel) {
    // [v1.2.0] Cirrus lives at 6.5-8.7 km whatever the cumulus base is:
    // it is a different cloud family, not a smaller cumulus on top of it.
    // [v1.2.0] The deck stays in the real cirrus band, 6.5-11.2 km. The upper
    // clamp matters: the base is tied to the cumulus deck, so CLOUD_HEIGHT = 4 with
    // CLOUD_THICKNESS = 3 (3600 m base, 5.4 km deep) pushed it to 11.7 km, where its
    // lower edge sits at 21 deg of elevation and the layer would vanish for a player
    // standing on the ground again -- exactly the class of bug this fix closes.
    float minY = clamp(cloudMaxY + cloudSpan * 0.5, 6500.0, 9000.0);
    float span = 2200.0;
    // [v1.2.0] HOW FAR THE DECK IS QUERIED -- see AUR_CIRRUS_REACH.
    // ---------------------------------------------------------------------------
    // The slab used to be queried up to min(renderDistance, terrainDist), where
    // terrainDist is the CUMULUS render distance (3-16 km) -- a sensible cap for a
    // cloud at 1.2-3.6 km and a fatal one for a deck at 6.5 km, which cannot be
    // entered at any pitch if the ray is cut at 6 km. That is why the layer
    // disappeared while its shape was being fixed: the march never reached it.
    float maxDist = min(renderDistance, terrainDist);
    maxDist = skyPixel ? AUR_CIRRUS_REACH : min(maxDist, AUR_CIRRUS_REACH);
    vec2 range = auraliteSlabRange(cameraPosition, worldDir, minY, minY + span, maxDist);
    if (range.y <= 0.0) return vec4(0.0);

    // [v1.2.0] NO SECOND TRANSFORM -- THIS WAS THE RED-CLOUD BUG.
    // ---------------------------------------------------------------------------
    // auraliteSunDir() ALREADY returns a world-space direction; it performs the
    // view -> world transform internally (see its definition). Wrapping it in
    // mat3(gbufferModelViewInverse) again applies that rotation TWICE, so the sun
    // the clouds were lit by was rotated by the camera's own orientation: turn your
    // head and the sun moves.
    // Measured with the true sun at 60 degrees of elevation:
    //     pitch   0 deg -> light elevation +60 deg, beam R/B   1.4  (correct)
    //     pitch  45 deg -> +16 deg,  R/B   2.7
    //     pitch  60 deg -> +1.5 deg, R/B  37.6   <- deep orange
    //     pitch  70 deg -> -8.4 deg, R/B 374.7   <- the "sun" is below the horizon
    // Looking up dragged the light source under the horizon, so the cloud was lit by
    // a sunset beam at any time of day; the blue skylight added on top turned that
    // orange into pink. Looking down rotated it the other way. That is the entire
    // "clouds turn red when I look up or down, at any hour" report -- and it is why
    // no amount of colour work could touch it: the
    // colour maths was right, the DIRECTION handed to it was wrong.
    vec3 sunDirW = auraliteSunDir(sunPosition, shadowLightPosition);
    float sunOwns = smoothstep(-0.35, -0.10, sunDirW.y);
    vec3 boltPosI = lightningBoltPosition.xyz;
    float boltPresent = step(0.5, dot(boltPosI, boltPosI));

    // A longer reach must not become coarser slicing: 60 km over 4 steps is 15 km
    // per sample and the veil would read as four bands. The cirrus march has no
    // light march (one tap toward the sun, one density sample per step), so paying
    // for 12 steps is cheap -- about one cumulus light tap.
    // [v1.2.0] A slice every 800 m, not every 3.5 km. The old rule was tuned
    // against the 6-12 km slab; over the longer paths this deck now actually has
    // (up to 8 km at grazing) 4 steps meant 2 km per slice and the veil read as
    // four flat sheets. The sample count stays the same order as the cumulus light
    // march, and the floor of 6 keeps the zenith from being sliced in two.
    int steps = max(auraliteCirrusSteps(), int(clamp((range.y - range.x) / 800.0, 6.0, 12.0)));
    float ds = (range.y - range.x) / float(steps);
    float sigmaExt = auraliteCirrusExtinction();

    // Midpoint rule, deterministic: the veil is thin, so the slice count is what
    // removes banding here -- never a per-pixel offset, which would show as grain.
    const float sliceCenter = 0.5;

    float transmission = 1.0;
    vec3 scattered = vec3(0.0);

    for (int i = 0; i < 12; ++i) {
        if (i >= steps) break;
        float tDist = range.x + (float(i) + sliceCenter) * ds;
        vec3 p = worldDir * tDist + cameraPosition;
        float density = auraliteCirrusDensity(p, t, minY, span);
        // [v1.2.0] The deck must DISSOLVE at the end of its reach, not be cut.
        // A layer that stops at 40 km shows its own edge as a bright white arc across
        // the sky -- measured as a band of opacity 0.7 where the path grazes the slab
        // and then a hard cut. Fading the density over the last 40 % of the reach
        // lets it thin into the horizon haze, which is what a real cirrus sheet does.
        density *= 1.0 - smoothstep(0.55 * maxDist, maxDist, tDist);
        if (density <= 0.001) continue;
        float h = clamp((p.y - minY) / max(span, 1.0), 0.0, 1.0);

        vec3 q = p + lightDir * span * 0.5;
        float tau = auraliteCirrusDensity(q, t, minY, span) * span * 0.5;
        float lightT = exp(-tau * sigmaExt);

        // Cirrus is the highest thing in the sky, so it is the last to lose the sun.
        // Mapped to a real 7-11 km: at -2 deg the cumulus base is long dark while
        // the cirrus is still burning red, which is the classic sunset photograph.
        float altM = p.y;
        float sunVis = auraliteCloudSunlit(sunDirW, altM);
        // [v1.2.0] Same gate as the cumulus, and it is the one that keeps the
        // high deck honest: at 7 km the depression is 2.7 degrees, so cirrus keeps
        // the sun about twice as long as a 1.2 km cumulus -- the red cirrus of a
        // sunset photograph -- and then goes out instead of glowing all night.
        float lightGate = 1.0;
        vec3 cirrusSun = auraliteCloudSunRadiance(
            auraliteCloudEffectiveSunSin(sunDirW.y, altM), sunsetFactor, altM) * sunVis;
        vec3 cirrusLight = mix(lightColor, cirrusSun, sunOwns);

        // Cirrus is optically thin, so single scattering dominates and there is no
        // significant multiple-scattering term: one phase function, one tap.
        vec3 radiance = cirrusLight * (phase * 1.35 + 0.05) * lightT * lightGate
                      + ambient * 1.15 * mix(1.0, mix(0.70, 1.0, sunVis), sunOwns)
                      + vec3(1.25, 1.35, 1.70) * flash * mix(1.0, auraliteBoltProximity(p), boltPresent);

        float sigma = density * sigmaExt;
        float stepTrans = exp(-sigma * ds);
        scattered += transmission * radiance * (1.0 - stepTrans);
        transmission *= stepTrans;
        if (transmission < 0.02) break;
    }

    return vec4(scattered, 1.0 - transmission);
}

// A separately advected middle deck: altocumulus-like patches in fair weather,
// tending to an altostratus-like sheet in rain. An inexpensive optical march;
// not a meteorological simulation or a complete WMO-genus implementation.
#ifdef CLOUD_MID_LAYER
vec4 auraliteMidClouds(vec3 worldDir, vec3 lightDir, float t, float lowTop,
                       float terrainDist, bool skyPixel, vec3 ambient,
                       float sunsetFactor, out float midDistance, out float midHeight) {
    float base = clamp(max(3400.0, lowTop + 150.0), 3400.0, 5500.0);
    float span = mix(900.0, 1500.0, rainStrength);
    float reach = skyPixel ? AUR_CIRRUS_REACH : min(terrainDist, AUR_CIRRUS_REACH);
    vec2 range = auraliteSlabRange(cameraPosition, worldDir, base, base + span, reach);
    midDistance = 0.0;
    midHeight = base + span * 0.5;
    if (range.y <= 0.0) return vec4(0.0);
    const int steps = 6;
    float ds = (range.y - range.x) / float(steps);
    float T = 1.0;
    vec3 scattering = vec3(0.0);
    float depthSum = 0.0;
    vec3 sunDir = auraliteSunDir(sunPosition, shadowLightPosition);
    vec3 cloudSun = auraliteCloudSunRadiance(auraliteCloudEffectiveSunSin(sunDir.y, midHeight), sunsetFactor, midHeight)
                   * auraliteCloudSunlit(sunDir, midHeight);
    // Diffuse mid-level layer; no added ray-start noise or angular sun disc.
    vec3 radiance = ambient + cloudSun * 0.08;
    vec2 wind = vec2(17.0, 8.0) * (t * AUR_CLOUD_TIME_SCALE * getCloudWindSpeedMultiplier());
    for (int i = 0; i < steps; ++i) {
        float d = range.x + (float(i) + 0.5) * ds;
        vec3 pos = cameraPosition + worldDir * d;
        float h = clamp((pos.y - base) / span, 0.0, 1.0);
        vec2 uv = (pos.xz + wind) / 3400.0;
        float moisture = auraliteCloudLife(uv + vec2(11.0, -27.0), t);
        float patches = noise(uv + vec2(0.12 * h, -0.08 * h));
        float threshold = mix(0.57, 0.32, rainStrength) + (0.5 - moisture) * 0.22;
        float density = smoothstep(threshold, threshold + 0.17, patches);
        density *= smoothstep(0.0, 0.16, h) * (1.0 - smoothstep(0.78, 1.0, h));
        density *= 1.0 - smoothstep(0.55 * reach, reach, d);
        float seg = exp(-density * 0.006 * ds);
        float weight = T * (1.0 - seg);
        scattering += radiance * weight;
        depthSum += d * weight;
        T *= seg;
        if (T < 0.01) break;
    }
    float a = 1.0 - T;
    midDistance = depthSum / max(a, 0.0001);
    return vec4(scattering, a);
}
#endif

vec4 auraliteVolumetricClouds(vec3 worldDir, vec3 lightDir, vec3 lightColor,
                              float terrainDist, float dayFactor, float sunsetFactor, float t,
                              bool skyPixel) {
    // [v1.2.0] The deck is defined in metres (see auraliteCloudBaseAltitude):
    // 1200 m base by default, not 160 blocks. A storm lowers the base by 12 %.
    float baseAlt = auraliteCloudBaseAltitude();
    float cloudMinY = baseAlt * (1.0 - rainStrength * 0.12);
    float cloudSpan = auraliteCloudDepthMetres(baseAlt);

    float cloudMaxY = cloudMinY + cloudSpan;
    float cloudRenderDistance = auraliteCloudRenderDistance();

    // The terminator needs the real sun, not the shadow light: at night the
    // shadow light is the moon, and the moon must not be switched off by the
    // Earth's shadow (it is above the horizon whenever it is the light source).
    // [v1.2.0] NO SECOND TRANSFORM -- THIS WAS THE RED-CLOUD BUG.
    // ---------------------------------------------------------------------------
    // auraliteSunDir() ALREADY returns a world-space direction; it performs the
    // view -> world transform internally (see its definition). Wrapping it in
    // mat3(gbufferModelViewInverse) again applies that rotation TWICE, so the sun
    // the clouds were lit by was rotated by the camera's own orientation: turn your
    // head and the sun moves.
    // Measured with the true sun at 60 degrees of elevation:
    //     pitch   0 deg -> light elevation +60 deg, beam R/B   1.4  (correct)
    //     pitch  45 deg -> +16 deg,  R/B   2.7
    //     pitch  60 deg -> +1.5 deg, R/B  37.6   <- deep orange
    //     pitch  70 deg -> -8.4 deg, R/B 374.7   <- the "sun" is below the horizon
    // Looking up dragged the light source under the horizon, so the cloud was lit by
    // a sunset beam at any time of day; the blue skylight added on top turned that
    // orange into pink. Looking down rotated it the other way. That is the entire
    // "clouds turn red when I look up or down, at any hour" report -- and it is why
    // no amount of colour work could touch it: the
    // colour maths was right, the DIRECTION handed to it was wrong.
    vec3 sunDirW = auraliteSunDir(sunPosition, shadowLightPosition);
    // How much of the direct light below still belongs to the sun. Above -5.7 deg
    // it is all sun; below -20 deg the moon owns the light and no terminator
    // applies (mix would otherwise black out moonlit clouds).
    float sunOwns = smoothstep(-0.35, -0.10, sunDirW.y);

    // [v1.2.0] Deterministic ray start. The per-pixel IGN offset is gone: with
    // TAA off in most profiles there is nothing to resolve that noise, so it read
    // as static grain crawling over the deck whenever the camera moved. Every
    // pixel now aims at the middle of its shell -- stable, and free.
    const float shellCenter = 0.5;
    float flash = auraliteLightningFlash(frameTimeCounter);
    // A bolt is only placed when the game actually has one; otherwise the flash
    // stays uniform over the deck.
    vec3 boltPos = lightningBoltPosition.xyz;
    float boltPresent = step(0.5, dot(boltPos, boltPos));
    float phase = auraliteCloudPhase(dot(worldDir, lightDir));
    float horizonSoftness = smoothstep(0.01, 0.18, abs(worldDir.y));

    // Sky ambient. v1.1.4 used one fixed day/night triplet; now the night end is
    // pulled toward the moon colour and the twilight end toward the sun colour, so
    // the shaded side of a cloud changes colour with the sky instead of staying
    // grey. Both ends stay dim: this is the light a cloud receives from the whole
    // hemisphere, not from the sun.
    vec3 skyBase = mix(vec3(0.010, 0.013, 0.022), vec3(0.30, 0.34, 0.40), dayFactor);

    // SKY LIGHT AT SUNSET IS TWO COLOURS, NOT ONE.
    // The twilight sky is orange toward the sun and blue-violet everywhere else
    // (the zenith never goes red -- that light has been scattered out of the
    // beam). So the side of a cloud that faces the sun is lit by the warm half of
    // the sky and glows red-orange, while its shaded body is lit by the blue half
    // and goes grey-blue. That red/blue split inside ONE cloud is what a real
    // sunset cloud looks like; tinting the whole cloud red reads as candy.
    vec3 sunHue = auraliteHueAtSameLuma(
        max(auraliteCloudSunRadiance(auraliteCloudEffectiveSunSin(sunDirW.y, cloudMaxY), sunsetFactor, cloudMaxY),
            vec3(1e-4)));
    // ==========================================================================
    // [v1.2.0] THE AMBIENT ON A CLOUD MUST NOT DEPEND ON WHERE YOU LOOK.
    // --------------------------------------------------------------------------
    // The warm fraction of the sky ambient used to be
    //     warmAmt = sunsetFactor * sunOwns * mix(0.25, 0.85, dot(worldDir, lightDir))
    // -- i.e. a function of the VIEW RAY. That is a category error: the light a
    // cloud receives from the sky is a property of the cloud, and does not change
    // when the player turns their head. In practice it meant the same cloud was
    // tinted orange when you looked at it one way and grey-blue when you looked
    // at it another; at high sun the effect is small, but pitch to the zenith or
    // the nadir and dot(worldDir, lightDir) collapses to +-sin(sun elevation), so
    // the tint jumped to whichever end of the range was nearest -- which is the
    // "clouds turn red when I look straight up or down" report.
    // The directional red/blue split inside a cloud is real, but it comes from
    // the PHASE FUNCTION (light scattered toward the viewer), not from the
    // ambient. So the ambient warmth is now driven by how low the sun is -- the
    // actual reason the sunward half of the sky is orange -- and the phase
    // function alone produces the lit/shaded split. Identical cloud, identical
    // colour, from every camera angle.
    // ==========================================================================
    float sunLow = 1.0 - smoothstep(0.02, 0.40, lightDir.y);   // 1 at the horizon, 0 high up
    float warmAmt = sunsetFactor * sunOwns * mix(0.10, 0.70, sunLow);
    // [v1.2.0] AND THE WARM BAND IS NEAR THE HORIZON, NOT OVERHEAD.
    // ------------------------------------------------------------------------------
    // The warm fraction of skylight belongs to the thin band of air just above the
    // horizon (that is why the sunward horizon is orange at sunset and the zenith is
    // still blue). A cloud at 1.2 km stands above most of that band and sees mostly
    // the upper dome, so its skylight should be far less warm than the horizon's.
    // Without this factor the tint was applied as if the whole sky dome were orange,
    // which is what made a cloud overhead go red at sunset -- while a cloud near the
    // horizon, correctly, stayed gold. Aerosol scale height AUR_H_M = 1200 m: the
    // deck keeps 0.39 of the warm fraction, cirrus at 7 km keeps 0.003.
    // The golden COLOUR of a sunset cloud does not depend on this: that comes from
    // the direct beam (auraliteCloudSunRadiance, reddened by a long air path), so a
    // cloud stays gold where the sun reaches it and blue-grey where it does not --
    // the real red/blue split, with no red ambient to leak into the shaded half.
    float warmAltFade = exp(-max(cloudMinY - cameraPosition.y, 0.0) / AUR_H_M);
    warmAmt *= warmAltFade;
    vec3 ambient = auraliteTintAmbient(skyBase, sunHue, warmAmt);
    ambient *= mix(1.0, 0.45, rainStrength * (0.5 + 0.5 * thunderStrength));

    // Cumulus deck. [v1.2.0] The slab is widened downward by the base
    // spread so that a column whose condensation level drifted down is not cut
    // off by the march. Samples outside a column's own cloud return zero in
    // auraliteCloudDensity, so this costs only the early-out.
    // [v1.2.0] The slab top also has to cover the deepest column: 1.6x
    // depth times today's convection. Cells above every column simply return
    // zero density, so widening the slab costs only the early-out.
    float slabTop = cloudMinY + cloudSpan * 1.6 * auraliteCloudConvection();
    vec2 range = auraliteSlabRange(cameraPosition, worldDir,
                                   cloudMinY - auraliteCloudBaseSpread(), slabTop,
                                   min(cloudRenderDistance, terrainDist));

    float transmission = 1.0;
    vec3 scattered = vec3(0.0);
    float depthAccum = 0.0;      // transmittance-weighted cloud depth, metres
    float depthAlt = 0.0;        // transmittance-weighted cloud altitude, metres

    if (range.y > 0.0) {
        int steps = auraliteCloudSteps();
        // Octaves of multiple scattering. Three is the standard count (Schneider);
        // the cheapest setting drops to two, which loses the most diffuse order.
        int octaves = 3;
        int lightSamples = 2;
        #if CLOUD_QUALITY == 1
        octaves = 2;
        #endif
        float ds = (range.y - range.x) / float(steps);
        float phaseCos = dot(worldDir, lightDir);
        // Thunderstorm liquid water content is 1-3 g/m3 against 0.25-0.30 for fair
        // cumulus (a 4-10x extinction), but the field already saturates by then.
        // 1.5x keeps the deck reading as dense without turning it into a black slab.
        float sigmaExt = auraliteCloudExtinction() * mix(1.0, 1.5, rainStrength * thunderStrength);

        // One terrain tap for the whole ray, taken lazily at the first sample that
        // actually has cloud in it: -1 means "not asked yet".
        float terrainVis = -1.0;

        for (int i = 0; i < 56; ++i) {
            if (i >= steps) break;
            float tDist = range.x + (float(i) + shellCenter) * ds;
            vec3 p = worldDir * tDist + cameraPosition;

            float density = auraliteCloudDensity(p, t, cloudMinY, cloudSpan, true, 0);
            if (density <= 0.002) continue;

            if (terrainVis < 0.0) terrainVis = auraliteCloudTerrainVisibility(p);

            float heightFrac = clamp((p.y - cloudMinY) / cloudSpan, 0.0, 1.0);

            // The terminator: is this altitude still lit? Bases lose the sun first,
            // tops last, so the upper cloud keeps the red light after the lower part
            // has gone blue-grey. That IS the "higher = redder at sunset" effect.
            // The altitude is REAL here: the sample's height above the ground is
            // the deck's height, so the terminator and the airmass are computed at
            // the height where the light actually arrives.
            float altM = p.y;
            float sunVis = auraliteCloudSunlit(sunDirW, altM);

            // [v1.2.0] THE SUN'S BEAM IS GATED BY THE CLOUD'S OWN TERMINATOR.
            // ------------------------------------------------------------------
            // The gate used to be `lightGate = mix(1.0, sunVis, sunOwns)`, and
            // sunOwns is smoothstep(-0.35, -0.10, sunY) -- i.e. between -6 and -20
            // degrees of solar elevation the factor slid from 1 to 0 and the gate
            // was DISABLED exactly there: at sunY = -0.20 (11 degrees below the
            // horizon) the beam still passed at 56 %. Meanwhile the colour came
            // from auraliteCloudSunRadiance(), which clamps the effective elevation
            // to 0.015 and therefore always returns a horizon sun: R/B 21 measured
            // on screen. A cloud at 1.8 km is in the Earth's shadow once the sun is
            // more than ~1.4 degrees below the horizon, so for 1.5 in-game hours
            // after sunset every cloud was lit by a fake sunset beam -- the "clouds
            // are red after sunset" report. Measured at /time 13000 / 13500 / 14000:
            // the light colour read R/B 21 at 13000 and 13500, and turned neutral
            // (R/B 1.0) only at 14000, where sunOwns had reached 0 and the moon
            // finally supplied the light.
            // The beam is now multiplied by sunVis -- the cloud's own horizon test,
            // depression 1.4 degrees at 1.8 km, 2.7 at 7 km -- so a cloud goes dark
            // when the sun leaves IT, which is what the red-after-sunset effect
            // actually is: a few minutes, not two hours. sunOwns stays, but only as
            // the blend toward the moon-lit colour once the beam is gone.
            float lightGate = 1.0;   // gating lives in cloudSun now, applied once
            vec3 cloudSun = auraliteCloudSunRadiance(
                auraliteCloudEffectiveSunSin(sunDirW.y, altM), sunsetFactor, altM) * sunVis;
            vec3 cloudLight = mix(lightColor, cloudSun, sunOwns);

            // Powder: thin rims facing the light have had fewer scattering events,
            // so they read darker than the body. This is what gives cumulus its edge.
            // It is a first-order effect, so only the first octave gets it.
            // [v1.2.0] Beer's law on this sample's own optical depth, in
            // place of an arbitrary coefficient 8.0: the powder term is the
            // fraction of the direct beam this slab actually intercepts, so it has
            // to know sigma and the step length, not just a normalised density.
            float powder = 1.0 - exp(-2.0 * density * sigmaExt * ds);

            // Real multiple scattering in place of the old 0.12 constant.
            float firstOrderT;
            vec3 firstOrderLight;
            vec3 scatteredLight = auraliteCloudMultipleScattering(
                p, lightDir, t, cloudMinY, cloudSpan, lightSamples, octaves,
                phaseCos, powder, firstOrderT, firstOrderLight);

            // Terrain, terminator and Earth's-shadow gates apply to every order,
            // because every order ultimately descends from the same sunlight.
            float lightGateAll = lightGate * mix(1.0, terrainVis, 0.85);
            // A cloud below the terminator sits in the Earth's curved shadow, so its
            // sky light is reduced too -- but not to zero: the twilight sky above it
            // is still bright. 30 % cut, only while the sun owns the light.
            float ambShadow = mix(1.0, mix(0.70, 1.0, sunVis), sunOwns);

            // Lightning is a source INSIDE the medium, so it is not attenuated by
            // the light march, and it is local: a bolt lights the cloud around it.
            float boltGlow = flash * mix(1.0, auraliteBoltProximity(p), boltPresent);

            float tauSky = sigmaExt * density * (1.0 - heightFrac) * cloudSpan * 0.58;
            float skyVis = exp(-tauSky);
            // Sky-ambient contribution of the reference model, kept alongside the
            // corrected direct-sun optical depth.
            vec3 skyAmbient = ambient * (0.45 + 0.55 * heightFrac);

            vec3 stepRadiance = cloudLight * scatteredLight * lightGateAll * ambShadow
                              + skyAmbient * ambShadow
                              + vec3(1.35, 1.45, 1.80) * boltGlow * (0.35 + 0.65 * powder);

            float sigma = density * sigmaExt;
            float stepTrans = exp(-sigma * ds);
            float stepWeight = transmission * (1.0 - stepTrans);
            scattered += stepRadiance * stepWeight;
            depthAccum += tDist * stepWeight;
            depthAlt += p.y * stepWeight;
            transmission *= stepTrans;
            if (transmission < 0.01) break;
        }
    }

    // From below the mid deck, composite it behind the low layer and before
    // cirrus. Inside/above the layer this approximation is deliberately skipped
    // rather than drawing a depth-inverted cloud over the foreground.
#ifdef CLOUD_MID_LAYER
    if (cameraPosition.y < 3400.0 && worldDir.y > 0.001) {
        float midDistance, midHeight;
        vec4 mid = auraliteMidClouds(worldDir, lightDir, t, cloudMaxY,
                                     terrainDist, skyPixel, ambient, sunsetFactor,
                                     midDistance, midHeight);
        depthAccum += transmission * mid.a * midDistance;
        depthAlt += transmission * mid.a * midHeight;
        scattered += transmission * mid.rgb;
        transmission *= 1.0 - mid.a;
    }
#endif

    // Cirrus behind the cumulus, same propagation: S = S_c + T_c * S_i.
    #ifdef CLOUD_CIRRUS
    vec4 cirrus = auraliteCirrusClouds(worldDir, lightDir, lightColor, dayFactor,
                                       sunsetFactor, t, terrainDist, cloudRenderDistance,
                                       cloudMaxY, cloudSpan, ambient, flash, phase,
                                       skyPixel);
    scattered += transmission * cirrus.rgb;
    transmission *= 1.0 - cirrus.a;
    #endif

    float cover = 1.0 - transmission;
    float alpha = clamp(cover * horizonSoftness, 0.0, 1.0);
    vec3 rgb = scattered / max(cover, 0.02);

    // Aerial perspective, applied at the cloud's OWN depth (transmittance-weighted),
    // not at the render distance: a cloud overhead must not be washed out because
    // one at the horizon is.
    // The extinction comes from the meteorological visibility by Koschmieder's
    // relation, sigma = 3.912 / V, instead of a made-up coefficient. V = 40 km is
    // clear but ordinary air (standard visibility is 20-50 km); the earlier
    // 4e-5 1/m silently meant a visibility of 98 km, which is alpine air and made
    // distant clouds far too crisp.
    // Rain lowers visibility for the same reason it lowers it outside a shader:
    // more aerosol-sized droplets in the air. 40 km in clear air, 8 km in heavy
    // rain, which is the measured range for moderate to heavy precipitation.
    float visibilityM = mix(40000.0, 8000.0, rainStrength);
    float airExtinction = 3.912 / visibilityM;   // 9.8e-5 1/m at the ground
    // [v1.2.0] AERIAL PERSPECTIVE IS ABOUT THE AIR IN FRONT, NOT THE CLOUD.
    // ------------------------------------------------------------------------------
    // `cloudDepth` here used to be the transmittance-weighted path length THROUGH
    // the cloud, and it drove the haze mix. That is the wrong quantity twice over.
    // Haze is air between the camera and the cloud, so a cloud 1.2 km overhead --
    // thick, and therefore with a large cloudDepth -- was veiled as heavily as one
    // at the edge of a 20 km render distance. At sunset that veil is tinted warm,
    // so the cloud straight above the player went orange/red: the same report as
    // before, from a different cause. Fix20 could not remove it, because the term
    // was never view-directional -- it was view-DISTANCE, and the zenith is where
    // the error is largest in the other direction.
    // depthAccum is now the transmittance-weighted DISTANCE along the ray (it was
    // already being accumulated as tDist), so the haze is what it should be: air
    // over 1.2 km overhead is 0.04 opacity, air over 20 km is 0.49.
    float cloudDist = depthAccum / max(cover, 0.02);
    float cloudAlt = depthAlt / max(cover, 0.02);

    // [v1.2.0] Aerosol has a scale height of about 1.2 km, so the optical
    // depth between the camera and a cloud is NOT sigma_surface * distance. That
    // treated the whole path to a 12 km cloud as if it ran at ground density,
    // which veiled the deck with 69 % haze; Koschmieder's visibility is a
    // GROUND-LEVEL quantity and does not apply unchanged a kilometre up.
    // Integrating the exponential profile along the straight path,
    //     tau = sigma0 * H * (exp(-y0/H) - exp(-y1/H)) / (y1 - y0) * distance,
    // gives 0.29 at the same 12 km, i.e. 25 % haze: aerial perspective stays
    // visible, but the deck keeps its edges. This is the same scale height the
    // sun transmittance above already uses (AUR_H_M), so light in and light out
    // now agree.
    float y0 = cameraPosition.y;
    float y1 = cloudAlt;
    float dyA = y1 - y0;
    float columnFactor = abs(dyA) > 1.0
        ? AUR_H_M * (exp(-y0 / AUR_H_M) - exp(-y1 / AUR_H_M)) / dyA
        : exp(-y0 / AUR_H_M);
    float aerial = 1.0 - exp(-cloudDist * airExtinction * columnFactor);
    float hazeAlt = cloudAlt;
    // [v1.2.0] The haze takes its warm light from the sun only while the sun
    // is above the haze's own horizon; below it the air is lit by the sky, which
    // the ambient term already carries. Without this the same fake horizon sun
    // tinted the final colour pink for two hours after sunset.
    vec3 hazeSun = auraliteCloudSunRadiance(
        auraliteCloudEffectiveSunSin(sunDirW.y, hazeAlt), sunsetFactor, hazeAlt)
        * auraliteCloudSunlit(sunDirW, hazeAlt);
    vec3 hazeLight = mix(lightColor, hazeSun, sunOwns);
    // Haze takes the colour of the sky IN THE DIRECTION BEING LOOKED AT: orange
    // toward the sun, blue-grey away from it.
    vec3 haze = ambient * 2.2;
    // Haze is drawn along the view ray, so it MAY depend on the direction -- you
    // are looking through different air toward the sun than away from it. The
    // amount is capped lower than before (0.20..0.60 vs 0.20..0.80) and the tint
    // helper itself is now bounded (see auraliteTintAmbient), so a low sun can
    // warm the haze without being able to turn it into a saturated red sheet.
    float hazeFacing = 0.5 + 0.5 * dot(worldDir, lightDir);
    haze = auraliteTintAmbient(haze,
        auraliteHueAtSameLuma(max(hazeSun, vec3(1e-4))),
        sunsetFactor * sunOwns * mix(0.20, 0.60, hazeFacing));
    haze += hazeLight * 0.35;
    float aerialBlend = clamp(aerial * 0.55, 0.0, 0.70);
    rgb = mix(rgb, haze, aerialBlend);

    return vec4(rgb, alpha);
}
#endif // CLOUD_MODE == 1

// ==============================================================================
// METEOROLOGICAL MULTI-HEIGHT 3D VOLUMETRIC CLOUD ENGINE (4 LAYERS)
// CLOUD_HEIGHT / CLOUD_THICKNESS now control actual geometry.
// ==============================================================================
// [v1.2.0] The per-pixel `ditherAmount` / IGN ray-start jitter of v1.1.3-v1.1.4
// is gone: every pixel now marches the same deterministic set of slices. The
// slicing that the jitter used to dissolve is controlled by CLOUD_QUALITY
// (step count), not by noise.
vec4 renderVolumetricClouds(vec3 worldDir, vec3 lightDir, vec3 lightColor, float terrainDist, float dayFactor, float sunsetFactor, float t, bool skyPixel) {
    #if CLOUD_MODE == 1
    return auraliteVolumetricClouds(worldDir, lightDir, lightColor, terrainDist, dayFactor, sunsetFactor, t, skyPixel);
    #endif
    // The legacy sheet path below never reads skyPixel: it has no high deck, so
    // there is no reach to fix there. Unused parameters are legal in GLSL.
    // ---- legacy layered-sheet path (CLOUD_MODE = 0) ----
    // Wire CLOUD_HEIGHT define into base altitude
    float cloudBaseY = 160.0;
    #if CLOUD_HEIGHT == 1
    cloudBaseY = 110.0;
    #elif CLOUD_HEIGHT == 3
    cloudBaseY = 240.0;
    #endif

    // Wire CLOUD_THICKNESS define into layer span
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

    // [v1.1.3] Ray step count now scales with the new CLOUD_QUALITY option
    // (was hardcoded 12 regardless of profile).
    int cloudSteps = 12;
    #if CLOUD_QUALITY == 1
    cloudSteps = 8;
    #elif CLOUD_QUALITY == 3
    cloudSteps = 16;
    #endif
    float stepSize = (t_end - t_start) / float(cloudSteps);

    // [v1.2.0] Deterministic ray start. v1.1.3-v1.1.4 offset t_start by an IGN
    // value in [0,1) on geometry pixels under TAA; the slices themselves are
    // already evaluated at (i + 0.5), so the offset only jittered the interval
    // boundaries — i.e. it replaced step banding with per-pixel noise, traded
    // against TAA. With TAA off by default (TAA_JITTER=0) there was nothing to
    // resolve that noise, which is why it read as grain. Removed.

    float transmission = 1.0;
    vec3 cloudLighting = vec3(0.0);

    // Camera-stable sampling.
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

    for (int i = 0; i < 16; ++i) {
        if (i >= cloudSteps) break; // [v1.1.3] CLOUD_QUALITY-scaled loop
        float slice = (float(i) + 0.5) / float(cloudSteps);
        float tDistance = t_start + (float(i) + 0.5) * stepSize;
        float sampleY = mix(yStart, yEnd, slice);
        float tHeight = (sampleY - cameraPosition.y) / safeDirY;
        float curr_t = mix(tDistance, tHeight, heightSliceWeight);
        vec3 p = ((worldDir) * (curr_t) + (cameraPosition));

        float stepDensity = 0.0;
        vec3 stepColor = vec3(0.0);

        if (p.y >= layerCirrusBottom && p.y <= layerCirrusTop) {
            float layerT3D = clamp((p.y - layerCirrusBottom) / max(layerCirrusTop - layerCirrusBottom, 0.001), 0.0, 1.0);
            vec2 uv = ((cloudCoordCirrus(cloud3DDomain(p.xz, p.y, layerT3D, vec2(0.18, -0.11), vec2(42.0, -31.0)))) * (0.0006) + (windCirrus));
            float d1 = noise(uv * 4.5 + vec2(layerT3D * 1.7, -layerT3D * 1.1));
            float d2 = noise(uv * 11.0 + vec2(-layerT3D * 3.1, layerT3D * 2.4));
            float cirrusDensity = d1 * d2;
            float layerFeather = smoothstep(layerCirrusBottom, layerCirrusBottom + cloudSpan * 0.035, p.y) *
                                 (1.0 - smoothstep(layerCirrusTop - cloudSpan * 0.045, layerCirrusTop, p.y));
            stepDensity = smoothstep(0.18, 0.48, cirrusDensity) * layerFeather * 0.12 * (1.0 - rainStrength);
            vec3 dayBase = mix(vec3(0.003, 0.005, 0.012) * 0.6, vec3(0.98), dayFactor);
            stepColor = mix(dayBase, vec3(1.0, 0.75, 0.55), sunsetFactor * 0.8);
            stepColor += vec3(1.0, 0.86, 0.66) * silverLining * stepDensity * 0.28;
        }
        else if (p.y >= layerAcBottom && p.y < layerCirrusBottom) {
            float layerT3D = clamp((p.y - layerAcBottom) / max(layerCirrusBottom - layerAcBottom, 0.001), 0.0, 1.0);
            vec2 uv = ((cloudCoordAc(cloud3DDomain(p.xz, p.y, layerT3D, vec2(-0.22, 0.17), vec2(-52.0, 37.0)))) * (0.001) + (windAc));
            float d = noise(uv * 1.8 + vec2(layerT3D * 1.3, -layerT3D * 0.9));
            float threshold = mix(0.44, 0.28, rainStrength);
            float layerFeather = smoothstep(layerAcBottom, layerAcBottom + cloudSpan * 0.035, p.y) *
                                 (1.0 - smoothstep(layerCirrusBottom - cloudSpan * 0.035, layerCirrusBottom, p.y));
            stepDensity = smoothstep(threshold, threshold + 0.2, d) * layerFeather * 0.18 * (1.0 - rainStrength * 0.35);
            vec3 dayBase = mix(vec3(0.003, 0.005, 0.012) * 0.6, vec3(0.95), dayFactor);
            stepColor = mix(dayBase, vec3(1.0, 0.62, 0.38), sunsetFactor * 0.8);
            stepColor += vec3(1.0, 0.78, 0.56) * silverLining * stepDensity * 0.22;
        }
        else if (p.y >= layerAltoBottom && p.y < layerAcBottom) {
            float layerT3D = clamp((p.y - layerAltoBottom) / max(layerAcBottom - layerAltoBottom, 0.001), 0.0, 1.0);
            vec2 uv = ((cloudCoordAlto(cloud3DDomain(p.xz, p.y, layerT3D, vec2(0.28, 0.13), vec2(58.0, 29.0)))) * (0.0014) + (windAlto));
            float d = noise(uv * 1.5 + vec2(-layerT3D * 1.1, layerT3D * 1.6));
            float threshold = mix(0.40, 0.22, rainStrength);
            float layerFeather = smoothstep(layerAltoBottom, layerAltoBottom + cloudSpan * 0.030, p.y) *
                                 (1.0 - smoothstep(layerAcBottom - cloudSpan * 0.035, layerAcBottom, p.y));
            stepDensity = smoothstep(threshold, threshold + 0.24, d) * layerFeather * 0.24;
            vec3 dayBase = mix(vec3(0.002, 0.004, 0.01) * 0.6, vec3(0.92), dayFactor);
            stepColor = mix(dayBase, vec3(1.0, 0.58, 0.3), sunsetFactor * 0.85);
            stepColor += vec3(1.0, 0.72, 0.48) * silverLining * stepDensity * 0.18;
        }
        else if (p.y >= cloudMinY && p.y < layerAltoBottom) {
            float hFactor = clamp((p.y - cloudMinY) / (layerAltoBottom - cloudMinY), 0.0, 1.0);
            vec2 uv = ((cloudCoordCumulus(cloud3DDomain(p.xz, p.y, hFactor, vec2(0.34, -0.23), vec2(72.0, -54.0)))) * (0.0018) + (windCumulus));
            uv += vec2(hFactor * 0.31, -hFactor * 0.27);
            float d = fbm(uv);
            // Flatter bottoms + softer tops look more like cumulus and cost only ALU.
            float bottomLift = smoothstep(0.02, 0.18, hFactor);
            float topFade = 1.0 - smoothstep(0.68, 1.0, hFactor);
            float heightProfile = bottomLift * topFade;
            float cloudMin = mix(0.42, 0.16, rainStrength);
            float cloudMax = mix(0.68, 0.44, rainStrength);
            float edgeSoftness = mix(0.10, 0.18, rainStrength);
            stepDensity = smoothstep(cloudMin, cloudMax + edgeSoftness * (1.0 - hFactor), d) * heightProfile * 0.38;

            vec3 lightPos = ((lightDir) * (35.0) + (p));
            float hLight = clamp((lightPos.y - cloudMinY) / max(layerAltoBottom - cloudMinY, 0.001), 0.0, 1.0);
            vec2 lightUV = ((cloudCoordCumulus(cloud3DDomain(lightPos.xz, lightPos.y, hLight, vec2(0.34, -0.23), vec2(72.0, -54.0)))) * (0.0018) + (windCumulus));
            lightUV += vec2(hLight * 0.31, -hLight * 0.27);
            float dLight = noise(lightUV);
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

    #if CLOUD_MODE == 1
    // [v1.2.0] The raymarched deck lives at a real altitude; the veil has to
    // use the same one or it would trigger hundreds of metres away from the cloud.
    cloudBaseY = auraliteCloudBaseAltitude() * (1.0 - rainStrength * 0.12);
    cloudSpan = auraliteCloudDepthMetres(auraliteCloudBaseAltitude());
    #endif

    float cloudMinY = cloudBaseY;
    float cloudMaxY = cloudBaseY + cloudSpan;
    float y = cameraPosition.y;

    // Fast early-out: no noise/fbm unless the camera is actually in the cloud slab.
    if (y < cloudMinY || y > cloudMaxY) return 0.0;

    #if CLOUD_MODE == 1
    // [v1.2.0] Same field the raymarch integrates, so flying into a cloud
    // fogs up exactly where the cloud actually is instead of where a 2D sheet was.
    return auraliteCloudDensity(cameraPosition, t, cloudMinY, cloudSpan, true, 0);
    #endif

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
        float layerT3D = clamp((y - layerAcTop) / max(layerCirrusTop - layerAcTop, 0.001), 0.0, 1.0);
        vec2 uv = ((cloudCoordCirrus(cloud3DDomain(p.xz, y, layerT3D, vec2(0.18, -0.11), vec2(42.0, -31.0)))) * (0.0006) + (windCirrus));
        float d1 = noise(uv * 4.5 + vec2(layerT3D * 1.7, -layerT3D * 1.1));
        float d2 = noise(uv * 11.0 + vec2(-layerT3D * 3.1, layerT3D * 2.4));
        float layerFeather = smoothstep(layerAcTop, layerAcTop + cloudSpan * 0.035, y) *
                             (1.0 - smoothstep(layerCirrusTop - cloudSpan * 0.045, layerCirrusTop, y));
        density = smoothstep(0.18, 0.48, d1 * d2) * layerFeather * 0.70 * (1.0 - rainStrength);
    } else if (y >= layerAltoTop && y < layerAcTop) {
        float layerT3D = clamp((y - layerAltoTop) / max(layerAcTop - layerAltoTop, 0.001), 0.0, 1.0);
        vec2 uv = ((cloudCoordAc(cloud3DDomain(p.xz, y, layerT3D, vec2(-0.22, 0.17), vec2(-52.0, 37.0)))) * (0.001) + (windAc));
        float d = fbm(uv * 1.8 + vec2(layerT3D * 1.3, -layerT3D * 0.9));
        float threshold = mix(0.44, 0.28, rainStrength);
        float layerFeather = smoothstep(layerAltoTop, layerAltoTop + cloudSpan * 0.035, y) *
                             (1.0 - smoothstep(layerAcTop - cloudSpan * 0.035, layerAcTop, y));
        density = smoothstep(threshold, threshold + 0.2, d) * layerFeather * 0.86 * (1.0 - rainStrength * 0.35);
    } else if (y >= layerCumulusTop && y < layerAltoTop) {
        float layerT3D = clamp((y - layerCumulusTop) / max(layerAltoTop - layerCumulusTop, 0.001), 0.0, 1.0);
        vec2 uv = ((cloudCoordAlto(cloud3DDomain(p.xz, y, layerT3D, vec2(0.28, 0.13), vec2(58.0, 29.0)))) * (0.0014) + (windAlto));
        float d = fbm(uv * 1.5 + vec2(-layerT3D * 1.1, layerT3D * 1.6));
        float threshold = mix(0.40, 0.22, rainStrength);
        float layerFeather = smoothstep(layerCumulusTop, layerCumulusTop + cloudSpan * 0.030, y) *
                             (1.0 - smoothstep(layerAltoTop - cloudSpan * 0.035, layerAltoTop, y));
        density = smoothstep(threshold, threshold + 0.24, d) * layerFeather * 0.96;
    } else {
        float hFactor = clamp((y - cloudMinY) / max(layerCumulusTop - cloudMinY, 0.001), 0.0, 1.0);
        vec2 uv = ((cloudCoordCumulus(cloud3DDomain(p.xz, y, hFactor, vec2(0.34, -0.23), vec2(72.0, -54.0)))) * (0.0018) + (windCumulus));
        uv += vec2(hFactor * 0.31, -hFactor * 0.27);
        float d = fbm(uv);
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

// =============================================================================
// ENHANCED SHADOW SAMPLING - Premium 32-Sample Poisson Disk PCF with adaptive LOD
// [v1.1.2] Shadows extend to render distance (far) with quality-based LOD.
// =============================================================================
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

float sampleShadow(vec3 shadowScreenPos, float distToCamera, float bias, float shadowLodRange) {
    if (shadowScreenPos.x < 0.0 || shadowScreenPos.x > 1.0 ||
        shadowScreenPos.y < 0.0 || shadowScreenPos.y > 1.0 ||
        shadowScreenPos.z < 0.0 || shadowScreenPos.z > 1.0) {
        return 1.0;
    }

    // =============================================================================
    // SHADOW LOD SYSTEM
    // Vanilla receivers use `far`. DH receivers can use a controlled extension
    // of that range, so LOD terrain just beyond vanilla chunks can receive the
    // same shared dh_shadow map instead of fading to permanently unshadowed.
    // Quality reduces (32 -> 16 -> 8 -> 4) and the filter widens with distance.
    // =============================================================================
    shadowLodRange = max(shadowLodRange, 1.0);
    float distRatio = clamp(distToCamera / shadowLodRange, 0.0, 1.0);

    // Determine LOD level: sample count and filter multiplier
    int sampleCount = 32;
    float lodFilterMult = 1.0;

    #if SHADOW_LOD == 1  // Balanced: aggressive reduction for real GPU savings
    if (distRatio > 0.25) { sampleCount = 16; lodFilterMult = 1.8; }
    // [v1.2.0] 8 taps over a 3.4-texel footprint is pure noise, and TAA is
    // disabled by default in this pack, so nothing ever integrated it away --
    // distant shadows visibly seethed and crawled. 12 taps with a slightly
    // tighter footprint reads as soft instead of dirty.
    if (distRatio > 0.5) { sampleCount = 12; lodFilterMult = 2.2; }
    #elif SHADOW_LOD == 2  // Aggressive: maximum reduction for performance
    if (distRatio > 0.15) { sampleCount = 16; lodFilterMult = 2.0; }
    if (distRatio > 0.35) { sampleCount = 8; lodFilterMult = 3.5; }
    if (distRatio > 0.6) { sampleCount = 4; lodFilterMult = 5.0; }
    #endif

    // Skip shadow sampling beyond the selected receiver range. The final fade
    // handles the transition; out-of-map projection samples remain unshadowed.
    if (distRatio > 0.95) return 1.0;

    float texelSize = 1.0 / float(shadowMapResolution);

    float spreadRadius = 1.2 * lodFilterMult;
    #if SHADOW_SOFTNESS == 1
    spreadRadius = 0.6 * lodFilterMult;
    #elif SHADOW_SOFTNESS == 3
    spreadRadius = 2.2 * lodFilterMult;
    #endif

    // =============================================================================
    // WEATHER-AWARE PHYSICAL PCSS (Percentage Closer Soft Shadows)
    // =============================================================================
    float avgBlockerDepth = 0.0;
    float blockerCount = 0.0;
    float searchRadius = 16.0 * texelSize * spreadRadius;
    int blockerSearchSamples = min(16, sampleCount);

    for (int i = 0; i < 16; ++i) {
        if (i >= blockerSearchSamples) break;
        vec2 offset = poissonDisk[i * 2] * searchRadius;
        vec2 sampleUV = shadowScreenPos.xy + offset;
        // [v1.1.2] Bounds check: skip samples outside shadow map to prevent
        // clamp-to-border artifacts (border returns 1.0 = unshadowed).
        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) continue;
        float sampleDepth = texture(shadowtex0, sampleUV).r;
        if (sampleDepth < shadowScreenPos.z - bias) {
            avgBlockerDepth += sampleDepth;
            blockerCount += 1.0;
        }
    }

    float minSpreadFactor = mix(0.15, 0.65, rainStrength * (0.6 + 0.4 * thunderStrength));

    float actualSpread = spreadRadius;
    #if SHADOW_PCSS_BLUR == 1
    // [v1.1.2] PCSS penumbra softening: naturally increases blur at distance and
    // during rain. When SHADOW_PCSS_BLUR is disabled, shadows use fixed softness.
    if (blockerCount > 0.0) {
        avgBlockerDepth /= blockerCount;
        // [v1.1.2] Clamp avgBlockerDepth to prevent NaN from near-zero values
        avgBlockerDepth = max(avgBlockerDepth, 1e-4);
        // [v1.1.2] Simplified penumbra estimation: proportional to distance
        // from blocker to receiver, with conservative clamping to prevent artifacts.
        float penumbraSize = (shadowScreenPos.z - avgBlockerDepth) / max(1e-4, avgBlockerDepth);
        // [v1.1.2] Conservative clamp: penumbraSize rarely needs to exceed 2.0
        // for visually correct soft shadows. Larger values cause light bleeding.
        penumbraSize = clamp(penumbraSize, 0.0, 2.0);
        // [v1.1.2] Reduced lightSize from 140 to 40 to prevent extreme spread
        float lightSize = 40.0;
        float minSpread = minSpreadFactor * spreadRadius;
        float maxSpread = 8.0 * spreadRadius;
        // [v1.1.2] Use spreadRadius (not texelSize) so SHADOW_SOFTNESS still
        // controls the base spread magnitude. This ensures softness setting works.
        float pcssSpread = clamp(penumbraSize * lightSize * spreadRadius, minSpread, maxSpread);
        float blockerWeight = blockerCount / float(blockerSearchSamples);
        actualSpread = mix(minSpread, pcssSpread, smoothstep(0.0, 1.0, blockerWeight));
    } else {
        actualSpread = minSpreadFactor * spreadRadius;
    }
    #else
    // Fixed softness: no distance-based or rain-based blur increase
    actualSpread = spreadRadius;
    #endif

    // [v1.1.2] Cap actualSpread to prevent sampling outside shadow map bounds
    // Keep the deterministic PCF kernel wide enough to cross texel boundaries.
    // PCSS previously collapsed to 0.09--0.33 texels in dry weather, so even
    // 32 taps could behave like one hard depth test at the shadow edge.
    // The existing tap count, LOD, weather and softness controls are preserved.
    actualSpread = clamp(actualSpread, 1.25, 16.0);

    // Adaptive PCF with LOD sample count — fewer samples at distance
    float shadow = 0.0;
    for (int i = 0; i < 32; ++i) {
        if (i >= sampleCount) break;
        vec2 offset = poissonDisk[i] * texelSize * actualSpread;
        vec2 sampleUV = shadowScreenPos.xy + offset;
        // [v1.1.2] Out-of-bounds samples count as unshadowed (1.0)
        // to maintain correct averaging without clamp-to-border artifacts.
        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) {
            shadow += 1.0;
        } else {
            float depth = texture(shadowtex0, sampleUV).r;
            shadow += step(shadowScreenPos.z - bias, depth);
        }
    }
    shadow /= float(sampleCount);

    // Gentle fade at the end of the vanilla or DH receiver range instead of a
    // hard cutoff. This prevents a visible shadow discontinuity at the seam.
    float distFade = 1.0 - smoothstep(shadowLodRange * 0.85, shadowLodRange * 0.98, distToCamera);
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

// `budget` is the maximum number of density taps. The terrain pass can afford
// twelve per pixel; the godray pass evaluates the shadow once every four steps of
// up to 24, so it passes 4 and gets the same shape at a quarter of the cost.
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
    shadowClipPos.z -= 0.040 * max(0.5 * abs(shadowProjection[2][2]), 1e-9);
    vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
    vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;

    // [v1.2.0] THE SHAFTS WERE SAMPLING A BINARY SHADOW, AND A MOVING ONE.
    // ---------------------------------------------------------------------------
    // Two things made crepuscular rays sparkle at sunset, when they are longest
    // and strongest:
    // 1. `return step(shadowScreenPos.z, blockerDepth)` is a switch, not a
    //    transmittance. Moving the camera by a fraction of a shadow texel flips a
    //    whole sample between lit and unlit, and with 8 samples along the ray that
    //    is a 12.5 % brightness step per flipped tap. Measured on a CPU model of a
    //    512 x 512 shadow map of tree crowns (crowns 8-24 texels across, 8 ray
    //    samples, camera creeping over 2 texels in 12 frames): the largest
    //    frame-to-frame jump of a shaft was 25.0 %, and 6.7 % of frames jumped by
    //    more than 5 %. After the fix below: 12.3 % and 2.2 %.
    // 2. Leaving the shadow map returned 1.0 in ONE step -- "fully lit". At sunset
    //    the light is nearly horizontal, its frustum is stretched, and a large part
    //    of every ray lies outside it. That border sweeps across the screen as the
    //    camera turns, so whole shafts switched on and off along a hard line.
    // So: four taps in a rotated cross for the spatial part, a soft compare over a
    // depth band for the axial part, and a fade to "lit" across the outer 2 % of
    // the map instead of a hard edge. Cost is 4 fetches per ray sample instead of
    // one (Godrays quality 1: 32 per pixel), which buys a stable image.
    // Real texel size: shadowMapResolution is a user setting (1024...8192), so a
    // hardcoded 1/2048 would make the blur radius wrong on every other preset.
    vec2 shSize = vec2(textureSize(shadowtex0, 0));
    vec2 shTexel = (shSize.x > 0.0 && shSize.y > 0.0) ? 1.0 / shSize : vec2(1.0 / 2048.0);
    vec2 baseUV = shadowScreenPos.xy;
    // [v1.2.0] THE SOFT-COMPARE BAND WAS 200x TOO WIDE, WHICH IS WHAT BROKE
    // THE SHAFTS.
    // ---------------------------------------------------------------------------
    // The bias above is applied in CLIP space, so in NDC it is that value DIVIDED
    // by the clip w -- i.e. by the distance to the sample. Reusing the clip-
    // space number as if it were already an NDC band was the mistake:
    //     zBand = 8 * 0.040 * 0.5 * |P22| = 0.16 NDC, with no /w
    // At 100 blocks, where the clip-space bias is worth 0.0002 NDC, that is a band
    // of about 32 METRES of depth. Every sample then landed in the middle of the
    // ramp, the compare returned ~0.5 everywhere, and the shafts turned from carved
    // beams into a uniform half-lit haze: "godrays as if broken".
    // The band has to live in the same space as the compare, so it is divided by w
    // too: 32 cm of world depth, i.e. eight times the 4 cm bias the surface lookup
    // uses, which is what silences the depth quantisation of the shadow map without
    // dissolving real occluders.
    float wAbs = max(abs(shadowClipPos.w), 1e-3);
    float biasNDC = 0.040 * max(0.5 * abs(shadowProjection[2][2]), 1e-9) / wAbs;
    float zBand = max(8.0 * biasNDC, 1e-6);
    float vis = 0.0;
    vec2 cross1 = vec2( 0.0,  1.5) * shTexel;
    vec2 cross2 = vec2( 1.5,  0.0) * shTexel;
    for (int t = 0; t < 4; ++t) {
        vec2 o = (t == 0) ? cross1 : (t == 1) ? -cross1 : (t == 2) ? cross2 : -cross2;
        vec2 uv = clamp(baseUV + o, vec2(0.0), vec2(1.0));
        float blockerDepth = texture(shadowtex0, uv).r;
        vis += clamp((blockerDepth - shadowScreenPos.z) / zBand + 0.5, 0.0, 1.0);
    }
    vis *= 0.25;

    // Distance from the edge of the shadow map in UV units; outside it there is no
    // data, so fade toward the unshadowed value instead of jumping to it.
    vec2 edge = min(baseUV, vec2(1.0) - baseUV);
    float inside = smoothstep(0.0, 0.02, min(edge.x, edge.y));
    float inDepth = smoothstep(0.0, 0.01, shadowScreenPos.z)
                  * (1.0 - smoothstep(0.99, 1.0, shadowScreenPos.z));
    return mix(1.0, vis, inside * inDepth);
    #endif
}

// ==============================================================================
// [v1.2.0] THE CLOUD SHADOW THAT GATES THE SHAFTS: SMOOTH, AND ONCE PER RAY
// ------------------------------------------------------------------------------
// Two independent defects made the shafts blink when a broken cloud passed over.
// 1. TOO FEW SAMPLES ALONG THE LIGHT RAY. computeCloudShadow() was called with
//    budget = 4, so the optical depth of the deck came from 3-4 taps spread over
//    1.4-5.8 km -- one tap per 0.5-1.9 km, against a cloud field whose smallest
//    features are 135-540 m. A single tap crossing a cloud edge changes tau by
//    sigma * density * ds = 0.0197 * 0.5 * 1400 ~ 14, i.e. the shadow snaps from
//    1.0 to "as good as none". Measured on the CPU model, walking the deck over a
//    fixed point in 10 m steps (the drift of one game second at 11 m/s): the
//    largest single-step change of the shadow was 0.98, and 4 % of all steps were
//    jumps above 0.25. That IS the flicker: an on/off switch, many times, as the
//    fragments go by.
//      12 taps at 200 m cut the largest jump to 0.47 and the fraction of >0.25
//    steps to 3.3 %, and dropping the 135-540 m erosion octave for this purpose
//    removes the finest structure that the taps cannot resolve anyway (0.58).
// 2. THE SHADOW WAS REFRESHED EVERY FOURTH SHAFT STEP. The four blocks along the
//    ray each carried the value from a different point, so a shaft was drawn in
//    four brightness plateaus that jumped independently as the camera or the
//    cloud moved. The cloud shadow is a kilometre-scale field and the godray ray
//    is at most 160 blocks long, so ONE evaluation at the middle of the ray is
//    both correct and cheaper (one density march instead of 2-6).
// Finally the term is not allowed to reach zero: haze near the ground is lit by
// the whole sky, not only by the direct beam, so a cloud dims the shafts to 22 %
// instead of switching them off. That is the difference between a soft penumbra
// and a strobe.
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

// ==============================================================================
// [v1.1.0] TRUE VOLUMETRIC GODRAYS — full single-scattering raymarch
//   L(cam) = ∫ Tr(cam→x) · σs(h) · P_HG(θ) · V_shadow(x) · V_cloud(x) · E_light dx
// What makes this "true" volumetric compared to the previous approximation:
//   • The shadow map is tested at EVERY raymarch step, so shafts are carved by
//     real geometry occlusion (trees, buildings, caves), not implied by a
//     forward-looking boost.
//   • Midpoint-rule sampling (uniform, no per-pixel dither). v1.1.4 jittered the
//     first sample with IGN; that removed step banding by adding noise to every
//     pixel of every frame, which is exactly what this fork strips out.
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

// [v1.2.0] Interleaved Gradient Noise removed. The ray march below now uses the
// plain midpoint rule — see the comment at the sample loop.

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

#ifdef AUR_CLOUD_SHADOW_VSH
// [v1.2.0] Comes from composite.vsh (see generator tools/gen_composite_vsh.py):
// the value is one per frame, so flat.
flat in float vCloudShadowFactor;
#endif

vec3 computeVolumetricGodrays(vec3 rayDirView, vec3 rayDirWorld, float maxRayDistance,
                              vec3 lightViewDir, vec3 lightWorldDir,
                              float dayFactor, float sunsetFactor) {
    // [v1.2.0] THE HARD HORIZON CUT AND THE SUN -> MOON SWAP.
    // ---------------------------------------------------------------------------
    // This used to be `if (lightWorldDir.y <= 0.01) return vec3(0.0);`, i.e. the
    // shafts switched off in one frame when the sun's elevation crossed 0.57 deg --
    // exactly the moment they are brightest and longest. A few in-game minutes
    // later Iris swaps shadowLightPosition to the moon, the direction of the light
    // jumps, and the shafts reappear pointing somewhere else. Sun, off, moon, on:
    // that is the flicker at sunset.
    // Now the strength follows the light's elevation smoothly (0 at the horizon,
    // full at 3.4 deg), and the moon side is faded IN with the sun's own depression
    // so the swap carries no step: when the light becomes the moon the sun is only
    // just below the horizon, the moon's fill is still zero, and it rises over the
    // next ~7 deg of solar depression.
    // [v1.2.0] THE GODRAY LIGHT NO LONGER READS THE SHADOW MAP'S DIRECTION.
    // ---------------------------------------------------------------------------
    // A 35-frame sequence over one sunset showed every derived
    // quantity toggling between two states: the reference ray read exactly 0.027
    // (its `lightWorldDir.y <= 0.01` cutoff firing) in one frame and 0.725 (light
    // above the horizon) in the next, while the platform held `lightPresence` and
    // the sun's elevation steady. The only input that alternates that way is
    // `shadowLightPosition`: Iris flips it between the sun and the moon and, near
    // the horizon, does so repeatedly. Everything downstream inherited the flip --
    // the cutoff, the light colour (kelvin of a negative elevation), and the cloud
    // shadow, which was marched along a direction that pointed at a different body
    // every other frame.
    // The godray physics now comes from `sunPosition` alone (the uniform that is
    // NEVER swapped), the moon being its antipode. The map's
    // own direction is still used for the shadow-map tap, because that is what the
    // map actually contains, but it can no longer change the light, its colour or
    // the sun/moon blend.
    vec3 sunDirG = auraliteSunDir(sunPosition, shadowLightPosition);
    float sunUp = sunDirG.y;
    float moonUp = -sunDirG.y;                       // the moon is the antipode of the sun
    float sunLit = smoothstep(-0.03, 0.06, sunUp);   // sun shining: 0..1
    // The moon enters as the sun sets: at the moment of substitution (sunUp ~ -0.02)
    // its contribution is still zero, full - at a depression of 7 degrees. There are no steps from here.
    float moonLit = smoothstep(-0.02, 0.04, moonUp) * smoothstep(0.0, -0.12, sunUp);
    float lightPresence = clamp(sunLit + moonLit, 0.0, 1.0);
    if (lightPresence <= 0.0005 || maxRayDistance <= 1.0) return vec3(0.0);

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
    // [v1.1.4] Use a local HG denominator with a tiny epsilon: the conservative
    // guard previously shared with cloud code capped the forward peak too low and
    // made shafts nearly invisible.
    // [v1.2.0] THE PHASE IS COUNTED ACCORDING TO WORLD DIRECTIONS.
    // -------------------------------------------------------------------------
    // There was dot(rayDirView, normalize(lightViewDir)) and lightViewDir is
    // shadowLightPosition, that is, the same vector that Iris replaces
    // between the Sun and the Moon. At sunset, the Sun and Moon are almost antipodes: substitution
    // flips the cosine almost 180 degrees, and the Mi phase in one adjacent
    // one frame is considered “forward”, and in another frame it is considered “backward”. Plus on the horizon itself
    // cosine is close to zero, so the phase reacts to any vector jitter
    // twice as strong. Measured over 10 frames: the strip of the NEW beam was jumping
    // 96 <-> 181 out of 255 with a stationary scene - this is exactly a change in direction,
    // not physics. The angle between the ray of sight and the direction towards the Sun is the value
    // in the world, and you need to take it from sunPosition, which is never swapped.
    float cosTheta = clamp(dot(normalize(rayDirWorld), sunDirG), -1.0, 1.0);
    float g = mix(0.74, 0.84, sunsetFactor); // hazier, more forward-peaked at sunset
    float g2 = g * g;
    float phaseFwd = (1.0 - g2) / (12.5663706144 * max(0.008, pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5)));
    float phaseBack = 0.0182 / max(0.008, pow(1.0334 + 0.36 * cosTheta, 1.5)); // g = -0.18 lobe
    float phase = mix(phaseFwd, phaseBack, 0.20);
    // Isotropic floor: real haze is polydisperse, so crepuscular rays stay clearly
    // visible even when looking ACROSS them, not only toward the sun.
    phase = phase * 0.92 + 0.055;

    // --- Light energy (colored!) ---
    #if SKY_MODE == 1
    vec3 sunE = physicalSunRadiance(sunDirG) * 1.35 + physicalMultiScatter(sunDirG.y) * 0.25;
    #else
    vec3 sunE = kelvinToRGB(getSolarKelvin(max(0.001, sunUp)));
    sunE = mix(sunE, vec3(1.0, 0.52, 0.24), sunsetFactor * 0.6);
    #endif
    vec3 moonE = vec3(0.38, 0.50, 0.78) * getMoonPhaseBrightness(moonPhase);
    // [v1.2.0] Blend on the ELEVATIONS, not on worldTime-derived dayFactor:
    // the two bodies are each faded by their own altitude, so a flip of the shadow
    // light cannot move the blend, and the swap carries no step.
    vec3 sunPart = sunE * sunLit;
    vec3 moonPart = moonE * 0.16 * moonLit;   // 0.16 - same night brightness as before
    vec3 lightEnergy = sunPart + moonPart;

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

    // --- Uniform midpoint raymarch with exact segment integration ---
    // [v1.2.0] No dither: sample i sits exactly in the middle of its segment,
    // which is the unbiased second-order estimate. v1.1.4 offset the whole
    // pattern by IGN(u) in [0,1) — correct on average, but visible as animated
    // grain in the shafts. If banding ever shows up here, raise GODRAY samples in
    // the profile instead of re-introducing noise.
    const float SAMPLE_CENTER = 0.5;
    float stepLen = rayLength / float(sampleCount);

    float transmittance = 1.0;
    vec3 scattered = vec3(0.0);
    // [v1.2.0] One cloud-shadow evaluation per ray (see auraliteGodrayCloudShadow).
    // [v1.2.0] Marched along the SUN (or, at night, the MOON) direction from
    // the sun uniform, never along the shadow map's flip-prone direction.
    vec3 cloudMarchDir = (sunUp > -0.02) ? sunDirG : -sunDirG;
    // [v1.2.0] ...AND THE SHADOW MAP IS ONLY TRUSTED WHILE IT BELONGS TO THE
    // SAME BODY. Iris renders shadowtex0 for whichever light is active, and that is
    // the same flip-prone quantity. When the map was drawn for the other body its
    // occluders sit in the wrong place, so the tap is faded out smoothly instead of
    // being applied on one frame and taken away on the next -- which is exactly the
    // sparkling the 35-frame sequence shows.
    float shadowAgree = smoothstep(-0.10, 0.35, dot(normalize(lightWorldDir), cloudMarchDir));
    // [v1.2.0] CLOUD SHADOW - ONE COLUMN PER FRAME, NOT FIVE PER PIXEL.
    // -------------------------------------------------------------------------
    // The shadow used to be taken at one point in the middle of the beam, then at
    // three, then at five. Measurement over 43 frames shows that accumulating points
    // does not solve the problem: the value continues to move 8-37 LSB between frames at a
    // FIXED camera, because it is not the integral estimate that changes, but the path itself
    // through the deck (the Sun passes 0.3° per second, the entry point into the deck moves away
    // at 19 m/s, the clouds are blown away by another 11 m/s).
    // Physically the shadow is a property of the deck column, not of the pixel.
    // The beam is 96-180 blocks long, and the deck hangs 1200 m above the chamber: two beams from
    // points spaced 180 blocks apart pass through the same column
    // clouds (field cell 2160 m - 12 times more than this separation). Difference between
    // they are less than 8%, while the interframe scatter from the movement of the Sun is 10-15%.
    // That is, pixel-by-pixel calculation adds not information, but noise.
    // Now the shadow is considered at ONE point, built only from uniforms
    // (cameraPosition + 4 blocks up), so all pixels in the frame receive the same
    // the same number: it cannot flicker across the screen in principle. At the same time the cost
    // drops five times: there were 5 calls of 16 densities = 80 field evaluations per
    // pixel, now 16.
    // [v1.2.0] The value itself now comes from the vertex shader: see
    // AUR_CLOUD_SHADOW_VSH above. The #else branch is the same computation done
    // per pixel; it is the verification path, and it also covers the case where the
    // vertex shader does not link (e.g. a foreign composite.vsh in the assembly).
#ifdef AUR_CLOUD_SHADOW_VSH
    float cloudShadow = vCloudShadowFactor;
#else
    vec3 cloudShadowProbe = cameraPosition + vec3(0.0, 4.0, 0.0);
    float cloudShadow = mix(0.22, 1.0,
        auraliteGodrayCloudShadow(cloudShadowProbe, cloudMarchDir, AUR_CLOUD_TIME));
#endif

    for (int i = 0; i < 24; ++i) {
        if (i >= sampleCount) break;

        float sampleDist = (float(i) + SAMPLE_CENTER) * stepLen;
        vec3 sampleViewPos = rayDirView * sampleDist;
        vec3 sampleWorldPos = cameraPosition + rayDirWorld * sampleDist;

        // Exponential aerosol falloff above sea level (Y≈64), denser in valleys.
        float heightDensity = exp(-max(sampleWorldPos.y - 64.0, 0.0) * 0.010);
        heightDensity = clamp(heightDensity * densityMult, 0.06, 1.75);

        // Denser medium + higher single-scatter albedo (0.85):
        // the previous 0.0050/0.0072 pair integrated to a nearly invisible shaft.
        float sigmaS = 0.0085 * heightDensity; // scattering
        float sigmaT = 0.0100 * heightDensity; // extinction (scatter + absorb)

        // Per-step geometric occlusion from the shadow map — the heart of the effect.
        float vis = mix(1.0, sampleVolumetricSunVisibility(sampleViewPos), shadowAgree);

        // [v1.2.0] The cloud shadow no longer changes inside the loop: it is
        // a kilometre-scale field and this ray is 96-160 blocks long.
        vis *= cloudShadow;

        // Exact analytic integral of Tr·σs over this segment (energy conserving).
        float segTr = exp(-sigmaT * stepLen);
        if (vis > 0.001) {
            scattered += lightEnergy * (transmittance * vis * phase * (sigmaS / sigmaT) * (1.0 - segTr));
        }
        transmittance *= segTr;
        if (transmittance < 0.02) break; // fully absorbed — early out
    }

    scattered *= weatherVisibility * strengthMult * lightPresence;

    // Soft shoulder keeps the sun-facing core from blowing out the HDR pipeline
    // while preserving the linear response of faint side-lit shafts.
    // Relaxed 0.55 -> 0.30 — the old shoulder crushed the bright core.
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
// The traceSSR function lives there. Corrected stale comment: no
// colortex6 hand-off exists anymore (removed in v1.0.3, see note above at the
// colortex2/colortex1 uniform declarations). final.fsh reads the surface normal
// directly from colortex2 and roughness from colortex1.z instead.

// Realistic low-valley / waterline mist density.
// Softer vertical profile than the original: dense around water level, feathered upward.
float getGroundMistDensity(float y) {
    // Layer covers rivers/plains and softly fades upward into the air.
    float lowerFade = smoothstep(60.2, 62.0, y);
    float upperFade = 1.0 - smoothstep(66.2, 70.2, y);

    // Highest density is close to cold wet ground/water; it thins with height.
    // [v1.2.0] The core used to reach 1.0 and sit from y 63 to 68.6, i.e. it
    // filled the entire playable height of a plains valley at full strength.
    float nearGroundCore = 1.0 - smoothstep(63.0, 68.2, y);
    float body = mix(0.30, 0.92, nearGroundCore);

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
    return mix(1.0, 1.35, morning);   // [v1.2.0] 1.5 -> 1.18 was too far
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

    // [v1.2.0] This veil is what "too thick inside the fog" actually was:
    // up to 88 % of the horizon replaced by fog, and it does not fall off with
    // distance because it is a screen-space wash. Halved and made to saturate
    // lower, so standing in the layer reads as haze, not as a white wall.
    // [v1.2.0] Rescaled: the ladder now brackets the v1.1.4 look instead of
    // sitting far below it. Standard (the default) is ~85 % of the old density.
    float densityScale = 0.55;
    #if GROUND_MIST_DENSITY == 2
    densityScale = 0.85;
    #elif GROUND_MIST_DENSITY == 3
    densityScale = 1.15;
    #endif

    float localDensity = camMistDensity * mistTimeFactor * pathMult * fogLevelMult * densityScale;
    float veil = 1.0 - exp(-dist * localDensity * 0.0017);
    float maxVeil = clamp(0.66 * localDensity, 0.0, 0.80);
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

    // Distant Horizons fog rescale. This exponential density was
    // tuned against the vanilla render distance (`far`, e.g. 80-256m). Distant
    // Horizons LOD terrain can extend hundreds to thousands of blocks past
    // `far`, but without this correction the SAME density keeps accumulating
    // over that whole extra distance, so fog saturates to ~90-100% opacity long
    // before DH's own draw distance — every distant LOD chunk gets buried under
    // a flat white/grey wall instead of fading in gradually. Rescale density so
    // the same relative falloff that used to fully resolve at `far` now resolves
    // at dhRenderDistance instead, giving real atmospheric-perspective depth
    // across the whole extended DH view instead of an early whiteout.
    #ifdef DISTANT_HORIZONS
    if (isOverworld && dhRenderDistance > far) {
        effectiveDensity *= clamp(far / float(dhRenderDistance), 0.05, 1.0);
    }
    #endif

    float fogFactor = 1.0 - exp(-dist * effectiveDensity);
    return clamp(fogFactor, 0.0, 0.985);
}

// [v1.2.0] Linear distance to surface based on buffer value
// depth. It is necessary that the threshold “there is a transparent surface here” be expressed
// in BLOCKS, not raw buffer units: the ground is three steps deep
// ~0.9990, and the accuracy difference there is more than 1e-5.
float aurViewZ(float d) {
    vec4 v = gbufferProjectionInverse * vec4(0.0, 0.0, d * 2.0 - 1.0, 1.0);
    return -(v.z / max(v.w, 1e-6));
}

void main() {
    float depth = texture(depthtex0, texcoord).r;
    vec4 albedoData = texture(colortex0, texcoord);

    // ==============================================================================
    // DISTANT HORIZONS DEPTH RECONCILIATION
    // ------------------------------------------------------------------------------
    // DH renders its LOD geometry into SEPARATE depth textures (dhDepthTex0/1) using
    // its own far-reaching dhProjection, while colortex0/1/2 (albedo/PBR/normal) are
    // shared attachments also written by dh_terrain.fsh/dh_water.fsh. Without this
    // block, every pixel where ONLY DH geometry exists still reads depth==1.0 from
    // the normal depthtex0 (nothing vanilla was drawn there), so the code below
    // treated all distant DH terrain as empty SKY: it skipped sun/moon lighting,
    // shadows and ground fog entirely and only composited clouds/godrays over it.
    // That is the real cause of DH chunks looking flat/washed-out/foggy rather
    // than lit like normal terrain (this is a separate, deeper issue than fog
    // density alone). We detect that case here and reconstruct the DH pixel's
    // view-space position with dhProjectionInverse so every distance-based effect
    // below (lighting, shadows, fog, PBR fade, clouds) treats it exactly like
    // regular terrain instead of sky.
    // ==============================================================================
    bool isDHTerrain = false;
    float dhDepthSample = 1.0;
    #ifdef DISTANT_HORIZONS
    dhDepthSample = texture(dhDepthTex0, texcoord).r;
    isDHTerrain = (depth >= 1.0) && (dhDepthSample < 1.0);
    #endif
    bool isSkyPixel = (depth >= 1.0) && !isDHTerrain;

    // Bulletproof Dimension Detection using Minecraft's native 'dimension' uniform (-1: Nether, 0: Overworld, 1: End)
    // with reliable biome/color fallbacks if needed.
    bool isNether = (dimension == -1) || (isNetherBiome > 0.5) || (fogColor.r > 0.18 && fogColor.g < 0.12 && fogColor.b < 0.05);
    bool isEnd = (dimension == 1) || (isEndBiome > 0.5) || (fogColor.r > 0.01 && fogColor.r < 0.08 && fogColor.g < 0.02 && fogColor.b > 0.04 && fogColor.b < 0.15);
    bool isOverworld = !isNether && !isEnd; // [v1.1.1] Do not let a default dimension=0 override Nether/End fallbacks

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

    // Compute view-space position ONCE instead of twice (was redundant)
    // DH pixels must be unprojected with dhProjectionInverse (DH's own
    // near/far planes), not gbufferProjectionInverse — using the vanilla inverse
    // projection on a depth value written by DH's projection would reconstruct a
    // wildly wrong view-space position (and therefore wrong terrainDist/worldDir),
    // since the two projections have different far planes.
    float reconstructionDepth = depth;
    #ifdef DISTANT_HORIZONS
    if (isDHTerrain) reconstructionDepth = dhDepthSample;
    #endif
    vec3 NDCPos = vec3(texcoord.xy, reconstructionDepth) * 2.0 - 1.0;
    vec3 viewPos;
    #ifdef DISTANT_HORIZONS
    viewPos = isDHTerrain ? projectAndDivide(dhProjectionInverse, NDCPos)
                          : projectAndDivide(gbufferProjectionInverse, NDCPos);
    #else
    viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
    #endif
    float terrainDist = length(viewPos);
    vec3 viewDir = normalize(viewPos);

    // Calculate world space directions. worldL is the active shadow light: Sun
    // by day, Moon at night. Physical atmosphere code must always use the REAL
    // sun direction, otherwise an elevated moon is accidentally treated as a
    // daytime sun and lights the entire world at night.
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * viewDir);
    vec3 worldL = normalize(mat3(gbufferModelViewInverse) * L);
    // [v1.2.0] Taken straight from the sunPosition uniform; see
    // auraliteSunDir(). Nothing is inferred from the flip-prone shadow light any
    // more, so the sun cannot end up on the wrong side of the sky.
    vec3 atmosphericSunDir = auraliteSunDir(sunPosition, shadowLightPosition);
    vec3 atmosphericMoonDir = -atmosphericSunDir;
    // [v1.2.0] Cheap hard guarantee: the light palette can never call it
    // "day" while the real sun is below the horizon. This only bites if worldTime
    // and the celestial angle have drifted apart; in a normal world the gate is
    // 1 whenever the tick ramp already says "day".
    dayFactor *= smoothstep(-0.26, 0.04, atmosphericSunDir.y);

    // Physical sky uses actual solar elevation, not a hard worldTime cutoff,
    // for terrain/fog/water as well.
    #if SKY_MODE == 1
    if (isOverworld) {
        float physicalDay = smoothstep(-0.150, 0.045, atmosphericSunDir.y);
        float physicalTwilight = smoothstep(-0.205, -0.015, atmosphericSunDir.y)
                               * (1.0 - smoothstep(-0.015, 0.185, atmosphericSunDir.y));
        // [v1.2.0] Twilight floor: below ~-6 deg the smoothstep above is already
        // zero, which used to make the world pitch black while the sky was still
        // glowing through nautical twilight. The floor follows the sky's own
        // phase curve, so ground and sky fade together.
        dayFactor = max(physicalDay, 0.16 * twilightGroundLight(atmosphericSunDir.y));
        sunsetFactor = max(sunsetFactor * 0.35, physicalTwilight);
        twilightFactor = sunsetFactor;
    }
    #endif

    // Setup basic variables for lighting
    vec3 currentLightColor = vec3(0.0);
    vec3 ambientColor = vec3(0.05);
    vec3 currentFogColor = vec3(0.5);
    // Analytic sky-reflection colour for water surfaces
    // (zenith/horizon gradient + sun-side glow). Filled in by the dimension
    // palette blocks below; stays zero where not applicable.
    vec3 waterSkyRefl = vec3(0.0);
    // Diffuse ambient floor used ONLY by rescued water pixels
    // (broken-MRT setups where the lightmap may read zero).
    vec3 waterAmbientFloor = vec3(0.0);
    float fogDensity = 0.0013;
    vec3 directLighting = vec3(0.0);
    float shadowFactor = 1.0;

    // Read G-buffer: normals + emissive flag from colortex2
    vec4 normalData = texture(colortex2, texcoord);
    vec3 encodedNormal = normalData.xyz * 2.0 - 1.0;
    // Sky/unused G-buffer pixels can contain zero or stale normal data; avoid
    // normalize(vec3(0)) producing undefined values before the sky branch returns.
    vec3 normal = length(encodedNormal) > 1e-4 ? normalize(encodedNormal) : vec3(0.0, 1.0, 0.0);

    // [v1.1.4] DH LOD meshes can carry averaged or winding-inverted normals.
    // A visible opaque surface must face the camera; correcting only DH pixels
    // prevents one mountain/tree side from receiving direct sun on both faces.
    // Vanilla normal maps keep their original orientation.
    if (isDHTerrain && dot(normal, -viewDir) < 0.0) {
        normal = -normal;
    }
    // ======================================================================
    // BLACK WATER REGRESSION FIX — MRT-proof water detection.
    // Composite never gave water any sky/ambient reflection: its brightness
    // came solely from albedo * (direct + ambient) plus optional SSR hits in
    // final.fsh. In sun-shadowed areas (and on profiles with SSR off) that
    // crushed frozen-biome navy tints to black.
    // User report proved a worse failure: on some Iris builds the translucent
    // pass drops the colortex1/colortex2 MRT writes ENTIRELY (the same failure
    // the v1.0.3 depth-only detector was built around). Water then arrives
    // with a zeroed/garbage normal+alpha AND a zero lightmap — it is either
    // swallowed by the emissive fast path below (alpha reads 0.0) or lit by a
    // black lightmap. Everything tag/lightmap-based dies with it.
    // The depth test cannot lie: depthtex1 (solid-only) differs from depthtex0
    // only where a translucent surface is on top. Detection ladder:
    //   a) primary: colortex2.a = 0.8 tag (written by gbuffers_water /
    //      gbuffers_terrain_translucent / dh_water; glass=1.0, ice=1.0,
    //      lava=0.1, foliage=0.62) — clean, and keeps caves honest via the
    //      real lightmap;
    //   b) RESCUE (v1.1.3): tag lost → accept depth-diff pixels, rejecting
    //      lava-orange and portal-violet albedo. Rescued pixels also escape
    //      the emissive fast path and get an ambient/skyLight floor below.
    //      Horizontal glass/ice passing this ladder is acceptable — SSR
    //      already mirrored them on healthy setups.
    // ======================================================================
    bool tagIsWater = abs(normalData.a - 0.8) < 0.05;
    float depthSolid = texture(depthtex1, texcoord).r;
    float dhDepthSolid = 1.0;
    #ifdef DISTANT_HORIZONS
    dhDepthSolid = texture(dhDepthTex1, texcoord).r;
    #endif
    vec3 normalWorld = normalize(mat3(gbufferModelViewInverse) * normal);

    // [v1.1.4] The same solid-vs-translucent depth proof works for DH's own
    // depth pair. This preserves the MRT-loss rescue path for distant water
    // instead of relying exclusively on a colortex2.a tag written by dh_water.
    // ==================================================================
    // [v1.2.0] THE TRANSLUCENT-SURFACE TEST, IN BLOCKS.
    // ==================================================================
    // The threshold used to be (depthSolid - depth) > 1e-5 on RAW
    // depth-buffer values. The depth of the ground three steps from the camera is ~0.9990,
    // so one or two steps of depth precision already exceed 1e-5. That is
    // why the check “there is a transparent surface in the pixel” passed on
    // CONTINUOUS stone and earth.
    // Next came the water rescue branch (v1.1.3): such a surface
    // received the right to be considered water if the albedo was “water-colored”
    // (b >= 0.95 r and brightness < 0.56). Gray stone, earth and gravel pass
    // this test, but LIGHT SAND does not: its texture brightness is higher than 0.56.
    // Result: the whole world received illumination of the “saved water” (it’s big - it contains
    // member of the waterAmbientFloor and a reflection of the sky), but the sand did not, and remained with
    // one ambientColor. Here's everything we saw:
    // * stains ONLY on the sand and on the sandy bottom under water;
    // * spot color is exactly equal to ambientColor (daytime blue 44/64/100,
    // at dawn warm 70/61/59 - coincides with sunsetAmbient pack);
    // * there is no spot at night (frame 18000: sand/around = 0.82), because
    // the rescue light goes out along with dayFactor;
    // * shadows and cloud shadows have nothing to do with it;
    // * albedo 1.00, skyLight 0.76, mark 1.00 - with this set dark
    // There shouldn't be a pixel.
    // Edit: the threshold is transferred to BLOCKS through the rear projection and is equal to 5 cm.
    // A solid surface gives zero at any distance, real water -
    // centimeters and more. Rescue branch remains for broken assemblies
    // with lost MRT and no longer takes over land.
    bool vanillaDepthSaysTranslucent = !isDHTerrain && depth < 0.999999 &&
        (aurViewZ(depthSolid) - aurViewZ(depth)) > 0.05;
    bool dhDepthSaysTranslucent = false;
    #ifdef DISTANT_HORIZONS
    dhDepthSaysTranslucent = isDHTerrain && dhDepthSample < 0.999999 &&
        (aurViewZ(dhDepthSolid) - aurViewZ(dhDepthSample)) > 0.05;   //  also in blocks
    #endif
    bool depthSaysTranslucent = vanillaDepthSaysTranslucent || dhDepthSaysTranslucent;

    // Hue-fingerprint classification (albedo-only, MRT-proof):
    //  - portal violet is always green-starved:  g < 0.75·r  and  b > 1.8·g
    //  - lava / fire / honey are always blue-starved: b < 0.45·r, b < 0.60·g
    //    (the old g<0.30 test only caught dark crust — bright lava escaped);
    //  - water is blue/blue-green and never pale: b ≥ 0.95·r with lum < 0.56,
    //    or vivid tropical green-blue (g > 2.2·r, b > 2.2·r).
    // Water, ice and glass legitimately classify as rescued on broken-MRT rigs,
    // but particles (torch flames, portal/end sparkles, squid ink), pale ice
    // and clear glass must NOT pick up the water lighting — and no longer do.
    bool portalAlbedoGuess = albedoData.b > albedoData.g * 1.8 &&
                             albedoData.g < 0.42 &&
                             albedoData.g < albedoData.r * 0.75;
    bool lavaAlbedoGuess = albedoData.b < albedoData.r * 0.45 &&
                           albedoData.b < albedoData.g * 0.60 &&
                           albedoData.r > albedoData.g * 0.80;
    float albedoLum = dot(albedoData.rgb, vec3(0.299, 0.587, 0.114));
    bool waterColored = (albedoData.b >= albedoData.r * 0.95 && albedoLum < 0.56) ||
                        (albedoData.g > albedoData.r * 2.2 && albedoData.b > albedoData.r * 2.2);
    bool rescuedWater = !tagIsWater && depthSaysTranslucent && waterColored &&
                        !lavaAlbedoGuess && !portalAlbedoGuess;
    bool waterLike = tagIsWater || rescuedWater;
    // If the decoded normal is untrustworthy for horizontal water (MRT loss or
    // clear value), synthesise a flat water normal in view space so the
    // reflection/Fresnel below still have sane inputs.
    vec3 waterNormalView = normalWorld.y > 0.70
                         ? normal
                         : normalize(mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0));
    // Reflection direction of the view ray about the (wave-perturbed, or
    // synthesised flat) water normal, in world space.
    vec3 waterReflWorld = normalize(mat3(gbufferModelViewInverse) *
                                    reflect(viewDir, waterNormalView));

    // Rescued water must NOT be eaten by the emissive fast path
    // (its cleared alpha reads 0.0 on broken-MRT setups). Real emissives
    // (portals) stay emissive via the portal-albedo guard above.
    // Lost-MRT safety: when the translucent G-buffer writes are
    // dropped, every surface reads alpha 0.0 and the old test would send
    // water/ice/glass into the emissive fast path (flat, unlit albedo). Require
    // the albedo to actually look self-lit (portal violet / lava orange) before
    // taking that path — everything else translucent falls through to normal
    // lighting with the daylight floor above.
    bool emissiveLikeAlbedo = portalAlbedoGuess || lavaAlbedoGuess;
    // [v1.1.4] dh_terrain uses 0.24 for DH_BLOCK_ILLUMINATED. It must bypass
    // the portal/lava hue guard: sea lanterns and modded cyan/white lamps are
    // legitimate distant emitters even though they are not blue-starved lava.
    bool isDHIlluminated = isDHTerrain && abs(normalData.a - 0.24) < 0.035;
    float isEmissive = (isDHIlluminated ||
                        (normalData.a < 0.5 && !rescuedWater && emissiveLikeAlbedo)) ? 1.0 : 0.0;
    bool isFoliage = abs(normalData.a - 0.62) < 0.01;

    // [v1.2.0] VEGETATION SHADING NORMAL
    // A grass/fern/flower quad is a vertical card, so its surface normal is
    // horizontal no matter where the sun stands. With a plain Lambert term
    // N·L ~ 0 at noon and the entire plant layer renders black in full sun --
    // exactly the "dark grass at zenith" bug. Real blades are thin, translucent
    // and packed into a sward, so the layer as a whole is lit like an
    // upward-facing canopy. Blend the SHADING normal toward the sky normal,
    // weighted by how vertical the card is. The geometric normal still drives
    // shadow bias, so contact shadows do not move.
    vec3 shadeNormal = normal;
    float foliageUpBlend = 0.0;
    #ifdef VEGETATION_CANOPY
    if (isFoliage) {
        float cardVertical = 1.0 - abs(normalWorld.y);
        // The canopy assumption only holds while the sun is ABOVE the sward. At
        // a low sun the individual vertical blades are exactly the surfaces
        // catching the light, so the blend fades out with solar elevation and
        // foliage keeps its rim light at sunrise/sunset instead of going flat.
        float canopyGain = smoothstep(-0.02, 0.40, atmosphericSunDir.y);
        foliageUpBlend = 0.88 * cardVertical * canopyGain;
        shadeNormal = normalize(mat3(gbufferModelView) *
                       normalize(mix(normalWorld, vec3(0.0, 1.0, 0.0), foliageUpBlend)));
    }
    #endif

    vec4 lmData = texture(colortex1, texcoord);
    float blockLight = lmData.r;
    float skyLight = lmData.g;

    // MRT-LOSS DAYLIGHT FLOOR — fixes black ice & striped dark water.
    // On Iris builds that drop the translucent pass's colortex1/colortex2 MRT
    // writes, the lightmap reads 0 for every translucent surface. Because the
    // entire lighting pipeline (direct sun, day ambient, halos, fog) scales by
    // skyLight, water/ice/glass then collapse to near-black — and the rescue
    // path only re-lights water, leaving ice black and water lit by a dim
    // Fresnel-modulated reflection that reads as dark diagonal stripes.
    // The depth test cannot lie: depthSaysTranslucent is true wherever a
    // translucent surface sits in front of solid geometry. Give those pixels a
    // daylight floor (scaled by dayFactor so nights stay dark and caves are
    // merely dimmer, not pitch black). When the tag works, skyLight is already
    // correct and this floor never triggers.
    if (depthSaysTranslucent && !isSkyPixel && skyLight < 0.25) {
        skyLight = max(skyLight, 0.75 * dayFactor);
    }

    // 1. Dynamic Hand/Held Light
    float heldLightVal = float(max(heldBlockLightValue, heldBlockLightValue2));
    // [v1.1.3] Strong held light sources (sea lantern, glowstone, shroomlight,
    // lava bucket) read slightly cooler than a weak candle-strength one. A true
    // per-item colour table would need heldItemId → colour mappings that differ
    // between Minecraft versions / resource packs, so for now we approximate by
    // intensity and note the upgrade path here.
    float heldCoolMix = 0.0;
    if (heldLightVal > 0.1) {
        float handGlow = max(0.0, (heldLightVal / 15.0) - terrainDist * 0.08);
        blockLight = max(blockLight, handGlow);
        heldCoolMix = clamp(handGlow, 0.0, 1.0) * smoothstep(9.0, 15.0, heldLightVal) * 0.45;
    }

    // ===============================================================================
    // [v1.1.1] Precompute Overworld light color before the emissive fast path.
    // Emissive pixels can still have volumetric clouds/godrays in front of them;
    // those clouds need a real sun/moon light color instead of the initial vec3(0).
    // The regular terrain branch recalculates the same values later for its own
    // local variables (notably extinction used by SUNRISE_GLOW).
    // ===============================================================================
    if (isOverworld) {
        float sunIntMultFast = 1.0;
        #if SUN_INTENSITY == 1
        sunIntMultFast = 0.70;
        #elif SUN_INTENSITY == 3
        sunIntMultFast = 1.35;
        #elif SUN_INTENSITY == 4
        sunIntMultFast = 1.85;
        #endif

        float moonIntMultFast = 1.0;
        #if MOON_INTENSITY == 1
        moonIntMultFast = 0.45;
        #elif MOON_INTENSITY == 3
        moonIntMultFast = 2.2;
        #elif MOON_INTENSITY == 4
        moonIntMultFast = 4.5;
        #endif

        vec3 sunContribFast = vec3(0.0);
        {
            float sinAlphaFast = max(0.001, atmosphericSunDir.y);
            float currentKFast = getSolarKelvin(sinAlphaFast);
            currentKFast = mix(currentKFast, 1850.0, sunsetFactor * 0.88);
            float airMassFast = getAirmass(sinAlphaFast);
            vec3 rayleighExtFast = vec3(0.075, 0.155, 0.375);
            vec3 extinctionFast = exp(-airMassFast * rayleighExtFast);
            extinctionFast = mix(extinctionFast, max(extinctionFast, vec3(0.36)), sunsetFactor * 0.65);
            float sunPresenceDayFast = smoothstep(-0.06, 0.08, atmosphericSunDir.y) * dayFactor;
            float sunPresenceTwilightFast = smoothstep(-0.28, 0.06, atmosphericSunDir.y) * sunsetFactor * 0.55;
            float sunPresenceFast = max(sunPresenceDayFast, sunPresenceTwilightFast);
            #if SKY_MODE == 1
            // Same LUT-derived solar transmittance used by physical sky/clouds.
            sunContribFast = physicalSunRadiance(atmosphericSunDir) * 2.6 * sunPresenceFast * sunIntMultFast;
            #else
            sunContribFast = kelvinToRGB(currentKFast) * extinctionFast * 2.6 * sunPresenceFast * sunIntMultFast;
            #endif
        }

        vec3 moonContribFast = vec3(0.0);
        {
            float moonElevFast = -atmosphericSunDir.y;
            float moonPresenceFast = smoothstep(-0.06, 0.08, moonElevFast)
                                   * (1.0 - smoothstep(-0.02, 0.22, atmosphericSunDir.y));
            float moonBrightnessFast = getMoonPhaseBrightness(moonPhase);
            moonContribFast = auraliteMoonLightColor() * 0.028 * moonBrightnessFast * moonPresenceFast * moonIntMultFast;
        }

        currentLightColor = sunContribFast + moonContribFast;
        float weatherDimFactorFast = mix(1.0, 0.55, rainStrength);
        weatherDimFactorFast = mix(weatherDimFactorFast, 0.15, rainStrength * thunderStrength);
        currentLightColor *= weatherDimFactorFast;
    }

    // ==============================================================================
    // EMISSIVE FAST PATH — Portals and other self-lit surfaces skip scene lighting
    // Prevents composite from re-lighting emissive surfaces
    // ==============================================================================
    // Sky pixels do not write colortex2, so alpha may contain stale data there.
    // Only treat a pixel as emissive if it is real geometry (not sky).
    // Use !isSkyPixel instead of depth < 1.0: for DH-only pixels the
    // vanilla depth stays at 1.0 even though dh_terrain.fsh wrote real emissive
    // geometry (e.g. distant glowstone/illuminated blocks) into colortex0-2.
    if (!isSkyPixel && isEmissive > 0.5) {
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
            float fogFactor = 0.0; // No fog in the End
            finalColor = mix(finalColor, vec3(0.02, 0.01, 0.05), clamp(fogFactor, 0.0, 0.985));
        }

        // Blend volumetric clouds in front of emissive surfaces
        #ifdef PROCEDURAL_CLOUDS
        if (isOverworld) {
            float cloudTime = AUR_CLOUD_TIME;
            vec4 volClouds = renderVolumetricClouds(worldDir, worldL, currentLightColor, terrainDist, dayFactor, sunsetFactor, cloudTime, false);
            finalColor = mix(finalColor, volClouds.rgb, volClouds.a);
            finalColor = applyInsideCloudVeil(finalColor, terrainDist, worldDir, dayFactor, sunsetFactor, fogColor, cloudTime);
        }
        #endif

        #ifdef GODRAYS
        if (isOverworld) {
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
            float sinAlpha = max(0.001, atmosphericSunDir.y);
            float currentK = getSolarKelvin(sinAlpha);
            // Force deep warm Kelvin during sunset/sunrise twilight. This keeps /time set 12800 red.
            currentK = mix(currentK, 1850.0, sunsetFactor * 0.88);
            float airMass = getAirmass(sinAlpha);
            vec3 RayleighExtinction = vec3(0.075, 0.155, 0.375);
            extinction = exp(-airMass * RayleighExtinction);
            extinction = mix(extinction, max(extinction, vec3(0.36)), sunsetFactor * 0.65);
            float sunPresenceDay = smoothstep(-0.06, 0.08, atmosphericSunDir.y) * dayFactor;
            float sunPresenceTwilight = smoothstep(-0.28, 0.06, atmosphericSunDir.y) * sunsetFactor * 0.55;
            float sunPresence = max(sunPresenceDay, sunPresenceTwilight);
            #if SKY_MODE == 1
            sunContrib = physicalSunRadiance(atmosphericSunDir) * 2.6 * sunPresence * sunIntMult;
            // Keep extinction coherent for sunrise glow and Rayleigh-tinted
            // ambient even though direct colour now comes from the LUT fit.
            extinction = physicalSunTransmittance(atmosphericSunDir.y);
            #else
            sunContrib = kelvinToRGB(currentK) * extinction * 2.6 * sunPresence * sunIntMult;
            #endif
        }

        // --- Moon contribution ---
        vec3 moonContrib = vec3(0.0);
        {
            // [v1.2.0] Was `-worldL.y` (i.e. "the other body") gated by a
            // hard 13000..23200 tick window. The moon lights the world only
            // while it is above the horizon AND the sun is down, which is a
            // statement about elevations, not about ticks.
            float moonPresence = smoothstep(-0.06, 0.08, atmosphericMoonDir.y)
                               * (1.0 - smoothstep(-0.02, 0.22, atmosphericSunDir.y));
            float moonBrightness = getMoonPhaseBrightness(moonPhase);
            vec3 moonBaseColor = auraliteMoonLightColor();
            moonContrib = moonBaseColor * 0.028 * moonBrightness * moonPresence * moonIntMult;
        }

        currentLightColor = sunContrib + moonContrib;

        // Weather dimming
        float weatherDimFactor = mix(1.0, 0.55, rainStrength);
        weatherDimFactor = mix(weatherDimFactor, 0.15, rainStrength * thunderStrength);
        currentLightColor *= weatherDimFactor;

        float rawNdotL = dot(normal, L);   // geometric normal: shadow bias only
        float shadeNdotL = dot(shadeNormal, L);
        #if LIGHT_WRAP == 1
        float NdotL = max(0.0, shadeNdotL);
        #elif LIGHT_WRAP == 2
        float NdotL = pow(max(0.0, shadeNdotL * 0.5 + 0.5), 1.6);
        #else
        float NdotL = pow(max(0.0, shadeNdotL * 0.5 + 0.5), 1.2);
        #endif
        float shadow = 1.0;
        #ifdef SHADOWS
        vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
        vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
        vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
        shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
        // [v1.1.1] Shadow Acne cleanup.
        // Biasing the general term alone still left acne on water/ice at
        // low sun. Increase the general bias slightly and add an extra receiver
        // bias only for tagged water pixels (colortex2.a ~= 0.8). This keeps
        // regular terrain contact shadows tight while cleaning noisy water.
        // [v1.1.4] DH can render/cast beyond vanilla `far`, but previous code
        // used `far` for both LOD thresholds and fade, making every DH receiver
        // immediately unshadowed. Extend only the receiver range; projection
        // bounds still safely reject locations absent from the shadow map.
        float shadowLodRange = far;
        #ifdef DISTANT_HORIZONS
        if (isDHTerrain) {
            float rangeMultiplier = 2.0;
            #if DH_SHADOW_RANGE == 1
            rangeMultiplier = 1.25; // Seam: inexpensive short continuation
            #elif DH_SHADOW_RANGE == 3
            rangeMultiplier = 4.0;  // Far: maximum useful DH receiver range
            #endif
            float desiredDHRange = max(far, shadowDistance) * rangeMultiplier;
            shadowLodRange = min(max(float(dhRenderDistance), far), desiredDHRange);
        }
        #endif

        // ------------------------------------------------------------------
        // [v1.2.0] SHADOW BIAS IN METRES, NOT IN "SHADER UNITS"
        // The biases used to be bare numbers (0.00020 / 0.00062 / 0.00010) fed
        // straight into a depth-buffer comparison. A depth-buffer value is not a
        // length: it is 0..1 spread over the WHOLE shadow frustum, so the same
        // constant means a bigger real offset as shadowDistance grows. At the
        // pack's 512 m setting one screen-z unit spans ~1024 m, which turned the
        // nominal 0.00020 into ~0.4 m and the grazing-angle term into ~1.3 m of
        // depth offset. Anything thinner than that simply cannot shadow: grass
        // cards, fences, leaves, mob feet -- their contact shadows were being
        // pushed off the receiver and vanished. That is the "shadows don't work"
        // report, and it is invisible in the constants because they look small.
        // Fixed by converting every term from metres into this frame's depth
        // units using the shadow projection's own depth derivative, so the bias
        // is physically constant whatever shadowDistance is set to.
        // ------------------------------------------------------------------
        float worldToShadowDepth = 0.5 * abs(shadowProjection[2][2]); // screen-z per metre
        worldToShadowDepth = max(worldToShadowDepth, 1e-9);

        // One shadow-map texel in metres: the ortho frustum is 2*shadowDistance wide.
        float shadowTexelWorld = 2.0 * shadowDistance / float(shadowMapResolution);

        // 4 cm constant lift -- enough to beat depth quantisation, small enough
        // to leave grass and fence contact shadows attached.
        float baseBias = 0.040 * worldToShadowDepth;

        // Grazing surfaces span up to one texel of depth per texel of screen, so
        // the slope term is expressed in texels rather than as a magic number.
        float slopeTerm = 1.0 - clamp(rawNdotL, 0.0, 1.0);
        float slopeBias = 0.90 * shadowTexelWorld * slopeTerm * slopeTerm * worldToShadowDepth;

        // Distant receivers are sampled with fewer taps and coarser depth.
        float distBias = 0.60 * shadowTexelWorld
                       * smoothstep(0.5, 1.0, terrainDist / shadowLodRange)
                       * worldToShadowDepth;

        // [v1.1.4] Water is a very flat, high-contrast receiver: even a small
        // depth mismatch reads as obvious crawling acne across the surface. The
        // old 0.00018 tag bias was insufficient at noon and on DH LOD water.
        // Keep terrain contact shadows tight, but give water a dedicated floor
        // plus a small ripple/slope term. DH gets a larger floor because its
        // coarse LOD depth amplifies quantisation error.
        float waterReceiverBias = 0.0;
        // Extra bias when the depth pair shows a transparent layer. This does not
        // prove that the receiver is water: the condition also covers glass and the
        // opaque surface behind it, and it can lift real shadows, so it stays narrow.
        bool translucentReceiver = waterLike || depthSaysTranslucent;
        if (translucentReceiver) {
            // Same metre-based derivation; water was previously tagged with
            // 0.00065 (=1.3 m!) which is more than enough to erase every
            // reflection-side contact shadow.
            // The threshold is in the menu and is deliberately above the old
            // 13 cm: waves shift the surface by centimetres, and the depth step of the
            // shadow map is decimetres on blocks 128...512.
            waterReceiverBias = (isDHTerrain ? max(AUR_WATER_GUARD, 0.220) : AUR_WATER_GUARD) * worldToShadowDepth;
            waterReceiverBias += 0.060 * (1.0 - clamp(normalWorld.y, 0.0, 1.0)) * worldToShadowDepth;
        }
        float bias = baseBias + slopeBias + distBias + waterReceiverBias;
        
        vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
        vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;
        shadow = sampleShadow(shadowScreenPos, terrainDist, bias, shadowLodRange);
        // Reception is suppressed only for water pixels: shadows from blocks on the
        // sand remain. The wrap light model also needs care at a grazing/back-facing
        // surface, where the shadow map becomes unstable: do not apply its comparison
        // at N.L <= 0; blend back to the original visibility for N.L >= 0.15.
        // This can reduce real cast shadows at grazing incidence. Lambert is
        // unchanged, and no random noise is introduced.
        #if LIGHT_WRAP != 1
        shadow = mix(1.0, shadow, smoothstep(0.0, 0.15, rawNdotL));
        #endif
        #endif

        // Shadow lift
        float shadowFloor = 0.25;
        #if AMBIENT_BRIGHTNESS == 1
        shadowFloor = 0.10;
        #elif AMBIENT_BRIGHTNESS == 3
        shadowFloor = 0.45;
        #endif
        // [v1.2.0] THIN-BLADE TRANSLUCENCY
        // A shadow-map hit on a plant is usually the plant shadowing ITSELF:
        // sunlight passes between and through the blades, it is not blocked by
        // stone. Lifting only the vegetation floor keeps cast shadows from trees
        // and walls visible while stopping grass from going pitch black.
        float foliageFloor = shadowFloor;
        #ifdef VEGETATION_CANOPY
        if (isFoliage && !isDHTerrain) foliageFloor = mix(shadowFloor, 1.0, 0.35);
        #endif
        shadowFactor = mix(mix(foliageFloor, 1.0, shadow), shadow, dayFactor);
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
        // DH_BLOCK_LEAVES represents a coarse mixed canopy (and may include
        // bamboo/cactus). Applying a two-sided SSS wrap to that LOD proxy makes
        // both sun-facing and opposite sides read as directly sunlit. Keep SSS
        // for detailed vanilla foliage, but let DH use one-sided diffuse light.
        if (isFoliage && !isDHTerrain) {
            float sssShadow = smoothstep(0.0, 0.45, shadow);
            float vDotL = max(0.0, dot(viewDir, L));
            float sssBleed = pow(vDotL, 4.0) * 0.82;
            float wrap = pow(max(0.0, dot(normal, -L) * 0.5 + 0.5), 2.0) * 0.16;
            vec3 sssColor = currentLightColor * (sssBleed + wrap) * skyLight * sssShadow;
            directLighting += sssColor;
        }
        #endif

        // Sun Halo
        #ifdef SUN_HALO
        if (dayFactor > 0.01) {
            vec3 viewDirWorld = normalize(mat3(gbufferModelViewInverse) * normalize(viewPos));
            float forwardDot = max(0.0, dot(viewDirWorld, atmosphericSunDir));
            float mie = pow(forwardDot, 8.0);
            float haloIntensity = mie * skyLight * shadowFactor * dayFactor * (1.0 - rainStrength) * 0.45;
            vec3 sunBaseColor = kelvinToRGB(getSolarKelvin(max(0.001, atmosphericSunDir.y)));
            vec3 haloColor = sunBaseColor * extinction * haloIntensity * 1.8;
            directLighting += haloColor;
        }
        #endif

        // Procedural transparent cloud shadows. Only direct sunlight is dimmed;
        // ambient/torch light remains readable, so the result stays realistic and playable.
        #ifdef CLOUD_SHADOWS
        if (!isSkyPixel && skyLight > 0.03 && dayFactor > 0.02) {
            vec3 worldPosForCloudShadow = cameraPosition + worldDir * terrainDist;
            float cloudShadow = computeCloudShadow(worldPosForCloudShadow, atmosphericSunDir, dayFactor, AUR_CLOUD_TIME, 12);
            directLighting *= mix(1.0, cloudShadow, skyLight);
        }
        #endif

        // Hemisphere ambient
        float normalUp = normal.y * 0.5 + 0.5;
        #ifdef VEGETATION_CANOPY
        // The sward sees more sky than a single vertical card does.
        normalUp = mix(normalUp, 1.0, foliageUpBlend * 0.75);
        #endif

        vec3 nightSkyAmbient = vec3(0.006, 0.008, 0.018);
        vec3 nightGroundAmbient = vec3(0.003, 0.003, 0.005);
        vec3 nightAmbient = mix(nightGroundAmbient, nightSkyAmbient, normalUp) * (0.4 + skyLight * 0.6);

        vec3 daySkyAmbient = vec3(0.32, 0.42, 0.58);
        vec3 dayGroundAmbient = vec3(0.18, 0.14, 0.08);
        vec3 dayAmbient = mix(dayGroundAmbient, daySkyAmbient, normalUp) * skyLight * 0.75;
        // [v1.1.3] Tint the day hemisphere ambient by the actual Rayleigh
        // extinction computed for the sun: at sunset the scattered skylight is
        // warm and blue-depleted instead of the previous static grey-blue —
        // makes golden-hour ambience physically coherent for free.
        dayAmbient *= mix(vec3(1.0), 0.55 + 0.90 * extinction, 0.45);
        #if SKY_MODE == 1
        // Low-frequency multi-scatter and biome ground bounce join the same
        // physical sky energy used by fog/reflections without a second ray march.
        dayAmbient += physicalMultiScatter(atmosphericSunDir.y) * mix(0.18, 0.55, normalUp);
        dayAmbient += physicalGroundBounceAlbedo() * (0.06 + 0.10 * normalUp) * dayFactor;
        #endif

        ambientColor = mix(nightAmbient, dayAmbient, dayFactor);

        vec3 sunsetAmbient = vec3(0.22, 0.12, 0.06) * skyLight * 0.6;
        ambientColor = mix(ambientColor, sunsetAmbient, twilightFactor * 0.5);

        float ambientDimFactor = mix(1.0, 0.65, rainStrength);
        ambientDimFactor = mix(ambientDimFactor, 0.15, rainStrength * thunderStrength);
        ambientColor *= ambientDimFactor;

        // [v1.1.4] Coarse DH vertex colour already carries broad baked sky
        // brightness. Without a small opposite-side reduction it can look as if
        // the sun illuminates both faces of a distant hill. This affects only
        // daylight LOD geometry; vanilla terrain retains its full sky bounce.
        #ifdef DISTANT_HORIZONS
        if (isDHTerrain) {
            float dhSunFacing = smoothstep(-0.08, 0.22, rawNdotL);
            ambientColor *= mix(1.0, mix(0.58, 1.0, dhSunFacing), dayFactor);
        }
        #endif

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

        #if SKY_MODE == 1
        // Terrain aerial perspective converges toward the same directional
        // atmosphere used by gbuffers_skybasic instead of a separate blue fog.
        vec3 physicalFog = physicalSkyRadianceApprox(worldDir, atmosphericSunDir, dayFactor);
        currentFogColor = mix(currentFogColor, physicalFog, 0.86);
        #endif

        float baseDensity = 0.0013;
        #if FOG_DENSITY_LEVEL == 1
        baseDensity = 0.0008;
        #elif FOG_DENSITY_LEVEL == 3
        baseDensity = 0.0025;
        #endif
        fogDensity = mix(baseDensity, baseDensity * 5.0, rainStrength);

        // Water analytic sky-reflection gradient. Horizon uses
        // the fully-mixed fog colour (day/sunset/storm/biome aware); zenith
        // mirrors the SSR sky-fallback palette in final.fsh so SSR and
        // non-SSR water stay visually consistent. A modest warm glow on the
        // sun side keeps the reflection alive at sunset. Independent of the
        // shadow map on purpose — this is ambient specular: the reflected sky
        // is still visible from sun-shadowed water (black-channel fix).
        {
            #if SKY_MODE == 1
            // Reflection uses the shared physical directional fit, not the
            // legacy gradient fallback, so water and horizon agree in SKY_MODE=1.
            waterSkyRefl = physicalSkyRadianceApprox(waterReflWorld, atmosphericSunDir, dayFactor);
            #else
            float wUp = clamp(waterReflWorld.y, 0.0, 1.0);
            vec3 wZenith = mix(vec3(0.006, 0.008, 0.012), vec3(0.10, 0.26, 0.58), dayFactor);
            wZenith = mix(wZenith, currentFogColor * 0.55, rainStrength);
            vec3 wSky = mix(currentFogColor, wZenith, pow(wUp, 0.6));
            float wSun = pow(clamp(dot(waterReflWorld, atmosphericSunDir), 0.0, 1.0), 8.0);
            wSky += vec3(1.0, 0.55, 0.25) * wSun * (0.35 + 0.65 * twilightFactor) * dayFactor;
            waterSkyRefl = wSky;
            #endif
        }

        // Diffuse ambient floor for rescued (broken-MRT) water:
        // day hemisphere ambient mirrored from the palette above, night floor,
        // dimmed by storms — brightened vs v1.1.3 so the wave-Fresnel banding
        // of the sky reflection can no longer read as black stripes.
        waterAmbientFloor = mix(vec3(0.0025, 0.0030, 0.0045), vec3(0.42, 0.55, 0.70), dayFactor);
        waterAmbientFloor *= mix(1.0, 0.60, rainStrength);

    } else if (isNether) {
        // --- THE NETHER ---
        directLighting = vec3(0.0);
        float pulse = sin(frameTimeCounter * 0.5) * 0.12 + 0.88;
        // Nether biomes colored fog and ambient lighting:
        // Reads and scales the native biome fogColor from Minecraft (Soul Sand Valley, Warped/Crimson forest, etc.)
        // to dynamically shift atmosphere, rather than hardcoding warm red everywhere.
        currentFogColor = clamp(fogColor * 1.5, vec3(0.01), vec3(1.0));
        ambientColor = clamp((fogColor * 1.45 + vec3(0.04)) * pulse * 1.22, vec3(0.01), vec3(0.8));
        fogDensity = 0.0038;
        waterSkyRefl = currentFogColor * 1.2; // modded nether water gets a dim biome sheen
        waterAmbientFloor = ambientColor * 0.8; // rescued-water diffuse floor

    } else if (isEnd) {
        // --- THE END ---
        directLighting = vec3(0.0);
        ambientColor = vec3(0.14, 0.1, 0.22);
        currentFogColor = vec3(0.02, 0.01, 0.05);
        fogDensity = 0.0000; // Completely remove End fog for clear obsidian towers & sky visibility.
        waterSkyRefl = currentFogColor * 1.5; // dim violet sheen for End water
        waterAmbientFloor = vec3(0.10, 0.075, 0.17); // rescued-water diffuse floor
    }

    // ==============================================================================
    // SKY PASS
    // ==============================================================================
    // Use isSkyPixel instead of raw depth >= 1.0: DH-only pixels also
    // read depth == 1.0 from the vanilla depth buffer, but they are real distant
    // terrain (dh_terrain.fsh/dh_water.fsh already wrote albedo/normal/PBR data
    // for them) and must fall through to the TERRAIN LIGHTING path below instead
    // of being treated as empty sky with no sun/moon lighting or shadows.
    if (isSkyPixel) {
        vec3 finalColor = albedoData.rgb;
        #ifdef PROCEDURAL_CLOUDS
        if (isOverworld) {
            float cloudTime = AUR_CLOUD_TIME;
            vec4 volClouds = renderVolumetricClouds(worldDir, worldL, currentLightColor, getCloudRenderDistance(), dayFactor, sunsetFactor, cloudTime, true);
            // Direct additive components before haze, godrays and postprocessing.
            // Radiance views 2-4 share the same 1/4 linear display scale.
            finalColor = mix(finalColor, volClouds.rgb, volClouds.a);
        }
        #endif

        // If the camera is inside the low morning/evening mist layer, veil the horizon sky too.
        #ifdef GROUND_MIST
        if (isOverworld) {
            float camMistDensity = getGroundMistDensity(cameraPosition.y);
            float camMistTime = getGroundMistTimeFactor(time) * getGroundMistMorningBoost(time);
            float humidityFactor = clamp(0.60 + wetness * 0.26 + rainStrength * 0.08, 0.50, 1.02);   // [v1.2.0]
            camMistTime *= humidityFactor;
            float skyMistVeil = getInsideGroundMistVeil(420.0, worldDir, camMistDensity, camMistTime);
            vec3 skyMistColor = mix(vec3(0.50, 0.55, 0.62), vec3(0.75, 0.78, 0.80), dayFactor);
            skyMistColor = mix(skyMistColor, fogColor, 0.24);
            finalColor = mix(finalColor, skyMistColor, skyMistVeil);
        }
        #endif

        #ifdef PROCEDURAL_CLOUDS
        if (isOverworld) {
            float cloudTime = AUR_CLOUD_TIME;
            finalColor = applyInsideCloudVeil(finalColor, 900.0, worldDir, dayFactor, sunsetFactor, fogColor, cloudTime);
        }
        #endif

        #ifdef GODRAYS
        if (isOverworld) {
            // [v1.2.0] RAYS SHOULD NOT PARTICIPATE IN THE DEPTH TEST.
            // ------------------------------------------------------------------
            // This pass draws the sky, but the depth in the buffer does not yet contain the sky.
            // The rays go across the screen like ordinary triangles, and where the ray lies
            // almost in the plane of the screen (and at sunset it is almost horizontal), it
            // pixels fall within ±1 LSB of the depth test. Hence the even HORIZONTAL
            // lines: white - where the fragment won the test and the beam was drawn twice,
            // black - where he lost and didn’t show up at all. It's not noise or clouds,
            // This is z-fighting, and it is treated by moving the polygon.
            gl_FragDepth = 1.0;   // the sky belongs to the farthest plane
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
    // [v1.1.3] Cooler tint where a strong held light dominates the block light.
    torchColor = mix(torchColor, kelvinToRGB(3100.0) * 2.3, heldCoolMix);
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
        // In the Nether/End there is no direct sun/moon light vector,
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
            // [v1.2.0] The same moonlight colour as the diffuse term.

            float moonSpecIntMult = 1.0;
            #if MOON_INTENSITY == 1
            moonSpecIntMult = 0.5;
            #elif MOON_INTENSITY == 3
            moonSpecIntMult = 2.0;
            #elif MOON_INTENSITY == 4
            moonSpecIntMult = 3.5;
            #endif
            specLightColor = auraliteMoonLightColor() * 0.45 * moonBr * pbrStrengthMult * moonSpecIntMult;
        }

        // Added missing NdotL_pbr cosine factor for correct Cook-Torrance BRDF.
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

    // Analytic sky reflection for water — the actual black-water
    // fix. Ambient specular: works with SSR disabled (VERY_LOW/LOW profiles),
    // in sun shadow, and under twilight. The Schlick Fresnel keeps a 0.28
    // floor because pure F0≈0.02 at steep look-down angles was exactly what
    // let shadowed water crush to black since v1.0.7. Multiplied by skyLight
    // so cave water stays naturally dark. Fog below still attenuates it.
    // Rescued (broken-MRT) pixels additionally get an effective
    // skyLight floor (their lightmap may read 0) plus a diffuse ambient floor,
    // since both colortex1 and colortex2 are untrustworthy on those setups.
    // Floor raised 0.20 -> 0.28 so the wave-modulated Fresnel
    // banding keeps a visible sky reflection everywhere (no black stripes on
    // ice-adjacent water when the MRT lightmap is lost).
    if (waterLike && isEyeInWater != 1) {
        float wNoV = clamp(dot(waterNormalView, -viewDir), 0.0, 1.0);
        float wFres = 0.02 + 0.98 * pow(1.0 - wNoV, 5.0);
        float wSkyFactor = tagIsWater ? skyLight : max(skyLight, 0.75);
        // [TUNE v1.1.3] User feedback: the sun-side sky mirror read ~25% too
        // hot at grazing angles — global amplitude trim of THIS ambient term
        // only. Diffuse ambient floor and SSR hits in final.fsh are untouched.
        shadedTerrain += waterSkyRefl * max(wFres, 0.28) * wSkyFactor * 0.75;
        if (!tagIsWater) shadedTerrain += albedo * waterAmbientFloor * wSkyFactor;
    }

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
        vec3 underwaterWorldPos = feetPlayerPos + cameraPosition; // [v1.1.1] world-stable caustic UVs

        // --- 1. UNDERWATER CAUSTICS (enhanced dual-layer) ---
        // Two overlapping caustic layers at different scales/speeds create a natural
        // dancing light pattern on submerged surfaces.
        vec2 causticUV1 = underwaterWorldPos.xz * 0.30 + vec2(frameTimeCounter * 0.42, frameTimeCounter * 0.22);
        vec2 causticUV2 = underwaterWorldPos.xz * 0.18 - vec2(frameTimeCounter * 0.28, -frameTimeCounter * 0.35);
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
        // [v1.1.3] Biome-aware absorption: swamp/mangrove water is greener and
        // murkier (absorbs more blue, less green) than open-ocean water.
        vec3 absorptionCoeffs = mix(vec3(0.18, 0.045, 0.015), vec3(0.23, 0.038, 0.10), isSwampBiome);
        vec3 waterAbsorption = exp(-terrainDist * absorptionCoeffs);
        finalColor = finalColor * waterAbsorption;

        // --- 4. VOLUMETRIC SCATTERING FOG ---
        // In-scattered ambient light replaces absorbed wavelengths, tinting distant
        // objects toward deep blue/teal. Stronger deeper and farther.
        float depthBelowSurface = max(62.0 - cameraPosition.y, 0.0);
        float depthFogDensity = 0.032 + depthBelowSurface * 0.0025;
        float uwFogFactor = 1.0 - exp(-terrainDist * depthFogDensity);
        vec3 deepWaterColor = mix(vec3(0.02, 0.12, 0.32), vec3(0.008, 0.04, 0.12), smoothstep(0.0, 30.0, depthBelowSurface));
        deepWaterColor = mix(deepWaterColor, vec3(0.04, 0.10, 0.05), isSwampBiome * 0.7); // [v1.1.3] swamp tint
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
    // Now guarded by #ifdef GROUND_MIST so the toggle works
    #ifdef GROUND_MIST
    if (isOverworld) {
        float mistTimeFactor = getGroundMistTimeFactor(time);

        // Morning fog is naturally stronger around dawn due to overnight cooling.
        // Evening and night remain unchanged.
        mistTimeFactor *= getGroundMistMorningBoost(time);

        // Wet ground/water keeps fog alive longer after rain; active rain blends it into haze.
        float humidityFactor = clamp(0.60 + wetness * 0.26 + rainStrength * 0.08, 0.50, 1.02);   // [v1.2.0]
        mistTimeFactor *= humidityFactor;

        float worldY = cameraPosition.y + worldDir.y * terrainDist;
        // Fade out distant 2D sheets when standing inside the mist layer
        float camMistHere = getGroundMistDensity(cameraPosition.y);
        float mistDensityFactor = getGroundMistDensity(worldY) * (1.0 - camMistHere * 0.95);

        if (mistTimeFactor > 0.01 && mistDensityFactor > 0.01) {
            vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
            vec3 mistWorldPos = feetPlayerPos + cameraPosition; // [v1.1.1] world-stable mist sheets

            // Large slow sheets + small breakup. Much slower motion than clouds/waves,
            // because real valley/radiation fog creeps rather than visibly flows.
            vec2 drift = vec2(frameTimeCounter * 0.010, frameTimeCounter * 0.0035);
            vec2 largeUV = mistWorldPos.xz * 0.026 + drift;
            vec2 smallUV = mistWorldPos.xz * 0.074 - drift * 1.7;
            float largeSheet = fbm(largeUV);
            float smallBreakup = noise(smallUV);
            float sheetMask = smoothstep(0.18, 0.82, largeSheet * 0.78 + smallBreakup * 0.22);
            float mistNoise = mix(0.44, 0.88, sheetMask);   // [v1.2.0]

            float fogLevelMult = 1.0;
            #if FOG_DENSITY_LEVEL == 1
            fogLevelMult = 0.55;
            #elif FOG_DENSITY_LEVEL == 3
            fogLevelMult = 1.65;
            #endif

            // Optical accumulation through the layer. No hard 120m cutoff anymore:
            // the mist accumulates with distance, then fades very gently to avoid a flat wall.
            float distanceAccum = 1.0 - exp(-terrainDist * 0.0032 * fogLevelMult);   // [v1.2.0]
            float farBlend = 1.0 - smoothstep(260.0, 520.0, terrainDist);
            float outdoorFactor = mix(0.36, 0.82, skyLight);

            // [v1.2.0] The cap used to be 0.75 -- three quarters of the frame
            // replaced by fog with the horizon gone entirely.
            float mistDensityScale = 0.55;
            #if GROUND_MIST_DENSITY == 2
            mistDensityScale = 0.85;
            #elif GROUND_MIST_DENSITY == 3
            mistDensityScale = 1.15;
            #endif
            float rawOpacity = mistDensityFactor * mistNoise * mistTimeFactor * distanceAccum * farBlend * outdoorFactor * fogLevelMult;
            float maxOpacity = clamp(0.46 * mistDensityFactor * mistTimeFactor * fogLevelMult * mistDensityScale, 0.0, 0.70);
            float mistOpacity = clamp(rawOpacity * 0.44 * mistDensityScale, 0.0, maxOpacity);

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
        float humidityFactor = clamp(0.60 + wetness * 0.26 + rainStrength * 0.08, 0.50, 1.02);   // [v1.2.0]
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
        float cloudTime = AUR_CLOUD_TIME;
        vec4 volClouds = renderVolumetricClouds(worldDir, worldL, currentLightColor, terrainDist, dayFactor, sunsetFactor, cloudTime, false);
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

    // final.fsh reads normals from colortex2 and roughness from colortex1
    // directly — the same buffers the PBR specular pass already uses.
}
